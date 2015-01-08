/*
** Copyright 2010 Logitech. All Rights Reserved.
**
** This file is licensed under BSD. Please see the LICENSE file for details.
*/

#ifndef JIVE_H
#define JIVE_H

#include "common.h"
#include "log.h"

#include <SDL_image.h>
#include <SDL_ttf.h>
#include <SDL_gfxPrimitives.h>
#include <SDL_rotozoom.h>


/* target frame rate 14 fps (originally) - may be tuned per platform, should be /2 */
/* updated to the max effective rate of scrolling on a fab4 */
#define JIVE_FRAME_RATE 30

/* print profile information for blit's */
#undef JIVE_PROFILE_BLIT

#define MIN(a,b) (((a)<(b))?(a):(b))
#define MAX(a,b) (((a)>(b))?(a):(b))

#define JIVE_COLOR_WHITE 0xFFFFFFFF
#define JIVE_COLOR_BLACK 0x000000FF

#define JIVE_XY_NIL -1
#define JIVE_WH_NIL 65535
#define JIVE_WH_FILL 65534

typedef enum {
	/* note ordered for left->right sort */
	JIVE_ALIGN_CENTER = 0,
	JIVE_ALIGN_LEFT,
	JIVE_ALIGN_RIGHT,
	JIVE_ALIGN_TOP,
	JIVE_ALIGN_BOTTOM,
	JIVE_ALIGN_TOP_LEFT,
	JIVE_ALIGN_TOP_RIGHT,
	JIVE_ALIGN_BOTTOM_LEFT,
	JIVE_ALIGN_BOTTOM_RIGHT,
} JiveAlign;


typedef enum {
	JIVE_LAYOUT_NORTH = 0,
	JIVE_LAYOUT_EAST,
	JIVE_LAYOUT_SOUTH,
	JIVE_LAYOUT_WEST,
	JIVE_LAYOUT_CENTER,
	JIVE_LAYOUT_NONE,
} JiveLayout;


typedef enum {
	JIVE_LAYER_FRAME		= 0x01,
	JIVE_LAYER_CONTENT		= 0x02,
	JIVE_LAYER_CONTENT_OFF_STAGE	= 0x04,
	JIVE_LAYER_CONTENT_ON_STAGE	= 0x08,
	JIVE_LAYER_LOWER		= 0x10,
	JIVE_LAYER_TITLE		= 0x20,
	JIVE_LAYER_ALL			= 0xFF,
} JiveLayer;


