/*
** Copyright 2010 Logitech. All Rights Reserved.
**
** This file is licensed under BSD. Please see the LICENSE file for details.
*/

#ifdef sun

#include "common.h"
#include "jive.h"

#include <sys/types.h>
#include <stdio.h>
#include <time.h>
#include <string.h>
#include <unistd.h>
#include <stdlib.h>
#include <sys/utsname.h>

#include <netdb.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/sockio.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <net/if.h>
#include <net/if_arp.h>
#include <net/if_dl.h>
#include <net/if_types.h>

#define PREF_DIR "/.jivelite"

char *platform_get_home_dir() {
    char *dir;
    const char *home = getenv("HOME");

    dir = malloc(strlen(home) + strlen(PREF_DIR) + 1);
    strcpy(dir, home);
    strcat(dir, PREF_DIR);

    return dir;
}

char *platform_get_mac_address()
{
	struct  arpreq          parpreq;
	struct  sockaddr_in     *psa;
	struct  in_addr         inaddr;
	struct  hostent         *phost;
	char                    hostname[MAXHOSTNAMELEN];
	char                    **paddrs;
	int			sock;
	char 			*macaddr = NULL;
	char 			*utmac;
	int			status=0;

	macaddr = malloc(18);

	utmac = getenv("UTMAC");
	if (utmac)
	{
		if ( strlen(utmac) == 17 )
		{
			strncpy ( macaddr, utmac, 17 );
			macaddr[17] = '\0';
			return macaddr;
		}
	}

	/* Set a fake macaddr to start, return fake instead of NULL on error */
	sprintf(macaddr, "00:00:00:00:99:01");

	gethostname(hostname,  MAXHOSTNAMELEN);

	phost = gethostbyname(hostname);

	paddrs = phost->h_addr_list;
	memcpy(&inaddr.s_addr, *paddrs, sizeof(inaddr.s_addr));

	sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);

	if ( sock == -1 ) {
                return macaddr;
	}

	memset(&parpreq, 0, sizeof(struct arpreq));
	psa = (struct sockaddr_in *) &parpreq.arp_pa;
	memset(psa, 0, sizeof(struct sockaddr_in));
	psa->sin_family = AF_INET;
	memcpy(&psa->sin_addr, *paddrs, sizeof(struct in_addr));

	status = ioctl(sock, SIOCGARP, &parpreq);

	if ( status == -1 ) {
		return macaddr;
	}

        sprintf(macaddr, "%02x:%02x:%02x:%02x:%02x:%02x",
                (unsigned char) parpreq.arp_ha.sa_data[0],
                (unsigned char) parpreq.arp_ha.sa_data[1],
                (unsigned char) parpreq.arp_ha.sa_data[2],
                (unsigned char) parpreq.arp_ha.sa_data[3],
                (unsigned char) parpreq.arp_ha.sa_data[4],
                (unsigned char) parpreq.arp_ha.sa_data[5]);

	return macaddr;
}

/* find non loopback ip address to allow check for active network */
char *platform_get_ip_address(void) {
	return NULL;
}

char *platform_get_arch() {
    struct utsname name;
    char *arch;

    uname(&name);

    arch = strdup(name.machine);
    return arch;
}

int watchdog_get() {
	return -1;
}

int watchdog_keepalive(int watchdog_id, int count) {
	return -1;
}

void platform_init(lua_State *L) {
}

#endif
