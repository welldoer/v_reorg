// Copyright (c) 2019 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.

module main

import os
import time
import strings

const (
	Version = '0.1.18'
)

enum BuildMode {
	// `v program.v'
	// Build user code only, and add pre-compiled vlib (`cc program.o builtin.o os.o...`)
	default_mode
	// `v -embed_vlib program.v`
	// vlib + user code in one file (slower compilation, but easier when working on vlib and cross-compiling)
	embed_vlib
	// `v -lib ~/v/os`
	// build any module (generate os.o + os.vh)
	build //TODO a better name would be smth like `.build_module` I think
}

const (
	SupportedPlatforms = ['windows', 'mac', 'linux', 'freebsd', 'openbsd', 'netbsd', 'dragonfly', 'msvc']
	ModPath            = os.home_dir() + '/.vmodules/'
)

enum OS {
	mac
	linux
	windows
	freebsd
	openbsd
	netbsd
	dragonfly
	msvc
}

enum Pass {
	// A very short pass that only looks at imports in the beginning of
	// each file
	imports
	// First pass, only parses and saves declarations (fn signatures,
	// consts, types).
	// Skips function bodies.
	// We need this because in V things can be used before they are
	// declared.
	decl
	// Second pass, parses function bodies and generates C or machine code.
	main
}

struct V {
mut:
	os         OS // the OS to build for
	out_name_c string // name of the temporary C file
	files      []string // all V files that need to be parsed and compiled
	dir        string // directory (or file) being compiled (TODO rename to path?)
	table      *Table // table with types, vars, functions etc
	cgen       *CGen // C code generator
	pref       *Preferences // all the prefrences and settings extracted to a struct for reusability
	lang_dir   string // "~/code/v"
	out_name   string // "program.exe"
	vroot      string
	mod        string  // module being built with -lib
	//parsers    []Parser
}

struct Preferences {
mut:
	build_mode     BuildMode
	nofmt          bool // disable vfmt
	is_test        bool // `v test string_test.v`
	is_script      bool // single file mode (`v program.v`), main function can be skipped
	is_live        bool // for hot code reloading
	is_so          bool
	is_prof        bool // benchmark every function
	translated     bool // `v translate doom.v` are we running V code translated from C? allow globals, ++ expressions, etc
	is_prod        bool // use "-O2"
	is_verbose     bool // print extra information with `v.log()`
	obfuscate      bool // `v -obf program.v`, renames functions to "f_XXX"
	is_repl        bool
	is_run         bool
	show_c_cmd     bool // `v -show_c_cmd` prints the C command to build program.v.c
	sanitize       bool // use Clang's new "-fsanitize" option
	is_debuggable  bool
	is_debug       bool // keep compiled C files
	no_auto_free   bool // `v -nofree` disable automatic `free()` insertion for better performance in some applications  (e.g. compilers)
	cflags        string // Additional options which will be passed to the C compiler.
						 // For example, passing -cflags -Os will cause the C compiler to optimize the generated binaries for size.
						 // You could pass several -cflags XXX arguments. They will be merged with each other.
						 // You can also quote several options at the same time: -cflags '-Os -fno-inline-small-functions'.
	ccompiler  string // the name of the used C compiler
}


