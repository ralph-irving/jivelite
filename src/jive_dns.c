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
#define INVALID_SOCKET_FD INVALID_SOCKET
#define SHUTDOWNSOCKET(s) shutdown((s), SD_BOTH)
#define SOCKET_SEND_FLAGS 0

#else
#include <fcntl.h>
#include <sys/stat.h>
#include <resolv.h>

typedef int socket_t;
#define CLOSESOCKET(s) close(s)
#define INVALID_SOCKET_FD (-1)
#define SHUTDOWNSOCKET(s) shutdown((s), SHUT_RDWR)
#ifndef MSG_NOSIGNAL
#define MSG_NOSIGNAL 0
#endif
#define SOCKET_SEND_FLAGS MSG_NOSIGNAL

#endif

struct dns_userdata {
	socket_t fd[2];
	SDL_Thread *t;
	SDL_mutex *mutex;
	bool stopping;
};


static bool dns_is_stopping(struct dns_userdata *u) {
	bool stopping;

	if (SDL_LockMutex(u->mutex) != 0) {
		return true;
	}
	stopping = u->stopping;
	SDL_UnlockMutex(u->mutex);

	return stopping;
}


static void dns_request_stop(struct dns_userdata *u) {
	if (SDL_LockMutex(u->mutex) != 0) {
		return;
	}
	u->stopping = true;
	SDL_UnlockMutex(u->mutex);
}

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


static bool socket_send_all(socket_t fd, const void *buf, size_t len) {
	const char *p = buf;

	while (len > 0) {
		ssize_t sent = send(fd, p, len, SOCKET_SEND_FLAGS);

		if (sent < 0) {
#ifdef _WIN32
			if (WSAGetLastError() == WSAEINTR) {
				continue;
			}
#else
			if (errno == EINTR) {
				continue;
			}
#endif
			break;
		}
		if (sent == 0) {
			break;
		}

		p += sent;
		len -= sent;
	}

	return len == 0;
}


static bool socket_recv_all(socket_t fd, void *buf, size_t len) {
	char *p = buf;

	while (len > 0) {
		ssize_t received = recv(fd, p, len, 0);

		if (received < 0) {
#ifdef _WIN32
			if (WSAGetLastError() == WSAEINTR) {
				continue;
			}
#else
			if (errno == EINTR) {
				continue;
			}
#endif
			return false;
		}
		if (received == 0) {
			return false;
		}

		p += received;
		len -= received;
	}

	return true;
}


static bool socket_begin_nonblocking(socket_t fd, int *original_flags) {
#ifdef _WIN32
	u_long nonblocking = 1;

	(void)original_flags;
	return ioctlsocket(fd, FIONBIO, &nonblocking) == 0;
#else
	*original_flags = fcntl(fd, F_GETFL, 0);
	return *original_flags >= 0 &&
		fcntl(fd, F_SETFL, *original_flags | O_NONBLOCK) == 0;
#endif
}


static bool socket_end_nonblocking(socket_t fd, int original_flags) {
#ifdef _WIN32
	u_long blocking = 0;

	(void)original_flags;
	return ioctlsocket(fd, FIONBIO, &blocking) == 0;
#else
	return fcntl(fd, F_SETFL, original_flags) == 0;
#endif
}


static bool socket_wait_writable(struct dns_userdata *u) {
	while (!dns_is_stopping(u)) {
		fd_set writefds;
		struct timeval timeout;
		int result;

		FD_ZERO(&writefds);
		FD_SET(u->fd[1], &writefds);
		timeout.tv_sec = 0;
		timeout.tv_usec = 100000;
#ifdef _WIN32
		result = select(0, NULL, &writefds, NULL, &timeout);
#else
		result = select(u->fd[1] + 1, NULL, &writefds, NULL, &timeout);
#endif
		if (result > 0) {
			return true;
		}
		if (result == 0) {
			continue;
		}
#ifdef _WIN32
		if (WSAGetLastError() != WSAEINTR) {
			return false;
		}
#else
		if (errno != EINTR) {
			return false;
		}
#endif
	}

	return false;
}


