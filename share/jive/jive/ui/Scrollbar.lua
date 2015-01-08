
--[[
=head1 NAME

jive.ui.Scrollbar - A scrollbar widget.

=head1 DESCRIPTION

A scrollbar widget, extends L<jive.ui.Widget>.

=head1 SYNOPSIS

 -- Create a new label to display 'Hello World'
 local scrollbar = jive.ui.Scrollbar("label")

 -- Set the scrollbar range, 10 items bubble is in the middle
 scrollbar:setScroll(1, 10, 5)

=head1 STYLE

The Scrollbar includes the following style parameters in addition to the widgets basic parameters.

=over

B<bg_img> : the background image tile.

B<img> : the bar image tile.

B<horizontal> : true if the scrollbar is horizontal, otherwise the scrollbar is vertial (defaults to horizontal).

=head1 METHODS

=cut
--]]


-- stuff we use
local tostring, type = tostring, type

local oo	= require("loop.simple")
local math      = require("math")
local Slider	= require("jive.ui.Slider")
local Widget	= require("jive.ui.Widget")


local log       = require("jive.utils.log").logger("jivelite.ui")

local EVENT_KEY_PRESS = jive.ui.EVENT_KEY_PRESS
local EVENT_SCROLL    = jive.ui.EVENT_SCROLL
local EVENT_CONSUME   = jive.ui.EVENT_CONSUME

local KEY_BACK        = jive.ui.KEY_BACK
local KEY_UP          = jive.ui.KEY_UP
local KEY_DOWN        = jive.ui.KEY_DOWN
local KEY_LEFT        = jive.ui.KEY_LEFT


-- our class
module(...)
oo.class(_M, Slider)



function __init(self, style, closure)

	local obj = oo.rawnew(self, Slider(style))

	obj.range = 1
	obj.value = 1
	obj.size = 1
	obj.closure = closure
	obj.jumpOnDown = false

	return obj
end


--[[

=head2 jive.ui.Scrollbar:setScrollbar(min, max, pos, size)

Set the scrollbar range I<min> to I<max>, the bar position to I<pos> and
the bar size to I<size>.  This method can be used when using this widget 
as a scrollbar.

=cut
--]]
function setScrollbar(self, min, max, pos, size)
	self.range = max - min
	self.value = pos - min
	self.size = size


	self:reDraw()
end


function _setSlider(self, percent)
	
	--boundary guard, since value is often past border (e.g. when vertical slider drag y value moves above slider)  
	if percent < 0 then
		percent = 0
	elseif percent >= 1 then
		percent = .9999 
	end

	local pos = percent * (self.range)

	self.value = math.floor(pos)
	self:reDraw()
	
-- removed oldValue check (performance enhancement as far as I can see) because value (in menu case, for example) was
-- being reset by the menu after setSelectedIndex was called, calling false positives here
-- I would think that these would always have been the same, but was not the case,
-- so in the future this discrepency could be resolved and this performance enhancement could be re-added.			
--	if self.value ~= oldvalue and self.closure then
	if self.closure then
		self.closure(self, self.value, false)
	end
end


--[[ C optimized:

jive.ui.Scrollbar:pack()
jive.ui.Scrollbar:draw()

--]]

--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]
