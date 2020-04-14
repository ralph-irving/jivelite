/*
** Copyright 2010 Logitech. All Rights Reserved.
**
** This file is licensed under BSD. Please see the LICENSE file for details.
*/

#include "common.h"
#include "jive.h"


/* actual FPS will only run at half of the JIVE_FRAME_RATE */
#define SCROLL_FPS	(JIVE_FRAME_RATE / 2)
#define SCROLL_OFFSET_STEP_MINIMUM	5
#define FONT_SCROLL_FACTOR	5

#define SCROLL_PAD_RIGHT  40
#define SCROLL_PAD_LEFT   -200
#define SCROLL_PAD_START  -100

#define MAX_CHARS 1000  // max number or characters before spliting text in a label
                        // this gets round SDLs limitation on max surface width

typedef struct label_line {
	JiveSurface *text_sh;
	JiveSurface *text_fg;
	Uint16 label_x, label_y; // line position
	Uint16 lineHeight;       // line height
	Uint16 textOffset;
} LabelLine;


typedef struct label_format {
	JiveFont *font;
	bool is_sh, is_fg;
	Uint32 fg, sh;
	Uint16 lineHeight;
	Uint16 textOffset;
} LabelFormat;


typedef struct label_widget {
	JiveWidget w;

	// skin properties
	Uint16 label_w;
	JiveAlign text_align;
	JiveTile *bg_tile;
	size_t num_format;
	LabelFormat *format;
	LabelFormat base;

	int scroll_offset_step;
	
	// prepared lines
	int scroll_offset;
	size_t num_lines;
	Uint16 text_w, text_h; // maximum label width and height
	LabelLine *line;
} LabelWidget;


static JivePeerMeta labelPeerMeta = {
	sizeof(LabelWidget),
	"JiveLabel",
	jiveL_label_gc,
};


static void jive_label_gc_lines(LabelWidget *peer);
static void jive_label_gc_formats(LabelWidget *format);


int jiveL_label_skin(lua_State *L) {
	LabelWidget *peer;
	JiveTile *bg_tile;
	size_t i, num_format;

	/* stack is:
	 * 1: widget
	 */

	lua_pushcfunction(L, jiveL_style_path);
	lua_pushvalue(L, -2);
	lua_call(L, 1, 0);

	peer = jive_getpeer(L, 1, &labelPeerMeta);

	jive_widget_pack(L, 1, (JiveWidget *)peer);

	jive_label_gc_formats(peer);

	peer->base.font = jive_font_ref(jive_style_font(L, 1, "font"));
	
	//scroll_offset_step is font size dependent
	if ( peer->base.font->size && peer->base.font->size > SCROLL_OFFSET_STEP_MINIMUM * FONT_SCROLL_FACTOR ) {
		peer->scroll_offset_step = peer->base.font->size / FONT_SCROLL_FACTOR; 
	} else {
		peer->scroll_offset_step = SCROLL_OFFSET_STEP_MINIMUM; 
	}
	
	peer->base.lineHeight = jive_style_int(L, 1, "lineHeight", jive_font_capheight(peer->base.font));
	peer->base.textOffset = jive_font_offset(peer->base.font);

	peer->base.fg = jive_style_color(L, 1, "fg", JIVE_COLOR_BLACK, NULL);
	peer->base.sh = jive_style_color(L, 1, "sh", JIVE_COLOR_WHITE, &(peer->base.is_sh));

	num_format = jive_style_array_size(L, 1, "line");
	peer->format = calloc(num_format, sizeof(LabelFormat));
	peer->num_format = num_format;

	for (i=0; i<num_format; i++) {
		peer->format[i].font = jive_font_ref(jive_style_array_font(L, 1, "line", i+1, "font"));
		if (peer->format[i].font) {
			peer->format[i].lineHeight = jive_style_array_int(L, 1, "line", i+1, "height", jive_font_capheight(peer->format[i].font));
			peer->format[i].textOffset = jive_font_offset(peer->base.font);
			if (peer->format[i].font->size > peer->scroll_offset_step * FONT_SCROLL_FACTOR) {
				//use large font found for scroll_offset
				peer->scroll_offset_step = peer->format[i].font->size / FONT_SCROLL_FACTOR; 
			}
		}
		peer->format[i].fg = jive_style_array_color(L, 1, "line", i+1, "fg", JIVE_COLOR_BLACK, &(peer->format[i].is_fg));
		peer->format[i].sh = jive_style_array_color(L, 1, "line", i+1, "sh", JIVE_COLOR_BLACK, &(peer->format[i].is_sh));
	}

	bg_tile = jive_style_tile(L, 1, "bgImg", NULL);
	if (bg_tile != peer->bg_tile) {
		if (peer->bg_tile) {
			jive_tile_free(peer->bg_tile);
		}
		peer->bg_tile = jive_tile_ref(bg_tile);
	}

	peer->text_align = jive_style_align(L, 1, "align", JIVE_ALIGN_LEFT);
	return 0;
}


