/*
** Copyright 2010 Logitech. All Rights Reserved.
**
** This file is licensed under BSD. Please see the LICENSE file for details.
*/

#include "common.h"
#include "jive.h"

#include <time.h>

#include <SDL_syswm.h>

int (*jive_sdlevent_pump)(lua_State *L);
int (*jive_sdlfilter_pump)(const SDL_Event *event);

LOG_CATEGORY *log_ui_draw;
LOG_CATEGORY *log_ui;

SDL_Rect jive_dirty_region, last_dirty_region;

/* global counter used to invalidate widget skin and layout */
Uint32 jive_origin = 0;
static Uint32 next_jive_origin = 0;


/* performance warning thresholds, 0 = disabled */
struct jive_perfwarn perfwarn = { 0, 0, 0, 0, 0, 0 };


/* button hold threshold 1 seconds */
#define HOLD_TIMEOUT 1000

#define LONG_HOLD_TIMEOUT 3500

#define POINTER_TIMEOUT 20000

static bool update_screen = true;

static JiveTile *jive_background = NULL;

static Uint16 screen_w, screen_h, screen_bpp;

static bool screen_isfull = false;

struct jive_keymap {
	SDLKey keysym;
	SDLMod mod;      // 0 for don't care, otherwise expected SDLmod value
	JiveKey keycode;
};

struct jive_keyir {
	SDLKey keysym;
	Uint32 code;
};

static enum jive_key_state {
	KEY_STATE_NONE,
	KEY_STATE_DOWN,
	KEY_STATE_SENT,
} key_state = KEY_STATE_NONE;

static enum jive_mouse_state {
	MOUSE_STATE_NONE,
	MOUSE_STATE_DOWN,
	MOUSE_STATE_SENT,
} mouse_state = MOUSE_STATE_NONE;

static JiveKey key_mask = 0;

static Uint32 key_timeout = 0;

static Uint32 mouse_timeout = 0;
static Uint32 mouse_long_timeout = 0;
static Uint32 mouse_timeout_arg;

static Uint32 pointer_timeout = 0;
static bool pointer_enable = true;

static Uint16 mouse_origin_x, mouse_origin_y;

static struct jive_keymap keymap[] = {
	{ SDLK_LEFT,		0, JIVE_KEY_LEFT },
	{ SDLK_RIGHT,		0, JIVE_KEY_RIGHT },
	{ SDLK_UP,			0, JIVE_KEY_UP },
	{ SDLK_DOWN,		0, JIVE_KEY_DOWN },
	{ SDLK_END,			0, JIVE_KEY_BACK },
	{ SDLK_HOME,		0, JIVE_KEY_HOME },
	//{ SDLK_RIGHT,		0, JIVE_KEY_GO },
	//{ SDLK_LEFT,		0, JIVE_KEY_BACK },
	{ SDLK_KP_PLUS,		0, JIVE_KEY_ADD },
	{ SDLK_PAGEUP,		0, JIVE_KEY_PAGE_UP },
	{ SDLK_PAGEDOWN,	0, JIVE_KEY_PAGE_DOWN },
	{ SDLK_PRINT,		0, JIVE_KEY_PRINT },
	{ SDLK_SYSREQ,		0, JIVE_KEY_PRINT },
	{ SDLK_F1,          0, JIVE_KEY_PRESET_1 },
	{ SDLK_F2,          0, JIVE_KEY_PRESET_2 },
	{ SDLK_F3,          0, JIVE_KEY_PRESET_3 },
	{ SDLK_F4,          0, JIVE_KEY_PRESET_4 },
	{ SDLK_F5,          0, JIVE_KEY_PRESET_5 },
	{ SDLK_F6,          0, JIVE_KEY_PRESET_6 },
	{ SDLK_POWER,       0, JIVE_KEY_POWER },

#ifdef SDL_MEDIAKEYS_DEFINED
	// include with patched SDL - optimised for windows MCE remotes
	{ SDLK_AudioPlay,   0, JIVE_KEY_PLAY },
	{ SDLK_AudioPause,  0, JIVE_KEY_PAUSE },
	{ SDLK_AudioPrev,   0, JIVE_KEY_REW },
	{ SDLK_AudioNext,   0, JIVE_KEY_FWD },
	{ SDLK_AudioStop,   0, JIVE_KEY_STOP },
	{ SDLK_AudioRaiseVolume, 0, JIVE_KEY_VOLUME_UP },
	{ SDLK_AudioLowerVolume, 0, JIVE_KEY_VOLUME_DOWN },
	{ SDLK_AudioMute,   0, JIVE_KEY_MUTE },
	{ SDLK_LeftMouse,   0, JIVE_KEY_BACK },
	{ SDLK_RightMouse,  0, JIVE_KEY_GO },
	{ SDLK_WWW,         0, JIVE_KEY_HOME },
#endif

	// control modified keypresses from windows MCE remote
	{ SDLK_RETURN, KMOD_LALT,                JIVE_KEY_HOME },     // "Start button"
	{ SDLK_F4,     KMOD_LALT,                JIVE_KEY_HOME },     // "Close button"
	{ SDLK_b,      KMOD_LCTRL | KMOD_LSHIFT, JIVE_KEY_REW_SCAN }, // "Scan back"
	{ SDLK_f,      KMOD_LCTRL | KMOD_LSHIFT, JIVE_KEY_FWD_SCAN }, // "Scan forward"
	{ SDLK_r,      KMOD_LCTRL,               JIVE_KEY_ADD },      // "Rec"
	{ SDLK_t,      KMOD_LCTRL | KMOD_LSHIFT, JIVE_KEY_PRESET_1 }, // "Yello"
	{ SDLK_m,      KMOD_LCTRL,               JIVE_KEY_PRESET_2 }, // "Blue"
	{ SDLK_i,      KMOD_LCTRL,               JIVE_KEY_PRESET_3 }, // "Green"
	{ SDLK_e,      KMOD_LCTRL,               JIVE_KEY_PRESET_4 }, // "Red"
	{ SDLK_o,      KMOD_LCTRL,               JIVE_KEY_PRESET_5 }, // "Preset"
	{ SDLK_g,      KMOD_LCTRL,               JIVE_KEY_PRESET_6 }, // "Preset"
	//{ SDLK_t,      KMOD_LCTRL, JIVE_KEY_PRESET_6 }, // "Preset"
	//{ SDLK_m,      KMOD_LCTRL | KMOD_LSHIFT, JIVE_KEY_PRESET_6 }, // "Preset"

	{ SDLK_RETURN,		0, JIVE_KEY_GO },

	{ SDLK_UNKNOWN,     0, JIVE_KEY_NONE },
};

#ifdef EMULATE_IR
static struct jive_keyir irmap[] = {
	{ SDLK_UP,       0x7689e01f }, /* arrow_up */
	{ SDLK_DOWN,     0x7689b04f }, /* arrow_down */
	{ SDLK_LEFT,     0x7689906f }, /* arrow_left */
	{ SDLK_RIGHT,    0x7689d02f }, /* arrow_right */
	{ SDLK_0,        0x76899867 },
	{ SDLK_1,        0x7689f00f },
	{ SDLK_2,        0x768908f7 },
	{ SDLK_3,        0x76898877 },
	{ SDLK_4,        0x768948b7 },
	{ SDLK_5,        0x7689c837 },
	{ SDLK_6,        0x768928d7 },
	{ SDLK_7,        0x7689a857 },
	{ SDLK_8,        0x76896897 },
	{ SDLK_9,        0x7689e817 },
	{ SDLK_x,        0x768910ef }, /* play */
	{ SDLK_a,        0x7689609f }, /* add */
	{ SDLK_UNKNOWN,	 0x0        },
};
#endif

static int process_event(lua_State *L, SDL_Event *event);
static void process_timers(lua_State *L);
static int filter_events(const SDL_Event *event);
int jiveL_update_screen(lua_State *L);


int jive_traceback (lua_State *L) {
	lua_getfield(L, LUA_GLOBALSINDEX, "debug");
	if (!lua_istable(L, -1)) {
		lua_pop(L, 1);
		return 1;
	}
	lua_getfield(L, -1, "traceback");
	if (!lua_isfunction(L, -1)) {
		lua_pop(L, 2);
		return 1;
	}
	lua_pushvalue(L, 1);  /* pass error message */
	lua_pushinteger(L, 2);  /* skip this function and traceback */
	lua_call(L, 2, 1);  /* call debug.traceback */
	return 1;
}


