
--[[
=head1 NAME

applets.ImageViewer.ImageSourceCard - use SD card as image source for Image Viewer

=head1 DESCRIPTION

Finds images from SD card

=head1 FUNCTIONS

Applet related methods are described in L<jive.Applet>. 

=cut
--]]


-- stuff we use
local oo        = require("loop.simple")
local io        = require("io")
local string    = require("jive.utils.string")
local log       = require("jive.utils.log").logger("applet.ImageViewer")
local lfs       = require("lfs")

local require   = require
local ImageSourceLocalStorage = require("applets.ImageViewer.ImageSourceLocalStorage")

module(...)
ImageSourceCard = oo.class(_M, ImageSourceLocalStorage)

function getFolder(self)
	return self:_getFolder("(/media/mmc%w*)")
end

function _getFolder(self, pattern)
	local mounts = io.open("/proc/mounts", "r")
	local path
	
	if mounts == nil then
		log:error("/proc/mounts could not be opened")
		return
	end

	for line in mounts:lines() do
		local mountPoint = string.match(line, pattern)
		if mountPoint and lfs.attributes(mountPoint, "mode") == "directory" then
			log:debug('Mounted drive found at ', mountPoint)
			self.applet:getSettings()["card.path"] = mountPoint
			path = mountPoint
			break
		end
	end
	mounts:close()
	
	return path
end

-- if user decides to change path manually, switch to "card" mode
-- with this media as default path
function settings(self, window)
	local imgpath = self:getFolder() or "/media"
	self.applet:getSettings()["card.path"] = imgpath
	
	return oo.superclass(ImageSourceCard).settings(self, window)
end

--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.


=cut
--]]

