/* Public domain. */

//#include "uint32.h"
//#include "bytestr.h"
#include "md5.h"
#include "md5_internal.h"

void md5_final (MD5Schedule_ref ctx, char *digest /* 16 chars */)
{
  register unsigned int count = (ctx->bits[0] >> 3) & 0x3F ;
  register unsigned char *p = ctx->in + count ;
  *p++ = 0x80;
  count = 63 - count ;
  if (count < 8)
  {
    memset(p, 0, count) ;
    uint32_little_endian(ctx->in, 16) ;
    md5_transform(ctx->buf, (uint32 *)ctx->in) ;
    memset(ctx->in, 0, 56) ;
  }
  else memset(p, 0, count - 8) ;
  uint32_little_endian(ctx->in, 14) ;

  ((uint32 *)ctx->in)[14] = ctx->bits[0] ;
  ((uint32 *)ctx->in)[15] = ctx->bits[1] ;

  md5_transform(ctx->buf, (uint32 *)ctx->in) ;
  uint32_little_endian((char *)ctx->buf, 4) ;
  memmove(digest, (char *)ctx->buf, 16) ;
}
