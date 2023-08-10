package cli

import "core:testing"
import "core:strings"

field_name_to_argument_name :: proc(name: string, allocator := context.allocator) -> string {
	return strings.to_camel_case(name, allocator)
}

@(test, private = "package")
test_field_name_to_argument_name :: proc(t: ^testing.T) {
	testing.expect_value(t, field_name_to_argument_name("foo"), "foo")
	testing.expect_value(t, field_name_to_argument_name("foo_bar"), "fooBar")
	testing.expect_value(t, field_name_to_argument_name("foo_bar_baz"), "fooBarBaz")
}
