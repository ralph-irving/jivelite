/*
** Copyright 2010 Logitech. All Rights Reserved.
**
** This file is licensed under BSD. Please see the LICENSE file for details.
*/

#include "common.h"
#include "jive.h"

#ifndef INT_MAX
#include <limits.h>
#endif

typedef struct menu_widget {
	JiveWidget w;

	Uint16 max_height;
	Uint16 item_height;
	Uint16 items_per_line;

	bool has_scrollbar;

	JiveFont *font;
	Uint32 fg;
} MenuWidget;


static JivePeerMeta menuPeerMeta = {
	sizeof(MenuWidget),
	"JiveMenu",
	jiveL_menu_gc,
};


int jiveL_menu_skin(lua_State *L) {
	MenuWidget *peer;
	int numWidgets;

	/* stack is:
	 * 1: widget
	 */

	peer = jive_getpeer(L, 1, &menuPeerMeta);

	lua_pushcfunction(L, jiveL_style_path);
	lua_pushvalue(L, 1);
	lua_call(L, 1, 0);

	jive_widget_pack(L, 1, (JiveWidget *)peer);

	/* menu properties */
	peer->item_height = jive_style_int(L, 1, "itemHeight", 20);
	peer->max_height = jive_style_int(L, 1, "maxHeight", JIVE_WH_NIL);

	lua_pushinteger(L, peer->item_height);
	lua_setfield(L, 1, "itemHeight");

	peer->items_per_line = jive_style_int(L, 1, "itemsPerLine", 1);

	lua_pushinteger(L, peer->items_per_line);
	lua_setfield(L, 1, "itemsPerLine");

	peer->font = jive_font_ref(jive_style_font(L, 1, "font"));
	peer->fg = jive_style_color(L, 1, "fg", JIVE_COLOR_BLACK, NULL);

	/* number of menu items visible */
	numWidgets = (peer->w.bounds.h / peer->item_height) * peer->items_per_line;
	lua_pushinteger(L, numWidgets);
	lua_setfield(L, 1, "numWidgets");

	return 0;
}


