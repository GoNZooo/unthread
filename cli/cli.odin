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

field_name_to_long_name :: proc(name: string, allocator := context.allocator) -> string {
	return strings.to_kebab_case(name, allocator)
}

@(test, private = "package")
test_field_name_to_long_name :: proc(t: ^testing.T) {
	testing.expect_value(t, field_name_to_long_name("foo"), "foo")
	testing.expect_value(t, field_name_to_long_name("foo_bar"), "foo-bar")
	testing.expect_value(t, field_name_to_long_name("foo_bar_baz"), "foo-bar-baz")
}

TestStruct :: struct {
	field_one:   string `cli:"1,field-one"`,
	field_two:   int `cli:"2,field-two"`,
	field_three: bool `cli:"field-three"`,
	no_tag:      f32,
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
		fmt.panicf("invalid `cli` tag format: '%s', should be `short-name,long-name`", tag)
	}
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
		tag_values := cli_tag_values(f.name, tag)
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
			cli_short_name = "",
			cli_long_name = "field-three",
		},
		{field_name = "no_tag", field_type = f32, cli_short_name = "", cli_long_name = "no-tag"},
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
