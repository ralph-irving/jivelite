#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
LUA_BIN=${LUA_BIN:-lua}

LUA_PATH="$ROOT/share/jive/?.lua;$ROOT/share/jive/?/init.lua;$ROOT/share/lua/5.1/?.lua;$ROOT/share/lua/5.1/?/init.lua;;"
export LUA_PATH

exec "$LUA_BIN" "$ROOT/tests/tick_uptime.lua"
