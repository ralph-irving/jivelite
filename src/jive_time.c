/*
** Copyright 2026 JiveLite contributors.
**
** This file is licensed under BSD. Please see the LICENSE file for details.
*/

#include "common.h"

#if defined(WIN32)
#include <windows.h>
#elif defined(__APPLE__)
#include <mach/mach_time.h>
#else
#include <time.h>
#endif

#if !defined(WIN32) && !defined(__APPLE__) && !HAVE_CLOCK_GETTIME
static SDL_mutex *tick_mutex = NULL;
static Uint32 tick_last = 0;
static u64_t tick_epoch = 0;
static bool tick_initialized = false;
#endif

void jive_time_init(void)
{
#if !defined(WIN32) && !defined(__APPLE__) && !HAVE_CLOCK_GETTIME
	if (tick_mutex == NULL) {
		tick_mutex = SDL_CreateMutex();
	}
	if (!tick_initialized) {
		tick_last = SDL_GetTicks();
		tick_initialized = true;
	}
#endif
}

void jive_time_quit(void)
{
#if !defined(WIN32) && !defined(__APPLE__) && !HAVE_CLOCK_GETTIME
	if (tick_mutex != NULL) {
		SDL_DestroyMutex(tick_mutex);
		tick_mutex = NULL;
	}
#endif
}

u64_t jive_jiffies(void)
{
#if defined(WIN32)
	LARGE_INTEGER counter;
	LARGE_INTEGER frequency;
	u64_t whole;
	u64_t remainder;

	if (!QueryPerformanceFrequency(&frequency) || frequency.QuadPart <= 0 ||
		!QueryPerformanceCounter(&counter)) {
		return (u64_t)SDL_GetTicks();
	}

	whole = (u64_t)counter.QuadPart / (u64_t)frequency.QuadPart;
	remainder = (u64_t)counter.QuadPart % (u64_t)frequency.QuadPart;
	return whole * 1000 + remainder * 1000 / (u64_t)frequency.QuadPart;
#elif defined(__APPLE__)
	static mach_timebase_info_data_t timebase = { 0, 0 };
	u64_t absolute;
	u64_t whole;
	u64_t remainder;
	u64_t nanoseconds;

	if (timebase.denom == 0) {
		mach_timebase_info(&timebase);
	}
	absolute = mach_absolute_time();
	whole = absolute / timebase.denom;
	remainder = absolute % timebase.denom;
	nanoseconds = whole * timebase.numer +
		(remainder * timebase.numer) / timebase.denom;
	return nanoseconds / 1000000;
#elif HAVE_CLOCK_GETTIME
	struct timespec now;

	if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) {
		return (u64_t)SDL_GetTicks();
	}
	return (u64_t)now.tv_sec * 1000 + (u64_t)now.tv_nsec / 1000000;
#else
	Uint32 current;
	u64_t result;

	if (!tick_initialized) {
		jive_time_init();
	}
	if (tick_mutex != NULL) {
		SDL_LockMutex(tick_mutex);
	}
	current = SDL_GetTicks();
	if (current < tick_last) {
		tick_epoch += ((u64_t)1 << 32);
	}
	tick_last = current;
	result = tick_epoch + current;
	if (tick_mutex != NULL) {
		SDL_UnlockMutex(tick_mutex);
	}
	return result;
#endif
}
