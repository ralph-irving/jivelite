/*
** Copyright 2010 Logitech. All Rights Reserved.
**
** This file is licensed under BSD. Please see the LICENSE file for details.
*/

#include "common.h"
#include "jive.h"

#include <time.h>

extern struct jive_perfwarn perfwarn;

void jive_widget_pack(lua_State *L, int index, JiveWidget *data) {

	JIVEL_STACK_CHECK_BEGIN(L);

	/* preferred bounds from style */
	data->preferred_bounds.x = jive_style_int(L, 1, "x", JIVE_XY_NIL);
	data->preferred_bounds.y = jive_style_int(L, 1, "y", JIVE_XY_NIL);
	data->preferred_bounds.w = jive_style_int(L, 1, "w", JIVE_WH_NIL);
	data->preferred_bounds.h = jive_style_int(L, 1, "h", JIVE_WH_NIL);

	/* padding from style */
	jive_style_insets(L, 1, "padding", &data->padding);
	jive_style_insets(L, 1, "border", &data->border);

	/* layer from style */
	data->layer = jive_style_int(L, 1, "layer", JIVE_LAYER_CONTENT);
	data->z_order = jive_style_int(L, 1, "zOrder", 0);
	data->hidden = jive_style_int(L, 1, "hidden", 0);

	JIVEL_STACK_CHECK_END(L);
}


int jiveL_widget_set_bounds(lua_State *L) {
	JiveWidget *peer;
	SDL_Rect bounds;

	if (jive_getmethod(L, 1, "checkSkin")) {
		lua_pushvalue(L, 1);
		lua_call(L, 1, 0);
	}
	
	lua_getfield(L, 1, "peer");
	peer = lua_touserdata(L, -1);
	if (!peer) {
		return 0;
	}

	memcpy(&bounds, &peer->bounds, sizeof(bounds));
	
	if (lua_isnumber(L, 2)) {
		bounds.x = lua_tointeger(L, 2);
	}
	if (lua_isnumber(L, 3)) {
		bounds.y = lua_tointeger(L, 3);
	}
	if (lua_isnumber(L, 4)) {
		bounds.w = lua_tointeger(L, 4);
	}
	if (lua_isnumber(L, 5)) {
		bounds.h = lua_tointeger(L, 5);
	}

	// mark old widget bounds for redrawing
	lua_pushcfunction(L, jiveL_widget_redraw);
	lua_pushvalue(L, 1);
	lua_call(L, 1, 0);

	// check if the widget has moved
	if (memcmp(&peer->bounds, &bounds, sizeof(bounds)) == 0) {
		// no change
		return 0;
	}

	memcpy(&peer->bounds, &bounds, sizeof(bounds));

	// mark widget for layout
	if (jive_getmethod(L, 1, "reLayout")) {
		lua_pushvalue(L, 1);
		lua_call(L, 1, 0);
	}

	// mark new widget bounds for redrawing
	lua_pushcfunction(L, jiveL_widget_redraw);
	lua_pushvalue(L, 1);
	lua_call(L, 1, 0);

	//printf("## SET_BOUNDS %p %d,%d %dx%d\n", lua_topointer(L, 1), peer->bounds.x, peer->bounds.y, peer->bounds.w, peer->bounds.h);

	return 0;
}


int jiveL_widget_get_bounds(lua_State *L) {
	JiveWidget *peer;

	if (jive_getmethod(L, 1, "checkSkin")) {
		lua_pushvalue(L, 1);
		lua_call(L, 1, 0);
	}
	
	lua_getfield(L, 1, "peer");
	peer = lua_touserdata(L, -1);
	if (!peer) {
		return 0;
	}

	lua_pushinteger(L, peer->bounds.x);
	lua_pushinteger(L, peer->bounds.y);
	lua_pushinteger(L, peer->bounds.w);
	lua_pushinteger(L, peer->bounds.h);
	return 4;
}


int jiveL_widget_get_z_order(lua_State *L) {
	JiveWidget *peer;

	lua_getfield(L, 1, "peer");
	peer = lua_touserdata(L, -1);
	if (!peer) {
		return 0;
	}

	lua_pushinteger(L, peer->z_order);
	return 1;
}


int jiveL_widget_is_hidden(lua_State *L) {
	JiveWidget *peer;

	lua_getfield(L, 1, "peer");
	peer = lua_touserdata(L, -1);
	if (!peer) {
		return 0;
	}

	lua_pushboolean(L, peer->hidden);
	return 1;
}


