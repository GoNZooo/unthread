package unthread

import "core:testing"
import "core:fmt"
import "core:log"

LockFile :: struct {
	filename:  string,
	version:   string,
	cache_key: string,
	entries:   []LockFileEntry,
}

LockFileEntry :: struct {
	name:    string,
	version: string,
	hash:    string,
}

parse_lock_file :: proc(
	filename: string,
	source: string,
	tokenizer: ^Tokenizer,
) -> (
	lock_file: LockFile,
	error: ExpectationError,
) {
	return
}

parse_package_name :: proc(tokenizer: ^Tokenizer) -> (name: string, error: ExpectationError) {
	token, expect_error := tokenizer_expect(tokenizer, String{})
	if expect_error != nil {
		return "", expect_error.?
	}

	return token.token.(String).value, nil
}

@(test, private = "package")
test_parse_package_name :: proc(t: ^testing.T) {
	context.logger = log.create_console_logger()

	tokenizer := tokenizer_create(`"@aashutoshrathi/word-wrap@npm:1.2.6"`)
	name, error := parse_package_name(&tokenizer)
	testing.expect(
		t,
		error == nil,
		fmt.tprintf("Error is not nil for valid package name: %v\n", error),
	)

	testing.expect_value(t, name, "@aashutoshrathi/word-wrap@npm:1.2.6")
}