static void prepare(lua_State *L) {
	LabelWidget *peer;
	Uint16 width, height, offset;
	int max_width = 0;
	int total_height = 0;
	size_t num_lines = 0;
	const char *str, *ptr, *nptr;
	char *tmp;
	Uint32 c;

	peer = jive_getpeer(L, 1, &labelPeerMeta);


	/* free existing text surfaces */
	jive_label_gc_lines(peer);

	/* split multi-line text */
	lua_getglobal(L, "tostring");
	lua_getfield(L, 1, "value");

	if (lua_isnil(L, -1)) {
		lua_pop(L, 1);

		/* use text from skin if no value */
		lua_pushcfunction(L, jiveL_style_value);
		lua_pushvalue(L, 1);
		lua_pushstring(L, "text");
		lua_pushstring(L, "");
		lua_call(L, 3, 1);
	}
	lua_call(L, 1, 1);

	ptr = str = lua_tostring(L, -1);

	if (!ptr || *ptr == '\0') {
		return;
	}

	tmp = alloca(strlen(ptr) + 1);

	do {
		LabelLine *line;
		JiveFont *font;
		Uint32 fg, sh;
		bool is_sh;
		size_t len;
		unsigned count;

		/* find line ending and split very long words*/
		count = 0;
		c = utf8_get_char(ptr, &nptr);
		while (c != '\0' && c != '\n' && c != '\r' && count < MAX_CHARS) {
			ptr = nptr;
			c = utf8_get_char(ptr, &nptr);
			count++;
		}
		len = nptr - str - 1;

		peer->num_lines = num_lines + 1;
		peer->line = realloc(peer->line, peer->num_lines * sizeof(LabelLine));

		/* format for line */
		font = peer->base.font;
		height = peer->base.lineHeight;
		offset = peer->base.textOffset;
		fg = peer->base.fg;
		sh = peer->base.sh;
		is_sh = peer->base.is_sh;

		if (num_lines < peer->num_format) {
			LabelFormat *format = &peer->format[num_lines];

			if (format->font) {
				font = format->font;
				height = format->lineHeight;
				offset = format->textOffset;
			}
			if (format->is_fg) {
				fg = format->fg;
			}
			if (format->is_sh) {
				sh = format->sh;
			}
		}

		line = &peer->line[num_lines++];

		/* shadow and foreground text */
		strncpy(tmp, str, len);
		tmp[len] = '\0';

		line->text_sh = is_sh ? jive_font_draw_text(font, sh, tmp) : NULL;
		line->text_fg = jive_font_draw_text(font, fg, tmp);

		/* label dimensions */
		jive_surface_get_size(line->text_fg, &width, NULL);
		max_width = MAX(max_width, width);
		total_height += height;

		line->lineHeight = height;
		line->textOffset = offset;

		/* skip white space */
		while (c == '\n' || c == '\r' || c == ' ') {
			ptr = nptr;
			c = utf8_get_char(ptr, &nptr);
		}

		str = ptr;
	} while (c != '\0');

	/* text width and height */
	peer->text_h = total_height;
	peer->text_w = max_width;

	/* reset scroll position */
	peer->scroll_offset = SCROLL_PAD_START;
}


