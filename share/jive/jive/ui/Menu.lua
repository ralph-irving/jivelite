-----------------------------------------------------------------------------
-- Menu.lua
-----------------------------------------------------------------------------

--[[
=head1 NAME

jive.ui.Menu - A menu widget.

=head1 DESCRIPTION

A menu widget, extends L<jive.ui.Widget>.

=head1 SYNOPSIS

 -- Create a new menu
 local menu = jive.ui.Menu("menu")

=head1 STYLE

The Label includes the following style parameters in addition to the widgets basic parameters.

=over

B<itemHeight> : the height of each menu item.

=head1 METHODS

=cut
--]]


-- stuff we use
local _assert, ipairs, pairs, string, tostring, type, getmetatable, bit = _assert, ipairs, pairs, string, tostring, type, getmetatable, bit

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
local NumberLetterAccel    = require("jive.ui.NumberLetterAccel")
local Flick                = require("jive.ui.Flick")
local Timer                = require("jive.ui.Timer")
local System               = require("jive.System")

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
local EVENT_IR_PRESS       = jive.ui.EVENT_IR_PRESS
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

local CLEARPAD_PER_PIXEL_Y = 4248/272
local CHIRAL_GAIN          = .4

-- distance travelled from mouse origin where PRESS or HOLD event will be ignored and drag takes over (is relatively high due it being finger interface, finger may roll while waiting for hold to trigger)
local MOUSE_QUICK_SLOPPY_PRESS_DISTANCE = 24
local MOUSE_QUICK_DRAG_DISTANCE = 35
local MOUSE_QUICK_TOUCH_TIME_MS = 120
local MOUSE_SLOW_DRAG_DISTANCE = 20

