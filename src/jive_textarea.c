/*
** Copyright 2010 Logitech. All Rights Reserved.
**
** This file is licensed under BSD. Please see the LICENSE file for details.
*/

#include "common.h"
#include "jive.h"


typedef struct textarea_widget {
	JiveWidget w;

	// pointer to start of lines
	Uint16 num_lines;
	int *lines;
	Uint16 line_width;
	bool has_scrollbar;
	bool hide_scrollbar;
	bool is_header_widget;

	// style
	JiveFont *font;
	Uint16 line_height;
	Uint16 text_offset;
	Uint16 y_offset;
	JiveAlign align;
	bool is_sh;
	Uint32 sh;
	Uint32 fg;
	JiveTile *bg_tile;
} TextareaWidget;


static JivePeerMeta textareaPeerMeta = {
	sizeof(TextareaWidget),
	"JiveTextarea",
	jiveL_textarea_gc,
};


static void invalidate(TextareaWidget *peer);
static void wordwrap(TextareaWidget *peer, char *text, int visible_lines, Uint16 sw, bool has_scrollbar);


int jiveL_textarea_skin(lua_State *L) {
	TextareaWidget *peer;
	JiveTile *bg_tile;

	/* stack is:
	 * 1: widget
	 */

	lua_pushcfunction(L, jiveL_style_path);
	lua_pushvalue(L, -2);
	lua_call(L, 1, 0);

	peer = jive_getpeer(L, 1, &textareaPeerMeta);

	jive_widget_pack(L, 1, (JiveWidget *)peer);


	peer->font = jive_font_ref(jive_style_font(L, 1, "font"));
	peer->sh = jive_style_color(L, 1, "sh", JIVE_COLOR_WHITE, &(peer->is_sh));
	peer->fg = jive_style_color(L, 1, "fg", JIVE_COLOR_BLACK, NULL);
	bg_tile = jive_style_tile(L, 1, "bgImg", NULL);

	if (bg_tile != peer->bg_tile) {
		if (peer->bg_tile) {
			jive_tile_free(peer->bg_tile);
		}
		peer->bg_tile = jive_tile_ref(bg_tile);
	}

	peer->line_height = jive_style_int(L, 1, "lineHeight", jive_font_height(peer->font));
	lua_pushinteger(L, peer->line_height);
	lua_setfield(L, 1, "lineHeight");

	peer->text_offset = jive_font_offset(peer->font);

	peer->align = jive_style_align(L, 1, "align", JIVE_ALIGN_TOP_LEFT);

	invalidate(peer);

	return 0;
}


int jiveL_textarea_get_preferred_bounds(lua_State *L) {
	TextareaWidget *peer;
	Uint16 w = 0;
	Uint16 h = 0;

	/* stack is:
	 * 1: widget
	 */

	// FIXME
	if (jive_getmethod(L, 1, "checkLayout")) {
		lua_pushvalue(L, 1);
		lua_call(L, 1, 0);
	}

	peer = jive_getpeer(L, 1, &textareaPeerMeta);

	if (peer->num_lines == 0) {
		/* empty textarea */
		lua_pushnil(L);
		lua_pushnil(L);
		lua_pushinteger(L, 0);
		lua_pushinteger(L, 0);
		return 4;
	}

	w = peer->w.bounds.w + peer->w.padding.left + peer->w.padding.right;
	h = (peer->num_lines * peer->line_height) + peer->w.padding.top + peer->w.padding.bottom;

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

	lua_pushinteger(L, (peer->w.preferred_bounds.w == JIVE_WH_NIL) ? w : peer->w.preferred_bounds.w);
	lua_pushinteger(L, (peer->w.preferred_bounds.h == JIVE_WH_NIL) ? h : peer->w.preferred_bounds.h);
	return 4;
}


int jiveL_textarea_invalidate(lua_State *L) {
	TextareaWidget *peer;

	/* stack is:
	 * 1: widget
	 */

	peer = jive_getpeer(L, 1, &textareaPeerMeta);
	invalidate(peer);

	return 0;
}