static int jiveL_initSDL(lua_State *L) {
	const SDL_VideoInfo *video_info;
	JiveSurface *srf, *splash, *icon;
	JiveSurface **p;
	Uint16 splash_w, splash_h;

	/* logging */
	log_ui_draw = LOG_CATEGORY_GET("jivelite.ui.draw");
	log_ui = LOG_CATEGORY_GET("jivelite.ui");

	/* linux fbcon does not need a mouse */
	SDL_putenv("SDL_NOMOUSE=1");

	if(SDL_getenv("JIVE_NOCURSOR")) {
		pointer_enable = false;
	}

	/* initialise SDL */
	if (SDL_Init(SDL_INIT_VIDEO) < 0) {
		LOG_ERROR(log_ui_draw, "SDL_Init(V|T|A): %s\n", SDL_GetError());
		SDL_Quit();
		exit(-1);
	}

	/* report video info */
	if ((video_info = SDL_GetVideoInfo())) {
		LOG_INFO(log_ui_draw, "%d,%d %d bits/pixel %d bytes/pixel [R<<%d G<<%d B<<%d]", video_info->current_w, video_info->current_h, video_info->vfmt->BitsPerPixel, video_info->vfmt->BytesPerPixel, video_info->vfmt->Rshift, video_info->vfmt->Gshift, video_info->vfmt->Bshift);
		LOG_INFO(log_ui_draw, "Hardware acceleration %s available", video_info->hw_available?"is":"is not");
		LOG_INFO(log_ui_draw, "Window manager %s available", video_info->wm_available?"is":"is not");
	}

	/* Register callback for additional events (used for multimedia keys)*/
	SDL_EventState(SDL_SYSWMEVENT,SDL_ENABLE);
	SDL_SetEventFilter(filter_events);

	platform_init(L);

	/* open window */
	SDL_WM_SetCaption("JiveLite", "JiveLite");
	SDL_ShowCursor(SDL_DISABLE);
	SDL_EnableKeyRepeat (100, 100);
	SDL_EnableUNICODE(1);

	/* load the icon */
	icon = jive_surface_load_image("jive/app.png");
	if (icon) {
		jive_surface_set_wm_icon(icon);
		jive_surface_free(icon);
	}

	screen_w = video_info->current_w;
	screen_h = video_info->current_h;

	screen_bpp = video_info->vfmt->BitsPerPixel;

	splash = jive_surface_load_image("jive/splash.png");
	if (splash) {
		jive_surface_get_size(splash, &splash_w, &splash_h);
		if (video_info->wm_available) {
			screen_w = splash_w;
			screen_h = splash_h;
		}
	}

	srf = jive_surface_set_video_mode(screen_w, screen_h, screen_bpp, video_info->wm_available ? false : true);
	if (!srf) {
		LOG_ERROR(log_ui_draw, "Video mode not supported: %dx%d\n", screen_w, screen_h);
		SDL_Quit();
		exit(-1);
	}

	if (splash) {
		jive_surface_blit(splash, srf, MAX(0, (screen_w - splash_w) / 2), MAX(0, (screen_h - splash_h) / 2));
		jive_surface_flip(srf);
	}

	lua_getfield(L, 1, "screen");
	if (lua_isnil(L, -1)) {
		LOG_ERROR(log_ui_draw, "no screen table");

		SDL_Quit();
		exit(-1);
	}

	/* store screen surface */
	p = (JiveSurface **)lua_newuserdata(L, sizeof(JiveSurface *));
	*p = jive_surface_ref(srf);
	luaL_getmetatable(L, "JiveSurface");
	lua_setmetatable(L, -2);

	lua_setfield(L, -2, "surface");

	lua_getfield(L, -1, "bounds");
	lua_pushinteger(L, screen_w);
	lua_rawseti(L, -2, 3);
	lua_pushinteger(L, screen_h);
	lua_rawseti(L, -2, 4);
	lua_pop(L, 2);

	/* background image */
	jive_background = jive_tile_fill_color(0x000000FF);

	/* jive.ui.style = {} */
	lua_getglobal(L, "jive");
	lua_getfield(L, -1, "ui");
	lua_newtable(L);
	lua_setfield(L, -2, "style");
	lua_pop(L, 2);

	return 0;
}

static int filter_events(const SDL_Event *event)
{
	if (jive_sdlfilter_pump) {
		return jive_sdlfilter_pump(event);
	}
	
	return 1;
}

void jive_send_key_event(JiveEventType keyType, JiveKey keyCode, Uint32 ticks) {
	JiveEvent keyEvent;
	memset(&keyEvent, 0, sizeof(JiveEvent));
	
	keyEvent.type = keyType;
	keyEvent.ticks = ticks;
	keyEvent.u.key.code = keyCode;
	jive_queue_event(&keyEvent);
}

void jive_send_gesture_event(JiveGesture code) {
	JiveEvent event;
	memset(&event, 0, sizeof(JiveEvent));

	event.type = JIVE_EVENT_GESTURE;
	event.ticks = jive_jiffies();
	event.u.gesture.code = code;
	jive_queue_event(&event);
}

void jive_send_char_press_event(Uint16 unicode) {
	JiveEvent event;
	memset(&event, 0, sizeof(JiveEvent));

	event.type = JIVE_EVENT_CHAR_PRESS;
	event.ticks = jive_jiffies();
	event.u.text.unicode = unicode;
	jive_queue_event(&event);
}


static int jiveL_quit(lua_State *L) {

	/* de-reference all windows */
	jiveL_getframework(L);
	lua_pushnil(L);
	lua_setfield(L, -2, "windowStack");
	lua_pop(L, 1);

	/* force lua GC */
	lua_gc(L, LUA_GCCOLLECT, 0);

	/* quit SDL */
	SDL_Quit();

	return 0;
}


static int jiveL_process_events(lua_State *L) {
	Uint32 r = 0;
	SDL_Event event;

	/* stack:
	 * 1 : jive.ui.Framework
	 */

	JIVEL_STACK_CHECK_BEGIN(L);

	/* Exit if we have no windows */
	lua_getfield(L, 1, "windowStack");
	if (lua_objlen(L, -1) == 0) {
		lua_pop(L, 1);

		lua_pushboolean(L, 0);
		return 1;
	}
	lua_rawgeti(L, -1, 1);


	/* pump keyboard/mouse events once per frame */
	SDL_PumpEvents();

	if (jive_sdlevent_pump) {
		jive_sdlevent_pump(L);
	}

	/* process events */
	process_timers(L);
	while (SDL_PeepEvents(&event, 1, SDL_GETEVENT, SDL_ALLEVENTS) > 0 ) {
		r |= process_event(L, &event);
	}

	lua_pop(L, 2);
	
	JIVEL_STACK_CHECK_END(L);

	if (r & JIVE_EVENT_QUIT) {
		lua_pushboolean(L, 0);
		return 1;
	}

	lua_pushboolean(L, 1);
	return lua_yield(L, 1);
}


int jiveL_set_update_screen(lua_State *L) {
	/* stack is:
	 * 1: framework
	 * 2: enable/disable screen updates
	 */

	bool old_update_screen = update_screen;
	update_screen = lua_toboolean(L, 2);

	if (update_screen && !old_update_screen) {
		/* cancel any pending transitions */
		lua_pushnil(L);
		lua_setfield(L, 1, "transition");

		/* redraw now */
		lua_pushcfunction(L, jiveL_update_screen);
		lua_pushvalue(L, 1);
		lua_call(L, 1, 0);

		/* short delay to allow video buffer to flip */
		SDL_Delay(50);
	}

	return 0;
}


