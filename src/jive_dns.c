/*
** Copyright 2010 Logitech. All Rights Reserved.
**
**
** This file is licensed under BSD. Please see the LICENSE file for details.
*/

#include "common.h"

#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>

typedef SOCKET socket_t;
#define CLOSESOCKET(s) closesocket(s)

#else
#include <sys/stat.h>
#include <resolv.h>

typedef int socket_t;
#define CLOSESOCKET(s) close(s)

#endif

/* fm - 01/12/2010
Userland DNS resolve requests are queued into a pipe in jiveL_dns_write(), then
dns_resolver_thread() reads the pipe and calls gethostbyaddr() or gethostbyname().
Both of these functions are blocking and can take a couple of seconds to return,
especially if the network is down.
To allow the pipe to empty if a lot of DNS requests are issued while the network
is down a 'shortcut' is taken as long as the following timeout is active. The
shortcut path doesn't call the blocking functions but just reads from the pipe
and returns the last error code again.
The timeout was set to 2 minutes which I found in my tests on Jive, Baby and
Touch not to be necessary to make sure the pipe gets emptied. 10 seconds seem
to be enough.
The 10 seconds timeout also makes reconnecting a lot quicker when the network is
re-established. 
*/
#define RESOLV_TIMEOUT (10 * 1000) /* 10 seconds (was 2 minutes) */


/*
 * Some systems do not provide this so that we provide our own. It's not
 * marvelously fast, but it works just fine.
 * (from luasocket)
 */
#ifndef HAVE_INET_ATON
int inet_aton(const char *cp, struct in_addr *inp)
{
    unsigned int a = 0, b = 0, c = 0, d = 0;
    int n = 0, r;
    unsigned long int addr = 0;
    r = sscanf(cp, "%u.%u.%u.%u%n", &a, &b, &c, &d, &n);
    if (r == 0 || n == 0) return 0;
    cp += n;
    if (*cp) return 0;
    if (a > 255 || b > 255 || c > 255 || d > 255) return 0;
    if (inp) {
        addr += a; addr <<= 8;
        addr += b; addr <<= 8;
        addr += c; addr <<= 8;
        addr += d;
        inp->s_addr = htonl(addr);
    }
    return 1;
}
#endif


#if defined(WIN32) || !defined(HAVE_SOCKETPAIR)

/* socketpair.c
 * Copyright 2007 by Nathan C. Myers <ncm@cantrip.org>; all rights reserved.
 * This code is Free Software.  It may be copied freely, in original or 
 * modified form, subject only to the restrictions that (1) the author is
 * relieved from all responsibilities for any use for any purpose, and (2)
 * this copyright notice must be retained, unchanged, in its entirety.  If
 * for any reason the author might be held responsible for any consequences
 * of copying or use, license is withheld.  
 */

int socketpair(int domain, int type, int protocol, SOCKET socks[2])
{
    struct sockaddr_in addr;
    SOCKET listener;
    int e;
    int addrlen = sizeof(addr);
    DWORD flags = WSA_FLAG_OVERLAPPED;

    if (socks == 0) {
      WSASetLastError(WSAEINVAL);
      return SOCKET_ERROR;
    }

    socks[0] = socks[1] = INVALID_SOCKET;
    if ((listener = socket(AF_INET, SOCK_STREAM, 0)) == INVALID_SOCKET) 
        return SOCKET_ERROR;

    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(0x7f000001);
    addr.sin_port = 0;

    e = bind(listener, (const struct sockaddr*) &addr, sizeof(addr));
    if (e == SOCKET_ERROR) {
        e = WSAGetLastError();
    	closesocket(listener);
        WSASetLastError(e);
        return SOCKET_ERROR;
    }
    e = getsockname(listener, (struct sockaddr*) &addr, &addrlen);
    if (e == SOCKET_ERROR) {
        e = WSAGetLastError();
    	closesocket(listener);
        WSASetLastError(e);
        return SOCKET_ERROR;
    }

    do {
        if (listen(listener, 1) == SOCKET_ERROR)                      break;
        if ((socks[0] = WSASocket(AF_INET, SOCK_STREAM, 0, NULL, 0, flags))
                == INVALID_SOCKET)                                    break;
        if (connect(socks[0], (const struct sockaddr*) &addr,
                    sizeof(addr)) == SOCKET_ERROR)                    break;
        if ((socks[1] = accept(listener, NULL, NULL))
                == INVALID_SOCKET)                                    break;
        closesocket(listener);
        return 0;
    } while (0);
    e = WSAGetLastError();
    closesocket(listener);
    closesocket(socks[0]);
    closesocket(socks[1]);
    WSASetLastError(e);
    return SOCKET_ERROR;
}
#endif


