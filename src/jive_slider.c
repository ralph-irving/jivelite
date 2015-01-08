/*
** Copyright 2010 Logitech. All Rights Reserved.
**
** This file is licensed under BSD. Please see the LICENSE file for details.
*/

#include "common.h"
#include "jive.h"


typedef struct slider_widget {
	JiveWidget w;

	JiveAlign align;
	Uint16 slider_x, slider_y; // aligned position

	JiveTile *bg;
	JiveTile *tile;
	JiveSurface *pill_img;
	Uint16 pill_x;
	Uint16 pill_y;
	Uint16 pill_w;
	Uint16 pill_h;
	bool horizontal;
} SliderWidget;


static JivePeerMeta sliderPeerMeta = {
	sizeof(SliderWidget),
	"JiveSlider",
	jiveL_slider_gc,
};


int jiveL_slider_skin(lua_State *L) {
	SliderWidget *peer;
	JiveTile *bg, *tile;
	JiveSurface *pill_img;
	/* stack is:
	 * 1: widget
	 */

	lua_pushcfunction(L, jiveL_style_path);
	lua_pushvalue(L, -2);
	lua_call(L, 1, 0);

	peer = jive_getpeer(L, 1, &sliderPeerMeta);

	jive_widget_pack(L, 1, (JiveWidget *)peer);

	/* slider background */
	bg = jive_style_tile(L, 1, "bgImg", NULL);
	if (peer->bg != bg) {
		if (peer->bg) {
			jive_tile_free(peer->bg);
		}

		peer->bg = jive_tile_ref(bg);
	}

	/* vertial or horizontal */
	peer->horizontal = jive_style_int(L, 1, "horizontal", 1);

	/* slider bubble */
	tile = jive_style_tile(L, 1, "img", NULL);
	if (peer->tile != tile) {
		if (peer->tile) {
			jive_tile_free(peer->tile);
		}

		peer->tile = jive_tile_ref(tile);
	}

	pill_img = jive_style_image(L, 1, "pillImg", NULL);
	if (peer->pill_img != pill_img) {
		if (peer->pill_img) {
			jive_surface_free(peer->pill_img);
		}
		peer->pill_img = jive_surface_ref(pill_img);
	}

	peer->align = jive_style_align(L, 1, "align", JIVE_ALIGN_CENTER);

	return 0;
}


int jiveL_slider_layout(lua_State *L) {
	SliderWidget *peer;
	Uint16 tw, th;

	/* stack is:
	 * 1: widget
	 */
	peer = jive_getpeer(L, 1, &sliderPeerMeta);

	if (!peer->tile) {
		return 0;
	}
	if (peer->pill_img) {
		jive_surface_get_size(peer->pill_img, &peer->pill_w, &peer->pill_h);
	}
	else {
		peer->pill_w = 0;
		peer->pill_h = 0;
	}

	jive_tile_get_min_size(peer->tile, &tw, &th);

	if (peer->w.bounds.w != JIVE_WH_NIL) {
		tw = peer->w.bounds.w;
	}
	if (peer->w.bounds.h != JIVE_WH_NIL) {
		th = peer->w.bounds.h;
	}

	if (peer->horizontal) {
		peer->slider_y = jive_widget_valign((JiveWidget *)peer, peer->align, th);
	}
	else {
		peer->slider_x = jive_widget_halign((JiveWidget *)peer, peer->align, tw);
	}

	return 0;
}

