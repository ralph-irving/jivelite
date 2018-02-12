/*
** Copyright 2010 Logitech. All Rights Reserved.
**
** This file is licensed under BSD. Please see the LICENSE file for details.
*/

#include "../common.h"
#include "../jive.h"

#include "visualizer.h"

#define VUMETER_DEFAULT_SAMPLE_WINDOW 1024 * 2

int visualizer_vumeter(lua_State *L) {
	long long sample_accumulator[2];
	int16_t *ptr;
	s16_t sample;
	s32_t sample_sq;
	size_t i, num_samples, samples_until_wrap;

	int offs;

	num_samples = luaL_optinteger(L, 2, VUMETER_DEFAULT_SAMPLE_WINDOW);

	sample_accumulator[0] = 0;
	sample_accumulator[1] = 0;

	vis_check();

	if (vis_get_playing()) {

		vis_lock();

		offs = vis_get_buffer_idx() - (num_samples * 2);
		while (offs < 0) offs += vis_get_buffer_len();

		ptr = vis_get_buffer() + offs;
		samples_until_wrap = vis_get_buffer_len() - offs;

		for (i=0; i<num_samples; i++) {
			sample = (*ptr++) >> 8;
			sample_sq = sample * sample;
			sample_accumulator[0] += sample_sq;

			sample = (*ptr++) >> 8;
			sample_sq = sample * sample;
			sample_accumulator[1] += sample_sq;

			samples_until_wrap -= 2;
			if (samples_until_wrap <= 0) {
				ptr = vis_get_buffer();
				samples_until_wrap = vis_get_buffer_len();
			}
		}

		vis_unlock();
	}

	sample_accumulator[0] /= num_samples;
	sample_accumulator[1] /= num_samples;

	lua_newtable(L);
	lua_pushinteger(L, sample_accumulator[0]);
	lua_rawseti(L, -2, 1);
	lua_pushinteger(L, sample_accumulator[1]);
	lua_rawseti(L, -2, 2);

	return 1;
}
