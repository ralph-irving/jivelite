/*
** Copyright 2010 Logitech. All Rights Reserved.
**
** This file is licensed under BSD. Please see the LICENSE file for details.
*/


#include "common.h"
#include "jive.h"
#include "version.h"


static char *mac_address;
static char *uuid;
static char *arch;
static char *machine;
static int hardware_rev;
static char *homedir;
static char *resource_path = NULL;

// public API
const char * system_get_machine(void) {
	return machine;
}

const char * system_get_arch(void) {
	return arch;
}

const char * system_get_version(void) {
	return JIVE_VERSION;
}

const char * system_get_uuid_char(void) {
	return uuid;
}


static int system_get_mac_address(lua_State *L) {
	if (mac_address) {
		lua_pushstring(L, mac_address);
	}
	else {
		lua_pushnil(L);
	}
	return 1;
}


static int system_get_ip_address(lua_State *L) {
	char *addr = platform_get_ip_address();
	if (addr) {
		lua_pushstring(L, addr);
	} else {
		lua_pushnil(L);
	}
	return 1;
}


static int system_get_uuid(lua_State *L) {
	if (uuid) {
		lua_pushstring(L, uuid);
	}
	else {
		lua_pushnil(L);
	}
	return 1;
}


static int system_lua_get_arch(lua_State *L) {
	if (arch) {
		lua_pushstring(L, arch);
	}
	else {
		lua_pushnil(L);
	}
	return 1;
}


static int system_lua_get_machine(lua_State *L) {
	if (machine) {
		lua_pushstring(L, machine);
		lua_pushinteger(L, hardware_rev);
		return 2;
	}
	else {
		lua_pushnil(L);
		return 1;
	}
}


static int system_get_uptime(lua_State *L) {
	Uint32 uptime;
	int updays, upminutes, uphours;

	// FIXME wraps around after 49.7 days
	uptime = jive_jiffies() / 1000;

	updays = (int) uptime / (60*60*24);
	upminutes = (int) uptime / 60;
	uphours = (upminutes / 60) % 24;
	upminutes %= 60;
	
	lua_newtable(L);
	lua_pushinteger(L, updays);
	lua_setfield(L, -2, "days");

	lua_pushinteger(L, uphours);
	lua_setfield(L, -2, "hours");

	lua_pushinteger(L, upminutes);
	lua_setfield(L, -2, "minutes");

	return 1;
}


static int system_get_user_dir(lua_State *L) {
	lua_pushfstring(L, "%s/userpath", homedir);
	return 1;
}


static int system_init(lua_State *L) {
	/* stack is:
	 * 1: system
	 * 2: table
	 */

	lua_getfield(L, 2, "macAddress");
	if (!lua_isnil(L, -1)) {
		char *ptr;
		
		if (mac_address) {
			free(mac_address);
		}
		mac_address = strdup(lua_tostring(L, -1));

		ptr = mac_address;
		while (*ptr) {
			*ptr = tolower(*ptr);
			ptr++;
		}
	}
	lua_pop(L, 1);

	lua_getfield(L, 2, "uuid");
	if (!lua_isnil(L, -1)) {
		if (uuid) {
			free(uuid);
		}
		uuid = strdup(lua_tostring(L, -1));
	}
	lua_pop(L, 1);

	lua_getfield(L, 2, "machine");
	if (!lua_isnil(L, -1)) {
		if (machine) {
			free(machine);
		}
		machine = strdup(lua_tostring(L, -1));
	}
	lua_pop(L, 1);

	lua_getfield(L, 2, "revision");
	if (!lua_isnil(L, -1)) {
		hardware_rev = lua_tointeger(L, -1);
	}
	lua_pop(L, 1);

	return 0;
}


static int system_find_file(lua_State *L) {
	char fullpath[PATH_MAX];
	const char *path;

	/* stack is:
	 * 1: framework
	 * 2: path
	 */

	path = luaL_checkstring(L, 2);

	if (jive_find_file(path, fullpath)) {
		lua_pushstring(L, fullpath);
	}
	else {
		lua_pushnil(L);
	}

	return 1;
}


static int system_init_file_path(lua_State *L) {
	const char *lua_path;
	char *ptr;

	/* set jiveui_path from lua path */
	lua_getglobal(L, "package");
	if (!lua_istable(L, -1)) {
		lua_pop(L, 1);
		return 0;
	}
	
	lua_getfield(L, -1, "path");
	if (!lua_isstring(L, -1)) {
		lua_pop(L, 2);
		return 0;
	}

	lua_path = lua_tostring(L, -1);

	if (resource_path) {
		free(resource_path);
	}
	resource_path = malloc(strlen(lua_path) + 1);

	/* convert from lua path into jive path */
	ptr = resource_path;
	while (*lua_path) {
		switch (*lua_path) {
		case '?':
			while (*lua_path && *lua_path != ';') {
				lua_path++;
			}
			break;
			
		case ';':
			*ptr++ = ';';
			while (*lua_path && *lua_path == ';') {
				lua_path++;
			}
			break;
			
		default:
			*ptr++ = *lua_path++;
		}
	}
	*ptr = '\0';
	
	lua_pop(L, 2);
	return 0;
}


