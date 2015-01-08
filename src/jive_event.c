/*
** Copyright 2010 Logitech. All Rights Reserved.
**
** This file is licensed under BSD. Please see the LICENSE file for details.
*/


#include "common.h"
#include "jive.h"


void jive_pushevent(lua_State *L, JiveEvent *event) {
	JiveEvent *obj = lua_newuserdata(L, sizeof(JiveEvent));

	lua_getglobal(L, "jive");
	lua_getfield(L, -1, "ui");
	lua_getfield(L, -1, "Event");

	lua_setmetatable(L, -4);
	lua_pop(L, 2);

	/* copy event data */
	memcpy(obj, event, sizeof(JiveEvent));
}

int jiveL_event_new(lua_State *L) {
	
	/* stack is:
	 * 1: jive.ui.Event
	 * 2: type
	 * 3: value (optional)
	 */

	JiveEvent *event = lua_newuserdata(L, sizeof(JiveEvent));

	lua_getglobal(L, "jive");
	lua_getfield(L, -1, "ui");
	lua_getfield(L, -1, "Event");

	lua_setmetatable(L, -4);
	lua_pop(L, 2);

	/* send attributes */
	event->type = lua_tointeger(L, 2);
	event->ticks = jive_jiffies();
	if (!lua_isnil(L, 3)) {
		switch (event->type) {
		case JIVE_EVENT_SCROLL:
			event->u.scroll.rel = lua_tointeger(L, 3);
			break;
		
		case JIVE_ACTION:
			event->u.action.index = lua_tointeger(L, 3);
			break;
		
		case JIVE_EVENT_KEY_DOWN:
		case JIVE_EVENT_KEY_UP:
		case JIVE_EVENT_KEY_PRESS:
		case JIVE_EVENT_KEY_HOLD:
			event->u.key.code = lua_tointeger(L, 3);
			break;
		
		case JIVE_EVENT_CHAR_PRESS:
			event->u.text.unicode = lua_tointeger(L, 3);
			break;
		
		case JIVE_EVENT_GESTURE:
			event->u.gesture.code = lua_tointeger(L, 3);
			break;

		case JIVE_EVENT_MOUSE_DOWN:
		case JIVE_EVENT_MOUSE_UP:
		case JIVE_EVENT_MOUSE_PRESS:
		case JIVE_EVENT_MOUSE_HOLD:
		case JIVE_EVENT_MOUSE_MOVE:
		case JIVE_EVENT_MOUSE_DRAG:
			event->u.mouse.x = lua_tointeger(L, 3);
			event->u.mouse.y = lua_tointeger(L, 4);
			event->u.mouse.finger_count = luaL_optinteger(L, 5, 0);
			event->u.mouse.finger_width = luaL_optinteger(L, 6, 0);
			event->u.mouse.finger_pressure = luaL_optinteger(L, 7, 0);
			break;

		case JIVE_EVENT_IR_PRESS:
		case JIVE_EVENT_IR_HOLD:
			event->u.ir.code = lua_tointeger(L, 3);
			break;

		case JIVE_EVENT_MOTION:
			event->u.motion.x = lua_tointeger(L, 3);
			event->u.motion.y = lua_tointeger(L, 4);
			event->u.motion.z = lua_tointeger(L, 5);
			break;

		default:
			break;
		}
	}

	return 1;
}

int jiveL_event_get_type(lua_State *L) {
	JiveEvent* event = (JiveEvent*)lua_touserdata(L, 1);
	if (event == NULL) {
		luaL_error(L, "invalid Event");
	}

	lua_pushinteger(L, (lua_Integer)event->type);

	return 1;
}


int jiveL_event_get_ticks(lua_State *L) {
	JiveEvent* event = (JiveEvent*)lua_touserdata(L, 1);
	if (event == NULL) {
		luaL_error(L, "invalid Event");
	}

	lua_pushinteger(L, (lua_Integer)event->ticks);

	return 1;
}


int jiveL_event_get_scroll(lua_State *L) {
	JiveEvent* event = (JiveEvent*)lua_touserdata(L, 1);
	if (event == NULL) {
		luaL_error(L, "invalid Event");
	}

	switch (event->type) {
	case JIVE_EVENT_SCROLL:
		lua_pushinteger(L, event->u.scroll.rel);
		return 1;

	default:
		luaL_error(L, "Not a scroll event");
	}
	return 0;
}


