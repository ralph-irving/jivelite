
--[[
=head1 NAME

jive.ui.Slider - A slider widget.

=head1 DESCRIPTION

A slider widget, extends L<jive.ui.Widget>.

=head1 SYNOPSIS

 -- Create a new label to display 'Hello World'
 local slider = jive.ui.Slider("slider")

 -- Set the slider range, 10 items bubble is in the middle
 slider:setScroll(1, 10, 5)

=head1 STYLE

The Slider includes the following style parameters in addition to the widgets basic parameters.

=over

B<bg_img> : the background image tile.

B<img> : the bar image tile.

B<horizontal> : true if the slider is horizontal, otherwise the slider is vertial (defaults to horizontal).

=head1 METHODS

=cut
--]]


-- stuff we use
local tonumber, tostring, type, bit = tonumber, tostring, type, bit

local oo	= require("loop.simple")
local math      = require("math")

local Widget	= require("jive.ui.Widget")
local IRMenuAccel = require("jive.ui.IRMenuAccel")
local Framework	= require("jive.ui.Framework")
local System    = require("jive.System")

local log       = require("jive.utils.log").logger("jivelite.ui")

local EVENT_KEY_PRESS = jive.ui.EVENT_KEY_PRESS
local EVENT_SCROLL    = jive.ui.EVENT_SCROLL
local EVENT_CONSUME   = jive.ui.EVENT_CONSUME
local EVENT_UNUSED    = jive.ui.EVENT_UNUSED
local EVENT_MOUSE_HOLD        = jive.ui.EVENT_MOUSE_HOLD
local EVENT_MOUSE_DRAG        = jive.ui.EVENT_MOUSE_DRAG
local EVENT_MOUSE_PRESS       = jive.ui.EVENT_MOUSE_PRESS
local EVENT_MOUSE_DOWN        = jive.ui.EVENT_MOUSE_DOWN
local EVENT_MOUSE_UP          = jive.ui.EVENT_MOUSE_UP
local EVENT_MOUSE_ALL         = jive.ui.EVENT_MOUSE_ALL
local EVENT_IR_ALL            = jive.ui.EVENT_IR_ALL
local EVENT_IR_DOWN           = jive.ui.EVENT_IR_DOWN
local EVENT_IR_REPEAT         = jive.ui.EVENT_IR_REPEAT

local KEY_BACK        = jive.ui.KEY_BACK
local KEY_UP          = jive.ui.KEY_UP
local KEY_DOWN        = jive.ui.KEY_DOWN
local KEY_LEFT        = jive.ui.KEY_LEFT
local KEY_GO          = jive.ui.KEY_GO
local KEY_RIGHT       = jive.ui.KEY_RIGHT
local KEY_FWD         = jive.ui.KEY_FWD

local MOUSE_COMPLETE = 0
local MOUSE_DOWN = 1
local MOUSE_DRAG = 2

local PAGING_BOUNDARY_BUFFER_FRACTION = .25

--BUFFER_ZONE area beyond pill bounds to allow a sloppy touch to still be considered in contact with the pill 
local BUFFER_ZONE = 15

-- our class
module(...)
oo.class(_M, Widget)



function __init(self, style, min, max, value, closure, dragDoneClosure)

	local obj = oo.rawnew(self, Widget(style))

	obj.min = min or 1
	obj.range = max or 1
	obj.value = 1
	obj.closure = closure
	obj.dragDoneClosure = dragDoneClosure
	obj.sliderEnabled = true
        obj.irAccel = IRMenuAccel("arrow_up", "arrow_down")
	
--	obj.dragThreshold = 25
	obj.dragThreshold = 12 -- todo: test this lower value on fab4 to see if sloppy taps still work as page up/down

	obj.distanceFromMouseDownMax = 0
	obj.jumpOnDown = true

	obj.touchpadBottomCorrection = System:getTouchpadBottomCorrection()
	obj:setValue(value or obj.min)

	obj:addActionListener("go", obj, _callClosureAction)
	obj:addActionListener("play", obj, _callClosureAction)
	obj:addListener(bit.bor(EVENT_SCROLL, EVENT_KEY_PRESS, EVENT_MOUSE_ALL, EVENT_IR_DOWN, EVENT_IR_REPEAT),
			function(event)
				return obj:_eventHandler(event)
			end)
	return obj
