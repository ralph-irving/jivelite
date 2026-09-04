/*
** Native tests for the monotonic application clock state machine.
*/

#include <assert.h>
#include <stdio.h>

#include "common.h"

#ifdef main
#undef main
#endif

void jive_time_test_reset(Uint32 current_sdl, bool primary_valid,
			  u64_t current_primary);
u64_t jive_time_test_update(Uint32 current_sdl, bool primary_valid,
			    u64_t current_primary);

static void test_live_clock(void)
{
	u64_t before;
	u64_t after;

	assert(SDL_Init(SDL_INIT_TIMER) == 0);
	assert(jive_time_init());
	before = jive_jiffies();
	SDL_Delay(5);
	after = jive_jiffies();
	assert(after >= before + 1);
	jive_time_quit();
	SDL_Quit();
}

static void test_primary_crosses_32_bit_boundary(void)
{
	u64_t initial = ((u64_t)1 << 32) - 2;

	jive_time_test_reset(100, true, initial);
	assert(jive_time_test_update(104, true, initial + 4) == initial + 4);
}

static void test_sdl_fallback_crosses_wrap(void)
{
	u64_t initial = ((u64_t)1 << 32) + 100;

	jive_time_test_reset(0xfffffffeU, true, initial);
	assert(jive_time_test_update(2, false, 0) == initial + 4);
	assert(jive_time_test_update(7, false, 0) == initial + 9);
}

static void test_primary_recovery_does_not_jump(void)
{
	jive_time_test_reset(100, true, 1000);
	assert(jive_time_test_update(110, false, 0) == 1010);
	assert(jive_time_test_update(120, true, 5000) == 1020);
	assert(jive_time_test_update(130, true, 5010) == 1030);
}

static void test_backward_primary_uses_sdl_delta(void)
{
	jive_time_test_reset(100, true, 5000);
	assert(jive_time_test_update(110, true, 1000) == 5010);
	assert(jive_time_test_update(120, true, 1010) == 5020);
	assert(jive_time_test_update(130, true, 1020) == 5030);
}

int main(int argc, char **argv)
{
	(void)argc;
	(void)argv;
	test_live_clock();
	test_primary_crosses_32_bit_boundary();
	test_sdl_fallback_crosses_wrap();
	test_primary_recovery_does_not_jump();
	test_backward_primary_uses_sdl_delta();
	puts("native tick clock tests passed");
	return 0;
}
