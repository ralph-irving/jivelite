/*
** Copyright 2010 Logitech. All Rights Reserved.
**
** This file is licensed under BSD. Please see the LICENSE file for details.
*/

#ifndef JIVE_COMMON_H
#define JIVE_COMMON_H

#define HAVE_SOCKETPAIR    1
#define HAVE_SYSLOG        1

#if defined(linux) || defined(__sun)
#define HAVE_CLOCK_GETTIME 1
#endif

#include <assert.h>
#include <errno.h>
#include <math.h>
#include <signal.h>
#include <stdio.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#ifndef WIN32
#include <libgen.h>
#include <pthread.h>
#include <sys/time.h>
#include <sys/shm.h>
#include <sys/socket.h>
#include <sys/utsname.h>
#include <unistd.h>
#include <netdb.h>
#include <arpa/inet.h>
#endif


#ifndef PATH_MAX
/* Default POSIX maximum path length */
#define PATH_MAX 256
#endif


#if defined(WIN32)
#define DIR_SEPARATOR_CHAR	'\\'
#define DIR_SEPARATOR_STR	"\\"
#define PATH_SEPARATOR_CHAR	';'
#define PATH_SEPARATOR_STR	";"
#define LIBRARY_EXT		"dll"
#define mkdir(path,mode) _mkdir (path)
typedef _W64 int   ssize_t;
#endif /* WIN32 */

#ifndef DIR_SEPARATOR_CHAR
#define DIR_SEPARATOR_CHAR	'/'
#define DIR_SEPARATOR_STR	"/"
#define PATH_SEPARATOR_CHAR	':'
#define PATH_SEPARATOR_STR	":"
#define LIBRARY_EXT		"so"
#endif /* !DIR_SEPARATOR_CHAR */

#include <SDL.h>

#include "lua.h"
#include "lauxlib.h"

#include "log.h"
#include "types.h"

/* utilities */
extern int jive_find_file(const char *path, char *fullpath);

/* watchdog */
int watchdog_get();
int watchdog_keepalive(int watchdog_id, int count);

/* system */
const char * system_get_machine(void);
const char * system_get_arch(void);
const char * system_get_version(void);
const char * system_get_uuid_char(void);

/* monotonic application time in milliseconds */
bool jive_time_init(void);
void jive_time_quit(void);
u64_t jive_jiffies(void);


#if WITH_DMALLOC
#include <dmalloc.h>
#endif

#if defined(_MSC_VER)
#define inline __inline
#endif //defined(_MSC_VER)

#endif // JIVE_COMMON_H