end


--[[

=head2 jive.ui.Slider:setScrollbar(min, max, pos, size)

Set the slider range I<min> to I<max>, the bar position to I<pos> and
the bar size to I<size>.  This method can be used when using this widget 
as a slider.

=cut
--]]
function setScrollbar(self, min, max, pos, size)

	self.range = max - min
	self.value = pos - min
	self.size = size

	self:reDraw()
end


--[[

=head2 jive.ui.Slider:setRange(min, max, value)

Set the slider range I<min> to I<max>, and the bar size to I<value>. This
method can be used when using this widget as a scrollbar.

=cut
--]]
function setRange(self, min, max, value)
	self.range = max
	self.min = min
	self.value = 1

	self:setValue(value)
end


--[[

=head2 jive.ui.Slider:setValue(value)

Set the slider value to I<value>.

=cut
--]]
function setValue(self, value)
	if self.size == tonumber(value) then
		return
	end

	self.size = tonumber(value) or 0

	if tonumber(self.size) < tonumber(self.min) then
		self.size = tonumber(self.min)
	elseif self.size > self.range then
		self.size = tonumber(self.range)
	end

	self:reDraw()
end

--[[

=head2 jive.ui.Slider:setEnabled(value)

Toggles the slider as an enabled or disabled widget
For use in consuming events when the slider is intended to be non-interactive

=cut
--]]
function setEnabled(self, enable)
	if enable then
		self.sliderEnabled = true
	else
		self.sliderEnabled = false
	end
end


--[[

=head2 jive.ui.Slider:getValue()

Returns the value of the slider.

=cut
--]]
function getValue(self)
	return self.size
end


function _moveSlider(self, value)
	local oldSize = self.size

	self:setValue(self.size + value)

	if self.size ~= oldSize then
		if self.closure then
			self.closure(self, self.size, false)
		end
	end
end


function _setSlider(self, percent)
	local oldSize = self.size

	self:setValue(math.ceil(percent * self.range))

	if self.size ~= oldSize then
		if self.closure then
			self.closure(self, self.size, false)
		end
	end
end


function _callClosureAction(self, event)
	if self.closure then
		self.closure(self, self.size, true)
		return EVENT_CONSUME
	end

	return EVENT_UNUSED
end


