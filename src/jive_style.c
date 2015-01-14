/*
** Copyright 2010 Logitech. All Rights Reserved.
**
** This file is licensed under BSD. Please see the LICENSE file for details.
*/

#include "common.h"
#include "jive.h"


static void get_jive_ui_style(lua_State *L) {
	lua_getglobal(L, "jive");
	luaL_checktype(L, -1, LUA_TTABLE);

	lua_getfield(L, -1, "ui");
	luaL_checktype(L, -1, LUA_TTABLE);

	lua_getfield(L, -1, "style");
	luaL_checktype(L, -1, LUA_TTABLE);

	lua_remove(L, -2);
	lua_remove(L, -2);
}

static int search_path(lua_State *L, int widget, char *path, const char *key) {
	char *tok = strtok(path, ".");
	while (tok) {
		lua_pushstring(L, tok);
		lua_gettable(L, -2);

		if (lua_isnil(L, -1)) {
			lua_pop(L, 1);
			return 0;
		}

		luaL_checktype(L, -1, LUA_TTABLE);
		lua_replace(L, -2);

		tok = strtok(NULL, ".");
	}

	lua_pushstring(L, key);
	lua_gettable(L, -2);

	return 1;
}

static int jiveL_style_find_value(lua_State *L) {
	/* stack is:
	 * 1: widget
	 * 2: skin
	 * 3: path
	 * 4: key
	 */

	const char *path = lua_tostring(L, 3);
	const char *key = lua_tostring(L, 4);

	char *ptr = (char *) path;
	while (ptr) {
		char *tmp = strdup(ptr);

		lua_pushvalue(L, 2);
		if (search_path(L, 1, tmp, key) && !lua_isnil(L, -1)) {
			free(tmp);

			lua_remove(L, -2);
			return 1;
		}
		free(tmp);
		lua_pop(L, 1);

		ptr = strchr(ptr, '.');
		if (ptr) {
			ptr++;
		}
	}

	lua_pushnil(L);
	return 1;
}

inline static void debug_style(lua_State *L, const char *path, const char *key) {
	if (!IS_LOG_PRIORITY(log_ui_draw, LOG_PRIORITY_DEBUG)) {
		return;
	}

	lua_getglobal(L, "tostring");
	lua_pushvalue(L, -2);
	lua_call(L, 1, 1);

	lua_getglobal(L, "tostring");
	lua_pushvalue(L, 1);
	lua_call(L, 1, 1);

	LOG_DEBUG(log_ui_draw, "style: [%s] %s : %s = %s", lua_tostring(L, -1), path, key, lua_tostring(L, -2));
	lua_pop(L, 2);
}

static int STYLE_VALUE_NIL;