int jiveL_event_get_keycode(lua_State *L) {
	JiveEvent* event = (JiveEvent*)lua_touserdata(L, 1);
	if (event == NULL) {
		luaL_error(L, "invalid Event");
	}

	switch (event->type) {
	case JIVE_EVENT_KEY_DOWN:
	case JIVE_EVENT_KEY_UP:
	case JIVE_EVENT_KEY_PRESS:
	case JIVE_EVENT_KEY_HOLD:
		lua_pushinteger(L, (lua_Integer)event->u.key.code);
		return 1;

	default:
		luaL_error(L, "Not a key event");
	}
	return 0;
}

int jiveL_event_get_unicode(lua_State *L) {
	JiveEvent* event = (JiveEvent*)lua_touserdata(L, 1);
	if (event == NULL) {
		luaL_error(L, "invalid Event");
	}

	switch (event->type) {
	case JIVE_EVENT_CHAR_PRESS:
		lua_pushinteger(L, event->u.text.unicode);
		return 1;

	default:
		luaL_error(L, "Not a char event");
	}
	return 0;
}


int jiveL_event_get_mouse(lua_State *L) {
	JiveEvent* event = (JiveEvent*)lua_touserdata(L, 1);
	if (event == NULL) {
		luaL_error(L, "invalid Event");
	}

	switch (event->type) {
	case JIVE_EVENT_MOUSE_DOWN:
	case JIVE_EVENT_MOUSE_UP:
	case JIVE_EVENT_MOUSE_PRESS:
	case JIVE_EVENT_MOUSE_HOLD:
	case JIVE_EVENT_MOUSE_MOVE:
	case JIVE_EVENT_MOUSE_DRAG:
		lua_pushinteger(L, event->u.mouse.x);
		lua_pushinteger(L, event->u.mouse.y);
		if (event->u.mouse.finger_count == 0) {
			return 2;
		}

		lua_pushinteger(L, event->u.mouse.finger_count);
		lua_pushinteger(L, event->u.mouse.finger_width);
		lua_pushinteger(L, event->u.mouse.finger_pressure);
		if (event->u.mouse.chiral_active) {
			lua_pushinteger(L, event->u.mouse.chiral_value);
		}
		else {
	                lua_pushnil(L);
		}
		return 6;

	default:
		luaL_error(L, "Not a mouse event");
	}
	return 0;
}

int jiveL_event_get_action_internal(lua_State *L) {
	JiveEvent* event = (JiveEvent*)lua_touserdata(L, 1);
	if (event == NULL) {
		luaL_error(L, "invalid Event");
	}

	switch (event->type) {
	case JIVE_ACTION:
		lua_pushinteger(L, event->u.action.index);
		return 1;

	default:
		luaL_error(L, "Not an action event");
	}
	return 0;
}


int jiveL_event_get_motion(lua_State *L) {
        JiveEvent* event = (JiveEvent*)lua_touserdata(L, 1);
        if (event == NULL) {
                luaL_error(L, "invalid Event");
        }

        switch (event->type) {
        case (JiveEventType) JIVE_EVENT_MOTION:
                lua_pushinteger(L, (Sint16) event->u.motion.x);
                lua_pushinteger(L, (Sint16) event->u.motion.y);
                lua_pushinteger(L, (Sint16) event->u.motion.z);
                return 3;

        default:
                luaL_error(L, "Not a motion event");
        }
        return 0;
}


int jiveL_event_get_switch(lua_State *L) {
        JiveEvent* event = (JiveEvent*)lua_touserdata(L, 1);
        if (event == NULL) {
                luaL_error(L, "invalid Event");
        }

        switch (event->type) {
        case (JiveEventType) JIVE_EVENT_SWITCH:
                lua_pushinteger(L, (Sint16) event->u.sw.code);
                lua_pushinteger(L, (Sint16) event->u.sw.value);
                return 2;

        default:
                luaL_error(L, "Not a motion event");
        }
        return 0;
}


