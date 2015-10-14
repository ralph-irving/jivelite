/* CopyResampled routine adapted from libgd 

Adapted from libgd code with the following copyright:

     Portions copyright 1994, 1995, 1996, 1997, 1998, 1999, 2000, 2001,
     2002 by Cold Spring Harbor Laboratory. Funded under Grant
     P41-RR02188 by the National Institutes of Health. 

     Portions copyright 1996, 1997, 1998, 1999, 2000, 2001, 2002 by
     Boutell.Com, Inc. 

     Portions relating to GD2 format copyright 1999, 2000, 2001, 2002
     Philip Warner.
     
     Portions relating to PNG copyright 1999, 2000, 2001, 2002 Greg
     Roelofs. 

     Portions relating to gdttf.c copyright 1999, 2000, 2001, 2002 John  
     Ellson (ellson@lucent.com).
   
     Portions relating to gdft.c copyright 2001, 2002 John Ellson  
     (ellson@lucent.com).  

     Portions copyright 2000, 2001, 2002, 2003, 2004, 2005, 2006, 2007
		 2008 Pierre-Alain Joye (pierre@libgd.org).  

     Portions relating to JPEG and to color quantization copyright 2000,
     2001, 2002, Doug Becker and copyright (C) 1994, 1995, 1996, 1997,
     1998, 1999, 2000, 2001, 2002, Thomas G. Lane. This software is
     based in part on the work of the Independent JPEG Group. See the
     file README-JPEG.TXT for more information.

     Portions relating to WBMP copyright 2000, 2001, 2002 Maurice
     Szmurlo and Johan Van den Brande.

     Permission has been granted to copy, distribute and modify gd in
     any context without fee, including a commercial application,
     provided that this notice is present in user-accessible supporting
     documentation.

     This does not affect your ownership of the derived work itself, and 
     the intent is to assure proper credit for the authors of gd, not to
     interfere with your productive use of gd. If you have questions,
     ask. "Derived works" includes all programs that utilize the   
     library. Credit must be given in user-accessible documentation.

     This software is provided "AS IS." The copyright holders disclaim  
     all warranties, either express or implied, including but not
     limited to implied warranties of merchantability and fitness for a
     particular purpose, with respect to this code and accompanying  
     documentation.

     Although their code does not appear in gd, the authors wish to thank
     David Koblas, David Rowley, and Hutchison Avenue Software Corporation
     for their prior contributions.

*/


#include "common.h"
#include "jive.h"


#define floor2(exp) ((long) exp)

// NB - this assumes 4 bytes per pixel at present and does nothing in other cases

void copyResampled (SDL_Surface *dst, SDL_Surface *src, 
					int dstX, int dstY, int srcX, int srcY,
					int dstW, int dstH, int srcW, int srcH) {
	int x, y;
	double sy1, sy2, sx1, sx2;
	Uint8 bpp;

	bpp = src->format->BytesPerPixel;

	if ((bpp != 4 && bpp != 2) || dst->format->BytesPerPixel != 4) {
		LOG_ERROR(log_ui, "Unsupported BytesPerPixel: src:%d dst:%d", src->format->BytesPerPixel, dst->format->BytesPerPixel);
		return;
	}

	for (y = dstY; (y < dstY + dstH); y++) {
		sy1 = ((double) y - (double) dstY) * (double) srcH / (double) dstH;
		sy2 = ((double) (y + 1) - (double) dstY) * (double) srcH / (double) dstH;

		for (x = dstX; (x < dstX + dstW); x++) {
			double sx, sy;
			double spixels = 0;
			double red = 0.0, green = 0.0, blue = 0.0, alpha = 0.0;
			sx1 = ((double) x - (double) dstX) * (double) srcW / dstW;
			sx2 = ((double) (x + 1) - (double) dstX) * (double) srcW / dstW;
			sy = sy1;

			do {
				double yportion;
				if (floor2 (sy) == floor2 (sy1)) {
					yportion = 1.0 - (sy - floor2 (sy));
					if (yportion > sy2 - sy1) {
						yportion = sy2 - sy1;
					}
					sy = floor2 (sy);
				} else if (sy == floor2 (sy2)) {
					yportion = sy2 - floor2 (sy2);
				} else {
					yportion = 1.0;
				}
				sx = sx1;

				do {
					double xportion;
					double pcontribution;
					Uint8 R, G, B, A;
					Uint32 pixel;

					if (floor2 (sx) == floor2 (sx1)) {
						xportion = 1.0 - (sx - floor2 (sx));
						if (xportion > sx2 - sx1) {
							xportion = sx2 - sx1;
						}
						sx = floor2 (sx);
					} else if (sx == floor2 (sx2)) {
						xportion = sx2 - floor2 (sx2);
					} else {
						xportion = 1.0;
					}
					pcontribution = xportion * yportion;

					pixel = bpp == 2
						? *((Uint16 *)src->pixels + ((int) sy + srcY) * src->pitch / bpp + ((int) sx + srcX))
						: *((Uint32 *)src->pixels + ((int) sy + srcY) * src->pitch / bpp + ((int) sx + srcX));

					SDL_GetRGBA(pixel, src->format, &R, &G, &B, &A);

					red   += R * pcontribution;
					green += G * pcontribution;
					blue  += B * pcontribution;
					alpha += A * pcontribution;
					spixels += xportion * yportion;
					sx += 1.0;
				} while (sx < sx2);

				sy += 1.0;

			} while (sy < sy2);

			if (spixels != 0.0) {
				red /= spixels;
				green /= spixels;
				blue /= spixels;
				alpha /= spixels;
			}

			if (red > 255.0) {
				red = 255.0;
			}
			if (green > 255.0) {
				green = 255.0;
			}
			if (blue > 255.0) {
				blue = 255.0;
			}
			if (alpha > 255.0) {
				alpha = 255.0;
			}

			*((Uint32 *)dst->pixels + y * dst->pitch / 4 + x) = 
				SDL_MapRGBA(dst->format, (Uint8)red, (Uint8)green, (Uint8)blue, (Uint8)alpha);
		}
	}
}
