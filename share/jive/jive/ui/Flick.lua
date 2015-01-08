-----------------------------------------------------------------------------
-- Flick.lua
-----------------------------------------------------------------------------

--[[
=head1 NAME

jive.ui.Flicks - Manages Finger Flicks

=head1 METHODS

=cut
--]]


-- stuff we use
local _assert, ipairs, pairs, string, tostring, type, getmetatable = _assert, ipairs, pairs, string, tostring, type, getmetatable

local oo                   = require("loop.simple")
local debug                = require("jive.utils.debug")
                           
local table                = require("jive.utils.table")
local Framework            = require("jive.ui.Framework")
local Event                = require("jive.ui.Event")
local Widget               = require("jive.ui.Widget")
local Label                = require("jive.ui.Label")
local Scrollbar            = require("jive.ui.Scrollbar")
local Surface              = require("jive.ui.Surface")
local ScrollAccel          = require("jive.ui.ScrollAccel")
local IRMenuAccel          = require("jive.ui.IRMenuAccel")
local Timer                = require("jive.ui.Timer")

local log                  = require("jive.utils.log").logger("jivelite.ui")

local math                 = require("math")


local EVENT_ALL            = jive.ui.EVENT_ALL
local EVENT_ALL_INPUT      = jive.ui.EVENT_ALL_INPUT
local ACTION               = jive.ui.ACTION
local EVENT_ACTION         = jive.ui.EVENT_ACTION
local EVENT_SCROLL         = jive.ui.EVENT_SCROLL
local EVENT_IR_ALL         = jive.ui.EVENT_IR_ALL
local EVENT_IR_DOWN        = jive.ui.EVENT_IR_DOWN
local EVENT_IR_REPEAT      = jive.ui.EVENT_IR_REPEAT
local EVENT_KEY_ALL        = jive.ui.EVENT_KEY_ALL
local EVENT_KEY_PRESS      = jive.ui.EVENT_KEY_PRESS
local EVENT_SHOW           = jive.ui.EVENT_SHOW
local EVENT_HIDE           = jive.ui.EVENT_HIDE
local EVENT_SERVICE_JNT    = jive.ui.EVENT_SERVICE_JNT
local EVENT_FOCUS_GAINED   = jive.ui.EVENT_FOCUS_GAINED
local EVENT_FOCUS_LOST     = jive.ui.EVENT_FOCUS_LOST
local EVENT_MOUSE_PRESS    = jive.ui.EVENT_MOUSE_PRESS
local EVENT_MOUSE_DOWN     = jive.ui.EVENT_MOUSE_DOWN
local EVENT_MOUSE_UP       = jive.ui.EVENT_MOUSE_UP
local EVENT_MOUSE_MOVE     = jive.ui.EVENT_MOUSE_MOVE
local EVENT_MOUSE_DRAG     = jive.ui.EVENT_MOUSE_DRAG
local EVENT_MOUSE_HOLD     = jive.ui.EVENT_MOUSE_HOLD
local EVENT_MOUSE_ALL      = jive.ui.EVENT_MOUSE_ALL

local EVENT_CONSUME        = jive.ui.EVENT_CONSUME
local EVENT_UNUSED         = jive.ui.EVENT_UNUSED
                           
local KEY_FWD              = jive.ui.KEY_FWD
local KEY_REW              = jive.ui.KEY_REW
local KEY_GO               = jive.ui.KEY_GO
local KEY_BACK             = jive.ui.KEY_BACK
local KEY_UP               = jive.ui.KEY_UP
local KEY_DOWN             = jive.ui.KEY_DOWN
local KEY_LEFT             = jive.ui.KEY_LEFT
local KEY_RIGHT            = jive.ui.KEY_RIGHT
local KEY_PLAY             = jive.ui.KEY_PLAY
local KEY_PAGE_UP           = jive.ui.KEY_PAGE_UP
local KEY_PAGE_DOWN         = jive.ui.KEY_PAGE_DOWN

--speed (pixels/ms) that must be surpassed for flick to start.
local FLICK_THRESHOLD_START_SPEED = 90/1000


--"recent" distance that must be surpassed for flick to start.
-- is used to check for drag then quick finger stop then release. Normal averaging doesn't handle this case well, thus we have this further check.
local FLICK_RECENT_THRESHOLD_DISTANCE = 5

--speed (pixels/ms) that per pixel afterscrolling occurs, otherwise is per item when faster.
local FLICK_THRESHOLD_BY_PIXEL_SPEED = 600/1000

--speed (pixels/ms) at which flick scrolling will stop
local FLICK_STOP_SPEED =  1/1000