/* write a string to the pipe fd */
static void write_str(socket_t fd, char *str) {
	size_t len;

	len = strlen(str);
	send(fd, &len, sizeof(len), 0);
	send(fd, str, len, 0);
}


/* read a string to the lua stack from the pipe fd */
static void read_pushstring(lua_State *L, socket_t fd) {
	size_t len;
	char *buf;

	recv(fd, &len, sizeof(len), 0);

	if (len == 0) {
		lua_pushnil(L);
	}
	else {
		buf = malloc(len);
		if ( buf == NULL )
			lua_pushnil(L);
		else {
			recv(fd, buf, len, 0);
			lua_pushlstring(L, buf, len);

			free(buf);
		}
	}
}


static int stat_resolv_conf(void) {
#ifndef _WIN32
	struct stat stat_buf;
	static time_t last_mtime = 0;

	/* check if resolv.conf has changed */
	if (stat("/etc/resolv.conf", &stat_buf) == 0) {
		if (last_mtime != stat_buf.st_mtime) {
			last_mtime = stat_buf.st_mtime;
			return 1;
		}
	}
#endif

	return 0;
}


/* dns resolver thread */
static int dns_resolver_thread(void *p) {
	socket_t fd = (long) p;
	struct hostent *hostent;
	struct in_addr **addr, byaddr;
	char **alias;
	size_t len;
	char *buf;
	char *failed_error = NULL;
	Uint32 failed_timeout = 0;

	while (1) {
		if (recv(fd, &len, sizeof(len), 0) < 0) {
			/* broken pipe */
			return 0;
		}

		buf = malloc(len + 1);
		if ( buf == NULL )
			return 0;

		if (recv(fd, buf, len, 0) < 0) {
			/* broken pipe */
			free(buf);
			return 0;
		}
		buf[len] = '\0';
		if (failed_error && stat_resolv_conf()) {
			#ifndef _WIN32
			//reload resolv.conf
			res_init();
			#endif
		}
		else if (failed_error && !stat_resolv_conf()) {
			Uint32 now = jive_jiffies();
			
			if (now - failed_timeout < RESOLV_TIMEOUT) {
				write_str(fd, failed_error);
				free(buf);
				continue;
			}
		}
		failed_error = NULL;

		if (inet_aton(buf, &byaddr)) {
			hostent = gethostbyaddr((char *) &byaddr, sizeof(addr), AF_INET);
		}
		else {
			hostent = gethostbyname(buf);
		}
		free(buf);

		if (hostent == NULL) {
			/* error */
			switch (h_errno) {
			case HOST_NOT_FOUND:
				write_str(fd, "Not found");
				break;
			case NO_DATA:
				write_str(fd, "No data");
				break;
			case NO_RECOVERY:
				failed_error = "No recovery";
				failed_timeout = jive_jiffies();
				write_str(fd, failed_error);
				break;
			case TRY_AGAIN:
				failed_error = "Try again"; 
				failed_timeout = jive_jiffies();
				write_str(fd, failed_error);
				break;
			}
		}
		else {
			write_str(fd, ""); // no error
			write_str(fd, hostent->h_name);

			alias = hostent->h_aliases;
			while (*alias) {
				write_str(fd, *alias);
				alias++;
			}
			write_str(fd, ""); // end of aliases

			addr = (struct in_addr **) hostent->h_addr_list;
			while (*addr) {
				write_str(fd, inet_ntoa(**addr));
				addr++;
			}
			write_str(fd, ""); // end if addrs
		}
	}
}