static bool socket_send_all_interruptible(struct dns_userdata *u,
					  const void *buf, size_t len) {
	const char *p = buf;

	while (len > 0 && !dns_is_stopping(u)) {
		ssize_t sent = send(u->fd[1], p, len, SOCKET_SEND_FLAGS);

		if (sent < 0) {
#ifdef _WIN32
			int error = WSAGetLastError();

			if (error == WSAEINTR) {
				continue;
			}
			if (error == WSAEWOULDBLOCK && socket_wait_writable(u)) {
				continue;
			}
#else
			if (errno == EINTR) {
				continue;
			}
			if ((errno == EAGAIN || errno == EWOULDBLOCK) &&
			    socket_wait_writable(u)) {
				continue;
			}
#endif
			break;
		}
		if (sent == 0) {
			break;
		}

		p += sent;
		len -= sent;
	}

	return len == 0;
}


static bool dns_write_str(struct dns_userdata *u, const char *str) {
	int original_flags = 0;
	size_t len = strlen(str);
	bool sent;
	bool restored;

	if (!socket_begin_nonblocking(u->fd[1], &original_flags)) {
		SHUTDOWNSOCKET(u->fd[1]);
		return false;
	}
	sent = socket_send_all_interruptible(u, &len, sizeof(len)) &&
		socket_send_all_interruptible(u, str, len);
	restored = socket_end_nonblocking(u->fd[1], original_flags);
	if (sent && restored) {
		return true;
	}

	/* Make any partially delivered frame end in EOF instead of blocking Lua. */
	SHUTDOWNSOCKET(u->fd[1]);
	return false;
}


