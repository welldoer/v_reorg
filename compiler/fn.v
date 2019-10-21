// Copyright (c) 2019 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.

module main

import strings

const (
	MaxLocalVars = 50
)

struct Fn {
	// addr int
mut:
	name          string
	mod           string
	local_vars    []Var
	var_idx       int
	args          []Var
	is_interface  bool
	// called_fns    []string
	// idx           int
	scope_level   int
	typ           string // return type
	is_c          bool
	receiver_typ  string
	is_public     bool
	is_method     bool
	returns_error bool
	is_decl       bool // type myfn fn(int, int)
	defer_text    []string
	//gen_types []string
}

fn (f &Fn) find_var(name string) Var {
	for i in 0 .. f.var_idx {
		if f.local_vars[i].name == name {
			return f.local_vars[i]
		}
	}
	return Var{}
}


fn (f mut Fn) open_scope() {
	f.defer_text << ''
	f.scope_level++
}

fn (f mut Fn) close_scope() {
	f.scope_level--
	f.defer_text = f.defer_text.left(f.scope_level + 1)
}

fn (f &Fn) mark_var_used(v Var) {
	for i, vv in f.local_vars {
		if vv.name == v.name {
			//mut ptr := &f.local_vars[i]
			//ptr.is_used = true
			f.local_vars[i].is_used = true
			return
		}
	}
}

fn (f &Fn) mark_var_changed(v Var) {
	for i, vv in f.local_vars {
		if vv.name == v.name {
			//mut ptr := &f.local_vars[i]
			//ptr.is_used = true
			f.local_vars[i].is_changed = true
			// return
		}
	}
}

fn (f &Fn) known_var(name string) bool {
	v := f.find_var(name)
	return v.name.len > 0
}

fn (f mut Fn) register_var(v Var) {
	new_var := {v | scope_level: f.scope_level}
	// Expand the array
	if f.var_idx >= f.local_vars.len {
		f.local_vars << new_var
	}
	else {
		f.local_vars[f.var_idx] = new_var
	}
	f.var_idx++
}

fn (f mut Fn) clear_vars() {
	f.var_idx = 0
	f.local_vars = []Var
}

// vlib header file?
fn (p mut Parser) is_sig() bool {
	return (p.pref.build_mode == .default_mode || p.pref.build_mode == .build) &&
	(p.file_path.contains(ModPath))
}

fn new_fn(mod string, is_public bool) *Fn {
	return &Fn {
		mod: mod
		local_vars: [Var{}		; MaxLocalVars]
		is_public: is_public
	}
}

