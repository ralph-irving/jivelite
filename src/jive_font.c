/*
** Copyright 2010 Logitech. All Rights Reserved.
**
** This file is licensed under BSD. Please see the LICENSE file for details.
*/


#include "common.h"
#include "jive.h"


static const char *JIVE_FONT_MAGIC = "Font";

static JiveFont *fonts = NULL;


static int load_ttf_font(JiveFont *font, const char *name, Uint16 size);

static void destroy_ttf_font(JiveFont *font);

static int width_ttf_font(JiveFont *font, const char *str);

static SDL_Surface *draw_ttf_font(JiveFont *font, Uint32 color, const char *str);



JiveFont *jive_font_load(const char *name, Uint16 size) {

	// Do we already have this font loaded?
	JiveFont *ptr = fonts;
	while (ptr) {
		if (ptr->size == size &&
		    strcmp(ptr->name, name) == 0) {
			ptr->refcount++;
			return ptr;
		}

		ptr = ptr->next;
	}

	/* Initialise the TTF api when required */
	if (!TTF_WasInit() && TTF_Init() == -1) {
		LOG_WARN(log_ui_draw, "TTF_Init: %s\n", TTF_GetError());
		exit(-1);
	}

	ptr = calloc(sizeof(JiveFont), 1);
	
	if (!load_ttf_font(ptr, name, size)) {
		free(ptr);
		return NULL;
	}

	ptr->refcount = 1;
	ptr->name = strdup(name);
	ptr->size = size;
	ptr->next = fonts;
	ptr->magic = JIVE_FONT_MAGIC;
	fonts = ptr;

	return ptr;
}

JiveFont *jive_font_ref(JiveFont *font) {
	if (font) {
		assert(font->magic == JIVE_FONT_MAGIC);
		++font->refcount;
	}
	return font;
}

void jive_font_free(JiveFont *font) {
	assert(font && font->magic == JIVE_FONT_MAGIC);

	if (--font->refcount > 0) {
		return;
	}

	if (font == fonts) {
		fonts = font->next;
	}
	else {
		JiveFont *ptr = fonts;
		while (ptr) {
			if (ptr->next == font) {
				ptr->next = font->next;
				break;
			}

			ptr = ptr->next;
		}
	}

	font->destroy(font);
	free(font->name);
	free(font);

	/* Shutdown the TTF api when all fonts are free */
	if (fonts == NULL && TTF_WasInit()) {
		TTF_Quit();
	}
}

int jive_font_width(JiveFont *font, const char *str) {
	assert(font && font->magic == JIVE_FONT_MAGIC);

	return font->width(font, str);
}

int jive_font_nwidth(JiveFont *font, const char *str, size_t len) {
	char *tmp;

	assert(font && font->magic == JIVE_FONT_MAGIC);

	if (len <= 0) {
		return 0;
	}

	// FIXME use utf8 len
	tmp = alloca(len + 1);
	strncpy(tmp, str, len);
	*(tmp + len) = '\0';

	return font->width(font, tmp);
}

int jive_font_miny_char(JiveFont *font, Uint16 ch) {
	int miny;

	assert(font && font->magic == JIVE_FONT_MAGIC);

	TTF_GlyphMetrics(font->ttf, ch, NULL, NULL, &miny, NULL, NULL);

	return miny;
}

int jive_font_maxy_char(JiveFont *font, Uint16 ch) {
	int maxy;

	assert(font && font->magic == JIVE_FONT_MAGIC);

	TTF_GlyphMetrics(font->ttf, ch, NULL, NULL, NULL, &maxy, NULL);

	return maxy;
}

int jive_font_capheight(JiveFont *font) {
	assert(font && font->magic == JIVE_FONT_MAGIC);

	return font->capheight;
}

int jive_font_height(JiveFont *font) {
	assert(font && font->magic == JIVE_FONT_MAGIC);

	return font->height;
}

int jive_font_ascend(JiveFont *font) {
	assert(font && font->magic == JIVE_FONT_MAGIC);

	return font->ascend;
}

int jive_font_offset(JiveFont *font) {
	assert(font && font->magic == JIVE_FONT_MAGIC);

	return font->ascend - font->capheight;
}