int jiveL_style_rawvalue(lua_State *L) {
	const char *key, *path;
	int pathidx;

	/* stack is:
	 * 1: widget
	 * 2: key
	 * 3: default
	 * 4... args
	 */

	/* Make sure we have a default value */
	if (lua_gettop(L) == 2) {
		lua_pushnil(L);
	}

	key = lua_tostring(L, 2);

	/* Concatenate style paths */
	lua_getfield(L, 1, "_stylePath");
	if (lua_isnil(L, -1)) {
		lua_pop(L, 1);

		lua_pushcfunction(L, jiveL_style_path);
		lua_pushvalue(L, 1);
		lua_call(L, 1, 1);
	}

	pathidx = lua_gettop(L);
	path = lua_tostring(L, -1);

	/* check cache */
	lua_getfield(L, LUA_REGISTRYINDEX, "jiveStyleCache");
	if (lua_isnil(L, -1)) {
		lua_pop(L, 1);

		lua_newtable(L);
		lua_pushvalue(L, -1);
		lua_setfield(L, LUA_REGISTRYINDEX, "jiveStyleCache");
	}

	lua_pushvalue(L, pathidx); // path
	lua_gettable(L, -2);
	if (lua_isnil(L, -1)) {
		lua_pop(L, 1);

		lua_newtable(L);

		lua_pushvalue(L, pathidx); // path
		lua_pushvalue(L, -2);
		lua_settable(L, -4);
	}

	lua_getfield(L, -1, key);
	if (lua_isnil(L, -1)) {
		lua_pop(L, 1);

		// find value
		lua_pushcfunction(L, jiveL_style_find_value);
		lua_pushvalue(L, 1); // widget
		get_jive_ui_style(L); // skin
		lua_pushvalue(L, pathidx);
		lua_pushvalue(L, 2); // key
		lua_call(L, 4, 1);

		if (lua_isnil(L, -1)) {
			/* use a marker for nil */
			lua_pushlightuserdata(L, &STYLE_VALUE_NIL);
		}
		else {
			lua_pushvalue(L, -1);
		}
		lua_setfield(L, -3, key);

		debug_style(L, path, key);
	}

	/* nil marker */
	lua_pushlightuserdata(L, &STYLE_VALUE_NIL);
	if (lua_equal(L, -1, -2) == 1) {
		lua_pushnil(L);
		lua_replace(L, -3);
	}
	lua_pop(L, 1);

	if (!lua_isnil(L, -1)) {
		/* return skin value */
		return 1;
	}

	/* per widget skin */
	if (jive_getmethod(L, 1, "getWindow")) {
		lua_pushvalue(L, 1);
		lua_call(L, 1, 1);

		if (!lua_isnil(L, -1)) {
			lua_getfield(L, -1, "skin");
			if (!lua_isnil(L, -1)) {
				lua_pushcfunction(L, jiveL_style_find_value);
				lua_pushvalue(L, 1); // widget
				lua_pushvalue(L, -3); // skin
				lua_pushvalue(L, pathidx);
				lua_pushvalue(L, 2); // key
				lua_call(L, 4, 1);

				if (!lua_isnil(L, -1)) {
					debug_style(L, path, key);

					return 1;
				}
				lua_pop(L, 1);
			}
		}
		lua_pop(L, 1);
	}

	/* default value */
	lua_pop(L, 1);
	lua_pushvalue(L, 3);

	return 1;
}


int jiveL_style_value(lua_State *L) {
	int nargs;

	/* stack is:
	 * 1: widget
	 * 2: key
	 * 3: default
	 * 4... args
	 */

	nargs = lua_gettop(L) - 3;

	jiveL_style_rawvalue(L);

	/* is the value a function? */
	if (lua_isfunction(L, -1)) {
		int i;

		// push widget
		lua_pushvalue(L, 1);

		// push optional arguments
		for (i = 0; i < nargs; i++) {
			lua_pushvalue(L, 4 + i);
		}

		if (lua_pcall(L, 1 + nargs, 1, 0) != 0) {
			LOG_WARN(log_ui_draw, "error running style function:\n\t%s\n", lua_tostring(L, -1));
			lua_pop(L, 1);
			return 0;
		}
	}

	return 1;
}


int jiveL_style_array_value(lua_State *L) {

	/* stack is:
	 * 1: widget
	 * 2: array key
	 * 3: array index
	 * 4: value key
	 * 5: default
	 */

	lua_pushnil(L);
	lua_insert(L, 3);

	/* fetch array */
	jiveL_style_rawvalue(L);
	if (lua_type(L, -1) != LUA_TTABLE) {
		lua_pushvalue(L, 6);
		return 1;
	}

	/* fetch index */
	lua_pushvalue(L, 4);
	lua_gettable(L, -2);
	if (lua_isnil(L, -1)) {
		lua_pushvalue(L, 6);
		return 1;
	}

	/* fetch value */
	lua_pushvalue(L, 5);
	lua_gettable(L, -2);
	if (lua_isnil(L, -1)) {
		lua_pushvalue(L, 6);
		return 1;
	}

	return 1;
}


int jiveL_style_path(lua_State *L) {
	int numStrings = 0;

	lua_pushvalue(L, 1);
	while (!lua_isnil(L, -1)) {
		lua_getfield(L, -1, "style");
		if (!lua_isnil(L, -1)) {
			lua_insert(L, 2);
			lua_pushstring(L, ".");
			lua_insert(L, 2);
			numStrings += 2;
		}
		else {
			lua_pop(L, 1);
		}
		
		lua_getfield(L, -1, "styleModifier");
		if (!lua_isnil(L, -1)) {
			lua_insert(L, 2);
			lua_pushstring(L, ".");
			lua_insert(L, 2);
			numStrings += 2;
		}
		else {
		    lua_pop(L, 1);
		}

		lua_getfield(L, -1, "parent");
		lua_replace(L, -2);
	}
	lua_pop(L, 1);

	lua_concat(L, numStrings - 1);
	lua_remove(L, -2);

	lua_pushvalue(L, -1);
	lua_setfield(L, 1, "_stylePath");

	return 1;
}


