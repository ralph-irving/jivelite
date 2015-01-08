/* Public domain. */

//#include "uint32.h"
//#include "bytestr.h"
#include "common.h"

void uint32_pack_big (char *s, uint32 u)
{
  ((unsigned char *)s)[3] = T8(u) ; u >>= 8 ;
  ((unsigned char *)s)[2] = T8(u) ; u >>= 8 ;
  ((unsigned char *)s)[1] = T8(u) ; u >>= 8 ;
  ((unsigned char *)s)[0] = T8(u) ;
}
