/* Public domain. */

//#include "uint32.h"
//#include "bytestr.h"
#include "md5.h"
#include "md5_internal.h"

void md5_update (MD5Schedule_ref ctx, char const *s, unsigned int len)
{
  register uint32 t = ctx->bits[0] ;
  if ((ctx->bits[0] = t + (len << 3)) < t)
    ctx->bits[1]++ ;
  ctx->bits[1] += len >> 29 ;
  t = (t >> 3) & 0x3f ;
  if (t)
  {
    unsigned char *p = ctx->in + t ;
    t = 64 - t ;
    if (len < t)
    {
      memmove((char *)p, s, len) ;
      return ;
    }
    memmove((char *)p, s, t) ;
    uint32_little_endian(ctx->in, 16) ;
    md5_transform(ctx->buf, (uint32 *)ctx->in) ;
    s += t ; len -= t ;
  }
  while (len >= 64)
  {
    memmove((char *)ctx->in, s, 64) ;
    uint32_little_endian(ctx->in, 16) ;
    md5_transform(ctx->buf, (uint32 *)ctx->in) ;
    s += 64 ; len -= 64 ;
  }
  memmove((char *)ctx->in, s, len) ;
}