int jiveL_widget_get_preferred_bounds(lua_State *L) {
	JiveWidget *peer;

	if (jive_getmethod(L, 1, "checkSkin")) {
		lua_pushvalue(L, 1);
		lua_call(L, 1, 0);
	}
	
	lua_getfield(L, 1, "peer");
	peer = lua_touserdata(L, -1);
	if (!peer) {
		return 0;
	}

	if (peer->preferred_bounds.x == JIVE_XY_NIL) {
		lua_pushnil(L);
	}
	else {
		lua_pushinteger(L, peer->preferred_bounds.x);
	}
	if (peer->preferred_bounds.y == JIVE_XY_NIL) {
		lua_pushnil(L);
	}
	else {
		lua_pushinteger(L, peer->preferred_bounds.y);
	}
	if (peer->preferred_bounds.w == JIVE_WH_NIL) {
		lua_pushnil(L);
	}
	else {
		lua_pushinteger(L, peer->preferred_bounds.w);
	}
	if (peer->preferred_bounds.h == JIVE_WH_NIL) {
		lua_pushnil(L);
	}
	else {
		lua_pushinteger(L, peer->preferred_bounds.h);
	}
	return 4;
}


int jiveL_widget_get_padding(lua_State *L) {
	JiveWidget *peer;

	if (jive_getmethod(L, 1, "checkSkin")) {
		lua_pushvalue(L, 1);
		lua_call(L, 1, 0);
	}
	
	lua_getfield(L, 1, "peer");
	peer = lua_touserdata(L, -1);
	if (!peer) {
		return 0;
	}

	lua_pushinteger(L, peer->padding.left);
	lua_pushinteger(L, peer->padding.top);
	lua_pushinteger(L, peer->padding.right);
	lua_pushinteger(L, peer->padding.bottom);
	return 4;
}


int jiveL_widget_get_border(lua_State *L) {
	JiveWidget *peer;

	if (jive_getmethod(L, 1, "checkSkin")) {
		lua_pushvalue(L, 1);
		lua_call(L, 1, 0);
	}

	lua_getfield(L, 1, "peer");
	peer = lua_touserdata(L, -1);
	if (!peer) {
		return 0;
	}
	
	lua_pushinteger(L, peer->border.left);
	lua_pushinteger(L, peer->border.top);
	lua_pushinteger(L, peer->border.right);
	lua_pushinteger(L, peer->border.bottom);
	return 4;
}


int jiveL_widget_mouse_inside(lua_State *L) {
	JiveWidget *peer;
	JiveEvent* event;

	/* stack is:
	 * 1: widget
	 * 2: mouse event
	 */

	if (jive_getmethod(L, 1, "checkSkin")) {
		lua_pushvalue(L, 1);
		lua_call(L, 1, 0);
	}
	
	lua_getfield(L, 1, "peer");
	peer = lua_touserdata(L, -1);
	if (!peer) {
		lua_pushboolean(L, 0);
		return 1;
	}

	event = (JiveEvent*)lua_touserdata(L, 2);
	if (!event || (event->type & JIVE_EVENT_MOUSE_ALL) == 0) {
		lua_pushboolean(L, 0);
		return 1;
	}

	lua_pushboolean(L, peer->bounds.x <= event->u.mouse.x && event->u.mouse.x < peer->bounds.x + peer->bounds.w &&
			peer->bounds.y <= event->u.mouse.y && event->u.mouse.y < peer->bounds.y + peer->bounds.h);
	return 1;
}


int jiveL_widget_mouse_bounds(lua_State *L) {
	JiveWidget *peer;
	JiveEvent* event;

	/* stack is:
	 * 1: widget
	 * 2: mouse event
	 */

	if (jive_getmethod(L, 1, "checkSkin")) {
		lua_pushvalue(L, 1);
		lua_call(L, 1, 0);
	}
	
	lua_getfield(L, 1, "peer");
	peer = lua_touserdata(L, -1);
	if (!peer) {
		lua_pushboolean(L, 0);
		return 1;
	}

	event = (JiveEvent*)lua_touserdata(L, 2);
	if (!event || (event->type & JIVE_EVENT_MOUSE_ALL) == 0) {
		lua_pushboolean(L, 0);
		return 1;
	}

	lua_pushinteger(L, event->u.mouse.x - peer->bounds.x - peer->padding.left);
	lua_pushinteger(L, event->u.mouse.y - peer->bounds.y - peer->padding.top);
	lua_pushinteger(L, peer->bounds.w - peer->padding.left - peer->padding.right);
	lua_pushinteger(L, peer->bounds.h - peer->padding.top - peer->padding.bottom);
	return 4;
}


