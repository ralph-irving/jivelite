
--[[
=head1 NAME

applets.ImageViewer.ImageSourceUSB - use USB disk as image source for Image Viewer

=head1 DESCRIPTION

Finds images from USB media

=head1 FUNCTIONS

Applet related methods are described in L<jive.Applet>. 

=cut
--]]


-- stuff we use
local oo        = require("loop.simple")
local log       = require("jive.utils.log").logger("applet.ImageViewer")

local require   = require
local ImageSourceCard = require("applets.ImageViewer.ImageSourceCard")

module(...)
ImageSourceCard = oo.class(_M, ImageSourceCard)

function getFolder(self)
	return self:_getFolder("(/media/sd%w*)")
end

--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.


=cut
--]]

