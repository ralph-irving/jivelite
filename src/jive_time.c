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

struct jive_clock_state {
	SDL_mutex *mutex;
	Uint32 last_sdl;
	u64_t last_primary;
	u64_t value;
	bool initialized;
	bool primary_valid;
};

static struct jive_clock_state clock_state = { NULL, 0, 0, 0, false, false };

#if defined(WIN32)
static LARGE_INTEGER qpc_frequency;
#elif defined(__APPLE__)
static mach_timebase_info_data_t mach_timebase = { 0, 0 };
#endif

static bool read_primary_ticks(u64_t *ticks)
{
#if defined(WIN32)
	LARGE_INTEGER counter;
	u64_t whole;
	u64_t remainder;

	if (qpc_frequency.QuadPart <= 0 &&
		(!QueryPerformanceFrequency(&qpc_frequency) ||
		 qpc_frequency.QuadPart <= 0)) {
		return false;
	}
	if (!QueryPerformanceCounter(&counter) || counter.QuadPart < 0) {
		return false;
	}

	whole = (u64_t)counter.QuadPart / (u64_t)qpc_frequency.QuadPart;
	remainder = (u64_t)counter.QuadPart % (u64_t)qpc_frequency.QuadPart;
	*ticks = whole * 1000 +
		remainder * 1000 / (u64_t)qpc_frequency.QuadPart;
	return true;
#elif defined(__APPLE__)
	u64_t absolute;
	u64_t whole;
	u64_t remainder;
	u64_t nanoseconds;

	if (mach_timebase.denom == 0 &&
		mach_timebase_info(&mach_timebase) != KERN_SUCCESS) {
		return false;
	}
	if (mach_timebase.denom == 0) {
		return false;
	}

	absolute = mach_absolute_time();
	whole = absolute / mach_timebase.denom;
	remainder = absolute % mach_timebase.denom;
	nanoseconds = whole * mach_timebase.numer +
		(remainder * mach_timebase.numer) / mach_timebase.denom;
	*ticks = nanoseconds / 1000000;
	return true;
#elif HAVE_CLOCK_GETTIME
	struct timespec now;

	if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) {
		return false;
	}
	*ticks = (u64_t)now.tv_sec * 1000 +
		(u64_t)now.tv_nsec / 1000000;
	return true;
#else
	(void)ticks;
	return false;
#endif
}

static void reset_clock_samples(Uint32 current_sdl, bool primary_valid,
				u64_t current_primary)
{
	clock_state.last_sdl = current_sdl;
	clock_state.last_primary = current_primary;
	clock_state.value = primary_valid ?
		current_primary : (u64_t)current_sdl;
	clock_state.initialized = true;
	clock_state.primary_valid = primary_valid;
}

static u64_t update_clock_samples(Uint32 current_sdl, bool primary_valid,
				  u64_t current_primary)
{
	u64_t delta;
	bool primary_moved_backwards;

	if (!clock_state.initialized) {
		reset_clock_samples(current_sdl, primary_valid, current_primary);
		return clock_state.value;
	}

	primary_moved_backwards = primary_valid && clock_state.primary_valid &&
		current_primary < clock_state.last_primary;

	/* Uint32 subtraction extends one SDL wrap between consecutive samples. */
	delta = (Uint32)(current_sdl - clock_state.last_sdl);
	if (primary_valid && clock_state.primary_valid &&
		!primary_moved_backwards) {
		delta = current_primary - clock_state.last_primary;
	}

	clock_state.value += delta;
	clock_state.last_sdl = current_sdl;
	clock_state.last_primary = current_primary;
	/* A backwards sample needs one additional sample to re-anchor safely. */
	clock_state.primary_valid = primary_valid && !primary_moved_backwards;

	return clock_state.value;
}

static void initialize_clock_state(void)
{
	u64_t primary = 0;
	bool primary_valid;

	primary_valid = read_primary_ticks(&primary);
	reset_clock_samples(SDL_GetTicks(), primary_valid, primary);
}

bool jive_time_init(void)
{
	if (clock_state.mutex == NULL) {
		clock_state.mutex = SDL_CreateMutex();
	}
	if (clock_state.mutex == NULL) {
		return false;
	}

	if (SDL_LockMutex(clock_state.mutex) != 0) {
		return false;
	}
	if (!clock_state.initialized) {
		initialize_clock_state();
	}
	SDL_UnlockMutex(clock_state.mutex);
	return true;
}

void jive_time_quit(void)
{
	if (clock_state.mutex != NULL) {
		SDL_DestroyMutex(clock_state.mutex);
	}
	clock_state.mutex = NULL;
	clock_state.last_sdl = 0;
	clock_state.last_primary = 0;
	clock_state.value = 0;
	clock_state.initialized = false;
	clock_state.primary_valid = false;
}

u64_t jive_jiffies(void)
{
	Uint32 current_sdl;
	u64_t current_primary = 0;
	u64_t result;
	bool current_primary_valid;

	if (clock_state.mutex == NULL || !clock_state.initialized) {
		fprintf(stderr, "Monotonic clock used outside SDL lifecycle\n");
		abort();
	}
	if (SDL_LockMutex(clock_state.mutex) != 0) {
		fprintf(stderr, "Could not lock monotonic clock: %s\n",
			SDL_GetError());
		abort();
	}

	current_sdl = SDL_GetTicks();
	current_primary_valid = read_primary_ticks(&current_primary);
	result = update_clock_samples(current_sdl, current_primary_valid,
				      current_primary);

	SDL_UnlockMutex(clock_state.mutex);
	return result;
}

#if defined(JIVE_TIME_TEST)
void jive_time_test_reset(Uint32 current_sdl, bool primary_valid,
			  u64_t current_primary)
{
	reset_clock_samples(current_sdl, primary_valid, current_primary);
}

u64_t jive_time_test_update(Uint32 current_sdl, bool primary_valid,
			    u64_t current_primary)
{
	return update_clock_samples(current_sdl, primary_valid, current_primary);
}
#endif