typedef enum {
	JIVE_EVENT_NONE			= 0x00000000,

	JIVE_EVENT_SCROLL		= 0x00000001,
	JIVE_EVENT_ACTION		= 0x00000002,
        
	JIVE_EVENT_KEY_DOWN		= 0x00000010,
	JIVE_EVENT_KEY_UP		= 0x00000020,
	JIVE_EVENT_KEY_PRESS		= 0x00000040,
	JIVE_EVENT_KEY_HOLD		= 0x00000080,

	JIVE_EVENT_MOUSE_DOWN		= 0x00000100,
	JIVE_EVENT_MOUSE_UP		= 0x00000200,
	JIVE_EVENT_MOUSE_PRESS		= 0x00000400,
	JIVE_EVENT_MOUSE_HOLD		= 0x00000800,
	JIVE_EVENT_MOUSE_MOVE           = 0x01000000,
	JIVE_EVENT_MOUSE_DRAG           = 0x00100000,
    
	JIVE_EVENT_WINDOW_PUSH		= 0x00001000,
	JIVE_EVENT_WINDOW_POP		= 0x00002000,
	JIVE_EVENT_WINDOW_ACTIVE	= 0x00004000,
	JIVE_EVENT_WINDOW_INACTIVE	= 0x00008000,

	JIVE_EVENT_SHOW			= 0x00010000,
	JIVE_EVENT_HIDE			= 0x00020000,
	JIVE_EVENT_FOCUS_GAINED		= 0x00040000,
	JIVE_EVENT_FOCUS_LOST		= 0x00080000,

	JIVE_EVENT_WINDOW_RESIZE	= 0x00200000,
	JIVE_EVENT_SWITCH		= 0x00400000,
	JIVE_EVENT_MOTION		= 0x00800000,

	JIVE_EVENT_CHAR_PRESS           = 0x02000000,
	JIVE_EVENT_IR_PRESS             = 0x04000000,
	JIVE_EVENT_IR_HOLD              = 0x08000000,
	JIVE_EVENT_IR_UP                = 0x00000004,
	JIVE_EVENT_IR_DOWN              = 0x20000000,
	JIVE_EVENT_IR_REPEAT            = 0x40000000,
	JIVE_ACTION                     = 0x10000000,
	JIVE_EVENT_GESTURE              = 0x00000008,

	//Note: don't use 0x80000000, 0x40000000 is the highest usable value
	
	JIVE_EVENT_CHAR_ALL 	= ( JIVE_EVENT_CHAR_PRESS),
	JIVE_EVENT_IR_ALL               = ( JIVE_EVENT_IR_PRESS | JIVE_EVENT_IR_HOLD | JIVE_EVENT_IR_UP | JIVE_EVENT_IR_DOWN | JIVE_EVENT_IR_REPEAT),
	JIVE_EVENT_KEY_ALL		= ( JIVE_EVENT_KEY_DOWN | JIVE_EVENT_KEY_UP | JIVE_EVENT_KEY_PRESS | JIVE_EVENT_KEY_HOLD ),
	JIVE_EVENT_MOUSE_ALL		= ( JIVE_EVENT_MOUSE_DOWN | JIVE_EVENT_MOUSE_UP | JIVE_EVENT_MOUSE_PRESS | JIVE_EVENT_MOUSE_HOLD | JIVE_EVENT_MOUSE_MOVE | JIVE_EVENT_MOUSE_DRAG ),
	JIVE_EVENT_ALL_INPUT		= ( JIVE_EVENT_KEY_ALL | JIVE_EVENT_MOUSE_ALL | JIVE_EVENT_SCROLL | JIVE_EVENT_CHAR_ALL | JIVE_EVENT_IR_ALL | JIVE_EVENT_GESTURE),

	JIVE_EVENT_VISIBLE_ALL		= ( JIVE_EVENT_SHOW | JIVE_EVENT_HIDE ),
	JIVE_EVENT_ALL			= 0x7FFFFFFF,
} JiveEventType;


typedef enum {
	JIVE_EVENT_UNUSED		= 0x0000,
	JIVE_EVENT_CONSUME		= 0x0001,
	JIVE_EVENT_QUIT			= 0x0002,
} JiveEventStatus;


typedef enum {
	JIVE_KEY_NONE			= 0x0000,
	JIVE_KEY_GO			= 0x0001,
	JIVE_KEY_BACK			= 0x0002,
	JIVE_KEY_UP			= 0x0004,
	JIVE_KEY_DOWN			= 0x0008,
	JIVE_KEY_LEFT			= 0x0010,
	JIVE_KEY_RIGHT			= 0x0020,
	JIVE_KEY_HOME			= 0x0040,
	JIVE_KEY_PLAY			= 0x0080,
	JIVE_KEY_ADD			= 0x0100,
	JIVE_KEY_PAUSE			= 0x0200,
	JIVE_KEY_REW			= 0x0400,
	JIVE_KEY_FWD			= 0x0800,
	JIVE_KEY_VOLUME_UP		= 0x1000,
	JIVE_KEY_VOLUME_DOWN		= 0x2000,
	JIVE_KEY_PAGE_UP		= 0x4000,
	JIVE_KEY_PAGE_DOWN		= 0x8000,
	JIVE_KEY_PRINT			= 0x10000,
	JIVE_KEY_PRESET_1		= 0x20000,
	JIVE_KEY_PRESET_2		= 0x40000,
	JIVE_KEY_PRESET_3		= 0x80000,
	JIVE_KEY_PRESET_4		= 0x100000,
	JIVE_KEY_PRESET_5		= 0x200000,
	JIVE_KEY_PRESET_6		= 0x400000,
	JIVE_KEY_ALARM			= 0x800000,
	JIVE_KEY_MUTE			= 0x1000000,
	JIVE_KEY_POWER			= 0x2000000,
	JIVE_KEY_STOP           = 0x4000000,
	JIVE_KEY_REW_SCAN    	= 0x8000000,
	JIVE_KEY_FWD_SCAN		=0x10000000,
} JiveKey;

typedef enum {
	JIVE_GESTURE_L_R                = 0x0001,
	JIVE_GESTURE_R_L 	        = 0x0002,
} JiveGesture;