local FLICK_STOP_SPEED_WITH_SNAP =  60/1000

local SNAP_PIXEL_SHIFT = 1 -- todo: anything other than one will not works since it will go endlessly

--if initial speed is greater than this, "letter" accelerators will occur for the flick
local FLICK_FORCE_ACCEL_SPEED = 72 * 30/1000

--time after flick starts that decel occurs
local FLICK_DECEL_START_TIME = 100

--time from decel start to scroll stop (trying new linger setting, which throws this off)
local FLICK_DECEL_TOTAL_TIME = 400

--extra afterscroll time (FLICK_SPEED_DECEL_TIME_FACTOR / flickSpeed ) is
 -- multiplied by FLICK_DECEL_TOTAL_TIME.  flick speed maxes out at about 3.
local FLICK_SPEED_DECEL_TIME_FACTOR = .8
local FLICK_SPEED_DECEL_START_TIME_FACTOR = .7

-- Only the mouse points gathered for the last FLICK_STALE_TIME will be used for flick calculation
local FLICK_STALE_TIME = 190

-- our class
module(..., oo.class)





function stopFlick(self, byFinger)

	self.flickTimer:stop()
	self.flickInterruptedByFinger = byFinger
	self.flickInProgress = false
	self.snapToItemInProgress = false

	self:resetFlickData()
end


