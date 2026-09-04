#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
CC=${CC:-cc}
SDL_CONFIG=${SDL_CONFIG:-sdl-config}
CFLAGS=${CFLAGS:--Wall -Wextra -Werror}
LUA_CFLAGS=${LUA_CFLAGS:-}
LUA_LIBS=${LUA_LIBS:--lluajit-5.1}
SYSTEM_LIBS=${SYSTEM_LIBS:--lresolv}
SDL_LIBS=${SDL_LIBS:-$($SDL_CONFIG --libs | sed -e 's@[^ ]*libSDLmain\.a@@g' -e 's@-lSDLmain@@g')}
OUT=${TMPDIR:-/tmp}/jivelite-dns-shutdown-$$

trap 'rm -f "$OUT"' EXIT HUP INT TERM

"$CC" $CFLAGS -DJIVE_DNS_TEST -I"$ROOT/src" $LUA_CFLAGS \
	$($SDL_CONFIG --cflags) \
	"$ROOT/tests/dns_shutdown.c" "$ROOT/src/jive_dns.c" \
	"$ROOT/src/jive_time.c" $SDL_LIBS $LUA_LIBS $SYSTEM_LIBS -o "$OUT"
"$OUT"
