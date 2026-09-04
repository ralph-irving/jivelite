#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
CC=${CC:-cc}
SDL_CONFIG=${SDL_CONFIG:-sdl-config}
CFLAGS=${CFLAGS:--Wall -Wextra -Werror}
LUA_CFLAGS=${LUA_CFLAGS:-}
SDL_LIBS=${SDL_LIBS:-$($SDL_CONFIG --libs | sed -e 's@[^ ]*libSDLmain\.a@@g' -e 's@-lSDLmain@@g')}
OUT=${TMPDIR:-/tmp}/jivelite-tick-clock-$$

trap 'rm -f "$OUT"' EXIT HUP INT TERM

"$CC" $CFLAGS -DJIVE_TIME_TEST -I"$ROOT/src" $LUA_CFLAGS \
	$($SDL_CONFIG --cflags) \
	"$ROOT/tests/tick_clock.c" "$ROOT/src/jive_time.c" \
	$SDL_LIBS -o "$OUT"
"$OUT"