int jive_style_int(lua_State *L, int index, const char *key, int def) {
	int value;

	JIVEL_STACK_CHECK_BEGIN(L);

	lua_pushcfunction(L, jiveL_style_value);
	lua_pushvalue(L, index);
	lua_pushstring(L, key);
	lua_pushinteger(L, def);
	lua_call(L, 3, 1);

	if (lua_isboolean(L, -1)) {
		value = lua_toboolean(L, -1);
	}
	else {
		value = lua_tointeger(L, -1);
	}
	lua_pop(L, 1);

	JIVEL_STACK_CHECK_END(L);

	return value;
}


int jiveL_style_color(lua_State *L) {
	Uint32 r, g, b, a;
	
	/* stack is:
	 * 1: widget
	 * 2: key
	 * 3: default
	 */

	jiveL_style_value(L);

	if (lua_isnil(L, -1)) {
		return 1;
	}

	if (!lua_istable(L, -1)) {
		luaL_error(L, "invalid component in style color, table expected");
	}

	/* use empty table for not set */
	if (lua_objlen(L, -1) == 0) {
		lua_pop(L, 1);

		lua_pushnil(L);
		return 1;
	}

	lua_rawgeti(L, -1, 1);
	lua_rawgeti(L, -2, 2);
	lua_rawgeti(L, -3, 3);
	lua_rawgeti(L, -4, 4);

	r = (int) luaL_checknumber(L, -4);
	g = (int) luaL_checknumber(L, -3);
	b = (int) luaL_checknumber(L, -2);
	if (lua_isnumber(L, -1)) {
		a = (int) luaL_checknumber(L, -1);
	}
	else {
		a = 0xFF;
	}

	lua_pop(L, 5);
 
	lua_pushnumber(L, (lua_Integer)((r << 24) | (g << 16) | (b << 8) | a) );
	return 1;
}

int jiveL_style_array_color(lua_State *L) {
	Uint32 r, g, b, a;
	
	/* stack is:
	 * 1: widget
	 * 2: key
	 * 3: default
	 */

	jiveL_style_array_value(L);

	//todo: this is an exact copy of the code in jiveL_style_color - Check with Richard about refactoring a helper method (thought there was some issue with L and a helper method)
	if (lua_isnil(L, -1)) {
		return 1;
	}

	if (!lua_istable(L, -1)) {
		luaL_error(L, "invalid component in style color, table expected");
	}

	/* use empty table for not set */
	if (lua_objlen(L, -1) == 0) {
		lua_pop(L, 1);

		lua_pushnil(L);
		return 1;
	}

	lua_rawgeti(L, -1, 1);
	lua_rawgeti(L, -2, 2);
	lua_rawgeti(L, -3, 3);
	lua_rawgeti(L, -4, 4);

	r = (int) luaL_checknumber(L, -4);
	g = (int) luaL_checknumber(L, -3);
	b = (int) luaL_checknumber(L, -2);
	if (lua_isnumber(L, -1)) {
		a = (int) luaL_checknumber(L, -1);
	}
	else {
		a = 0xFF;
	}

	lua_pop(L, 5);
 
	lua_pushnumber(L, (lua_Integer)((r << 24) | (g << 16) | (b << 8) | a) );
	return 1;
}


Uint32 jive_style_color(lua_State *L, int index, const char *key, Uint32 def, bool *is_set) {
	Uint32 col;

	JIVEL_STACK_CHECK_BEGIN(L);

	lua_pushcfunction(L, jiveL_style_color);
	lua_pushvalue(L, index);
	lua_pushstring(L, key);
	lua_pushnil(L);
	lua_call(L, 3, 1);

	if (lua_isnil(L, -1)) {
		lua_pop(L, 1);

		if (is_set) {
			*is_set = 0;
		}
		return def;
	}

	col = (Uint32) lua_tointeger(L, -1);
	if (is_set) {
		*is_set = 1;
	}
	lua_pop(L, 1);

	JIVEL_STACK_CHECK_END(L);

	return col;
}

