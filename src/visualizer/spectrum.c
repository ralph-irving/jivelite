/*
** Copyright 2010 Logitech. All Rights Reserved.
**
** This file is licensed under BSD. Please see the LICENSE file for details.
*/

#include "../common.h"
#include "../jive.h"

#include "visualizer.h"
#include "kiss_fft.h"

#include <math.h>

/////////////////////////////////////////////////////////
//
// Package constants
//
/////////////////////////////////////////////////////////

// Calculated as (x ^ 2.5) * (0x1fffff) where x is in the range
// 0..1 in 32 steps. This creates a curve weighted towards
// lower values.
static int power_map[32] = {
  0, 362, 2048, 5643, 11585, 20238, 31925, 46935, 65536, 87975, 114486, 
  145290, 180595, 220603, 265506, 315488, 370727, 431397, 497664, 
  569690, 647634, 731649, 821886, 918490, 1021605, 1131370, 1247924, 
  1371400, 1501931, 1639645, 1784670, 1937131
}; 

#define X_SCALE_LOG 20

// The maximum number of input samples sent to the FFT.
// This is the actual number of input points for a combined
// stereo signal.
// For separate stereo signals, the number of input points for
// each signal is half of the value.
#define MAX_SAMPLE_WINDOW 1024 * X_SCALE_LOG

// The maximum number of subbands forming the output of the FFT.
// The is the actual number of output points for a combined
// stereo signal.
// For separate stereo signals, the number of output points for
// each signal is half of the value.
#define MAX_SUBBANDS MAX_SAMPLE_WINDOW / 2 / X_SCALE_LOG

// The minimum size of the FFT that we'll do.
#define MIN_SUBBANDS 16

// The minimum total number of input samples to consider for the FFT.
// If the sample window used is smaller, then we will use multiple
// sample windows.
#define MIN_FFT_INPUT_SAMPLES 128

/////////////////////////////////////////////////////////
//
// Package state variables
//
/////////////////////////////////////////////////////////

// Rendering related state variables

// The width of the channel histogram in pixels
static int channel_width[2];

// The size of an individual histogram bar in pixels
static int bar_size[2];

// The number of subbands displayed by a single histogram bar
static int subbands_in_bar[2];

// The number of histogram to display
static int num_bars[2];

// Is the channel histogram flipped 
static int channel_flipped[2];

// Do we clip the number of subbands shown based on the width
// or show all of them?
static int clip_subbands[2];

// FFT related state variables

// The number of output points of the FFT. In clipped mode, we
// may not display all of them.
static int num_subbands;

// The number of input points to the FFT.
static int sample_window;

// The number of sample windows that we will average across.
static int num_windows;

// Should we combine the channel histograms and only show a single
// channel?
static int is_mono;

// The value to use for computing preemphasis 
// TODO: needed as parameter?
//static int preemphasis_db_per_khz;

/////////////////////////////////////////////////////////
//
// Package buffers
//
/////////////////////////////////////////////////////////

// A Hamming window used on the input samples. This could be
// precalculated for a fixed window size. Right now, we're
// computing it in the begin() method.
double filter_window[MAX_SAMPLE_WINDOW];

// Preemphasis applied to the subbands. This is precomputed
// based on a db/KHz value.
double preemphasis[MAX_SUBBANDS];

// Lookup table to index the FFT result into the subband to
// produce a log scale on the x axis
int decade_idx[MAX_SUBBANDS];
int decade_len[MAX_SUBBANDS];

// Used in power computation across multiple sample windows.
// For a small window size, this could be stack based.
float avg_power[2 * MAX_SUBBANDS];

kiss_fft_cfg cfg = NULL;

// Parameters on the lua stack for the spectrum analyzer:
//   2 - Channels: stereo == 0, mono == 1
// Left channel parameters:
//   3 - Width in pixels
//   4 - orientation: left to right == 0, right to left == 1
//   5 - Bar size in pixels
//   6 - Clipping: show all subbands == 0, clip higher subbands == 1
// Right channel parameters (not required for mono):
//   7-10 - same as left channel parameters

