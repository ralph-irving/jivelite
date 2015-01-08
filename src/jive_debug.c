/*
** Copyright 2010 Logitech. All Rights Reserved.
**
** This file is licensed under BSD. Please see the LICENSE file for details.
*/


#include <time.h>
#include "common.h"


static struct log_category *log_debug_hooks;

struct perf_hook_data {
	Uint32 hook_stack;
	clock_t hook_threshold;
	clock_t kill_threshold;
	clock_t hook_ticks[100];
};

static void perf_hook(lua_State *L, lua_Debug *ar)
{
	struct perf_hook_data *hd;
	clock_t ticks, duration;

	ticks = clock();

	lua_pushlightuserdata(L, (char *)((unsigned long)L) + 1);
	lua_gettable(L, LUA_REGISTRYINDEX);
	hd = lua_touserdata(L, -1);

	if (!hd) {
		return;
	}

	if (ar->event == LUA_HOOKCALL) {
		if (hd->hook_stack < sizeof(hd->hook_ticks)) {
			hd->hook_ticks[hd->hook_stack] = ticks;
		}
		hd->hook_stack++;
	}
	else {
		hd->hook_stack--;
		duration = ticks - hd->hook_ticks[hd->hook_stack];

		if (hd->hook_stack < sizeof(hd->hook_ticks)
		    && duration > hd->hook_threshold) {

			lua_getfield(L, LUA_GLOBALSINDEX, "debug");
			if (!lua_istable(L, -1)) {
				lua_pop(L, 1);
				return;
			}
			lua_getfield(L, -1, "traceback");
			if (!lua_isfunction(L, -1)) {
				lua_pop(L, 2);
				return;
			}

			/* message */
			lua_pushstring(L, "Func took ");
			lua_pushinteger(L, (ticks - hd->hook_ticks[hd->hook_stack]) * 1000 / CLOCKS_PER_SEC);
			lua_pushstring(L, "ms");
			lua_concat(L, 3);
			/* skip this function */
			lua_pushinteger(L, 1);
			lua_call(L, 2, 1);  /* call debug.traceback */

			LOG_WARN(log_debug_hooks, "%s\n", lua_tostring(L, -1));
			
			lua_pop(L, 2);

			if (hd->kill_threshold && (duration > hd->kill_threshold)) {
				exit(-1);
			}
		}
	}
}


/*
 * Install a debug hook to report functions that take too long to
 * execute. Takes two arguments, the first is the time threshold
 * in ms. If the second optional time threashold is exceeded the
 * process is exited (to trigger the system crash actions).
 */
static int jiveL_perfhook(lua_State *L) {
	struct perf_hook_data *hd;

	if (lua_gethook(L) != NULL) {
		return 0;
	}

	lua_sethook(L, perf_hook, LUA_MASKCALL | LUA_MASKRET, 0);

	lua_pushlightuserdata(L, (char *)((unsigned long)L) + 1);
	hd = lua_newuserdata(L, sizeof(struct perf_hook_data));
	lua_settable(L, LUA_REGISTRYINDEX);

	memset(hd, 0, sizeof(*hd));
	hd->hook_threshold = (lua_tointeger(L, 1) * CLOCKS_PER_SEC) / 1000;
	hd->kill_threshold = (luaL_optinteger(L, 2, 0) * CLOCKS_PER_SEC) / 1000;

	return 0;
}


struct heap_state {
	long number;
	long integer;
	long boolean;
	long string;
	long table;
	long function;
	long thread;
	long userdata;
	long lightuserdata;
	long new_table;
	long new_function;
	long new_thread;
	long new_userdata;
	long new_lightuserdata;
	long free_table;
	long free_function;
	long free_thread;
	long free_userdata;
	long free_lightuserdata;
};


static int jiveL_seenobj(lua_State *L, int type, int index) {
	const void *ptr = lua_topointer(L, index);

	lua_pushinteger(L, (lua_Integer) ptr);
	lua_gettable(L, 1);

	if (lua_isnil(L, -1)) {
		lua_pop(L, 1);

		lua_pushinteger(L, (lua_Integer) ptr);
		lua_pushinteger(L, type);
		lua_settable(L, 1);

		return 0;
	}
	else {
		lua_pop(L, 1);

		return 1;
	}
}


static int jiveL_newobj(lua_State *L, int type, int index) {
	const void *ptr = lua_topointer(L, index);

	lua_pushinteger(L, (lua_Integer) ptr);
	lua_gettable(L, 2);

	if (lua_isnil(L, -1)) {
		lua_pop(L, 1);
		return 1;
	}
	else {
		lua_pop(L, 1);

		lua_pushinteger(L, (lua_Integer) ptr);
		lua_pushnil(L);
		lua_settable(L, 2);

		return 0;
	}
}


