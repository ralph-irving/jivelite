/*
** Copyright 2010 Logitech. All Rights Reserved.
**
** This file is licensed under BSD. Please see the LICENSE file for details.
*/


/* Standard includes */
#include "common.h"
#include "version.h"

/* Lua API */
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

/* Module initialization functions */
extern int jive_system_init(lua_State *L);
extern int jive_log_init(lua_State *L);

extern int luaopen_jive_system(lua_State *L);
extern int luaopen_log(lua_State *L);
extern int luaopen_jive(lua_State *L);
extern int luaopen_jive_ui_framework(lua_State *L);
extern int luaopen_jive_net_dns(lua_State *L);
extern int luaopen_jive_debug(lua_State *L);
#if !defined(WIN32)
extern int luaopen_visualizer(lua_State *L);
#endif

/* LUA_DEFAULT_SCRIPT
** The default script this program runs, unless another script is given
** on the command line
*/
#define LUA_DEFAULT_SCRIPT "jive.JiveMain"

/* LUA_DEFAULT_*_PATH
** Try relative path to binary first then fixed path to system install
*/
#define LUA_DEFAULT_REL_PATH "../share/jive"
#ifdef __sun
#define LUA_DEFAULT_FIX_PATH "/opt/jivelite/share/jive"
#else
#define LUA_DEFAULT_FIX_PATH "/usr/share/jive"
#endif


/* GLOBALS
*/

// our lua state
static lua_State *globalL = NULL;


/* lmessage
** prints a message to std err. pname is optional 
*/
static void l_message (const char *pname, const char *msg) {

	if (pname) {
		fprintf(stderr, "%s: ", pname);
	}
		
	fprintf(stderr, "%s\n", msg);
	fflush(stderr);
}


/******************************************************************************/
/* Code below is specific to jive                                       */
/******************************************************************************/


static void jive_openlibs(lua_State *L) {
	// jive version
	lua_newtable(L);
	lua_pushstring(L, JIVE_VERSION);
	lua_setfield(L, -2, "JIVE_VERSION");
	lua_setglobal(L, "jive");

	// jive lua extensions
	lua_pushcfunction(L, luaopen_jive);
	lua_call(L, 0, 0);

	lua_pushcfunction(L, luaopen_jive_ui_framework);
	lua_call(L, 0, 0);

	lua_pushcfunction(L, luaopen_jive_net_dns);
	lua_call(L, 0, 0);

	lua_pushcfunction(L, luaopen_jive_debug);
	lua_call(L, 0, 0);

	lua_pushcfunction(L, luaopen_jive_system);
	lua_call(L, 0, 0);

	lua_pushcfunction(L, luaopen_log);
	lua_call(L, 0, 0);

#if !defined(WIN32)
	lua_pushcfunction(L, luaopen_visualizer);
	lua_call(L, 0, 0); 
#endif
}


#if defined(WIN32)

#include <windows.h>
#include <direct.h>

char *realpath(const char *filename, char *resolved_name) {
	GetFullPathName(filename, PATH_MAX, resolved_name, NULL);
	return resolved_name;
}

char *dirname(char *path) {
	// FIXME
	return path;
}
#endif


