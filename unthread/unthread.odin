package unthread

import "core:path/filepath"
import "core:fmt"
import "core:log"
import "core:os"
import "core:mem/virtual"
import "dependencies:cli"

Command :: union {
	AnalyzeLockFile,
	DiffLockFiles,
}

AnalyzeLockFile :: struct {
	filename: string `cli:"f,filename/required"`,
}

DiffLockFiles :: struct {
	file1: string `cli:"1,file1/required"`,
	file2: string `cli:"2,file2/required"`,
}

main :: proc() {
	arena: virtual.Arena
	arena_init_error := virtual.arena_init_growing(&arena, 1024 * 1024 * 10)
	if arena_init_error != nil {
		fmt.println("Failed to initialize arena: ", arena_init_error)
		os.exit(1)
	}
	context.allocator = virtual.arena_allocator(&arena)
	context.logger = log.create_console_logger()

	arguments := os.args
	if len(arguments) < 2 {
		fmt.printf("Commands:\n\n")
		cli.print_help_for_union_type_and_exit(Command)
		os.exit(1)
	}

	command, _, cli_error := cli.parse_arguments_as_type(arguments[1:], Command)
	if cli_error != nil {
		fmt.println("Failed to parse arguments: ", cli_error)
		os.exit(1)
	}
	switch c in command {
	case AnalyzeLockFile:
		run_analyze_lock_file(c)
	case DiffLockFiles:
		run_diff_lock_files(c)
	}
}

run_analyze_lock_file :: proc(lock_file_arguments: AnalyzeLockFile) {
	filename := lock_file_arguments.filename

	file_bytes, file_read_ok := os.read_entire_file_from_filename(filename)
	if !file_read_ok {
		fmt.println("Failed to read file: ", filename)
		os.exit(1)
	}
	file_data := string(file_bytes)
	tokenizer := tokenizer_create(file_data, filename)
	lock_file, lock_file_error := parse_lock_file(filename, file_data, &tokenizer)
	if lock_file_error != nil {
		fmt.println("Failed to parse lock file: ", lock_file_error)
		os.exit(1)
	}

	package_json_file := filepath.join({filepath.dir(filename), "package.json"})
	package_json_file_bytes, package_json_file_read_ok := os.read_entire_file_from_filename(
		package_json_file,
	)
	if !package_json_file_read_ok {
		fmt.println("Failed to read file: ", package_json_file)
		os.exit(1)
	}

	package_json, package_json_error := read_package_json_file(package_json_file_bytes)
	if package_json_error != nil {
		fmt.println("Failed to read package.json file: ", package_json_error)
		os.exit(1)
	}

	direct_to_transitive_ratio := f32(len(package_json.dependencies)) / f32(len(lock_file.entries))

	fmt.printf(
		"Dependencies:\n\tDirect: %d (Development: %d)\n\tTransitive: %d\n\tRatio (direct/transitive): %f\n",
		len(package_json.dependencies) + len(package_json.devDependencies),
		len(package_json.devDependencies),
		len(lock_file.entries),
		direct_to_transitive_ratio,
	)
}

run_diff_lock_files :: proc(arguments: DiffLockFiles) {
	file1 := arguments.file1
	file2 := arguments.file2

	file1_bytes, file1_read_ok := os.read_entire_file_from_filename(file1)
	if !file1_read_ok {
		fmt.println("Failed to read file: ", file1)
		os.exit(1)
	}

	file2_bytes, file2_read_ok := os.read_entire_file_from_filename(file2)
	if !file2_read_ok {
		fmt.println("Failed to read file: ", file2)
		os.exit(1)
	}

	file1_data := string(file1_bytes)
	file2_data := string(file2_bytes)

	tokenizer1 := tokenizer_create(file1_data, file1)
	tokenizer2 := tokenizer_create(file2_data, file2)

	lock_file1, lock_file1_error := parse_lock_file(file1, file1_data, &tokenizer1)
	if lock_file1_error != nil {
		fmt.println("Failed to parse lock file: ", lock_file1_error)
		os.exit(1)
	}

	lock_file2, lock_file2_error := parse_lock_file(file2, file2_data, &tokenizer2)
	if lock_file2_error != nil {
		fmt.println("Failed to parse lock file: ", lock_file2_error)
		os.exit(1)
	}

	lock_file1_entries := lock_file1.entries
	lock_file2_entries := lock_file2.entries

	in_a, in_b, diff_error := diff_package_entries(lock_file1_entries, lock_file2_entries)
	if diff_error != nil {
		fmt.println("Failed to diff lock files: ", diff_error)
		os.exit(1)
	}

	for name, _ in in_a {
		fmt.printf("- %s\n", name)
	}

	for name, _ in in_b {
		fmt.printf("+ %s\n", name)
	}
}