static void jiveL_inspect(lua_State *L, struct heap_state *s, int index) {
	int type = lua_type(L, index);

	/* max stack */
	if (!lua_checkstack(L, 4)) {
		printf("Stack error\n");
		return;
	}

	/* count object */
	switch (type) {
	case LUA_TNUMBER:
		/*
		if (lua_isinteger(L, index)) {
			s->integer++;
		}
		else {
			s->number++;
		}
		*/
		break;
	case LUA_TBOOLEAN:
		s->boolean++;
		break;
	case LUA_TSTRING:
		s->string++;
		break;
	case LUA_TTABLE:
		if (jiveL_seenobj(L, LUA_TTABLE, index)) {
			return;
		}

		s->table++;
		if (jiveL_newobj(L, LUA_TTABLE, index)) {
			s->new_table++;
		}

		lua_pushnil(L);
		while (lua_next(L, index) != 0) {
			int top = lua_gettop(L);

			jiveL_inspect(L, s, top - 1);
			jiveL_inspect(L, s, top);

			lua_pop(L, 1);
		}
		break;
	case LUA_TFUNCTION:
		if (jiveL_seenobj(L, LUA_TFUNCTION, index)) {
			return;
		}

		s->function++;
		if (jiveL_newobj(L, LUA_TFUNCTION, index)) {
			s->new_function++;
		}

		lua_getfenv(L, index);
		jiveL_inspect(L, s, lua_gettop(L));
		lua_pop(L, 1);
		break;
	case LUA_TUSERDATA:
		if (jiveL_seenobj(L, LUA_TUSERDATA, index)) {
			return;
		}

		s->userdata++;
		if (jiveL_newobj(L, LUA_TUSERDATA, index)) {
			s->new_userdata++;
		}
		break;
	case LUA_TTHREAD:
		if (jiveL_seenobj(L, LUA_TTHREAD, index)) {
			return;
		}

		s->thread++;
		if (jiveL_newobj(L, LUA_TTHREAD, index)) {
			s->new_thread++;
		}
		break;
	case LUA_TLIGHTUSERDATA:
		if (jiveL_seenobj(L, LUA_TLIGHTUSERDATA, index)) {
			return;
		}

		s->lightuserdata++;
		if (jiveL_newobj(L, LUA_TLIGHTUSERDATA, index)) {
			s->new_lightuserdata++;
		}
		break;
	}

	/* count meta table */
	if (lua_getmetatable(L, index)) {
		jiveL_inspect(L, s, lua_gettop(L));
		lua_pop(L, 1);
	}
}


/* Inspect heap */
static int jiveL_heap(lua_State *L) {
	struct heap_state s;

	memset(&s, 0, sizeof(s));

	/* heap history */
	lua_newtable(L);
	lua_getfield(L, LUA_REGISTRYINDEX, "heap_debug");

	/* stack is:
	 * 1: heap table
	 * 2: last heap table
	 */

	/* globals */
	jiveL_inspect(L, &s, LUA_GLOBALSINDEX);

	/* XXXX: environ? */

	/* count freed objects */
	lua_pushnil(L);
	while (lua_next(L, 2) != 0) {
		switch (lua_tointeger(L, -1)) {
		case LUA_TTABLE:
			s.free_table++;
			break;
		case LUA_TFUNCTION:
			s.free_function++;
			break;
		case LUA_TUSERDATA:
			s.free_userdata++;
			break;
		case LUA_TTHREAD:
			s.free_thread++;
			break;
		case LUA_TLIGHTUSERDATA:
			s.free_lightuserdata++;
			break;
		}

		lua_pop(L, 1);
	}

	/* store heap history */
	lua_pop(L, 1);
	lua_setfield(L, LUA_REGISTRYINDEX, "heap_debug");

	/* results */
	lua_newtable(L);

	lua_pushinteger(L, s.number);
	lua_setfield(L, -2, "number");

	lua_pushinteger(L, s.integer);
	lua_setfield(L, -2, "integer");

	lua_pushinteger(L, s.boolean);
	lua_setfield(L, -2, "boolean");

	lua_pushinteger(L, s.string);
	lua_setfield(L, -2, "string");

	lua_pushinteger(L, s.table);
	lua_setfield(L, -2, "table");

	lua_pushinteger(L, s.new_table);
	lua_setfield(L, -2, "new_table");

	lua_pushinteger(L, s.free_table);
	lua_setfield(L, -2, "free_table");

	lua_pushinteger(L, s.function);
	lua_setfield(L, -2, "function");

	lua_pushinteger(L, s.new_function);
	lua_setfield(L, -2, "new_function");

	lua_pushinteger(L, s.free_function);
	lua_setfield(L, -2, "free_function");

	lua_pushinteger(L, s.thread);
	lua_setfield(L, -2, "thread");

	lua_pushinteger(L, s.new_thread);
	lua_setfield(L, -2, "new_thread");

	lua_pushinteger(L, s.free_thread);
	lua_setfield(L, -2, "free_thread");

	lua_pushinteger(L, s.userdata);
	lua_setfield(L, -2, "userdata");

	lua_pushinteger(L, s.new_userdata);
	lua_setfield(L, -2, "new_userdata");

	lua_pushinteger(L, s.free_userdata);
	lua_setfield(L, -2, "free_userdata");

	lua_pushinteger(L, s.lightuserdata);
	lua_setfield(L, -2, "lightuserdata");

	lua_pushinteger(L, s.new_lightuserdata);
	lua_setfield(L, -2, "new_lightuserdata");

	lua_pushinteger(L, s.free_lightuserdata);
	lua_setfield(L, -2, "free_lightuserdata");

	return 1;
}


static const struct luaL_Reg debug_funcs[] = {
	{ "perfhook", jiveL_perfhook },
	{ "heap", jiveL_heap },
	{ NULL, NULL }
};


int luaopen_jive_debug(lua_State *L) {
	log_debug_hooks = log_category_get("lua.hooks");

	/* heap history */
	lua_newtable(L);
	lua_setfield(L, LUA_REGISTRYINDEX, "heap_debug");

	luaL_register(L, "jive", debug_funcs);
	return 1;
}