enum {
	/* reserved: 0x00000001 */
	/* reserved: 0x00000002 */
	/* reserved: 0x00000003 */
	JIVE_USER_EVENT_EVENT		= 0x00000004,
};


typedef struct jive_peer_meta JivePeerMeta;

typedef struct jive_inset JiveInset;

typedef struct jive_widget JiveWidget;

typedef struct jive_surface JiveSurface;

typedef JiveSurface JiveTile; // Bug 10001 refactoring

typedef struct jive_event JiveEvent;

typedef struct jive_font JiveFont;


struct jive_peer_meta {
	size_t size;
	const char *magic;
	lua_CFunction gc;
};

struct jive_inset {
	Uint16 left, top, right, bottom;
};

struct jive_widget {
	SDL_Rect bounds;
	SDL_Rect preferred_bounds;
	JiveInset padding;
	JiveInset border;
	Uint32 skin_origin;
	Uint32 child_origin;
	Uint32 layout_origin;
	JiveAlign align;
	Uint8 layer;
	Sint16 z_order;
	bool hidden;
};

struct jive_scroll_event {
	int rel;
};

struct jive_action_event {
	int index;
};

struct jive_key_event {
	JiveKey code;
};

struct jive_char_event {
	Uint16 unicode;
};

struct jive_mouse_event {
	Uint16 x;
	Uint16 y;
	/* extended to support touchscreens */
	Uint16 finger_count;
	Uint16 finger_pressure;
	Uint16 finger_width;
	Sint16 chiral_value;
	bool chiral_active;
};

struct jive_motion_event {
	Sint16 x;
	Sint16 y;
	Sint16 z;
};

struct jive_sw_event {
	Uint16 code;
	Uint16 value;
};

struct jive_ir_event {
	Uint32 code;
};

struct jive_gesture_event {
	JiveGesture code;
};

struct jive_event {
	JiveEventType type;
	Uint32 ticks;

	union {
		struct jive_scroll_event scroll;
		struct jive_action_event action;
		struct jive_key_event key;
		struct jive_char_event text;
		struct jive_mouse_event mouse;
		struct jive_motion_event motion;
		struct jive_sw_event sw;
		struct jive_ir_event ir;
		struct jive_gesture_event gesture;
	} u;
};

struct jive_font {
	Uint32 refcount;
	char *name;
	Uint16 size;

	// Specific font functions
	SDL_Surface *(*draw)(struct jive_font *, Uint32, const char *);
	int (*width)(struct jive_font *, const char *);
	void (*destroy)(struct jive_font *);

	// Data for specifc font types
	TTF_Font *ttf;
	int height;
	int capheight;
	int ascend;

	struct jive_font *next;

	const char *magic;
};

struct jive_perfwarn {
	Uint32 screen;
	Uint32 layout;
	Uint32 draw;
	Uint32 event;
	int queue;
	Uint32 garbage;
};


/* logging */
extern LOG_CATEGORY *log_ui_draw;
extern LOG_CATEGORY *log_ui;

/* extra pump function */
extern int (*jive_sdlevent_pump)(lua_State *L);

extern int (*jive_sdlfilter_pump)(const SDL_Event *event);
void jive_send_key_event(JiveEventType keyType, JiveKey keyCode, Uint32 ticks);
void jive_send_gesture_event(JiveGesture code);
void jive_send_char_press_event(Uint16 unicode);


/* platform functions */
void platform_init(lua_State *L);
char *platform_get_mac_address();
char *platform_get_ip_address(void);
char *platform_get_home_dir();
char *platform_get_arch();


/* global counter used to invalidate widget */
extern Uint32 jive_origin;

/* Util functions */
void jive_print_stack(lua_State *L, char *str);
void jive_debug_traceback(lua_State *L, int n);
int jiveL_getframework(lua_State *L);
int jive_getmethod(lua_State *L, int index, char *method) ;
void *jive_getpeer(lua_State *L, int index, JivePeerMeta *peerMeta);
void jive_torect(lua_State *L, int index, SDL_Rect *rect);
void jive_rect_union(SDL_Rect *a, SDL_Rect *b, SDL_Rect *c);
void jive_rect_intersection(SDL_Rect *a, SDL_Rect *b, SDL_Rect *c);
void jive_queue_event(JiveEvent *evt);
int jive_traceback (lua_State *L);