/* paths_setup
** Modify the lua path and cpath, prepending standard directories
** relative to this executable.
*/
static void paths_setup(lua_State *L, char *app) {
	char *temp, *binpath, *path;
	
	temp = malloc(PATH_MAX+1);
	if (!temp) {
		l_message("Error", "malloc failure for temp");
		exit(-1);
	}
	binpath = malloc(PATH_MAX+1);
	if (!binpath) {
		l_message("Error", "malloc failure for binpath");
		exit(-1);
	}
	path = malloc(PATH_MAX+1);
	if (!path) {
		l_message("Error", "malloc failure for path");
		exit(-1);
	}

	// full path to jive binary
	if (app[0] == '/') {
		// we were called with a full path
		strcpy(path, app);
	}
	else {
		// add working dir + app and resolve
		getcwd(temp, PATH_MAX+1);
		strcat(temp, "/");       
		strcat(temp, app);
		realpath(temp, path);
	}

	// directory containing jive
	strcpy(binpath, dirname(path));

	// set paths in lua (package.path & package cpath)
	lua_getglobal(L, "package");
	if (lua_istable(L, -1)) {
		luaL_Buffer b;
		luaL_buffinit(L, &b);

		// default lua path
		lua_getfield(L, -1, "path");
		luaL_addvalue(&b);
		luaL_addstring(&b, ";");

		// lua path relative to executable
#if !defined(WIN32)
		strcpy(temp, binpath);
		strcat(temp, "/../share/lua/5.1");
		realpath(temp, path);
#endif

		luaL_addstring(&b, path);
		luaL_addstring(&b, DIR_SEPARATOR_STR "?.lua;");
		luaL_addstring(&b, path);
		luaL_addstring(&b, DIR_SEPARATOR_STR "?" DIR_SEPARATOR_STR "?.lua;");

		// script path relative to executale
		strcpy(temp, binpath);
		strcat(temp, "/" LUA_DEFAULT_REL_PATH);
		realpath(temp, path);

		luaL_addstring(&b, path);
		luaL_addstring(&b, DIR_SEPARATOR_STR "?.lua;");

		// script fixed path for system install
		luaL_addstring(&b, LUA_DEFAULT_FIX_PATH);
		luaL_addstring(&b, DIR_SEPARATOR_STR "?.lua;");
		
		// set lua path
		luaL_pushresult(&b);
		lua_setfield(L, -2, "path");

		luaL_buffinit(L, &b);

		// default lua cpath
		lua_getfield(L, -1, "cpath");
		luaL_addvalue(&b);
		luaL_addstring(&b, ";");

		// lua cpath
#if !defined(WIN32)
		strcpy(temp, binpath);
		strcat(temp, "/../lib/lua/5.1");
		realpath(temp, path);
#endif

		luaL_addstring(&b, path);
		luaL_addstring(&b, DIR_SEPARATOR_STR "?." LIBRARY_EXT ";");
		luaL_addstring(&b, path);
		luaL_addstring(&b, DIR_SEPARATOR_STR "?" DIR_SEPARATOR_STR "core." LIBRARY_EXT ";");

		// cpath relative to executable
		strcpy(temp, binpath);
		strcat(temp, "/" LUA_DEFAULT_REL_PATH);
		realpath(temp, path);

		luaL_addstring(&b, path);
		luaL_addstring(&b, DIR_SEPARATOR_STR "?." LIBRARY_EXT ";");
		luaL_addstring(&b, path);
		luaL_addstring(&b, DIR_SEPARATOR_STR "?" DIR_SEPARATOR_STR "core." LIBRARY_EXT ";");
		
		// fixed cpath for sytem install
		luaL_addstring(&b, LUA_DEFAULT_FIX_PATH);
		luaL_addstring(&b, DIR_SEPARATOR_STR "?." LIBRARY_EXT ";");
		luaL_addstring(&b, LUA_DEFAULT_FIX_PATH);
		luaL_addstring(&b, DIR_SEPARATOR_STR "?" DIR_SEPARATOR_STR "core." LIBRARY_EXT ";");

		// set lua cpath
		luaL_pushresult(&b);

		lua_setfield(L, -2, "cpath");
	}
	else {
		l_message("Error", "'package' is not a table");
	}

	// pop package table off the stack
	lua_pop(L, 1); 

	free(temp);
	free(binpath);
	free(path);
}


/******************************************************************************/
/* Code below almost identical to lua code                                    */
/******************************************************************************/

/* report
** prints an error message from the lua stack if any 
*/
static int report (lua_State *L, int status) {

	if (status && !lua_isnil(L, -1)) {
	
		const char *msg = lua_tostring(L, -1);
		if (msg == NULL) {
			msg = "(error object is not a string)";
		}
		l_message("Jive", msg);
		lua_pop(L, 1);
  	}
	return status;
}


/* lstop
** manages signals during processing
*/
static void lstop (lua_State *L, lua_Debug *ar) {
	(void)ar;  /* unused arg. */
	
	lua_sethook(L, NULL, 0, 0);
	luaL_error(L, "interrupted!");
}

/* laction
** manages signals during processing
*/
static void laction (int i) {

	// if another SIGINT happens before lstop
	// terminate process (default action) 
	signal(i, SIG_DFL);
	
	lua_sethook(globalL, lstop, LUA_MASKCALL | LUA_MASKRET | LUA_MASKCOUNT, 1);
}

/* traceback
** provides error messages
*/
static int traceback (lua_State *L) {
	
	lua_getfield(L, LUA_GLOBALSINDEX, "debug");
	if (!lua_istable(L, -1)) {
		lua_pop(L, 1);
		return 1;
	}
	
	lua_getfield(L, -1, "traceback");
	if (!lua_isfunction(L, -1)) {
		lua_pop(L, 2);
		return 1;
	}
	
	// pass error message
	lua_pushvalue(L, 1); 
	
	// skip this function and traceback
	lua_pushinteger(L, 2);
	
	// call debug.traceback
	lua_call(L, 2, 1);
	return 1;
}


/* getargs
** pushes arguments on the lua stack for the called script
*/
static int getargs (lua_State *L, char **argv, int n) {
	int narg;
	int i;
	int argc = 0;
	
	// count total number of arguments
	while (argv[argc]) {
		argc++;
	}
	
	// number of arguments to the script
	// => all arguments minus program name [0] and any other arguments found 
	// before
	narg = argc - (n + 1);
	
	// check stack has enough room
	luaL_checkstack(L, narg + 3, "too many arguments to script");
	
	// push arguments
	for (i=n+1; i < argc; i++) {
		lua_pushstring(L, argv[i]);
	}
	
	// create a table with narg array elements and n+1 non array elements
	lua_createtable(L, narg, n + 1);
	for (i=0; i < argc; i++) {
		// push the argument
		lua_pushstring(L, argv[i]);
		// insert into table (-2 on stack) [i-n] value popped from stack
		lua_rawseti(L, -2, i - n);
	}
	
	return narg;
}