int jiveL_label_layout(lua_State *L) {
	LabelWidget *peer;
	Uint16 y;
	size_t i;

	/* stack is:
	 * 1: widget
	 */

	// FIXME
	prepare(L);

	peer = jive_getpeer(L, 1, &labelPeerMeta);


	/* align the label, minus the widget width */
	y = jive_widget_valign((JiveWidget *)peer, peer->text_align, peer->text_h);

	for (i=0; i<peer->num_lines; i++) {
		LabelLine *line = &peer->line[i];
		Uint16 w, h;

		jive_surface_get_size(line->text_fg, &w, &h);

		line->label_x = jive_widget_halign((JiveWidget *)peer, peer->text_align, w);
		line->label_y = y - line->textOffset;

		y += line->lineHeight;
	}

	/* maximum render width */
	peer->label_w = peer->w.bounds.w - peer->w.padding.left - peer->w.padding.right;

	return 0;
}


int jiveL_label_do_animate(lua_State *L) {
	int pause_scroll = 0;

	/* stack is:
	 * 1: widget
	 */

	LabelWidget *peer = jive_getpeer(L, 1, &labelPeerMeta);

	/* scroll? */
	if (peer->text_w <= peer->label_w) {
		if (jive_getmethod(L, 1, "textStopCallback")) {
			lua_pushvalue(L, 1); // framework
			lua_call(L, 1, 0);
		}	
		return 0;
	}

	peer->scroll_offset += peer->scroll_offset_step;

	if (peer->scroll_offset > peer->text_w  + SCROLL_PAD_RIGHT) {
		/*
		 * Time to pause scrolling. But need to redraw the label
		 * once more ensuring it finishes up at the left margin.
		*/
		peer->scroll_offset = 0;
		pause_scroll = 1;
	}

	if (peer->scroll_offset < 0) {
		return 0;
	}
	jive_getmethod(L, 1, "reDraw");
	lua_pushvalue(L, 1);
	lua_call(L, 1, 0);

	/* time to pause ? */
	if (pause_scroll) {

		peer->scroll_offset = SCROLL_PAD_LEFT;

		if (jive_getmethod(L, 1, "textStopCallback")) {
			lua_pushvalue(L, 1); // framework
			lua_call(L, 1, 0);
		}
	}

	return 0;
}


int jiveL_label_animate(lua_State *L) {
	/* stack is:
	 * 1: widget
	 * 2: boolean
	 */

	LabelWidget *peer = jive_getpeer(L, 1, &labelPeerMeta);
	if (lua_toboolean(L, 2)) {
		peer->scroll_offset = SCROLL_PAD_START;

		lua_getfield(L, 1, "_animationHandle");
		if (!lua_isnil(L, -1)) {
			return 0;
		}

		/* add animation handler */
		jive_getmethod(L, 1, "addAnimation");
		lua_pushvalue(L, 1);
		lua_pushcfunction(L, &jiveL_label_do_animate);
		lua_pushinteger(L, SCROLL_FPS);
		lua_call(L, 3, 1);
		lua_setfield(L, 1, "_animationHandle");
	}
	else {
		peer->scroll_offset = 0;

		/* remove animation handler */
		lua_getfield(L, 1, "_animationHandle");
		if (lua_isnil(L, -1)) {
			return 0;
		}

		jive_getmethod(L, 1, "removeAnimation");
		lua_pushvalue(L, 1);
		lua_pushvalue(L, -3);
		lua_call(L, 2, 0);
		
		lua_pushnil(L);
		lua_setfield(L, 1, "_animationHandle");
	}

	return 0;
}


