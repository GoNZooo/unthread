package unthread

import "core:encoding/json"

PackageJson :: struct {
	name:             string,
	version:          string,
	description:      string,
	main:             string,
	scripts:          map[string]string,
	resolutions:      map[string]string,
	dependencies:     map[string]string,
	devDependencies:  map[string]string,
	peerDependencies: map[string]string,
	packageManager:   string,
}

read_package_json_file :: proc(
	data: []byte,
) -> (
	package_json: PackageJson,
	error: json.Unmarshal_Error,
) {
	json.unmarshal(data, &package_json) or_return

	return package_json, nil
}
