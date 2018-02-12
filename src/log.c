/*
** Copyright 2010 Logitech. All Rights Reserved.
**
** This file is licensed under BSD. Please see the LICENSE file for details.
*/

#include "common.h"
#include <time.h>
#ifdef HAVE_SYSLOG
#include <syslog.h>
#endif

#if defined(WIN32)
#include <winsock2.h>
#define strcasecmp stricmp
#endif

#define LOG_BUFFER_SIZE 512

static enum log_priority appender_stdout = LOG_PRIORITY_DEBUG;
static enum log_priority appender_syslog = LOG_PRIORITY_OFF;

static struct log_category *category_head = NULL;

#if defined(WIN32)

#if defined(_MSC_VER) || defined(_MSC_EXTENSIONS)
  #define DELTA_EPOCH_IN_MICROSECS  11644473600000000Ui64
#else
  #define DELTA_EPOCH_IN_MICROSECS  11644473600000000ULL
#endif

struct tm *gmtime_r (const time_t *, struct tm *);

struct tm *
gmtime_r (const time_t *timer, struct tm *result)
{
   struct tm *local_result;
   local_result = gmtime (timer);

   if (local_result == NULL || result == NULL)
     return NULL;

   memcpy (result, local_result, sizeof (result));
   return result;
} 

struct timezone 
{
  int  tz_minuteswest; /* minutes W of Greenwich */
  int  tz_dsttime;     /* type of dst correction */
};
 
int gettimeofday(struct timeval *tv, struct timezone *tz)
{
  FILETIME ft;
  unsigned __int64 tmpres = 0;
  static int tzflag;
 
  if (NULL != tv)
  {
    GetSystemTimeAsFileTime(&ft);
 
    tmpres |= ft.dwHighDateTime;
    tmpres <<= 32;
    tmpres |= ft.dwLowDateTime;
 
    /*converting file time to unix epoch*/
    tmpres /= 10;  /*convert into microseconds*/
    tmpres -= DELTA_EPOCH_IN_MICROSECS; 
    tv->tv_sec = (long)(tmpres / 1000000UL);
    tv->tv_usec = (long)(tmpres % 1000000UL);
  }
 
  if (NULL != tz)
  {
    if (!tzflag)
    {
      _tzset();
      tzflag++;
    }
    tz->tz_minuteswest = _timezone / 60;
    tz->tz_dsttime = _daylight;
  }
 
  return 0;
}
#endif

void log_init() {
#ifdef HAVE_SYSLOG
	openlog("jivelite", LOG_ODELAY | LOG_CONS, LOG_USER);
#endif
}


void log_free() {
	struct log_category *next, *ptr = category_head;

#ifdef HAVE_SYSLOG
	closelog();
#endif

	while (ptr) {
		next = ptr->next;
		free(ptr);
		ptr = next;
	}
}


struct log_category *log_category_get(const char *name) {
	struct log_category *ptr = category_head;

	/* existing category? */
	while (ptr) {
		if (strcmp(ptr->name, name) == 0) {
			return ptr;
		}

		ptr = ptr->next;
	}

	/* create category */
	ptr = malloc(sizeof(struct log_category) + strlen(name) + 1);
	ptr->priority = LOG_PRIORITY_OFF;
	strcpy(ptr->name, name);

	ptr->next = category_head;
	category_head = ptr;

	return ptr;
}


void log_category_vlog(struct log_category *category, enum log_priority priority, const char *format, va_list args) {
	struct timeval t;
	struct tm tm;

	char *buf = alloca(LOG_BUFFER_SIZE);
	vsnprintf(buf, LOG_BUFFER_SIZE, format, args);

	if (appender_stdout >= priority) {
		char *color;

		gettimeofday(&t, NULL);
		gmtime_r(&t.tv_sec, &tm);

		switch (priority) {
		case LOG_PRIORITY_ERROR:
			color = "\033[0;31m";
			break;
		case LOG_PRIORITY_WARN:
			color = "\033[0;32m";
			break;
		case LOG_PRIORITY_INFO:
			color = "\033[0;33m";
			break;
		default:
		case LOG_PRIORITY_DEBUG:
			color = "\033[0;34m";
		}

#if defined(WIN32)
		printf("%02d.%03ld %-6s %s - %s\n",
		       t.tv_sec,
		       (long)(t.tv_usec / 1000),
		       log_priority_to_string(priority), category->name, buf);
#else
		printf("%s%04d%02d%02d %02d:%02d:%02d.%03ld %-6s %s - %s\033[0m\n",
		       color,
		       tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday,
		       tm.tm_hour, tm.tm_min, tm.tm_sec,
		       (long)(t.tv_usec / 1000),
		       log_priority_to_string(priority), category->name, buf);

#endif
	}

#ifdef HAVE_SYSLOG
	if (appender_syslog >= priority) {
		char *ptr, *lasts = NULL;

		/* log individual lines to syslog */
		ptr = strtok_r(buf, "\n", &lasts);
		syslog(priority, "%-6s %s - %s", log_priority_to_string(priority), category->name, ptr);

		ptr = strtok_r(NULL, "\n", &lasts);
		while (ptr) {
			syslog(priority, "%s", ptr);
			ptr = strtok_r(NULL, "\n", &lasts);
		}
	}
#endif

	return;
}