/* docall
** calls the script
*/
static int docall (lua_State *L, int narg, int clear) {
	int status;
  
	// get the function index
	int base = lua_gettop(L) - narg;
  
	// push traceback function
	lua_pushcfunction(L, traceback);
  
	// put it under chunk and args
	lua_insert(L, base); 
  
	signal(SIGINT, laction);
	status = lua_pcall(L, narg, (clear ? 0 : LUA_MULTRET), base);
	signal(SIGINT, SIG_DFL);
  
	// remove traceback function
	lua_remove(L, base);  

	return status;
}


/* handle_script
** does the work, load the script
*/
static int handle_script (lua_State *L, char **argv, int n) {
	int status, narg;
	
	// do we have a script?
	// set fname to the name of the script to execute
	const char *fname;
	if (n != 0) {
		fname = argv[n];
	}
	else {
		fname = LUA_DEFAULT_SCRIPT;
	}

	// use 'require' to search the lua path
	lua_getglobal(L, "require");
	lua_pushstring(L, fname);

	// collect arguments in a table on stack
	narg = getargs(L, argv, n);
	
	// name table on the stack
	lua_setglobal(L, "arg");
	
	// load and run the script
	status = docall(L, narg + 1, 0);
	return report(L, status);
}


/* Smain
** used to transfer arguments and status to protected main 
*/
struct Smain {
	int argc;
	char **argv;
	int status;
};


#ifdef NO_STDIO_REDIRECT
static void get_temp_dir(char *path) {
	strcpy(path, getenv("TEMP"));	
}

static void get_stdout_file_path(char *path) {
	get_temp_dir(path);
	strcat(path, "/stdout-JiveLite.txt");
}

static void get_stderr_file_path(char *path) {
	get_temp_dir(path);
	strcat(path, "/stderr-JiveLite.txt");
}

static void redirect_stdio() {
	char *stdoutpath, *stderrpath;

	stdoutpath = malloc(PATH_MAX+1);
	if (!stdoutpath) {
		l_message("Error", "malloc failure for stdoutpath");
		exit(-1);
	}
	stderrpath = malloc(PATH_MAX+1);
	if (!stderrpath) {
		l_message("Error", "stderrpath failure for binpath");
		exit(-1);
	}

	get_stdout_file_path(stdoutpath);
	get_stderr_file_path(stderrpath);
    	
	freopen(stdoutpath, TEXT("w"), stdout);
	freopen(stderrpath, TEXT("w"), stderr);
	
	free(stdoutpath);
	free(stderrpath);
}
#endif

/* pmain
** our main, called in lua protected mode by main
*/
static int pmain (lua_State *L) {
	
	// fetch *Smain from the stack
	struct Smain *s = (struct Smain *)lua_touserdata(L, 1);
	int script = 0;
	char **argv = s->argv;
	
	// set our global state
	globalL = L;
	
	// stop collector during initialization
	lua_gc(L, LUA_GCSTOP, 0);

	// open lua libraries
	luaL_openlibs(L);

	// configure paths
	paths_setup(L, argv[0]);

	// init system and platform information
	jive_system_init(L);

	// init logging
	jive_log_init(L);

	// open jive libraries
	jive_openlibs(L);
	
	// restart collector
	lua_gc(L, LUA_GCRESTART, 0);

#ifdef NO_STDIO_REDIRECT
	/* SDL not redirecting. Instead, put console output in user writable directory - used for Vista, for instance which disallows writing to app dir */ 
	redirect_stdio();	
#endif

	/* 
	// do we have an argument? - disabled as we do not want to run alternative scripts, but want to see the arguments
	if (argv[1] != NULL) {
		script = 1;
	}
	*/
	
	// do a script
	s->status = handle_script(L, argv, script);
	if (s->status != 0) {
		return 0;
	}

	return 0;
}


/* main 
*/
int main (int argc, char **argv) {
	int status;
	struct Smain s;
	lua_State *L;

	// say hello
#if !defined(WIN32)
	l_message(NULL, "\nJiveLite " JIVE_VERSION);
#endif
	
	// create state
	L = lua_open();
	if (L == NULL) {
		l_message(argv[0], "cannot create state: not enough memory");
		return EXIT_FAILURE;
	}
	
	// call our main in protected mode
	s.argc = argc;
	s.argv = argv;
	status = lua_cpcall(L, &pmain, &s);
	
	// report on any error
	report(L, status);
	
	// close state
	lua_close(L);

	// report status to caller
	return (status || s.status) ? EXIT_FAILURE : EXIT_SUCCESS;
}