int jiveL_slider_draw(lua_State *L) {

	/* stack is:
	 * 1: widget
	 * 2: surface
	 * 3: layer
	 */

	SliderWidget *peer = jive_getpeer(L, 1, &sliderPeerMeta);
	JiveSurface *srf = *(JiveSurface **)lua_touserdata(L, 2);
	bool drawLayer = luaL_optinteger(L, 3, JIVE_LAYER_ALL) & peer->w.layer;

	if (!drawLayer) {
		return 0;
	}

	if (peer->bg) {
		jive_tile_blit(peer->bg, srf, peer->w.bounds.x + peer->slider_x, peer->w.bounds.y + peer->slider_y, peer->w.bounds.w, peer->w.bounds.h);
	}

	if (peer->tile) {
		int height, width;
		int range, value, size;
		int x, y, w, h;
		Uint16 tw, th;

		height = peer->w.bounds.h - peer->w.padding.top - peer->w.padding.bottom;
		width = peer->w.bounds.w - peer->w.padding.left - peer->w.padding.right;
	
		lua_getfield(L, 1, "range");
		range = lua_tointeger(L, -1);

		lua_getfield(L, 1, "value");
		value = lua_tointeger(L, -1);
		lua_pop(L, 2);

		lua_getfield(L, 1, "size");
		size = lua_tointeger(L, -1);
		lua_pop(L, 2);

		jive_tile_get_min_size(peer->tile, &tw, &th);

		if (peer->horizontal) {
			width -= tw;
			x = (width / (float)(range - 1)) * (value - 1);
			w = (width / (float)(range - 1)) * (size - 1) + tw;
			y = 0;
			h = height;
			peer->pill_x = peer->w.bounds.x + peer->slider_x + peer->w.padding.left + (w - tw);
			peer->pill_y = peer->w.bounds.y + peer->slider_y + peer->w.padding.top + y;
		}
		else {
			height -= th;
			x = 0;
			w = width;
			y = (height / (float)(range - 1)) * (value - 1);
			h = (height / (float)(range - 1)) * (size - 1) + th;
			peer->pill_x = peer->w.bounds.x + peer->slider_x + peer->w.padding.left + x;
			peer->pill_y = peer->w.bounds.y + peer->slider_y + peer->w.padding.top + (h - th);
		}

		jive_tile_blit(peer->tile, srf, peer->w.bounds.x + peer->slider_x + peer->w.padding.left + x, peer->w.bounds.y + peer->slider_y + peer->w.padding.top + y, w, h);

		if (peer->pill_img) {
			jive_surface_blit(peer->pill_img, srf, peer->pill_x, peer->pill_y);
		}
	}

	return 0;
}

int jiveL_slider_get_pill_bounds(lua_State *L) {
	SliderWidget *peer;

	/* stack is:
	 * 1: widget
	 */

	if (jive_getmethod(L, 1, "checkSkin")) {
		lua_pushvalue(L, 1);
		lua_call(L, 1, 0);
	}

	peer = jive_getpeer(L, 1, &sliderPeerMeta);

	if (peer->pill_img) {
		lua_pushinteger(L, peer->pill_x);
		lua_pushinteger(L, peer->pill_y);
		lua_pushinteger(L, peer->pill_w);
		lua_pushinteger(L, peer->pill_h);
	} else {
		lua_pushnil(L);
		lua_pushnil(L);
		lua_pushnil(L);
		lua_pushnil(L);
	}
	return 4;
}


int jiveL_slider_get_preferred_bounds(lua_State *L) {
	SliderWidget *peer;
	Uint16 w = 0;
	Uint16 h = 0;

	/* stack is:
	 * 1: widget
	 */

	if (jive_getmethod(L, 1, "checkSkin")) {
		lua_pushvalue(L, 1);
		lua_call(L, 1, 0);
	}

	peer = jive_getpeer(L, 1, &sliderPeerMeta);

	if (peer->bg) {
		jive_tile_get_min_size(peer->bg, &w, &h);
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

	if (peer->horizontal) {
		lua_pushinteger(L, (peer->w.preferred_bounds.w == JIVE_WH_NIL) ? JIVE_WH_FILL : peer->w.preferred_bounds.w);
		lua_pushinteger(L, (peer->w.preferred_bounds.h == JIVE_WH_NIL) ? h : peer->w.preferred_bounds.h);
	}
	else {
		lua_pushinteger(L, (peer->w.preferred_bounds.w == JIVE_WH_NIL) ? w : peer->w.preferred_bounds.w);
		lua_pushinteger(L, (peer->w.preferred_bounds.h == JIVE_WH_NIL) ? JIVE_WH_FILL : peer->w.preferred_bounds.h );
	}
	return 4;
}

int jiveL_slider_gc(lua_State *L) {
	SliderWidget *peer;

	luaL_checkudata(L, 1, sliderPeerMeta.magic);

	peer = lua_touserdata(L, 1);

	if (peer->bg) {
		jive_tile_free(peer->bg);
		peer->bg = NULL;
	}
	if (peer->tile) {
		jive_tile_free(peer->tile);
		peer->tile = NULL;
	}

	if (peer->pill_img) {
		jive_surface_free(peer->pill_img);
		peer->pill_img = NULL;
	}

	return 0;
}
