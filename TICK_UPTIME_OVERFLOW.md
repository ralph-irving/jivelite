# Monotonic Tick Uptime Overflow

Status: implementation complete; native 32-bit hardware validation remains
open

## Problem

JiveLite exposed a 32-bit millisecond counter. It wrapped after `2^32`
milliseconds, approximately 49 days, 17 hours, and 3 minutes. This is a
counter-width defect on every CPU architecture, not a limitation of 32-bit
processors.

The Lua binding used `lua_pushinteger()`. A runtime with a signed 32-bit
`lua_Integer` can therefore expose negative tick values after `2^31`
milliseconds, approximately 24 days, 20 hours, and 31 minutes.

The possible symptoms include stalled timers and animations, stale discovery
state, incorrect input deadlines, and delayed network retries.

## Clock design

`jive_jiffies()` now returns unsigned 64-bit milliseconds. Its primary source
is platform specific:

- Linux and Solaris use `clock_gettime(CLOCK_MONOTONIC)`;
- macOS uses `mach_absolute_time()`; and
- Windows uses `QueryPerformanceCounter()`.

The clock maintains a mutex-protected state containing the last primary-clock
sample, the last `SDL_GetTicks()` sample, and the accumulated 64-bit result.
Normal updates use the primary-clock delta. If that clock fails or moves
backwards, the update uses unsigned SDL delta arithmetic instead. The first
successful primary sample after recovery only re-anchors that source; it does
not replace the accumulated result. A backwards primary sample also forces a
separate re-anchoring sample, preventing a later recovery from replaying the
backwards jump as elapsed time. Consequently failure and recovery cannot make
application time jump backwards or spuriously forwards.

Initialization fails explicitly if the SDL mutex cannot be created or locked.
The implementation never accesses its 64-bit shared state without that mutex,
which is required because 64-bit reads and writes are not generally atomic on
32-bit targets. JiveLite initializes the clock immediately after SDL and shuts
it down immediately before SDL; calling it outside that lifecycle is an error.

The DNS resolver owns an SDL worker thread that also reads the application
clock. Its request receive path remains blocking, so an idle worker sleeps in
the kernel without periodic polling. Only a framed reply send temporarily
switches the worker endpoint to non-blocking mode. If the reply buffer is full,
`select()` waits for write readiness with a bounded timeout and checks a
mutex-protected stop flag before retrying. The original blocking mode is
restored after the reply.

The userdata finalizer sets the stop flag, shuts down both directions of the
socket pair, waits for the worker with `SDL_WaitThread()`, and only then closes
the sockets and destroys the worker mutex. Therefore Lua shutdown completes
all clock users before the `atexit()` handler destroys the clock mutex and
shuts down SDL. Platforms that provide `MSG_NOSIGNAL` or `SO_NOSIGPIPE` also
suppress `SIGPIPE`, so an interrupted write reports an error instead of
terminating the process.

Socket shutdown cannot interrupt a blocking system resolver call such as
`gethostbyname()`. Application shutdown can therefore wait for an in-progress
resolver call to return. A strict upper bound would require a separate,
cancellable resolver design rather than additional socket handling.

Unsigned subtraction extends an SDL wrap as long as the application samples
the clock at least once per `2^32` milliseconds. JiveLite samples it continuously
in its event loop. No sampling algorithm can infer multiple unobserved wraps
after more than 49.7 days without a call.

## Consumers and compatibility

Native event timestamps, input deadlines, DNS retry state, and uptime storage
use 64-bit values. Lua receives ticks through `lua_pushnumber()`. Both supported
Lua runtimes use a double-precision `lua_Number`, which represents every integer
millisecond exactly through `2^53`.

The public Lua method names, arguments, return units, and timer behavior are
unchanged. Existing Lua applets do not require source changes.

Changing `JiveEvent.ticks` changes the native structure layout. Native modules
that exchange `JiveEvent` values must be rebuilt against the matching JiveLite
headers. An old binary module must not be reused with the new executable even
if its source still compiles: the two binaries would disagree about field
offsets and the size of `JiveEvent`.

Ralph Irving's separate `lirc-bsp` repository builds the existing
`ir_bsp.so` native module used for infrared input on piCorePlayer. This does not
mean that JiveLite gains a new package or external runtime dependency. It means
that the companion source patch in that repository must be applied and the
already existing module must be compiled again against this version of
`jive.h`. The patch replaces the module's private 32-bit millisecond source and
32-bit IR timing fields with `jive_jiffies()` and `u64_t`, so IR down, repeat,
hold, press, and up events use JiveLite's 64-bit clock domain.

The resulting `ir_bsp.so` resolves `jive_jiffies()` from the JiveLite
executable at load time, just as the module already resolves other exported
JiveLite symbols. piCorePlayer's JiveLite link uses `-Wl,-E` to expose those
symbols. Package validation therefore means building and installing the
matching JiveLite executable and `ir_bsp.so` together, then testing infrared
input on piCorePlayer hardware. It does not mean introducing or downloading a
second LIRC implementation.

SqueezePlay contains related clock code but also sends intentional 32-bit tick
fields over the SlimProto wire protocol. It requires a separate source and
protocol audit; this JiveLite change must not be copied there mechanically.

## Verification

The native state-machine test covers:

- a primary clock crossing `2^32`;
- the SDL fallback crossing its wrap;
- primary-clock failure and recovery; and
- a primary clock moving backwards.

The Lua test covers one-shot, recurring, and sorted timers across `2^31` and
`2^32`. The matching `lirc-bsp` test verifies IR down, repeat, hold, and up
events across `2^32`. The DNS lifecycle test repeatedly starts a resolver and
collects its Lua userdata while the worker is either waiting in `recv()` or
writing into a deliberately saturated reply buffer. It verifies that the
interruptible send path and subsequent worker join both terminate before the
application clock is shut down. Code inspection and the blocking receive test
also ensure that idle operation contains no timed receive polling loop.

Required before claiming complete platform validation:

- Windows and Solaris compile and runtime tests;
- a compile and runtime test on a real 32-bit target; and
- a piCorePlayer package test with the rebuilt `lirc-bsp` module.

Completed locally:

- full x86_64 Linux, Intel macOS, and i386 Debian LuaJIT builds;
- native clock tests on x86_64 Linux and Intel macOS;
- native clock tests with AddressSanitizer and UndefinedBehaviorSanitizer on
  Intel macOS;
- DNS shutdown tests on x86_64 Linux, Intel macOS, and i386 Debian, including
  AddressSanitizer and UndefinedBehaviorSanitizer on both desktop platforms
  and ThreadSanitizer on Linux;
- Lua timer tests with LuaJIT 2.1 and Jive Lua 5.1.5; and
- native clock and LuaJIT timer tests in an i386 Debian userspace.

The i386 result validates a real 32-bit userspace ABI under container
virtualization. It does not replace runtime validation on Radio, Touch, or
another physical 32-bit target.
