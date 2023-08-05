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
	names:         []string,
	version:       string,
	resolution:    string,
	checksum:      string,
	language_name: string,
	link_type:     string,
	dependencies:  []Dependency,
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
	peek_token := tokenizer_peek(tokenizer)
	_, is_string := peek_token.(String)
	if !is_string {
		// we hit a non-string dependency, so we want to read the line as `name: bound`
		name := tokenizer_read_string_until(tokenizer, {":"}) or_return
		tokenizer_expect(tokenizer, Colon{}) or_return
		tokenizer_expect(tokenizer, Space{}) or_return
		bounds := tokenizer_read_string_until(tokenizer, {"\r\n", "\n"}) or_return
		tokenizer_expect(tokenizer, Newline{}) or_return

		return Dependency{name = name, bounds = bounds}, nil
	}

	token := tokenizer_expect(tokenizer, String{}) or_return
	name := token.token.(String).value
	tokenizer_skip_any_of(tokenizer, {Colon{}, Space{}})
	bounds := tokenizer_read_string_until(tokenizer, {"\r\n", "\n"}) or_return
	tokenizer_expect(tokenizer, Newline{}) or_return

	return Dependency{name = name, bounds = bounds}, nil
}

parse_checksum :: proc(tokenizer: ^Tokenizer) -> (checksum: string, error: ExpectationError) {
	tokenizer_skip_any_of(tokenizer, {Space{}})
	tokenizer_skip_string(tokenizer, "checksum: ") or_return
	checksum = tokenizer_read_string_until(tokenizer, {"\r\n", "\n"}) or_return
	tokenizer_expect(tokenizer, Newline{}) or_return

	return checksum, nil
}

parse_language_name :: proc(
	tokenizer: ^Tokenizer,
) -> (
	language_name: string,
	error: ExpectationError,
) {
	tokenizer_skip_any_of(tokenizer, {Space{}})
	tokenizer_skip_string(tokenizer, "languageName: ") or_return
	language_name = tokenizer_read_string_until(tokenizer, {"\r\n", "\n"}) or_return
	tokenizer_expect(tokenizer, Newline{}) or_return

	return language_name, nil
}

parse_link_type :: proc(tokenizer: ^Tokenizer) -> (link_type: string, error: ExpectationError) {
	tokenizer_skip_any_of(tokenizer, {Space{}})
	tokenizer_skip_string(tokenizer, "linkType: ") or_return
	link_type = tokenizer_read_string_until(tokenizer, {"\r\n", "\n"}) or_return
	tokenizer_expect(tokenizer, Newline{}) or_return

	return link_type, nil
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

	dependencies2 := `  dependencies:
    "@ampproject/remapping": ^2.2.0
    "@babel/code-frame": ^7.22.5
    "@babel/generator": ^7.22.9
    "@babel/helper-compilation-targets": ^7.22.9
    "@babel/helper-module-transforms": ^7.22.9
    "@babel/helpers": ^7.22.6
    "@babel/parser": ^7.22.7
    "@babel/template": ^7.22.5
    "@babel/traverse": ^7.22.8
    "@babel/types": ^7.22.5
    convert-source-map: ^1.7.0
    debug: ^4.1.0
    gensync: ^1.0.0-beta.2
    json5: ^2.2.2
    semver: ^6.3.1
`
	tokenizer = tokenizer_create(dependencies2)
	dependencies, error = parse_dependencies(&tokenizer)
	testing.expect(
		t,
		error == nil,
		fmt.tprintf("Error is not nil for valid dependencies: %v\n", error),
	)

	testing.expect(
		t,
		slice.equal(
			dependencies,
			[]Dependency{
				{name = "@ampproject/remapping", bounds = "^2.2.0"},
				{name = "@babel/code-frame", bounds = "^7.22.5"},
				{name = "@babel/generator", bounds = "^7.22.9"},
				{name = "@babel/helper-compilation-targets", bounds = "^7.22.9"},
				{name = "@babel/helper-module-transforms", bounds = "^7.22.9"},
				{name = "@babel/helpers", bounds = "^7.22.6"},
				{name = "@babel/parser", bounds = "^7.22.7"},
				{name = "@babel/template", bounds = "^7.22.5"},
				{name = "@babel/traverse", bounds = "^7.22.8"},
				{name = "@babel/types", bounds = "^7.22.5"},
				{name = "convert-source-map", bounds = "^1.7.0"},
				{name = "debug", bounds = "^4.1.0"},
				{name = "gensync", bounds = "^1.0.0-beta.2"},
				{name = "json5", bounds = "^2.2.2"},
				{name = "semver", bounds = "^6.3.1"},
			},
		),
		fmt.tprintf(
			"Parsed dependencies are not equal to expected dependencies, got: %v\n",
			dependencies,
		),
	)
}

@(test, private = "package")
test_parse_checksum :: proc(t: ^testing.T) {
	context.logger = log.create_console_logger()

	checksum1 :=
		`  checksum: 7bf069aeceb417902c4efdaefab1f7b94adb7dea694a9aed1bda2edf4135348a080820529b1a300c6f8605740a00ca00c19b2d5e74b5dd489d99d8c11d5e56d1` +
		"\n"
	tokenizer := tokenizer_create(checksum1)
	checksum, error := parse_checksum(&tokenizer)
	testing.expect(
		t,
		error == nil,
		fmt.tprintf("Error is not nil for valid checksum: %v\n", error),
	)

	testing.expect_value(
		t,
		checksum,
		"7bf069aeceb417902c4efdaefab1f7b94adb7dea694a9aed1bda2edf4135348a080820529b1a300c6f8605740a00ca00c19b2d5e74b5dd489d99d8c11d5e56d1",
	)

	rest_of_source := tokenizer.source[tokenizer.position:]
	testing.expect_value(t, rest_of_source, "")
}

@(test, private = "package")
test_parse_language_name :: proc(t: ^testing.T) {
	context.logger = log.create_console_logger()

	language_name1 := `  languageName: node` + "\n"
	tokenizer := tokenizer_create(language_name1)
	language_name, error := parse_language_name(&tokenizer)
	testing.expect(
		t,
		error == nil,
		fmt.tprintf("Error is not nil for valid language name: %v\n", error),
	)

	testing.expect_value(t, language_name, "node")

	rest_of_source := tokenizer.source[tokenizer.position:]
	testing.expect_value(t, rest_of_source, "")
}

@(test, private = "package")
test_parse_link_type :: proc(t: ^testing.T) {
	context.logger = log.create_console_logger()

	link_type1 := `  linkType: hard` + "\n"
	tokenizer := tokenizer_create(link_type1)
	link_type, error := parse_link_type(&tokenizer)
	testing.expect(
		t,
		error == nil,
		fmt.tprintf("Error is not nil for valid link type: %v\n", error),
	)

	testing.expect_value(t, link_type, "hard")

	rest_of_source := tokenizer.source[tokenizer.position:]
	testing.expect_value(t, rest_of_source, "")
}
