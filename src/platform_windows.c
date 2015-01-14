/*
** Copyright 2010 Logitech. All Rights Reserved.
**
** This file is licensed under BSD. Please see the LICENSE file for details.
*/


#include "common.h"
#include "jive.h"

#include <SDL_syswm.h>
#include <intrin.h>
#include <iphlpapi.h>
#include <ws2tcpip.h>

#ifndef WM_APPCOMMAND
#define WM_APPCOMMAND	0x0319
#endif

char *platform_get_home_dir() {
	char *dir;
	const char *home = getenv("APPDATA");

	dir = malloc(strlen(home) + strlen("\\Jivelite") + 1);
	strcpy(dir, home);
	strcat(dir, "\\Jivelite");

	return dir;
}

// find non loopback ip address to allow check for active network
char *platform_get_ip_address(void) {
	WSADATA wsa_Data;
	char hostname[NI_MAXHOST];
	struct hostent *host_entry;
	char *szLocalIP = NULL;

	if (WSAStartup(MAKEWORD(2,2), &wsa_Data) == 0)  
	{
		// Get the local hostname
		gethostname(hostname, NI_MAXHOST);

		host_entry = gethostbyname(hostname);

		szLocalIP = inet_ntoa (*(struct in_addr *)*host_entry->h_addr_list);

		WSACleanup();
	}

	return szLocalIP;
}

char *platform_get_mac_address() {
    WSADATA info; 
    struct hostent *phost;
    struct in_addr inaddr;
    IPAddr srcip;
    ULONG MacAddr[2];
    unsigned char *bMacAddr;
    ULONG PhyAddrLen = 6;
    char hostname[NI_MAXHOST];
    char *macaddr = NULL;

    srcip = 0;
    macaddr = malloc(18);

#if 0
    char *utmac;
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
#endif

    /* Set a fake macaddr to start, return fake instead of NULL on error */
    sprintf(macaddr, "01:02:03:04:05:06");

    if (WSAStartup(MAKEWORD(2,2), &info) == 0)
    {
        gethostname(hostname, NI_MAXHOST);

        phost = gethostbyname(hostname);

        inaddr.S_un.S_addr = *((unsigned long*) phost->h_addr);

        SendARP((IPAddr) inaddr.S_un.S_addr, srcip , MacAddr , &PhyAddrLen);

        bMacAddr = (unsigned char *) &MacAddr;

        if (PhyAddrLen)
            sprintf(macaddr, "%02x:%02x:%02x:%02x:%02x:%02x",*bMacAddr,
                *(bMacAddr+1),*(bMacAddr+2),*(bMacAddr+3),*(bMacAddr+4),*(bMacAddr+5));

        WSACleanup();
    }

    return macaddr;
}

static int windows_filter_pump(const SDL_Event *event) {
	//handle multimedia button events
	if (event->type == SDL_SYSWMEVENT)
	{
		SDL_SysWMmsg *wmmsg;
		wmmsg = event->syswm.msg;
		
		if (wmmsg->msg == WM_APPCOMMAND) {
			switch (GET_APPCOMMAND_LPARAM(wmmsg->lParam)) {
				case APPCOMMAND_MEDIA_NEXTTRACK:
					jive_send_key_event(JIVE_EVENT_KEY_PRESS, JIVE_KEY_FWD, jive_jiffies());
					return 0; // return non-zero, because we have handled the message (see MSDN doc)
				case APPCOMMAND_MEDIA_PREVIOUSTRACK:
					jive_send_key_event(JIVE_EVENT_KEY_PRESS, JIVE_KEY_REW, jive_jiffies());
					return 0;
				case APPCOMMAND_MEDIA_PLAY_PAUSE:
					jive_send_key_event(JIVE_EVENT_KEY_PRESS, JIVE_KEY_PAUSE, jive_jiffies());
					return 0;
				case APPCOMMAND_VOLUME_DOWN:
					jive_send_key_event(JIVE_EVENT_KEY_DOWN, JIVE_KEY_VOLUME_DOWN, jive_jiffies());
					jive_send_key_event(JIVE_EVENT_KEY_UP, JIVE_KEY_VOLUME_DOWN, jive_jiffies());
					return 0;
				case APPCOMMAND_VOLUME_UP:
					jive_send_key_event(JIVE_EVENT_KEY_DOWN, JIVE_KEY_VOLUME_UP, jive_jiffies());
					jive_send_key_event(JIVE_EVENT_KEY_UP, JIVE_KEY_VOLUME_UP, jive_jiffies());
					return 0;
				//todo: APPCOMMAND_MEDIA_STOP or JIVE_KEY_VOLUME_UP - do anything for these?
				default : break;
			}
		}
    }
	return 1;
}

char *platform_get_arch() {
    // FIXME
    return "unknown";
}

int watchdog_get() {
	return -1;
}

int watchdog_keepalive(int watchdog_id, int count) {
	return -1;
}

void platform_init(lua_State *L) {
	jive_sdlfilter_pump = windows_filter_pump;
}
