package unthread

import "core:fmt"
import "core:log"
import "core:os"
import "core:mem/virtual"

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
		fmt.println("Usage: unthread <file>")
		os.exit(1)
	}

	filename := arguments[1]
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

	log.infof("Lock file entries: %d", len(lock_file.entries))
}