/* Surface functions */
JiveSurface *jive_surface_set_video_mode(Uint16 w, Uint16 h, Uint16 bpp, bool fullscreen);
JiveSurface *jive_surface_newRGB(Uint16 w, Uint16 h);
JiveSurface *jive_surface_newRGBA(Uint16 w, Uint16 h);
JiveSurface *jive_surface_new_SDLSurface(SDL_Surface *sdl_surface);
JiveSurface *jive_surface_ref(JiveSurface *srf);
JiveSurface *jive_surface_load_image(const char *path);
JiveSurface *jive_surface_load_image_data(const char *data, size_t len);
int jive_surface_set_wm_icon(JiveSurface *srf);
int jive_surface_save_bmp(JiveSurface *srf, const char *file);
int jive_surface_cmp(JiveSurface *a, JiveSurface *b, Uint32 key);
void jive_surface_get_offset(JiveSurface *src, Sint16 *x, Sint16 *y);
void jive_surface_set_offset(JiveSurface *src, Sint16 x, Sint16 y);
void jive_surface_get_clip(JiveSurface *srf, SDL_Rect *r);
void jive_surface_set_clip(JiveSurface *srf, SDL_Rect *r);
void jive_surface_push_clip(JiveSurface *srf, SDL_Rect *r, SDL_Rect *pop);
void jive_surface_set_clip_arg(JiveSurface *srf, Uint16 x, Uint16 y, Uint16 w, Uint16 h);
void jive_surface_get_clip_arg(JiveSurface *srf, Uint16 *x, Uint16 *y, Uint16 *w, Uint16 *h);
void jive_surface_flip(JiveSurface *srf);
void jive_surface_blit(JiveSurface *src, JiveSurface *dst, Uint16 dx, Uint16 dy);
void jive_surface_blit_clip(JiveSurface *src, Uint16 sx, Uint16 sy, Uint16 sw, Uint16 sh,
			    JiveSurface* dst, Uint16 dx, Uint16 dy);
void jive_surface_blit_alpha(JiveSurface *src, JiveSurface *dst, Uint16 dx, Uint16 dy, Uint8 alpha);
void jive_surface_get_size(JiveSurface *srf, Uint16 *w, Uint16 *h);
int jive_surface_get_bytes(JiveSurface *srf);
void jive_surface_free(JiveSurface *srf);
void jive_surface_release(JiveSurface *srf);

/* Encapsulated SDL_gfx functions */
JiveSurface *jive_surface_rotozoomSurface(JiveSurface *srf, double angle, double zoom, int smooth);
JiveSurface *jive_surface_zoomSurface(JiveSurface *srf, double zoomx, double zoomy, int smooth);
JiveSurface *jive_surface_shrinkSurface(JiveSurface *srf, int factorx, int factory);
JiveSurface *jive_surface_resize(JiveSurface *srf, int w, int h, bool keep_aspect);
void jive_surface_pixelColor(JiveSurface *srf, Sint16 x, Sint16 y, Uint32 col);
void jive_surface_hlineColor(JiveSurface *srf, Sint16 x1, Sint16 x2, Sint16 y, Uint32 color);
void jive_surface_vlineColor(JiveSurface *srf, Sint16 x, Sint16 y1, Sint16 y2, Uint32 color);
void jive_surface_rectangleColor(JiveSurface *srf, Sint16 x1, Sint16 y1, Sint16 x2, Sint16 y2, Uint32 col);
void jive_surface_boxColor(JiveSurface *srf, Sint16 x1, Sint16 y1, Sint16 x2, Sint16 y2, Uint32 col);
void jive_surface_lineColor(JiveSurface *srf, Sint16 x1, Sint16 y1, Sint16 x2, Sint16 y2, Uint32 col);
void jive_surface_aalineColor(JiveSurface *srf, Sint16 x1, Sint16 y1, Sint16 x2, Sint16 y2, Uint32 col);
void jive_surface_circleColor(JiveSurface *srf, Sint16 x, Sint16 y, Sint16 r, Uint32 col);
void jive_surface_aacircleColor(JiveSurface *srf, Sint16 x, Sint16 y, Sint16 r, Uint32 col);
void jive_surface_filledCircleColor(JiveSurface *srf, Sint16 x, Sint16 y, Sint16 r, Uint32 col);
void jive_surface_ellipseColor(JiveSurface *srf, Sint16 x, Sint16 y, Sint16 rx, Sint16 ry, Uint32 col);
void jive_surface_aaellipseColor(JiveSurface *srf, Sint16 x, Sint16 y, Sint16 rx, Sint16 ry, Uint32 col);
void jive_surface_filledEllipseColor(JiveSurface *srf, Sint16 x, Sint16 y, Sint16 rx, Sint16 ry, Uint32 col);
void jive_surface_pieColor(JiveSurface *srf, Sint16 x, Sint16 y, Sint16 rad, Sint16 start, Sint16 end, Uint32 col);
void jive_surface_filledPieColor(JiveSurface *srf, Sint16 x, Sint16 y, Sint16 rad, Sint16 start, Sint16 end, Uint32 col);
void jive_surface_trigonColor(JiveSurface *srf, Sint16 x1, Sint16 y1, Sint16 x2, Sint16 y2, Sint16 x3, Sint16 y3, Uint32 col);
void jive_surface_aatrigonColor(JiveSurface *srf, Sint16 x1, Sint16 y1, Sint16 x2, Sint16 y2, Sint16 x3, Sint16 y3, Uint32 col);
void jive_surface_filledTrigonColor(JiveSurface *srf, Sint16 x1, Sint16 y1, Sint16 x2, Sint16 y2, Sint16 x3, Sint16 y3, Uint32 col);

