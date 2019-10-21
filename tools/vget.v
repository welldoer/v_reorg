module main

import (
	http 
	os 
	json
) 

const (
	//url = 'http://localhost:8089' 
	url = 'https://vpm.best' 
) 

struct Mod {
	id int 
	name string 
	url string
	nr_downloads int 
}

fn main() {
	if os.args.len <= 1 {
		println('usage: vget module [module] [module] [...]')
		return
	} 

	home := os.home_dir()
	home_vmodules := '${home}.vmodules'
	if !os.dir_exists( home_vmodules ) {
		println('Creating $home_vmodules/ ...')
		os.mkdir(home_vmodules)
	}
	os.chdir(home_vmodules)

	mut errors := 0
	names := os.args.slice(1, os.args.len)
	for name in names {
		s := http.get_text(url + '/jsmod/$name')
		mod := json.decode(Mod, s) or {
			errors++
			println('Error. Make sure you are online.')
			continue
		}
		
		if( '' == mod.url || '' == mod.name ){
			errors++
			// a possible 404 error, which means a missing module?
			println('Skipping module "$name", since it does not exist.')
			continue
		}

		final_module_path := '$home_vmodules/' + mod.name.replace('.', '/')

		println('Installing module "$name" from $mod.url to $final_module_path ...')
		_ := os.exec('git clone --depth=1 $mod.url $final_module_path') or {
			errors++
			println('Could not install module "$name" to "$final_module_path" .')
			println('Error details: $err')
			continue
		}
	}
	if errors > 0 {
		exit(1)
	}
}
