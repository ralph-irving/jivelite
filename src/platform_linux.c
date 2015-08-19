/*
** Copyright 2010 Logitech. All Rights Reserved.
**
** This file is licensed under BSD. Please see the LICENSE file for details.
*/

#ifndef __APPLE__

#include "common.h"
#include "version.h"
#include "jive.h"

#include <errno.h>
#include <signal.h>
#include <syslog.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/utsname.h>
#include <sys/types.h>
#include <sys/ipc.h>
#include <sys/sem.h>
#include <netinet/in.h>
#include <linux/if.h>
#include <execinfo.h>


char *platform_get_home_dir() {
    char *dir;
    const char *home = getenv("HOME");

    dir = malloc(strlen(home) + 11);
    strcpy(dir, home);
    strcat(dir, "/.jivelite");

    return dir;
}

// search first 4 interfaces returned by IFCONF - same method used by squeezelite
char *platform_get_mac_address() {
    struct ifconf ifc;
    struct ifreq *ifr, *ifend;
    struct ifreq ifreq;
    struct ifreq ifs[4];
    char *utmac;
    u8_t mac[6];

    mac[0] = mac[1] = mac[2] = mac[3] = mac[4] = mac[5] = 0;

    int s = socket(AF_INET, SOCK_DGRAM, 0);
 
    ifc.ifc_len = sizeof(ifs);
    ifc.ifc_req = ifs;

    if (ioctl(s, SIOCGIFCONF, &ifc) == 0) {
		ifend = ifs + (ifc.ifc_len / sizeof(struct ifreq));

		for (ifr = ifc.ifc_req; ifr < ifend; ifr++) {
			if (ifr->ifr_addr.sa_family == AF_INET) {

				strncpy(ifreq.ifr_name, ifr->ifr_name, sizeof(ifreq.ifr_name));
				if (ioctl (s, SIOCGIFHWADDR, &ifreq) == 0) {
					memcpy(mac, ifreq.ifr_hwaddr.sa_data, 6);
					if (mac[0]+mac[1]+mac[2] != 0) {
						break;
					}
				}
			}
		}
	}

    close(s);

    char *macaddr = malloc(18);

    utmac = getenv("UTMAC");
    if (utmac)
    {
        if ( strlen(utmac) == 17 )
        {
            sscanf(utmac,"%2hhx:%2hhx:%2hhx:%2hhx:%2hhx:%2hhx", &mac[0],&mac[1],&mac[2],&mac[3],&mac[4],&mac[5]);
        }
    }

    sprintf(macaddr, "%02x:%02x:%02x:%02x:%02x:%02x", mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);

	return macaddr;
}

// find non loopback ip address to allow check for active network
char *platform_get_ip_address(void) {
    struct ifconf ifc;
    struct ifreq *ifr, *ifend;
    struct ifreq ifreq;
    struct ifreq ifs[4];
	struct in_addr addr;
	
	int found = 0;
    int s = socket(AF_INET, SOCK_DGRAM, 0);
	
	memset(&addr, 0, sizeof(addr));
	
    ifc.ifc_len = sizeof(ifs);
    ifc.ifc_req = ifs;
	
    if (ioctl(s, SIOCGIFCONF, &ifc) == 0) {
		ifend = ifs + (ifc.ifc_len / sizeof(struct ifreq));
		
		for (ifr = ifc.ifc_req; ifr < ifend; ifr++) {
			if (ifr->ifr_addr.sa_family == AF_INET) {
				
				strncpy(ifreq.ifr_name, ifr->ifr_name, sizeof(ifreq.ifr_name));
				if (ioctl (s, SIOCGIFADDR, &ifreq) == 0) {
					addr = ((struct sockaddr_in *)&ifreq.ifr_addr)->sin_addr;
					if (addr.s_addr != 0x0100007f) { // ignore loopback address (fix endian?)
						found = 1;
						break;
					}
				}
			}
		}
	}
	
	close(s);
	
	return found ? inet_ntoa(addr) : NULL;
}

char *platform_get_arch() {
    struct utsname name;
    char *arch;

    uname(&name);

    arch = strdup(name.machine);
    return arch;
}


static LOG_CATEGORY *log_sp;
static lua_State *Lsig = NULL;
static lua_Hook Hf = NULL;
static int Hmask = 0;
static int Hcount = 0;


static void print_trace(void)
{
	void *array[50];
	size_t size;
	char **strings;
	size_t i;
	int mapfd;

	/* backtrace */
	size = backtrace(array, sizeof(array));
	strings = backtrace_symbols(array, size);

	log_category_log(log_sp, LOG_PRIORITY_INFO, "Backtrack:");

	for (i = 0; i < size; i++) {
		log_category_log(log_sp, LOG_PRIORITY_INFO, "%s", strings[i]);
	}

	free(strings);

	/* link map */
	mapfd = open("/proc/self/maps", O_RDONLY);
	if (mapfd != -1) {
		char buf[256];
		char *ptr, *str, *end;
		ssize_t n, offset;

		log_category_log(log_sp, LOG_PRIORITY_INFO, "Memory map:");

		offset = 0;
		while ((n = read(mapfd, buf + offset, sizeof(buf) - offset)) > 0) {
			str = ptr = buf;
			end = buf + n + offset;

			while (ptr < end) {
				while (ptr < end && *ptr != '\n') ptr++;

				if (ptr < end) {
					log_category_log(log_sp, LOG_PRIORITY_INFO, "%.*s", ptr-str, str);
					ptr++;
					str = ptr;
				}
			}

			offset = end - str;
			memmove(buf, str, offset);
		}
		close (mapfd);
	}
}


static void quit_hook(lua_State *L, lua_Debug *ar) {
	/* set the old hook */
	lua_sethook(L, Hf, Hmask, Hcount);

	/* stack trace */
	lua_getglobal(L, "debug");
	lua_getfield(L, -1, "traceback");
	lua_call(L, 0, 1);

	log_sp = LOG_CATEGORY_GET("jivelite");

	LOG_WARN(log_sp, "%s", lua_tostring(L, -1));
}


static void quit_handler(int signum) {
	LOG_ERROR(log_sp, "SIGQUIT jivelite %s", JIVE_VERSION);
	print_trace();

	Hf = lua_gethook(Lsig);
	Hmask = lua_gethookmask(Lsig);
	Hcount = lua_gethookcount(Lsig);

	/* set handler hook */
	lua_sethook(Lsig, quit_hook, LUA_MASKCALL | LUA_MASKRET | LUA_MASKLINE, 0);
}


static void segv_handler(int signum) {
	struct sigaction sa;

	sa.sa_handler = SIG_DFL;
	sigemptyset(&sa.sa_mask);
	sa.sa_flags = 0;
	sigaction(signum, &sa, NULL);

	LOG_ERROR(log_sp, "SIGSEGV jivelite %s", JIVE_VERSION);
	print_trace();

	/* dump core */
	raise(signum);
}


void platform_init(lua_State *L) {
	struct sigaction sa;

	Lsig = L;
	log_sp = LOG_CATEGORY_GET("jivelite");


	sigemptyset(&sa.sa_mask);
	sa.sa_flags = SA_RESTART;

	sa.sa_handler = quit_handler;
	sigaction(SIGQUIT, &sa, NULL);

	sa.sa_handler = segv_handler;
	sigaction(SIGSEGV, &sa, NULL);
}

#endif
