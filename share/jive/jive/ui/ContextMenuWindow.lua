

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


function __init(self, title, windowId, noShading)
	local obj = oo.rawnew(self, Window("context_menu" , title, _, windowId))

	obj._DEFAULT_SHOW_TRANSITION = Window.transitionFadeInFast
	obj._DEFAULT_HIDE_TRANSITION = Window.transitionNone

	obj:setAllowScreensaver(false)
	obj:setShowFrameworkWidgets(false)
	obj:setContextMenu(true)

	obj:setButtonAction("lbutton", nil)
	obj:setButtonAction("rbutton", "cancel")

	obj:addActionListener("cancel", obj, _cancelContextMenuAction)
	obj:addActionListener("add", obj, _cancelContextMenuAction)

	obj.noShading = noShading
	obj._bg = _capture(obj)

	return obj
end

function _cancelContextMenuAction()
	Window:hideContextMenus()
	return EVENT_CONSUME
end

function draw(self, surface, layer)
	if not Framework.transition then
		--draw snapshot version of previous version because drawing both windows is too cpu-intensive
		self._bg:blit(surface, 0, 0)
	end
	Window.draw(self, surface, layer)
end


function _getTopWindowContextMenu(self)
	local topWindow = Window:getTopNonTransientWindow()

	if topWindow:isContextMenu() then
		return topWindow
	end
end

function show(self)
	local topContextMenuWindow = self:_getTopWindowContextMenu()
	if topContextMenuWindow then
		self._bg = topContextMenuWindow._bg
		self:setButtonAction('lbutton', 'back')
		Window.show(self, Window.transitionPushLeftStaticTitle)
	else
		Window.show(self)
		self.isTopContextMenu = true
	end

end

function hide(self)

	local stack = Framework.windowStack

	local idx = 1
	local topwindow = stack[idx]
	while topwindow and topwindow.alwaysOnTop do
		idx = idx + 1
		topwindow = stack[idx]
	end

	if stack[idx + 1] and stack[idx + 1]:isContextMenu() then
		Window.hide(self, Window.transitionPushRightStaticTitle)
	else
		Window.hide(self)
	end

end


function _capture(self)
	local sw, sh = Framework:getScreenSize()
	local img = Surface:newRGB(sw, sh)

	--take snapshot of screen
	Framework:draw(img)

	if not self.noShading then
		--apply shading - tried via maskImg, but child CM windows didn't display maksImg correct
		img:filledRectangle(0, 0, sw, sh, 0x00000085)
	end
	return img
end


--function borderLayout(self)
--	Window.borderLayout(self, true)
--end


function __tostring(self)
	return "ContextMenuWindow()"
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]