int jiveL_textarea_layout(lua_State *L) {
	TextareaWidget *peer;
	Uint16 sx, sy, sw, sh, tmp;
	JiveInset sborder;
	int top_line, visible_lines;
	int widget_height, max_height;
	const char *text;

	/* stack is:
	 * 1: widget
	 */

	peer = jive_getpeer(L, 1, &textareaPeerMeta);

	/* scrollbar size */
	sw = 0;
	sh = peer->w.bounds.h;
	sborder.left = 0;
	sborder.top = 0;
	sborder.right = 0;
	sborder.bottom = 0;

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

	sw += sborder.left + sborder.right;
	sh += sborder.top + sborder.bottom;

	sx = peer->w.bounds.x + peer->w.bounds.w - sw + sborder.left;
	sy = peer->w.bounds.y + sborder.top;


	/* invalidate wordwrap if width changed */
	if (peer->line_width != peer->w.bounds.w) {
		invalidate(peer);
		peer->line_width = peer->w.bounds.w;
	}

	lua_getfield(L, 1, "isHeaderWidget");
	peer->is_header_widget = lua_toboolean(L, -1);
	lua_pop(L, 1);

	lua_getfield(L, 1, "hideScrollbar");
	peer->hide_scrollbar = lua_toboolean(L, -1);
	lua_pop(L, 1);

	/* word wrap text */
	lua_getglobal(L, "tostring");
	lua_getfield(L, 1, "text");
	if (lua_isnil(L, -1)) {
		/* nil is empty textarea */
		lua_pop(L, 2);

		peer->num_lines = 0;
		lua_pushinteger(L, peer->num_lines);
		lua_setfield(L, 1, "numLines");

		return 0;
	}

	lua_call(L, 1, 1);
	text = lua_tostring(L, -1);

	visible_lines = peer->w.bounds.h / peer->line_height;
	wordwrap(peer, (char *) text, visible_lines, sw, false);

	lua_pushinteger(L, peer->num_lines);
	lua_setfield(L, 1, "numLines");


	/* vertical alignment */
	widget_height = peer->w.bounds.h - peer->w.padding.top - peer->w.padding.bottom;
	lua_getfield(L, 1, "isHeaderWidget");
	if (lua_toboolean(L, -1)) {
		lua_getfield(L, 1, "parent");
		lua_getfield(L, -1, "headerWidgetHeight");

		if (!lua_isnil(L, -1)) {
			widget_height = lua_tointeger(L, -1) - peer->w.padding.top - peer->w.padding.bottom;
		}

		lua_pop(L, 1);
		lua_pop(L, 1);
	}
	lua_pop(L, 1);

	max_height = peer->num_lines * peer->line_height;
	if (max_height < widget_height) {
		peer->y_offset = (widget_height - max_height) / 2;
	}
	else {
		peer->y_offset = 0;
	}

	/* top and visible lines */
	lua_getfield(L, 1, "topLine");
	top_line = lua_tointeger(L, -1);
	lua_pop(L, 1);

	if (visible_lines > peer->num_lines) {
		visible_lines = peer->num_lines;
	}
	if (top_line + visible_lines > peer->num_lines) {
		lua_pushinteger(L, peer->num_lines - visible_lines);
		lua_setfield(L, 1, "topLine");
	}

	lua_pushinteger(L, visible_lines);
	lua_setfield(L, 1, "visibleLines");


	/* scroll bar bounds */
	lua_getfield(L, 1, "scrollbar");
	if (!lua_isnil(L, -1)) {
		if (jive_getmethod(L, -1, "setBounds")) {
			lua_pushvalue(L, -2);
			lua_pushinteger(L, sx);
			lua_pushinteger(L, sy);
			lua_pushinteger(L, sw);
			lua_pushinteger(L, sh - sborder.top); //match jive_menu code
			lua_call(L, 5, 0);
		}

		if (jive_getmethod(L, -1, "setScrollbar")) {
			lua_pushvalue(L, -2);
			lua_pushinteger(L, 0);
			lua_pushinteger(L, peer->num_lines);
			lua_pushinteger(L, top_line + 1);
			lua_pushinteger(L, visible_lines);
			lua_call(L, 5, 0);
		}
	}
	lua_pop(L, 1);

	return 0;
}

