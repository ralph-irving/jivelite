
--[[
=head1 NAME

jive.ui.Surface - A graphic surface

=head1 DESCRIPTION

A graphic surface. Can be used for drawing or images.

All colors used in the api are given as 32bit RGBA values.

=head1 SYNOPSIS

 -- Drawing
 local srf = jive.ui.Surface:newRGBA(100, 100)
 srf:rectangle(10, 10, 90, 90, 0xFFFFFFFF)

 -- Images
 local img = jive.ui.Surface:loadImage("example.png")

=head1 METHODS

=head2 newRGB(w, h)

Constructs a new RGB surface of width and height I<w> and I<h>.

=head2 newRGBA(w, h)

Constructs a new RGBA surface of width and height I<w> and I<h>. The surface is filled with transparency.

=head2 loadImage(path)

Load an image from I<path>. If I<path> is relative the lua path is searched for the image. Returns the loaded image.

=head2 loadImageData(data, len)

Load an image from I<data> using I<len> bytes. Returns the loaded image.

=head2 drawText(font, color, str)

Draw text I<str> in font I<font>, in color I<color>. Returns a new surface containing the text.

=head2 setOffset(x, y)

Sets a surface offset. This offset is used by all blitting and drawing methods.

=head2 setClip(x, y, w, h)

Sets I<x, y, w, h> as the surface clip rectangle. This offset is used by all blitting and drawing methods.

=head2 getClip()

Returns I<x, y, w, h> the surface clip rectangle.

=head2 blit(dst, dx, dy)

Blits this surface to the I<dst> surface at I<dx, dy>.

=head2 blitClip(sx, sy, sw, sh, dst, dx, dy)

Blits a subset this surface I<sx, sy, sw, sh> to the I<dst> surface at I<dx, dy>.

=head2 blitAlpha(dst, dx, dy, alpha)

Blits this surface to the I<dst> surface at I<dx, dy> using a per surface alpha value. Only works with RGB surfaces.

=head2 getSize()

Returns I<w, h>, the surface size.

=head2 release()

Free the wrapped surface object. This can be useful if temporary surfaces are created frequently (such as when using rotozoom), Lua has
  garbage collection that will eventually free it, but since Lua does not realize the size of the data, it make the gc of it a low priority.
  This can lead to an OOM error, so it prudent to use release when working with any temporary surface. 

=back

=head1 DRAWING METHODS

The following methods are from the SDL_gfx package. See L<http://www.ferzkopp.net/joomla/content/view/19/14/> for more details.

=over

=head2 rotozoom(angle, zoom, smooth)

=head2 zoom(zoomx, zoomy, smooth)

=head2 shrink(factorx, factory)

=head2 pixel(x, y, color)

=head2 hline(x1, x2, y, color)

=head2 vline(x, y1, y2, color)

=head2 rectangle(x1, y1, x2, y2, color)

=head2 filledRectangle(x1, y1, x2, y2, color)

=head2 line(x1, y1, x2, y2, color)

=head2 aaline(x1, y1, x2, y2, color)

=head2 circle(x, y, r, color)

=head2 aacircle(x, y, r, color)

=head2 filledCircle(x, y, r, color)

=head2 ellipse(x, y, rx, ry, color)

=head2 aaellipse(x, y, rx, ry, color)

=head2 filledEllipse(x, y, rx, ry, color)

=head2 pie(x, y, rad, start, end, color)

=head2 filledPie(x, y, rad, start, end, color)

=head2 trigon(x1, y1, x2, y2, x3, y3, color)

=head2 aatrigon(x1, y1, x2, y2, x3, y3, color)

=head2 filledTrigon(x1, y1, x2, y2, x3, y3, color)

=cut
--]]

-- C implementation

local oo = require("loop.base")

module(..., oo.class)

--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