struct dns_userdata {
	socket_t fd[2];
	SDL_Thread *t;
};


static int jiveL_dns_open(lua_State *L) {
	struct dns_userdata *u;
	int r;

	u = lua_newuserdata(L, sizeof(struct dns_userdata));

	r = socketpair(AF_UNIX, SOCK_STREAM, 0, u->fd);
	if (r < 0) {
		return luaL_error(L, "socketpair failed: %s", strerror(r));
	}

	u->t = SDL_CreateThread(dns_resolver_thread, (void *)(long)(u->fd[1]));

	luaL_getmetatable(L, "jive.dns");
	lua_setmetatable(L, -2);

	return 1;
}


static int jiveL_dns_gc(lua_State *L) {
	struct dns_userdata *u;

	u = lua_touserdata(L, 1);
	CLOSESOCKET(u->fd[0]);
	CLOSESOCKET(u->fd[1]);

	return 0;
}


static int jiveL_dns_getfd(lua_State *L) {
	struct dns_userdata *u;

	u = lua_touserdata(L, 1);
	lua_pushinteger(L, u->fd[0]);

	return 1;
}


static int jiveL_dns_read(lua_State *L) {
	struct dns_userdata *u;
	int i, resolved;

	u = lua_touserdata(L, 1);

	/* error? */
	read_pushstring(L, u->fd[0]);
	if (!lua_isnil(L, -1)) {
		lua_pushnil(L);
		lua_insert(L, -2);
		return 2;
	}

	/* read hostent table */
	lua_newtable(L);
	resolved = lua_gettop(L);

	lua_pushstring(L, "name");
	read_pushstring(L, u->fd[0]);
	lua_settable(L, resolved);

	i = 1;
	lua_newtable(L);
	read_pushstring(L, u->fd[0]);
	while (!lua_isnil(L, -1)) {
		lua_rawseti(L, -2, i++);
		read_pushstring(L, u->fd[0]);
	}
	lua_pop(L, 1);
	lua_setfield(L, resolved, "alias");

	i = 1;
	lua_newtable(L);
	read_pushstring(L, u->fd[0]);
	while (!lua_isnil(L, -1)) {
		lua_rawseti(L, -2, i++);
		read_pushstring(L, u->fd[0]);
	}
	lua_pop(L, 1);
	lua_setfield(L, resolved, "ip");

	return 1;
}


static int jiveL_dns_write(lua_State *L) {
	struct dns_userdata *u;
	const char *buf;
	size_t len;

	u = lua_touserdata(L, 1);
	buf = lua_tolstring(L, 2, &len);

	send(u->fd[0], &len, sizeof(len), 0);
	send(u->fd[0], buf, len, 0);

	return 0;
}


static const struct luaL_Reg dns_lib[] = {
	{ "open", jiveL_dns_open },
	{ NULL, NULL }
};


int luaopen_jive_net_dns(lua_State *L) {
	luaL_newmetatable(L, "jive.dns");

	lua_pushcfunction(L, jiveL_dns_gc);
	lua_setfield(L, -2, "__gc");

	lua_pushcfunction(L, jiveL_dns_read);
	lua_setfield(L, -2, "read");

	lua_pushcfunction(L, jiveL_dns_write);
	lua_setfield(L, -2, "write");

	lua_pushcfunction(L, jiveL_dns_getfd);
	lua_setfield(L, -2, "getfd");

	lua_pushvalue(L, -1);
	lua_setfield(L, -2, "__index");

	luaL_register(L, "jive.dns", dns_lib);

	return 0;
}
