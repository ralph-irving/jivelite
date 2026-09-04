/*
** Verify that DNS workers are joined before the application clock is stopped.
*/

#include <assert.h>
#include <stdio.h>

#include "common.h"
#include "lualib.h"

#ifdef main
#undef main
#endif

int luaopen_jive_net_dns(lua_State *L);

static void run_dns_lifecycle(bool fill_send_buffer)
{
	lua_State *L = luaL_newstate();
	const char *script;
	int status;

	assert(L != NULL);
	luaL_openlibs(L);
	luaopen_jive_net_dns(L);

	script = fill_send_buffer ?
		"dns_worker = jive.dns.open()\n"
		"dns_worker:write('__jive_dns_fill_send_buffer__')\n" :
		"dns_worker = jive.dns.open()\n";
	status = luaL_dostring(L, script);
	if (status != 0) {
		fprintf(stderr, "%s\n", lua_tostring(L, -1));
	}
	assert(status == 0);

	/* Let the worker block in recv(), or fill its reply socket and send(). */
	SDL_Delay(fill_send_buffer ? 50 : 1);

	/* lua_close() collects the userdata and must join its worker. */
	lua_close(L);
}

int main(int argc, char **argv)
{
	int i;

	(void)argc;
	(void)argv;
	assert(SDL_Init(SDL_INIT_TIMER) == 0);
	assert(jive_time_init());

	for (i = 0; i < 100; i++) {
		run_dns_lifecycle(false);
	}
	for (i = 0; i < 10; i++) {
		run_dns_lifecycle(true);
	}

	/* The clock must remain usable after every DNS worker has terminated. */
	(void)jive_jiffies();
	jive_time_quit();
	SDL_Quit();

	puts("DNS shutdown tests passed");
	return 0;
}