static int _draw_screen(lua_State *L) {
	JiveSurface *srf;
	Uint32 t0 = 0, t1 = 0, t2 = 0, t3 = 0, t4 = 0;
	clock_t c0 = 0, c1 = 0;
	bool_t standalone_draw, drawn = false;


	JIVEL_STACK_CHECK_BEGIN(L);

	/* stack is:
	 * 1: framework
	 * 2: surface (in screen format)
	 * 3: standalone_draw (used to draw screen to a new surface)
	 */

	srf = *(JiveSurface **)lua_touserdata(L, 2);
	
	standalone_draw = lua_toboolean(L, 3);

	/* Exit if we have no windows, nothing to draw */
	lua_getfield(L, 1, "windowStack");
	if (lua_objlen(L, -1) == 0) {
		lua_pop(L, 1);

		JIVEL_STACK_CHECK_ASSERT(L);
		return 0;
	}
	lua_rawgeti(L, -1, 1);	// topwindow

	if (perfwarn.screen) {
		t0 = jive_jiffies();
		c0 = clock();
	}


	do {
		jive_origin = next_jive_origin;

		/* Layout window and widgets */
		if (jive_getmethod(L, -1, "checkLayout")) {
			lua_pushvalue(L, -2);
			lua_call(L, 1, 0);
		}

		/* check in case the origin changes during layout */
	} while (jive_origin != next_jive_origin);

	if (perfwarn.screen) t1 = jive_jiffies();
 
	/* Widget animations - don't update in a standalone draw as its not the main screen update */
	if (!standalone_draw) {
		lua_getfield(L, 1, "animations");
		lua_pushnil(L);
		while (lua_next(L, -2) != 0) {
			lua_getfield(L, -1, "animations");
			lua_pushnil(L);
			while (lua_next(L, -2) != 0) {
				int frame;
				
				/* stack is:
				 * -2: key
				 * -1: table
				 */
				lua_rawgeti(L, -1, 2);
				frame = lua_tointeger(L, -1) - 1;
				
				if (frame == 0) {
					lua_rawgeti(L, -2, 1); // function
					lua_pushvalue(L, -6); // widget
					lua_call(L, 1, 0);
					// function is poped by lua_call
					
					lua_rawgeti(L, -2, 3);
					lua_rawseti(L, -3, 2);
				}
				else {
				  lua_pushinteger(L, frame);
				  lua_rawseti(L, -3, 2);
				}
				lua_pop(L, 2);
			}
			lua_pop(L, 2);
		}
		lua_pop(L, 1);
	}

	if (perfwarn.screen) t2 = jive_jiffies();

	/* Window transitions */
	lua_getfield(L, 1, "transition");
	if (!lua_isnil(L, -1)) {
		/* Draw background */
		jive_surface_set_clip(srf, NULL);
		jive_tile_set_alpha(jive_background, 0); // no alpha channel
		jive_tile_blit(jive_background, srf, 0, 0, screen_w, screen_h);

		if (perfwarn.screen) t3 = jive_jiffies();
		
		/* Animate screen transition */
		lua_pushvalue(L, -1);
		lua_pushvalue(L, -3);  	// widget
		lua_pushvalue(L, 2);	// surface
		lua_call(L, 2, 0);

		drawn = true;
	}
	else if (jive_dirty_region.w || standalone_draw) {
		SDL_Rect dirty;

		/* only redraw dirty region for non standalone draws */
		if (!standalone_draw) {
			jive_rect_union(&jive_dirty_region, &last_dirty_region, &dirty);
			jive_surface_set_clip(srf, &dirty);
		}

#if 0
		printf("REDRAW: %d,%d %dx%d\n", jive_dirty_region.x, jive_dirty_region.y, jive_dirty_region.w, jive_dirty_region.h);
		printf("--> %d,%d %dx%d\n", dirty.x, dirty.y, dirty.w, dirty.h);
#endif

		/* Draw background */
		jive_tile_blit(jive_background, srf, 0, 0, screen_w, screen_h);

		if (perfwarn.screen) t3 = jive_jiffies();

		/* Draw screen */
		if (jive_getmethod(L, -2, "draw")) {
			lua_pushvalue(L, -3);	// widget
			lua_pushvalue(L, 2);	// surface
			lua_pushinteger(L, JIVE_LAYER_ALL); // layer
			lua_call(L, 3, 0);
		}

#if 0
		// show the dirty region for debug purposes:
		jive_surface_rectangleColor(srf, jive_dirty_region.x, jive_dirty_region.y,
			jive_dirty_region.x + jive_dirty_region.w, jive_dirty_region.y + jive_dirty_region.h, 0xFFFFFFFF);
#endif	

		/* clear the dirty region for non standalone draws */
		if (!standalone_draw) {
			memcpy(&last_dirty_region, &jive_dirty_region, sizeof(last_dirty_region));
			jive_dirty_region.w = 0;
		}

		drawn = true;
	}

	if (perfwarn.screen) {
		t4 = jive_jiffies();
		c1 = clock();
		if (t4-t0 > perfwarn.screen) {
			if (!t3) {
				t3 = t2;
			}
			printf("update_screen > %dms: %4dms (%dms) [layout:%dms animate:%dms background:%dms draw:%dms]\n",
				   perfwarn.screen, t4-t0, (int)((c1-c0) * 1000 / CLOCKS_PER_SEC), t1-t0, t2-t1, t3-t2, t4-t3);
		}
	}
	
	lua_pop(L, 3);

	JIVEL_STACK_CHECK_END(L);

	lua_pushboolean(L, drawn);
	return 1;
}


int jiveL_draw(lua_State *L) {
	/* stack is:
	 * 1: framework
	 * 2: surface
	 */

	lua_pushcfunction(L, jive_traceback);  /* push traceback function */

	lua_pushcfunction(L, _draw_screen);
	lua_pushvalue(L, 1);
	lua_pushvalue(L, 2);
	lua_pushboolean(L, 1);                 /* draw complete screen without updating animation or dirty regions */ 

	if (lua_pcall(L, 3, 0, 3) != 0) {
		LOG_WARN(log_ui_draw, "error in draw_screen:\n\t%s\n", lua_tostring(L, -1));
		return 0;
	}

	lua_pop(L, 1);

	return 0;
}


int jiveL_update_screen(lua_State *L) {
	JiveSurface *screen;

	/* stack is:
	 * 1: framework
	 */

	if (!update_screen) {
		return 0;
	}

	lua_pushcfunction(L, jive_traceback);  /* push traceback function */

	lua_pushcfunction(L, _draw_screen);
	lua_pushvalue(L, 1);

	lua_getfield(L, 1, "screen");
	lua_getfield(L, -1, "surface");
	lua_replace(L, -2);
	screen = *(JiveSurface **)lua_touserdata(L, -1);

	lua_pushboolean(L, 0);

	if (lua_pcall(L, 3, 1, 2) != 0) {
		LOG_WARN(log_ui_draw, "error in update_screen:\n\t%s\n", lua_tostring(L, -1));
		return 0;
	}

	/* flip screen */
	if (lua_toboolean(L, -1)) {
		jive_surface_flip(screen);
	}

	lua_pop(L, 2);

	return 0;
}


void jive_redraw(SDL_Rect *r) {
	if (jive_dirty_region.w) {
		jive_rect_union(&jive_dirty_region, r, &jive_dirty_region);
	}
	else {
		memcpy(&jive_dirty_region, r, sizeof(jive_dirty_region));
	}

	//printf("DIRTY: %d,%d %dx%d\n", jive_dirty_region.x, jive_dirty_region.y, jive_dirty_region.w, jive_dirty_region.h);
}


int jiveL_redraw(lua_State *L) {
	SDL_Rect r;

	/* stack top:
	 * -2: framework
	 * -1: rectangle or nil
	 */

	if (lua_isnil(L, -1)) {
		r.x = 0;
		r.y = 0;
		r.w = screen_w;
		r.h = screen_h;
	}
	else {
		jive_torect(L, 2, &r);
	}
	lua_pop(L, 1);

	jive_redraw(&r);

	return 0;
}


int jiveL_style_changed(lua_State *L) {

	/* stack top:
	 * 1: framework
	 */

	/* clear style cache */
	lua_pushnil(L);
	lua_setfield(L, LUA_REGISTRYINDEX, "jiveStyleCache");

	/* bump layout counter */
	next_jive_origin++;

	/* redraw screen */
	lua_pushcfunction(L, jiveL_redraw);
	lua_pushvalue(L, 1);
	lua_pushnil(L);
	lua_call(L, 2, 0);

	return 0;
}


void jive_queue_event(JiveEvent *evt) {
	SDL_Event user_event;
	user_event.type = SDL_USEREVENT;

	user_event.user.code = JIVE_USER_EVENT_EVENT;
	user_event.user.data1 = malloc(sizeof(JiveEvent));
	memcpy(user_event.user.data1, evt, sizeof(JiveEvent));

	SDL_PushEvent(&user_event);
}


