--[[
=head1 NAME

jive.ui.ScrollWheel

=head1 DESCRIPTION

Class to handle scroll events.

--]]

local oo                   = require("loop.base")

local math                 = require("math")

local debug                = require("jive.utils.debug")
local log                  = require("jive.utils.log").logger("jivelite.ui")


-- our class
module(..., oo.class)


--[[
=head2 ScrollWheel(itemAvailable)

Creates a filter for non-accelerated scroll events.

I<itemAvailable> is a function that returns a true if the items in a range
of indexes are loaded. This is optional, by default it is assumed that all
items are loaded.

=cut
--]]
function __init(self, itemAvailable)
	local obj = oo.rawnew(self, {})

	obj.itemAvailable = itemAvailable or function() return true end

	return obj
end


function _itemAvailable(self, listTop, listVisible, listSize)
	-- make sure the list indices are in range
	if listVisible > listSize then
		listVisible = listSize
	end
	if listTop + listVisible > listSize then
		listTop = listSize - listVisible
	end
	if listTop < 1 then
		listTop = 1
	end

	return self.itemAvailable(listTop, listVisible)
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

	-- Only move one item up or down in the list
	local dir = scroll > 0 and 1 or -1

	-- Don't scroll if the list has not yet loaded 
	if not _itemAvailable(self, listIndex + dir + (listIndex - listTop), listVisible, listSize) then
		dir = 0
	end

	return dir
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]
