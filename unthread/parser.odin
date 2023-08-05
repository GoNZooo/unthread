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
	names:             []string,
	version:           string,
	resolution:        string,
	checksum:          string,
	language_name:     string,
	link_type:         LinkType,
	dependencies:      []Dependency,
	peer_dependencies: []Dependency,
	dependencies_meta: map[string]DependencyMeta,
}

LinkType :: enum {
	Hard,
	Soft,
}

ParsingError :: union {
	ExpectedTokenError,
	ExpectedStringError,
	ExpectedEndMarkerError,
	mem.Allocator_Error,
}

Dependency :: struct {
	name:   string,
	bounds: string,
}

DependencyMeta :: struct {
	optional: bool,
}

Binary :: struct {
	name: string,
	path: string,
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

parse_peer_dependencies :: proc(
	tokenizer: ^Tokenizer,
	allocator := context.allocator,
) -> (
	dependencies: []Dependency,
	error: ParsingError,
) {
	tokenizer_skip_any_of(tokenizer, {Space{}})
	tokenizer_skip_string(tokenizer, "peerDependencies:") or_return
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

parse_dependencies_meta :: proc(
	tokenizer: ^Tokenizer,
	allocator := context.allocator,
) -> (
	dependencies_meta: map[string]DependencyMeta,
	error: ParsingError,
) {
	tokenizer_skip_string(tokenizer, "  dependenciesMeta:") or_return
	tokenizer_expect(tokenizer, Newline{}) or_return
	reading_meta := true
	dependencies_meta = make(map[string]DependencyMeta, 0, allocator) or_return

	for reading_meta {
		base_indent_error := tokenizer_skip_string(tokenizer, "    ")
		if base_indent_error != nil {
			reading_meta = false
			continue
		}
		peek_token := tokenizer_peek(tokenizer)
		_, is_string := peek_token.(String)
		package_name: string
		if !is_string {
			package_name = tokenizer_read_string_until(tokenizer, {":"}) or_return
		} else {
			package_name_token := tokenizer_expect(tokenizer, String{}) or_return
			package_name = package_name_token.token.(String).value
		}

		tokenizer_expect(tokenizer, Colon{}) or_return
		tokenizer_expect(tokenizer, Newline{}) or_return
		dependency_meta := parse_dependency_meta(tokenizer) or_return

		dependencies_meta[package_name] = dependency_meta
	}

	return dependencies_meta, nil
}

parse_dependency_meta :: proc(
	tokenizer: ^Tokenizer,
) -> (
	dependency_meta: DependencyMeta,
	error: ParsingError,
) {
	tokenizer_skip_string(tokenizer, "      ") or_return
	tokenizer_expect_exact(tokenizer, LowerSymbol{value = "optional"}) or_return
	tokenizer_expect(tokenizer, Colon{}) or_return
	tokenizer_skip_any_of(tokenizer, {Space{}})
	token := tokenizer_expect(tokenizer, Boolean{}) or_return
	tokenizer_expect(tokenizer, Newline{}) or_return

	return DependencyMeta{optional = token.token.(Boolean).value}, nil
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

parse_link_type :: proc(tokenizer: ^Tokenizer) -> (link_type: LinkType, error: ExpectationError) {
	tokenizer_skip_any_of(tokenizer, {Space{}})
	tokenizer_skip_string(tokenizer, "linkType: ") or_return
	token := tokenizer_expect(tokenizer, LowerSymbol{}) or_return
	tokenizer_expect(tokenizer, Newline{}) or_return

	link_type_token := token.token.(LowerSymbol)

	if link_type_token.value == "hard" {
		return LinkType.Hard, nil
	} else if link_type_token.value == "soft" {
		return LinkType.Soft, nil
	} else {
		// TODO: this should be an error received from the tokenizer for a `expect_one_of` call or
		// something like that
		return link_type, ExpectedOneOfError(
			ExpectedOneOf{
				expected = {LowerSymbol{value = "hard"}, LowerSymbol{value = "soft"}},
				actual = link_type_token,
			},
		)
	}
}

parse_binaries :: proc(
	tokenizer: ^Tokenizer,
	allocator := context.allocator,
) -> (
	binaries: []Binary,
	error: ParsingError,
) {
	tokenizer_skip_any_of(tokenizer, {Space{}})
	tokenizer_skip_string(tokenizer, "bin:") or_return
	tokenizer_expect(tokenizer, Newline{}) or_return
	reading_binaries := true
	binaries_slice := make([dynamic]Binary, 0, 0, allocator) or_return

	for reading_binaries {
		binary, error := parse_binary_line(tokenizer)
		if error != nil {
			reading_binaries = false
			continue
		}

		append(&binaries_slice, binary)
	}

	return binaries_slice[:], nil
}

parse_binary_line :: proc(tokenizer: ^Tokenizer) -> (binary: Binary, error: ExpectationError) {
	tokenizer_skip_string(tokenizer, "    ") or_return
	name := tokenizer_read_string_until(tokenizer, {":"}) or_return
	tokenizer_skip_any_of(tokenizer, {Colon{}, Space{}})
	path := tokenizer_read_string_until(tokenizer, {"\r\n", "\n"}) or_return
	tokenizer_expect(tokenizer, Newline{}) or_return

	return Binary{name = name, path = path}, nil
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
test_parse_peer_dependencies :: proc(t: ^testing.T) {
	context.logger = log.create_console_logger()

	dependencies1 := `  peerDependencies:
    "@swc/helpers": ^0.5.05` + "\n"
	tokenizer := tokenizer_create(dependencies1)
	dependencies, error := parse_peer_dependencies(&tokenizer)
	testing.expect(
		t,
		error == nil,
		fmt.tprintf("Error is not nil for valid dependencies: %v\n", error),
	)

	testing.expect(
		t,
		slice.equal(dependencies, []Dependency{{name = "@swc/helpers", bounds = "^0.5.05"}}),
		fmt.tprintf(
			"Parsed dependencies are not equal to expected dependencies, got: %v\n",
			dependencies,
		),
	)

	dependencies2 :=
		`  peerDependencies:
    react: ^16.8.0 || ^17.0.0 || ^18.0.0
    react-dom: ^16.8.0 || ^17.0.0 || ^18.0.0` +
		"\n"
	tokenizer = tokenizer_create(dependencies2)
	dependencies, error = parse_peer_dependencies(&tokenizer)
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
				{name = "react", bounds = "^16.8.0 || ^17.0.0 || ^18.0.0"},
				{name = "react-dom", bounds = "^16.8.0 || ^17.0.0 || ^18.0.0"},
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

	testing.expect_value(t, link_type, LinkType.Hard)

	rest_of_source := tokenizer.source[tokenizer.position:]
	testing.expect_value(t, rest_of_source, "")

	link_type2 := `  linkType: soft` + "\n"
	tokenizer = tokenizer_create(link_type2)
	link_type, error = parse_link_type(&tokenizer)
	testing.expect(
		t,
		error == nil,
		fmt.tprintf("Error is not nil for valid link type: %v\n", error),
	)

	testing.expect_value(t, link_type, LinkType.Soft)

	rest_of_source = tokenizer.source[tokenizer.position:]
	testing.expect_value(t, rest_of_source, "")
}

@(test, private = "package")
test_parse_binaries :: proc(t: ^testing.T) {
	context.logger = log.create_console_logger()

	binaries1 := `  bin:
    prettierd: bin/prettierd` + "\n"
	tokenizer := tokenizer_create(binaries1)
	binaries, error := parse_binaries(&tokenizer)
	testing.expect(
		t,
		error == nil,
		fmt.tprintf("Error is not nil for valid binaries: %v\n", error),
	)

	testing.expect(
		t,
		slice.equal(binaries, []Binary{{name = "prettierd", path = "bin/prettierd"}}),
		fmt.tprintf("Parsed binaries are not equal to expected binaries, got: %v\n", binaries),
	)

	rest_of_source := tokenizer.source[tokenizer.position:]
	testing.expect_value(t, rest_of_source, "")

	binaries2 :=
		`  bin:
    getstorybook: ./bin/index.js
    sb: ./bin/index.js
    third: bin/third.js` +
		"\n"
	tokenizer = tokenizer_create(binaries2)
	binaries, error = parse_binaries(&tokenizer)
	testing.expect(
		t,
		error == nil,
		fmt.tprintf("Error is not nil for valid binaries: %v\n", error),
	)

	testing.expect(
		t,
		slice.equal(
			binaries,
			[]Binary{
				{name = "getstorybook", path = "./bin/index.js"},
				{name = "sb", path = "./bin/index.js"},
				{name = "third", path = "bin/third.js"},
			},
		),
		fmt.tprintf("Parsed binaries are not equal to expected binaries, got: %v\n", binaries),
	)

	rest_of_source = tokenizer.source[tokenizer.position:]
	testing.expect_value(t, rest_of_source, "")
}

@(test, private = "package")
test_parse_dependencies_meta :: proc(t: ^testing.T) {
	context.logger = log.create_console_logger()

	dependencies_meta1 :=
		`  dependenciesMeta:
    "@esbuild/android-arm":
      optional: true
    "@esbuild/android-arm64":
      optional: true
    "@esbuild/android-x64":
      optional: true
    "@esbuild/darwin-arm64":
      optional: true
    "@esbuild/darwin-x64":
      optional: true
    "@esbuild/freebsd-arm64":
      optional: true
    "@esbuild/freebsd-x64":
      optional: true
    "@esbuild/linux-arm":
      optional: true
    "@esbuild/linux-arm64":
      optional: true
    "@esbuild/linux-ia32":
      optional: true
    "@esbuild/linux-loong64":
      optional: true
    "@esbuild/linux-mips64el":
      optional: true
    "@esbuild/linux-ppc64":
      optional: true
    "@esbuild/linux-riscv64":
      optional: true
    "@esbuild/linux-s390x":
      optional: true
    "@esbuild/linux-x64":
      optional: true
    "@esbuild/netbsd-x64":
      optional: true
    "@esbuild/openbsd-x64":
      optional: true
    "@esbuild/sunos-x64":
      optional: true
    "@esbuild/win32-arm64":
      optional: true
    "@esbuild/win32-ia32":
      optional: true
    "@esbuild/win32-x64":
      optional: true` +
		"\n"

	expected_dependencies_meta := map[string]DependencyMeta {
		"@esbuild/android-arm" = {optional = true},
		"@esbuild/android-arm64" = {optional = true},
		"@esbuild/android-x64" = {optional = true},
		"@esbuild/darwin-arm64" = {optional = true},
		"@esbuild/darwin-x64" = {optional = true},
		"@esbuild/freebsd-arm64" = {optional = true},
		"@esbuild/freebsd-x64" = {optional = true},
		"@esbuild/linux-arm" = {optional = true},
		"@esbuild/linux-arm64" = {optional = true},
		"@esbuild/linux-ia32" = {optional = true},
		"@esbuild/linux-loong64" = {optional = true},
		"@esbuild/linux-mips64el" = {optional = true},
		"@esbuild/linux-ppc64" = {optional = true},
		"@esbuild/linux-riscv64" = {optional = true},
		"@esbuild/linux-s390x" = {optional = true},
		"@esbuild/linux-x64" = {optional = true},
		"@esbuild/netbsd-x64" = {optional = true},
		"@esbuild/openbsd-x64" = {optional = true},
		"@esbuild/sunos-x64" = {optional = true},
		"@esbuild/win32-arm64" = {optional = true},
		"@esbuild/win32-ia32" = {optional = true},
		"@esbuild/win32-x64" = {optional = true},
	}

	tokenizer := tokenizer_create(dependencies_meta1)
	dependencies_meta, error := parse_dependencies_meta(&tokenizer)
	testing.expect(
		t,
		error == nil,
		fmt.tprintf("Error is not nil for valid dependencies meta: %v\n", error),
	)

	testing.expect(
		t,
		len(dependencies_meta) == len(expected_dependencies_meta),
		fmt.tprintf(
			"Parsed dependencies meta length is not equal to expected dependencies meta length, got: %v\n",
			dependencies_meta,
		),
	)

	for key, value in dependencies_meta {
		testing.expect(
			t,
			value == expected_dependencies_meta[key],
			fmt.tprintf(
				"Parsed dependencies meta is not equal to expected dependencies meta, got: %v\n",
				dependencies_meta,
			),
		)
	}

	rest_of_source := tokenizer.source[tokenizer.position:]
	testing.expect_value(t, rest_of_source, "")
}

maps_equal :: proc(a: map[$K]$V, b: map[K]V) -> bool where intrinsics.type_is_comparable(V) {
	if len(a) != len(b) {
		return false
	}

	for key, value in a {
		if b[key] != value {
			return false
		}
	}

	return true
}
