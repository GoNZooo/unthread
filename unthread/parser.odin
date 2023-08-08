package unthread

import "core:time"
import "core:mem/virtual"
import "core:os"
import "core:strings"
import "core:testing"
import "core:fmt"
import "core:log"
import "core:slice"
import "core:mem"

LockFile :: struct {
	filename:  string,
	version:   int,
	cache_key: int,
	entries:   []LockFileEntry,
}

LockFileEntry :: struct {
	names:                  []string,
	// TODO(gonz): make this a `Version` union that is semver (+ maybe git ref) or `OtherVersion`
	version:                string,
	resolution:             string,
	conditions:             string,
	checksum:               string,
	// TODO(gonz): make this a union that has some presets & an `OtherLanguage` option
	language_name:          string,
	link_type:              LinkType,
	dependencies:           []Dependency,
	binaries:               []Binary,
	peer_dependencies:      []Dependency,
	// TODO(gonz): make this `string` a `PackageName` type
	dependencies_meta:      map[string]DependencyMeta,
	peer_dependencies_meta: map[string]DependencyMeta,
}

LinkType :: enum {
	Hard,
	Soft,
}

ParsingError :: union #shared_nil {
	Maybe(ExpectedToken),
	Maybe(ExpectedString),
	Maybe(ExpectedEndMarker),
	Maybe(ExpectedOneOf),
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
	allocator := context.allocator,
) -> (
	lock_file: LockFile,
	error: ParsingError,
) {
	tokenizer_skip_any_of(tokenizer, {Comment{}, Newline{}})
	version, cache_key := parse_metadata(tokenizer) or_return
	tokenizer_expect(tokenizer, Newline{}) or_return
	lock_file.filename = filename
	lock_file.version = version
	lock_file.cache_key = cache_key
	entries := make([dynamic]LockFileEntry, 0, 1024, allocator) or_return

	for {
		entry := parse_lock_file_entry(tokenizer, allocator) or_return
		append(&entries, entry)
		peek_token := tokenizer_peek(tokenizer)
		_, is_eof := peek_token.(EOF)
		// NOTE: if we read an EOF instead of a newline we're still fine to finish the parse
		// and jump out
		if is_eof {
			break
		}
	}

	lock_file.entries = entries[:]

	return lock_file, nil
}

