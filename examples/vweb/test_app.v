module main

import vweb

const (
	Port = 8082
)

struct App {
pub mut:
	vweb vweb.Context // TODO embed
}

fn main() {
	vweb.run<App>(Port)
}

pub fn (app mut App) init() {
	app.vweb.handle_static('.')
}

pub fn (app mut App) json_endpoint() {
	app.vweb.json('{"a": 3}')
}

/*
pub fn (app mut App) index() {
	$vweb.html() 
}
*/

pub fn (app mut App) text() {
	app.vweb.text('hello world')
}

pub fn (app mut App) cookie() {
	app.vweb.text('Headers:')
	app.vweb.set_cookie('cookie', 'test')
	app.vweb.text(app.vweb.headers)
	app.vweb.text('Text: hello world')
}