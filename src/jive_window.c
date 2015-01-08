/*
** Copyright 2010 Logitech. All Rights Reserved.
**
** This file is licensed under BSD. Please see the LICENSE file for details.
*/

#include "common.h"
#include "jive.h"

extern struct jive_perfwarn perfwarn;

typedef struct window_widget {
	JiveWidget w;

	JiveTile *bg_tile;
	JiveTile *mask_tile;
} WindowWidget;


static JivePeerMeta windowPeerMeta = {
	sizeof(WindowWidget),
	"JiveWindow",
	jiveL_window_gc,
};


int jiveL_window_skin(lua_State *L) {
	WindowWidget *peer;
	JiveTile *bg_tile;
	JiveTile *mask_tile;

	/* stack is:
	 * 1: widget
	 */

	lua_pushcfunction(L, jiveL_style_path);
	lua_pushvalue(L, -2);
	lua_call(L, 1, 0);

	peer = jive_getpeer(L, 1, &windowPeerMeta);

	jive_widget_pack(L, 1, (JiveWidget *)peer);

	/* set window layout function, defaults to borderLayout */
	lua_pushcfunction(L, jiveL_style_rawvalue);
	lua_pushvalue(L, 1); // widget
	lua_pushstring(L, "layout"); // key
	jive_getmethod(L, 1, "borderLayout"); // default
	lua_call(L, 3, 1);
	lua_setfield(L, 1, "_skinLayout");

	bg_tile = jive_style_tile(L, 1, "bgImg", NULL);
	if (bg_tile != peer->bg_tile) {
		if (peer->bg_tile) {
			jive_tile_free(peer->bg_tile);
		}
		peer->bg_tile = jive_tile_ref(bg_tile);
	}

	mask_tile = jive_style_tile(L, 1, "maskImg", NULL);
	if (mask_tile != peer->mask_tile) {
		if (peer->mask_tile) {
			jive_tile_free(peer->mask_tile);
		}
		peer->mask_tile = jive_tile_ref(mask_tile);
	}

	return 0;
}


int jiveL_window_check_layout(lua_State *L) {
	/* stack is:
	 * 1: widget
	 */
	int safty = 5;

	WindowWidget *peer = jive_getpeer(L, 1, &windowPeerMeta);

	lua_getfield(L, 1, "transparent");
	if (lua_toboolean(L, -1) && jive_getmethod(L, 1, "getLowerWindow")) {
		/* if transparent drawn lower window first */
		lua_pushvalue(L, 1);
		lua_call(L, 1, 1);

		if (!lua_isnil(L, -1)) {
			lua_pushcfunction(L, jiveL_window_check_layout);
			lua_pushvalue(L, -2);
			lua_call(L, 1, 0);
		}
	}
	lua_pop(L, 1);

	while (peer->w.child_origin != jive_origin && --safty > 0) {
#if 0
		/* debugging */
		jive_getmethod(L, 1, "dump");
		if (!lua_isnil(L, -1)) {
			lua_pushvalue(L, 1);
			lua_call(L, 1, 1);

			printf("layout %d:\n%s\n", jive_origin, lua_tostring(L, -1));
			lua_pop(L, 1);
		}
#endif

		lua_pushcfunction(L, jiveL_widget_check_layout);
		lua_pushvalue(L, 1);
		lua_call(L, 1, 0);

		/* check global widget layout */
		jiveL_getframework(L);
		lua_getfield(L, -1, "widgets");
		lua_pushnil(L);
		while (lua_next(L, -2) != 0) {
			lua_pushcfunction(L, jiveL_widget_check_layout);
			lua_pushvalue(L, -2);
			lua_call(L, 1, 0);

			lua_pop(L, 1);
		}
		lua_pop(L, 2);
	}

	return 0;
}


int jiveL_window_iterate(lua_State *L) {
	int r = 0;
	bool_t nohidden;

	/* stack is:
	 * 1: widget
	 * 2: closure
	 * 3: include hidden (optional)
	 */

	nohidden = !lua_toboolean(L, 3);

	// window widgets in z order
	lua_getfield(L, 1, "zWidgets");
	lua_pushnil(L);
	while (lua_next(L, -2) != 0) {
		if (nohidden && jive_getmethod(L, -1, "isHidden")) {
			lua_pushvalue(L, -2);
			lua_call(L, 1, 1);

			if (lua_toboolean(L, -1)) {
				lua_pop(L, 2);
				continue;
			}

			lua_pop(L, 1);
		}

		lua_pushvalue(L, 2);
		lua_pushvalue(L, -2);
		lua_call(L, 1, 1);

		r = r | luaL_optinteger(L, -1, 0);
		lua_pop(L, 2);
	}
	lua_pop(L, 1);

	lua_pushinteger(L, r);
	return 1;
}