@(test, private = "package")
test_parse_lock_file :: proc(t: ^testing.T) {
	context.logger = log.create_console_logger()

	lock_file1 :=
		`__metadata:
  version: 6
  cacheKey: 8

"@aashutoshrathi/word-wrap@npm:^1.2.3":
  version: 1.2.6
  resolution: "@aashutoshrathi/word-wrap@npm:1.2.6"
  checksum: ada901b9e7c680d190f1d012c84217ce0063d8f5c5a7725bb91ec3c5ed99bb7572680eb2d2938a531ccbaec39a95422fcd8a6b4a13110c7d98dd75402f66a0cd
  languageName: node
  linkType: hard

"@achingbrain/ip-address@npm:^8.1.0":
  version: 8.1.0
  resolution: "@achingbrain/ip-address@npm:8.1.0"
  dependencies:
    jsbn: 1.1.0
    sprintf-js: 1.1.2
  checksum: 2b845980a138faf9a5c1a58df2fcdba9e4bf0bc7a5b855bccaac9a61f6886d5707dd8e36ff59a4cfa2c83e29ee1518aae4579595e7534c7ebe01b91e07d86427
  languageName: node
  linkType: hard` +
		"\n"

	tokenizer := tokenizer_create(lock_file1)
	lock_file, error := parse_lock_file("lock_file1", lock_file1, &tokenizer)
	testing.expect(
		t,
		error == nil,
		fmt.tprintf("Expected error when parsing lock file to be `nil`, got: %v", error),
	)
	testing.expect_value(t, lock_file.filename, "lock_file1")
	testing.expect_value(t, lock_file.version, 6)
	testing.expect_value(t, lock_file.cache_key, 8)

	expected_entries := []LockFileEntry{
		{
			names = {"@aashutoshrathi/word-wrap@npm:^1.2.3"},
			version = "1.2.6",
			resolution = "@aashutoshrathi/word-wrap@npm:1.2.6",
			checksum = "ada901b9e7c680d190f1d012c84217ce0063d8f5c5a7725bb91ec3c5ed99bb7572680eb2d2938a531ccbaec39a95422fcd8a6b4a13110c7d98dd75402f66a0cd",
			language_name = "node",
			link_type = LinkType.Hard,
		},
		{
			names = {"@achingbrain/ip-address@npm:^8.1.0"},
			version = "8.1.0",
			resolution = "@achingbrain/ip-address@npm:8.1.0",
			dependencies = {
				{name = "jsbn", bounds = "1.1.0"},
				{name = "sprintf-js", bounds = "1.1.2"},
			},
			checksum = "2b845980a138faf9a5c1a58df2fcdba9e4bf0bc7a5b855bccaac9a61f6886d5707dd8e36ff59a4cfa2c83e29ee1518aae4579595e7534c7ebe01b91e07d86427",
			language_name = "node",
			link_type = LinkType.Hard,
		},
	}
	testing.expect_value(t, len(lock_file.entries), len(expected_entries))
	if len(lock_file.entries) != len(expected_entries) {
		return
	}
	for entry, i in expected_entries {
		testing.expect(
			t,
			slice.equal(lock_file.entries[i].names, entry.names),
			fmt.tprintf(
				"Expected names to be equal, got: %v instead of %v",
				lock_file.entries[i].names,
				entry.names,
			),
		)
		testing.expect_value(t, lock_file.entries[i].version, entry.version)
		testing.expect_value(t, lock_file.entries[i].resolution, entry.resolution)
		testing.expect_value(t, lock_file.entries[i].conditions, entry.conditions)
		testing.expect_value(t, lock_file.entries[i].checksum, entry.checksum)
		testing.expect_value(t, lock_file.entries[i].language_name, entry.language_name)
		testing.expect_value(t, lock_file.entries[i].link_type, entry.link_type)
		testing.expect(
			t,
			slice.equal(lock_file.entries[i].dependencies, entry.dependencies),
			fmt.tprintf(
				"Expected dependencies to be equal, got: %v instead of %v",
				lock_file.entries[i].dependencies,
				entry.dependencies,
			),
		)
		testing.expect(
			t,
			slice.equal(lock_file.entries[i].binaries, entry.binaries),
			fmt.tprintf(
				"Expected binaries to be equal, got: %v instead of %v",
				lock_file.entries[i].binaries,
				entry.binaries,
			),
		)
		testing.expect(
			t,
			slice.equal(lock_file.entries[i].peer_dependencies, entry.peer_dependencies),
			fmt.tprintf(
				"Expected peer dependencies to be equal, got: %v instead of %v",
				lock_file.entries[i].peer_dependencies,
				entry.peer_dependencies,
			),
		)
	}

	arena: virtual.Arena
	arena_init_error := virtual.arena_init_static(&arena, 1024 * 1024 * 4)
	if arena_init_error != nil {
		log.panicf("Failed to initialize arena: %v\n", arena_init_error)
	}
	allocator := virtual.arena_allocator(&arena)
	test_file_path :: "./test_data/test_file_1.lock"
	lock_file2, read_success := os.read_entire_file_from_filename(test_file_path, allocator)
	if !read_success {
		log.panicf("Failed to read test file '%s': %v", test_file_path)
	}

	tokenizer = tokenizer_create(string(lock_file2), test_file_path)
	start_time := time.tick_now()
	lock_file, error = parse_lock_file(test_file_path, string(lock_file2), &tokenizer, allocator)
	end_time := time.tick_now()
	log.infof("Time taken to parse lock file: %v", time.tick_diff(start_time, end_time))
	testing.expect(
		t,
		error == nil,
		fmt.tprintf("Expected error when parsing lock file to be `nil`, got: %v", error),
	)
}

