package unthread

import "core:path/filepath"
import "core:fmt"
import "core:log"
import "core:os"
import "core:mem/virtual"
import "dependencies:cli"

Command :: union {
	AnalyzeLockFile,
}

AnalyzeLockFile :: struct {
	filename: string `cli:"f,filename/required"`,
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
		fmt.println("Usage: unthread -f=<file>|--filename=<file>")
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