static int load_ttf_font(JiveFont *font, const char *name, Uint16 size) {
	int miny, maxy, descent;
	char *fullpath = malloc(PATH_MAX);

	if (!jive_find_file(name, fullpath) ) {
		free(fullpath);
		LOG_WARN(log_ui_draw, "Cannot find font %s\n", name);
		return 0;
	}

	font->ttf = TTF_OpenFont(fullpath, size);
	if (!font->ttf) {
		free(fullpath);
		LOG_WARN(log_ui_draw, "TTF_OpenFont: %s\n", TTF_GetError());
		return 0;
	}
	free(fullpath);

	font->ascend = TTF_FontAscent(font->ttf);

	/* calcualte the cap height using H */
	if (TTF_GlyphMetrics(font->ttf, 'H', NULL, NULL, NULL, &maxy, NULL) == 0) {
		font->capheight = maxy;
	}
	else {
		font->capheight = font->ascend;
	}

	/* calcualte the non diacritical descent using g */
	if (TTF_GlyphMetrics(font->ttf, 'g', NULL, NULL, &miny, NULL, NULL) == 0) {
		descent = miny;
	}
	else {
		descent = TTF_FontDescent(font->ttf);
	}

	/* calculate the font height, using the capheight and descent */
	font->height = font->capheight - descent + 1;

	font->width = width_ttf_font;
	font->draw = draw_ttf_font;
	font->destroy = destroy_ttf_font;

	return 1;
}

static void destroy_ttf_font(JiveFont *font) {
	if (font->ttf) {
		TTF_CloseFont(font->ttf);
		font->ttf = NULL;
	}
}

static int width_ttf_font(JiveFont *font, const char *str) {
	int w, h;

	if (!str) {
		return 0;
	}

	TTF_SizeUTF8(font->ttf, str, &w, &h);
	return w;
}

static SDL_Surface *draw_ttf_font(JiveFont *font, Uint32 color, const char *str) {
#ifdef JIVE_PROFILE_BLIT
	Uint32 t0 = jive_jiffies(), t1;
#endif //JIVE_PROFILE_BLIT
	SDL_Color clr;
	SDL_Surface *srf;

	// don't call render for null strings as it produces an error which we want to hide
	if (*str == '\0') {
		return NULL;
	}

	clr.r = (color >> 24) & 0xFF;
	clr.g = (color >> 16) & 0xFF;
	clr.b = (color >> 8) & 0xFF;

	srf = TTF_RenderUTF8_Blended(font->ttf, str, clr);

	if (!srf) {
		LOG_ERROR(log_ui_draw, "render returned error: %s\n", TTF_GetError());
	}

#if 0
	// draw text bounding box for debugging
	if (srf) {
		rectangleColor(srf, 0,0, srf->w - 1, srf->h - 1, 0xff0000df);
		lineColor(srf, 0, font->ascend, srf->w - 1, font->ascend, 0xff0000df);
		lineColor(srf, 0, font->ascend, srf->w - 1, font->ascend, 0xff0000df);
		lineColor(srf, 0, font->ascend - font->capheight, srf->w - 1, font->ascend - font->capheight, 0xff0000df);
	}
#endif


#ifdef JIVE_PROFILE_BLIT
	t1 = jive_jiffies();
	printf("\tdraw_ttf_font took=%d %s\n", t1-t0, str);
#endif //JIVE_PROFILE_BLIT

	return srf;
}

JiveSurface *jive_font_draw_text(JiveFont *font, Uint32 color, const char *str) {
	assert(font && font->magic == JIVE_FONT_MAGIC);

	return jive_surface_new_SDLSurface(str ? font->draw(font, color, str) : NULL);
}

JiveSurface *jive_font_ndraw_text(JiveFont *font, Uint32 color, const char *str, size_t len) {
	char *tmp;

	// FIXME use utf8 len

	tmp = alloca(len + 1);
	strncpy(tmp, str, len);
	*(tmp + len) = '\0';
	
	return jive_font_draw_text(font, color, tmp);
}