// Function signatures are added to the top of the .c file in the first run.
fn (p mut Parser) fn_decl() {
	p.fgen('fn ')
	//defer { p.fgenln('\n') }
	is_pub := p.tok == .key_pub
	is_live := p.attr == 'live' && !p.pref.is_so  && p.pref.is_live
	if p.attr == 'live' &&  p.first_pass() && !p.pref.is_live && !p.pref.is_so {
		println('INFO: run `v -live program.v` if you want to use [live] functions')
	}
	if is_pub {
		p.next()
	}
	p.returns = false
	//p.gen('/* returns $p.returns */')
	p.next()
	mut f := new_fn(p.mod, is_pub)
	// Method receiver
	mut receiver_typ := ''
	if p.tok == .lpar {
		f.is_method = true
		p.check(.lpar)
		receiver_name := p.check_name()
		is_mut := p.tok == .key_mut
		is_amp := p.tok == .amp
		if is_mut || is_amp {
			p.check_space(p.tok)
		}
		receiver_typ = p.get_type()
		T := p.table.find_type(receiver_typ)
		if T.cat == .interface_ {
			p.error('invalid receiver type `$receiver_typ` (`$receiver_typ` is an interface)')
		}
		// Don't allow modifying types from a different module
		if !p.first_pass() && !p.builtin_mod && T.mod != p.mod {
			println('T.mod=$T.mod')
			println('p.mod=$p.mod')
			p.error('cannot define new methods on non-local type `$receiver_typ`')
		}
		// (a *Foo) instead of (a mut Foo) is a common mistake
		if !p.builtin_mod && receiver_typ.contains('*') {
			t := receiver_typ.replace('*', '')
			p.error('use `($receiver_name mut $t)` instead of `($receiver_name *$t)`')
		}
		f.receiver_typ = receiver_typ
		if is_mut || is_amp {
			receiver_typ += '*'
		}
		p.check(.rpar)
		p.fspace()
		receiver := Var {
			name: receiver_name
			is_arg: true
			typ: receiver_typ
			is_mut: is_mut
			ref: is_amp
			ptr: is_mut
			line_nr: p.scanner.line_nr
		}
		f.args << receiver
		f.register_var(receiver)
	}
	if p.tok == .plus || p.tok == .minus || p.tok == .mul {
		f.name = p.tok.str()
		p.next()
	}
	else {
		f.name = p.check_name()
	}
	// C function header def? (fn C.NSMakeRect(int,int,int,int))
	is_c := f.name == 'C' && p.tok == .dot
	// Just fn signature? only builtin.v + default build mode
	// is_sig := p.builtin_mod && p.pref.build_mode == default_mode
	// is_sig := p.pref.build_mode == default_mode && (p.builtin_mod || p.file.contains(LANG_TMP))
	is_sig := p.is_sig()
	// println('\n\nfn decl !!is_sig=$is_sig name=$f.name $p.builtin_mod')
	if is_c {
		p.check(.dot)
		f.name = p.check_name()
		f.is_c = true
	}
	else if !p.pref.translated && !p.file_path.contains('view.v') {
		if contains_capital(f.name) {
			p.error('function names cannot contain uppercase letters, use snake_case instead')
		}
		if f.name.contains('__') {
			p.error('function names cannot contain double underscores, use single underscores instead')
		}
	}
	// simple_name := f.name
	// println('!SIMP.le=$simple_name')
	// user.register() => User_register()
	has_receiver := receiver_typ.len > 0
	if receiver_typ != '' {
		// f.name = '${receiver_typ}_${f.name}'
	}
	// full mod function name
	// os.exit ==> os__exit()
	if !is_c && !p.builtin_mod && p.mod != 'main' && receiver_typ.len == 0 {
		f.name = p.prepend_mod(f.name)
	}
	if p.first_pass() && p.table.known_fn(f.name) && receiver_typ.len == 0 {
		existing_fn := p.table.find_fn(f.name)
		// This existing function could be defined as C decl before (no body), then we don't need to throw an erro
		if !existing_fn.is_decl {
			p.error('redefinition of `$f.name`')
		}
	}
	// Generic?
	mut is_generic := false
	if p.tok == .lt {
		is_generic = true
		p.next()
		gen_type := p.check_name()
		if gen_type != 'T' {
			p.error('only `T` is allowed as a generic type for now')
		}
		p.check(.gt)
		if p.first_pass() {
			p.table.register_generic_fn(f.name)
		}  else {
			//gen_types := p.table.fn_gen_types(f.name)
			//println(gen_types)
		}
	}
	// Args (...)
	p.fn_args(mut f)
	// Returns an error?
	if p.tok == .not {
		p.next()
		f.returns_error = true
	}
	// Returns a type?
	mut typ := 'void'
	if p.tok == .name || p.tok == .mul || p.tok == .amp || p.tok == .lsbr ||
	p.tok == .question {
		p.fgen(' ')
		// TODO In
		// if p.tok in [ .name, .mul, .amp, .lsbr ] {
		typ = p.get_type()
	}
	// Translated C code can have empty functions (just definitions)
	is_fn_header := !is_c && !is_sig && (p.pref.translated || p.pref.is_test) &&	p.tok != .lcbr
	if is_fn_header {
		f.is_decl = true
	}
	// { required only in normal function declarations
	if !is_c && !is_sig && !is_fn_header {
		p.fgen(' ')
		p.check(.lcbr)
	}
	// Register ?option type
	if typ.starts_with('Option_') {
		p.cgen.typedefs << 'typedef Option $typ;'
	}
	// Register function
	f.typ = typ
	mut str_args := f.str_args(p.table)
	// Special case for main() args
	if f.name == 'main' && !has_receiver {
		if str_args != '' || typ != 'void' {
			p.error('fn main must have no arguments and no return values')
		}
		typ = 'int'
		str_args = 'int argc, char** argv'
	}
	dll_export_linkage := if p.os == .msvc && p.attr == 'live' && p.pref.is_so {
		'__declspec(dllexport) '
	} else if p.attr == 'inline' {
		'static inline '
	} else {
		''
	}
	if !p.is_vweb {
		p.cur_fn = f
	}
	// Generate `User_register()` instead of `register()`
	// Internally it's still stored as "register" in type User
	mut fn_name_cgen := p.table.cgen_name(f)
	// Start generation of the function body
	skip_main_in_test := f.name == 'main' && p.pref.is_test
	if !is_c && !is_live && !is_sig && !is_fn_header && !skip_main_in_test {
		if p.pref.obfuscate {
			p.genln('; // $f.name')
		}
		// Generate this function's body for all generic types
		if is_generic {
			gen_types := p.table.fn_gen_types(f.name)
			// Remember current scanner position, go back here for each type
			// TODO remove this once tokens are cached in `new_parser()`
			cur_pos := p.scanner.pos
			cur_tok := p.tok
			cur_lit := p.lit
			for gen_type in gen_types {
				p.genln('$dll_export_linkage$typ ${fn_name_cgen}_$gen_type($str_args) {')
				p.genln('// T start $p.pass ${p.strtok()}')
				p.cur_gen_type = gen_type // TODO support more than T
				p.statements()
				p.scanner.pos = cur_pos
				p.tok  = cur_tok
				p.lit = cur_lit
			}
		}
		else {
			p.genln('$dll_export_linkage$typ $fn_name_cgen($str_args) {')
		}
	}
	if is_fn_header {
		p.genln('$typ $fn_name_cgen($str_args);')
		p.fgenln('')
	}
	if is_c {
		p.fgenln('\n')
	}
	// Register the method
	if receiver_typ != '' {
		mut receiver_t := p.table.find_type(receiver_typ)
		// No such type yet? It could be defined later. Create a new type.
		// struct declaration later will modify it instead of creating a new one.
		if p.first_pass() && receiver_t.name == '' {
			// println('fn decl !!!!!!! REG PH $receiver_typ')
			p.table.register_type2(Type {
				name: receiver_typ.replace('*', '')
				mod: p.mod
				is_placeholder: true
			})
		}
		// f.idx = p.table.fn_cnt
		receiver_t.add_method(f)
	}
	else {
		// println('register_fn typ=$typ isg=$is_generic')
		p.table.register_fn(f)
	}
	if is_sig || p.first_pass() || is_live || is_fn_header || skip_main_in_test {
		// First pass? Skip the body for now
		// Look for generic calls.
		if !is_sig && !is_fn_header {
			mut opened_scopes := 0
			mut closed_scopes := 0
			mut temp_scanner_pos := 0
			for {
				if p.tok == .lcbr {
					opened_scopes++
				}
				if p.tok == .rcbr {
					closed_scopes++
				}
				p.next()
				// find `foo<Bar>()` in function bodies and register generic types
				// TODO remove this once tokens are cached
				if p.tok == .gt && p.prev_tok == .name  && p.prev_tok2 == .lt &&
					p.scanner.text[p.scanner.pos-1] != `T` {
					temp_scanner_pos = p.scanner.pos
					p.scanner.pos -= 3
					for p.scanner.pos > 0 && (is_name_char(p.scanner.text[p.scanner.pos]) ||
						p.scanner.text[p.scanner.pos] == `.`  ||
						p.scanner.text[p.scanner.pos] == `<` ) {
						p.scanner.pos--
					}
					p.scanner.pos--
					p.next()
					// Run the function in the firt pass to register the generic type
					p.name_expr()
					p.scanner.pos = temp_scanner_pos
				}
				if p.tok.is_decl() && !(p.prev_tok == .dot && p.tok == .key_type) {
					break
				}
				// fn body ended, and a new fn attribute declaration like [live] is starting?
				if closed_scopes > opened_scopes && p.prev_tok == .rcbr {
					if p.tok == .lsbr {
						break
					}
				}
			}
		}
		// Live code reloading? Load all fns from .so
		if is_live && p.first_pass() && p.mod == 'main' {
			//println('ADDING SO FN $fn_name_cgen')
			p.cgen.so_fns << fn_name_cgen
			fn_name_cgen = '(* $fn_name_cgen )'
		}
		// Function definition that goes to the top of the C file.
		mut fn_decl := '$dll_export_linkage$typ $fn_name_cgen($str_args)'
		if p.pref.obfuscate {
			fn_decl += '; // $f.name'
		}
		// Add function definition to the top
		if !is_c && f.name != 'main' && p.first_pass() {
			// TODO hack to make Volt compile without -embed_vlib
			if f.name == 'darwin__nsstring' && p.pref.build_mode == .default_mode {
				return
			}
			p.cgen.fns << fn_decl + ';'
		}
		return
	}
	if p.attr == 'live' && p.pref.is_so {
		//p.genln('// live_function body start')
		p.genln('pthread_mutex_lock(&live_fn_mutex);')
	}
	if f.name == 'main' || f.name == 'WinMain' {
		p.genln('init_consts();')
		if p.table.imports.contains('os') {
			if f.name == 'main' {
				p.genln('os__args = os__init_os_args(argc, argv);')
			}
			else if f.name == 'WinMain' {
				p.genln('os__args = os__parse_windows_cmd_line(pCmdLine);')
			}
		}
		// We are in live code reload mode, call the .so loader in bg
		if p.pref.is_live {
			file_base := p.file_path.replace('.v', '')
			if p.os != .windows && p.os != .msvc {
				so_name := file_base + '.so'
				p.genln('
load_so("$so_name");
pthread_t _thread_so;
pthread_create(&_thread_so , NULL, &reload_so, NULL); ')
			} else {
				so_name := file_base + if p.os == .msvc {'.dll'} else {'.so'}
				p.genln('
live_fn_mutex = CreateMutexA(0, 0, 0);
load_so("$so_name");
unsigned long _thread_so;
_thread_so = CreateThread(0, 0, (LPTHREAD_START_ROUTINE)&reload_so, 0, 0, 0);
				')
			}
		}
		if p.pref.is_test && !p.scanner.file_path.contains('/volt') {
			p.error('tests cannot have function `main`')
		}
	}
	// println('is_c=$is_c name=$f.name')
	if is_c || is_sig || is_fn_header {
		// println('IS SIG .key_returnING tok=${p.strtok()}')
		return
	}
	// Profiling mode? Start counting at the beginning of the function (save current time).
	if p.pref.is_prof && f.name != 'main' && f.name != 'time__ticks' {
		p.genln('double _PROF_START = time__ticks();//$f.name')
		cgen_name := p.table.cgen_name(f)
		f.defer_text[f.scope_level] = '  ${cgen_name}_time += time__ticks() - _PROF_START;'
	}
	if is_generic {
		// Don't need to generate body for the actual generic definition
		p.cgen.nogen = true
	}
	p.statements_no_rcbr()
	p.cgen.nogen = false
	// Print counting result after all statements in main
	if p.pref.is_prof && f.name == 'main' {
		p.genln(p.print_prof_counters())
	}
	// Counting or not, always need to add defer before the end
	if !p.is_vweb {
		p.genln(f.defer_text[f.scope_level])
	}
	if typ != 'void' && !p.returns && f.name != 'main' && f.name != 'WinMain' {
		p.error('$f.name must return "$typ"')
	}
	if p.attr == 'live' && p.pref.is_so {
		//p.genln('// live_function body end')
		p.genln('pthread_mutex_unlock(&live_fn_mutex);')
	}
	// {} closed correctly? scope_level should be 0
	if p.mod == 'main' {
		// println(p.cur_fn.scope_level)
	}
	if p.cur_fn.scope_level > 2 {
		// p.error('unclosed {')
	}
	// Make sure all vars in this function are used (only in main for now)
	// if p.builtin_mod || p.mod == 'os' ||p.mod=='http'{
	if p.mod != 'main' {
		if !is_generic {
			p.genln('}')
		}
		return
	}
	p.check_unused_variables()
	p.cur_fn = EmptyFn
	if !is_generic {
		p.genln('}')
	}
}

fn (p mut Parser) check_unused_variables() {
	for var in p.cur_fn.local_vars {
		if var.name == '' {
			break
		}
		if !var.is_used && !p.pref.is_repl && !var.is_arg && !p.pref.translated && var.name != '_' {
			p.scanner.line_nr = var.line_nr - 1
			p.error('`$var.name` declared and not used')
		}
		if !var.is_changed && var.is_mut && !p.pref.is_repl && !var.is_arg && !p.pref.translated && var.name != '_' {
			p.scanner.line_nr = var.line_nr - 1
			p.error('`$var.name` is declared as mutable, but it was never changed')
		}
	}
}

// user.register() => "User_register(user)"
// method_ph - where to insert "user_register("
// receiver_var - "user" (needed for pthreads)
// receiver_type - "User"
fn (p mut Parser) async_fn_call(f Fn, method_ph int, receiver_var, receiver_type string) {
	// println('\nfn_call $f.name is_method=$f.is_method receiver_type=$f.receiver_type')
	// p.print_tok()
	mut thread_name := ''
	// Normal function => just its name, method => TYPE_FN.name
	mut fn_name := f.name
	if f.is_method {
		fn_name = receiver_type.replace('*', '') + '_' + f.name
		//fn_name = '${receiver_type}_${f.name}'
	}
	// Generate tmp struct with args
	arg_struct_name := 'thread_arg_$fn_name'
	tmp_struct := p.get_tmp()
	p.genln('$arg_struct_name * $tmp_struct = malloc(sizeof($arg_struct_name));')
	mut arg_struct := 'typedef struct  $arg_struct_name   { '
	p.next()
	p.check(.lpar)
	// str_args contains the args for the wrapper function:
	// wrapper(arg_struct * arg) { fn("arg->a, arg->b"); }
	mut str_args := ''
	mut did_gen_something := false
	for i, arg in f.args {
		arg_struct += '$arg.typ $arg.name ;'// Add another field (arg) to the tmp struct definition
		str_args += 'arg->$arg.name'
		if i == 0 && f.is_method {
			p.genln('$tmp_struct -> $arg.name =  $receiver_var ;')
			if i < f.args.len - 1 {
				str_args += ','
			}
			continue
		}
		// Set the struct values (args)
		p.genln('$tmp_struct -> $arg.name =  ')
		p.expression()
		p.genln(';')
		if i < f.args.len - 1 {
			p.check(.comma)
			str_args += ','
		}
		did_gen_something = true
	}

	if !did_gen_something {
		// Msvc doesnt like empty struct
		arg_struct += 'EMPTY_STRUCT_DECLARATION'
	}

	arg_struct += '} $arg_struct_name ;'
	// Also register the wrapper, so we can use the original function without modifying it
	fn_name = p.table.cgen_name(f)
	wrapper_name := '${fn_name}_thread_wrapper'
	wrapper_text := 'void* $wrapper_name($arg_struct_name * arg) {$fn_name( /*f*/$str_args );  }'
	p.cgen.register_thread_fn(wrapper_name, wrapper_text, arg_struct)
	// Create thread object
	tmp_nr := p.get_tmp_counter()
	thread_name = '_thread$tmp_nr'
	if p.os != .windows && p.os != .msvc {
		p.genln('pthread_t $thread_name;')
	}
	tmp2 := p.get_tmp()
	mut parg := 'NULL'
	if f.args.len > 0 {
		parg = ' $tmp_struct'
	}
	// Call the wrapper
	if p.os == .windows || p.os == .msvc {
		p.genln(' CreateThread(0,0, $wrapper_name, $parg, 0,0);')
	}
	else {
		p.genln('int $tmp2 = pthread_create(& $thread_name, NULL, $wrapper_name, $parg);')
	}
	p.check(.rpar)
}

fn (p mut Parser) fn_call(f Fn, method_ph int, receiver_var, receiver_type string) {
	if !f.is_public &&  !f.is_c && !p.pref.is_test && !f.is_interface && f.mod != p.mod  {
		p.error('function `$f.name` is private')
	}
	p.calling_c = f.is_c
	if f.is_c && !p.builtin_mod {
		if f.name == 'free' {
			p.error('use `free()` instead of `C.free()`')
		} else if f.name == 'malloc' {
			p.error('use `malloc()` instead of `C.malloc()`')
		}
	}
	mut cgen_name := p.table.cgen_name(f)
	p.next()
	mut gen_type := ''
	if p.tok == .lt {
		p.check(.lt)
		gen_type = p.check_name()
		// run<T> => run_App
		if gen_type == 'T' && p.cur_gen_type != '' {
			gen_type = p.cur_gen_type
		}
		// `foo<Bar>()`
		// If we are in the first pass, we need to add `Bar` type to the generic function `foo`,
		// so that generic `foo`s body can be generated for each type in the second pass.
		if p.first_pass() {
			println('registering $gen_type in $f.name fname=$f.name')
			p.table.register_generic_fn_type(f.name, gen_type)
			// Function bodies are skipped in the first passed, we only need to register the generic type here.
			return
		}
		cgen_name += '_' + gen_type
		p.check(.gt)
	}
	// if p.pref.is_prof {
	// p.cur_fn.called_fns << cgen_name
	// }
	// Normal function call
	if !f.is_method {
		p.gen(cgen_name)
		p.gen('(')
		// p.fgen(f.name)
	}
	// If we have a method placeholder,
	// we need to preappend "method(receiver, ...)"
	else {
		mut method_call := '${cgen_name}('
		receiver := f.args.first()
		if receiver.is_mut && !p.expr_var.is_mut {
			println('$method_call  recv=$receiver.name recv_mut=$receiver.is_mut')
			p.error('`$p.expr_var.name` is immutable, declare it with `mut`')
		}
		if !p.expr_var.is_changed {
			p.cur_fn.mark_var_changed(p.expr_var)
		}
		// if receiver is key_mut or a ref (&), generate & for the first arg
		if receiver.ref || (receiver.is_mut && !receiver_type.contains('*')) {
			method_call += '& /* ? */'
		}
		// generate deref (TODO copy pasta later in fn_call_args)
		if !receiver.is_mut && receiver_type.contains('*') {
			method_call += '*'
		}
		mut cast := ''
		// Method returns (void*) => cast it to int, string, user etc
		// number := *(int*)numbers.first()
		if f.typ == 'void*' {
			// array_int => int
			cast = receiver_type.all_after('_')
			cast = '*($cast*) '
		}
		p.cgen.set_placeholder(method_ph, '$cast $method_call')
	}
	// foo<Bar>()
	p.fn_call_args(mut f)
	p.gen(')')
	p.calling_c = false
	// println('end of fn call typ=$f.typ')
}

// for declaration
// return an updated Fn object with args[] field set
fn (p mut Parser) fn_args(f mut Fn) {
	p.check(.lpar)
	defer { p.check(.rpar) }
	if f.is_interface {
		int_arg := Var {
			typ: f.receiver_typ
		}
		f.args << int_arg
	}
	// `(int, string, int)`
	// Just register fn arg types
	types_only := p.tok == .mul || (p.peek() == .comma && p.table.known_type(p.lit)) || p.peek() == .rpar// (int, string)
	if types_only {
		for p.tok != .rpar {
			typ := p.get_type()
			v := Var {
				typ: typ
				is_arg: true
				// is_mut: is_mut
				line_nr: p.scanner.line_nr
			}
			// f.register_var(v)
			f.args << v
			if p.tok == .comma {
				p.next()
			}
		}
	}
	// `(a int, b, c string)` syntax
	for p.tok != .rpar {
		mut names := [
		p.check_name()
		]
		// `a,b,c int` syntax
		for p.tok == .comma {
			p.check(.comma)
			p.fspace()
			names << p.check_name()
		}
		p.fspace()
		is_mut := p.tok == .key_mut
		if is_mut {
			p.next()
		}
		mut typ := p.get_type()
		if is_mut && is_primitive_type(typ) {
			p.error('mutable arguments are only allowed for arrays, maps, and structs.' +
			'\nreturn values instead: `foo(n mut int)` => `foo(n int) int`')
		}
		for name in names {
			if !p.first_pass() && !p.table.known_type(typ) {
				p.error('fn_args: unknown type $typ')
			}
			if is_mut {
				typ += '*'
			}
			v := Var {
				name: name
				typ: typ
				is_arg: true
				is_mut: is_mut
				ptr: is_mut
				line_nr: p.scanner.line_nr
			}
			f.register_var(v)
			f.args << v
		}
		if p.tok == .comma {
			p.next()
		}
		if p.tok == .dotdot {
			f.args << Var {
				name: '..'
			}
			p.next()
		}
	}
}

// foo *(1, 2, 3, mut bar)*
fn (p mut Parser) fn_call_args(f mut Fn) *Fn {
	// p.gen('(')
	// println('fn_call_args() name=$f.name args.len=$f.args.len')
	// C func. # of args is not known
	// if f.name.starts_with('c_') {
	p.check(.lpar)
	if f.is_c {
		for p.tok != .rpar {
			p.bool_expression()
			if p.tok == .comma {
				p.gen(', ')
				p.check(.comma)
			}
		}
		p.check(.rpar)
		return f
	}
	// add debug information to panic when -debug arg is passed
	if p.v.pref.is_debug && f.name == 'panic' {
		mod_name := p.mod.replace('_dot_', '.')
		fn_name := p.cur_fn.name.replace('${p.mod}__', '')
		file_path := p.file_path.replace('\\', '\\\\') // escape \
		p.cgen.resetln(p.cgen.cur_line.replace(
			'v_panic (',
			'_panic_debug ($p.scanner.line_nr, tos2((byte *)"$file_path"), tos2((byte *)"$mod_name"), tos2((byte *)"$fn_name"), '
		))
	}
	// Receiver - first arg
	for i, arg in f.args {
		// println('$i) arg=$arg.name')
		// Skip receiver, because it was already generated in the expression
		if i == 0 && f.is_method {
			if f.args.len > 1 {
				p.gen(',')
			}
			continue
		}
		// Reached the final vararg? Quit
		if i == f.args.len - 1 && arg.name == '..' {
			break
		}
		ph := p.cgen.add_placeholder()
		// `)` here means that not enough args were provided
		if p.tok == .rpar {
			str_args := f.str_args(p.table)// TODO this is C args
			p.error('not enough arguments in call to `$f.name ($str_args)`')
		}
		// If `arg` is mutable, the caller needs to provide `mut`:
		// `mut numbers := [1,2,3]; reverse(mut numbers);`
		if arg.is_mut {
			if p.tok != .key_mut && p.tok == .name {
				mut dots_example :=  'mut $p.lit'
				if i > 0 {
					dots_example = '.., ' + dots_example
				}
				if i < f.args.len - 1 {
					dots_example = dots_example + ',..'
				}
				p.error('`$arg.name` is a mutable argument, you need to provide `mut`: `$f.name($dots_example)`')	
			}
			if p.peek() != .name {
				p.error('`$arg.name` is a mutable argument, you need to provide a variable to modify: `$f.name(... mut a...)`')
			}
			p.check(.key_mut)
			var_name := p.lit
			v := p.cur_fn.find_var(var_name)
			if v.name == '' {
				p.error('`$arg.name` is a mutable argument, you need to provide a variable to modify: `$f.name(... mut a...)`')
			}
			if !v.is_changed {
				p.cur_fn.mark_var_changed(v)
			}
		}
		p.expected_type = arg.typ
		typ := p.bool_expression()
		// Optimize `println`: replace it with `printf` to avoid extra allocations and
		// function calls. `println(777)` => `printf("%d\n", 777)`
		// (If we don't check for void, then V will compile `println(func())`)
		if i == 0 && f.name == 'println' && typ != 'string' && typ != 'void' {
			T := p.table.find_type(typ)
			$if !windows {
				fmt := p.typ_to_fmt(typ, 0)
				if fmt != '' {
					p.cgen.resetln(p.cgen.cur_line.replace('println (', '/*opt*/printf ("' + fmt + '\\n", '))
					continue
				}
			}
			if typ.ends_with('*') {
				p.cgen.set_placeholder(ph, 'ptr_str(')
				p.gen(')')
				continue
			}
			// Make sure this type has a `str()` method
			if !T.has_method('str') {
				// Arrays have automatic `str()` methods
				if T.name.starts_with('array_') {
					p.gen_array_str(mut T)
					p.cgen.set_placeholder(ph, '${typ}_str(')
					p.gen(')')
					continue
				}
				error_msg := ('`$typ` needs to have method `str() string` to be printable')
				if T.fields.len > 0 {
					mut index := p.cgen.cur_line.len - 1
					for index > 0 && p.cgen.cur_line[index] != ` ` { index-- }
					name := p.cgen.cur_line.right(index + 1)
					if name == '}' {
						p.error(error_msg)
					}
					p.cgen.resetln(p.cgen.cur_line.left(index))
					p.scanner.create_type_string(T, name)
					p.cgen.cur_line.replace(typ, '')
					p.next()
					return p.fn_call_args(mut f)
				}
				p.error(error_msg)
			}
			p.cgen.set_placeholder(ph, '${typ}_str(')
			p.gen(')')
			continue
		}
		got := typ
		expected := arg.typ
		// println('fn arg got="$got" exp="$expected"')
		if !p.check_types_no_throw(got, expected) {
			mut err := 'Fn "$f.name" wrong arg #${i+1}. '
			err += 'Expected "$arg.typ" ($arg.name)  but got "$typ"'
			p.error(err)
		}
		is_interface := p.table.is_interface(arg.typ)
		// Add `&` or `*` before an argument?
		if !is_interface {
			// Dereference
			if got.contains('*') && !expected.contains('*') {
				p.cgen.set_placeholder(ph, '*')
			}
			// Reference
			// TODO ptr hacks. DOOM hacks, fix please.
			if !got.contains('*') && expected.contains('*') && got != 'voidptr' {
				// Special case for mutable arrays. We can't `&` function results,
				// have to use `(array[]){ expr }` hack.
				if expected.starts_with('array_') && expected.ends_with('*') {
					p.cgen.set_placeholder(ph, '& /*111*/ (array[]){')
					p.gen('}[0] ')
				}
				// println('\ne:"$expected" got:"$got"')
				else if ! (expected == 'void*' && got == 'int') &&
				! (expected == 'byte*' && got.contains(']byte')) &&
				! (expected == 'byte*' && got == 'string') &&
				//! (expected == 'void*' && got == 'array_int') {
				! (expected == 'byte*' && got == 'byteptr') {
					p.cgen.set_placeholder(ph, '& /*112 EXP:"$expected" GOT:"$got" */')
				}
			}
		}
		// interface?
		if is_interface {
			if !got.contains('*') {
				p.cgen.set_placeholder(ph, '&')
			}
			// Pass all interface methods
			interface_type := p.table.find_type(arg.typ)
			for method in interface_type.methods {
				p.gen(', ${typ}_${method.name} ')
			}
		}
		// Check for commas
		if i < f.args.len - 1 {
			// Handle 0 args passed to varargs
			is_vararg := i == f.args.len - 2 && f.args[i + 1].name == '..'
			if p.tok != .comma && !is_vararg {
				p.error('wrong number of arguments for $i,$arg.name fn `$f.name`: expected $f.args.len, but got less')
			}
			if p.tok == .comma {
				p.fgen(', ')
			}
			if !is_vararg {
				p.next()
				p.gen(',')
			}
		}
	}
	// varargs
	if f.args.len > 0 {
		last_arg := f.args.last()
		if last_arg.name == '..' {
			for p.tok != .rpar {
				if p.tok == .comma {
					p.gen(',')
					p.check(.comma)
				}
				p.bool_expression()
			}
		}
	}
	if p.tok == .comma {
		p.error('wrong number of arguments for fn `$f.name`: expected $f.args.len, but got more')
	}
	p.check(.rpar)
	// p.gen(')')
	return f // TODO is return f right?
}

// "fn (int, string) int"
fn (f Fn) typ_str() string {
	mut sb := strings.new_builder(50)
	sb.write('fn (')
	for i, arg in f.args {
		sb.write(arg.typ)
		if i < f.args.len - 1 {
			sb.write(',')
		}
	}
	sb.write(')')
	if f.typ != 'void' {
		sb.write(' $f.typ')
	}
	return sb.str()
}

// f.args => "int a, string b"
fn (f &Fn) str_args(table *Table) string {
	mut s := ''
	for i, arg in f.args {
		// Interfaces are a special case. We need to pass the object + pointers
		// to all methods:
		// fn handle(r Runner) { =>
		// void handle(void *r, void (*Runner_run)(void*)) {
		if table.is_interface(arg.typ) {
			// First the object (same name as the interface argument)
			s += ' void* $arg.name'
			// Now  all methods
			interface_type := table.find_type(arg.typ)
			for method in interface_type.methods {
				s += ', $method.typ (*${arg.typ}_${method.name})(void*'
				if method.args.len > 1 {
					for a in method.args.right(1) {
						s += ', $a.typ'
					}
				}
				s += ')'
			}
		}
		else if arg.name == '..' {
			s += '...'
		}
		else {
			// s += '$arg.typ $arg.name'
			s += table.cgen_name_type_pair(arg.name, arg.typ)// '$arg.typ $arg.name'
		}
		if i < f.args.len - 1 {
			s += ', '
		}
	}
	return s
}