int jiveL_event_get_ircode(lua_State *L) {
	JiveEvent* event = (JiveEvent*)lua_touserdata(L, 1);
	if (event == NULL) {
		luaL_error(L, "invalid Event");
	}

	switch (event->type) {
	case JIVE_EVENT_IR_UP:
	case JIVE_EVENT_IR_DOWN:
	case JIVE_EVENT_IR_PRESS:
	case JIVE_EVENT_IR_REPEAT:
	case JIVE_EVENT_IR_HOLD:
		lua_pushinteger(L, event->u.ir.code);
		return 1;

	default:
		luaL_error(L, "Not an IR event");
	}
	return 0;
}

int jiveL_event_get_gesture(lua_State *L) {
	JiveEvent* event = (JiveEvent*)lua_touserdata(L, 1);
	if (event == NULL) {
		luaL_error(L, "invalid Event");
	}

	switch (event->type) {
	case JIVE_EVENT_GESTURE:
		lua_pushinteger(L, event->u.gesture.code);
		return 1;

	default:
		luaL_error(L, "Not a GESTURE event");
	}
	return 0;
}


int jiveL_event_tostring(lua_State* L) {
	luaL_Buffer buf;

	JiveEvent* event = (JiveEvent*)lua_touserdata(L, 1);
	if (event == NULL) {
		luaL_error(L, "invalid Event");
	}

	luaL_buffinit(L, &buf);
	lua_pushfstring(L, "Event(ticks=%d type=", event->ticks);
	luaL_addvalue(&buf);

	switch (event->type) {
	case JIVE_EVENT_NONE:
		lua_pushstring(L, "none");
		break;
					
	case JIVE_EVENT_SCROLL:
		lua_pushfstring(L, "SCROLL rel=%d", event->u.scroll.rel);
		break;
		
	case JIVE_EVENT_ACTION:
		lua_pushfstring(L, "ACTION");
		break;

	case JIVE_EVENT_KEY_DOWN:
		lua_pushfstring(L, "KEY_DOWN code=%d", event->u.key.code);
		break;
	case JIVE_EVENT_KEY_UP:
		lua_pushfstring(L, "KEY_UP code=%d", event->u.key.code);
		break;
	case JIVE_EVENT_KEY_PRESS:
		lua_pushfstring(L, "KEY_PRESS code=%d", event->u.key.code);
		break;
	case JIVE_EVENT_KEY_HOLD:
		lua_pushfstring(L, "KEY_HOLD code=%d", event->u.key.code);
		break;

	case JIVE_EVENT_CHAR_PRESS:
		lua_pushfstring(L, "CHAR_PRESS code=%d", event->u.text.unicode);
		break;

	case JIVE_EVENT_GESTURE:
		lua_pushfstring(L, "GESTURE code=%d", event->u.gesture.code);
		break;

	case JIVE_ACTION:
	    //todo: also show actionEventName - convert index to actionEventName by calling Framework:getActionEventNameByIndex
		lua_pushfstring(L, "ACTION actionIndex=%d", event->u.action.index);
		break;

	case JIVE_EVENT_MOUSE_DOWN:
		if (event->u.mouse.finger_count) {
			lua_pushfstring(L, "FINGER_DOWN x=%d,y=%d,n=%d,w=%d,p=%d,c=%d", event->u.mouse.x, event->u.mouse.y, event->u.mouse.finger_count, event->u.mouse.finger_width, event->u.mouse.finger_pressure, event->u.mouse.chiral_value);
		}
		else {
			lua_pushfstring(L, "MOUSE_DOWN x=%d,y=%d", event->u.mouse.x, event->u.mouse.y);
		}
		break;
	case JIVE_EVENT_MOUSE_UP:
		if (event->u.mouse.finger_count) {
			lua_pushfstring(L, "FINGER_UP x=%d,y=%d,n=%d,w=%d,p=%d,c=%d", event->u.mouse.x, event->u.mouse.y, event->u.mouse.finger_count, event->u.mouse.finger_width, event->u.mouse.finger_pressure, event->u.mouse.chiral_value);
		}
		else {
			lua_pushfstring(L, "MOUSE_UP x=%d,y=%d", event->u.mouse.x, event->u.mouse.y);
		}
		break;
	case JIVE_EVENT_MOUSE_PRESS:
		if (event->u.mouse.finger_count) {
			lua_pushfstring(L, "FINGER_PRESS x=%d,y=%d,n=%d,w=%d,p=%d,c=%d", event->u.mouse.x, event->u.mouse.y, event->u.mouse.finger_count, event->u.mouse.finger_width, event->u.mouse.finger_pressure, event->u.mouse.chiral_value);
		}
		else {
			lua_pushfstring(L, "MOUSE_PRESS x=%d,y=%d", event->u.mouse.x, event->u.mouse.y);
		}
		break;
	case JIVE_EVENT_MOUSE_HOLD:
		if (event->u.mouse.finger_count) {
			lua_pushfstring(L, "FINGER_HOLD x=%d,y=%d,n=%d,w=%d,p=%d,c=%d", event->u.mouse.x, event->u.mouse.y, event->u.mouse.finger_count, event->u.mouse.finger_width, event->u.mouse.finger_pressure, event->u.mouse.chiral_value);
		}
		else {
			lua_pushfstring(L, "MOUSE_HOLD x=%d,y=%d", event->u.mouse.x, event->u.mouse.y);
		}
		break;
	case JIVE_EVENT_MOUSE_MOVE:
		if (event->u.mouse.finger_count) {
			lua_pushfstring(L, "FINGER_MOVE x=%d,y=%d,n=%d,w=%d,p=%d,c=%d", event->u.mouse.x, event->u.mouse.y, event->u.mouse.finger_count, event->u.mouse.finger_width, event->u.mouse.finger_pressure, event->u.mouse.chiral_value);
		}
		else {
			lua_pushfstring(L, "MOUSE_MOVE x=%d,y=%d", event->u.mouse.x, event->u.mouse.y);
		}
		break;
	case JIVE_EVENT_MOUSE_DRAG:
		if (event->u.mouse.finger_count) {
			lua_pushfstring(L, "FINGER_DRAG x=%d,y=%d,n=%d,w=%d,p=%d,c=%d", event->u.mouse.x, event->u.mouse.y, event->u.mouse.finger_count, event->u.mouse.finger_width, event->u.mouse.finger_pressure, event->u.mouse.chiral_value);
		}
		else {
			lua_pushfstring(L, "MOUSE_DRAG x=%d,y=%d", event->u.mouse.x, event->u.mouse.y);
		}
		break;

	case JIVE_EVENT_MOTION:
		lua_pushfstring(L, "MOTION x=%d,y=%d,z=%d", event->u.motion.x, event->u.motion.y, event->u.motion.z);
		break;
	case JIVE_EVENT_SWITCH:
		lua_pushfstring(L, "SWITCH code=%d,value=%d", event->u.sw.code, event->u.sw.value);
		break;

	case JIVE_EVENT_IR_DOWN:
		lua_pushfstring(L, "IR_DOWN code=%p", event->u.ir.code);
		break;
	case JIVE_EVENT_IR_UP:
		lua_pushfstring(L, "IR_UP code=%p", event->u.ir.code);
		break;
	case JIVE_EVENT_IR_REPEAT:
		lua_pushfstring(L, "IR_REPEAT code=%p", event->u.ir.code);
		break;
	case JIVE_EVENT_IR_PRESS:
		lua_pushfstring(L, "IR_PRESS code=%p", event->u.ir.code);
		break;
	case JIVE_EVENT_IR_HOLD:
		lua_pushfstring(L, "IR_HOLD code=%p", event->u.ir.code);
		break;
    
	case JIVE_EVENT_WINDOW_PUSH:
		lua_pushstring(L, "WINDOW_PUSH");
		break;
	case JIVE_EVENT_WINDOW_POP:
		lua_pushstring(L, "WINDOW_POP");
		break;
	case JIVE_EVENT_WINDOW_ACTIVE:
		lua_pushstring(L, "WINDOW_ACTIVE");
		break;
	case JIVE_EVENT_WINDOW_INACTIVE:
		lua_pushstring(L, "WINDOW_INACTIVE");
		break;
		
	case JIVE_EVENT_SHOW:
		lua_pushstring(L, "SHOW");
		break;
	case JIVE_EVENT_HIDE:
		lua_pushstring(L, "HIDE");
		break;
	case JIVE_EVENT_FOCUS_GAINED:
		lua_pushstring(L, "FOCUS_GAINED");
		break;
	case JIVE_EVENT_FOCUS_LOST:
		lua_pushstring(L, "FOCUS_LOST");
		break;
		
	default:
		break;
	}
	luaL_addvalue(&buf);
	
	luaL_addstring(&buf, ")");
	luaL_pushresult(&buf);

	return 1;
}