/* Tile functions */
JiveTile *jive_tile_fill_color(Uint32 col);
JiveTile *jive_tile_load_image(const char *path);
JiveTile *jive_tile_load_image_data(const char *data, size_t len);
JiveTile *jive_tile_load_tiles(char *path[9]);
JiveTile *jive_tile_load_vtiles(char *path[3]);
JiveTile *jive_tile_load_htiles(char *path[3]);
JiveTile *jive_tile_ref(JiveTile *tile);
void jive_tile_get_min_size(JiveTile *tile, Uint16 *w, Uint16 *h);
void jive_tile_set_alpha(JiveTile *tile, Uint32 flags);
void jive_tile_free(JiveTile *tile);
void jive_tile_blit(JiveTile *tile, JiveSurface *dst, Uint16 dx, Uint16 dy, Uint16 dw, Uint16 dh);
void jive_tile_blit_centered(JiveTile *tile, JiveSurface *dst, Uint16 dx, Uint16 dy, Uint16 dw, Uint16 dh);
SDL_Surface *jive_tile_get_image_surface(JiveTile *tile);


/* Font functions */
JiveFont *jive_font_load(const char *name, Uint16 size);
JiveFont *jive_font_ref(JiveFont *font);
void jive_font_free(JiveFont *font);
int jive_font_width(JiveFont *font, const char *str);
int jive_font_nwidth(JiveFont *font, const char *str, size_t len);
int jive_font_miny_char(JiveFont *font, Uint16 ch);
int jive_font_maxy_char(JiveFont *font, Uint16 ch);
int jive_font_height(JiveFont *font);
int jive_font_capheight(JiveFont *font);
int jive_font_ascend(JiveFont *font);
int jive_font_offset(JiveFont *font);
JiveSurface *jive_font_draw_text(JiveFont *font, Uint32 color, const char *str);
JiveSurface *jive_font_ndraw_text(JiveFont *font, Uint32 color, const char *str, size_t len);
Uint32 utf8_get_char(const char *ptr, const char **nptr);


/* C helper functions */
void jive_redraw(SDL_Rect *r);
void jive_pushevent(lua_State *L, JiveEvent *event);

void jive_widget_pack(lua_State *L, int index, JiveWidget *data);
int jive_widget_halign(JiveWidget *this, JiveAlign align, Uint16 width);
int jive_widget_valign(JiveWidget *this, JiveAlign align, Uint16 height);

int jive_style_int(lua_State *L, int index, const char *key, int def);
Uint32 jive_style_color(lua_State *L, int index, const char *key, Uint32 def, bool *is_set);
JiveSurface *jive_style_image(lua_State *L, int index, const char *key, JiveSurface *def);
JiveTile *jive_style_tile(lua_State *L, int index, const char *key, JiveTile *def);
JiveFont *jive_style_font(lua_State *L, int index, const char *key);
JiveAlign jive_style_align(lua_State *L, int index, char *key, JiveAlign def);
void jive_style_insets(lua_State *L, int index, char *key, JiveInset *inset);
int jive_style_array_size(lua_State *L, int index, char *key);
int jive_style_array_int(lua_State *L, int index, const char *array, int n, const char *key, int def);
JiveFont *jive_style_array_font(lua_State *L, int index, const char *array, int n, const char *key);
Uint32 jive_style_array_color(lua_State *L, int index, const char *array, int n, const char *key, Uint32 def, bool *is_set);