/* read a string to the lua stack from the pipe fd */
static void read_pushstring(lua_State *L, socket_t fd) {
	size_t len;
	char *buf;

	if (!socket_recv_all(fd, &len, sizeof(len))) {
		lua_pushnil(L);
		return;
	}

	if (len == 0) {
		lua_pushnil(L);
	}
	else {
		buf = malloc(len);
		if ( buf == NULL )
			lua_pushnil(L);
		else if (socket_recv_all(fd, buf, len)) {
			lua_pushlstring(L, buf, len);
			free(buf);
		}
		else {
			free(buf);
			lua_pushnil(L);
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
	struct dns_userdata *u = p;
	socket_t fd = u->fd[1];
	struct hostent *hostent;
	struct in_addr **addr, byaddr;
	char **alias;
	size_t len;
	char *buf;
	char *failed_error = NULL;
	u64_t failed_timeout = 0;

	while (1) {
		if (dns_is_stopping(u) ||
		    !socket_recv_all(fd, &len, sizeof(len))) {
			/* broken pipe */
			return 0;
		}
		buf = malloc(len + 1);
		if ( buf == NULL )
			return 0;

		if (dns_is_stopping(u) || !socket_recv_all(fd, buf, len)) {
			/* broken pipe */
			free(buf);
			return 0;
		}
		buf[len] = '\0';
#if defined(JIVE_DNS_TEST)
		if (strcmp(buf, "__jive_dns_fill_send_buffer__") == 0) {
			char response[4096];

			free(buf);
			memset(response, 'x', sizeof(response) - 1);
			response[sizeof(response) - 1] = '\0';
			while (!dns_is_stopping(u) && dns_write_str(u, response)) {
				/* The test finalizer must stop the saturated writer. */
			}
			return 0;
		}
#endif
		if (failed_error && stat_resolv_conf()) {
			#ifndef _WIN32
			//reload resolv.conf
			res_init();
			#endif
		}
		else if (failed_error && !stat_resolv_conf()) {
			u64_t now = jive_jiffies();
			
			if (now - failed_timeout < RESOLV_TIMEOUT) {
				if (!dns_write_str(u, failed_error)) {
					return 0;
				}
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
				if (!dns_write_str(u, "Not found")) return 0;
				break;
			case NO_DATA:
				if (!dns_write_str(u, "No data")) return 0;
				break;
			case NO_RECOVERY:
				failed_error = "No recovery";
				failed_timeout = jive_jiffies();
				if (!dns_write_str(u, failed_error)) return 0;
				break;
			case TRY_AGAIN:
				failed_error = "Try again"; 
				failed_timeout = jive_jiffies();
				if (!dns_write_str(u, failed_error)) return 0;
				break;
			}
		}
		else {
			if (!dns_write_str(u, "")) return 0; // no error
			if (!dns_write_str(u, hostent->h_name)) return 0;

			alias = hostent->h_aliases;
			while (*alias) {
				if (!dns_write_str(u, *alias)) return 0;
				alias++;
			}
			if (!dns_write_str(u, "")) return 0; // end of aliases

			addr = (struct in_addr **) hostent->h_addr_list;
			while (*addr) {
				if (!dns_write_str(u, inet_ntoa(**addr))) return 0;
				addr++;
			}
			if (!dns_write_str(u, "")) return 0; // end of addrs
		}
	}
}


static int jiveL_dns_open(lua_State *L) {
	struct dns_userdata *u;
	int r;
#if defined(SO_NOSIGPIPE)
	int no_sigpipe = 1;
#endif

	u = lua_newuserdata(L, sizeof(struct dns_userdata));
	u->fd[0] = INVALID_SOCKET_FD;
	u->fd[1] = INVALID_SOCKET_FD;
	u->t = NULL;
	u->mutex = SDL_CreateMutex();
	u->stopping = false;
	if (u->mutex == NULL) {
		return luaL_error(L, "failed to create DNS worker mutex");
	}

	r = socketpair(AF_UNIX, SOCK_STREAM, 0, u->fd);
	if (r < 0) {
		SDL_DestroyMutex(u->mutex);
		u->mutex = NULL;
		return luaL_error(L, "socketpair failed: %s", strerror(r));
	}
#if defined(SO_NOSIGPIPE)
	setsockopt(u->fd[0], SOL_SOCKET, SO_NOSIGPIPE,
		   (const void *)&no_sigpipe, sizeof(no_sigpipe));
	setsockopt(u->fd[1], SOL_SOCKET, SO_NOSIGPIPE,
		   (const void *)&no_sigpipe, sizeof(no_sigpipe));
#endif

	u->t = SDL_CreateThread(dns_resolver_thread, u);
	if (u->t == NULL) {
		CLOSESOCKET(u->fd[0]);
		CLOSESOCKET(u->fd[1]);
		u->fd[0] = INVALID_SOCKET_FD;
		u->fd[1] = INVALID_SOCKET_FD;
		SDL_DestroyMutex(u->mutex);
		u->mutex = NULL;
		return luaL_error(L, "create dns_resolver_thread failed");
	}

	luaL_getmetatable(L, "jive.dns");
	lua_setmetatable(L, -2);

	return 1;
}


static int jiveL_dns_gc(lua_State *L) {
	struct dns_userdata *u;

	u = lua_touserdata(L, 1);
	if (u->t != NULL) {
		/* Interrupt worker I/O, then keep the sockets valid until it stops. */
		dns_request_stop(u);
		SHUTDOWNSOCKET(u->fd[0]);
		SHUTDOWNSOCKET(u->fd[1]);
		SDL_WaitThread(u->t, NULL);
		u->t = NULL;
	}
	if (u->fd[0] != INVALID_SOCKET_FD) {
		CLOSESOCKET(u->fd[0]);
		u->fd[0] = INVALID_SOCKET_FD;
	}
	if (u->fd[1] != INVALID_SOCKET_FD) {
		CLOSESOCKET(u->fd[1]);
		u->fd[1] = INVALID_SOCKET_FD;
	}
	if (u->mutex != NULL) {
		SDL_DestroyMutex(u->mutex);
		u->mutex = NULL;
	}

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

	if (!socket_send_all(u->fd[0], &len, sizeof(len)) ||
	    !socket_send_all(u->fd[0], buf, len)) {
		SHUTDOWNSOCKET(u->fd[0]);
		return luaL_error(L, "DNS request pipe write failed");
	}

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