int jiveL_dispatch_event(lua_State *L) {
	Uint32 r = 0;
	Uint32 t0 = 0, t1 = 0;
	clock_t c0 = 0, c1 = 0;

	/* stack is:
	 * 1: framework
	 * 2: widget
	 * 3: event
	 */

	if (perfwarn.event) {
		t0 = jive_jiffies();
		c0 = clock();
	}

	lua_pushcfunction(L, jive_traceback);  /* push traceback function */

	// call global event listeners
	if (jive_getmethod(L, 1, "_event")) {
		lua_pushvalue(L, 1); // framework
		lua_pushvalue(L, 3); // event
		lua_pushboolean(L, 1); // global listeners

		if (lua_pcall(L, 3, 1, 4) != 0) {
			LOG_WARN(log_ui_draw, "error in event function:\n\t%s\n", lua_tostring(L, -1));
			return 0;
		}

		r |= lua_tointeger(L, -1);
		lua_pop(L, 1);
	}

	/* by default send the event to the top window. fetch that top
	 * window here in case the global event handler has modified
	 * the window stack.
	 */
	if (lua_isnil(L, 2)) {
		lua_getfield(L, 1, "windowStack");
		if (lua_objlen(L, -1) == 0) {
			lua_pop(L, 1);
			return 0;
		}
		lua_rawgeti(L, -1, 1);
		lua_replace(L, 2);
	}

	// call widget event handler, unless the event is consumed
	if (!(r & JIVE_EVENT_CONSUME) && jive_getmethod(L, 2, "_event")) {
		lua_pushvalue(L, 2); // widget
		lua_pushvalue(L, 3); // event

		if (lua_pcall(L, 2, 1, 4) != 0) {
			LOG_WARN(log_ui_draw, "error in event function:\n\t%s\n", lua_tostring(L, -1));
			return 0;
		}

		r |= lua_tointeger(L, -1);
		lua_pop(L, 1);
	}

	// call unused event listeners, unless the event is consumed
	if (!(r & JIVE_EVENT_CONSUME) && jive_getmethod(L, 1, "_event")) {
		lua_pushvalue(L, 1); // framework
		lua_pushvalue(L, 3); // event
		lua_pushboolean(L, 0); // unused listeners

		if (lua_pcall(L, 3, 1, 4) != 0) {
			LOG_WARN(log_ui_draw, "error in event function:\n\t%s\n", lua_tostring(L, -1));
			return 0;
		}

		r |= lua_tointeger(L, -1);
		lua_pop(L, 1);
	}

	if (perfwarn.event) {
		t1 = jive_jiffies();
		c1 = clock();
		if (t1-t0 > perfwarn.event) {
			printf("process_event > %dms: %4dms (%dms) ", perfwarn.event, t1-t0, (int)((c1-c0) * 1000 / CLOCKS_PER_SEC));
			lua_getglobal(L, "tostring");
			lua_pushvalue(L, 2);
			lua_call(L, 1, 1);
			lua_pushcfunction(L, jiveL_event_tostring);
			lua_pushvalue(L, 3);
			lua_call(L, 1, 1);
			printf("[widget:%s event:%s]\n", lua_tostring(L, -2), lua_tostring(L, -1));
			lua_pop(L, 2);
		}
	}

	lua_pushinteger(L, r);
	return 1;
}

int jiveL_set_video_mode(lua_State *L) {
	JiveSurface *srf;
	JiveSurface **p;
	Uint16 w, h, bpp;
	bool isfull;
	const SDL_VideoInfo *video_info;

	/* stack is:
	 * 1: framework
	 * 2: w
	 * 3: h
	 * 4: bpp
	 * 5: fullscreen
	 */

	w = luaL_optinteger(L, 2, 0);
	h = luaL_optinteger(L, 3, 0);
	bpp = luaL_optinteger(L, 4, 16);
	isfull = lua_toboolean(L, 5);

	// force fullscreen if no window manager is available - this prevents sdl crashing on some hardware
	video_info = SDL_GetVideoInfo();
	if (!video_info->wm_available) {
		isfull = true;
	}

	if (w == screen_w &&
	    h == screen_h &&
	    bpp == screen_bpp &&
	    isfull == screen_isfull) {
		return 0;
	}

	/* update video mode */
	srf = jive_surface_set_video_mode(w, h, bpp, isfull);
	if (!srf) {
		LOG_ERROR(log_ui_draw, "Video mode not supported: %dx%d\n", w, h);

		SDL_Quit();
		exit(-1);
	}

	/* store new screen surface */
	lua_getfield(L, 1, "screen");
	p = (JiveSurface **)lua_newuserdata(L, sizeof(JiveSurface *));
	*p = jive_surface_ref(srf);
	luaL_getmetatable(L, "JiveSurface");
	lua_setmetatable(L, -2);

	lua_setfield(L, -2, "surface");

	lua_getfield(L, -1, "bounds");
	lua_pushvalue(L, 2); /* width */
	lua_rawseti(L, -2, 3);
	lua_pushvalue(L, 3); /* height */
	lua_rawseti(L, -2, 4);
	lua_pop(L, 2);

	screen_w = w;
	screen_h = h;
	screen_bpp = bpp;
	screen_isfull = isfull;

	next_jive_origin++;

	return 0;
}

int jiveL_get_background(lua_State *L) {
	JiveTile **p = (JiveTile **)lua_newuserdata(L, sizeof(JiveTile *));
	*p = jive_tile_ref(jive_background);
	luaL_getmetatable(L, "JiveTile");
	lua_setmetatable(L, -2);

	return 1;
}

int jiveL_set_background(lua_State *L) {
	/* stack is:
	 * 1: framework
	 * 2: background image (tile)
	 */
	if (jive_background) {
		jive_tile_free(jive_background);
	}
	if (lua_isnil(L, 2)) {
		jive_background = jive_tile_fill_color(0x000000FF);
	} else {
		jive_background = jive_tile_ref(*(JiveTile **)lua_touserdata(L, 2));
	}
	next_jive_origin++;

	return 0;
}

int jiveL_push_event(lua_State *L) {

	/* stack is:
	 * 1: framework
	 * 2: JiveEvent
	 */

	JiveEvent *evt;
	if (lua_isnil(L, 2)) {
		//nothing to do when no event is passed in
		return 0;
	}

	evt = lua_touserdata(L, 2);
	jive_queue_event(evt);

	return 0;
} 

int jiveL_event(lua_State *L) {
	int r = 0;
	int listener_type;
	int event_type;

	/* stack is:
	 * 1: framework
	 * 2: event
	 * 3: globalListeners if true, or unusedListeners
	 */

	lua_getfield(L, 2, "getType");
	lua_pushvalue(L, 2);
	lua_call(L, 1, 1);
	event_type = lua_tointeger(L, -1);
	lua_pop(L, 1);

	listener_type = lua_toboolean(L, 3);
	if (listener_type) {
		lua_getfield(L, 1, "globalListeners");
	}
	else {
		lua_getfield(L, 1, "unusedListeners");
	}
	lua_pushnil(L);
	while (r == 0 && lua_next(L, -2) != 0) {
		int mask;

		lua_rawgeti(L, -1, 1);
		mask = lua_tointeger(L, -1);

		if (event_type & mask) {
			lua_rawgeti(L, -2, 2);
			lua_pushvalue(L, 2);
			lua_call(L, 1, 1);

			r = r | lua_tointeger(L, -1);

			lua_pop(L, 1);
		}

		lua_pop(L, 2);
	}
	lua_pop(L, 1);

	lua_pushinteger(L, r);
	return 1;
}


int jiveL_get_ticks(lua_State *L) {
	lua_pushinteger(L, jive_jiffies());
	return 1;
}


int jiveL_thread_time(lua_State *L) {
	lua_pushinteger(L, (int)(clock() * 1000 / CLOCKS_PER_SEC));
	return 1;
}


static int do_dispatch_event(lua_State *L, JiveEvent *jevent) {
	int r;

	/* Send event to lua widgets */
	r = JIVE_EVENT_UNUSED;
	lua_pushcfunction(L, jiveL_dispatch_event);
	jiveL_getframework(L);
	lua_pushnil(L); // default to top window
	jive_pushevent(L, jevent);
	lua_call(L, 3, 1);
	r = lua_tointeger(L, -1);
	lua_pop(L, 1);

	return r;
}