/* lua functions */
int jiveL_get_background(lua_State *L);
int jiveL_set_background(lua_State *L);
int jiveL_dispatch_event(lua_State *L);
int jiveL_dirty(lua_State *L);

int jiveL_event_new(lua_State *L);
int jiveL_event_tostring(lua_State* L);
int jiveL_event_get_type(lua_State *L);
int jiveL_event_get_ticks(lua_State *L);
int jiveL_event_get_scroll(lua_State *L);
int jiveL_event_get_keycode(lua_State *L);
int jiveL_event_get_unicode(lua_State *L);
int jiveL_event_get_mouse(lua_State *L);
int jiveL_event_get_action_internal(lua_State *L);
int jiveL_event_get_motion(lua_State *L);
int jiveL_event_get_switch(lua_State *L);
int jiveL_event_get_ircode(lua_State *L);
int jiveL_event_get_gesture(lua_State *L);

int jiveL_widget_set_bounds(lua_State *L);
int jiveL_widget_get_bounds(lua_State *L);
int jiveL_widget_get_z_order(lua_State *L);
int jiveL_widget_is_hidden(lua_State *L);
int jiveL_widget_get_preferred_bounds(lua_State *L);
int jiveL_widget_get_padding(lua_State *L);
int jiveL_widget_get_border(lua_State *L);
int jiveL_widget_mouse_bounds(lua_State *L);
int jiveL_widget_mouse_inside(lua_State *L);
int jiveL_widget_reskin(lua_State *L);
int jiveL_widget_relayout(lua_State *L);
int jiveL_widget_redraw(lua_State *L);
int jiveL_widget_check_skin(lua_State *L);
int jiveL_widget_check_layout(lua_State *L);
int jiveL_widget_peer_tostring(lua_State *L);

int jiveL_icon_get_preferred_bounds(lua_State *L);
int jiveL_icon_skin(lua_State *L);
int jiveL_icon_set_value(lua_State *L);
int jiveL_icon_layout(lua_State *L);
int jiveL_icon_animate(lua_State *L);
int jiveL_icon_draw(lua_State *L);
int jiveL_icon_gc(lua_State *L);

int jiveL_label_get_preferred_bounds(lua_State *L);
int jiveL_label_skin(lua_State *L);
int jiveL_label_layout(lua_State *L);
int jiveL_label_animate(lua_State *L);
int jiveL_label_draw(lua_State *L);
int jiveL_label_gc(lua_State *L);

int jiveL_group_get_preferred_bounds(lua_State *L);
int jiveL_group_skin(lua_State *L);
int jiveL_group_layout(lua_State *L);
int jiveL_group_iterate(lua_State *L);
int jiveL_group_draw(lua_State *L);
int jiveL_group_gc(lua_State *L);

int jiveL_textinput_get_preferred_bounds(lua_State *L);
int jiveL_textinput_skin(lua_State *L);
int jiveL_textinput_layout(lua_State *L);
int jiveL_textinput_draw(lua_State *L);
int jiveL_textinput_gc(lua_State *L);

int jiveL_menu_get_preferred_bounds(lua_State *L);
int jiveL_menu_skin(lua_State *L);
int jiveL_menu_layout(lua_State *L);
int jiveL_menu_iterate(lua_State *L);
int jiveL_menu_draw(lua_State *L);
int jiveL_menu_gc(lua_State *L);

int jiveL_textarea_get_preferred_bounds(lua_State *L);
int jiveL_textarea_skin(lua_State *L);
int jiveL_textarea_invalidate(lua_State *L);
int jiveL_textarea_layout(lua_State *L);
int jiveL_textarea_draw(lua_State *L);
int jiveL_textarea_gc(lua_State *L);

int jiveL_window_skin(lua_State *L);
int jiveL_window_check_layout(lua_State *L);
int jiveL_window_iterate(lua_State *L);
int jiveL_window_draw_or_transition(lua_State *L);
int jiveL_window_draw(lua_State *L);
int jiveL_window_event_handler(lua_State *L);
int jiveL_window_gc(lua_State *L);