int jiveL_textarea_draw(lua_State *L) {
	char *text;
	Uint16 y;
	int i, top_line, visible_lines, bottom_line, num_lines;
	Sint16 old_pixel_offset_x, old_pixel_offset_y, new_pixel_offset_y;
	int y_offset = 0;
	bool is_menu_child = false;

	/* stack is:
	 * 1: widget
	 * 2: surface
	 * 3: layer
	 */

	TextareaWidget *peer = jive_getpeer(L, 1, &textareaPeerMeta);
	JiveSurface *srf = *(JiveSurface **)lua_touserdata(L, 2);
	bool drawLayer = luaL_optinteger(L, 3, JIVE_LAYER_ALL) & peer->w.layer;
	SDL_Rect pop_clip, new_clip;

	if (!drawLayer || peer->num_lines == 0) {
		return 0;
	}

	if (peer->bg_tile) {
		jive_tile_blit(peer->bg_tile, srf, peer->w.bounds.x, peer->w.bounds.y, peer->w.bounds.w, peer->w.bounds.h);
	}

	lua_getfield(L, 1, "isHeaderWidget");
	if (lua_toboolean(L, -1)) {
		//y offset not used for header widget, not sure why it should ever auto-apply
		y_offset = peer->y_offset;

		//adjust clip height so we don't draw below parent's bounds
		lua_getfield(L, 1, "parent");
		if (jive_getmethod(L, -1, "getBounds")) {
			lua_pushvalue(L, -2);
			lua_call(L, 1, 4);

			new_clip.h  = lua_tointeger(L, -1) - peer->w.padding.top - peer->w.padding.bottom;
			lua_pop(L, 4);
		}
		lua_pop(L, 1);
	} else {
		new_clip.h = peer->w.bounds.h - peer->w.padding.top;
	}

	lua_pop(L, 1);

	new_clip.x = peer->w.bounds.x;
	new_clip.y = peer->w.bounds.y + peer->w.padding.top;
	new_clip.w = peer->w.bounds.w;

	//Fairly ugly hack to support textarea as a menu item for multiline_text style
	//Otherwise, for the extra hidden menu item for smooth scrolling, the textarea will draw into iconbar
	lua_getfield(L, 1, "isMenuChild");
	if (lua_toboolean(L, -1)) {
		is_menu_child = true;
	}
	lua_pop(L, 1);
/*
	if (lua_toboolean(L, -1)) {
		lua_getfield(L, 1, "parent"); //group
		lua_getfield(L, -1, "parent"); //menu
		if (jive_getmethod(L, -1, "getBounds")) {
			int menu_h, menu_y;
			lua_pushvalue(L, -2);
			lua_call(L, 1, 4);
			menu_h  = lua_tointeger(L, -1);
			menu_y  = lua_tointeger(L, -3);
			lua_pop(L, 4);

			//if bottom of textarea is below bottom of bounding menu, don't draw
			if (new_clip.h + new_clip.y > menu_h + menu_y) {
				lua_pop(L, 1);
				lua_pop(L, 1);
				return 0;

			}
		}
		lua_pop(L, 1);
		lua_pop(L, 1);
	}
	lua_pop(L, 1);
*/
	jive_surface_push_clip(srf, &new_clip, &pop_clip);


	lua_getglobal(L, "tostring");
	lua_getfield(L, 1, "text");
	if (lua_isnil(L, -1) && !peer->font) {
		lua_pop(L, 2);
		return 0;
	}
	lua_call(L, 1, 1);

	text = (char *) lua_tostring(L, -1);

	y = peer->w.bounds.y + peer->w.padding.top - peer->text_offset + y_offset;

	lua_getfield(L, 1, "topLine");
	top_line = lua_tointeger(L, -1);
	lua_pop(L, 1);

	lua_getfield(L, 1, "visibleLines");
	visible_lines = lua_tointeger(L, -1);
	lua_pop(L, 1);

	lua_getfield(L, 1, "numLines");
	num_lines = lua_tointeger(L, -1);
	lua_pop(L, 1);

	lua_getfield(L, 1, "pixelOffsetY");
	new_pixel_offset_y = lua_tointeger(L, -1);
	lua_pop(L, 1);

	jive_surface_get_offset(srf, &old_pixel_offset_x, &old_pixel_offset_y);
	if (!is_menu_child) {
		jive_surface_set_offset(srf, old_pixel_offset_x, new_pixel_offset_y);
	}

	bottom_line = top_line + visible_lines;

	for (i = top_line; i < bottom_line + 1 && i < num_lines ; i++) {
		JiveSurface *tsrf;
		int x;

		int line = peer->lines[i];
		int next = peer->lines[i+1];

		unsigned char b = text[(next - 1)];
		unsigned char c = text[next];
		text[next] = '\0';
		if (b == '\n') {
			text[(next - 1)] = '\0';
		}

		x = peer->w.bounds.x + peer->w.padding.left;
		switch (peer->align) {
		case JIVE_ALIGN_CENTER:
		case JIVE_ALIGN_TOP:
		case JIVE_ALIGN_BOTTOM: {
			Uint16 line_width = jive_font_width(peer->font, &text[line]);
			x = jive_widget_halign((JiveWidget *)peer, peer->align, line_width);
			break;
		}
		default:
			break;
		}

		/* to suppress 'get_image_surface - no SDL surface available' error we
		   only draw if there's something to draw */
		if (text[line] != '\0') {

			/* shadow text */
			if (peer->is_sh) {
				tsrf = jive_font_draw_text(peer->font, peer->sh, &text[line]);
				jive_surface_blit(tsrf, srf, x + 1, y + 1);
				jive_surface_free(tsrf);
			}

			/* foreground text */
			tsrf = jive_font_draw_text(peer->font, peer->fg, &text[line]);
			jive_surface_blit(tsrf, srf, x, y);
			jive_surface_free(tsrf);
		}

		text[next] = c;
		text[(next - 1)] = b;

		y += peer->line_height;
	}
	if (!is_menu_child) {
		jive_surface_set_offset(srf, old_pixel_offset_x, old_pixel_offset_y);
	}
	jive_surface_set_clip(srf, &pop_clip);

	/* draw scrollbar */
	if (peer->has_scrollbar && !peer->is_header_widget) {
		lua_getfield(L, 1, "scrollbar");
		if (!lua_isnil(L, -1) && jive_getmethod(L, -1, "draw")) {
			lua_pushvalue(L, -2);
			lua_pushvalue(L, 2);
			lua_pushvalue(L, 3);
			lua_call(L, 3, 0);
		}	
		lua_pop(L, 1);
	}

	return 0;
}


