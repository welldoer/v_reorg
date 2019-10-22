// Copyright (c) 2019 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.

import crypto.rand

fn test_crypto_rand() {
	no_bytes := 100
	max_percentage_diff := 20

	r1 := rand.read(no_bytes) or {
		assert false
		return
	}
	assert r1.len == no_bytes
	r2 := rand.read(no_bytes) or {
		assert false
		return
	}
	assert r2.len == no_bytes
	
	mut difference := 0
	for i, _ in r1 {
		difference += if r1[i] == r2[i] {0} else {1}
	}

	diff_percentage := f32(100) - (f32(difference)/f32(no_bytes)*100)

	assert diff_percentage <= max_percentage_diff
}
