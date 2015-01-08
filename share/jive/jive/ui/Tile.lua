
--[[
=head1 NAME

jive.ui.Tile - A tiled image.

=head1 DESCRIPTION

A tiled image used to fill an area.

=head1 SYNOPSIS

 -- Fill with a transparnet red
 local tile = jive.ui.Tile:fillColor(0xff00007f)

 -- Horizontal bar filled with images
 tile = Tile:loadHTiles({
				"iconbar_l.png",
				"iconbar.png",
				"iconbar_r.png",
			})
 -- Blit tile


=head1 METHODS

=head2 jive.ui.Tile:fillColor(color)

Create a tile with a fill colour.

=head2 jive.ui.Tile:loadImage(path)

Create a tile with a single image, this is repeated to fill the area if required.

=head2 jive.ui.Tile:loadImageData(data, len)

Create a tile using image from I<data> using I<len> bytes. Returns the tile.

=head2 jive.ui.Tile:loadTiles({ p1, p2, p3, p4, p5, ... })

Create a rectangular tile with nine images:

 ----------------
 | p2 | p3 | p4 |
 ----------------
 | p9 | p1 | p5 |
 ----------------
 | p8 | p7 | p6 |
 ----------------


=head2 jive.ui.Tile:loadVTiles({ p1, p2, p3 })

Create a vertical tile with three images:

 ------
 | p1 |
 ------
 | p2 |
 ------
 | p3 |
 ------

=head2 jive.ui.Tile:loadHTiles({ p1, p2, p3 })

Create a horizontal tile with three images:

 ----------------
 | p1 | p2 | p3 |
 ----------------

=head2 tile:blit(srf, x, y, w, h)

Blit the tile to surface at I<x, y>, the area I<w, h> is filled.

=head2 tile:getMinSize()

Returns the minimum I<width>,I<height> the tile can be painted.

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