static int draw_closure(lua_State *L) {
	Uint32 t0 = 0, t1 = 0;

	if (perfwarn.draw) t0 = jive_jiffies();

	if (jive_getmethod(L, 1, "draw")) {
		lua_pushvalue(L, 1); // widget
		lua_pushvalue(L, lua_upvalueindex(1)); // surface
		lua_pushvalue(L, lua_upvalueindex(2)); // layer
		lua_call(L, 3, 0);
	}

	if (perfwarn.draw) {
		t1 = jive_jiffies();
		if (t1 - t0 > perfwarn.draw) {
			lua_getglobal(L, "tostring");
			lua_pushvalue(L, 1);
			lua_call(L, 1, 1);
			printf("widget_draw   > %dms: %4dms [%s]\n", perfwarn.draw, t1-t0, lua_tostring(L, -1));
			lua_pop(L, 1);
		}
	}

	return 0;
}


int jiveL_window_draw(lua_State *L) {

	/* stack is:
	 * 1: widget
	 * 2: surface
	 * 3: layer
	 */

	WindowWidget *peer = jive_getpeer(L, 1, &windowPeerMeta);
	JiveSurface *srf = *(JiveSurface **)lua_touserdata(L, 2);
	Uint32 layer = luaL_optinteger(L, 3, JIVE_LAYER_ALL);
	bool_t is_transparent, is_mask;

	lua_getfield(L, 1, "transparent");
	is_transparent = lua_toboolean(L, -1);
	lua_pop(L, 1);

	is_mask = (layer & peer->w.layer) && peer->mask_tile;

	if ((is_transparent || is_mask) &&
	    jive_getmethod(L, 1, "getLowerWindow")) {
		lua_pushvalue(L, 1);
		lua_call(L, 1, 1);

		/* draw window underneath a popup */
		if (is_transparent && (layer & JIVE_LAYER_LOWER)
		    && jive_getmethod(L, -1, "draw")) {
			lua_pushvalue(L, -2);
			lua_pushvalue(L, 2);
			lua_pushinteger(L, JIVE_LAYER_ALL);
				
			lua_call(L, 3, 0);
		}

		/* draw mask under a popup */
		if (is_mask && !lua_isnil(L, -1)) {
			JiveWidget *peer2;

			lua_getfield(L, -1, "peer");
			if (!lua_isnil(L, -1)) {
				peer2 = lua_touserdata(L, -1);

				jive_tile_blit(peer->mask_tile, srf, peer2->bounds.x, peer2->bounds.y, peer2->bounds.w, peer2->bounds.h);
			}
				
			lua_pop(L, 1);
		}

		lua_pop(L, 1);
	}

	/* window background */
	if ((layer & peer->w.layer) && peer->bg_tile) {
		jive_tile_blit(peer->bg_tile, srf, peer->w.bounds.x, peer->w.bounds.y, peer->w.bounds.w, peer->w.bounds.h);
	}

	/* draw widgets */
	if (jive_getmethod(L, 1, "iterate")) {
		lua_pushvalue(L, 1); // widget

		lua_pushvalue(L, 2); // surface
		lua_pushvalue(L, 3); // layer
		lua_pushcclosure(L, draw_closure, 2);

		lua_call(L, 2, 0);
	}

	return 0;
}


static int do_array_event(lua_State *L) {
	int r = 0;

	if (lua_isnil(L, -1)) {
		return r;
	}

	lua_pushnil(L);
	while (lua_next(L, -2) != 0) {
		if (jive_getmethod(L, -1, "_event")) {
			lua_pushvalue(L, -2);	// widget
			lua_pushvalue(L, 2);	// event
			lua_call(L, 2, 1);
					
			r |= lua_tointeger(L, -1);
			lua_pop(L, 1);
		}

		lua_pop(L, 1);
	}

	return r;
}