function updateFlickData(self, mouseEvent)
	local x, y = mouseEvent:getMouse()
	local ticks = mouseEvent:getTicks()

	--hack until reason for 0 ticks is resolved
	if (ticks == 0) then
		return
	end

	--hack until reason for false "far out of range" ticks is happening

	if #self.flickData.points >=1 then
		local previousTicks = self.flickData.points[#self.flickData.points].ticks
		if math.abs(ticks - previousTicks ) > 10000 then
			log:error("Erroneous tick value occurred, ignoring : ", ticks, "  after previuos tick value of: ", previousTicks)
			return
		end
	end

	--use last flick data collection time as initital scroll time to avoid jerky delay when afterscroll starts 
	self.flickInitialScrollT = Framework:getTicks()

	table.insert(self.flickData.points, {y = y, ticks = ticks})

	--remove any more than 20 points
	if #self.flickData.points >= 20 then
		--only keep last 20 values (number was come up by trial and error, flick and quick stopping, quick flicks, multi-speed flicks)
		-- I found that having this number lower (less averging) made the afterscroll "jump"
		-- also only collect events that occurred in the last 100ms
		table.remove(self.flickData.points, 1)
	end

end

function resetFlickData(self)
	self.flickData.points = {}
end

function getFlickSpeed(self, itemHeight, mouseUpT)
	--remove stale points
	if #self.flickData.points > 1 then
		local staleRemoved = false
		repeat
			if self.flickData.points[#self.flickData.points].ticks - self.flickData.points[1].ticks > FLICK_STALE_TIME then
				table.remove(self.flickData.points, 1)
			else
				staleRemoved = true
			end
		until staleRemoved
	end

	if not self.flickData.points or #self.flickData.points < 2 then
		return nil
	end

	if mouseUpT then
		local delayUntilUp = mouseUpT - self.flickData.points[#self.flickData.points].ticks
		if delayUntilUp > 25 then
			-- a long delay since last point is one indication of a finger stop since lower level duplicate suppression may be in effect
			return nil
		end
	end

	--finger stop checking
	-- finger may have stopped after a drag, but the averaging might make it appear that a flick occurred
	local recentPoints = 5
	if #self.flickData.points > recentPoints then
		local recentIndex = 1 + #self.flickData.points - recentPoints
		local recentDistance = self.flickData.points[#self.flickData.points].y - self.flickData.points[recentIndex].y

		if math.abs(recentDistance) <= FLICK_RECENT_THRESHOLD_DISTANCE then
			log:debug("Returning nil, didn't surpase 'recent' threshold distance: ", recentDistance)
			return nil
		end

	end

	local distance = self.flickData.points[#self.flickData.points].y - self.flickData.points[1].y
	local time = self.flickData.points[#self.flickData.points].ticks - self.flickData.points[1].ticks

	--speed = pixels/ms
	local speed = distance/time


	log:debug("Flick info: speed: ", speed, "  distance: ", distance, "  time: ", time )

	local direction = speed >= 0 and -1 or 1
	return math.abs(speed), direction
end


function snap(self, direction)
	self:flick(FLICK_STOP_SPEED, direction, true)
end

--if initialSpeed nil, then continue any existing flick. If non nil, start a new flick at that rate
function flick(self, initialSpeed, direction, noMinimum)
	if initialSpeed then
		self:stopFlick()
		if not noMinimum and initialSpeed < FLICK_THRESHOLD_START_SPEED then
			log:debug("Under threshold, not flicking: ", initialSpeed )
			if self.parent.snapToItemEnabled then
				self.parent:snapToNearest()
			end
			return
		end
		self.flickInProgress = true
		self.flickInitialSpeed = initialSpeed
		self.flickDirection = direction
		self.snapToItemInProgress = false
		self.flickTimer:start()

		if not self.flickInitialScrollT then
			self.flickInitialScrollT = Framework:getTicks()
		end
		self.flickLastY = 0
		self.flickInitialDecelerationScrollT = nil
		self.flickPreDecelY = 0

		local decelTime = FLICK_DECEL_TOTAL_TIME *  (1 + math.abs(math.pow(self.flickInitialSpeed / FLICK_SPEED_DECEL_TIME_FACTOR, 3)))
		self.flickAccelRate = -self.flickInitialSpeed / decelTime
		self.flickDecelStartT = FLICK_DECEL_START_TIME * (1 + math.abs(math.pow(self.flickInitialSpeed/FLICK_SPEED_DECEL_START_TIME_FACTOR, 3.5)))
		log:debug("*****Starting flick - decelTime: ", decelTime, " self.flickDecelStartT: ", self.flickDecelStartT )
	end

	--continue flick
	local now = Framework:getTicks()

	local flickCurrentY, byItemOnly
	if not self.flickInitialDecelerationScrollT then
		--still at full speed

		flickCurrentY = self.flickInitialSpeed * (now - self.flickInitialScrollT)
		self.flickPreDecelY = flickCurrentY

		--slow speed if past decel time
		if self.flickInitialDecelerationScrollT == nil and now - self.flickInitialScrollT > self.flickDecelStartT then
			log:debug("*****Starting flick slow down")
			self.flickInitialDecelerationScrollT = now
		end
		
		byItemOnly = math.abs(self.flickInitialSpeed) > FLICK_THRESHOLD_BY_PIXEL_SPEED and now - self.flickInitialScrollT > 100
	end

	if self.flickInitialDecelerationScrollT then	
		local elapsedTime = now - self.flickInitialDecelerationScrollT


		--v = v0 + at
		local flickCurrentSpeed = self.flickInitialSpeed + (self.flickAccelRate * elapsedTime)
		
		if self.snapToItemInProgress then
			flickCurrentY = self.flickLastY + SNAP_PIXEL_SHIFT
		else
			-- y = v0*t +.5 * a * t^2
			flickCurrentY = self.flickPreDecelY + self.flickInitialSpeed * elapsedTime + (.5 * self.flickAccelRate * elapsedTime * elapsedTime )
			byItemOnly = math.abs(flickCurrentSpeed) > FLICK_THRESHOLD_BY_PIXEL_SPEED
		end

		local stopSpeed = FLICK_STOP_SPEED
		if self.parent.snapToItemEnabled then
			stopSpeed = FLICK_STOP_SPEED_WITH_SNAP
		end
		
		if self.snapToItemInProgress or flickCurrentSpeed < stopSpeed then
			if self.parent.snapToItemEnabled and self.parent.pixelOffsetY ~= 0 then
				log:debug("*******Snapping Flick at slow down point. current speed:", flickCurrentSpeed, " offset", self.parent.pixelOffsetY)
				self.snapToItemInProgress = true
			else
				log:debug("*******Stopping Flick at slow down point. current speed:", flickCurrentSpeed, " offset", self.parent.pixelOffsetY)
				self:stopFlick()
				return
			end
		end
	end


	local pixelOffset = math.floor(flickCurrentY - self.flickLastY)

	self.parent:handleDrag(self.flickDirection * pixelOffset, byItemOnly)

	self.flickLastY = self.flickLastY + pixelOffset

	if not self.parent:isWraparoundEnabled() and (self.parent:isAtBottom() and self.flickDirection > 0)
		or (self.parent:isAtTop() and self.flickDirection < 0) then
		--stop at boundaries
		log:debug("*******Stopping Flick at boundary") -- need a ui cue that this has happened
		self:stopFlick()
	end
end


--[[

=head2 jive.ui.Drag()

Constructs a new Drag object.

=cut
--]]
function __init(self, parent)
	local obj = oo.rawnew(self)

	obj.parent = parent

	obj.flickData = {}
	obj.flickData.points = {}

	obj.flickTimer = Timer(25,
			       function()
			                obj:flick()
			       end)

	return obj
end



--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