static int process_event(lua_State *L, SDL_Event *event) {
	JiveEvent jevent;
	Uint32 now;

	memset(&jevent, 0, sizeof(JiveEvent));
	jevent.ticks = now = jive_jiffies();

	switch (event->type) {
	case SDL_QUIT:
		jiveL_quit(L);
		exit(0);
		break;

	case SDL_MOUSEBUTTONDOWN:
		/* map the mouse scroll wheel to up/down */
		if (event->button.button == SDL_BUTTON_WHEELUP) {
			jevent.type = JIVE_EVENT_SCROLL;
			--(jevent.u.scroll.rel);
			break;
		}
		else if (event->button.button == SDL_BUTTON_WHEELDOWN) {
			jevent.type = JIVE_EVENT_SCROLL;
			++(jevent.u.scroll.rel);
			break;
		}

		// Fall through

	case SDL_MOUSEBUTTONUP:
		if (event->button.button == SDL_BUTTON_LEFT) {
			if (event->button.state == SDL_PRESSED) {
				jevent.type = JIVE_EVENT_MOUSE_DOWN;
				jevent.u.mouse.x = event->button.x;
				jevent.u.mouse.y = event->button.y;
			}
			else {
				jevent.type = JIVE_EVENT_MOUSE_UP;
				jevent.u.mouse.x = event->button.x;
				jevent.u.mouse.y = event->button.y;
			}
		}

		if (event->type == SDL_MOUSEBUTTONDOWN) {
			if (mouse_state == MOUSE_STATE_NONE) {
				mouse_state = MOUSE_STATE_DOWN;
				mouse_timeout_arg = (event->button.y << 16) | event->button.x;
				mouse_timeout = now + HOLD_TIMEOUT;
				mouse_long_timeout = now + LONG_HOLD_TIMEOUT;

				mouse_origin_x = event->button.x;
				mouse_origin_y = event->button.y;
				break;
			}
		}
		else /* SDL_MOUSEBUTTONUP */ {
			if (mouse_state == MOUSE_STATE_DOWN) {
				/*
				 * MOUSE_PRESSED and MOUSE_UP events
				 */
				JiveEvent up;

				memset(&up, 0, sizeof(JiveEvent));
				up.type = JIVE_EVENT_MOUSE_PRESS;
				up.ticks = jive_jiffies();
				up.u.mouse.x = event->button.x;
				up.u.mouse.y = event->button.y;
				do_dispatch_event(L, &up);
			}

			mouse_timeout = 0;
			mouse_long_timeout = 0;
			mouse_state = MOUSE_STATE_NONE;
		}
		break;

	case SDL_MOUSEMOTION:

		/* show mouse cursor */
		if (pointer_enable && pointer_timeout == 0) {
			SDL_ShowCursor(SDL_ENABLE);
		}
		pointer_timeout = now + POINTER_TIMEOUT;

		if (event->motion.state & SDL_BUTTON(1)) {
			if ( (mouse_state == MOUSE_STATE_DOWN || mouse_state == MOUSE_STATE_SENT)) {
				jevent.type = JIVE_EVENT_MOUSE_DRAG;
				jevent.u.mouse.x = event->motion.x;
				jevent.u.mouse.y = event->motion.y;
			}
		}
		else {
			jevent.type = JIVE_EVENT_MOUSE_MOVE;
			jevent.u.mouse.x = event->motion.x;
			jevent.u.mouse.y = event->motion.y;
		}
		break;

	case SDL_KEYDOWN:
		/*
		  this emulates the scrollwheel using keypresses - remove for them moment as we want 4 way navigation

		if (event->key.keysym.mod == KMOD_NONE || event->key.keysym.mod == KMOD_NUM) {
			if (event->key.keysym.sym == SDLK_UP) {
				jevent.type = JIVE_EVENT_SCROLL;
				--(jevent.u.scroll.rel);
				break;
			}
			else if (event->key.keysym.sym == SDLK_DOWN) {
				jevent.type = JIVE_EVENT_SCROLL;
				++(jevent.u.scroll.rel);
				break;
			}
		}
		*/
		// Fall through

	case SDL_KEYUP: {
		struct jive_keymap *entry = keymap;
		
#ifdef EMULATE_IR
		if (event->key.keysym.mod & (KMOD_ALT|KMOD_MODE)) {
			struct jive_keyir *ir = irmap;

			while (ir->keysym != SDLK_UNKNOWN) {
				if (ir->keysym == event->key.keysym.sym) {
					break;
				}
				ir++;
			}
			if (ir->keysym == SDLK_UNKNOWN) {
				break;
			}

			if (event->type == SDL_KEYDOWN) {
				jevent.type = JIVE_EVENT_IR_DOWN;
				jevent.u.ir.code = ir->code;
			}
			else {
				JiveEvent irup;

				jevent.type = JIVE_EVENT_IR_PRESS;
				jevent.u.ir.code = ir->code;

				memset(&irup, 0, sizeof(JiveEvent));
				irup.type = JIVE_EVENT_IR_UP;
				irup.ticks = jive_jiffies();
				irup.u.ir.code = ir->code;
				jive_queue_event(&irup);
			}

			break;
		}
#endif

		while (entry->keysym != SDLK_UNKNOWN) {
			if (entry->keysym == event->key.keysym.sym) {
				if (event->type == SDL_KEYDOWN && (!entry->mod || entry->mod == event->key.keysym.mod)) {
					// match a key with same modifiers if present on keydown
					break;
				}
				if (event->type == SDL_KEYUP && (key_mask & entry->keycode)) {
					// match a key which is currently marked as down ignoring modifiers as they may have changed
					break;
				}
			}
			entry++;
		}

		if (entry->keysym == SDLK_UNKNOWN) {
			// handle regular character keys ('a', 't', etc..)
			if (event->type == SDL_KEYDOWN && event->key.keysym.unicode != 0) {
				jevent.type = JIVE_EVENT_CHAR_PRESS;
				if (event->key.keysym.sym == SDLK_BACKSPACE) {
					//special case for Backspace, where value set is not ascii value, instead pass backspace ascii value
					jevent.u.text.unicode = 8;
				} else {
					jevent.u.text.unicode = event->key.keysym.unicode;
				}
			}
		}

		/* handle pgup/upgn and cursors as repeatable keys */
		else if (entry->keysym == SDLK_PAGEUP || entry->keysym == SDLK_PAGEDOWN ||
				 entry->keysym == SDLK_UP || entry->keysym == SDLK_DOWN || entry->keysym == SDLK_LEFT || entry->keysym == SDLK_RIGHT) {
			if (event->type == SDL_KEYDOWN) {
				jevent.type = JIVE_EVENT_KEY_PRESS;
				jevent.ticks = jive_jiffies();
				jevent.u.key.code = entry->keycode;
			}
		}
		
		else if (event->type == SDL_KEYDOWN) {
			if (key_mask & entry->keycode) {
				// ignore key repeats
				return 0;
			}
			if (key_mask == 0) {
				key_state = KEY_STATE_NONE;
			}

			switch (key_state) {
			case KEY_STATE_NONE:
				key_state = KEY_STATE_DOWN;
				// fall through

			case KEY_STATE_DOWN: {
				key_mask |= entry->keycode;

				jevent.type = JIVE_EVENT_KEY_DOWN;
				jevent.u.key.code = entry->keycode;

				key_timeout = now + HOLD_TIMEOUT;
				break;
			 }

			case KEY_STATE_SENT:
				break;
			}
		}
		else /* SDL_KEYUP */ {
			if (! (key_mask & entry->keycode)) {
				// ignore repeated key ups
				return 0;
			}

			switch (key_state) {
			case KEY_STATE_NONE:
				break;

			case KEY_STATE_DOWN: {
				/*
				 * KEY_PRESSED and KEY_UP events
				 */
				JiveEvent keyup;

				jevent.type = JIVE_EVENT_KEY_PRESS;
				jevent.u.key.code = key_mask;

				memset(&keyup, 0, sizeof(JiveEvent));
				keyup.type = JIVE_EVENT_KEY_UP;
				keyup.ticks = jive_jiffies();
				keyup.u.key.code = entry->keycode;
				jive_queue_event(&keyup);

				key_state = KEY_STATE_SENT;
				break;
			}

			case KEY_STATE_SENT: {
				/*
				 * KEY_UP event
				 */
				jevent.type = JIVE_EVENT_KEY_UP;
				jevent.u.key.code = entry->keycode;
				break;
			}
			}

			key_timeout = 0;
			key_mask &= ~(entry->keycode);
			if (key_mask == 0) {
				key_state = KEY_STATE_NONE;
			}
		}
		break;
	}

	case SDL_USEREVENT:
		assert(event->user.code == JIVE_USER_EVENT_EVENT);

		memcpy(&jevent, event->user.data1, sizeof(JiveEvent));
		free(event->user.data1);
		break;

		/* disable for the moment as it causes continual resizing
		   if the event for a resize gets delayed as we have a stack of resize notifications which cause resize to the old size

	case SDL_VIDEORESIZE: {
		JiveSurface *srf;
		int bpp = 16;

		screen_w = event->resize.w;
		screen_h = event->resize.h;

		srf = jive_surface_set_video_mode(screen_w, screen_h, bpp, false);

		lua_getfield(L, 1, "screen");

		lua_getfield(L, -1, "bounds");
		lua_pushinteger(L, screen_w);
		lua_rawseti(L, -2, 3);
		lua_pushinteger(L, screen_h);
		lua_rawseti(L, -2, 4);
		lua_pop(L, 1);

		JiveSurface **p = (JiveSurface **)lua_newuserdata(L, sizeof(JiveSurface *));
		*p = jive_surface_ref(srf);
		luaL_getmetatable(L, "JiveSurface");
		lua_setmetatable(L, -2);

		lua_setfield(L, -2, "surface");

		lua_pop(L, 1);

		next_jive_origin++;

		jevent.type = JIVE_EVENT_WINDOW_RESIZE;
		
		mouse_state = MOUSE_STATE_NONE;
		break;

	}
	*/

	default:
		return 0;
	}

	return do_dispatch_event(L, &jevent);
}


