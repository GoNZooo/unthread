package cli

import "core:intrinsics"
import "core:log"
import "core:slice"
import "core:testing"
import "core:strings"
import "core:reflect"
import "core:fmt"
import "core:mem"
import "core:strconv"

StructCliInfo :: struct {
	type:   typeid,
	fields: []FieldCliInfo,
}

FieldCliInfo :: struct {
	name:           string,
	cli_short_name: string,
	cli_long_name:  string,
	type:           typeid,
	offset:         uintptr,
	required:       bool,
}

CliTagValues :: struct {
	short:    string,
	long:     string,
	required: bool,
}

TestStruct :: struct {
	field_one:   string `cli:"1,field-one"`,
	field_two:   int `cli:"2,field-two/required"`,
	field_three: bool `cli:"field-three/required"`,
	no_tag:      f32,
}

CliParseError :: union {
	mem.Allocator_Error,
	CliValueParseError,
}

CliValueParseError :: struct {
	value:   string,
	type:    typeid,
	message: string,
}

parse_arguments_as_type :: proc(
	arguments: []string,
	$T: typeid,
	allocator := context.allocator,
) -> (
	value: T,
	error: CliParseError,
) {
	when T == string {
		return arguments[0], nil
	} else when T == int {
		i, ok := strconv.parse_int(arguments[0], 10)
		if !ok {
			return 0,
				CliValueParseError{
					value = arguments[0],
					type = T,
					message = fmt.tprintf("invalid integer value: '%s'", arguments[0]),
				}
		}

		return i, nil
	} else when T == f32 {
		f, ok := strconv.parse_f32(arguments[0])
		if !ok {
			return 0,
				CliValueParseError{
					value = arguments[0],
					type = T,
					message = fmt.tprintf("invalid float value: '%s'", arguments[0]),
				}
		}

		return f, nil
	} else when T == f64 {
		f, ok := strconv.parse_f64(arguments[0])
		if !ok {
			return 0,
				CliValueParseError{
					value = arguments[0],
					type = T,
					message = fmt.tprintf("invalid float value: '%s'", arguments[0]),
				}
		}

		return f, nil
	} else when T == bool {
		if arguments[0] == "true" {
			return true, nil
		} else if arguments[0] == "false" {
			return false, nil
		} else {
			return false,
				CliValueParseError{
					value = arguments[0],
					type = T,
					message = fmt.tprintf("invalid boolean value: '%s'", arguments[0]),
				}
		}
	}

	if reflect.is_struct(type_info_of(T)) {
		cli_info := struct_decoding_info(T, allocator) or_return
		v := parse_arguments_with_struct_cli_info(T, cli_info, arguments, allocator) or_return

		return v, nil
	}

	return value, nil
}

@(test, private = "package")
test_parse_arguments_as_type :: proc(t: ^testing.T) {
	context.logger = log.create_console_logger()

	s, error := parse_arguments_as_type({"foo"}, string, context.allocator)
	testing.expect_value(t, error, nil)
	testing.expect_value(t, s, "foo")

	i: int
	i, error = parse_arguments_as_type({"123"}, int, context.allocator)
	testing.expect_value(t, error, nil)
	testing.expect_value(t, i, 123)

	float32: f32
	float32, error = parse_arguments_as_type({"123.456"}, f32, context.allocator)
	testing.expect_value(t, error, nil)
	testing.expect_value(t, float32, 123.456)

	float64: f64
	float64, error = parse_arguments_as_type({"123.456"}, f64, context.allocator)
	testing.expect_value(t, error, nil)
	testing.expect_value(t, float64, 123.456)

	b: bool
	b, error = parse_arguments_as_type({"true"}, bool, context.allocator)
	testing.expect_value(t, error, nil)
	testing.expect_value(t, b, true)

	ts: TestStruct
	ts, error = parse_arguments_as_type(
		{"-2=123", "--field-one=foo", "--no-tag=123.456", "--field-three"},
		TestStruct,
		context.allocator,
	)
	testing.expect_value(t, error, nil)
	testing.expect_value(
		t,
		ts,
		TestStruct{field_one = "foo", field_two = 123, field_three = true, no_tag = 123.456},
	)
}

make_argument_map :: proc(
	arguments: []string,
	allocator := context.allocator,
) -> (
	result: map[string]string,
	error: CliParseError,
) {
	result = make(map[string]string, 0, allocator) or_return

	for argument in arguments {
		without_dash := strings.trim_left(argument, "-")
		split_on_equals := strings.split(without_dash, "=", allocator) or_return
		if len(split_on_equals) == 1 {
			result[split_on_equals[0]] = ""
		} else if len(split_on_equals) == 2 {
			result[split_on_equals[0]] = split_on_equals[1]
		} else {
			error = CliValueParseError {
				message = fmt.tprintf("invalid flag argument: '%s'", argument),
			}

			return result, error
		}
	}

	return result, nil
}