static int mouse_closure(lua_State *L) {
	JiveWidget *peer;
	JiveEvent *event;

	/* stack is:
	 * 1: widget
	 * upvalue:
	 * 1: event
	 */

	lua_getfield(L, 1, "peer");
	peer = lua_touserdata(L, -1);
	if (!peer) {
		lua_pop(L, 1);
		return 0;
	}

	event = lua_touserdata(L, lua_upvalueindex(1));

	if (peer->bounds.x < event->u.mouse.x && event->u.mouse.x < peer->bounds.x + peer->bounds.w && 
	    peer->bounds.y < event->u.mouse.y && event->u.mouse.y < peer->bounds.y + peer->bounds.h) {
		if (jive_getmethod(L, 1, "_event")) {
			lua_pushvalue(L, 1); /* widget */
			lua_pushvalue(L, lua_upvalueindex(1)); /* event */
			lua_call(L, 2, 1);

			return 1;
		}
	}

	return 0;
}


int jiveL_window_event_handler(lua_State *L) {
	int r = 0;

	/* stack is:
	 * 1: widget
	 * 2: event
	 */

	JiveEvent *event = lua_touserdata(L, 2);

	switch (event->type) {

	case JIVE_EVENT_SCROLL:
	case JIVE_EVENT_KEY_DOWN:
	case JIVE_EVENT_KEY_UP:
	case JIVE_EVENT_KEY_PRESS:
	case JIVE_EVENT_KEY_HOLD:
	case JIVE_EVENT_IR_PRESS:
	case JIVE_EVENT_IR_HOLD:
	case JIVE_EVENT_IR_UP:
	case JIVE_EVENT_IR_DOWN:
	case JIVE_EVENT_IR_REPEAT:
	case JIVE_ACTION:

		/*
		 * Only send UI events to focused widget
		 */
		lua_getfield(L, 1, "focus");
		if (!lua_isnil(L, -1) && jive_getmethod(L, -1, "_event")) {
			lua_pushvalue(L, -2); // widget
			lua_pushvalue(L, 2); // event
			lua_call(L, 2, 1);

			return 1;
		}
		break;


	case JIVE_EVENT_MOUSE_DOWN:
	case JIVE_EVENT_MOUSE_UP:
	case JIVE_EVENT_MOUSE_PRESS:
	case JIVE_EVENT_MOUSE_HOLD:
	case JIVE_EVENT_MOUSE_MOVE:
	case JIVE_EVENT_MOUSE_DRAG:
		/* Forward mouse events to the enclosed widgets */
		/* C side mouse handling is no longer used, is now handled inside the Lua code */
		if (jive_getmethod(L, 1, "iterate")) {
			lua_pushvalue(L, 1); // widget

			lua_pushvalue(L, 2); // event
			lua_pushcclosure(L, mouse_closure, 1);

			lua_call(L, 2, 1);
		}
		else {
			lua_pushinteger(L, r);
		}
		return 1;

	case JIVE_EVENT_WINDOW_ACTIVE:
		/*
		 * Reparent global widgets when this widget is active
		 */
		jiveL_getframework(L);
		lua_getfield(L, -1, "widgets");
		lua_pushnil(L);
		while (lua_next(L, -2) != 0) {
			lua_pushvalue(L, 1);
			lua_setfield(L, -2, "parent");
			
			lua_pop(L, 1);
		}
		lua_pop(L, 2);
		/* fall through */

	case JIVE_EVENT_WINDOW_PUSH:
	case JIVE_EVENT_WINDOW_POP:
	case JIVE_EVENT_WINDOW_INACTIVE:
		/*
		 * Don't forward window events
		 */
		break;


	case JIVE_EVENT_SHOW:
	case JIVE_EVENT_HIDE:
		/* Forward visiblity events to child widgets */
		lua_getfield(L, 1, "widgets");
		r |= do_array_event(L);
		lua_pop(L, 1);

		lua_pushinteger(L, r);
		return 1;

	default:
		/*
		 * Other events to all widgets
		 */
		r = 0;

		/* events to global widgets */
		jiveL_getframework(L);
		lua_getfield(L, -1, "widgets");
		r |= do_array_event(L);
		lua_pop(L, 2);

		/* events to child widgets */
		lua_getfield(L, 1, "widgets");
		r |= do_array_event(L);
		lua_pop(L, 1);

		lua_pushinteger(L, r);
		return 1;
	}

	lua_pushinteger(L, JIVE_EVENT_UNUSED);
	return 1;
}


int jiveL_window_gc(lua_State *L) {
	WindowWidget *peer;

	luaL_checkudata(L, 1, windowPeerMeta.magic);
	peer = lua_touserdata(L, 1);

	if (peer->bg_tile) {
		jive_tile_free(peer->bg_tile);
		peer->bg_tile = NULL;
	}
	if (peer->mask_tile) {
		jive_tile_free(peer->mask_tile);
		peer->mask_tile = NULL;
	}

	return 0;
}
