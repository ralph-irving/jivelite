--[[
=head1 NAME

jive.ui.StickyMenu - A subclass of SimpleMenu that allows for "stickier" menu scrolling

=head1 DESCRIPTION

A sticky menu widget, extends L<jive.ui.SimpleMenu>, which extends L<jive.ui.Menu>.

=head1 SYNOPSIS

 -- Create a new menu, with a sticky multiplier of 3x the stickiness of a normal menu
 local menu = jive.ui.StickyMenu("menu", 3
		   {
			   {
				   id = 'uniqueString',
				   text = "Item 1",
				   sound = "WINDOWSHOW",
				   icon = widget1,
				   callback = function1
			   ),
			   {
				   id = 'anotherUniqueString',
				   text = "Item 2",
				   sound = "WINDOWSHOW",
				   icon = widget2,
				   callback = function2
			   ),
		   }
)

=head1 STYLE


=head1 METHODS

=cut
--]]


-- stuff we use
local _assert, ipairs, string, tostring, type, tonumber = _assert, ipairs, string, tostring, type, tonumber


local oo              = require("loop.simple")
local debug           = require("jive.utils.debug")

local Group           = require("jive.ui.Group")
local Label           = require("jive.ui.Label")
local Icon            = require("jive.ui.Icon")
local Textarea        = require("jive.ui.Textarea")
local math            = require("math")
local Menu            = require("jive.ui.Menu")
local SimpleMenu      = require("jive.ui.SimpleMenu")
local Widget          = require("jive.ui.Widget")

local table           = require("jive.utils.table")
local log             = require("jive.utils.log").logger("jivelite.ui")

local ACTION    = jive.ui.ACTION
local EVENT_ACTION    = jive.ui.EVENT_ACTION
local EVENT_FOCUS_GAINED = jive.ui.EVENT_FOCUS_GAINED
local EVENT_FOCUS_LOST   = jive.ui.EVENT_FOCUS_LOST

local EVENT_CONSUME   = jive.ui.EVENT_CONSUME
local EVENT_UNUSED    = jive.ui.EVENT_UNUSED


-- our class
module(...)
oo.class(_M, SimpleMenu)


function __init(self, style, multiplier, items, itemRenderer, itemListener)
	_assert(type(style) == "string")

	local obj = oo.rawnew(self, SimpleMenu(style, itemRenderer or _itemRenderer, itemListener or _itemListener))
	obj.items = items or {}
	obj.multiplier = multiplier or 1
	obj.icons = {}
	obj.checks = {}
	obj.arrows = {}
	obj.stickyDown = 1
	obj.stickyUp = 1

	obj:setItems(obj.items, #obj.items)

	return obj
end


--override scrollBy to create Sticky scrolling

function scrollBy(self, scroll, allowMultiple, isNewOperation, forceAccel)

	log:debug(self, scroll)
	if self.headerWidget then
	        isNewOperation = false
	end


	-- if scroll is positive, then we are scrolling downward
	if scroll > 0 then
		-- first reset the sticky incrementer for upward scrolling, since we aren't doing that
		self.stickyUp = 1

		if self.multiplier == self.stickyDown then
			log:debug("StickyMenu: okay scroll down now ")
			Menu.scrollBy(self, scroll, allowMultiple, isNewOperation, forceAccel)
			if self.headerWidget and self.headerWidget.handleMenuHeaderWidgetScrollBy then
				self.headerWidget:handleMenuHeaderWidgetScrollBy(scroll, self)
			end
			self.stickyDown = 1
		else
			self.stickyDown = self.stickyDown + 1
			log:debug("StickyMenu: don't scroll down yet ", self.stickyDown, '(', self.multiplier, ')')
		end

	-- if scroll is negative, then we are scrolling upward
	else
		-- first reset the sticky incrementer for downward scrolling, since we aren't doing that
		self.stickyDown = 1

		if self.multiplier == self.stickyUp then
			log:debug("StickyMenu: okay scroll up now ")
			Menu.scrollBy(self, scroll, allowMultiple, isNewOperation, forceAccel)
			if self.headerWidget and self.headerWidget.handleMenuHeaderWidgetScrollBy then
				self.headerWidget:handleMenuHeaderWidgetScrollBy(scroll, self)
			end
			self.stickyUp = 1
		else
			self.stickyUp = self.stickyUp + 1
			log:debug("StickyMenu: don't scroll up yet ", self.stickyUp)
		end

	end

end

function __tostring(self)
	return "StickyMenu()"
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]


