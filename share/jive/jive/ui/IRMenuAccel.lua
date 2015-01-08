--[[
=head1 NAME

jive.ui.IrMenuAccel

=head1 DESCRIPTION

Class to handle ir events with acceleration.

--]]

local oo                   = require("loop.simple")
local math                 = require("math")

local ScrollWheel          = require("jive.ui.ScrollWheel")

local debug                = require("jive.utils.debug")
local log                  = require("jive.utils.log").logger("jivelite.ui")

local EVENT_IR_DOWN        = jive.ui.EVENT_IR_DOWN
local EVENT_IR_REPEAT      = jive.ui.EVENT_IR_REPEAT

local DOUBLE_CLICK_HOLD_TIME = 400 -- ms
local INITIAL_ITEM_CHANGE_PERIOD = 350 -- ms
local CYCLES_BEFORE_ACCELERATION_STARTS = 1

-- our class
module(..., oo.class)


--[[
=head2 IrMenuAccel(positiveButtonName, negativeButtonName)

Creates a filter for accelerated ir events, using ir button names "arrow_down" and "arrow_up" for 
the positive and negative IR event triggers, unless overridden by positiveCode and negativeCode.

Option param:
positiveCode indicate the ir button name that will trigger positive acceleration
negativeCode indicate the ir button name that will trigger negative acceleration


=cut
--]]
function __init(self, positiveButtonName, negativeButtonName)
	local obj = oo.rawnew(self, {})

	obj.positiveButtonName = positiveButtonName and positiveButtonName or "arrow_down"
	obj.negativeButtonName = negativeButtonName and negativeButtonName or "arrow_up"
	obj.listIndex   = 1
	obj.lastItemChangeT = 0
	obj.itemChangePeriod = INITIAL_ITEM_CHANGE_PERIOD
	obj.itemChangeCycles = 0
	obj.lastDownT = nil
	obj.onlyScrollByOne = false
	obj.cyclesBeforeAccelerationStarts = CYCLES_BEFORE_ACCELERATION_STARTS

	return obj
end


--[[
=head2 self:event(event, listTop, listIndex, listVisible, listSize)

Called with an ir event I<event>. Returns how far the selection should
move by.

I<listTop> is the index of the list item at the top of the screen.
I<listIndex> is the selected list item.
I<listVisible> is the number of items on the screen.
I<listSize> is the total number of items in the list.

=cut
--]]
function event(self, event, listTop, listIndex, listVisible, listSize)

	local dir = nil
	if event:isIRCode(self.positiveButtonName) then 
		dir = 1
	elseif event:isIRCode(self.negativeButtonName) then
		dir = -1
	else
		log:error("Unexpected irCode: " , event:getIRCode())
	end
		

	-- update state
	local now = event:getTicks()

	self.listIndex   = listIndex or 1

	--restart accelaration if new DOWN event seen
	if event:getType() == EVENT_IR_DOWN then
		if self.lastDownT and (now - self.lastDownT < DOUBLE_CLICK_HOLD_TIME) then
			--make the acceleration kick in faster on a quick second down
			self.lastDownT = nil
			self.itemChangeCycles = 12
			self.itemChangePeriod = INITIAL_ITEM_CHANGE_PERIOD * .6
		else
			self.lastDownT = now
			self.itemChangeCycles = 1
			self.itemChangePeriod = INITIAL_ITEM_CHANGE_PERIOD
		end

		self.lastItemChangeT = now
			
		--always move just one on a IR_DOWN
		local scrollBy = 1
		log:debug("IR Acceleration params -- scrollBy: " , scrollBy, " dir: ", dir, " itemChangePeriod: ", self.itemChangePeriod, " itemChangeCycles: ", self.itemChangeCycles)
		return scrollBy * dir
	end

	-- apply the acceleration, based on number of "itemChange" cycles, not based on "amount of input" 
	-- Initial technique: increase the "item change rate" initially and move just by one, later increase scrollBy amount - not quite as sophisticated as SC accel

	if now > self.itemChangePeriod + self.lastItemChangeT then
		self.lastItemChangeT = now
		
		local scrollBy = 1
		--early on, only move one item at a time, but increase item change period
		 
		--currently when you lift the ir button, the last repeat seem to be coming in later, so the menu doesn't 
		 -- stop on the item seen on the screen, maybe due to the event loop lag, maybe not
  		 -- It is then important to go slowly enough early on so that when the ir button is 
		 -- lifted that the item stays on the current item. If a faster initial scroll occurs,
		 -- then the ui usually stops on the item after the selected item.
		 -- Ideally this can be optimized, to give the best of both worlds.
		   
		 -- todo: the acceleration algorithm could be listSize based (i.e. scroll faster soon on a longer list)

		if self.itemChangeCycles == self.cyclesBeforeAccelerationStarts then
			self.itemChangePeriod = self.itemChangePeriod / 2 
		elseif self.itemChangeCycles > 80 then
			scrollBy = 64
		elseif self.itemChangeCycles > 60 then
			scrollBy = 16
		elseif self.itemChangeCycles > 50 then
			scrollBy = 8
		elseif self.itemChangeCycles > 40 then
			scrollBy = 4
		elseif self.itemChangeCycles > 30 then
			scrollBy = 2
		elseif self.itemChangeCycles > 16 then
			self.itemChangePeriod = 0 --full speed
		end

		self.itemChangeCycles = self.itemChangeCycles + 1

		if self.onlyScrollByOne then
			scrollBy = 1
		end

		--don't move move than half a list
		if listSize > 1 and scrollBy > listSize / 2 then
			scrollBy = listSize / 2
		end

		log:debug("IR Acceleration params -- scrollBy: " , scrollBy, " dir: ", dir, " itemChangePeriod: ", self.itemChangePeriod, " itemChangeCycles: ", self.itemChangeCycles)
					
		return scrollBy * dir
	end
	
	return 0
end

function setCyclesBeforeAccelerationStarts(self, cyclesBeforeAccelerationStarts)
	self.cyclesBeforeAccelerationStarts = cyclesBeforeAccelerationStarts
end

--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]