static void invalidate(TextareaWidget *peer)
{
	if (peer->lines) {
		free(peer->lines);
		peer->num_lines = 0;
		peer->lines = NULL;
	}
}


static void wordwrap(TextareaWidget *peer, char *text, int visible_lines, Uint16 scrollbar_width, bool has_scrollbar) {
	// maximum text width
	int width = peer->w.bounds.w - peer->w.padding.left - peer->w.padding.right;

	// lines points to the start of each line
	int max_lines = 100;
	unsigned int *lines = malloc(sizeof(int) * max_lines);
	int num_lines = 0;

	char *ptr = text;
	char *line_start = ptr;
	char *word_break = NULL;
	Uint16 line_width = 0;

	/* optimization, don't wrap text with width = 0 */
	if (width <= 0) {
		lines[0] = 0;
		lines[1] = strlen(ptr);

		if (peer->lines) {
			free(peer->lines);
		}

		peer->num_lines = 1;
		peer->lines = realloc(lines, sizeof(int) * (1 + 1));

		return;
	}


	peer->has_scrollbar = has_scrollbar;
	if (has_scrollbar && !peer->is_header_widget) {
		width -= scrollbar_width;
	}

	lines[num_lines++] = (ptr - text);

	while (*ptr) {
		char c;
		char *next;
		Uint32 code = utf8_get_char(ptr, (const char **)&next);

		switch (code) {
		case '\n':
			/* Line break */
			ptr = next;
			word_break = NULL;

			if (max_lines == num_lines) {
				max_lines += 100;
				lines = realloc(lines, sizeof(int) * max_lines);
			}

			line_start = ptr;
			lines[num_lines++] = (ptr - text);
			line_width = 0;
			continue;

		case '.':
		    /* Word break, but exclude urls */
		    if (utf8_get_char(next, NULL) != ' ') {
			break;
		    }

		case ' ':
		case ',':
		case '-':
			/* Word break */
			word_break = next;
			break;
		}

		// Calculate width of string to char
		c = *next;
		*next = '\0';
		line_width += jive_font_width(peer->font, (char *)ptr);
		*next = c;

		// Line is less than widget width
		if (line_width < width) {
			ptr = next;
			continue;
		}

		if (max_lines == num_lines) {
			max_lines += 100;
			lines = realloc(lines, sizeof(int) * max_lines);
		}

		// Next line
		line_width = 0;

		if (!has_scrollbar && num_lines > visible_lines && !(peer->is_header_widget || peer->hide_scrollbar)) {
			free(lines);
			return wordwrap(peer, text, visible_lines, scrollbar_width, true);
		}

		if (word_break) {
			ptr = word_break;
			word_break = NULL;
		}

		/* trim extra \n caused by line breaks */
		code = utf8_get_char(ptr, (const char **)&next);
		if (code == '\n') {
			ptr = next;
			code = utf8_get_char(ptr, (const char **)&next);
		}

		/* trim leading space on line break */
	  	while (code != 0 && code == ' ') {
			ptr = next;
			code = utf8_get_char(ptr, (const char **)&next);
		}

		line_start = ptr;
		lines[num_lines++] = (ptr - text);
	}
	lines[num_lines] = (ptr - text);

	if (!has_scrollbar && num_lines > visible_lines && !(peer->is_header_widget || peer->hide_scrollbar)) {
		free(lines);
		return wordwrap(peer, text, visible_lines, scrollbar_width, true);
	}

	if (peer->lines) {
		free(peer->lines);
	}
	peer->num_lines = num_lines;
	peer->lines = realloc(lines, sizeof(int) * (num_lines + 1));
}


int jiveL_textarea_gc(lua_State *L) {
	TextareaWidget *peer;

	luaL_checkudata(L, 1, textareaPeerMeta.magic);

	peer = lua_touserdata(L, 1);

	if (peer->lines) {
		free(peer->lines);
		peer->lines = NULL;
	}
	if (peer->font) {
		jive_font_free(peer->font);
		peer->font = NULL;
	}
	if (peer->bg_tile) {
		jive_tile_free(peer->bg_tile);
		peer->bg_tile = NULL;
	}

	return 0;
}