int jiveL_menu_layout(lua_State *L) {
	MenuWidget *peer;
	Uint16 x, y;
	Uint16 sx, sy, sw, sh, tmp;
	JiveInset sborder;
	Uint16 hwx, hwy, hww, hwh, hwtmp;
	JiveInset hwborder;
	int numWidgets, listSize;
	bool hide_scrollbar;
	int num_widgets_per_line = 0;


	peer = jive_getpeer(L, 1, &menuPeerMeta);


	/* number of menu items visible */
	numWidgets = (peer->w.bounds.h / peer->item_height) * peer->items_per_line;
	lua_pushinteger(L, numWidgets);
	lua_setfield(L, 1, "numWidgets");


	/* update widget contents */
	if (jive_getmethod(L, 1, "_updateWidgets")) {
		lua_pushvalue(L, 1);
		lua_call(L, 1, 0);
	}


	lua_getfield(L, 1, "listSize");
	listSize = lua_tointeger(L, -1);
	lua_pop(L, 1);

	lua_getfield(L, 1, "hideScrollbar");
	hide_scrollbar = lua_toboolean(L, -1);
	lua_pop(L, 1);

	peer->has_scrollbar = ( (!hide_scrollbar) && (listSize > numWidgets));

	/* measure scrollbar */
	sw = 0;
	sh = peer->w.bounds.h;
	sborder.left = 0;
	sborder.top = 0;
	sborder.right = 0;
	sborder.bottom = 0;

	if (peer->has_scrollbar) {
		lua_getfield(L, 1, "scrollbar");
		if (!lua_isnil(L, -1)) {
			if (jive_getmethod(L, -1, "getPreferredBounds")) {
				lua_pushvalue(L, -2);
				lua_call(L, 1, 4);
				
				if (!lua_isnil(L, -2)) {
					tmp = lua_tointeger(L, -2);
					if (tmp != JIVE_WH_FILL) {
						sw = tmp;
					}
				}
				if (!lua_isnil(L, -1)) {
					tmp = lua_tointeger(L, -1);
					if (tmp != JIVE_WH_FILL) {
						sh = tmp;
					}
				}

				lua_pop(L, 4);
			}

			if (jive_getmethod(L, -1, "getBorder")) {
				lua_pushvalue(L, -2);
				lua_call(L, 1, 4);
				
				sborder.left = lua_tointeger(L, -4);
				sborder.top = lua_tointeger(L, -3);
				sborder.right = lua_tointeger(L, -2);
				sborder.bottom = lua_tointeger(L, -1);
				lua_pop(L, 4);
			}
		}
		lua_pop(L, 1);

		//todo: fixme: right and bottom are ignored with this code
		sw += sborder.left + sborder.right;
		sh += sborder.top + sborder.bottom;
	}

	sx = peer->w.bounds.x + peer->w.bounds.w - sw + sborder.left;
	sy = peer->w.bounds.y + sborder.top;


	/* measure headerWidget */
	hww = 0;
	hwh = peer->w.bounds.h;
	hwborder.left = 0;
	hwborder.top = 0;
	hwborder.right = 0;
	hwborder.bottom = 0;

	lua_getfield(L, 1, "headerWidget");
	if (!lua_isnil(L, -1)) {
		if (jive_getmethod(L, -1, "getPreferredBounds")) {
			lua_pushvalue(L, -2);
			lua_call(L, 1, 4);

			if (!lua_isnil(L, -2)) {
				hwtmp = lua_tointeger(L, -2);
				if (hwtmp != JIVE_WH_FILL) {
					hww = hwtmp;
				}
			}
			if (!lua_isnil(L, -1)) {
				hwtmp = lua_tointeger(L, -1);
				if (hwtmp != JIVE_WH_FILL) {
					hwh = hwtmp;
				}
			}

			lua_pop(L, 4);
		}

		if (jive_getmethod(L, -1, "getBorder")) {
			lua_pushvalue(L, -2);
			lua_call(L, 1, 4);

			hwborder.left = lua_tointeger(L, -4);
			hwborder.top = lua_tointeger(L, -3);
			hwborder.right = lua_tointeger(L, -2);
			hwborder.bottom = lua_tointeger(L, -1);
			lua_pop(L, 4);
		}
	}
	lua_pop(L, 1);

	//todo: fixme: right and bottom are ignored with this code
	hww += hwborder.left + hwborder.right;
	hwh += hwborder.top + hwborder.bottom;

	hwx = peer->w.bounds.x + hwborder.left;
	hwy = peer->w.bounds.y + hwborder.top;


	/* position widgets */
	x = peer->w.bounds.x + peer->w.padding.left;
	y = peer->w.bounds.y + peer->w.padding.top;

	lua_getfield(L, 1, "widgets");
	lua_pushnil(L);
	while (lua_next(L, -2) != 0) {
		if (jive_getmethod(L, -1, "setBounds")) {
			lua_pushvalue(L, -2);
			lua_pushinteger(L, x);
			lua_pushinteger(L, y);
			lua_pushinteger(L, (peer->w.bounds.w - peer->w.padding.left - peer->w.padding.right - sw) / peer->items_per_line);
			lua_pushinteger(L, peer->item_height);
			
			lua_call(L, 5, 0);
		}

		num_widgets_per_line++;
		if (num_widgets_per_line >= peer->items_per_line) {
			num_widgets_per_line = 0;
			x = peer->w.bounds.x + peer->w.padding.left;
			y += peer->item_height;
		} else {
			x += (peer->w.bounds.w - peer->w.padding.left - peer->w.padding.right - sw) / peer->items_per_line;
		}

		lua_pop(L, 1);
	}
	lua_pop(L, 1);


	/* position scrollbar */
	if (peer->has_scrollbar) {
		lua_getfield(L, 1, "scrollbar");
		if (!lua_isnil(L, -1)) {
			if (jive_getmethod(L, -1, "setBounds")) {
				lua_pushvalue(L, -2);
				lua_pushinteger(L, sx);
				lua_pushinteger(L, sy);
				lua_pushinteger(L, sw - sborder.left - sborder.right);
				lua_pushinteger(L, sh - sborder.top - sborder.bottom);
				lua_call(L, 5, 0);
			}
		}
		lua_pop(L, 1);
	}

	/* position headerWidget */
	lua_getfield(L, 1, "headerWidget");
	if (!lua_isnil(L, -1)) {
		if (jive_getmethod(L, -1, "setBounds")) {
			lua_pushvalue(L, -2);
			lua_pushinteger(L, hwx);
			lua_pushinteger(L, hwy);
			lua_pushinteger(L, hww - hwborder.left - hwborder.right);
			lua_pushinteger(L, hwh - hwborder.top - hwborder.bottom);
			lua_call(L, 5, 0);
		}
	}
	lua_pop(L, 1);

	return 0;
}

int jiveL_menu_iterate(lua_State *L) {
	/* stack is:
	 * 1: widget
	 * 2: closure
	 */

	/* iterate widgets */
	lua_getfield(L, 1, "widgets");
	lua_pushnil(L);
	while (lua_next(L, -2) != 0) {
		lua_pushvalue(L, 2);
		lua_pushvalue(L, -2);
		lua_call(L, 1, 0);

		lua_pop(L, 1);
	}
	lua_pop(L, 1);

	/* iterate scrollbar */
	lua_getfield(L, 1, "scrollbar");
	if (!lua_isnil(L, -1)) {
		lua_pushvalue(L, 2);
		lua_pushvalue(L, -2);
		lua_call(L, 1, 0);
	}	
	lua_pop(L, 1);

	/* iterate header widget */
	lua_getfield(L, 1, "headerWidget");
	if (!lua_isnil(L, -1)) {
		lua_pushvalue(L, 2);
		lua_pushvalue(L, -2);
		lua_call(L, 1, 0);
	}
	lua_pop(L, 1);

	return 0;
}

