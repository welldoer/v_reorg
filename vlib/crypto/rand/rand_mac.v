// Copyright (c) 2019 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.

module rand

#flag darwin -framework Security

// import const (
// 	kSecRandomDefault
// 	errSecSuccess
// )

const (
	kSecRandomDefault = 0
	errSecSuccess     = 0
)

pub fn read(bytes_needed int) ?[]byte {
	mut buffer := malloc(bytes_needed)
	status := C.SecRandomCopyBytes(kSecRandomDefault, bytes_needed, buffer)
	if status != errSecSuccess {
		return ReadError
	}
	return c_array_to_bytes_tmp(bytes_needed, buffer)
}