parse_metadata :: proc(
	tokenizer: ^Tokenizer,
) -> (
	version: int,
	cache_key: int,
	error: ParsingError,
) {
	tokenizer_skip_string(tokenizer, "__metadata:") or_return
	tokenizer_expect(tokenizer, Newline{}) or_return
	tokenizer_skip_string(tokenizer, "  version:") or_return
	tokenizer_skip_any_of(tokenizer, {Space{}})
	version_token := tokenizer_expect(tokenizer, Integer{}) or_return
	tokenizer_expect(tokenizer, Newline{}) or_return
	tokenizer_skip_string(tokenizer, "  cacheKey:") or_return
	tokenizer_skip_any_of(tokenizer, {Space{}})
	cache_key_token := tokenizer_expect(tokenizer, Integer{}) or_return
	tokenizer_expect(tokenizer, Newline{}) or_return

	return version_token.token.(Integer).value, cache_key_token.token.(Integer).value, nil
}

@(test, private = "package")
test_parse_metadata :: proc(t: ^testing.T) {
	context.logger = log.create_console_logger()

	metadata := `__metadata:
  version: 6
  cacheKey: 8` + "\n"

	tokenizer := tokenizer_create(metadata)
	version, cache_key, error := parse_metadata(&tokenizer)
	testing.expect(
		t,
		error == nil,
		fmt.tprintf("Expected error when parsing metadata to be `nil`, got: %v", error),
	)

	expected_version := 6
	testing.expect(
		t,
		version == expected_version,
		fmt.tprintf(
			"Expected metadata version to be equal, got: '%s' instead of '%s'",
			version,
			expected_version,
		),
	)

	expected_cache_key := 8
	testing.expect(
		t,
		cache_key == expected_cache_key,
		fmt.tprintf(
			"Expected metadata cache key to be equal, got: '%s' instead of '%s'",
			cache_key,
			expected_cache_key,
		),
	)
}

parse_lock_file_entry :: proc(
	tokenizer: ^Tokenizer,
	allocator := context.allocator,
) -> (
	lock_file_entry: LockFileEntry,
	error: ParsingError,
) {
	lock_file_entry.names = parse_package_name_header(tokenizer, allocator) or_return

	reading_fields := true
	for reading_fields {
		tokenizer_skip_any_of(tokenizer, {Space{}})
		symbol_token, symbol_read_error := tokenizer_expect(tokenizer, LowerSymbol{})
		if symbol_read_error != nil {
			reading_fields = false
			break
		}
		tokenizer_expect(tokenizer, Colon{}) or_return

		field_name := symbol_token.token.(LowerSymbol).value
		switch field_name {
		case "version":
			tokenizer_expect(tokenizer, Space{}) or_return
			lock_file_entry.version = parse_version(tokenizer) or_return
		case "resolution":
			tokenizer_expect(tokenizer, Space{}) or_return
			lock_file_entry.resolution = parse_resolution(tokenizer) or_return
		case "conditions":
			tokenizer_expect(tokenizer, Space{}) or_return
			lock_file_entry.conditions = parse_conditions(tokenizer) or_return
		case "checksum":
			tokenizer_expect(tokenizer, Space{}) or_return
			lock_file_entry.checksum = parse_checksum(tokenizer) or_return
		case "languageName":
			tokenizer_expect(tokenizer, Space{}) or_return
			lock_file_entry.language_name = parse_language_name(tokenizer) or_return
		case "linkType":
			tokenizer_expect(tokenizer, Space{}) or_return
			lock_file_entry.link_type = parse_link_type(tokenizer) or_return
		case "dependencies":
			tokenizer_expect(tokenizer, Newline{}) or_return
			lock_file_entry.dependencies = parse_dependencies(tokenizer, allocator) or_return
		case "peerDependencies":
			tokenizer_expect(tokenizer, Newline{}) or_return
			lock_file_entry.peer_dependencies = parse_peer_dependencies(
				tokenizer,
				allocator,
			) or_return
		case "dependenciesMeta":
			tokenizer_expect(tokenizer, Newline{}) or_return
			lock_file_entry.dependencies_meta = parse_dependencies_meta(
				tokenizer,
				allocator,
			) or_return
		case "peerDependenciesMeta":
			tokenizer_expect(tokenizer, Newline{}) or_return
			lock_file_entry.peer_dependencies_meta = parse_dependencies_meta(
				tokenizer,
				allocator,
			) or_return
		case "bin":
			tokenizer_expect(tokenizer, Newline{}) or_return
			lock_file_entry.binaries = parse_binaries(tokenizer, allocator) or_return
		case:
			log.panicf(
				"Unexpected field name '%s' in lock file entry (file: '%s')",
				field_name,
				tokenizer.filename,
			)
		}
	}

	return lock_file_entry, nil
}