/*
binary 			hex 	decimal 	notes
00000000-01111111 	00-7F 	0-127	 	US-ASCII (single byte)
10000000-10111111 	80-BF 	128-191 	Second, third, or fourth byte of a multi-byte sequence
11000000-11000001 	C0-C1 	192-193 	Overlong encoding: start of a 2-byte sequence, but code point <= 127
11000010-11011111 	C2-DF 	194-223 	Start of 2-byte sequence
11100000-11101111 	E0-EF 	224-239 	Start of 3-byte sequence
11110000-11110100 	F0-F4 	240-244 	Start of 4-byte sequence
11110101-11110111 	F5-F7 	245-247 	Restricted by RFC 3629: start of 4-byte sequence for codepoint above 10FFFF
11111000-11111011 	F8-FB 	248-251 	Restricted by RFC 3629: start of 5-byte sequence
11111100-11111101 	FC-FD 	252-253 	Restricted by RFC 3629: start of 6-byte sequence
11111110-11111111 	FE-FF 	254-255 	Invalid: not defined by original UTF-8 specification
*/

Uint32 utf8_get_char(const char *ptr, const char **nptr)
{
	Uint32 c, v;
	const unsigned char *uptr = (const unsigned char *)ptr;

	c = *uptr++;

	if (c <= 127) {
		/* US-ASCII */
		v = c & 0x7F;
	}
	else if (c <= 191) {
		/* error */
		v = 0xFFFD;
	}
	else if (c <= 223) {
		/* 2-bytes */
		v = (c & 0x1F) << 6;
		c = *uptr++;
		v |= (c & 0x3F);
	}
	else if (c <= 239) {
		/* 3-byte */
		v = (c & 0x0F) << 12;
		c = *uptr++;
		v |= (c & 0x3F) << 6;
		c = *uptr++;
		v |= (c & 0x3F);
	}
	else if (c <= 244) {
		/* 4-byte */
		v = (c & 0x07) << 18;
		c = *uptr++;
		v |= (c & 0x3F) << 12;
		c = *uptr++;
		v |= (c & 0x3F) << 6;
		c = *uptr++;
		v |= (c & 0x3F);
	}
	else {
		/* error */
		v = 0xFFFD;
	}

	if (nptr) {
		*nptr = (const char *)uptr;
	}
	return v;
}


int jiveL_font_load(lua_State *L) {
	/*
	  class
	  fontname
	  size
	*/
	const char *fontname = luaL_checklstring(L, 2, NULL);
	int size = luaL_checkint(L, 3);

	if (fontname && size) {
		JiveFont *font = jive_font_load(fontname, size);
		if (font) {
			JiveFont **p = (JiveFont **)lua_newuserdata(L, sizeof(JiveFont *));
			*p = font;
			luaL_getmetatable(L, "JiveFont");
			lua_setmetatable(L, -2);
			return 1;
		}
	}

	return 0;
}

int jiveL_font_free(lua_State *L) {
	JiveFont *font = *(JiveFont **)lua_touserdata(L, 1);
	if (font) {
		jive_font_free(font);
	}
	return 0;
}

int jiveL_font_width(lua_State *L) {
 	JiveFont *font = *(JiveFont **)lua_touserdata(L, 1);
	const char *str = luaL_checklstring(L, 2, NULL);
	if (font) {
		lua_pushinteger(L, jive_font_width(font, str));
		return 1;
	}
	return 0;
}

int jiveL_font_capheight(lua_State *L) {
 	JiveFont *font = *(JiveFont **)lua_touserdata(L, 1);
	if (font) {
		lua_pushinteger(L, jive_font_capheight(font));
		return 1;
	}
	return 0;
}

int jiveL_font_height(lua_State *L) {
 	JiveFont *font = *(JiveFont **)lua_touserdata(L, 1);
	if (font) {
		lua_pushinteger(L, jive_font_height(font));
		return 1;
	}
	return 0;
}

int jiveL_font_ascend(lua_State *L) {
 	JiveFont *font = *(JiveFont **)lua_touserdata(L, 1);
	if (font) {
		lua_pushinteger(L, jive_font_ascend(font));
		return 1;
	}
	return 0;
}

int jiveL_font_offset(lua_State *L) {
 	JiveFont *font = *(JiveFont **)lua_touserdata(L, 1);
	if (font) {
		lua_pushinteger(L, jive_font_height(font));
		return 1;
	}
	return 0;
}

int jiveL_font_gc(lua_State *L) {
 	JiveFont *font = *(JiveFont **)lua_touserdata(L, 1);
	if (font) {
		jive_font_free(font);
	}
	return 0;
}
