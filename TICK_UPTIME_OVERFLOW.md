# Monotonic Tick Uptime Overflow

Status: fixed in this branch; native 32-bit hardware validation remains open

## Problem

JiveLite exposed `jive_jiffies()` as a 32-bit millisecond counter. It wrapped
after `2^32` milliseconds, approximately 49 days, 17 hours, and 3 minutes.
This was a counter-width issue on every CPU architecture, not only on 32-bit
processors.

The Lua binding also used `lua_pushinteger()`. On an ABI where `lua_Integer`
is a signed 32-bit type, the value could become negative after `2^31`
milliseconds, approximately 24 days, 20 hours, and 31 minutes.

This is a reliability and availability defect, not a direct TLS or memory
safety defect. A long-running UI could stop advancing timers or frames, retain
stale discovery state, mishandle input deadlines, or delay network timeouts.

## Affected consumers

The inventory covered:

- the native clock, event timestamps, input deadlines, uptime reporting, DNS
  retry time, and performance probes;
- frame scheduling, the sorted timer queue, and network inactivity timeouts;
- gesture, acceleration, quick-touch, transition, and UI rate-limit timing;
- player/server age and rate-limit state; and
- bundled discovery, now-playing, browser, and image-viewer timing.

These consumers share `Framework:getTicks()` or event timestamps. They do not
need individual wrap arithmetic once the common clock remains monotonically
increasing and exactly representable.

## Implementation

- `jive_jiffies()` now returns unsigned 64-bit milliseconds.
- Linux and Solaris use 64-bit `CLOCK_MONOTONIC` arithmetic.
- macOS uses `mach_absolute_time()` with its time-base conversion.
- Windows uses `QueryPerformanceCounter()`.
- A mutex-protected epoch extender preserves monotonic values on any remaining
  SDL-only fallback platform.
- C deadlines and event timestamps use 64-bit storage.
- Framework and event ticks use `lua_pushnumber()`. Both supported runtimes use
  a double-precision `lua_Number`, which exactly represents integer
  milliseconds through `2^53`.
- Public Lua method names and millisecond units are unchanged.

## Tests and remaining gate

`tests/run-tick-uptime.sh` injects values around both `2^31` and `2^32` into
the existing Timer API and verifies one-shot, recurring, and sorted timers.
The same source change has also passed clean Linux builds, complete LuaJIT 2.1
and Jive Lua 5.1.5 HTTP/TLS suites, both AddressSanitizer suites, native Intel
macOS builds, DMG verification, and native macOS HTTP/HTTPS smoke tests.

A real long-duration or injected-clock test on a native 32-bit target remains
required before claiming that platform gate. This fix is independent of HTTPS
and can be reviewed or reverted on its own.