@(test, private = "package")
test_make_argument_map :: proc(t: ^testing.T) {
	context.logger = log.create_console_logger()

	arguments := []string{"-2=123", "--field-one=foo", "--no-tag=123.456", "--field-three"}
	result, error := make_argument_map(arguments, context.allocator)
	testing.expect_value(t, error, nil)
	testing.expect_value(t, result["2"], "123")
	testing.expect_value(t, result["field-one"], "foo")
	testing.expect_value(t, result["no-tag"], "123.456")
	testing.expect_value(t, result["field-three"], "")
}

parse_arguments_with_struct_cli_info :: proc(
	$T: typeid,
	cli_info: StructCliInfo,
	arguments: []string,
	allocator := context.allocator,
) -> (
	result: T,
	error: CliParseError,
) {
	assert(T == cli_info.type, "cli_info.type must be equal to T")

	value: T
	value_bytes: [size_of(T)]byte
	argument_map := make_argument_map(arguments, context.allocator) or_return
	for field in cli_info.fields {
		map_value: string
		has_value: bool
		map_value, has_value = argument_map[field.cli_long_name]
		if !has_value && field.cli_short_name != "" {
			map_value, has_value = argument_map[field.cli_short_name]
		}
		if has_value && field.type == bool && map_value == "" {
			map_value = "true"
		}
		if !has_value && field.required {
			error = CliValueParseError {
				message = fmt.tprintf("missing required argument: '%s'", field.cli_long_name),
			}

			return value, error
		}
		parsed_value := parse_argument_as_type(map_value, field.type, allocator) or_return
		copy(value_bytes[field.offset:], parsed_value)
	}

	value = mem.reinterpret_copy(T, raw_data(value_bytes[:]))

	return value, nil
}

@(test, private = "package")
test_parse_arguments_with_struct_cli_info :: proc(t: ^testing.T) {
	context.logger = log.create_console_logger()

	arguments := []string{"-2=123", "--field-one=foo", "--no-tag=123.456", "--field-three"}
	ts_cli_info, cli_info_error := struct_decoding_info(TestStruct, context.allocator)
	testing.expect_value(t, cli_info_error, nil)
	ts, error := parse_arguments_with_struct_cli_info(
		TestStruct,
		ts_cli_info,
		arguments,
		context.allocator,
	)
	testing.expect_value(t, error, nil)
	testing.expect_value(
		t,
		ts,
		TestStruct{field_one = "foo", field_two = 123, field_three = true, no_tag = 123.456},
	)
}

parse_argument_as_type :: proc(
	argument: string,
	t: typeid,
	allocator := context.allocator,
) -> (
	result: []byte,
	error: CliParseError,
) {
	if t == string {
		return mem.any_to_bytes(argument), nil
	} else if t == int {
		i, ok := strconv.parse_int(argument, 10)
		if !ok {
			error = CliValueParseError {
				message = fmt.tprintf("invalid integer: '%s'", argument),
			}

			return result, error
		}

		return mem.any_to_bytes(i), nil
	} else if t == f32 {
		f, ok := strconv.parse_f32(argument)
		if !ok {
			error = CliValueParseError {
				message = fmt.tprintf("invalid float: '%s'", argument),
			}

			return result, error
		}

		return mem.any_to_bytes(f), nil
	} else if t == f64 {
		f, ok := strconv.parse_f64(argument)
		if !ok {
			error = CliValueParseError {
				message = fmt.tprintf("invalid float: '%s'", argument),
			}

			return result, error
		}

		return mem.any_to_bytes(f), nil
	} else if t == bool {
		if argument == "true" {
			return mem.any_to_bytes(true), nil
		} else if argument == "false" {
			return mem.any_to_bytes(false), nil
		} else {
			error = CliValueParseError {
				message = fmt.tprintf("invalid boolean: '%s'", argument),
			}

			return result, error
		}
	} else {
		error = CliValueParseError {
			message = fmt.tprintf("unsupported type: %v", t),
		}

		return result, error
	}
}