const char *log_category_get_name(struct log_category *category) {
	return category->name;
}


enum log_priority log_category_get_priority(struct log_category *category) {
	return category->priority;
}


void log_category_set_priority(struct log_category *category, enum log_priority priority) {
	category->priority = priority;
}


const char *log_priority_to_string(enum log_priority priority) {
	switch (priority) {
	case LOG_PRIORITY_OFF:
		return "OFF";
	case LOG_PRIORITY_ERROR:
		return "ERROR";
	case LOG_PRIORITY_WARN:
		return "WARN";
	case LOG_PRIORITY_INFO:
		return "INFO";
	case LOG_PRIORITY_DEBUG:
		return "DEBUG";
	}
	return NULL;
}


enum log_priority log_priority_to_int(const char *str) {
	if (!str) {
		return LOG_PRIORITY_OFF;
	}
	if (strcasecmp(str, "debug") == 0) {
		return LOG_PRIORITY_DEBUG;
	}
	else if(strcasecmp(str, "info") == 0) {
		return LOG_PRIORITY_INFO;
	}
	else if(strcasecmp(str, "warn") == 0) {
		return LOG_PRIORITY_WARN;
	}
	else if(strcasecmp(str, "error") == 0) {
		return LOG_PRIORITY_ERROR;
	}
	else {
		return LOG_PRIORITY_OFF;
	}
}


static int do_log(lua_State *L, enum log_priority priority, bool_t stacktrace) {
	LOG_CATEGORY *category;
	luaL_Buffer buf;
	lua_Debug ar;
	char *src;
	int i, argc;

	/* stack is:
	 * 1: log category
	 * 2: message...
	 */

	category = lua_touserdata(L, 1);
	if (!category) {
		return 0;
	};

	if (log_category_get_priority(category) < priority) {
		return 0;
	}

	argc = lua_gettop(L);

	/* calling function */
	lua_getstack(L, 1, &ar);
	lua_getinfo(L, "Sl", &ar);

	src = ar.short_src + strlen(ar.short_src);
	while (src-- > ar.short_src) {
		if (*src == '/') {
			src++;
			break;
		}
	}

	luaL_buffinit(L, &buf);

	/* log arguments */
	for (i=2; i<=argc; i++) {
		lua_getglobal(L, "tostring");
		lua_pushvalue(L, i);
		lua_call(L, 1, 1);

		luaL_addvalue(&buf);
	}

	luaL_pushresult(&buf);

	/* optional stack trace */
	if (stacktrace) {
		lua_getglobal(L, "debug");
		lua_getfield(L, -1, "traceback");
		lua_pushvalue(L, -3);
		lua_pushinteger(L, 2);
		lua_call(L, 2, 1);
	}

	log_category_log(category, priority, "%s:%d %s", src, ar.currentline, lua_tostring(L, -1));

	return 0;
}


static int log_debug(lua_State *L) {
	return do_log(L, LOG_PRIORITY_DEBUG, false);
}

static int log_info(lua_State *L) {
	return do_log(L, LOG_PRIORITY_INFO, false);
}

static int log_warn(lua_State *L) {
	return do_log(L, LOG_PRIORITY_WARN, false);
}

static int log_error(lua_State *L) {
	return do_log(L, LOG_PRIORITY_ERROR, true);
}


static int is_log(lua_State *L, enum log_priority priority) {
	LOG_CATEGORY *category;

	/* stack is:
	 * 1: log category
	 */

	category = lua_touserdata(L, 1);
	if (!category) {
		return 0;
	};

	lua_pushboolean(L, (log_category_get_priority(category) >= priority));
	return 1;
}


