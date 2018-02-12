#include "../common.h"
#include "../jive.h"

#include <pthread.h>

#include <stdio.h>
#include <sys/mman.h>

#define VIS_BUF_SIZE 16384

static struct vis_t {
	pthread_rwlock_t rwlock;
	u32_t buf_size;
	u32_t buf_index;
	bool running;
	u32_t rate;
	time_t updated;
	s16_t buffer[VIS_BUF_SIZE];
} * vis_mmap = NULL;

static bool running = false; // cached version of running so now playing status can be read without lock
static int vis_fd = -1;
static char *mac_address = NULL;

static void _reopen(void) {
	char shm_path[40];

	if (vis_mmap) {
		munmap(vis_mmap, sizeof(struct vis_t));
		vis_mmap = NULL;
	}

	if (vis_fd != -1) {
		close(vis_fd);
		vis_fd = -1;
	}

	if (!mac_address) {
		mac_address = platform_get_mac_address();
	}

	sprintf(shm_path, "/squeezelite-%s", mac_address ? mac_address : "");

	vis_fd = shm_open(shm_path, O_RDWR, 0666);
	if (vis_fd > 0) {
		vis_mmap = mmap(NULL, sizeof(struct vis_t), PROT_READ | PROT_WRITE, MAP_SHARED, vis_fd, 0);
		if (vis_mmap == MAP_FAILED) {
			close(vis_fd);
			vis_fd = -1;
			vis_mmap = NULL;
		}
	}
}

// check status of mmap, attempt to open or reopen if it has not been updated recently
// this allows squeezelite to be restarted and to map a different block of memory
void vis_check(void) {
	static time_t lastopen = 0;
	time_t now = time(NULL);

	if (!vis_mmap) {
		if (now - lastopen > 5) {
			_reopen();
			lastopen = now;
		}
		if (!vis_mmap) return;
	}

	pthread_rwlock_rdlock(&vis_mmap->rwlock);

	running = vis_mmap->running;

	if (running && now - vis_mmap->updated > 5) {
		pthread_rwlock_unlock(&vis_mmap->rwlock);
		_reopen();
		lastopen = now;
	} else {
		pthread_rwlock_unlock(&vis_mmap->rwlock);
	}
}

void vis_lock(void) {
	if (!vis_mmap) return;
	pthread_rwlock_rdlock(&vis_mmap->rwlock);
}

void vis_unlock(void) {
	if (!vis_mmap) return;
	pthread_rwlock_unlock(&vis_mmap->rwlock);
}

bool vis_get_playing(void) {
	if (!vis_mmap) return false;
	return running;
}

u32_t vis_get_rate(void) {
	if (!vis_mmap) return 0;
	return vis_mmap->rate;
}

s16_t *vis_get_buffer(void) {
	if (!vis_mmap) return NULL;
	return vis_mmap->buffer;
}

u32_t vis_get_buffer_len(void) {
	if (!vis_mmap) return 0;
	return vis_mmap->buf_size;
}

u32_t vis_get_buffer_idx(void) {
	if (!vis_mmap) return 0;
	return vis_mmap->buf_index;
}

extern int visualizer_spectrum_init(lua_State *L);
extern int visualizer_spectrum(lua_State *L);
extern int visualizer_vumeter(lua_State *L);

static const struct luaL_Reg visualizer_f[] = {
	{ "vumeter", visualizer_vumeter },
	{ "spectrum", visualizer_spectrum },
	{ "spectrum_init", visualizer_spectrum_init },
	{ NULL, NULL }
};

int luaopen_visualizer(lua_State *L) {
	lua_getglobal(L, "jive");

	/* register lua functions */
	lua_newtable(L);
	luaL_register(L, NULL, visualizer_f);
	lua_setfield(L, -2, "vis");

	return 0;
}

