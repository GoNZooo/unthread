package unthread

import "core:strings"
import "core:log"
import "core:testing"
import "core:mem"

diff_package_entries :: proc(
	a: []LockFileEntry,
	b: []LockFileEntry,
	allocator := context.allocator,
) -> (
	in_a: map[string]LockFileEntry,
	in_b: map[string]LockFileEntry,
	error: mem.Allocator_Error,
) {
	a_map := make(map[string]LockFileEntry, len(a), allocator) or_return
	defer delete(a_map)
	b_map := make(map[string]LockFileEntry, len(b), allocator) or_return
	defer delete(b_map)

	for entry in a {
		for name in entry.names {
			a_map[name] = entry
		}
	}

	for entry in b {
		for name in entry.names {
			b_map[name] = entry
		}
	}

	a_entries := make(map[string]LockFileEntry, len(a), allocator) or_return
	b_entries := make(map[string]LockFileEntry, len(b), allocator) or_return

	for name, entry in a_map {
		if _, ok := b_map[name]; !ok {
			a_entries[name] = entry
		}
	}

	for name, entry in b_map {
		if _, ok := a_map[name]; !ok {
			b_entries[name] = entry
		}
	}

	return a_entries, b_entries, nil
}

prefix_matches :: proc(s: string, prefix: string) -> bool {
	return strings.has_prefix(s, prefix)
}

read_until :: proc(s: string, characters: string) -> string {
	character_index := strings.index_any(s, characters)
	if character_index == -1 {
		return s
	}

	v := s[:character_index]

	return v
}

@(test)
test_read_until :: proc(t: ^testing.T) {
	context.logger = log.create_console_logger()

	testing.expect_value(t, read_until("hello", "e"), "h")
	testing.expect_value(t, read_until("hello there", " "), "hello")
	testing.expect_value(t, read_until("there", " "), "there")
}
