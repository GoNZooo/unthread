package cli

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
	field_name:     string,
	cli_short_name: string,
	cli_long_name:  string,
	field_type:     typeid,
}

CliTagValues :: struct {
	short: string,
	long:  string,
}

TestStruct :: struct {
	field_one:   string `cli:"1,field-one"`,
	field_two:   int `cli:"2,field-two"`,
	field_three: bool `cli:"field-three"`,
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
		cli_info.fields[i].field_name = f.name
		cli_info.fields[i].field_type = f.type.id
		cli_info.fields[i].cli_short_name = tag_values.short
		cli_info.fields[i].cli_long_name = tag_values.long
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
			field_name = "field_one",
			field_type = string,
			cli_short_name = "1",
			cli_long_name = "field-one",
		},
		{
			field_name = "field_two",
			field_type = int,
			cli_short_name = "2",
			cli_long_name = "field-two",
		},
		{
			field_name = "field_three",
			field_type = bool,
			cli_short_name = "",
			cli_long_name = "field-three",
		},
		{field_name = "no_tag", field_type = f32, cli_short_name = "", cli_long_name = "no-tag"},
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

cli_tag_values :: proc(field_name: string, tag: reflect.Struct_Tag) -> CliTagValues {
	tag_value := string(tag)
	if tag_value == "" {
		long_name := field_name_to_long_name(field_name)

		return CliTagValues{long = long_name}
	}
	values := strings.split(tag_value, ",")
	switch len(values) {
	case 1:
		return CliTagValues{long = values[0]}
	case 2:
		assert(
			len(values[0]) == 1,
			fmt.tprintf("invalid `cli` tag format: '%s', short name should be one character", tag),
		)

		return CliTagValues{short = values[0], long = values[1]}
	case:
		fmt.panicf("invalid `cli` tag format: '%s', should be `n,name`", tag)
	}
}