fn main() {
	// There's no `flags` module yet, so args have to be parsed manually
	args := env_vflags_and_os_args()
	// Print the version and exit.
	if '-v' in args || '--version' in args || 'version' in args {
		println('V $Version')
		return
	}
	if '-h' in args || '--help' in args || 'help' in args {
		println(HelpText)
		return
	}
	if 'translate' in args {
		println('Translating C to V will be available in V 0.3')
		return
	}
	if 'up' in args {
		update_v()
		return
	}
	if 'get' in args {
		println('use `v install` to install modules from vpm.vlang.io')
		return
	}
	if 'symlink' in args {
		create_symlink()
		return
	}
	if args.join(' ').contains(' test v') {
		test_v()
		return
	}
	if 'install' in args {
		if args.len < 3 {
			println('usage: v install [module] [module] [...]')
			return
		}
		names := args.slice(2, args.len)
		vexec := os.executable()
		vroot := os.dir(vexec)
		vget := '$vroot/tools/vget'
		if true {
			//println('Building vget...')
			os.chdir(vroot + '/tools')
			vgetcompilation := os.exec('$vexec -o $vget vget.v') or {
				panic(err)
			}
			if vgetcompilation.exit_code != 0 {
				panic( vgetcompilation.output )
			}
		}
		vgetresult := os.exec('$vget ' + names.join(' ')) or {
			panic(err)
		}
		if vgetresult.exit_code != 0 {
			panic( vgetresult.output )
		}
		return
	}
	// TODO quit if the compiler is too old
	// u := os.file_last_mod_unix('v')
	// If there's no tmp path with current version yet, the user must be using a pre-built package
	// Copy the `vlib` directory to the tmp path.
/*
	// TODO
	if !os.file_exists(TmpPath) && os.file_exists('vlib') {
	}
*/
	// Just fmt and exit
	if 'fmt' in args {
		file := args.last()
		if !os.file_exists(file) {
			println('"$file" does not exist')
			exit(1)
		}
		if !file.ends_with('.v') {
			println('v fmt can only be used on .v files')
			exit(1)
		}
		println('vfmt is temporarily disabled')
		return
	}
	// v get sqlite
	if 'get' in args {
		// Create the modules directory if it's not there.
		if !os.file_exists(ModPath)  {
			os.mkdir(ModPath)
		}
	}
	// No args? REPL
	if args.len < 2 || (args.len == 2 && args[1] == '-') {
		run_repl()
		return
	}
	// Construct the V object from command line arguments
	mut v := new_v(args)
	if v.pref.is_verbose {
		println(args)
	}
	// Generate the docs and exit
	if 'doc' in args {
		// v.gen_doc_html_for_module(args.last())
		exit(0)
	}

	if 'run' in args {
		// always recompile for now, too error prone to skip recompilation otherwise
		// for example for -repl usage, especially when piping lines to v
		v.compile()
		v.run_compiled_executable_and_exit()
	}

	v.compile()

	if v.pref.is_test {
		v.run_compiled_executable_and_exit()
	}

}