Uint32 jive_style_array_color(lua_State *L, int index, const char *array, int n, const char *key, Uint32 def, bool *is_set) {
	Uint32 col;

	JIVEL_STACK_CHECK_BEGIN(L);

	lua_pushcfunction(L, jiveL_style_array_color);
	lua_pushvalue(L, index);
	lua_pushstring(L, array);
	lua_pushnumber(L, n);
	lua_pushstring(L, key);
	lua_pushnil(L);
	lua_call(L, 5, 1);


	if (lua_isnil(L, -1)) {
		lua_pop(L, 1);

		if (is_set) {
			*is_set = 0;
		}
		return def;
	}

	col = (Uint32) lua_tointeger(L, -1);
	if (is_set) {
		*is_set = 1;
	}
	lua_pop(L, 1);

	JIVEL_STACK_CHECK_END(L);

	return col;
}


JiveSurface *jive_style_image(lua_State *L, int index, const char *key, JiveSurface *def) {
	JiveSurface *value;
	JiveSurface **p;

	JIVEL_STACK_CHECK_BEGIN(L);

	lua_pushcfunction(L, jiveL_style_value);
	lua_pushvalue(L, index);
	lua_pushstring(L, key);

	p = (JiveSurface **)lua_newuserdata(L, sizeof(JiveSurface *));
	*p = def;
	luaL_getmetatable(L, "JiveSurface");
	lua_setmetatable(L, -2);
	lua_call(L, 3, 1);

	value = lua_isuserdata(L, -1) ? *(JiveSurface **)lua_touserdata(L, -1) : def;
	lua_pop(L, 1);

	JIVEL_STACK_CHECK_END(L);

	return value;
}


JiveTile *jive_style_tile(lua_State *L, int index, const char *key, JiveTile *def) {
	JiveTile *value;
	JiveTile **p;

	JIVEL_STACK_CHECK_BEGIN(L);

	lua_pushcfunction(L, jiveL_style_value);
	lua_pushvalue(L, index);
	lua_pushstring(L, key);

	p = (JiveTile **)lua_newuserdata(L, sizeof(JiveTile *));
	*p = def;
	luaL_getmetatable(L, "JiveTile");
	lua_setmetatable(L, -2);
	lua_call(L, 3, 1);

	value = lua_isuserdata(L, -1) ? *(JiveTile **)lua_touserdata(L, -1) : def;

	lua_pop(L, 1);

	JIVEL_STACK_CHECK_END(L);

	return value;
}


int jiveL_style_font(lua_State *L) {
	JiveFont **p;
	
	/* stack is:
	 * 1: widget
	 * 2: key
	 * 3: default
	 */

	jiveL_style_value(L);

	if (lua_isnil(L, -1)) {
		lua_pop(L, 1);

		/* default font */
		p = (JiveFont **)lua_newuserdata(L, sizeof(JiveFont *));
		*p = jive_font_load("fonts/FreeSans.ttf", 15);
		luaL_getmetatable(L, "JiveFont");
		lua_setmetatable(L, -2);
	}

	return 1;
}


JiveFont *jive_style_font(lua_State *L, int index, const char *key)  {
	JiveFont *value;

	JIVEL_STACK_CHECK_BEGIN(L);

	lua_pushcfunction(L, jiveL_style_font);
	lua_pushvalue(L, index);
	lua_pushstring(L, key);
	lua_pushnil(L);
	lua_call(L, 3, 1);

	value = *(JiveFont **)lua_touserdata(L, -1);
	lua_pop(L, 1);

	assert(value);

	JIVEL_STACK_CHECK_END(L);

	return value;
}