int visualizer_spectrum_init( lua_State *L) {
	int l2int = 0;
	int shiftsubbands;

	is_mono = luaL_optinteger(L, 2, 0);

//	printf( "* is_mono: %d\n", is_mono);

	channel_width[0] = luaL_optinteger(L, 3, 192);	// Default: 192
	channel_flipped[0] = luaL_optinteger(L, 4, 0);	// Default: false
	bar_size[0] = luaL_optinteger(L, 5, 6);		// Default: 6
	clip_subbands[0] = luaL_optinteger(L, 6, 0);	// Default: false

//	printf( "* channel_width[0]: %d\n", channel_width[0]);
//	printf( "* channel_flipped[0]: %d\n", channel_flipped[0]);
//	printf( "* bar_size[0]: %d\n", bar_size[0]);
//	printf( "* clip_subbands[0]: %d\n", clip_subbands[0]);

	if( !is_mono) {
		channel_width[1] = luaL_optinteger(L, 7, 192);
		channel_flipped[1] = luaL_optinteger(L, 8, 0);
		bar_size[1] = luaL_optinteger(L, 9, 2);
		clip_subbands[1] = luaL_optinteger(L, 10, 0);

//		printf( "* channel_width[1]: %d\n", channel_width[1]);
//		printf( "* channel_flipped[1]: %d\n", channel_flipped[1]);
//		printf( "* bar_size[1]: %d\n", bar_size[1]);
//		printf( "* clip_subbands[1]: %d\n", clip_subbands[1]);
	}

	// Approximate the number of subbands we'll display based
	// on the width available and the size of the histogram
	// bars.
	num_subbands = channel_width[0] / bar_size[0];

//	printf( "bar_size[0] %d num_subbands %d\n", bar_size[0], num_subbands);

	// Calculate the integer component of the log2 of the num_subbands
	l2int = 0;
	shiftsubbands = num_subbands;
	while( shiftsubbands != 1) {
		l2int++;
		shiftsubbands >>= 1;
	}

	// The actual number of subbands is the largest power
	// of 2 smaller than the specified width.
	num_subbands = 1L << l2int;

//	printf( "shiftsubbands %d l2int %d num_subbands %d\n", shiftsubbands, l2int, num_subbands);

	// In the case where we're going to clip the higher
	// frequency bands, we choose the next highest
	// power of 2.
	if( clip_subbands[0]) {
		num_subbands <<= 1;
	}

	// The number of histogram bars we'll display is nominally
	// the number of subbands we'll compute.
	num_bars[0] = num_subbands;

//	printf( "num_bars[0] %d num_bars[1] %d\n", num_bars[0], num_bars[1]);

	// Though we may have to compute more subbands to meet
	// a minimum and average them into the histogram bars.
	if( num_subbands < MIN_SUBBANDS) {
		subbands_in_bar[0] = MIN_SUBBANDS / num_subbands;
		num_subbands = MIN_SUBBANDS;
	} else {
		subbands_in_bar[0] = 1;
	}

//	printf( "subbands_in_bar[0] %d subbands_in_bar[1] %d\n", subbands_in_bar[0], subbands_in_bar[1]);

	// If we're clipping off the higher subbands we cut down
	// the actual number of bars based on the width available.
	if( clip_subbands[0]) {
		num_bars[0] = channel_width[0] / bar_size[0];
	}

	// Since we now have a fixed number of subbands, we choose
	// values for the second channel based on these.
	if( !is_mono) {
		num_bars[1] = channel_width[1] / bar_size[1];
		subbands_in_bar[1] = 1;
		// If we have enough space for all the subbands, great.
		if( num_bars[1] > num_subbands) {
			num_bars[1] = num_subbands;

		// If not, we find the largest factor of the
		// number of subbands that we can show.
		} else if( !clip_subbands[1]) {
			int s = num_subbands;
			subbands_in_bar[1] = 1;
			while( s > num_bars[1]) {
				s >>= 1;
				subbands_in_bar[1]++;
			}
			num_bars[1] = s;
		}
	}

//	printf( "num_bars[0] %d num_bars[1] %d\n", num_bars[0], num_bars[1]);
//	printf( "subbands_in_bar[0] %d subbands_in_bar[1] %d\n", subbands_in_bar[0], subbands_in_bar[1]);

	// Calculate the number of samples we'll need to send in as
	// input to the FFT. If we're halving the bandwidth (by
	// averaging adjacent samples), we're going to need twice
	// as many.
	sample_window = num_subbands * 2 * X_SCALE_LOG;

	if( sample_window < MIN_FFT_INPUT_SAMPLES) {
		num_windows = MIN_FFT_INPUT_SAMPLES / sample_window;
	} else {
		num_windows = 1;
	}

	if( cfg) {
		free( cfg);
		cfg = NULL;
	}

	if( !cfg) {
		double const1;
		double const2;
		int w;

		double freq_sum;
		double scale_db;
		double e;

		int s;

		cfg = kiss_fft_alloc( sample_window, 0, NULL, NULL);

// Still needed?
//		mem_addr_t lvptr = (mem_addr_t) last_values->aligned;
//		for( int ch = 0; ch < 2; ch++) {
//			for( u32_t s = 0; s < num_subbands; s++) {
//				paged_write_u32( last_values, lvptr, 0);
//				lvptr += sizeof( u32_t);
//			}
//		}

		const1 = 0.54;
		const2 = 0.46;
		for( w = 0; w < sample_window; w++) {
			const double twopi = 6.283185307179586476925286766;
			filter_window[w] = const1 - ( const2 * cos( twopi * (double) w / (double) sample_window));
		}

		// Compute the preemphasis
		freq_sum = 0;
		scale_db = 0;

		// compute the decade scale
		e = log(num_subbands * X_SCALE_LOG) / log(num_subbands);

		decade_idx[0] = 1;
		for( s = 0; s < num_subbands - 1; s++) {
			decade_idx[s+1] = pow( s+1, e) + 1;
			decade_len[s] = decade_idx[s+1] - decade_idx[s];

			while( freq_sum > 1) {
				freq_sum -= 1;
// TODO: needed as parameter?
//				scale_db += preemphasis_db_per_khz;
//				scale_db += ( 0x10000 >> 16);

				scale_db += 1.2; // 1.2 dB per kHz

			}
			if( scale_db != 0) {
				preemphasis[s] = pow( 10, ( scale_db / 10.0));
			} else {
				preemphasis[s] = 1;
			}
			freq_sum += (vis_get_rate() / 1000) / ((float)(num_subbands * X_SCALE_LOG) / decade_len[s]);
		}
		decade_len[s] = (num_subbands * X_SCALE_LOG) - decade_idx[s] + 1;
		preemphasis[s] = pow( 10, ( scale_db / 10.0));

//		for( s = 0; s < num_subbands; s++) {
//			printf("subband: %d, decade_idx: %d, decade_len: %d, preemphasis: %f\n", s, decade_idx[s], decade_len[s], preemphasis[s]);
//		}

	}

	// Return calculated number of bars for each channel
	lua_newtable( L);
	lua_pushinteger( L, num_bars[0]);
	lua_rawseti( L, -2, 1);
	lua_pushinteger( L, num_bars[1]);
	lua_rawseti( L, -2, 2);

	return 1;
}


