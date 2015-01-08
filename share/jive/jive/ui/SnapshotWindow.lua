

-- stuff we use
local ipairs, tostring, type = ipairs, tostring, type

local oo              = require("loop.simple")
local Framework       = require("jive.ui.Framework")
local Widget          = require("jive.ui.Widget")
local Window          = require("jive.ui.Window")
local Surface         = require("jive.ui.Surface")

local log             = require("jive.utils.log").logger("jivelite.ui")

local EVENT_ACTION    = jive.ui.EVENT_ACTION
local EVENT_KEY_PRESS = jive.ui.EVENT_KEY_PRESS
local ACTION          = jive.ui.ACTION
local EVENT_CONSUME   = jive.ui.EVENT_CONSUME


-- our class
module(...)
oo.class(_M, Window)


function __init(self, windowId)
	local obj = oo.rawnew(self, Window("" , "", _, windowId))

	obj._DEFAULT_SHOW_TRANSITION = Window.transitionNone
	obj._DEFAULT_HIDE_TRANSITION = Window.transitionFadeInFast

	obj:setAllowScreensaver(true)
	obj:setShowFrameworkWidgets(false)

	obj:setButtonAction("lbutton", nil)
	obj:setButtonAction("rbutton", nil)

	obj._bg = _capture(obj)

	return obj
end

function _cancelContextMenuAction()
	Window:hideContextMenus()
	return EVENT_CONSUME
end

function draw(self, surface, layer)
	self._bg:blit(surface, 0, 0)
end


function _getTopWindowContextMenu(self)
	local topWindow = Window:getTopNonTransientWindow()

	if topWindow:isContextMenu() then
		return topWindow
	end
end


function refresh(self)
	self._bg = self:_capture()
end


function _capture(self)
	local sw, sh = Framework:getScreenSize()
	local img = Surface:newRGB(sw, sh)

	--take snapshot of screen
	Framework:draw(img)

	return img
end


function __tostring(self)
	return "SnapshotWindow()"
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]
