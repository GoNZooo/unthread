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
	ExpectedStringError,
	mem.Allocator_Error,
}

Dependency :: struct {
	name:   string,
	bounds: string,
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

parse_version_line :: proc(tokenizer: ^Tokenizer) -> (version: string, error: ExpectationError) {
	tokenizer_skip_any_of(tokenizer, {Space{}})
	tokenizer_skip_string(tokenizer, "version: ") or_return
	string := tokenizer_read_string_until(tokenizer, {"\r\n", "\n"}) or_return
	tokenizer_skip_any_of(tokenizer, {Newline{}})

	return string, nil
}

parse_resolution_line :: proc(
	tokenizer: ^Tokenizer,
) -> (
	version: string,
	error: ExpectationError,
) {
	tokenizer_skip_any_of(tokenizer, {Space{}})
	tokenizer_skip_string(tokenizer, "resolution: ") or_return
	token := tokenizer_expect(tokenizer, String{}) or_return
	tokenizer_skip_any_of(tokenizer, {Newline{}})

	return token.token.(String).value, nil
}

parse_dependencies :: proc(
	tokenizer: ^Tokenizer,
	allocator := context.allocator,
) -> (
	dependencies: []Dependency,
	error: ParsingError,
) {
	tokenizer_skip_any_of(tokenizer, {Space{}})
	tokenizer_skip_string(tokenizer, "dependencies:") or_return
	tokenizer_expect(tokenizer, Newline{}) or_return
	reading_deps := true
	dependencies_slice := make([dynamic]Dependency, 0, 0, allocator) or_return

	for reading_deps {
		dependency, error := parse_dependency_line(tokenizer)
		if error != nil {
			reading_deps = false
			continue
		}

		append(&dependencies_slice, dependency)
	}

	return dependencies_slice[:], nil
}

parse_dependency_line :: proc(
	tokenizer: ^Tokenizer,
) -> (
	dependency: Dependency,
	error: ExpectationError,
) {
	tokenizer_skip_string(tokenizer, "    ") or_return
	token, expect_error := tokenizer_expect(tokenizer, String{})
	if expect_error != nil {
		// we hit a non-string dependency, so we want to read the line as `name: bound`
		name := tokenizer_read_string_until(tokenizer, {":"}) or_return
		tokenizer_expect(tokenizer, Colon{}) or_return
		bounds := tokenizer_read_string_until(tokenizer, {"\r\n", "\n"}) or_return
		tokenizer_expect(tokenizer, Newline{}) or_return

		return Dependency{name = name, bounds = bounds}, nil
	}

	name := token.token.(String).value
	tokenizer_skip_any_of(tokenizer, {Colon{}, Space{}})
	bounds := tokenizer_read_string_until(tokenizer, {"\r\n", "\n"}) or_return
	tokenizer_expect(tokenizer, Newline{}) or_return

	return Dependency{name = name, bounds = bounds}, nil
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

@(test, private = "package")
test_parse_version_line :: proc(t: ^testing.T) {
	context.logger = log.create_console_logger()

	tokenizer := tokenizer_create("version: 1.2.3\n")
	version, error := parse_version_line(&tokenizer)
	testing.expect(
		t,
		error == nil,
		fmt.tprintf("Error is not nil for valid version line: %v\n", error),
	)

	testing.expect_value(t, version, "1.2.3")

	rest_of_source := tokenizer.source[tokenizer.position:]
	testing.expect_value(t, rest_of_source, "")
}

@(test, private = "package")
test_parse_resolution_line :: proc(t: ^testing.T) {
	context.logger = log.create_console_logger()

	tokenizer := tokenizer_create(`resolution: "@babel/code-frame@npm:7.22.5"` + "\n")
	resolution, error := parse_resolution_line(&tokenizer)
	testing.expect(
		t,
		error == nil,
		fmt.tprintf("Error is not nil for valid resolution line: %v\n", error),
	)

	testing.expect_value(t, resolution, "@babel/code-frame@npm:7.22.5")

	rest_of_source := tokenizer.source[tokenizer.position:]
	testing.expect_value(t, rest_of_source, "")
}

@(test, private = "package")
test_parse_dependencies :: proc(t: ^testing.T) {
	context.logger = log.create_console_logger()

	dependencies1 := `  dependencies:
    "@babel/highlight": ^7.22.5` + "\n"
	tokenizer := tokenizer_create(dependencies1)
	dependencies, error := parse_dependencies(&tokenizer)
	testing.expect(
		t,
		error == nil,
		fmt.tprintf("Error is not nil for valid dependencies: %v\n", error),
	)

	testing.expect(
		t,
		slice.equal(dependencies, []Dependency{{name = "@babel/highlight", bounds = "^7.22.5"}}),
		fmt.tprintf(
			"Parsed dependencies are not equal to expected dependencies, got: %v\n",
			dependencies,
		),
	)
}