int jiveL_widget_reskin(lua_State *L) {
	JiveWidget *peer;

	/* stack is:
	 * 1: widget
	 */
	lua_getfield(L, 1, "peer");
	peer = lua_touserdata(L, -1);

	if (peer) {
		peer->skin_origin = jive_origin - 1;
	}

	return jiveL_widget_relayout(L);
}


int jiveL_widget_relayout(lua_State *L) {
	JiveWidget *peer;
	bool dirty;

	/* stack is:
	 * 1: widget
	 */

	/* mark widgets for layout until a layout root is reached */
	dirty = true;
	while (!lua_isnil(L, 1)) {
		lua_getfield(L, 1, "peer");
		peer = lua_touserdata(L, -1);

		if (peer) {
			peer->child_origin = jive_origin - 1;

			if (dirty) {
				peer->layout_origin = jive_origin - 1;

				lua_getfield(L, 1, "layoutRoot");
				if (lua_toboolean(L, -1)) {
					dirty = false;
				}
				lua_pop(L, 1);
			}
		}
		lua_pop(L, 1);

		lua_getfield(L, 1, "parent");
		lua_replace(L, 1);
	}

	return 0;
}


int jiveL_widget_redraw(lua_State *L) {
	JiveWidget *peer;
	int offset = 0;

	/* stack is:
	 * 1: widget
	 */

	lua_getfield(L, 1, "visible");
	if (lua_toboolean(L, -1)) {
		lua_getfield(L, 1, "peer");
		peer = lua_touserdata(L, -1);

		if (peer) {
			/* if the widget is inside a menu using smooth scrolling, find the offset
			 * and use it to adjust the dirty region reported by the widget */
			lua_getfield(L, 1, "smoothscroll");
			if (lua_istable(L, -1)) {
				lua_getfield(L, -1, "pixelOffsetY");
				offset = lua_tointeger(L, -1);
				lua_pop(L, 2);
			} else {
				lua_pop(L, 1);
			}
			
			if (!offset) {
				jive_redraw(&peer->bounds);
			} else {
				SDL_Rect r;
				memcpy(&r, &peer->bounds, sizeof(r));
				r.y += offset;
				jive_redraw(&r);
			}
		}

		lua_pop(L, 1);
	}
	lua_pop(L, 1);

	return 0;
}


int jiveL_widget_check_skin(lua_State *L) {
	JiveWidget *peer;

	lua_getfield(L, 1, "peer");
	peer = lua_touserdata(L, -1);
	lua_pop(L, 1);

	if (!peer || peer->skin_origin != jive_origin) {
		if (jive_getmethod(L, 1, "_skin")) {
			lua_pushvalue(L, 1);
			lua_call(L, 1, 0);
		}

		if (!peer) {
			lua_getfield(L, 1, "peer");
			peer = lua_touserdata(L, -1);
			lua_pop(L, 1);
		}

		peer->skin_origin = jive_origin;
	}

	return 0;
}


