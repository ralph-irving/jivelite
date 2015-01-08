/* Public domain. */

#ifndef SHA1_INTERNAL_H
#define SHA1_INTERNAL_H

#include "sha1.h"

extern void sha1_feed (SHA1Schedule_ref, unsigned char) ;
extern void sha1_transform (uint32 * /* 5 uint32s */, uint32 const * /* 16 uint32s */) ;

#endif