int jiveL_slider_skin(lua_State *L);
int jiveL_slider_layout(lua_State *L);
int jiveL_slider_draw(lua_State *L);
int jiveL_slider_get_preferred_bounds(lua_State *L);
int jiveL_slider_get_pill_bounds(lua_State *L);
int jiveL_slider_gc(lua_State *L);

int jiveL_style_path(lua_State *L);
int jiveL_style_value(lua_State *L);
int jiveL_style_rawvalue(lua_State *L);
int jiveL_style_color(lua_State *L);
int jiveL_style_array_color(lua_State *L);
int jiveL_style_font(lua_State *L);

int jiveL_font_load(lua_State *L);
int jiveL_font_free(lua_State *L);
int jiveL_font_width(lua_State *L);
int jiveL_font_capheight(lua_State *L);
int jiveL_font_height(lua_State *L);
int jiveL_font_ascend(lua_State *L);
int jiveL_font_offset(lua_State *L);
int jiveL_font_gc(lua_State *L);

int jiveL_surface_newRGB(lua_State *L);
int jiveL_surface_newRGBA(lua_State *L);
int jiveL_surface_load_image(lua_State *L);
int jiveL_surface_load_image_data(lua_State *L);
int jiveL_surface_draw_text(lua_State *L);
int jiveL_surface_free(lua_State *L);
int jiveL_surface_release(lua_State *L);
int jiveL_surface_save_bmp(lua_State *L);
int jiveL_surface_cmp(lua_State *L);
int jiveL_surface_set_offset(lua_State *L);
int jiveL_surface_set_clip_arg(lua_State *L);
int jiveL_surface_get_clip_arg(lua_State *L);
int jiveL_surface_blit(lua_State *L);
int jiveL_surface_blit_clip(lua_State *L);
int jiveL_surface_blit_alpha(lua_State *L);
int jiveL_surface_get_size(lua_State *L);
int jiveL_surface_get_bytes(lua_State *L);
int jiveL_surface_rotozoomSurface(lua_State *L);
int jiveL_surface_zoomSurface(lua_State *L);
int jiveL_surface_shrinkSurface(lua_State *L);
int jiveL_surface_resize(lua_State *L);
int jiveL_surface_pixelColor(lua_State *L);
int jiveL_surface_hlineColor(lua_State *L);
int jiveL_surface_vlineColor(lua_State *L);
int jiveL_surface_rectangleColor(lua_State *L);
int jiveL_surface_boxColor(lua_State *L);
int jiveL_surface_lineColor(lua_State *L);
int jiveL_surface_aalineColor(lua_State *L);
int jiveL_surface_circleColor(lua_State *L);
int jiveL_surface_aacircleColor(lua_State *L);
int jiveL_surface_filledCircleColor(lua_State *L);
int jiveL_surface_ellipseColor(lua_State *L);
int jiveL_surface_aaellipseColor(lua_State *L);
int jiveL_surface_filledEllipseColor(lua_State *L);
int jiveL_surface_pieColor(lua_State *L);
int jiveL_surface_filledPieColor(lua_State *L);
int jiveL_surface_trigonColor(lua_State *L);
int jiveL_surface_aatrigonColor(lua_State *L);
int jiveL_surface_filledTrigonColor(lua_State *L);
int jiveL_tile_fill_color(lua_State *L);

int jiveL_tile_load_image(lua_State *L);
int jiveL_tile_load_tiles(lua_State *L);
int jiveL_tile_load_vtiles(lua_State *L);
int jiveL_tile_load_htiles(lua_State *L);
int jiveL_tile_free(lua_State *L);
int jiveL_tile_blit(lua_State *L);
int jiveL_tile_min_size(lua_State *L);
int jiveL_surfacetile_gc(lua_State *L);


#define JIVEL_STACK_CHECK_BEGIN(L) { int _sc = lua_gettop((L));
#define JIVEL_STACK_CHECK_ASSERT(L) assert(_sc == lua_gettop((L)));
#define JIVEL_STACK_CHECK_END(L) JIVEL_STACK_CHECK_ASSERT(L) }

void copyResampled (SDL_Surface *dst, SDL_Surface *src, int dstX, int dstY, int srcX, int srcY,	int dstW, int dstH, int srcW, int srcH);

#endif // JIVE_H