int jiveL_widget_check_layout(lua_State *L) {
	JiveWidget *peer;

	Uint32 t0 = 0, t1 = 0, t2 = 0;
	clock_t c0 = 0, c1 = 0;

	/* stack is:
	 * 1: widget
	 * 2: force
	 */

	lua_getfield(L, 1, "peer");
	peer = lua_touserdata(L, -1);
	lua_pop(L, 1);

	if (!peer || peer->layout_origin != jive_origin) {
		/* layout dirty, update */
		if (perfwarn.layout) {
			t0 = jive_jiffies();
			c0 = clock();
		}

		/* does the skin need updating? */
		if (!peer || peer->skin_origin != jive_origin) {
			if (jive_getmethod(L, 1, "_skin")) {
				lua_pushvalue(L, 1);
				lua_call(L, 1, 0);
			}
			
			if (!peer) {
				lua_getfield(L, 1, "peer");
				peer = lua_touserdata(L, -1);
				lua_pop(L, 1);
			}

			peer->skin_origin = jive_origin;
		}

		if (perfwarn.layout) t1 = jive_jiffies();

		peer->layout_origin = jive_origin;

		/* update the layout */
		if (jive_getmethod(L, 1, "_layout")) {
			lua_pushvalue(L, 1);
			lua_call(L, 1, 0);
		}

		if (perfwarn.layout) {
			t2 = jive_jiffies();
			c1 = clock();
			if (t2 - t0 > perfwarn.layout) {
				lua_getglobal(L, "tostring");
				lua_pushvalue(L, 1);
				lua_call(L, 1, 1);
				printf("widget_layout > %dms: %3dms (%dms) [%s skin:%dms layout:%dms]\n",
					   perfwarn.layout, t2-t0, (int)((c1-c0) * 1000 / CLOCKS_PER_SEC), lua_tostring(L, -1), t1-t0, t2-t1);
				lua_pop(L, 1);
			}
		}
	}

	if (peer->child_origin != jive_origin) {
		peer->child_origin = jive_origin;

		/* layout children */
		jive_getmethod(L, 1, "iterate");
		lua_pushvalue(L, 1);
		lua_pushcfunction(L, jiveL_widget_check_layout);
		lua_pushboolean(L, 1); /* include hidden widgets */
		lua_call(L, 3, 0);
	}

	return 0;
}


int jiveL_widget_peer_tostring(lua_State *L) {
	JiveWidget *peer;
	int n;

	lua_getfield(L, 1, "peer");
	peer = lua_touserdata(L, -1);
	lua_pop(L, 1);

	if (!peer) {
		lua_pushstring(L, "");
		return 1;
	}

	n = lua_gettop(L);

	lua_pushfstring(L, "%p ", lua_topointer(L, 1));

	lua_pushinteger(L, peer->bounds.x);
	lua_pushstring(L, ",");
	lua_pushinteger(L, peer->bounds.y);
	lua_pushstring(L, " ");
	lua_pushinteger(L, peer->bounds.w);
	lua_pushstring(L, "x");
	lua_pushinteger(L, peer->bounds.h);
	lua_pushstring(L, " ");

	lua_pushinteger(L, peer->skin_origin);
	lua_pushstring(L, "/");
	lua_pushinteger(L, peer->layout_origin);
	lua_pushstring(L, "/");
	lua_pushinteger(L, peer->child_origin);

	if (peer->skin_origin != jive_origin || peer->layout_origin != jive_origin) {
		lua_pushstring(L, " **");
	}
	else if (peer->child_origin != jive_origin) {
		lua_pushstring(L, " *");
	}

	lua_concat(L, lua_gettop(L) - n);

	return 1;
}


int jive_widget_halign(JiveWidget *this, JiveAlign align, Uint16 width) {
	if (this->bounds.w - this->padding.left - this->padding.right < width) {
		return this->padding.left;
	}

	switch (align) {
	default:
        case JIVE_ALIGN_LEFT:
        case JIVE_ALIGN_TOP_LEFT:
        case JIVE_ALIGN_BOTTOM_LEFT:
		return this->padding.left;

        case JIVE_ALIGN_CENTER:
        case JIVE_ALIGN_TOP:
        case JIVE_ALIGN_BOTTOM:
		return ((this->bounds.w - this->padding.left - this->padding.right - width) / 2) + this->padding.left;

        case JIVE_ALIGN_RIGHT:
        case JIVE_ALIGN_TOP_RIGHT:
        case JIVE_ALIGN_BOTTOM_RIGHT:
		return this->bounds.w - this->padding.right - width;
	}
}


int jive_widget_valign(JiveWidget *this, JiveAlign align, Uint16 height) {
	switch (align) {
	default:
        case JIVE_ALIGN_TOP:
        case JIVE_ALIGN_TOP_LEFT:
        case JIVE_ALIGN_TOP_RIGHT:
		return this->padding.top;

        case JIVE_ALIGN_CENTER:
        case JIVE_ALIGN_LEFT:
        case JIVE_ALIGN_RIGHT:
		return this->padding.top + ((this->bounds.h - this->padding.top - this->padding.bottom) - height) / 2;

        case JIVE_ALIGN_BOTTOM:
        case JIVE_ALIGN_BOTTOM_LEFT:
        case JIVE_ALIGN_BOTTOM_RIGHT:
		return this->bounds.h - this->padding.bottom - height;
	}
}