static int log_is_debug(lua_State *L) {
	return is_log(L, LOG_PRIORITY_DEBUG);
}

static int log_is_info(lua_State *L) {
	return is_log(L, LOG_PRIORITY_INFO);
}

static int log_is_warn(lua_State *L) {
	return is_log(L, LOG_PRIORITY_WARN);
}

static int log_is_error(lua_State *L) {
	return is_log(L, LOG_PRIORITY_ERROR);
}

static int log_get_level(lua_State *L) {
	LOG_CATEGORY *category;

	/* stack is:
	 * 1: log category
	 */

	category = lua_touserdata(L, 1);
	if (!category) {
		return 0;
	};

	lua_pushstring(L, log_priority_to_string(log_category_get_priority(category)));
	return 1;
}


static int log_set_level(lua_State *L) {
	LOG_CATEGORY *category;

	/* stack is:
	 * 1: log category
	 * 2: level
	 */

	category = lua_touserdata(L, 1);
	if (!category) {
		return 0;
	};

	log_category_set_priority(category, log_priority_to_int(lua_tostring(L, 2)));
	return 0;
}


static int log_logger(lua_State *L) {
	struct log_category *category;

	/* stack is:
	 * 1: log class
	 * 2: logger name
	 */

	category = log_category_get(lua_tostring(L, 2));

	lua_pushlightuserdata(L, category);

	luaL_getmetatable(L, "jivelite.log.obj");
	lua_setmetatable(L, -2);

	return 1;
}


static int log_categories(lua_State *L) {
	struct log_category *ptr = category_head;

	lua_newtable(L);

	while (ptr) {
		lua_pushlightuserdata(L, ptr);
		lua_setfield(L, -2, log_category_get_name(ptr));

		ptr = ptr->next;
	}

	return 1;
}


static const struct luaL_Reg log_m[] = {
	{ "debug", log_debug },
	{ "info", log_info },
	{ "warn", log_warn },
	{ "error", log_error },
	{ "isDebug", log_is_debug },
	{ "isInfo", log_is_info },
	{ "isWarn", log_is_warn },
	{ "isError", log_is_error },
	{ "getLevel", log_get_level },
	{ "setLevel", log_set_level },
	{ NULL, NULL }
};


static const struct luaL_Reg log_f[] = {
	{ "logger", log_logger },
	{ "categories", log_categories },
	{ NULL, NULL }
};


int luaopen_log(lua_State *L) {
	/* methods */
	luaL_newmetatable(L, "jivelite.log.obj");

	lua_pushvalue(L, -1);
	lua_setfield(L, -2, "__index");

	luaL_register(L, NULL, log_m);

	/* class */
	luaL_register(L, "jivelite.log", log_f);

	return 0;
}


int jive_log_init(lua_State *L) {
	char *log_path;

	/* configure logging */
	log_path = alloca(PATH_MAX);
	if (!jive_find_file("logconf.lua", log_path)) {
		return 0;
	}

	/* load environment */
	if (luaL_loadfile(L, log_path) != 0) {
		fprintf(stderr, "error loading logconf: %s\n", lua_tostring(L, -1));
		return 0;
	}

	/* sandbox and evaluate environment */
	lua_newtable(L);
	lua_setfenv(L, -2);
	if (lua_pcall(L, 0, 1, 0) != 0) {
		fprintf(stderr, "error in logconf: %s\n", lua_tostring(L, -1));
		return 0;
	}

	/* configure appenders */
	lua_getfield(L, -1, "appender");
	if (!lua_isnil(L, -1)) {
		lua_pushnil(L);
		while (lua_next(L, -2) != 0) {
			if (strcmp(lua_tostring(L, -2), "stdout") == 0) {
				appender_stdout = log_priority_to_int(lua_tostring(L, -1));
			}
			if (strcmp(lua_tostring(L, -2), "syslog") == 0) {
				appender_syslog = log_priority_to_int(lua_tostring(L, -1));
			}

			lua_pop(L, 1);
		}
	}
	lua_pop(L, 1);

	/* configure categories */
	lua_getfield(L, -1, "category");
	if (!lua_isnil(L, -1)) {
		lua_pushnil(L);
		while (lua_next(L, -2) != 0) {
			struct log_category *category;

			category = log_category_get(lua_tostring(L, -2));
			log_category_set_priority(category, log_priority_to_int(lua_tostring(L, -1)));

			lua_pop(L, 1);
		}
	}
	lua_pop(L, 1);

	log_init();

	return 0;
}