int jive_find_file(const char *path, char *fullpath) {
	char *begin, *end;
	FILE *fp;

	/* absolute/relative path */
	fp = fopen(path, "r");
	if (fp) {
		fclose(fp);
		strcpy(fullpath, path);
		return 1;
	}

	/* search lua path */
	begin = resource_path;
	end = strchr(begin, ';');

	while (end) {
#if defined(WIN32)
		char *tmp;
#endif

		strncpy(fullpath, begin, end-begin);
		strcpy(fullpath + (end-begin), path);

#if defined(WIN32)
		/* Convert from UNIX style paths */
		tmp = fullpath;
		while (*tmp) {
			if (*tmp == '/') {
				*tmp = '\\';
			}
			++tmp;
		}
#endif

		fp = fopen(fullpath, "r");
		if (fp) {
			fclose(fp);
			return 1;
		}

		begin = end + 1;
		end = strchr(begin, ';');
	}

	return 0;
}


/*
 * 
 */
static int system_atomic_write(lua_State *L)
{
	const char *fname, *fdata;
	char *tname;
	size_t n, len;
	FILE *fp;
#if HAVE_FSYNC && !defined(FSYNC_WORKAROUND_ENABLED)
	DIR *dp;
#endif
	fname = lua_tostring(L, 2);
	fdata = lua_tolstring(L, 3, &len);

	tname = alloca(strlen(fname) + 5);
	strcpy(tname, fname);
	strcat(tname, ".new");
	
	if (!(fp = fopen(tname, "w"))) {
		return luaL_error(L, "fopen: %s", strerror(errno));
	}

	n = 0;
	while (n < len) {
		n += fwrite(fdata + n, 1, len - n, fp);

		if (ferror(fp)) {
			fclose(fp);
			return luaL_error(L, "fwrite: %s", strerror(errno));
		}
	}

	if (fflush(fp) != 0) {
		fclose(fp);
		return luaL_error(L, "fflush: %s", strerror(errno));
	}
#if HAVE_FSYNC && !defined(FSYNC_WORKAROUND_ENABLED)
	if (fsync(fileno(fp)) != 0) {
		fclose(fp);
		return luaL_error(L, "fsync: %s", strerror(errno));
	}
#endif
	if (fclose(fp) != 0) {
		return luaL_error(L, "fclose: %s", strerror(errno));
	}

#if defined(WIN32)
	/* windows systems must delete old file first */
	if (_access_s(fname, 0) == 0) {
		if (remove(fname) != 0) {
			return luaL_error(L, "remove old file: %s", strerror(errno));
		}
	}
#endif

	if (rename(tname, fname) != 0) {
		return luaL_error(L, "rename: %s", strerror(errno));
	}

#ifdef FSYNC_WORKAROUND_ENABLED
	/* sync filesystem if fsync is broken */
	sync();
#elif HAVE_FSYNC
	if (!(dp = opendir(dirname(tname)))) {
		return luaL_error(L, "opendir: %s", strerror(errno));
	}
	
	if (fsync(dirfd(dp)) != 0) {
		closedir(dp);
		return luaL_error(L, "fsync: %s", strerror(errno));
	}

	if (closedir(dp) != 0) {
		return luaL_error(L, "closedir: %s", strerror(errno));
	}
#endif

	return 0;
}


static const struct luaL_Reg jive_system_methods[] = {
	{ "getArch", system_lua_get_arch },
	{ "getMachine", system_lua_get_machine },
	{ "getMacAddress", system_get_mac_address },
	{ "getIPAddress", system_get_ip_address },
	{ "getUUID", system_get_uuid },
	{ "getUptime", system_get_uptime },
	{ "getUserDir", system_get_user_dir },
	{ "findFile", system_find_file },
	{ "atomicWrite", system_atomic_write },
	{ "init", system_init },
	{ NULL, NULL }
};


int luaopen_jive_system(lua_State *L) {
	/* register methods */
	lua_getglobal(L, "jive");

	lua_newtable(L);
	luaL_register(L, NULL, jive_system_methods);
	lua_setfield(L, -2, "System");

	lua_pop(L, 1);
	return 0;
}


int jive_system_init(lua_State *L) {
	const char *homeenv = getenv("JIVELITE_HOME");
	char *ptr;

	mac_address = platform_get_mac_address();
	if (mac_address) {
		ptr = mac_address;
		while (*ptr) {
			*ptr = tolower(*ptr);
			ptr++;
		}
	}

	arch = platform_get_arch();
	machine = strdup("jivelite");

	/* add homedir to lua patch */
	if (homeenv) {
		homedir = strdup(homeenv);
	}
	else {
		homedir = platform_get_home_dir();
	}

	lua_getglobal(L, "package");
	if (lua_istable(L, -1)) {
		luaL_Buffer b;
		luaL_buffinit(L, &b);

		/* add homedir */
		luaL_addstring(&b, homedir);
		luaL_addstring(&b, DIR_SEPARATOR_STR "userpath" DIR_SEPARATOR_STR "?.lua;");
		
		/* existing lua path */
		lua_getfield(L, -1, "path");
		luaL_addvalue(&b);
		luaL_addstring(&b, ";");

		/* store new path */
		luaL_pushresult(&b);
		lua_setfield(L, -2, "path");
	}

	system_init_file_path(L);

	return 0;
}