function _eventHandler(self, event)
	local type = event:getType()

	-- consume events if the slider is disabled
	if not self.sliderEnabled then
		return EVENT_UNUSED
	end

	if type == EVENT_SCROLL then
		self:_moveSlider(event:getScroll())
		return EVENT_CONSUME
	elseif type == EVENT_MOUSE_DOWN and not self.jumpOnDown then

		self.mouseState = MOUSE_DOWN
		updateMouseOriginOffset(self, event)

		return EVENT_CONSUME
	elseif type == EVENT_MOUSE_DRAG or (type == EVENT_MOUSE_DOWN and self.jumpOnDown) then
		updateMouseOriginOffset(self, event)

		if not self.jumpOnDown then
			--ignore value up until dragThreshold so that a sloppy press can still be seen
			if not mouseExceededBufferDistance(self, self.dragThreshold) then
				return EVENT_CONSUME
			end
		end

		self.mouseState = MOUSE_DRAG

		local x,y,w,h = self:mouseBounds(event)
		if w > h then
			if self.pillDragOnly then
				local xPill,yPill,wPill,hPill = self:getPillBounds(true)
				local xMouse, yMouse = event:getMouse()
				if not self.pillOffset then
					if xMouse >= xPill and xMouse <= xPill + wPill then			                        
						--adjust so movement is reference to the pill location, not the pointer location
						self.pillOffset = xMouse - xPill
						--no need to move initially, since stuck on pill
						return EVENT_CONSUME
					else
						--only drag if inside pill 
						return EVENT_CONSUME
					end
				end
				x = x - self.pillOffset
				self:_setSlider( x / (w - wPill) )
			else
				self:_setSlider(x / w)
			end
			-- horizontal
		else
			-- vertical
			if self.pillDragOnly then
				local xPill,yPill,wPill,hPill = self:getPillBounds(false)
				local xMouse, yMouse = event:getMouse()
				if not self.pillOffset then
					if yMouse >= (yPill) and yMouse <= (yPill + hPill) then			                        
						--adjust so movement is reference to the pill location, not the pointer location
						self.pillOffset = yMouse - yPill
						--no need to move initially, since stuck on pill
						return EVENT_CONSUME
					else
						--only drag if inside pill 
						return EVENT_CONSUME
					end
				end
				y = y - self.pillOffset
				self:_setSlider( y  / (h - hPill) )
			else
				self:_setSlider(y / (h - self.touchpadBottomCorrection))
			end
		end
		self.useDragDoneClosure = true

		return EVENT_CONSUME
	elseif type == EVENT_MOUSE_UP then

		if self.useDragDoneClosure then
			self.useDragDoneClosure = false
			if self.dragDoneClosure then
				self.dragDoneClosure(self, self.size, false)
			end
		end

		if self.mouseState == MOUSE_COMPLETE or self.mouseState == MOUSE_DRAG then
			return finishMouseSequence(self)
		end

		if not self.jumpOnDown then
			--perform pageup/pagedown (some of this is actually scrollbar specific.. Currently regular scrollbars
			 -- are self.jumpOnDown true by default, so this code won't be hit, but todo: refactor this so that scrollbar code isn't
			 -- inside the slider class.
			local x,y,w,h = self:mouseBounds(event)
			local sliderFraction
			if w > h then
				-- horizontal
				sliderFraction = x / w
			else
				-- vertical
				sliderFraction = y / h
			end

			local pos = sliderFraction * (self.range)
			local inUpperBufferZone = sliderFraction < PAGING_BOUNDARY_BUFFER_FRACTION
			local inLowerBufferZone = sliderFraction > (1 - PAGING_BOUNDARY_BUFFER_FRACTION)

			if inUpperBufferZone or (pos <= self.value and not inLowerBufferZone ) then
				Framework:pushAction("page_up")
			elseif inLowerBufferZone or pos > self.value + self.size then
				Framework:pushAction("page_down")
			end
		end
		return finishMouseSequence(self)
	elseif type == EVENT_MOUSE_PRESS or
		type == EVENT_MOUSE_HOLD then
		--ignore
		return EVENT_CONSUME

	elseif type == EVENT_KEY_PRESS then
		local keycode = event:getKeycode()

		if keycode == KEY_DOWN then
			self:_moveSlider(-1)
		elseif keycode == KEY_UP then
			self:_moveSlider(1)
		end

		if keycode == KEY_FWD then
			return _callClosureAction(self, event)
		end

		return EVENT_UNUSED
	elseif bit.band(type, EVENT_IR_ALL) > 0 then
		if event:isIRCode("arrow_up") or event:isIRCode("arrow_down") then
			if type == EVENT_IR_DOWN or type == EVENT_IR_REPEAT then
				local value = self.irAccel:event(event, 1, 1, 1, 100)

				if value ~= 0 then
					self:_moveSlider(value)
				end
			end
		end
		--all non-volume IR, pass through.
		return EVENT_UNUSED

	end
end



function finishMouseSequence(self)
	self.mouseState = MOUSE_COMPLETE

	self.mouseDownX = nil
	self.mouseDownY = nil
	self.distanceFromMouseDownMax = 0
	self.pillOffset = nil
	return EVENT_CONSUME
end


function updateMouseOriginOffset(self, event)
	local x, y = event:getMouse()

	if not self.mouseDownX then
		--new drag, set origin
		self.mouseDownX = x
		self.mouseDownY = y
	else
		--2nd or later point gathered

	        local distanceFromOrigin = math.sqrt(
					math.pow(x - self.mouseDownX, 2)
					+ math.pow(y - self.mouseDownY, 2) )

		if distanceFromOrigin > self.distanceFromMouseDownMax then
			self.distanceFromMouseDownMax = distanceFromOrigin
		end

	end

end


function mouseExceededBufferDistance(self, value)
	return self.distanceFromMouseDownMax >= value
end


--[[ C optimized:

jive.ui.Slider:pack()
jive.ui.Slider:draw()

--]]

--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]
