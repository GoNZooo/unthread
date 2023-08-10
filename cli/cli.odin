package cli

import "core:slice"
import "core:testing"
import "core:strings"
import "core:reflect"
import "core:fmt"
import "core:mem"

DecodingInfo :: struct {
	field_name:     string,
	cli_short_name: string,
	cli_long_name:  string,
	field_type:     typeid,
}

CliTagValues :: struct {
	short: string,
	long:  string,
}

field_name_to_argument_name :: proc(name: string, allocator := context.allocator) -> string {
	return strings.to_camel_case(name, allocator)
}

@(test, private = "package")
test_field_name_to_argument_name :: proc(t: ^testing.T) {
	testing.expect_value(t, field_name_to_argument_name("foo"), "foo")
	testing.expect_value(t, field_name_to_argument_name("foo_bar"), "fooBar")
	testing.expect_value(t, field_name_to_argument_name("foo_bar_baz"), "fooBarBaz")
}

TestStruct :: struct {
	field_one:   string `cli:"1,field-one"`,
	field_two:   int `cli:"2,field-two"`,
	field_three: bool `cli:"3,field-three"`,
}

@(test, private = "package")
test_get_struct_field_names :: proc(t: ^testing.T) {
	names := reflect.struct_field_names(TestStruct)
	testing.expect(t, slice.equal(names, []string{"field_one", "field_two", "field_three"}))
}

cli_tag_values :: proc(tag: reflect.Struct_Tag) -> CliTagValues {
	values := strings.split(string(tag), ",")
	assert(
		len(values) == 2,
		fmt.tprintf("invalid `cli` tag format: '%s', should be `short-name,long-name`", tag),
	)

	return CliTagValues{short = values[0], long = values[1]}
}

struct_decoding_info :: proc(
	type: typeid,
	allocator := context.allocator,
) -> (
	decoding_info: []DecodingInfo,
	error: mem.Allocator_Error,
) {
	struct_fields := reflect.struct_fields_zipped(type)
	decoding_info = make([]DecodingInfo, len(struct_fields), allocator) or_return

	for f, i in struct_fields {
		tag := reflect.struct_tag_get(f.tag, "cli")
		tag_values := cli_tag_values(tag)
		decoding_info[i].field_name = f.name
		decoding_info[i].field_type = f.type.id
		decoding_info[i].cli_short_name = tag_values.short
		decoding_info[i].cli_long_name = tag_values.long
	}

	return decoding_info, nil
}

@(test, private = "package")
test_struct_field_info :: proc(t: ^testing.T) {
	decoding_info, allocator_error := struct_decoding_info(TestStruct)
	if allocator_error != nil {
		fmt.panicf("Allocator error: %s", allocator_error)
	}
	expected_info := []DecodingInfo{
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
			cli_short_name = "3",
			cli_long_name = "field-three",
		},
	}
	testing.expect(
		t,
		slice.equal(decoding_info, expected_info),
		fmt.tprintf(
			"Expected decoding info slices to be equal, got: %v instead of %v",
			decoding_info,
			expected_info,
		),
	)
}
