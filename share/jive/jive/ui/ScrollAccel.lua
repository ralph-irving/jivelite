--[[
=head1 NAME

jive.ui.ScrollAccel

=head1 DESCRIPTION

Class to handle scroll events with acceleration.

--]]

local oo                   = require("loop.simple")
local math                 = require("math")

local ScrollWheel          = require("jive.ui.ScrollWheel")

local debug                = require("jive.utils.debug")
local log                  = require("jive.utils.log").logger("jivelite.ui")


-- our class
module(...)
oo.class(_M, ScrollWheel)


--[[
=head2 ScrollAccel(itemAvailable)

Creates a filter for accelerated scroll events.

I<itemAvailable> is a function that returns a true if the items in a range
of indexes are loaded. This is optional, by default it is assumed that all
items are loaded.

=cut
--]]
function __init(self, ...)
	local obj = oo.rawnew(self, ScrollWheel(...))

	obj.listIndex   = 1
	obj.scrollDir   = 0
	obj.scrollLastT = 0

	return obj
end


--[[
=head2 self:event(event, listTop, listIndex, listVisible, listSize)

Called with a scroll event I<event>. Returns how far the selection should
move by.

I<listTop> is the index of the list item at the top of the screen.
I<listIndex> is the selected list item.
I<listVisible> is the number of items on the screen.
I<listSize> is the total number of items in the list.

=cut
--]]
function event(self, event, listTop, listIndex, listVisible, listSize)

	local scroll = event:getScroll()

	-- update state
	local now = event:getTicks()
	local delta = (now - self.scrollLastT) / math.abs(scroll)

	local dir = scroll > 0 and 1 or -1

	self.listIndex   = listIndex or 1
	self.scrollDir   = dir
	self.scrollLastT = now

	-- no acceleration if changed direction, or paused scrolling
	if dir ~= self.scrollDir or delta > 250 then
		self.scrollAccel = nil

		-- call superclass
		return ScrollWheel.event(self, event, listTop, listIndex, listVisible, listSize)
	end
	self.scrollDir = dir

	-- apply the acceleration
	if self.scrollAccel then
		self.scrollAccel = self.scrollAccel + 1
	else
		self.scrollAccel = 1
	end

	local delta
	if     self.scrollAccel > 50 then
		delta = dir * math.max(math.ceil(listSize/50), math.abs(scroll) * 16)
	elseif self.scrollAccel > 40 then
		delta = scroll * 16
	elseif self.scrollAccel > 30 then
		delta = scroll * 8
	elseif self.scrollAccel > 20 then
		delta = scroll * 4
	elseif self.scrollAccel > 10 then
		delta = scroll * 2
	else
		delta = scroll
	end

	-- check the data in the list is loaded
	if not _itemAvailable(self, listTop + delta + (listIndex - listTop), listVisible, listSize) then
		-- FIXME we should look ahead here, and limit the
		-- acceleration so as not to reach parts of the list
		-- that have not been loaded yet.
		delta = 0
	end

	return delta
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]
