// Copyright (c) 2019 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.

module sync

//[init_with=new_waitgroup] // TODO: implement support for init_with struct attribute, and disallow WaitGroup{} from outside the sync.new_waitgroup() function.
pub struct WaitGroup {
mut:
	mu Mutex
	active int
}

pub fn new_waitgroup() WaitGroup {
	mut w := WaitGroup{}
	w.mu = sync.new_mutex()
	return w
}

pub fn (wg mut WaitGroup) add(delta int) {
	wg.mu.lock()
	wg.active += delta
	wg.mu.unlock()
	if wg.active < 0 {
		panic('Negative number of jobs in waitgroup')
	}
}

pub fn (wg mut WaitGroup) done() {
	wg.add(-1)
}

pub fn (wg mut WaitGroup) wait() {
	for wg.active > 0 {
		// waiting
	}
}