@(test, private = "package")
test_parse_argument_as_type :: proc(t: ^testing.T) {
	context.logger = log.create_console_logger()

	tid: typeid

	tid = string
	bytes, error := parse_argument_as_type("foo", tid, context.allocator)
	s := mem.reinterpret_copy(string, raw_data(bytes))
	testing.expect_value(t, error, nil)
	testing.expect(t, s == "foo", fmt.tprintf("Expected 'foo', got '%s'", s))

	tid = int
	bytes, error = parse_argument_as_type("123", tid, context.allocator)
	i := mem.reinterpret_copy(int, raw_data(bytes))
	testing.expect_value(t, error, nil)
	testing.expect(t, i == 123, fmt.tprintf("Expected 123, got %d", i))

	tid = f32
	bytes, error = parse_argument_as_type("123.456", tid, context.allocator)
	float32 := mem.reinterpret_copy(f32, raw_data(bytes))
	testing.expect_value(t, error, nil)
	testing.expect(t, float32 == 123.456, fmt.tprintf("Expected 123.456, got %f", float32))

	tid = f64
	bytes, error = parse_argument_as_type("123.456", tid, context.allocator)
	float64 := mem.reinterpret_copy(f64, raw_data(bytes))
	testing.expect_value(t, error, nil)
	testing.expect(t, float64 == 123.456, fmt.tprintf("Expected 123.456, got %f", float64))

	tid = bool
	bytes, error = parse_argument_as_type("true", tid, context.allocator)
	boolean := mem.reinterpret_copy(bool, raw_data(bytes))
	testing.expect_value(t, error, nil)
	testing.expect(
		t,
		boolean,
		fmt.tprintf("Expected true, got %v (%v)", boolean, typeid_of(type_of(boolean))),
	)
}

struct_decoding_info :: proc(
	type: typeid,
	allocator := context.allocator,
) -> (
	cli_info: StructCliInfo,
	error: mem.Allocator_Error,
) {
	struct_fields := reflect.struct_fields_zipped(type)
	cli_info.fields = make([]FieldCliInfo, len(struct_fields), allocator) or_return

	for f, i in struct_fields {
		tag := reflect.struct_tag_get(f.tag, "cli")
		tag_values := cli_tag_values(f.name, tag)
		cli_info.fields[i].name = f.name
		cli_info.fields[i].type = f.type.id
		cli_info.fields[i].cli_short_name = tag_values.short
		cli_info.fields[i].cli_long_name = tag_values.long
		cli_info.fields[i].offset = f.offset
		cli_info.fields[i].required = tag_values.required
	}

	cli_info.type = type

	return cli_info, nil
}

@(test, private = "package")
test_struct_field_info :: proc(t: ^testing.T) {
	cli_info, allocator_error := struct_decoding_info(TestStruct)
	if allocator_error != nil {
		fmt.panicf("Allocator error: %s", allocator_error)
	}
	fields := []FieldCliInfo{
		{
			name = "field_one",
			type = string,
			cli_short_name = "1",
			cli_long_name = "field-one",
			offset = 0,
			required = false,
		},
		{
			name = "field_two",
			type = int,
			cli_short_name = "2",
			cli_long_name = "field-two",
			offset = 16,
			required = true,
		},
		{
			name = "field_three",
			type = bool,
			cli_short_name = "",
			cli_long_name = "field-three",
			offset = 24,
			required = true,
		},
		{
			name = "no_tag",
			type = f32,
			cli_short_name = "",
			cli_long_name = "no-tag",
			offset = 28,
			required = false,
		},
	}
	testing.expect_value(t, cli_info.type, TestStruct)
	testing.expect(
		t,
		slice.equal(cli_info.fields, fields),
		fmt.tprintf(
			"Expected CLI info field slices to be equal, got: %v instead of %v",
			cli_info,
			fields,
		),
	)
}

field_name_to_long_name :: proc(name: string, allocator := context.allocator) -> string {
	return strings.to_kebab_case(name, allocator)
}

@(test, private = "package")
test_field_name_to_long_name :: proc(t: ^testing.T) {
	testing.expect_value(t, field_name_to_long_name("foo"), "foo")
	testing.expect_value(t, field_name_to_long_name("foo_bar"), "foo-bar")
	testing.expect_value(t, field_name_to_long_name("foo_bar_baz"), "foo-bar-baz")
}

cli_tag_values :: proc(
	field_name: string,
	tag: reflect.Struct_Tag,
	allocator := context.allocator,
) -> CliTagValues {
	tag_value := string(tag)
	if tag_value == "" {
		long_name := field_name_to_long_name(field_name)

		return CliTagValues{long = long_name}
	}
	keywords: []string
	keyword_split := strings.split(tag_value, "/")
	tag_value = keyword_split[0]
	if len(keyword_split) == 2 {
		keywords = strings.split(keyword_split[1], ",")
		tag_value = keyword_split[0]
	}
	values := strings.split(tag_value, ",")
	required := len(keywords) > 0 && keywords[0] == "required"
	switch len(values) {
	case 1:
		return CliTagValues{long = values[0], required = required}
	case 2:
		assert(
			len(values[0]) == 1,
			fmt.tprintf("invalid `cli` tag format: '%s', short name should be one character", tag),
		)

		return CliTagValues{short = values[0], long = values[1], required = required}
	case:
		fmt.panicf("invalid `cli` tag format: '%s', should be `n,name`", tag)
	}
}