int visualizer_spectrum( lua_State *L) {
	int sample_bin_ch0[MAX_SUBBANDS];
	int sample_bin_ch1[MAX_SUBBANDS];

	int i;
	int w;
	int ch;

	vis_check();

	// Shortcut if audio isn't running
	if( !vis_get_playing()) {
		lua_newtable( L);
		for( i = 0; i < num_bars[0]; i++) {
			lua_pushinteger( L, 0);
			lua_rawseti( L, -2, i + 1);
		}

		lua_newtable( L);
		for( i = 0; i < num_bars[1]; i++) {
			lua_pushinteger( L, 0);
			lua_rawseti( L, -2, i + 1);
		}
		return 2;
	}

	// Init avg_power
	for( i = 0; i < (2 * num_subbands); i++) {
		avg_power[i] = 0;
	}

	for( w = 0; w < num_windows; w++) {
		kiss_fft_cpx fin_buf[MAX_SAMPLE_WINDOW];
		kiss_fft_cpx fout_buf[MAX_SAMPLE_WINDOW];

		int avg_ptr;
		int s;

		int16_t *ptr;
		size_t samples_until_wrap;

		int sample;

		int offs;
#if 0
// Test case
		{
			double freq = ( M_PI * 16) / 256;
			float ampl = ( (int) pow( 2, 16)) / 2;
			int i;

			for( i = 0; i < sample_window; i++) {
				fin_buf[i].r = ( ampl * (float) sin( i * freq)) + ( ampl * (float) cos( i * freq));
				fin_buf[i].i = ( ampl * (float) sin( i * freq)) + ( ampl * (float) cos( i * freq));
			}
		}
#else
		vis_lock();

		offs = vis_get_buffer_idx() - (sample_window * 2) - (sample_window * 2 * w);
		while (offs < 0) offs += vis_get_buffer_len();

		ptr = vis_get_buffer() + offs;
		samples_until_wrap = vis_get_buffer_len() - offs;

		for( i = 0; i < sample_window; i++) {
			sample = (*ptr++) >> 7;
			fin_buf[i].r = (float) (filter_window[i] * sample);

			sample = (*ptr++) >> 7;
			fin_buf[i].i = (float) (filter_window[i] * sample);

			samples_until_wrap -=2;
			if( samples_until_wrap <= 0) {
				ptr = vis_get_buffer();
				samples_until_wrap = vis_get_buffer_len();
			}
		}

		vis_unlock();
#endif

		kiss_fft( cfg, fin_buf, fout_buf);

		// Extract the two separate frequency domain signals
		// and keep track of the power per bin.
		avg_ptr = 0;
		for( s = 0; s < num_subbands; s++) {
			kiss_fft_cpx ck, cnk;

			float r = 0, i = 0;
			int x;

			for( x = decade_idx[s]; x < decade_idx[s] + decade_len[s]; x ++) {
				ck = fout_buf[x];
				cnk = fout_buf[sample_window - x];

				r = ( ck.r + cnk.r) / 2;
				i = ( ck.i - cnk.i) / 2;

				avg_power[avg_ptr] += ( r * r + i * i) / num_windows;

				r = ( cnk.i + ck.i) / 2;
				i = ( cnk.r - ck.r) / 2;

				avg_power[avg_ptr+1] += ( r * r + i * i) / num_windows;
			}
			avg_power[avg_ptr] /= decade_len[s];
			avg_power[avg_ptr+1] /= decade_len[s];

			avg_ptr += 2;
		}
	}


	{
		int pre_ptr = 0;
		int avg_ptr = 0;
		int p;

		for( p = 0; p < num_subbands; p++) {
			long product = (long) ( avg_power[avg_ptr] * preemphasis[pre_ptr]);
			product >>= 16;
			avg_power[avg_ptr++] = (int) product;

			product = (long) ( avg_power[avg_ptr] * preemphasis[pre_ptr]);
			product >>= 16;
			avg_power[avg_ptr++] = (int) product;

			pre_ptr++;
		}
	}

	for( ch = 0; ch < (( is_mono) ? 1 : 2); ch++) {
		int power_sum = 0;
		int in_bar = 0;
		int curr_bar = 0;

		int avg_ptr = ( ch == 0) ? 0 : 1;

		int s;

		for( s = 0; s < num_subbands; s++) {
			// Average out the power for all subbands represented
			// by a bar.
			power_sum += avg_power[avg_ptr] / subbands_in_bar[ch];

			if( is_mono) {
				power_sum += avg_power[avg_ptr + 1] / subbands_in_bar[ch];
			}

			if( ++in_bar == subbands_in_bar[ch]) {
				int val;
				int i;

				if( is_mono) {
					power_sum >>= 2;
				}

#if 0
				val = log(power_sum << 8) * 1.5;
				if (val > 31) val = 31;
#else
				power_sum <<= 6; // FIXME scaling

				val = 0;
				for( i = 31; i > 0; i--) {
					if( power_sum >= power_map[i]) {
						val = i;
						break;
					}
				}
#endif
				if( ch == 0) {
					sample_bin_ch0[curr_bar++] = val;
				}
				if( ch == 1) {
					sample_bin_ch1[curr_bar++] = val;
				}

//				printf( "*** ch: %d, curr_bar: %d, val: %d\n", ch, curr_bar, val);
//				curr_bar++;

				if( curr_bar == num_bars[ch]) {
					break;
				}

				in_bar = 0;
				power_sum = 0;
			}
			avg_ptr += 2;
		}
	}


	lua_newtable( L);
	for( i = 0; i < num_bars[0]; i++) {
		if( channel_flipped[0] == 0) {
			lua_pushinteger( L, sample_bin_ch0[i]);
		} else {
			lua_pushinteger( L, sample_bin_ch0[num_bars[0] - 1 - i]);
		}
		lua_rawseti( L, -2, i + 1);
	}

	lua_newtable( L);
	for( i = 0; i < num_bars[1]; i++) {
		if( channel_flipped[1] == 0) {
			lua_pushinteger( L, sample_bin_ch1[i]);
		} else {
			lua_pushinteger( L, sample_bin_ch1[num_bars[1] - 1 - i]);
		}
		lua_rawseti( L, -2, i + 1);
	}

	return 2;
}