@(test, private = "package")
test_parse_lock_file_entry :: proc(t: ^testing.T) {
	context.logger = log.create_console_logger()

	lock_file_entry1 :=
		`"@aashutoshrathi/word-wrap@npm:^1.2.3":
  version: 1.2.6
  resolution: "@aashutoshrathi/word-wrap@npm:1.2.6"
  checksum: ada901b9e7c680d190f1d012c84217ce0063d8f5c5a7725bb91ec3c5ed99bb7572680eb2d2938a531ccbaec39a95422fcd8a6b4a13110c7d98dd75402f66a0cd
  languageName: node
  linkType: soft` +
		"\n"
	tokenizer := tokenizer_create(lock_file_entry1)
	lock_file_entry, error := parse_lock_file_entry(&tokenizer)
	testing.expect(
		t,
		error == nil,
		fmt.tprintf("Expected error when parsing lock file entry to be `nil`, got: %v", error),
	)

	expected_names := []string{"@aashutoshrathi/word-wrap@npm:^1.2.3"}
	testing.expect(
		t,
		slice.equal(lock_file_entry.names, expected_names),
		fmt.tprintf(
			"Expected lock file entry names to be equal, got: %v instead of %v",
			lock_file_entry.names,
			expected_names,
		),
	)

	expected_version := "1.2.6"
	testing.expect(
		t,
		lock_file_entry.version == expected_version,
		fmt.tprintf(
			"Expected lock file entry version to be equal, got: '%s' instead of '%s'",
			lock_file_entry.version,
			expected_version,
		),
	)

	expected_resolution := "@aashutoshrathi/word-wrap@npm:1.2.6"
	testing.expect(
		t,
		lock_file_entry.resolution == expected_resolution,
		fmt.tprintf(
			"Expected lock file entry resolution to be equal, got: '%s' instead of '%s'",
			lock_file_entry.resolution,
			expected_resolution,
		),
	)

	expected_checksum := "ada901b9e7c680d190f1d012c84217ce0063d8f5c5a7725bb91ec3c5ed99bb7572680eb2d2938a531ccbaec39a95422fcd8a6b4a13110c7d98dd75402f66a0cd"
	testing.expect(
		t,
		lock_file_entry.checksum == expected_checksum,
		fmt.tprintf(
			"Expected lock file entry checksum to be equal, got: '%s' instead of '%s'",
			lock_file_entry.checksum,
			expected_checksum,
		),
	)

	expected_language_name := "node"
	testing.expect(
		t,
		lock_file_entry.language_name == expected_language_name,
		fmt.tprintf(
			"Expected lock file entry language name to be equal, got: '%s' instead of '%s'",
			lock_file_entry.language_name,
			expected_language_name,
		),
	)

	expected_link_type := LinkType.Soft
	testing.expect(
		t,
		lock_file_entry.link_type == expected_link_type,
		fmt.tprintf(
			"Expected lock file entry link type to be equal, got: %v instead of %v",
			lock_file_entry.link_type,
			expected_link_type,
		),
	)
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

parse_package_name :: proc(tokenizer: ^Tokenizer) -> (name: string, error: ParsingError) {
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

parse_version :: proc(tokenizer: ^Tokenizer) -> (version: string, error: ParsingError) {
	string := tokenizer_read_string_until(tokenizer, {"\r\n", "\n"}) or_return
	tokenizer_skip_any_of(tokenizer, {Newline{}})

	return string, nil
}

@(test, private = "package")
test_parse_version :: proc(t: ^testing.T) {
	context.logger = log.create_console_logger()

	tokenizer := tokenizer_create("1.2.3\n")
	version, error := parse_version(&tokenizer)
	testing.expect(
		t,
		error == nil,
		fmt.tprintf("Error is not nil for valid version line: %v\n", error),
	)

	testing.expect_value(t, version, "1.2.3")

	rest_of_source := tokenizer.source[tokenizer.position:]
	testing.expect_value(t, rest_of_source, "")
}

parse_resolution :: proc(tokenizer: ^Tokenizer) -> (version: string, error: ParsingError) {
	token := tokenizer_expect(tokenizer, String{}) or_return
	tokenizer_skip_any_of(tokenizer, {Newline{}})

	return token.token.(String).value, nil
}

@(test, private = "package")
test_parse_resolution :: proc(t: ^testing.T) {
	context.logger = log.create_console_logger()

	tokenizer := tokenizer_create(`"@babel/code-frame@npm:7.22.5"` + "\n")
	resolution, error := parse_resolution(&tokenizer)
	testing.expect(
		t,
		error == nil,
		fmt.tprintf("Error is not nil for valid resolution line: %v\n", error),
	)

	testing.expect_value(t, resolution, "@babel/code-frame@npm:7.22.5")

	rest_of_source := tokenizer.source[tokenizer.position:]
	testing.expect_value(t, rest_of_source, "")
}

parse_conditions :: proc(tokenizer: ^Tokenizer) -> (conditions: string, error: ParsingError) {
	conditions = tokenizer_read_string_until(tokenizer, {"\r\n", "\n"}) or_return
	tokenizer_skip_any_of(tokenizer, {Newline{}})

	return conditions, nil
}

parse_dependencies :: proc(
	tokenizer: ^Tokenizer,
	allocator := context.allocator,
) -> (
	dependencies: []Dependency,
	error: ParsingError,
) {
	reading_deps := true
	dependencies_slice := make([dynamic]Dependency, 0, 20, allocator) or_return

	for reading_deps {
		dependency, dependency_line_error := parse_dependency_line(tokenizer)
		if dependency_line_error != nil {
			reading_deps = false
			continue
		}

		append(&dependencies_slice, dependency)
	}

	return dependencies_slice[:], nil
}

@(test, private = "package")
test_parse_dependencies :: proc(t: ^testing.T) {
	context.logger = log.create_console_logger()

	dependencies1 := `    "@babel/highlight": 7.22.5` + "\n"
	tokenizer := tokenizer_create(dependencies1)
	dependencies, error := parse_dependencies(&tokenizer)
	testing.expect(
		t,
		error == nil,
		fmt.tprintf("Error is not nil for valid dependencies: %v\n", error),
	)

	testing.expect(
		t,
		slice.equal(dependencies, []Dependency{{name = "@babel/highlight", bounds = "7.22.5"}}),
		fmt.tprintf(
			"Parsed dependencies are not equal to expected dependencies, got: %v\n",
			dependencies,
		),
	)

	dependencies2 := `    "@ampproject/remapping": ^2.2.0
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
    debug: 4.1.0
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
				{name = "debug", bounds = "4.1.0"},
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

parse_peer_dependencies :: proc(
	tokenizer: ^Tokenizer,
	allocator := context.allocator,
) -> (
	dependencies: []Dependency,
	error: ParsingError,
) {
	reading_deps := true
	dependencies_slice := make([dynamic]Dependency, 0, 20, allocator) or_return

	for reading_deps {
		dependency, dependency_line_error := parse_dependency_line(tokenizer)
		if dependency_line_error != nil {
			reading_deps = false
			continue
		}

		append(&dependencies_slice, dependency)
	}

	return dependencies_slice[:], nil
}

@(test, private = "package")
test_parse_peer_dependencies :: proc(t: ^testing.T) {
	context.logger = log.create_console_logger()

	dependencies1 := `    "@swc/helpers": ^0.5.05` + "\n"
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
		`    react: ^16.8.0 || ^17.0.0 || ^18.0.0
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

parse_dependency_line :: proc(
	tokenizer: ^Tokenizer,
) -> (
	dependency: Dependency,
	error: ParsingError,
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
	tokenizer_expect(tokenizer, Colon{})
	tokenizer_expect(tokenizer, Space{})
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

@(test, private = "package")
test_parse_dependencies_meta :: proc(t: ^testing.T) {
	context.logger = log.create_console_logger()

	dependencies_meta1 :=
		`    "@esbuild/android-arm":
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

parse_checksum :: proc(tokenizer: ^Tokenizer) -> (checksum: string, error: ParsingError) {
	checksum = tokenizer_read_string_until(tokenizer, {"\r\n", "\n"}) or_return
	tokenizer_expect(tokenizer, Newline{}) or_return

	return checksum, nil
}

@(test, private = "package")
test_parse_checksum :: proc(t: ^testing.T) {
	context.logger = log.create_console_logger()

	checksum1 :=
		`7bf069aeceb417902c4efdaefab1f7b94adb7dea694a9aed1bda2edf4135348a080820529b1a300c6f8605740a00ca00c19b2d5e74b5dd489d99d8c11d5e56d1` +
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

parse_language_name :: proc(
	tokenizer: ^Tokenizer,
) -> (
	language_name: string,
	error: ParsingError,
) {
	language_name = tokenizer_read_string_until(tokenizer, {"\r\n", "\n"}) or_return
	tokenizer_expect(tokenizer, Newline{}) or_return

	return language_name, nil
}

@(test, private = "package")
test_parse_language_name :: proc(t: ^testing.T) {
	context.logger = log.create_console_logger()

	language_name1 := `node` + "\n"
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

parse_link_type :: proc(tokenizer: ^Tokenizer) -> (link_type: LinkType, error: ParsingError) {
	token := tokenizer_expect(tokenizer, LowerSymbol{}) or_return
	tokenizer_expect(tokenizer, Newline{}) or_return

	link_type_token := token.token.(LowerSymbol)

	if link_type_token.value == "hard" {
		return LinkType.Hard, nil
	} else if link_type_token.value == "soft" {
		return LinkType.Soft, nil
	} else {
		// TODO(gonz): this should be an error received from the tokenizer for a `expect_one_of` call or
		// something like that
		return link_type, Maybe(ExpectedOneOf)(
		ExpectedOneOf{
			expected = {LowerSymbol{value = "hard"}, LowerSymbol{value = "soft"}},
			actual = link_type_token,
		},
		)
	}
}

@(test, private = "package")
test_parse_link_type :: proc(t: ^testing.T) {
	context.logger = log.create_console_logger()

	link_type1 := `hard` + "\n"
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

	link_type2 := `soft` + "\n"
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

parse_binaries :: proc(
	tokenizer: ^Tokenizer,
	allocator := context.allocator,
) -> (
	binaries: []Binary,
	error: ParsingError,
) {
	reading_binaries := true
	binaries_slice := make([dynamic]Binary, 0, 5, allocator) or_return

	for reading_binaries {
		binary, binary_line_error := parse_binary_line(tokenizer)
		if binary_line_error != nil {
			reading_binaries = false
			continue
		}

		append(&binaries_slice, binary)
	}

	return binaries_slice[:], nil
}

@(test, private = "package")
test_parse_binaries :: proc(t: ^testing.T) {
	context.logger = log.create_console_logger()
	binaries1 := `    prettierd: bin/prettierd` + "\n"
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
		`    getstorybook: ./bin/index.js
    sb: ./bin/index.js
    third: bin/third.js` + "\n"
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

parse_binary_line :: proc(tokenizer: ^Tokenizer) -> (binary: Binary, error: ParsingError) {
	tokenizer_skip_string(tokenizer, "    ") or_return
	name := tokenizer_read_string_until(tokenizer, {":"}) or_return
	tokenizer_skip_any_of(tokenizer, {Colon{}, Space{}})
	path := tokenizer_read_string_until(tokenizer, {"\r\n", "\n"}) or_return
	tokenizer_expect(tokenizer, Newline{}) or_return

	return Binary{name = name, path = path}, nil
}