static void process_timers(lua_State *L) {
	JiveEvent jevent;
	Uint32 now;

	memset(&jevent, 0, sizeof(JiveEvent));
	jevent.ticks = now = jive_jiffies();

	if (pointer_timeout && pointer_timeout < now) {
		SDL_ShowCursor(SDL_DISABLE);
		pointer_timeout = 0;
	}

	if (mouse_timeout && mouse_timeout < now) {
		if (mouse_state == MOUSE_STATE_DOWN) {
			jevent.type = JIVE_EVENT_MOUSE_HOLD;
			jevent.u.mouse.x = (mouse_timeout_arg >> 0) & 0xFFFF;
			jevent.u.mouse.y = (mouse_timeout_arg >> 16) & 0xFFFF;
			mouse_state = MOUSE_STATE_SENT;

			do_dispatch_event(L, &jevent);
		}
		mouse_timeout = 0;
	}

	if (mouse_long_timeout && mouse_long_timeout < now) {
		if (mouse_state == MOUSE_STATE_SENT) {
			jevent.type = JIVE_EVENT_MOUSE_HOLD;
			jevent.u.mouse.x = (mouse_timeout_arg >> 0) & 0xFFFF;
			jevent.u.mouse.y = (mouse_timeout_arg >> 16) & 0xFFFF;
			mouse_state = MOUSE_STATE_SENT;

			do_dispatch_event(L, &jevent);
		}
		mouse_long_timeout = 0;
	}

	if (key_timeout && key_timeout < now) {
		jevent.type = JIVE_EVENT_KEY_HOLD;
		jevent.u.key.code = key_mask;
		key_state = KEY_STATE_SENT;

		do_dispatch_event(L, &jevent);

		key_timeout = 0;
	}
}


int jiveL_perfwarn(lua_State *L) {
	/* stack is:
	 * 1: framework
	 * 2: table of threshold values, if no entry or 0 warnings are disabled 
	 */

	if (lua_istable(L, 2)) {
		lua_getfield(L, 2, "screen");
		perfwarn.screen = lua_tointeger(L, -1);
		lua_getfield(L, 2, "layout");
		perfwarn.layout = lua_tointeger(L, -1);
		lua_getfield(L, 2, "draw");
		perfwarn.draw = lua_tointeger(L, -1);
		lua_getfield(L, 2, "event");
		perfwarn.event = lua_tointeger(L, -1);
		lua_getfield(L, 2, "queue");
		perfwarn.queue = lua_tointeger(L, -1);
		lua_getfield(L, 2, "garbage");
		perfwarn.garbage = lua_tointeger(L, -1);
		lua_pop(L, 6);
	}
	
	return 0;
}


static void _set_const(lua_State *L, int index, const char *name, double value) {
	lua_pushstring(L, name);
	lua_pushnumber(L, value);
	lua_rawset(L, index < 0 ? index - 2 : index);
}


static const struct luaL_Reg icon_methods[] = {
	{ "getPreferredBounds", jiveL_icon_get_preferred_bounds },
	{ "setValue", jiveL_icon_set_value },
	{ "_skin", jiveL_icon_skin },
	{ "_layout", jiveL_icon_layout },
	{ "draw", jiveL_icon_draw },
	{ NULL, NULL }
};

static const struct luaL_Reg label_methods[] = {
	{ "getPreferredBounds", jiveL_label_get_preferred_bounds },
	{ "_skin", jiveL_label_skin },
	{ "_layout", jiveL_label_layout },
	{ "animate", jiveL_label_animate },
	{ "draw", jiveL_label_draw },
	{ NULL, NULL }
};

static const struct luaL_Reg group_methods[] = {
	{ "getPreferredBounds", jiveL_group_get_preferred_bounds },
	{ "_skin", jiveL_group_skin },
	{ "_layout", jiveL_group_layout },
	{ "iterate", jiveL_group_iterate },
	{ "draw", jiveL_group_draw },
	{ NULL, NULL }
};

static const struct luaL_Reg textinput_methods[] = {
	{ "getPreferredBounds", jiveL_textinput_get_preferred_bounds },
	{ "_skin", jiveL_textinput_skin },
	{ "_layout", jiveL_textinput_layout },
	{ "draw", jiveL_textinput_draw },
	{ NULL, NULL }
};

static const struct luaL_Reg menu_methods[] = {
	{ "getPreferredBounds", jiveL_menu_get_preferred_bounds },
	{ "_skin", jiveL_menu_skin },
	{ "_layout", jiveL_menu_layout },
	{ "iterate", jiveL_menu_iterate },
	{ "draw", jiveL_menu_draw },
	{ NULL, NULL }
};

static const struct luaL_Reg slider_methods[] = {
	{ "getPreferredBounds", jiveL_slider_get_preferred_bounds },
	{ "getPillBounds", jiveL_slider_get_pill_bounds },
	{ "_skin", jiveL_slider_skin },
	{ "_layout", jiveL_slider_layout },
	{ "draw", jiveL_slider_draw },
	{ NULL, NULL }
};

static const struct luaL_Reg textarea_methods[] = {
	{ "getPreferredBounds", jiveL_textarea_get_preferred_bounds },
	{ "_skin", jiveL_textarea_skin },
	{ "invalidate", jiveL_textarea_invalidate },
	{ "_layout", jiveL_textarea_layout },
	{ "draw", jiveL_textarea_draw },
	{ NULL, NULL }
};

static const struct luaL_Reg widget_methods[] = {
	{ "setBounds", jiveL_widget_set_bounds }, 
	{ "getBounds", jiveL_widget_get_bounds },
	{ "getZOrder", jiveL_widget_get_z_order },
	{ "isHidden", jiveL_widget_is_hidden },
	{ "getPreferredBounds", jiveL_widget_get_preferred_bounds },
	{ "getPadding", jiveL_widget_get_padding },
	{ "getBorder", jiveL_widget_get_border },
	{ "mouseBounds", jiveL_widget_mouse_bounds },
	{ "mouseInside", jiveL_widget_mouse_inside },
	{ "reSkin", jiveL_widget_reskin },
	{ "reLayout", jiveL_widget_relayout },
	{ "reDraw", jiveL_widget_redraw },
	{ "checkSkin", jiveL_widget_check_skin },
	{ "checkLayout", jiveL_widget_check_layout },
	{ "peerToString", jiveL_widget_peer_tostring },
	{ "stylePath", jiveL_style_path },
	{ "styleValue", jiveL_style_value },
	{ "styleInt", jiveL_style_value },
	{ "styleColor", jiveL_style_color },
	{ "styleArrayColor", jiveL_style_color },
	{ "styleImage", jiveL_style_value },
	{ "styleFont", jiveL_style_font },
	{ NULL, NULL }
};

static const struct luaL_Reg window_methods[] = {
	{ "_skin", jiveL_window_skin },
	{ "checkLayout", jiveL_window_check_layout },
	{ "iterate", jiveL_window_iterate },
	{ "draw", jiveL_window_draw },
	{ "_eventHandler", jiveL_window_event_handler },
	{ NULL, NULL }
};

static const struct luaL_Reg event_methods[] = {
	{ "new", jiveL_event_new },
	{ "getType", jiveL_event_get_type },
	{ "getTicks", jiveL_event_get_ticks },
	{ "getScroll", jiveL_event_get_scroll },
	{ "getKeycode", jiveL_event_get_keycode },
	{ "getUnicode", jiveL_event_get_unicode },
	{ "getMouse", jiveL_event_get_mouse },
	{ "getActionInternal", jiveL_event_get_action_internal },
	{ "getMotion", jiveL_event_get_motion },
	{ "getSwitch", jiveL_event_get_switch },
	{ "getIRCode", jiveL_event_get_ircode },
	{ "getGesture", jiveL_event_get_gesture },
	{ "tostring", jiveL_event_tostring },
	{ NULL, NULL }
};

static const struct luaL_Reg font_methods[] = {
	{ "load", jiveL_font_load },
	{ "free", jiveL_font_free },
	{ "width", jiveL_font_width },
	{ "capheight", jiveL_font_capheight },
	{ "height", jiveL_font_height },
	{ "ascend", jiveL_font_ascend },
	{ "offset", jiveL_font_offset },
	{ NULL, NULL }
};