local ITEMS_BEFORE_SCROLL_DEFAULT = 1
local GO_AS_CANCEL_TIME = 1500 -- (Note: under high load a quick double click might still trigger ht ecancel due to using getTicks() (which would include the even tloop time_. ideally we'd be based on input time, not getTicks, but lock doesn't always have easy access to input event)

--Mouse operation states

local MOUSE_COMPLETE = 0
local MOUSE_DOWN = 1
local MOUSE_SELECTED = 2
local MOUSE_DRAG = 3
local MOUSE_CHIRAL = 4

-- touch hardware supports smooth scrolling and requires additional state to be maintained
local TOUCH = System:hasTouch() or not System:isHardware()

-- our class
module(...)
oo.class(_M, Widget)



-- _selectedItem
-- returns the selected Item or nil if off stage
function _selectedItem(self)
	if self.selected then
		return self.widgets[self.selected - self.topItem + 1]
	else
		return self.widgets[self.topItem]
	end
end


-- _coerce
-- returns value coerced between 1 and max
local function _coerce(value, max)
	if value < 1 then
		return 1
	elseif value > max then
		return max
	end
	return value
end


local function _itemListener(self, item, event)

	local r = EVENT_UNUSED

	if item then
		r = self.itemListener(self, self.list, item, self.selected or 1, event)

		if r == EVENT_UNUSED then
			r = item:_event(event)
		end
	end
	return r
end


function _selectAndHighlightItemUnderPointer(self, event)
	--use item that was first under the finger, not when the selection occurs
	local x = self.mouseDownBoundsX
	local y = self.mouseDownBoundsY
	
	local i = (y - self.pixelOffsetY) / self.itemHeight --(h / self.numWidgets)

	local itemShift = math.floor(i)

	-- Smooth scrolling standard menu list (1 item per line) -> +1
	local tempVisibleWidgets = self.numWidgets + 1
	if self.itemsPerLine and self.itemsPerLine > 1 then
		-- Smooth scrolling grid view (4 items per line) -> +4
		tempVisibleWidgets = self.numWidgets + self.itemsPerLine

		itemShift = itemShift * self.itemsPerLine

		local sw, sh = Framework:getScreenSize()

		-- FIXME ********** - is this right?
		itemShift = itemShift + math.floor(x / (sw/self.itemsPerLine))
		--if x > (sw / 4 * 1) then itemShift = itemShift + 1 end
		--if x > (sw / 4 * 2) then itemShift = itemShift + 1 end
		--if x > (sw / 4 * 3) then itemShift = itemShift + 1 end
	end

	if itemShift >= 0 and itemShift < tempVisibleWidgets then
		--select item under cursor
		local selectedIndex = self.topItem + itemShift
		if selectedIndex <= self.listSize then
			self.usePressedStyle = true
			self:setSelectedIndex(selectedIndex, nil, true)
		else
			--outside of any menu item
			return false
		end
	else
		--outside of any menu item
		return false

	end

	return true
end

function resetDragData(self)
	self:setPixelOffsetY(0)
	self.dragYSinceShift = 0
end


function _updateScrollbar(self)
	local tempPixelOffsetY = self.pixelOffsetY
	local tempListSize = self.listSize
	
	if self.itemsPerLine and self.itemsPerLine > 1 then
		tempPixelOffsetY = tempPixelOffsetY * self.itemsPerLine
		-- Fix listSize in case the last line contains less than itemsPerLine items.
		if tempListSize % self.itemsPerLine ~= 0 then
			tempListSize = tempListSize - (tempListSize % self.itemsPerLine) + self.itemsPerLine
		end
	end
	
	local max = tempListSize * self.itemHeight
	local pos = (self.topItem - 1) * self.itemHeight - tempPixelOffsetY
	local size = self.numWidgets * self.itemHeight

	if size + pos > max then
		pos = max - size
	end
	self.scrollbar:setScrollbar(0, max, pos, size)
	
end


function setHideScrollbar(self, setting)
	self.hideScrollbar = setting
end


function handleDrag(self, dragAmountY, byItemOnly, forceAccel)

	if dragAmountY ~= 0 then
--		log:error("handleDrag dragAmountY: ", dragAmountY )

		self.dragYSinceShift = self.dragYSinceShift + dragAmountY
--		log:error("handleDrag dragYSinceShift: ", self.dragYSinceShift )

		if (self.dragYSinceShift > 0 and math.floor(self.dragYSinceShift / self.itemHeight) > 0) or
				(self.dragYSinceShift < 0 and math.floor(self.dragYSinceShift / self.itemHeight) < 0) then
			local itemShift = math.floor(self.dragYSinceShift / self.itemHeight)

			if self.itemsPerLine and self.itemsPerLine > 1 then
				itemShift = itemShift * self.itemsPerLine
			end

			self.dragYSinceShift = self.dragYSinceShift % self.itemHeight
			if itemShift > 0 and self.currentShiftDirection <= 0 then
				--changing shift direction, move cursor so scroll wil occur
				self:setSelectedIndex(self.topItem + self.numWidgets - 2, nil, true)
				self.currentShiftDirection = 1
			elseif itemShift < 0 and self.currentShiftDirection >= 0 then
				--changing shift direction, move cursor so scroll wil occur
				self:setSelectedIndex(self.topItem + 1, nil, true)
				self.currentShiftDirection = -1
			end



			if (self:isAtTop() and itemShift < 0) or (self:isAtBottom() and itemShift > 0) then
				--already at end
				self:resetDragData()
				self:_updateScrollbar()

			else
				--if resulting shift moves beyond bottom, reset offset
				if (self.topItem + itemShift < 1) or (self.topItem + itemShift + self.numWidgets >= self.listSize + 1) then
					self:resetDragData()
				else
					--here we are not at ends, so set offset
					if not byItemOnly then
						self:setPixelOffsetY(-1 * self.dragYSinceShift)
					else
						--by item only so fix the position so that the top item is visible in the same spot each time
						self:setPixelOffsetY(0)
					end
				end
				if log:isDebug() then
					log:debug("BY ITEM: self:scrollBy( itemShift ) ", itemShift, " self.pixelOffsetY: ", self.pixelOffsetY )
				end

				self:scrollBy( itemShift, true, false )
				self:_updateScrollbar()

				--should we bump?
				if not self.disableVerticalBump and self:isAtTop() and itemShift < 0 then
					self:getWindow():bumpDown()
				end

				if not self.disableVerticalBump and self:isAtBottom() and itemShift > 0 then
					self:getWindow():bumpUp()
				end

			end


		else
			--smooth scroll
			if not byItemOnly then
				self:setPixelOffsetY(-1 * self.dragYSinceShift)
			end

			if (self.topItem == 1 and self.currentShiftDirection == 1) or self:isAtBottom() then
				--already at end
				self:resetDragData()
			end

			if log:isDebug() then
				log:debug("BY PIXEL: Scroll offset by: ", self.pixelOffsetY, " item height: ", self.itemHeight)
			end
			self:_updateScrollbar()
			self:reDraw()
		end
	end
end


function snapToNearest(self)
	if math.abs(self.pixelOffsetY) > (self.itemHeight / 2) then
		self.flick:snap(1)
	else
		self.flick:snap(-1)
	end
end


function isWraparoundEnabled(self)
	return (self.wraparoundGap > 0)
end


function setDisableVerticalBump(self, value)
	self.disableVerticalBump = value
end

function _unpressSelectedItem(self)
	if _selectedItem(self) then
		_selectedItem(self):setStyleModifier(nil)
		_selectedItem(self):reDraw()
	end
end


function _showContextMenuAction(self, event)
	return (self:_showContextMenu())
end


function _showContextMenu(self)
	if not self.contextMenuManager then
		log:error("No contextMenuManager")
		return EVENT_CONSUMED
	end
	local contextMenuType = self.itemContextMenuTypeProvider(self)
	if contextMenuType then
		return (self.contextMenuManager:showContextMenu(contextMenuType, self))
	end

	log:debug("No contextMenuType for index: ", self:getSelectedIndex())

	return EVENT_CONSUMED
end


function _getMatchingChars(self, stringA, stringB)
	local validChars = ""

	for i = 1, stringA:len() do
		local char = string.sub(stringA, i, i)
		if string.find(stringB, char, 1, true) then
			validChars = validChars .. char
		end
	end

	return validChars
end

-- _eventHandler
-- manages all menu events
local function _eventHandler(self, event)

	local evtype = event:getType()
	if Framework.mostRecentInputType ~= "mouse" and evtype == EVENT_SHOW then
		local lastSelected = self._lastSelected

		if lastSelected then
			lastSelected:setStyleModifier(nil)
		end
	end
	
	if Framework.mostRecentInputType ~= "mouse" or evtype == EVENT_SHOW then
		self.usePressedStyle = false
	end

	if self.flickTimer and bit.band(evtype, bit.bor(EVENT_IR_ALL, EVENT_KEY_ALL, EVENT_SCROLL, EVENT_SHOW, EVENT_HIDE)) > 0 then
		--only all input other than mouse input, stop flick (mouse input will also stop flick but has special handling)
		log:debug("Flick stopped due to input: ", event:tostring())
		self:stopFlick()
	end

	if self.selectItemAfterFingerDownTimer and bit.band(evtype, bit.bor(EVENT_IR_ALL, EVENT_KEY_ALL, EVENT_SCROLL, EVENT_SHOW, EVENT_HIDE, EVENT_MOUSE_UP) ) > 0 then
		self.selectItemAfterFingerDownTimer:stop()
	end

	if evtype == EVENT_SCROLL then
		if self.locked == nil then
			self:resetDragData()
			if self.textMode then
				local textIndexes = self.textIndexHandler.getTextIndexes()
				--todo if size == 0
				local newIndex = (self.lastTextIndex and self.lastTextIndex or 0) + event:getScroll()
				
				--wraparound
				if newIndex > #textIndexes then
					newIndex = newIndex - #textIndexes
				elseif newIndex < 1 then
					newIndex = #textIndexes + newIndex				
				end

				self.accelKey = textIndexes[newIndex].key
					
				self:setSelectedIndex(textIndexes[newIndex].index, true )
				
				self.lastTextIndex = newIndex
				return EVENT_CONSUME
			end
			self:scrollBy(self.scroll:event(event, self.topItem, self.selected or 1, self.numWidgets, self.listSize))
			return EVENT_CONSUME
		end

	elseif evtype == EVENT_IR_PRESS then
		if self.textIndexHandler then
			local consume, switchCharacters, scrollLetter = self.numberLetterAccel:handleEvent(event, self.textIndexHandler.getValidChars())
			if consume then
				if scrollLetter then
					local newIndex = self.textIndexHandler.getIndex(scrollLetter)
					self:setSelectedIndex(newIndex)
					
					self.accelKey = scrollLetter
					self.accelKeyTimer:restart()
				end
				
				return EVENT_CONSUME
			end			
		end
				
	elseif evtype == EVENT_IR_DOWN or evtype == EVENT_IR_REPEAT then
		--todo add lock cancelling like in key press - let action hanlding take care of this
		if event:isIRCode("arrow_up") or event:isIRCode("arrow_down") then
			self:resetDragData()
			if self.locked == nil then
				local scrollAmount = self.irAccel:event(event, self.topItem, self.selected or 1, self.numWidgets, self.listSize)
				if self.textMode then
					self:dispatchNewEvent(EVENT_SCROLL, scrollAmount)
				else
					self:scrollBy(scrollAmount, true, evtype == EVENT_IR_DOWN)
				end
				return EVENT_CONSUME
			end
		end

	elseif evtype == ACTION then
		local action = event:getAction()

		if self.locked ~= nil then
			if action == "back" or action == "go_home" or action == "go_home_or_now_playing" then

				if type(self.locked) == "function" then
					self.locked(self)
				end
				self:unlock()

				return EVENT_CONSUME
			end
		else
			if (action == "go" or action == "back") and self.textMode then
				self.textMode = nil
				self.accelKey = nil
				self:reDraw()
				return EVENT_CONSUME
			end

			-- first send actions to selected widgets
			local r = _itemListener(self, _selectedItem(self), event)
			if r ~= EVENT_UNUSED then
				return r
			end

			if action == "text_mode" and self.textIndexHandler then
				--todo turn off text mode when leaving the menu
				self.textMode = not self.textMode
				if self.textMode then
					local textIndexes = self.textIndexHandler.getTextIndexes()
					
					if #textIndexes > 0 then
						--reset in case none found
						self.accelKey  = nil

						local selectedIndex = self:getSelectedIndex() or 1
						for i, wrapper in ipairs(textIndexes) do
							if wrapper.index > selectedIndex then
								break
							else
								self.accelKey  = wrapper.key
								self.lastTextIndex = i
							end
						end

--						log:warn("self.accelKey: ", self.accelKey)

					else
						
						self.accelKey  = nil
					end
				else
					self.accelKey  = nil
				end
				self:reDraw()
				return EVENT_CONSUME
				
			-- otherwise try default behaviour
			elseif action == "page_up" then
				--when paging up, top item becomes the bottom item
				if self.selected and self.selected > 1  then
					self:setSelectedIndex(self.topItem, true )
					self:scrollBy(-1 * (self.numWidgets - 2), true, false, false)
				end
				return EVENT_CONSUME

			elseif action == "page_down" then
				--when paging down, bottom item becomes the top item
				if not self.selected or self.selected < self.listSize then
					self:setSelectedIndex(self.topItem + self.numWidgets - 1, true )
					self:scrollBy(self.numWidgets - 2, true, false, false)
				end
				return EVENT_CONSUME

			elseif action == "go" then

				local r = self:dispatchNewEvent(EVENT_ACTION)

				if r == EVENT_UNUSED then
					self:playSound("BUMP")
					self:getWindow():bumpRight()
				end
				return r

			elseif action == "back" then
				if self.closeable then
					self:playSound("WINDOWHIDE")
					self:hide()
					return EVENT_CONSUME
				else
					self:playSound("BUMP")
					self:getWindow():bumpLeft()
					return EVENT_CONSUME
				end

			elseif string.match(action, "play_preset") then
				-- within menus treat preset button presses as special case to allow number keyboard based menu scrolling
				if self.textIndexHandler then
					local consume, switchCharacters, scrollLetter = 
						self.numberLetterAccel:handleEvent(event, self.textIndexHandler.getValidChars())
					if consume then
						if scrollLetter then
							local newIndex = self.textIndexHandler.getIndex(scrollLetter)
							self:setSelectedIndex(newIndex)
							
							self.accelKey = scrollLetter
							self.accelKeyTimer:restart()
						end

						return EVENT_CONSUME
					end
				end
			end
		end

	elseif evtype == EVENT_KEY_PRESS then
		local keycode = event:getKeycode()
		
		local scroll

		if (keycode == KEY_LEFT or keycode == KEY_RIGHT) and self.itemsPerLine and 
			(self.itemsPerLine == 1 or (keycode == KEY_LEFT and (self.selected == nil or self.selected == 1))) then
			if keycode == KEY_LEFT then
				Framework:pushAction("back")
			end
			if keycode == KEY_RIGHT then
				Framework:pushAction("go")
			end
			return EVENT_CONSUME
		elseif keycode == KEY_UP then
			scroll = -1 * (self.itemsPerLine or 1)
		elseif keycode == KEY_DOWN then
			scroll = 1 * (self.itemsPerLine or 1)
		elseif keycode == KEY_LEFT then
			scroll = -1
		elseif keycode == KEY_RIGHT then
			scroll = 1
		end

		if scroll and self.locked == nil then
			if self.textMode then
				self:dispatchNewEvent(EVENT_SCROLL, scroll)
			else
				self:scrollBy(scroll, true, false, false)
			end
			return EVENT_CONSUME
		end

		if self.locked == nil then
			self:resetDragData()
			-- send keys to selected widgets, otherwise ignore, will return as actions
			local r = _itemListener(self, _selectedItem(self), event)
			if r ~= EVENT_UNUSED then
				return r
			end
		end

	elseif self.locked == nil and evtype == EVENT_MOUSE_HOLD then

		if self.mouseState == MOUSE_DOWN then
			if self.scrollbar:mouseInside(event) or self.sliderDragInProgress then
				--might want to forward these to scrollbar, but there is no current need for that
			else
				--in body area
				--return _showContextMenuAction(self, event)
				if self.flick.flickInterruptedByFinger then
					--flick was interrupted so don't select the item under cursor (drag still allowed)
					return EVENT_CONSUME
				end
				
				Framework:pushAction("add")
				return EVENT_CONSUME
			end
		end

--		self.usePressedStyle = false
--		self:_unpressSelectedItem()

		return EVENT_CONSUME
	elseif self.locked == nil and evtype == EVENT_MOUSE_PRESS then

		if self.scrollbar:mouseInside(event) then

			-- forward event to scrollbar
			local result =  self.scrollbar:_event(event)
			_scrollList(self)

			return result


		else
			--PRESS now handled in UP
			return EVENT_CONSUME
		end

	elseif self.locked == nil and (evtype == EVENT_MOUSE_DOWN or
		evtype == EVENT_MOUSE_MOVE or
		evtype == EVENT_MOUSE_DRAG) then

		if evtype == EVENT_MOUSE_DOWN then
			--sometimes up doesn't occur so we must again try to reset state
			-- note: sometimes down isn't called either (if drag starts outside of bounds), so bug still exists where scrollbar drag falsely continues
			self.sliderDragInProgress = false
			self.currentShiftDirection = 0
			self.flick:resetFlickData()
			finishMouseSequence(self)

			self.mouseState = MOUSE_DOWN

			--stop any running flick on contact
			if self.flick.flickInProgress then
				log:debug("**** Stopping flick due to finger down")

				self.flick:stopFlick(true)
			end

		end

		--Note: on a down outside the scrollbar boundary, we don't want to forward this to the scrollbar
		--Normally that should never happen, but will if an up event is nevet sent to this widget, which would have cleared the
		-- sliderDragInProgress flag
		if self:mouseInside(event) and not self.scrollbar:mouseInside(event) and self.mouseState == MOUSE_CHIRAL then
			--for chiral, let body area take over focus again
			self.sliderDragInProgress = false
		end

		if self.scrollbar:mouseInside(event) or (self.sliderDragInProgress and evtype ~= EVENT_MOUSE_DOWN ) then
			if (evtype ~= EVENT_MOUSE_MOVE) then
				--allows slider drag to continue even when listitem area is entered
				-- a more comprehensive solution is needed so that drag of a slider is respected no matter
				-- where the mouse cursor is on the screen
				self.sliderDragInProgress = true
			end

			--clear any selected item
			self.usePressedStyle = false
			_selectedItem(self):setStyleModifier(nil)

			--zero out offset (scrollbar currently only moves discretely)
			self:setPixelOffsetY(0)
			
			-- forward event to scrollbar
			local r = self.scrollbar:_event(event)
			_scrollList(self)
			if evtype == EVENT_MOUSE_DOWN then
				--slider doesnt' consume the DOWN, but we require it to be consumed so menu is marked as the mouse focus widget.  -- this should now be fixed no. TODO: review extra event resutl check and remove.
				r = EVENT_CONSUME
			end
			return r

		else
			--mouse is inside menu region
			local x,y,w,h = self:mouseBounds(event)
			local i = y / self.itemHeight --(h / self.numWidgets)

			local itemShift = math.floor(i)

			if false and not self:isTouchMouseEvent(event) then
				--disabling regular desktop mouse behavior - favoring drag style for now
				--disabling regular desktop mouse behavior - favoring drag style for now
				--disabling regular desktop mouse behavior - favoring drag style for now
--				if evtype == EVENT_MOUSE_DRAG then
--					self:setSelectedIndex(self.topItem + itemShift)
--					_scrollList(self)
--				elseif (itemShift >= 0 and itemShift < self.numWidgets) then
--					-- menu selection follows mouse, but no scrolling occurs
--					self:setSelectedIndex(self.topItem + itemShift)
--				end
			else --touchpad - for now to test on desktop mouse Right-Click acts as single finger touch

				if evtype == EVENT_MOUSE_DOWN then
					self.flick:updateFlickData(event)

					updateMouseOriginOffset(self, event)

					if self.flick.flickInterruptedByFinger then
						--flick was interrupted so don't select the item under cursor (drag still allowed)
						return EVENT_CONSUME
					end

					  -- first unhighlight last selected item, why this needed? maybe during a locked situation (but shouldn't unlocking clear it - todo: investigate and remove this if it can be)
	                                self.usePressedStyle = false
					self:_unpressSelectedItem()

					if self.selectItemAfterFingerDownTimer then
						self.selectItemAfterFingerDownTimer:stop()
					end
					self.selectItemAfterFingerDownTimer = Timer(MOUSE_QUICK_TOUCH_TIME_MS,
							       function()
									self:_selectAndHighlightItemUnderPointer(event)
							       end,
							       true)
				       self.selectItemAfterFingerDownTimer:start()

				elseif evtype == EVENT_MOUSE_DRAG then
					if self.mouseState == MOUSE_COMPLETE then
						return EVENT_CONSUME
					end

					updateMouseOriginOffset(self, event)
					self.flick:updateFlickData(event)

					if not mouseExceededBufferDistance(self, MOUSE_SLOW_DRAG_DISTANCE ) then
						return EVENT_CONSUME
					end

					if event:getTicks() - self.mouseDownT < MOUSE_QUICK_TOUCH_TIME_MS
					    and not mouseExceededBufferDistance(self, MOUSE_QUICK_DRAG_DISTANCE ) then
						return EVENT_CONSUME
					end


					--unhighlight any selected item
					self.usePressedStyle = false
					_selectedItem(self):setStyleModifier(nil)
					self.selectItemAfterFingerDownTimer:stop()

					--collect drag data
					if ( self.dragOrigin.y == nil) then
						self.dragOrigin.x, self.dragOrigin.y = event:getMouse();
					end

					local mouseX, mouseY, fingerCount, fingerWidth, fingerPressure, chiralValue  = event:getMouse()
					local dragAmountY = self.dragOrigin.y - mouseY

					if chiralValue then
						if self.mouseState ~= MOUSE_CHIRAL then
							--clear old chiral values
							self.lastChirals = {}

						else
							--did direction change, if clear old values
							local lastChiral = self.lastChirals[#self.lastChirals].value
							if lastChiral * chiralValue < 1 then
								--direction shift
								self.lastChirals = {}
							end
						end

						self.mouseState = MOUSE_CHIRAL


						--moving average for smoothing
						local now = event:getTicks()
						table.insert(self.lastChirals, {value = chiralValue, ticks = now } )


						local sampleCount = 300
						if #self.lastChirals >= sampleCount then
							table.remove(self.lastChirals, 1)
						end

						local chiralTotal = 0
						local chiralPoints = 0
						local longChiralTotal = 0
						local longChiralPoints = 0
						for i, entry in ipairs(self.lastChirals) do
							local age = now - entry.ticks
--							log:error("age: ", age)

							if age < 500 then
								--only include values from last few moments
								chiralTotal = chiralTotal + entry.value
								chiralPoints = chiralPoints + 1
							end
							if age < 3000 then
								--only include values from last few moments
								longChiralTotal = longChiralTotal + entry.value
								longChiralPoints = longChiralPoints + 1
							end
						end
--						log:error("longChiralPoints ", longChiralPoints)


						local chiralAvg = chiralTotal/chiralPoints
						local pixels = chiralAvg/CLEARPAD_PER_PIXEL_Y * CHIRAL_GAIN

						local direction = math.abs(pixels) / pixels

						local longChiralAvg = longChiralTotal/longChiralPoints
						local longPixels = longChiralAvg/CLEARPAD_PER_PIXEL_Y * CHIRAL_GAIN

--						log:error("dragAmountY: ", dragAmountY, " ^2: ", dragAmountY * math.abs(dragAmountY), "2 second value:", (longChiralAvg/CLEARPAD_PER_PIXEL_Y * CHIRAL_GAIN))


						--Use non-linear response, if long moving average is above a threshold
						local byItemOnly = false
						local threshold1 = 4
						local threshold2 = 5.5
						if longChiralPoints > 200 and math.abs(longPixels) > threshold2 and math.abs(pixels) > 1.5 then
							dragAmountY = direction * math.abs(pixels) * math.pow(math.abs(longPixels/threshold2), 5)
							byItemOnly = true
						elseif longChiralPoints > 150 and math.abs(longPixels) > threshold1 and math.abs(pixels) > 2 then
							dragAmountY = direction * math.abs(pixels) * math.pow(math.abs(longPixels/threshold1), 3)
							byItemOnly = false
						else
							dragAmountY = pixels
						end
--						log:error("pixels ", pixels, " dA: ", dragAmountY )

						self:handleDrag(dragAmountY, byItemOnly, true)
					else
						self.mouseState = MOUSE_DRAG
						self:handleDrag(dragAmountY)
					end

					--reset origin
					self.dragOrigin.x, self.dragOrigin.y = mouseX, mouseY
					
--					log:error("self.pixelOffsetY                              : ", self.pixelOffsetY)

                               end
			end
			return EVENT_CONSUME
		end
		
	elseif evtype == EVENT_MOUSE_UP then
		--turn off accel keys (may have been on from a scrollbar slide)
		if (self.accel or self.accelKey) then
			self.accel = false
			self.accelKey = nil
			self:reLayout()
		end

		if self.sliderDragInProgress then
			finishMouseSequence(self)

			local result = self.scrollbar:_event(event)

			--turn off accel keys (may have been on from a scrollbar slide)
			if (self.accel or self.accelKey) then
				self.accel = false
				self.accelKey = nil
				self:reDraw()
			end

			return result
		end

		self.dragOrigin.x, self.dragOrigin.y = nil, nil;
		if self.mouseState == MOUSE_COMPLETE or self.sliderDragInProgress then
			if self.lockedT and Framework:getTicks() > self.lockedT + GO_AS_CANCEL_TIME then
				if type(self.locked) == "function" then
					self.locked(self)
				end
				self:unlock()
				return EVENT_CONSUME
			end

			return (finishMouseSequence(self))
		end

		local x1, y1 = event:getMouse()

		if self.mouseState == MOUSE_DRAG or self.mouseState == MOUSE_CHIRAL then

			--unhighlight any selected item
			self.usePressedStyle = false
			_selectedItem(self):setStyleModifier(nil)


			if self.mouseState == MOUSE_DRAG then
				--Should flick occur?
				local flickSpeed, flickDirection = self.flick:getFlickSpeed(self.itemHeight, event:getTicks())

				if flickSpeed then
					-- XXX - though flicking is a bit jumpy, it's still better than not to have it
--					if self.itemsPerLine and self.itemsPerLine > 1 then
--						-- FIXME: Flick doesn't work right with grid view (jumpy)
--						log:info("Not invoking flick in grid view mode.")
--					else
						self.flick:flick(flickSpeed, flickDirection)
--					end
				elseif self.snapToItemEnabled and (self.pixelOffsetY and self.pixelOffsetY ~= 0) then
					self:snapToNearest()					
				end
			end

			self.flick:resetFlickData()
			return (finishMouseSequence(self))
		end

		if mouseExceededBufferDistance(self, MOUSE_QUICK_SLOPPY_PRESS_DISTANCE) then
			--too far to be considered a "sloppy quick select"
			--would happen on a fast press under the hold threshold, since drag would have already picked up a slow drag at this distance
			-- so ignore this touch in the "grey zone"

			--unhighlight any selected item
			self.usePressedStyle = false
			_selectedItem(self):setStyleModifier(nil)

			return (finishMouseSequence(self))
		end

		--treat as a PRESS

		if self.flick.flickInterruptedByFinger then
			if self.snapToItemEnabled and (self.pixelOffsetY and self.pixelOffsetY ~= 0) then
				self:snapToNearest()					
			end			
			--flick just stopped (on the down event), so ignore this press - do the same for hold when implemented
			self.flick.flickInterruptedByFinger = nil
			return (finishMouseSequence(self))
		end

		if not self:_selectAndHighlightItemUnderPointer(event) then
			--tried to select but mouse not under a selectable area
			return (finishMouseSequence(self))
		end

		finishMouseSequence(self)

		--relayout so selected item is shown during transition
		self:reLayout()

		--need to allow screen to be repainted before event is sent, so put on a 0-length timer

		local tempDispatchTimer = Timer(0,
		       function()
				local r = self:dispatchNewEvent(EVENT_ACTION)
				if r == EVENT_UNUSED then
					self:playSound("BUMP")
					self:getWindow():bumpRight()
				end

				self.usePressedStyle = false
				self:_unpressSelectedItem()
		       end,
		       true)

		tempDispatchTimer:start()

		return EVENT_CONSUME




	elseif evtype == EVENT_SHOW or
		evtype == EVENT_HIDE then

               if evtype == EVENT_SHOW then
			local window = self:getWindow()
		end

		for i,widget in ipairs(self.widgets) do
			widget:_event(event)
		end
		self.scrollbar:_event(event)

		self:reLayout()
		return EVENT_UNUSED
	end

	if self.locked ~= nil then
		return EVENT_UNUSED		
	end
	
	-- other events to selected widgets
	return _itemListener(self, _selectedItem(self), event)
end


function isTouchMouseEvent(self, mouseEvent)
	local x, y, fingerCount = mouseEvent:getMouse()

	return fingerCount ~= nil
end



--[[

=head2 jive.ui.Menu(style)

Constructs a new Menu object. I<style> is the widgets style.

=cut
--]]
function __init(self, style, itemRenderer, itemListener, itemAvailable, contextMenuManager, itemContextMenuTypeProvider)
	_assert(type(style) == "string")
	_assert(type(itemRenderer) == "function")
	_assert(type(itemListener) == "function")
	_assert(itemAvailable == nil or type(itemAvailable) == "function")

	local obj = oo.rawnew(self, Widget(style))
	obj.irAccel = IRMenuAccel()
	
	obj.scroll = ScrollAccel(function(...)
					 if itemAvailable then
						 
					 else
						 return true
					 end
				 end)
	obj.scrollbar = Scrollbar("scrollbar",
				  function(_, value)
				          --value is in pixels, convert to items
				          local itemValue = math.floor(value/obj.itemHeight) + 1
  					  obj.accel = true
					  obj:setSelectedIndex(itemValue)
				  end)


	obj.scrollbar.parent = obj
	obj.layoutRoot = true
	obj.closeable = true

	obj.mouseState = MOUSE_COMPLETE
	obj.distanceFromMouseDownMax = 0

	obj.itemRenderer = itemRenderer
	obj.itemListener = itemListener
	if itemAvailable then
		obj.scroll = ScrollAccel(function(...) return itemAvailable(obj, obj.list, ...) end)
	else
		obj.scroll = ScrollAccel()
	end


	obj.list = nil
	obj.listSize = 0
	obj.scrollDir = 0

	obj.widgets = {}        -- array of widgets
	obj.lastWidgets = {}    -- hash of widgets
	obj.numWidgets = 0      -- number of visible widges
	obj.topItem = 1         -- index of top widget
	obj.selected = nil      -- index of selected widget
	obj.accel = false       -- true if the window is accelerated
	obj.dir = 0             -- last direction of scrolling


	obj.wraparoundGap = 0
	obj.itemsBeforeScroll = ITEMS_BEFORE_SCROLL_DEFAULT
	obj.noBarrier = false

	obj.usePressedStyle = true

	obj.dragOrigin = {}
	obj.dragYSinceShift = 0
	obj.pixelOffsetY = 0
	obj.currentShiftDirection = 0

	obj.flick = Flick(obj)

	-- timer to drop out of accelerated mode
	obj.accelTimer = Timer(200,
			       function()
				       obj.accel = false
				       obj:reLayout()
			       end,
			       true)
			       
	obj.accelKeyTimer = Timer(500,
					function()
				    	obj.accelKey = nil
						obj:reLayout()	
					end,
					true)

	obj.numberLetterAccel = NumberLetterAccel(function() end)

--	obj:addActionListener("context_menu", obj, _showContextMenuAction)
	obj.contextMenuManager = contextMenuManager
	obj.itemContextMenuTypeProvider = itemContextMenuTypeProvider

	obj:addListener(EVENT_ALL,
			 function (event)
				return (_eventHandler(obj, event))
			 end)
	
	return obj
end


function finishMouseSequence(self)
	self.mouseState = MOUSE_COMPLETE

	self.mouseDownX = nil
	self.mouseDownY = nil
	self.mouseDownT = nil
	self.distanceFromMouseDownMax = 0

	self.sliderDragInProgress = false

	return EVENT_CONSUME
end


function updateMouseOriginOffset(self, event)
	local x, y = event:getMouse()


	if not self.mouseDownX then
		--used for current slected item calculation (though shouldn't regular mouse x and y be used???)
		local boundsX,boundsY = self:mouseBounds(event)
		self.mouseDownBoundsX = boundsX
		self.mouseDownBoundsY = boundsY

		--new drag, set origin
		self.mouseDownX = x
		self.mouseDownY = y
		self.mouseDownT = event:getTicks()
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


--[[

=head2 jive.ui.Menu:setItems(list, listSize, min, max)

Set the items in the menu. list is the data structure containing the menu data
in a format suitable for the itemRenderer and itemListener. listSize is the
total number of items in the menu. Optionally min and max indicate the range of
menu items that have changed.

=cut
--]]
function setItems(self, list, listSize, min, max)
	self.list = list
	self.listSize = listSize

	if min == nil then
		min = 1
	end
	if max == nil then
		max = listSize
	end

	-- check if the scrollbar position is out of range
	if self.selected and self.selected > listSize then
		self.selected = listSize
	end

	-- update if changed items are visible
	local topItem, botItem = self:getVisibleIndicies()
	if not (max < topItem or min > botItem) then
		self:reLayout()
	end
end


--[[

=head2 jive.ui.Menu:setCloseable(isCloseable)

Sets if this menu is closeable. A closeable menu will pop from the window stack on the left button, if it is not closeable the menu will bump instead.

=cut
--]]
function setCloseable(self, isCloseable)
	_assert(type(isCloseable) == "boolean")

	self.closeable = isCloseable
end


--[[

=head2 jive.ui.Menu:getVisibleIndices()

Returns the indicies of the top and bottom visible items.

=cut
--]]
function getVisibleIndicies(self)
	local min = self.topItem
	local max = min + self.numWidgets - 1
	
	if max > self.listSize then
		return min, min + self.listSize
	else
		return min, max
	end
end


--[[

=head2 jive.ui.Menu:isScrollable()

Returns true if the menu is scrollable, otherwise it returns false.

=cut
--]]
function isScrollable(self)
	return self.listSize > self.numWidgets
end


--required functions for Drag module
function isAtBottom(self)
	return self.topItem + self.numWidgets >= self.listSize + 1
end


function isAtTop(self)
	return self.topItem == 1 and self.pixelOffsetY == 0
end

--[[

=head2 jive.ui.Menu:getSelectedIndex()

Returns the index of the selected item.

=cut
--]]
function getSelectedIndex(self)
	return self.selected or 1
end


--[[

=head2 jive.ui.Menu:getMiddleIndex()

Returns the index of the middle onscreen item. returns nil if numWidgets is not odd (thus no middle item)

=cut
--]]
function getMiddleIndex(self)
	if self.numWidgets % 2 == 0 then
		return nil
	end
	return self.topItem + ((self.numWidgets - 1) /2)
end


--[[

=head2 jive.ui.Menu:getSelectedItem()

Returns the widget of the selected item.

=cut
--]]
function getSelectedItem(self)
	return _selectedItem(self)
end

--[[

=head2 jive.ui.Menu:getItems()

Returns the list items from a menu

=cut
--]]
function getItems(self)
	return self.list
end

--[[

=head2 jive.ui.Menu:getSize()

Returns the list items from a menu

=cut
--]]
function getSize(self)
	return self.listSize
end

--[[

=head2 jive.ui.Menu:setSelectedIndex(index, coerce, noReLayout)

Sets I<index> as the selected menu item.
if I<coerce> is true, index < 1 will be treat as 1 and index > listSize will be treated as listSize.

=cut
--]]
function setSelectedIndex(self, index, coerce)
	_assert(type(index) == "number", "setSelectedIndex index is not a number: ", index)

	if coerce then
		if index < 1 then
			index = 1
		elseif index > self.listSize then
			index = self.listSize 
		end
	end

	if index >= 1 and index <= self.listSize then
		self.selected = index
		if not noReLayout then
			self:reLayout()
		end
	end
end


function setPixelOffsetY(self, value)
	self.pixelOffsetY = value
end


function isAccelerated(self)
	return self.accel, self.dir, self.selected
end


--[[

=head2 jive.ui.Menu:lock(self, cancel)

Lock the menu. Pressing back unlocks it and calls the I<cancel> closure. The style of the selected menu item is changed. This can be used for a loading animation.

=cut
--]]
function lock(self, cancel)
	self.locked = cancel or true
	self.lockedT = Framework:getTicks()
	self:reLayout()

	-- don't allow screensaver while locked
	local window = self:getWindow()
	self.lockedScreensaver = window:getAllowScreensaver()
	window:setAllowScreensaver(false)
end


--[[

=head2 jive.ui.Menu:lock(self, cancel)

Unlock the menu.

=cut
--]]
function unlock(self)
	if not self.locked then
		--already unlocked, so exit, but first make sure allowScreensaver is properly returned if needed
		if self.lockedScreensaver ~= nil then
			window:setAllowScreensaver(self.lockedScreensaver)
			self.lockedScreensaver = nil
		end

		return
	end

	-- restore screensaver setting
	local window = self:getWindow()
	window:setAllowScreensaver(self.lockedScreensaver)
	self.lockedScreensaver = nil

	self.locked = nil
	self:reLayout()
end

function getItemsBeforeScrollGap(self)
	if Framework:isMostRecentInput("mouse") then
		return 0
	end
	
	if self.itemsBeforeScroll > 1 then
		return self.itemsBeforeScroll
	end
	
	return 0
end
	
function getEffectiveItemsBeforeScroll(self)
	if self.mouseState ~= MOUSE_COMPLETE then
		--if mouse then user selects item under cursor. On completion, the selection point will be moved to the middle item instead.
		return ITEMS_BEFORE_SCROLL_DEFAULT
	else
		return self.itemsBeforeScroll
	end
end

--[[

=head2 jive.ui.Menu:scrollBy(scroll, allowMultiple, isNewOperation, forceAccel)

Scroll the menu by I<scroll> items. If I<scroll> is negative the menu scrolls up, otherwise the menu scrolls down. By
 default, restricts to scrolling one item unless at the edge of the visible list. If I<allowMultiple> is non-nil,
 ignore that behavior and scroll the requested scroll amount. If I<forceAccel> is non-nil, big letter accelerator will be
 forced on or off for true or false.

=cut
--]]
function scrollBy(self, scroll, allowMultiple, isNewOperation, forceAccel)
	_assert(type(scroll) == "number")

	local selected = (self.selected or 1)

	-- acceleration
	local now = Framework:getTicks()
	local dir = scroll > 0 and 1 or -1

--[[
	if dir == self.scrollDir and now - self.scrollLastT < 250 then
		if self.scrollAccel then
			self.scrollAccel = self.scrollAccel + 1
			if     self.scrollAccel > 50 then
				scroll = dir * math.max(math.ceil(self.listSize/50), math.abs(scroll) * 16)
			elseif self.scrollAccel > 40 then
				scroll = scroll * 16
			elseif self.scrollAccel > 30 then
				scroll = scroll * 8
			elseif self.scrollAccel > 20 then
				scroll = scroll * 4
			elseif self.scrollAccel > 10 then
				scroll = scroll * 2
			end
		else
			self.scrollAccel = 1
		end
	else
		self.scrollAccel = nil
	end
--]]
	self.scrollDir   = dir
	self.scrollLastT = now

	-- restrict to scrolling one item unless at the edge of the
	-- visible list, to stop it from visibly missing items when using the controller scroll wheel.
	if scroll > 0 then
		self.dir = 1
		self.accel = scroll > 1

		if not allowMultiple and selected < self.topItem + self.numWidgets - 2 then
			scroll = 1
		end

	elseif scroll < 0 then
		self.dir = -1
		self.accel = scroll < -1

		if not allowMultiple and selected > self.topItem + 1 then
			scroll = -1
		end
	else
		self.dir = 0
		self.accel = false
	end

	if forceAccel ~= nil then
		self.accel = forceAccel
	end

	if self.accel then
		self.accelTimer:restart()
		self.accelKeyTimer:restart()
	else
		self.accelTimer:stop()
	end

	selected = selected  + scroll

	if self.noBarrier then
		isNewOperation = true
	elseif self:getItemsBeforeScrollGap() and self:getItemsBeforeScrollGap() ~= 0 then
		isNewOperation = false
	end
	--for input sources such as ir remote, follow the "ir remote" list behavior seen on classic players
	if isNewOperation == false then
		if selected > self.listSize - self:getItemsBeforeScrollGap() then
			selected = self.listSize - self:getItemsBeforeScrollGap()
		elseif selected < 1 + self:getItemsBeforeScrollGap()then
			selected = _coerce(1, self.listSize) + self:getItemsBeforeScrollGap()
		end	
	elseif isNewOperation == true then
		if selected > self.listSize then
			selected = _coerce(1, self.listSize)
		elseif selected < 1 then
			selected = self.listSize
		end	
		   
	else -- isNewOperation nil, so use breakthrough barrier
		-- virtual barrier when scrolling off the ends of the list
		if self.barrier and Framework:getTicks() > self.barrier + 1400 then
			self.barrier = nil
		end
	
		if selected > self.listSize then
			selected = self.listSize
			if self.barrier == nil then
				self.barrier = Framework:getTicks()
			elseif Framework:getTicks() > self.barrier + 900 then
				selected = _coerce(1, self.listSize)
				self.barrier = nil
			end
	
		elseif selected < 1 then
			selected = _coerce(1, self.listSize)
			if self.barrier == nil then
				self.barrier = Framework:getTicks()
			elseif Framework:getTicks() > self.barrier + 900 then
				selected = self.listSize
				self.barrier = nil
			end
	
		else
			self.barrier = nil
		end
	end


	-- if selection has change, play click and redraw
	if (self.selected ~= nil and selected ~= self.selected) or (self.selected == nil and selected ~= 0) then
		if self.mouseState ~= MOUSE_DRAG and self.mouseState ~= MOUSE_CHIRAL and not self.flick.flickInProgress then
			--todo come up with more comprehensive "when to click" design once the requirement is better understood
			self:playSound("CLICK")
		end
		self.selected = selected

		_scrollList(self)
		self:reLayout()
	end
end


-- move the list to keep the selection in view, called during layout
function _scrollList(self)

	-- empty list, nothing to do
	if self.listSize == 0 then
		return
	end

	-- make sure selected stays in bounds
	local selected = _coerce(self.selected or 1, self.listSize)
	local topItem = self.topItem

	if self.numWidgets == 1 then
		self.topItem = selected
		return
	end

--	log:info("*********")
--	log:info("*** listSize: ", self.listSize, " numWid: ", self.numWidgets)
--	log:info("*** topItem ", topItem, " selected: ", selected)

	if self.itemsPerLine and self.itemsPerLine > 1 then
		
		--  show the first item if the first item is selected
		if selected == 1 then
			topItem = 1
			--		log:info("*** c1 ", topItem)
			
			--  otherwise, we've scrolled out of the view (up)
		elseif selected <= topItem - 1 then
			topItem = selected - ((selected - 1) % self.itemsPerLine)
			--		log:info("*** c2 ", topItem)
			
			-- show the last item if it is selected
		elseif selected == self.listSize then
			if self.listSize < self.numWidgets or self.numWidgets == 0 then
				topItem = 1
				--			log:info("*** c3a ", topItem)
			else
				topItem = selected - ((selected - 1) % self.itemsPerLine) - self.itemsPerLine
				if self.pixelOffsetY < -10 then
					topItem = topItem - self.itemsPerLine
				end
				--			log:info("*** c3b ", topItem)
			end
			
			-- otherwise, we've scrolled out of the view (down)
		elseif selected >= topItem + self.numWidgets then
			topItem = selected - ((selected - 1) % self.itemsPerLine) - self.itemsPerLine
			
			--		log:info("*** c4 ", topItem)
			--		log:info("*** poy ", self.pixelOffsetY)
			-- Smooth scrolling - up to three lines visible (12 widgets)
			if self.pixelOffsetY < -10 then
				topItem = topItem - self.itemsPerLine
			end
			--		log:info("*** c4 ", topItem)
			
		end
		
	else
		
		-- show the first item if the first item is selected
		if selected == 1 then
			topItem = 1
			
			-- otherwise, try to leave one item above the selected one (we've scrolled out of the view)
		elseif selected <= topItem  + ( self.itemsBeforeScroll - 1 ) then
			-- if we land here, selected > 1 so topItem cannot become < 1
			topItem = selected - self:getEffectiveItemsBeforeScroll() 
			
			-- show the last item if it is selected
		elseif selected == self.listSize then
			if self.listSize < self.numWidgets or self.numWidgets == 0 then
				topItem = 1
			else
				topItem = self.listSize - self.numWidgets + 1
			end
			
			-- otherwise, try to leave one item below the selected one (we've scrolled out of the view)
		elseif selected >= topItem + self.numWidgets - self.itemsBeforeScroll then
			topItem = selected - self.numWidgets + self:getEffectiveItemsBeforeScroll() + 1
		end
	end
	
	self.topItem = topItem
end


function _updateWidgets(self)

	local iPL = 1
	if self.itemsPerLine and self.itemsPerLine > 1 then
		iPL = self.itemsPerLine
	end

	local jumpScrollBottom = self.topItem + (self.numWidgets / iPL)
	if self.mouseState ~= MOUSE_COMPLETE then
		--when touch activity in progress, allow one more bottom item to be selected without jump, for half onscreen items
		jumpScrollBottom = jumpScrollBottom + iPL
	end
	local selected = _coerce(self.selected or 1, self.listSize)
	if #self.widgets > 0 and (selected < self.topItem
		or selected >= jumpScrollBottom) then
		-- update the list to keep the selection in view
		_scrollList(self)
	end

	local indexSize = self.numWidgets + iPL -- one extra for smooth scrolling
	local min = self.topItem
	local max = self.topItem + indexSize - 1
	if max > self.listSize then
		max = self.listSize
	end
	local indexSize = (max - min) + 1


	-- create index list
	local indexList = {}
	for i = min,max do
		indexList[#indexList + 1] = i
	end

	local lastSelected = self._lastSelected
	local lastSelectedIndex = self._lastSelectedIndex
	local lastHighlightedIndex = self._lastHighlightedIndex
	local nextSelectedIndex = self.selected or 1

	-- clear focus -- todo support "no highlight scroll"
	if lastSelectedIndex ~= nextSelectedIndex then
		if lastSelected then
			_itemListener(self, lastSelected, Event:new(EVENT_FOCUS_LOST))
		end
	end

	-- reorder widgets to maintain the position of the selected widgets
	-- this avoids having to change the widgets skin modifier, and
	-- therefore avoids having to reskin the widgets during scrolling.
	if self._lastSelectedOffset then
		local lastSelectedOffset = self._lastSelectedOffset
		local selectedOffset = self.selected and self.selected - self.topItem + 1 or self.topItem

		if lastSelectedOffset ~= selectedOffset then
			self.widgets[lastSelectedOffset], self.widgets[selectedOffset] = self.widgets[selectedOffset], self.widgets[lastSelectedOffset]

			self._lastSelected = self.widgets[lastSelectedOffset]
		end
	end

	-- render menu widgets
	self.itemRenderer(self, self.list, self.widgets, indexList, indexSize)

	-- show or hide widgets
	local nextWidgets = {}
	local lastWidgets = self.lastWidgets

	for i = 1, indexSize do

		local widget = self.widgets[i]

		if widget then
			if widget.parent ~= self then
				widget.parent = self
				if TOUCH then
					widget:setSmoothScrollingMenu(self)
				end
				widget:dispatchNewEvent(EVENT_SHOW)
			end

			lastWidgets[widget] = nil
			nextWidgets[widget] = 1
		end
	end

	for widget,i in pairs(lastWidgets) do
		widget:dispatchNewEvent(EVENT_HIDE)
		widget.parent = nil
		if TOUCH then
			widget:setSmoothScrollingMenu(nil)
		end
	end

	self.lastWidgets = nextWidgets

	-- unreference menu widgets out off stage
	for i = indexSize + 1, #self.widgets do
		self.widgets[i] = nil
	end


	local nextSelected = _selectedItem(self)

	-- clear selection
	if lastSelected and lastSelected ~= nextSelected then
		lastSelected:setStyleModifier(nil)
	end

	-- set selection and focus
	if nextSelected then
		if self.accel then
			self.accelKey = nextSelected:getAccelKey()
		end

		if self.locked then
			nextSelected:setStyleModifier("locked")
		else
			if self.usePressedStyle then
				nextSelected:setStyleModifier("pressed")
			else
				if Framework.mostRecentInputType == "mouse" then
					nextSelected:setStyleModifier(nil)
				else
					nextSelected:setStyleModifier("selected")
				end
			end
		end

		if Framework.mostRecentInputType == "mouse" then
			if self.usePressedStyle and lastHighlightedIndex ~= nextSelectedIndex then
				_itemListener(self, nextSelected, Event:new(EVENT_FOCUS_GAINED))
			end
		else
			if lastSelectedIndex ~= nextSelectedIndex then
				_itemListener(self, nextSelected, Event:new(EVENT_FOCUS_GAINED))
			end
		end
	end

	self._lastSelected = nextSelected
	self._lastSelectedIndex = nextSelectedIndex
	if self.usePressedStyle then
		self._lastHighlightedIndex = nextSelectedIndex
	end
	self._lastSelectedOffset = self.selected and self.selected - self.topItem + 1 or self.topItem

	self:_updateScrollbar()

--	log:warn("_update menu:\n", self:dump())


end


function __tostring(self)
	return "Menu(" .. self.listSize .. ")"
end


--[[ C optimized:

jive.ui.Icon:pack()
jive.ui.Icon:draw()

--]]

--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

