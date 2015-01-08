local _assert, pairs, string, tostring, type, math = _assert, pairs, string, tostring, type, math
local getmetatable = getmetatable

local oo                     = require("loop.base")
local Timer                  = require("jive.ui.Timer")

local debug                  = require("jive.utils.debug")
local log                    = require("jive.utils.log").logger("jivelite.ui")


local EVENT_MOUSE_ALL        = jive.ui.EVENT_MOUSE_ALL
local EVENT_MOUSE_PRESS      = jive.ui.EVENT_MOUSE_PRESS
local EVENT_MOUSE_DOWN       = jive.ui.EVENT_MOUSE_DOWN
local EVENT_MOUSE_DRAG       = jive.ui.EVENT_MOUSE_DRAG
local EVENT_MOUSE_HOLD       = jive.ui.EVENT_MOUSE_HOLD
local EVENT_MOUSE_UP         = jive.ui.EVENT_MOUSE_UP
local EVENT_FOCUS_LOST       = jive.ui.EVENT_FOCUS_LOST
local EVENT_SHOW             = jive.ui.EVENT_SHOW

local EVENT_CONSUME          = jive.ui.EVENT_CONSUME
local EVENT_UNUSED           = jive.ui.EVENT_UNUSED


-- distance outside of the widget where press will still occur
local PRESS_BUFFER_DISTANCE_FROM_WIDGET = 30


-- distance travelled from mouse origin where HOLD event will be ignored (is relatively high due it being finger interface, finger may roll while waiting for hold to trigger)
local HOLD_BUFFER_DISTANCE_FROM_ORIGIN = 30

--Mouse operation states

local MOUSE_COMPLETE = 0
local MOUSE_DOWN = 1
local MOUSE_HOLD = 2
local MOUSE_LONG_HOLD = 3

module(...)
oo.class(_M, oo.class)

--note: longHoldAction only applicable if holdAction result doesn't hide the window containing this button
function __init(self, widget, action, holdAction, longHoldAction)
	_assert(widget)

	widget.mouseState = MOUSE_COMPLETE
	widget.distanceFromMouseDownMax = 0

	widget:addListener(EVENT_SHOW,
		function(event)
			--might have been left in a pressed state while waiting for long hold to occur, so "unpress"
			widget:setStyleModifier(nil)
			widget:reDraw()

			return EVENT_UNUSED
		end)

	widget:addListener(EVENT_MOUSE_ALL,
		function(event)
			local type = event:getType()
			if log:isDebug() then
				log:debug("event: ", event:tostring(), " state: ", widget.mouseState)
			end

			--NOTE: PRESS event ignored(consumed) since we handle press locally

			if type == EVENT_MOUSE_DOWN then
				--finish mouse sequence defensively in case the previous down never occurred
				finishMouseSequence(widget)

				updateMouseOriginOffset(widget, event)

				widget:setStyleModifier("pressed")
				widget.mouseState = MOUSE_DOWN

				widget:reDraw()
				return EVENT_CONSUME
			end

			if type == EVENT_MOUSE_HOLD
			   and widget.mouseState == MOUSE_DOWN
			   and holdAction
			   and not mouseExceededHoldDistance(widget) then

				widget.mouseState = MOUSE_HOLD

				--finish up unless a longHold is still to come
				if not longHoldAction then
					widget:setStyleModifier(nil)
					widget:reDraw()
					finishMouseSequence(widget)
				end
				return holdAction()
			end

			if type == EVENT_MOUSE_HOLD
			   and (widget.mouseState == MOUSE_DOWN or widget.mouseState == MOUSE_HOLD)
			   and longHoldAction
			   and not mouseExceededHoldDistance(widget) then

				widget.mouseState = MOUSE_LONG_HOLD

				widget:setStyleModifier(nil)
				widget:reDraw()

				return longHoldAction()
			end

			if type == EVENT_MOUSE_UP then
				local delta = 0
				local x, y = event:getMouse()
				if widget.mouseDownX then
					delta = math.abs(widget.mouseDownX - x)
				end
				if widget.mouseState ~= MOUSE_DOWN then
				        --not a press
					widget:setStyleModifier(nil)
					widget:reDraw()

					finishMouseSequence(widget)
					return EVENT_CONSUME
				end

				widget:setStyleModifier(nil)
				widget:reDraw()


				-- compare x to self.mouseDownX. if the pixel delta is past a threshhold, don't return the action
				-- XXX: delta currently hardcoded to 100px. seems to work well for SB Touch, but it's fairly platform specific to be hardcoding that number.
				finishMouseSequence(widget)

				if mouseInsidePressDistance(widget, event) and action and delta < 100 then
					--press
					return action()
				end
				--else nothing (i.e. cancel)
				return EVENT_CONSUME
			end

			if type == EVENT_MOUSE_DRAG then
				if widget.mouseState == MOUSE_COMPLETE then
					return EVENT_CONSUME
				end

				updateMouseOriginOffset(widget, event)

				if mouseInsidePressDistance(widget, event) then
					--change to pressed style, but since drag happens oftens, don't redraw each time if style hasn't changed
					--done defensively, in case DOWN wasn't seen.
					local modifier = "pressed"
					if widget:setStyleModifier() ~= modifier then
						widget:setStyleModifier(modifier)
						widget:reDraw()
					end
				else
					--dragging outside of buffer distance, change pressed style to normal, but since drag happens oftens, don't redraw each time if style hasn't changed
					if widget:setStyleModifier() ~= nil then
						widget:setStyleModifier(nil)
						widget:reDraw()
					end
				end

				return EVENT_CONSUME
			end

			return EVENT_CONSUME
		end)

	return widget
end




function finishMouseSequence(self)
	self.mouseState = MOUSE_COMPLETE
	self.mouseDownX = nil
	self.mouseDownY = nil
	self.distanceFromMouseDownMax = 0
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


function mouseExceededHoldDistance(self)
	return self.distanceFromMouseDownMax >= HOLD_BUFFER_DISTANCE_FROM_ORIGIN
end


function mouseInsidePressDistance(widget, event)
	local mouseX, mouseY = event:getMouse()

	local widgetX, widgetY, widgetW, widgetH = widget:getBounds()

	--shortest line distances
	local distanceX, distanceY

	if mouseX < widgetX then
		distanceX = widgetX - mouseX
	elseif mouseX > widgetX + widgetW then
		distanceX =  mouseX - (widgetX + widgetW)
	else
		distanceX = 0
	end

	if mouseY < widgetY then
		distanceY = widgetY - mouseY
	elseif mouseY > widgetY + widgetH then
		distanceY =  mouseY - (widgetY + widgetH)
	else
		distanceY = 0
	end

	if distanceX == 0 and distanceY == 0 then
		--inside mouse bounds
		return true
	end

	--shortest distance to button bounds
	local distance = math.sqrt( math.pow(distanceX ,2) + math.pow(distanceY ,2) )


	return distance < PRESS_BUFFER_DISTANCE_FROM_WIDGET
end