static const struct luaL_Reg surface_methods[] = {
	{ "newRGB", jiveL_surface_newRGB },
	{ "newRGBA", jiveL_surface_newRGBA },
	{ "loadImage", jiveL_surface_load_image },
	{ "loadImageData", jiveL_surface_load_image_data },
	{ "drawText", jiveL_surface_draw_text },
	{ "free", jiveL_surface_free },
	{ "release", jiveL_surface_release },
	{ "saveBMP", jiveL_surface_save_bmp },
	{ "compare", jiveL_surface_cmp },
	{ "setOffset", jiveL_surface_set_offset },
	{ "setClip", jiveL_surface_set_clip_arg },
	{ "getClip", jiveL_surface_get_clip_arg },
	{ "blit", jiveL_surface_blit },
	{ "blitClip", jiveL_surface_blit_clip },
	{ "blitAlpha", jiveL_surface_blit_alpha },
	{ "getSize", jiveL_surface_get_size },
	{ "getBytes", jiveL_surface_get_bytes },
	{ "rotozoom", jiveL_surface_rotozoomSurface },
	{ "zoom", jiveL_surface_zoomSurface },
	{ "shrink", jiveL_surface_shrinkSurface },
	{ "resize", jiveL_surface_resize },
	{ "pixel", jiveL_surface_pixelColor },
	{ "hline", jiveL_surface_hlineColor },
	{ "vline", jiveL_surface_vlineColor },
	{ "rectangle", jiveL_surface_rectangleColor },
	{ "filledRectangle", jiveL_surface_boxColor },
	{ "line", jiveL_surface_lineColor },
	{ "aaline", jiveL_surface_aalineColor },
	{ "circle", jiveL_surface_circleColor },
	{ "aacircle", jiveL_surface_aacircleColor },
	{ "filledCircle", jiveL_surface_filledCircleColor },
	{ "ellipse", jiveL_surface_ellipseColor },
	{ "aaellipse", jiveL_surface_aaellipseColor },
	{ "filledEllipse", jiveL_surface_filledEllipseColor },
	{ "pie", jiveL_surface_pieColor },
	{ "filledPie", jiveL_surface_filledPieColor },
	{ "trigon", jiveL_surface_trigonColor },
	{ "aatrigon", jiveL_surface_aatrigonColor },
	{ "filledTrigon", jiveL_surface_filledTrigonColor },
	{ NULL, NULL }
};

static const struct luaL_Reg tile_methods[] = {
	{ "fillColor", jiveL_tile_fill_color },
	{ "loadImage", jiveL_tile_load_image },
	{ "loadTiles", jiveL_tile_load_tiles },
	{ "loadVTiles", jiveL_tile_load_vtiles },
	{ "loadHTiles", jiveL_tile_load_htiles },
	{ "free", jiveL_tile_free },
	{ "blit", jiveL_tile_blit },
	{ "getMinSize", jiveL_tile_min_size },
	{ NULL, NULL }
};

static const struct luaL_Reg core_methods[] = {
	{ "initSDL", jiveL_initSDL },
	{ "quit", jiveL_quit },
	{ "processEvents", jiveL_process_events },
	{ "setUpdateScreen", jiveL_set_update_screen },
	{ "draw", jiveL_draw },
	{ "updateScreen", jiveL_update_screen },
	{ "reDraw", jiveL_redraw },
	{ "pushEvent", jiveL_push_event },
	{ "dispatchEvent", jiveL_dispatch_event },
	{ "getTicks", jiveL_get_ticks },
	{ "threadTime", jiveL_thread_time },
	{ "setVideoMode", jiveL_set_video_mode },
	{ "getBackground", jiveL_get_background },
	{ "setBackground", jiveL_set_background },
	{ "styleChanged", jiveL_style_changed },
	{ "perfwarn", jiveL_perfwarn },
	{ "_event", jiveL_event },
	{ NULL, NULL }
};



static int jiveL_core_init(lua_State *L) {

	lua_getglobal(L, "jive");
	lua_getfield(L, -1, "ui");

	/* stack is:
	 * 1: jive table
	 * 2: ui table
	 */

	/* register methods */
	lua_getfield(L, 2, "Icon");
	luaL_register(L, NULL, icon_methods);
	lua_pop(L, 1);

	lua_getfield(L, 2, "Label");
	luaL_register(L, NULL, label_methods);
	lua_pop(L, 1);

	lua_getfield(L, 2, "Group");
	luaL_register(L, NULL, group_methods);
	lua_pop(L, 1);

	lua_getfield(L, 2, "Textinput");
	luaL_register(L, NULL, textinput_methods);
	lua_pop(L, 1);

	lua_getfield(L, 2, "Menu");
	luaL_register(L, NULL, menu_methods);
	lua_pop(L, 1);

	lua_getfield(L, 2, "Textarea");
	luaL_register(L, NULL, textarea_methods);
	lua_pop(L, 1);

	lua_getfield(L, 2, "Widget");
	luaL_register(L, NULL, widget_methods);
	lua_pop(L, 1);

	lua_getfield(L, 2, "Window");
	luaL_register(L, NULL, window_methods);
	lua_pop(L, 1);

	lua_getfield(L, 2, "Slider");
	luaL_register(L, NULL, slider_methods);
	lua_pop(L, 1);

	lua_getfield(L, 2, "Event");
	luaL_register(L, NULL, event_methods);
	lua_pop(L, 1);

	luaL_newmetatable(L, "JiveFont");
	lua_pushcfunction(L, jiveL_font_gc);
	lua_setfield(L, -2, "__gc");
	lua_getfield(L, 2, "Font");
	luaL_register(L, NULL, font_methods);
	lua_setfield(L, -2, "__index");
	lua_pop(L, 1);

	luaL_newmetatable(L, "JiveSurface"); 
	lua_pushcfunction(L, jiveL_surfacetile_gc);
	lua_setfield(L, -2, "__gc");
	lua_getfield(L, 2, "Surface");
	luaL_register(L, NULL, surface_methods);
	lua_setfield(L, -2, "__index");
	lua_pop(L, 1);

	luaL_newmetatable(L, "JiveTile");
	lua_pushcfunction(L, jiveL_surfacetile_gc);
	lua_setfield(L, -2, "__gc");
	lua_getfield(L, 2, "Tile");
	luaL_register(L, NULL, tile_methods);
	lua_setfield(L, -2, "__index");
	lua_pop(L, 1);

	lua_getfield(L, 2, "Framework");
	luaL_register(L, NULL, core_methods);
	lua_pop(L, 1);

	return 0;
}

static const struct luaL_Reg core_funcs[] = {
	{ "frameworkOpen", jiveL_core_init },
	{ NULL, NULL }
};

int luaopen_jive_ui_framework(lua_State *L) {
	luaL_register(L, "jive", core_funcs);
	return 1;
}

