package unthread

import "core:strings"
import "core:testing"
import "core:fmt"
import "core:log"
import "core:slice"
import "core:mem"

LockFile :: struct {
	filename:  string,
	version:   string,
	cache_key: string,
	entries:   []LockFileEntry,
}

LockFileEntry :: struct {
	names:   []string,
	version: string,
	hash:    string,
}

ParsingError :: union {
	ExpectedTokenError,
	mem.Allocator_Error,
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

parse_package_name_header :: proc(
	tokenizer: ^Tokenizer,
	allocator := context.allocator,
) -> (
	names: []string,
	error: ParsingError,
) {
	names = parse_package_names(tokenizer, allocator) or_return
	tokenizer_expect(tokenizer, Colon{}) or_return
	tokenizer_skip_any_of(tokenizer, {Newline{}})

	return names, nil
}

parse_package_names :: proc(
	tokenizer: ^Tokenizer,
	allocator := context.allocator,
) -> (
	names: []string,
	error: ParsingError,
) {
	full_package_name_token := tokenizer_expect(tokenizer, String{}) or_return

	full_package_name_string := full_package_name_token.token.(String).value
	names = strings.split(full_package_name_string, ", ", allocator)

	return names, nil
}

parse_package_name :: proc(tokenizer: ^Tokenizer) -> (name: string, error: ExpectationError) {
	token, expect_error := tokenizer_expect(tokenizer, String{})
	if expect_error != nil {
		return "", expect_error
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

@(test, private = "package")
test_parse_package_names :: proc(t: ^testing.T) {
	context.logger = log.create_console_logger()

	tokenizer := tokenizer_create(
		`"@babel/core@npm:^7.11.6, @babel/core@npm:^7.12.3, @babel/core@npm:^7.13.16, @babel/core@npm:^7.20.12, @babel/core@npm:^7.21.8, @babel/core@npm:^7.22.5, @babel/core@npm:^7.22.9, @babel/core@npm:^7.7.5"`,
	)
	names, error := parse_package_names(&tokenizer)
	testing.expect(
		t,
		error == nil,
		fmt.tprintf("Error is not nil for valid package names: %v\n", error),
	)

	testing.expect(
		t,
		slice.equal(
			names,
			[]string{
				"@babel/core@npm:^7.11.6",
				"@babel/core@npm:^7.12.3",
				"@babel/core@npm:^7.13.16",
				"@babel/core@npm:^7.20.12",
				"@babel/core@npm:^7.21.8",
				"@babel/core@npm:^7.22.5",
				"@babel/core@npm:^7.22.9",
				"@babel/core@npm:^7.7.5",
			},
		),
		fmt.tprintf(
			"Parsed package names are not equal to expected package names, got: %v\n",
			names,
		),
	)
}

@(test, private = "package")
test_parse_package_name_header :: proc(t: ^testing.T) {
	context.logger = log.create_console_logger()

	package_names :: `"@babel/core@npm:^7.11.6, @babel/core@npm:^7.12.3, @babel/core@npm:^7.13.16, @babel/core@npm:^7.20.12, @babel/core@npm:^7.21.8, @babel/core@npm:^7.22.5, @babel/core@npm:^7.22.9, @babel/core@npm:^7.7.5"`
	terminator_newline_and_indentation :: ":\n  "

	tokenizer := tokenizer_create(package_names + terminator_newline_and_indentation)
	names, error := parse_package_name_header(&tokenizer)
	testing.expect(
		t,
		error == nil,
		fmt.tprintf("Error is not nil for valid package names: %v\n", error),
	)

	testing.expect(
		t,
		slice.equal(
			names,
			[]string{
				"@babel/core@npm:^7.11.6",
				"@babel/core@npm:^7.12.3",
				"@babel/core@npm:^7.13.16",
				"@babel/core@npm:^7.20.12",
				"@babel/core@npm:^7.21.8",
				"@babel/core@npm:^7.22.5",
				"@babel/core@npm:^7.22.9",
				"@babel/core@npm:^7.7.5",
			},
		),
		fmt.tprintf(
			"Parsed package names are not equal to expected package names, got: %v\n",
			names,
		),
	)

	rest_of_source := tokenizer.source[tokenizer.position:]
	testing.expect_value(t, rest_of_source, "  ")
}