JiveAlign jive_style_align(lua_State *L, int index, char *key, JiveAlign def) {
	int v;

	const char *options[] = {
		"center",
		"left",
		"right",
		"top",
		"bottom",
		"top-left",
		"top-right",
		"bottom-left",
		"bottom-right",
		NULL
	};

	JIVEL_STACK_CHECK_BEGIN(L);


	lua_pushcfunction(L, jiveL_style_value);
	lua_pushvalue(L, index);
	lua_pushstring(L, key);
	lua_pushnil(L);
	lua_call(L, 3, 1);

	if (lua_isnil(L, -1)) {
		lua_pop(L, 1);		

		JIVEL_STACK_CHECK_ASSERT(L);
		return def;
	}

	v = luaL_checkoption(L, -1, options[def], options);
	lua_pop(L, 1);

	JIVEL_STACK_CHECK_END(L);

	return (JiveAlign) v;
}


void jive_style_insets(lua_State *L, int index, char *key, JiveInset *inset) {
	JIVEL_STACK_CHECK_BEGIN(L);

	lua_pushcfunction(L, jiveL_style_value);
	lua_pushvalue(L, index);
	lua_pushstring(L, key);
	lua_pushnil(L);
	lua_call(L, 3, 1);

	//if (lua_isinteger(L, -1)) {
	if (lua_isnumber(L, -1)) {
		int v = lua_tointeger(L, -1);
		inset->left = v;
		inset->top = v;
		inset->right = v;
		inset->bottom = v;
	}
	else if (lua_istable(L, -1)) {
		lua_rawgeti(L, -1, 1);
		lua_rawgeti(L, -2, 2);
		lua_rawgeti(L, -3, 3);
		lua_rawgeti(L, -4, 4);

		inset->left = luaL_optinteger(L, -4, 0);
		inset->top = luaL_optinteger(L, -3, 0);
		inset->right = luaL_optinteger(L, -2, 0);
		inset->bottom = luaL_optinteger(L, -1, 0);

		lua_pop(L, 4);
	}
	else {
		memset(inset, 0, sizeof(JiveInset));
	}
	lua_pop(L, 1);

	JIVEL_STACK_CHECK_END(L);
}


int jive_style_array_size(lua_State *L, int index, char *key) {
	size_t size = 0;

	JIVEL_STACK_CHECK_BEGIN(L);

	lua_pushcfunction(L, jiveL_style_value);
	lua_pushvalue(L, index);
	lua_pushstring(L, key);
	lua_pushnil(L);
	lua_call(L, 3, 1);

	if (lua_type(L, -1) != LUA_TTABLE) {
		lua_pop(L, 1);

		JIVEL_STACK_CHECK_ASSERT(L);
		return 0;
	}

	/* the array should use integer indexes, but it may be sparse
	 * so iterate over is to find the maximum index.
	 */
	lua_pushnil(L);
	while (lua_next(L, -2) != 0) {
		size = MAX(size, lua_tonumber(L, -2));
		lua_pop(L, 1);
	}
	lua_pop(L, 1);

	JIVEL_STACK_CHECK_END(L);

	return size;
}


int jive_style_array_int(lua_State *L, int index, const char *array, int n, const char *key, int def) {
	int value;

	JIVEL_STACK_CHECK_BEGIN(L);

	lua_pushcfunction(L, jiveL_style_array_value);
	lua_pushvalue(L, index);
	lua_pushstring(L, array);
	lua_pushnumber(L, n);
	lua_pushstring(L, key);
	lua_pushinteger(L, def);
	lua_call(L, 5, 1);

	if (lua_isboolean(L, -1)) {
		value = lua_toboolean(L, -1);
	}
	else {
		value = lua_tointeger(L, -1);
	}
	lua_pop(L, 1);

	JIVEL_STACK_CHECK_END(L);

	return value;
}


JiveFont *jive_style_array_font(lua_State *L, int index, const char *array, int n, const char *key) {
	JiveFont *value;

	JIVEL_STACK_CHECK_BEGIN(L);

	lua_pushcfunction(L, jiveL_style_array_value);
	lua_pushvalue(L, index);
	lua_pushstring(L, array);
	lua_pushnumber(L, n);
	lua_pushstring(L, key);
	lua_pushnil(L);
	lua_call(L, 5, 1);

	value = *(JiveFont **)lua_touserdata(L, -1);
	lua_pop(L, 1);

	JIVEL_STACK_CHECK_END(L);

	return value;
}