int luaopen_jive(lua_State *L) {

	// set constants in jive.ui table - needed before frameworkOpen is called
	lua_getglobal(L, "jive");
	lua_newtable(L);
	lua_setfield(L, -2, "ui");
	lua_getfield(L, -1, "ui");

	_set_const(L, -1, "FRAME_RATE", JIVE_FRAME_RATE);
	_set_const(L, -1, "XY_NIL",JIVE_XY_NIL);
	_set_const(L, -1, "WH_NIL",JIVE_WH_NIL);
	_set_const(L, -1, "WH_FILL",JIVE_WH_FILL);
	_set_const(L, -1, "ALIGN_CENTER",JIVE_ALIGN_CENTER);
	_set_const(L, -1, "ALIGN_LEFT",JIVE_ALIGN_LEFT);
	_set_const(L, -1, "ALIGN_RIGHT",JIVE_ALIGN_RIGHT);
	_set_const(L, -1, "ALIGN_TOP",JIVE_ALIGN_TOP);
	_set_const(L, -1, "ALIGN_BOTTOM",JIVE_ALIGN_BOTTOM);
	_set_const(L, -1, "ALIGN_TOP_LEFT",JIVE_ALIGN_TOP_LEFT);
	_set_const(L, -1, "ALIGN_TOP_RIGHT",JIVE_ALIGN_TOP_RIGHT);
	_set_const(L, -1, "ALIGN_BOTTOM_LEFT",JIVE_ALIGN_BOTTOM_LEFT);
	_set_const(L, -1, "ALIGN_BOTTOM_RIGHT",JIVE_ALIGN_BOTTOM_RIGHT);
	_set_const(L, -1, "LAYOUT_NORTH",JIVE_LAYOUT_NORTH);
	_set_const(L, -1, "LAYOUT_EAST",JIVE_LAYOUT_EAST);
	_set_const(L, -1, "LAYOUT_SOUTH",JIVE_LAYOUT_SOUTH);
	_set_const(L, -1, "LAYOUT_WEST",JIVE_LAYOUT_WEST);
	_set_const(L, -1, "LAYOUT_CENTER",JIVE_LAYOUT_CENTER);
	_set_const(L, -1, "LAYOUT_NONE",JIVE_LAYOUT_NONE);
	_set_const(L, -1, "LAYER_FRAME",JIVE_LAYER_FRAME);
	_set_const(L, -1, "LAYER_TITLE",JIVE_LAYER_TITLE);
	_set_const(L, -1, "LAYER_CONTENT",JIVE_LAYER_CONTENT);
	_set_const(L, -1, "LAYER_CONTENT_OFF_STAGE",JIVE_LAYER_CONTENT_OFF_STAGE);
	_set_const(L, -1, "LAYER_CONTENT_ON_STAGE",JIVE_LAYER_CONTENT_ON_STAGE);
	_set_const(L, -1, "LAYER_LOWER",JIVE_LAYER_LOWER);
	_set_const(L, -1, "LAYER_ALL",JIVE_LAYER_ALL);
	_set_const(L, -1, "EVENT_NONE",JIVE_EVENT_NONE);
	_set_const(L, -1, "EVENT_SCROLL",JIVE_EVENT_SCROLL);
	_set_const(L, -1, "EVENT_ACTION",JIVE_EVENT_ACTION);
	_set_const(L, -1, "EVENT_GESTURE",JIVE_EVENT_GESTURE);
	_set_const(L, -1, "EVENT_KEY_DOWN",JIVE_EVENT_KEY_DOWN);
	_set_const(L, -1, "EVENT_KEY_UP",JIVE_EVENT_KEY_UP);
	_set_const(L, -1, "EVENT_KEY_PRESS",JIVE_EVENT_KEY_PRESS);
	_set_const(L, -1, "EVENT_KEY_HOLD",JIVE_EVENT_KEY_HOLD);
	_set_const(L, -1, "EVENT_CHAR_PRESS",JIVE_EVENT_CHAR_PRESS);
	_set_const(L, -1, "EVENT_MOUSE_DOWN",JIVE_EVENT_MOUSE_DOWN);
	_set_const(L, -1, "EVENT_MOUSE_UP",JIVE_EVENT_MOUSE_UP);
	_set_const(L, -1, "EVENT_MOUSE_PRESS",JIVE_EVENT_MOUSE_PRESS);
	_set_const(L, -1, "EVENT_MOUSE_HOLD",JIVE_EVENT_MOUSE_HOLD);
	_set_const(L, -1, "EVENT_MOUSE_MOVE",JIVE_EVENT_MOUSE_MOVE);
	_set_const(L, -1, "EVENT_MOUSE_DRAG",JIVE_EVENT_MOUSE_DRAG);
	_set_const(L, -1, "EVENT_WINDOW_PUSH",JIVE_EVENT_WINDOW_PUSH);
	_set_const(L, -1, "EVENT_WINDOW_POP",JIVE_EVENT_WINDOW_POP);
	_set_const(L, -1, "EVENT_WINDOW_ACTIVE",JIVE_EVENT_WINDOW_ACTIVE);
	_set_const(L, -1, "EVENT_WINDOW_INACTIVE",JIVE_EVENT_WINDOW_INACTIVE);
	_set_const(L, -1, "EVENT_SHOW",JIVE_EVENT_SHOW);
	_set_const(L, -1, "EVENT_HIDE",JIVE_EVENT_HIDE);
	_set_const(L, -1, "EVENT_FOCUS_GAINED",JIVE_EVENT_FOCUS_GAINED);
	_set_const(L, -1, "EVENT_FOCUS_LOST",JIVE_EVENT_FOCUS_LOST);
	_set_const(L, -1, "EVENT_WINDOW_RESIZE",JIVE_EVENT_WINDOW_RESIZE);
	_set_const(L, -1, "EVENT_SWITCH",JIVE_EVENT_SWITCH);
	_set_const(L, -1, "EVENT_MOTION",JIVE_EVENT_MOTION);
	_set_const(L, -1, "EVENT_IR_PRESS",JIVE_EVENT_IR_PRESS);
	_set_const(L, -1, "EVENT_IR_UP",JIVE_EVENT_IR_UP);
	_set_const(L, -1, "EVENT_IR_DOWN",JIVE_EVENT_IR_DOWN);
	_set_const(L, -1, "EVENT_IR_REPEAT",JIVE_EVENT_IR_REPEAT);
	_set_const(L, -1, "EVENT_IR_HOLD",JIVE_EVENT_IR_HOLD);
	_set_const(L, -1, "EVENT_IR_ALL",JIVE_EVENT_IR_ALL);
	_set_const(L, -1, "EVENT_KEY_ALL",JIVE_EVENT_KEY_ALL);
	_set_const(L, -1, "ACTION",JIVE_ACTION);
	_set_const(L, -1, "EVENT_MOUSE_ALL",JIVE_EVENT_MOUSE_ALL);
	_set_const(L, -1, "EVENT_ALL_INPUT",JIVE_EVENT_ALL_INPUT);
	_set_const(L, -1, "EVENT_VISIBLE_ALL",JIVE_EVENT_VISIBLE_ALL);
	_set_const(L, -1, "EVENT_ALL",JIVE_EVENT_ALL);
	_set_const(L, -1, "EVENT_UNUSED",JIVE_EVENT_UNUSED);
	_set_const(L, -1, "EVENT_CONSUME",JIVE_EVENT_CONSUME);
	_set_const(L, -1, "EVENT_QUIT",JIVE_EVENT_QUIT);
	_set_const(L, -1, "GESTURE_L_R",JIVE_GESTURE_L_R);
	_set_const(L, -1, "GESTURE_R_L",JIVE_GESTURE_R_L);
	_set_const(L, -1, "KEY_NONE",JIVE_KEY_NONE);
	_set_const(L, -1, "KEY_GO",JIVE_KEY_GO);
	_set_const(L, -1, "KEY_BACK",JIVE_KEY_BACK);
	_set_const(L, -1, "KEY_UP",JIVE_KEY_UP);
	_set_const(L, -1, "KEY_DOWN",JIVE_KEY_DOWN);
	_set_const(L, -1, "KEY_LEFT",JIVE_KEY_LEFT);
	_set_const(L, -1, "KEY_RIGHT",JIVE_KEY_RIGHT);
	_set_const(L, -1, "KEY_HOME",JIVE_KEY_HOME);
	_set_const(L, -1, "KEY_PLAY",JIVE_KEY_PLAY);
	_set_const(L, -1, "KEY_ADD",JIVE_KEY_ADD);
	_set_const(L, -1, "KEY_PAUSE",JIVE_KEY_PAUSE);
	_set_const(L, -1, "KEY_STOP",JIVE_KEY_STOP);
	_set_const(L, -1, "KEY_REW",JIVE_KEY_REW);
	_set_const(L, -1, "KEY_FWD",JIVE_KEY_FWD);
	_set_const(L, -1, "KEY_REW_SCAN",JIVE_KEY_REW_SCAN);
	_set_const(L, -1, "KEY_FWD_SCAN",JIVE_KEY_FWD_SCAN);
	_set_const(L, -1, "KEY_VOLUME_UP",JIVE_KEY_VOLUME_UP);
	_set_const(L, -1, "KEY_VOLUME_DOWN",JIVE_KEY_VOLUME_DOWN);
	_set_const(L, -1, "KEY_MUTE",JIVE_KEY_MUTE);
	_set_const(L, -1, "KEY_ALARM",JIVE_KEY_ALARM);
	_set_const(L, -1, "KEY_POWER",JIVE_KEY_POWER);
	_set_const(L, -1, "KEY_PRESET_1",JIVE_KEY_PRESET_1);
	_set_const(L, -1, "KEY_PRESET_2",JIVE_KEY_PRESET_2);
	_set_const(L, -1, "KEY_PRESET_3",JIVE_KEY_PRESET_3);
	_set_const(L, -1, "KEY_PRESET_4",JIVE_KEY_PRESET_4);
	_set_const(L, -1, "KEY_PRESET_5",JIVE_KEY_PRESET_5);
	_set_const(L, -1, "KEY_PRESET_6",JIVE_KEY_PRESET_6);
	_set_const(L, -1, "KEY_PAGE_UP",JIVE_KEY_PAGE_UP);
	_set_const(L, -1, "KEY_PAGE_DOWN",JIVE_KEY_PAGE_DOWN);
	_set_const(L, -1, "KEY_PRINT",JIVE_KEY_PRINT);
	lua_pop(L, 2);

	return 0;
}