int jiveL_menu_draw(lua_State *L) {
	const char *accelKey;

	/* stack is:
	 * 1: widget
	 * 2: surface
	 * 3: layer
	 */

	MenuWidget *peer = jive_getpeer(L, 1, &menuPeerMeta);
	JiveSurface *srf = *(JiveSurface **)lua_touserdata(L, 2);
	bool drawLayer = luaL_optinteger(L, 3, JIVE_LAYER_ALL) & peer->w.layer;
	Sint16 old_pixel_offset_x, old_pixel_offset_y, new_pixel_offset_y;
	SDL_Rect pop_clip, new_clip;

	lua_getfield(L, 1, "accelKey");
	accelKey = lua_tostring(L, -1);

	/* draw widgets */
	new_clip.x = peer->w.bounds.x;
	new_clip.y = peer->w.bounds.y;
	new_clip.w = peer->w.bounds.w;
	new_clip.h = peer->w.bounds.h;
	jive_surface_push_clip(srf, &new_clip, &pop_clip);

	lua_getfield(L, 1, "pixelOffsetY");
	new_pixel_offset_y = lua_tointeger(L, -1);
	lua_pop(L, 1);

	jive_surface_get_offset(srf, &old_pixel_offset_x, &old_pixel_offset_y);
	jive_surface_set_offset(srf, old_pixel_offset_x, new_pixel_offset_y + old_pixel_offset_y);

	lua_getfield(L, 1, "widgets");
	lua_pushnil(L);
	while (lua_next(L, -2) != 0) {
		if (jive_getmethod(L, -1, "draw")) {
			lua_pushvalue(L, -2);
			lua_pushvalue(L, 2);
			lua_pushvalue(L, 3);
			lua_call(L, 3, 0);
		}

		lua_pop(L, 1);
	}
	lua_pop(L, 1);

	jive_surface_set_offset(srf, old_pixel_offset_x, old_pixel_offset_y);
	jive_surface_set_clip(srf, &pop_clip);

	/* draw scrollbar */
	if (peer->has_scrollbar) {
		lua_getfield(L, 1, "scrollbar");
		if (!lua_isnil(L, -1) && jive_getmethod(L, -1, "draw")) {
			lua_pushvalue(L, -2);
			lua_pushvalue(L, 2);
			lua_pushvalue(L, 3);
			lua_call(L, 3, 0);
		}	
		lua_pop(L, 1);
	}

	/* draw acceleration key letter */
	if (drawLayer && accelKey) {
		JiveSurface *txt;
		Uint16 x, y, txt_w, txt_h;

		txt = jive_font_draw_text(peer->font, peer->fg, accelKey);

		jive_surface_get_size(txt, &txt_w, &txt_h);

		x = (peer->w.bounds.x + peer->w.bounds.w - txt_w) / 2;
		y = (peer->w.bounds.y + peer->w.bounds.h - txt_h) / 2;
		jive_surface_blit(txt, srf, x, y);

		jive_surface_free(txt);
	}

	/* draw header widget */
	lua_getfield(L, 1, "headerWidget");
	if (!lua_isnil(L, -1) && jive_getmethod(L, -1, "draw")) {
		lua_pushvalue(L, -2);
		lua_pushvalue(L, 2);
		lua_pushvalue(L, 3);
		lua_call(L, 3, 0);
	}
	lua_pop(L, 1);

	return 0;
}


int jiveL_menu_get_preferred_bounds(lua_State *L) {
	MenuWidget *peer;

	if (jive_getmethod(L, 1, "checkSkin")) {
		lua_pushvalue(L, 1);
		lua_call(L, 1, 0);
	}
	
	lua_getfield(L, 1, "peer");
	peer = lua_touserdata(L, -1);
	if (!peer) {
		return 0;
	}

	if (peer->w.preferred_bounds.x == JIVE_XY_NIL) {
		lua_pushnil(L);
	}
	else {
		lua_pushinteger(L, peer->w.preferred_bounds.x);
	}
	if (peer->w.preferred_bounds.y == JIVE_XY_NIL) {
		lua_pushnil(L);
	}
	else {
		lua_pushinteger(L, peer->w.preferred_bounds.y);
	}
	if (peer->w.preferred_bounds.w == JIVE_WH_NIL) {
		lua_pushnil(L);
	}
	else {
		lua_pushinteger(L, peer->w.preferred_bounds.w);
	}

	if (peer->max_height != JIVE_WH_NIL) {
		/* calculate menu max height using list size */
		int max_height = INT_MAX;

		lua_getfield(L, 1, "listSize");
		max_height = (lua_tointeger(L, -1) * peer->item_height) / peer->items_per_line;
		lua_pop(L, 1);

		lua_pushinteger(L, MIN(max_height, peer->max_height));
	}
	else if (peer->w.preferred_bounds.h == JIVE_WH_NIL) {
		lua_pushnil(L);
	}
	else {
		lua_pushinteger(L, peer->w.preferred_bounds.h);
	}
	return 4;
}


int jiveL_menu_gc(lua_State *L) {
	MenuWidget *peer;

	luaL_checkudata(L, 1, menuPeerMeta.magic);

	peer = lua_touserdata(L, 1);

	if (peer->font) {
		jive_font_free(peer->font);
		peer->font = NULL;
	}

	return 0;
}
