import os
import time as t
import crypto.sha256 as s2

import (
	math
	log as l
	crypto.sha512 as s5
)

fn test_import() {
	assert os.O_RDONLY == os.O_RDONLY &&
		t.month_days[0] == t.month_days[0] &&
		s2.size == s2.size &&
		math.pi == math.pi &&
		l.INFO == l.INFO &&
		s5.size == s5.size
}