fn (v mut V) compile() {
	// Emily: Stop people on linux from being able to build with msvc
	if os.user_os() != 'windows' && v.os == .msvc {
		panic('Cannot build with msvc on ${os.user_os()}')
	}

	mut cgen := v.cgen
	cgen.genln('// Generated by V')
	// Add builtin parsers
	for i, file in v.files {
	//        v.parsers << v.new_parser(file)
	}
	v.add_v_files_to_compile()
	if v.pref.is_verbose {
		println('all .v files:')
		println(v.files)
	}
	// First pass (declarations)
	for file in v.files {
		mut p := v.new_parser(file)
		p.parse(.decl)
	}
	// Main pass
	cgen.pass = Pass.main
	if v.pref.is_debug {
		cgen.genln('#define VDEBUG (1) ')
	}

	cgen.genln(CommonCHeaders)
	
	v.generate_hotcode_reloading_declarations()

	imports_json := v.table.imports.contains('json')
	// TODO remove global UI hack
	if v.os == .mac && ((v.pref.build_mode == .embed_vlib && v.table.imports.contains('ui')) ||
	(v.pref.build_mode == .build && v.dir.contains('/ui'))) {
		cgen.genln('id defaultFont = 0; // main.v')
	}
	// TODO remove ugly .c include once V has its own json parser
	// Embed cjson either in embedvlib or in json.o
	if (imports_json && v.pref.build_mode == .embed_vlib) ||
	(v.pref.build_mode == .build && v.out_name.contains('json.o')) {
		//cgen.genln('#include "cJSON.c" ')
	}
	// We need the cjson header for all the json decoding user will do in default mode
	if v.pref.build_mode == .default_mode {
		if imports_json {
			cgen.genln('#include "cJSON.h"')
		}
	}
	if v.pref.build_mode == .embed_vlib || v.pref.build_mode == .default_mode {
		// If we declare these for all modes, then when running `v a.v` we'll get
		// `/usr/bin/ld: multiple definition of 'total_m'`
		// TODO
		//cgen.genln('i64 total_m = 0; // For counting total RAM allocated')
		cgen.genln('int g_test_ok = 1; ')
		if v.table.imports.contains('json') {
			cgen.genln('
#define js_get(object, key) cJSON_GetObjectItemCaseSensitive((object), (key))
')
		}
	}
	if os.args.contains('-debug_alloc') {
		cgen.genln('#define DEBUG_ALLOC 1')
	}
	cgen.genln('/*================================== FNS =================================*/')
	cgen.genln('this line will be replaced with definitions')
	defs_pos := cgen.lines.len - 1
	for file in v.files {
		mut p := v.new_parser(file)
		p.parse(.main)
		// p.g.gen_x64()
		// Format all files (don't format automatically generated vlib headers)
		if !v.pref.nofmt && !file.contains('/vlib/') {
			// new vfmt is not ready yet
		}
	}
	v.log('Done parsing.')
	// Write everything
	mut d := strings.new_builder(10000)// Avoid unnecessary allocations
	d.writeln(cgen.includes.join_lines())
	d.writeln(cgen.typedefs.join_lines())
	d.writeln(cgen.types.join_lines())
	d.writeln('\nstring _STR(const char*, ...);\n')
	d.writeln('\nstring _STR_TMP(const char*, ...);\n')
	d.writeln(cgen.fns.join_lines())
	d.writeln(cgen.consts.join_lines())
	d.writeln(cgen.thread_args.join_lines())
	if v.pref.is_prof {
		d.writeln('; // Prof counters:')
		d.writeln(v.prof_counters())
	}
	dd := d.str()
	cgen.lines.set(defs_pos, dd)// TODO `def.str()` doesn't compile

  v.generate_main()

  v.generate_hotcode_reloading_code()

  cgen.save()
	if v.pref.is_verbose {
		v.log('flags=')
		println(v.table.flags)
	}
	v.cc()
}

fn (v mut V) generate_main() {
	mut cgen := v.cgen

	// if v.build_mode in [.default, .embed_vlib] {
	if v.pref.build_mode == .default_mode || v.pref.build_mode == .embed_vlib {
		mut consts_init_body := cgen.consts_init.join_lines()
		for imp in v.table.imports {
			if imp == 'http' {
				consts_init_body += '\n http__init_module();'
			}
		}
		// vlib can't have `init_consts()`
		cgen.genln('void init_consts() {
#ifdef _WIN32
#ifndef _BOOTSTRAP_NO_UNICODE_STREAM
_setmode(_fileno(stdout), _O_U8TEXT);
SetConsoleMode(GetStdHandle(STD_OUTPUT_HANDLE), ENABLE_PROCESSED_OUTPUT | 0x0004);
// ENABLE_VIRTUAL_TERMINAL_PROCESSING
#endif
#endif
g_str_buf=malloc(1000);
$consts_init_body
}')
		// _STR function can't be defined in vlib
		cgen.genln('
string _STR(const char *fmt, ...) {
	va_list argptr;
	va_start(argptr, fmt);
	size_t len = vsnprintf(0, 0, fmt, argptr) + 1;
	va_end(argptr);
	byte* buf = malloc(len);
	va_start(argptr, fmt);
	vsprintf((char *)buf, fmt, argptr);
	va_end(argptr);
#ifdef DEBUG_ALLOC
	puts("_STR:");
	puts(buf);
#endif
	return tos2(buf);
}

string _STR_TMP(const char *fmt, ...) {
	va_list argptr;
	va_start(argptr, fmt);
	//size_t len = vsnprintf(0, 0, fmt, argptr) + 1;
	va_end(argptr);
	va_start(argptr, fmt);
	vsprintf((char *)g_str_buf, fmt, argptr);
	va_end(argptr);
#ifdef DEBUG_ALLOC
	//puts("_STR_TMP:");
	//puts(g_str_buf);
#endif
	return tos2(g_str_buf);
}

')
	}

	// Make sure the main function exists
	// Obviously we don't need it in libraries
	if v.pref.build_mode != .build {
		if !v.table.main_exists() && !v.pref.is_test {
			// It can be skipped in single file programs
			if v.pref.is_script {
				//println('Generating main()...')
				cgen.genln('int main() { init_consts();')
				cgen.genln('$cgen.fn_main;')
				cgen.genln('return 0; }')
			}
			else {
				println('panic: function `main` is undeclared in the main module')
				exit(1)
			}
		}
		// Generate `main` which calls every single test function
		else if v.pref.is_test {
			cgen.genln('int main() { init_consts();')
			for _, f in v.table.fns {
				if f.name.starts_with('test_') {
					cgen.genln('$f.name();')
				}
			}
			cgen.genln('return g_test_ok == 0; }')
		}
	}
}

fn final_target_out_name(out_name string) string {
	mut cmd := if out_name.starts_with('/') {
		out_name
	}
	else {
		'./' + out_name
	}
	$if windows {
		cmd = out_name
		cmd = cmd.replace('/', '\\')
		cmd += '.exe'
	}
	return cmd
}

fn (v V) run_compiled_executable_and_exit() {
	if v.pref.is_verbose {
		println('============ running $v.out_name ============')
	}	
	mut cmd := final_target_out_name(v.out_name).replace('.exe','')
	if os.args.len > 3 {
		cmd += ' ' + os.args.right(3).join(' ')
	}
	if v.pref.is_test {
		ret := os.system(cmd)
		if ret != 0 {
			exit(1)
		}
	}
	if v.pref.is_run {
		ret := os.system(cmd)
		// TODO: make the runner wrapping as transparent as possible
		// (i.e. use execve when implemented). For now though, the runner
		// just returns the same exit code as the child process
		// (see man system, man 2 waitpid: C macro WEXITSTATUS section)
		exit( ret >> 8 )
	}
	exit(0)
}

fn (v &V) v_files_from_dir(dir string) []string {
	mut res := []string
	if !os.file_exists(dir) {
		panic('$dir doesn\'t exist')
	} else if !os.dir_exists(dir) {
		panic('$dir isn\'t a directory')
	}
	mut files := os.ls(dir)
	if v.pref.is_verbose {
		println('v_files_from_dir ("$dir")')
	}
	files.sort()
	for file in files {
		if !file.ends_with('.v') && !file.ends_with('.vh') {
			continue
		}
		if file.ends_with('_test.v') {
			continue
		}
		if file.ends_with('_win.v') && (v.os != .windows && v.os != .msvc) {
			continue
		}
		if file.ends_with('_lin.v') && v.os != .linux {
			continue
		}
		if file.ends_with('_mac.v') && v.os != .mac {
			continue
		}
		if file.ends_with('_nix.v') && (v.os == .windows || v.os == .msvc) {
			continue
		}
		res << '$dir/$file'
	}
	return res
}

// Parses imports, adds necessary libs, and then user files
fn (v mut V) add_v_files_to_compile() {
	mut dir := v.dir
	v.log('add_v_files($dir)')
	// Need to store user files separately, because they have to be added after libs, but we dont know
	// which libs need to be added yet
	mut user_files := []string
	// v volt/slack_test.v: compile all .v files to get the environment
	// I need to implement user packages! TODO
	is_test_with_imports := dir.ends_with('_test.v') &&
	(dir.contains('/volt') || dir.contains('/c2volt'))// TODO
	if is_test_with_imports {
		user_files << dir
		pos := dir.last_index('/')
		dir = dir.left(pos) + '/'// TODO WHY IS THIS .neEDED?
	}
	if dir.ends_with('.v') {
		// Just compile one file and get parent dir
		user_files << dir
		dir = dir.all_before('/')
	}
	else {
		// Add files from the dir user is compiling (only .v files)
		files := v.v_files_from_dir(dir)
		for file in files {
			user_files << file
		}
	}
	if user_files.len == 0 {
		println('No input .v files')
		exit(1)
	}
	if v.pref.is_verbose {
		v.log('user_files:')
		println(user_files)
	}
	// Parse builtin imports
	for file in v.files {
		mut p := v.new_parser(file)
		p.parse(.imports)
	}
	// Parse user imports
	for file in user_files {
		mut p := v.new_parser(file)
		p.parse(.imports)
	}
	// Parse lib imports
/*
	if v.pref.build_mode == .default_mode {
		// strange ( for mod in v.table.imports ) dosent loop all items
		// for mod in v.table.imports {
		for i := 0; i < v.table.imports.len; i++ {
			mod := v.table.imports[i]
			mod_path := v.module_path(mod)
			import_path := '$ModPath/vlib/$mod_path'
			vfiles := v.v_files_from_dir(import_path)
			if vfiles.len == 0 {
				panic('cannot import module $mod (no .v files in "$import_path").')
			}
			// Add all imports referenced by these libs
			for file in vfiles {
				mut p := v.new_parser(file, Pass.imports)
				p.parse()
			}
		}
	}
	else {
*/
	// strange ( for mod in v.table.imports ) dosent loop all items
	// for mod in v.table.imports {
	for i := 0; i < v.table.imports.len; i++ {
		mod := v.table.imports[i]
		import_path := v.find_module_path(mod)
		vfiles := v.v_files_from_dir(import_path)
		if vfiles.len == 0 {
			panic('cannot import module $mod (no .v files in "$import_path").')
		}
		// Add all imports referenced by these libs
		for file in vfiles {
			mut p := v.new_parser(file)
			p.parse(.imports)
		}
	}
	if v.pref.is_verbose {
		v.log('imports:')
		println(v.table.imports)
	}
	// graph deps
	mut dep_graph := new_mod_dep_graph()
	dep_graph.from_import_tables(v.table.file_imports)
	deps_resolved := dep_graph.resolve()
	if !deps_resolved.acyclic {
		deps_resolved.display()
		panic('Import cycle detected.')
	}
	// add imports in correct order
	for mod in deps_resolved.imports() {
		// Building this module? Skip. TODO it's a hack.
		if mod == v.mod {
			continue
		}
		mod_path := v.find_module_path(mod)
		// If we are in default mode, we don't parse vlib .v files, but header .vh files in
		// TmpPath/vlib
		// These were generated by vfmt
/*
		if v.pref.build_mode == .default_mode || v.pref.build_mode == .build {
			module_path = '$ModPath/vlib/$mod_p'
		}
*/
		vfiles := v.v_files_from_dir(mod_path)
		for file in vfiles {
			if !file in v.files {
				v.files << file
			}
		}
	}
	// add remaining files (not modules)
	for fit in v.table.file_imports {
		//println('fit $fit.file_path')
		if !fit.file_path in v.files {
			v.files << fit.file_path
		}
	}
}

fn get_arg(joined_args, arg, def string) string {
	return get_all_after(joined_args, '-$arg', def)
}

fn get_all_after(joined_args, arg, def string) string {
	key := '$arg '
	mut pos := joined_args.index(key)
	if pos == -1 {
		return def
	}
	pos += key.len
	mut space := joined_args.index_after(' ', pos)
	if space == -1 {
		space = joined_args.len
	}
	res := joined_args.substr(pos, space)
	// println('get_arg($arg) = "$res"')
	return res
}

fn (v &V) module_path(mod string) string {
	// submodule support
	if mod.contains('.') {
		//return mod.replace('.', path_sep)
		return mod.replace('.', '/')
	}
	return mod
}

fn (v &V) log(s string) {
	if !v.pref.is_verbose {
		return
	}
	println(s)
}

fn new_v(args[]string) *V {
	joined_args := args.join(' ')
	target_os := get_arg(joined_args, 'os', '')
	mut out_name := get_arg(joined_args, 'o', 'a.out')
  
	mut dir := args.last()
	if args.contains('run') {
		dir = get_all_after(joined_args, 'run', '')
	}
	if args.len < 2 {
		dir = ''
	}
	// println('new compiler "$dir"')
	// build mode
	mut build_mode := BuildMode.default_mode
	mut mod := ''
	//if args.contains('-lib') {
	if joined_args.contains('build module ') {
		build_mode = .build
		// v -lib ~/v/os => os.o
		mod = os.dir(dir)
		mod = mod.all_after('/')
		println('Building module  "${mod}" dir="$dir"...')
		//out_name = '$TmpPath/vlib/${base}.o'
		out_name = mod + '.o'
		// Cross compiling? Use separate dirs for each os
/*
		if target_os != os.user_os() {
			os.mkdir('$TmpPath/vlib/$target_os')
			out_name = '$TmpPath/vlib/$target_os/${base}.o'
			println('target_os=$target_os user_os=${os.user_os()}')
			println('!Cross compiling $out_name')
		}
*/
	}
	// TODO embed_vlib is temporarily the default mode. It's much slower.
	else if !args.contains('-embed_vlib') {
		build_mode = .embed_vlib
	}
	//
	is_test := dir.ends_with('_test.v')
	is_script := dir.ends_with('.v')
	if is_script && !os.file_exists(dir) {
		println('`$dir` does not exist')
		exit(1)
	}
	// No -o provided? foo.v => foo
	if out_name == 'a.out' && dir.ends_with('.v') {
		out_name = dir.left(dir.len - 2)
	}
	// if we are in `/foo` and run `v .`, the executable should be `foo`
	if dir == '.' && out_name == 'a.out' {
		base := os.getwd().all_after('/')
		out_name = base.trim_space()
	}
	mut _os := OS.mac
	// No OS specifed? Use current system
	if target_os == '' {
		$if linux {
			_os = .linux
		}
		$if mac {
			_os = .mac
		}
		$if windows {
			_os = .windows
		}
		$if freebsd {
			_os = .freebsd
		}
		$if openbsd {
			_os = .openbsd
		}
		$if netbsd {
			_os = .netbsd
		}
		$if dragonfly {
			_os = .dragonfly
		}
	}
	else {
		switch target_os {
		case 'linux': _os = .linux
		case 'windows': _os = .windows
		case 'mac': _os = .mac
		case 'freebsd': _os = .freebsd
		case 'openbsd': _os = .openbsd
		case 'netbsd': _os = .netbsd
		case 'dragonfly': _os = .dragonfly
		case 'msvc': _os = .msvc
		}
	}
	builtins := [
	'array.v',
	'string.v',
	'builtin.v',
	'int.v',
	'utf8.v',
	'map.v',
	'option.v',
	]
	// Location of all vlib files
	vroot := os.dir(os.executable())
	//println('VROOT=$vroot')
	// v.exe's parent directory should contain vlib
	if os.dir_exists(vroot) && os.dir_exists(vroot + '/vlib/builtin') {

	}  else {
		println('vlib not found. It should be next to the V executable. ')
		println('Go to https://vlang.io to install V.')
		exit(1)
	}
	mut out_name_c := os.realpath( out_name ) + '.tmp.c'
	mut files := []string
	// Add builtin files
	if !out_name.contains('builtin.o') {
		for builtin in builtins {
			mut f := '$vroot/vlib/builtin/$builtin'
			// In default mode we use precompiled vlib.o, point to .vh files with signatures
			if build_mode == .default_mode || build_mode == .build {
				//f = '$TmpPath/vlib/builtin/${builtin}h'
			}
			files << f
		}
	}

	mut cflags := ''
	for ci, cv in args {
		if cv == '-cflags' {
			cflags += args[ci+1] + ' '
		}
	}

	obfuscate := args.contains('-obf')
	pref := &Preferences {
		is_test: is_test
		is_script: is_script
		is_so: args.contains('-shared')
		is_prod: args.contains('-prod')
		is_verbose: args.contains('-verbose')
		is_debuggable: args.contains('-g') // -debuggable implys debug
		is_debug: args.contains('-debug') || args.contains('-g')
		obfuscate: obfuscate
		is_prof: args.contains('-prof')
		is_live: args.contains('-live')
		sanitize: args.contains('-sanitize')
		nofmt: args.contains('-nofmt')
		show_c_cmd: args.contains('-show_c_cmd')
		translated: args.contains('translated')
		is_run: args.contains('run')
		is_repl: args.contains('-repl')
		build_mode: build_mode
		cflags: cflags
		ccompiler: find_c_compiler()
	}
	if pref.is_verbose || pref.is_debug {
		println('C compiler=$pref.ccompiler')
	}
	if pref.is_so {
		out_name_c = out_name.all_after('/') + '_shared_lib.c'
	}
	return &V {
		os: _os
		out_name: out_name
		files: files
		dir: dir
		lang_dir: vroot
		table: new_table(obfuscate)
		out_name_c: out_name_c
		cgen: new_cgen(out_name_c)
		vroot: vroot
		pref: pref
		mod: mod
	}
}


const (
	HelpText = '
Usage: v [options] [file | directory]

Options:
  -                 Read from stdin (Default; Interactive mode if in a tty)
  -h, help          Display this information.
  -v, version       Display compiler version.
  -lib              Generate object file.
  -prod             Build an optimized executable.
  -o <file>         Place output into <file>.
  -obf              Obfuscate the resulting binary.
  -show_c_cmd       Print the full C compilation command and how much time it took.
  -debug            Leave a C file for debugging in .program.c.
  -live             Enable hot code reloading (required by functions marked with [live]).
  fmt               Run vfmt to format the source code.
  up                Update V.
  run               Build and execute a V program. You can add arguments after the file name.


Files:
  <file>_test.v     Test file.
'
)

/*
- To disable automatic formatting:
v -nofmt file.v

- To build a program with an embedded vlib  (use this if you do not have prebuilt vlib libraries or if you
are working on vlib)
v -embed_vlib file.v
*/

fn env_vflags_and_os_args() []string {
   mut args := []string
   vflags := os.getenv('VFLAGS')
   if '' != vflags {
	 args << os.args[0]
	 args << vflags.split(' ')
	 if os.args.len > 1 {
	   args << os.args.right(1)
	 }
   }else{
	 args << os.args
   }
   return args
}

fn update_v() {
	println('Updating V...')
	vroot := os.dir(os.executable())
	s := os.exec('git -C "$vroot" pull --rebase origin master') or {
		panic(err)
	}
	println(s.output)
	$if windows {
		os.mv('$vroot/v.exe', '$vroot/v_old.exe')
		s2 := os.exec('$vroot/make.bat') or {
			panic(err)
		}
		println(s2.output)
	} $else {
		s2 := os.exec('make -C "$vroot"') or {
			panic(err)
		}
		println(s2.output)
	}
}

fn test_v() {
	args := env_vflags_and_os_args()
	vexe := args[0]
	// Emily: pass args from the invocation to the test
	// e.g. `v -g -os msvc test v` -> `$vexe -g -os msvc $file`
	mut joined_args := env_vflags_and_os_args().right(1).join(' ')
	joined_args = joined_args.left(joined_args.last_index('test'))
	println('$joined_args')

	test_files := os.walk_ext('.', '_test.v')
	for dot_relative_file in test_files {
		relative_file := dot_relative_file.replace('./', '')
		file := os.realpath( relative_file )
		tmpcfilepath := file.replace('_test.v', '_test.tmp.c')
		print(relative_file + ' ')
		r := os.exec('$vexe $joined_args -debug $file') or {
			panic('failed on $file')
		}
		if r.exit_code != 0 {
			println('failed `$file` (\n$r.output\n)')
			exit(1)
		} else {
			println('OK')
		}
		os.rm( tmpcfilepath )
	}
	println('\nBuilding examples...')
	examples := os.walk_ext('examples', '.v')
	for relative_file in examples {
		file := os.realpath( relative_file )
		tmpcfilepath := file.replace('.v', '.tmp.c')
		print(relative_file + ' ')
		r := os.exec('$vexe $joined_args -debug $file') or {
			panic('failed on $file')
		}
		if r.exit_code != 0 {
			println('failed `$file` (\n$r.output\n)')
			exit(1)
		} else {
			println('OK')
		}
		os.rm( tmpcfilepath )
	}
}

fn create_symlink() {
	vexe := os.executable()
	link_path := '/usr/local/bin/v'
	os.system('ln -sf $vexe $link_path')
	println('symlink "$link_path" has been created')
}