int jiveL_label_draw(lua_State *L) {
	size_t i;

	/* stack is:
	 * 1: widget
	 * 2: surface
	 * 3: layer
	 */

	LabelWidget *peer = jive_getpeer(L, 1, &labelPeerMeta);
	JiveSurface *srf = *(JiveSurface **)lua_touserdata(L, 2);
	bool drawLayer = luaL_optinteger(L, 3, JIVE_LAYER_ALL) & peer->w.layer;

	if (drawLayer && peer->bg_tile) {
		jive_tile_blit(peer->bg_tile, srf, peer->w.bounds.x, peer->w.bounds.y, peer->w.bounds.w, peer->w.bounds.h);
	}

	//jive_surface_boxColor(srf, peer->w.bounds.x, peer->w.bounds.y, peer->w.bounds.x + peer->w.bounds.w-1, peer->w.bounds.y + peer->w.bounds.h-1, 0x00FF007F);

	/* draw text label */
	if (!(drawLayer && peer->num_lines)) {
		return 0;
	}

	for (i = 0; i < peer->num_lines; i++) {
		Uint16 w, h, o, s;
		Uint16 text_w;
		LabelLine *line = &peer->line[i];

		jive_surface_get_size(line->text_fg, &w, &h);

	
		/* second text when scrolling */
		o = (peer->scroll_offset < 0) ? 0 : peer->scroll_offset;
		if (w < peer->label_w) {
			o = 0;
		}

		s = peer->text_w - o + SCROLL_PAD_RIGHT;
		text_w = peer->label_w;

		/* shadow text */
		if (line->text_sh) {
			jive_surface_blit_clip(line->text_sh, o, 0, text_w, h,
					       srf, peer->w.bounds.x + line->label_x + 1, peer->w.bounds.y + line->label_y + 1);

			if (o && s < text_w) {
				Uint16 len = MAX(0, text_w - s);
				jive_surface_blit_clip(line->text_sh, 0, 0, len, h,
						       srf, peer->w.bounds.x + line->label_x + s + 1, peer->w.bounds.y + line->label_y + 1);
			} 
		}

		/* foreground text */
		jive_surface_blit_clip(line->text_fg, o, 0, text_w, h,
				       srf, peer->w.bounds.x + line->label_x, peer->w.bounds.y + line->label_y);

		if (o && s < text_w) {
			Uint16 len = MAX(0, text_w - s);
			jive_surface_blit_clip(line->text_fg, 0, 0, len, h,
					       srf, peer->w.bounds.x + line->label_x + s, peer->w.bounds.y + line->label_y);
		} 
	}

	return 0;
}


int jiveL_label_get_preferred_bounds(lua_State *L) {
	LabelWidget *peer;
	Uint16 w, h;

	/* stack is:
	 * 1: widget
	 */

	// FIXME
	if (jive_getmethod(L, 1, "checkLayout")) {
		lua_pushvalue(L, 1);
		lua_call(L, 1, 0);
	}

	peer = jive_getpeer(L, 1, &labelPeerMeta);

	w = peer->text_w + peer->w.padding.left + peer->w.padding.right;
	h = peer->text_h + peer->w.padding.top + peer->w.padding.bottom;

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


static void jive_label_gc_lines(LabelWidget *peer) {
	size_t i;

	if (!peer->num_lines) {
		return;
	}

	for (i=0; i<peer->num_lines; i++) {
		if (peer->line[i].text_sh) {
			jive_surface_free(peer->line[i].text_sh);
		}
		if (peer->line[i].text_fg) {
			jive_surface_free(peer->line[i].text_fg);
		}
	}
	free(peer->line);
	peer->line = NULL;
	peer->num_lines = 0;
}


static void jive_label_gc_format(LabelFormat *format) {
	if (format->font) {
		jive_font_free(format->font);
		format->font = NULL;
	}
}


static void jive_label_gc_formats(LabelWidget *peer) {
	size_t i;

	jive_label_gc_format(&peer->base);
	for (i=0; i<peer->num_format; i++) {
		jive_label_gc_format(&peer->format[i]);
	}
	free(peer->format);
	peer->format = NULL;
	peer->num_format = 0;
}


int jiveL_label_gc(lua_State *L) {
	LabelWidget *peer;

	luaL_checkudata(L, 1, labelPeerMeta.magic);

	peer = lua_touserdata(L, 1);

	jive_label_gc_lines(peer);
	jive_label_gc_formats(peer);
	
	if (peer->bg_tile) {
		jive_tile_free(peer->bg_tile);
		peer->bg_tile = NULL;
	}

	return 0;
}
