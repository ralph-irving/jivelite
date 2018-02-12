
--[[
=head1 NAME

applets.Screenshot.ScreenshotApplet - Screenshot, press and hole Pause and Rew to take a screenshot.

=head1 DESCRIPTION

This applet saves screenshots as bmp files using a key combination to lock the Jive screen.

=head1 FUNCTIONS

Applet related methods are described in L<jive.Applet>. 
ScreenshotApplet overrides the following methods:

=cut
--]]


-- stuff we use
local oo               = require("loop.simple")
local string           = require("string")
local lfs              = require("lfs")

local Applet           = require("jive.Applet")
local Framework        = require("jive.ui.Framework")
local Group            = require("jive.ui.Group")
local Label            = require("jive.ui.Label")
local Popup            = require("jive.ui.Popup")
local Surface          = require("jive.ui.Surface")
local System           = require("jive.System")
local Window           = require("jive.ui.Window")


local JIVE_LAYER_ALL   = jive.ui.JIVE_LAYER_ALL


module(..., Framework.constants)
oo.class(_M, Applet)


local function _takeScreenshotAction(self)
	Framework:playSound("CLICK")

	-- write to userpath or /tmp/jiveliteXXXX.bmp
	local path = System.getUserDir()

	-- use /tmp instead, if it exists
        if lfs.attributes("/tmp", "mode") == "directory" then
		path = "/tmp"
	end

	-- disable old squeezeplay behaviour writing to /media
	-- if lfs.attributes("/media", "mode") ~= nil then
	-- 	for dir in lfs.dir("/media") do
	-- 		if not string.match(dir, "^%.") then
	-- 			local tmp = "/media/" .. dir 
	-- 			if lfs.attributes(tmp, "mode") == "directory" then
	-- 				path = tmp
	-- 				break
	-- 			end
	-- 		end
	-- 	end
	-- end

	local file = path .. string.format("/jivelite%04d.bmp", self.number)
	self.number = self.number + 1
	
	log:warn("Taking screenshot " .. file)

	-- take screenshot
	local sw, sh = Framework:getScreenSize()

	local window = Framework.windowStack[1]
	local bg = Framework.getBackground()

	local srf = Surface:newRGB(sw, sh)
	bg:blit(srf, 0, 0, sw, sh)
	window:draw(srf, JIVE_LAYER_ALL)

	srf:saveBMP(file)

	local popup = Popup("toast_popup")
	local group = Group("group", {
                text = Label("text", self:string("SCREENSHOT_TAKEN", file))
        })
        popup:addWidget(group)

	popup:addTimer(5000, function()
		popup:hide()
	end)
	self:tieAndShowWindow(popup)

	return EVENT_CONSUME
end


function init(self, ...)

	self.number = 1
	
	Framework:addActionListener("take_screenshot", self, _takeScreenshotAction)
	
	return self
end


--[[

=head2 applets.Screenshot.ScreenshotApplet:free()

Overridden to return always false, this ensure the applet is
permanently loaded.

=cut
--]]
function free(self)
	-- we cannot be unloaded
	return false
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

