
-- stuff we use
local _assert, getmetatable, ipairs, setmetatable, bit = _assert, getmetatable, ipairs, setmetatable, bit
local string, tonumber, tostring, type, unpack = string, tonumber, tostring, type, unpack

local oo                = require("loop.simple")
local Widget            = require("jive.ui.Widget")
local ScrollAccel       = require("jive.ui.ScrollAccel")
local IRMenuAccel       = require("jive.ui.IRMenuAccel")
local NumberLetterAccel = require("jive.ui.NumberLetterAccel")
local Timer             = require("jive.ui.Timer")
local Framework         = require("jive.ui.Framework")

local math              = require("math")
local string            = require("string")
local table             = require("jive.utils.table")
local log               = require("jive.utils.log").logger("jivelite.ui")
local locale            = require("jive.utils.locale")
local debug             = require("jive.utils.debug")

local EVENT_ALL         = jive.ui.EVENT_ALL
local EVENT_UNUSED      = jive.ui.EVENT_UNUSED

local EVENT_IR_DOWN     = jive.ui.EVENT_IR_DOWN
local EVENT_IR_REPEAT   = jive.ui.EVENT_IR_REPEAT
local EVENT_IR_HOLD     = jive.ui.EVENT_IR_HOLD
local EVENT_IR_PRESS    = jive.ui.EVENT_IR_PRESS
local EVENT_IR_UP       = jive.ui.EVENT_IR_UP
local EVENT_IR_ALL       = jive.ui.EVENT_IR_ALL
local EVENT_KEY_PRESS   = jive.ui.EVENT_KEY_PRESS
local EVENT_KEY_HOLD    = jive.ui.EVENT_KEY_HOLD
local EVENT_CHAR_PRESS   = jive.ui.EVENT_CHAR_PRESS
local EVENT_SCROLL      = jive.ui.EVENT_SCROLL
local EVENT_WINDOW_RESIZE = jive.ui.EVENT_WINDOW_RESIZE
local EVENT_CONSUME     = jive.ui.EVENT_CONSUME

local KEY_FWD           = jive.ui.KEY_FWD
local KEY_REW           = jive.ui.KEY_REW
local KEY_GO            = jive.ui.KEY_GO
local KEY_BACK          = jive.ui.KEY_BACK
local KEY_UP            = jive.ui.KEY_UP
local KEY_DOWN          = jive.ui.KEY_DOWN
local KEY_LEFT          = jive.ui.KEY_LEFT
local KEY_RIGHT         = jive.ui.KEY_RIGHT
local KEY_PLAY          = jive.ui.KEY_PLAY
local KEY_ADD           = jive.ui.KEY_ADD

local NUMBER_LETTER_OVERSHOOT_TIME = 150 --ms
local NUMBER_LETTER_TIMER_TIME = 1100 --ms

-- our class
module(...)
oo.class(_M, Widget)


-- return valid characters at cursor position.
function _getChars(self)
	if self.value.getChars then
		return tostring(self.value:getChars(self.cursor, self.allowedChars))
	end

	return tostring(self.allowedChars)
end

-- for ui input types like ir and for input like ip or date, down/up scroll polarity will be reversed
function _reverseScrollPolarityOnUpDownInput(self)
	if self.value.reverseScrollPolarityOnUpDownInput then
		return self.value:reverseScrollPolarityOnUpDownInput()
	end

	return false
end


-- returns true if text entry is valid.
function isValid(self)
	if self.value.isValid then
		return self.value:isValid(self.cursor)
	end

	return true
end


-- returns true if text entry is completed.
function _isEntered(self)
	if isValid(self) then
		return self.cursor > #tostring(self.value)
	else
		return false
	end
end



--[[

=head2 jive.ui.Textinput:getValue()

Returns the text displayed in the label.

=cut
--]]
function getValue(self)
	return self.value
end


--[[

=head2 jive.ui.Textinput:setValue(value)

Sets the text displayed in the label.

=cut
--]]
function setValue(self, value)
	_assert(value ~= nil)

	local ok = true
	if self.value ~= value then
		if self.value.setValue  then
			ok = self.value:setValue(value)
		else
			self.value = value
		end

		if self.updateCallback then
			self.updateCallback(self)
		end

		self:reLayout()
	end

	return ok
end


--[[

=head2 jive.ui.Textinput:setUpdateCallback

This callback is executed when the textinput value changes.

--]]
function setUpdateCallback(self, callback)
	self.updateCallback = callback
end


--[[

=head2 jive.ui.Textinput:_scroll(value)

Param chars may optionally be set to use an alternative set of chars rather than from self:_getChars(), which
 is useful for numberLetter scrolling, for instance.

Param restart may optionally be set. If true, _scroll() will always use the first char found in in the list of characters to scroll.


=cut
--]]
function _scroll(self, dir, chars, restart)
	if dir == 0 then
		return
	end
	local cursor = self.cursor
	local str = tostring(self.value)

	local v = chars and chars or self:_getChars()
	if #v == 0 then
		self:playSound("BUMP")
		self:getWindow():bumpRight()
		return
	end

	local s1 = string.sub(str, 1, cursor - 1)
	local s2 = string.sub(str, cursor, cursor)
	local s3 = string.sub(str, cursor + 1)

	if not restart and s2 == "" then
		-- new char, keep cursor near the last letter
		if cursor > 1 then
			s2 = string.sub(str, cursor - 1, cursor - 1)
		end

		-- compensate for the initial nil value
		if dir > 0 then
			dir = dir - 1
		end
	end

	-- find current character, unless overriden by optional restart param
	local i = nil
	if restart then
		i = 0
	else
		i = string.find(v, s2, 1, true)
	end

	-- move dir characters
	i = i + dir

	-- handle wrap around conditions
	if i < 1 then
		i = i + #v
	elseif i > #v then
		i = i - #v
	end

	-- new string
	local s2 = string.sub(v, i, i)

	self:setValue(s1 .. s2 .. s3)
	self:playSound("CLICK")
end


function _moveCursor(self, dir)
	-- range check
	local str = tostring(self.value)
	if (self.cursor == 1 and dir < 0)
		or (self.cursor > #str and dir > 0) then
		return
	end

	local oldCursor = self.cursor
	self.cursor = self.cursor + dir

	-- check for a valid character at the cursor position, if
	-- we don't find one then move again. this allows for
	-- formatted text entry, for example pairs of hex digits
	local str = tostring(self.value)
	local v = self:_getChars()
	local s2 = string.sub(str, self.cursor, self.cursor)

	if (not string.find(v, s2, 1, true)) then
		return _moveCursor(self, dir)
	end

	if self.cursor ~= oldCursor then
		self:playSound("SELECT")
	end
end


function _delete(self, alwaysBackspace)
	local cursor = self.cursor
	if self.value.delete and self.value.useValueDelete and self.value:useValueDelete() then
		local cursorShift = self.value:delete(cursor)
		if not cursorShift then
			return false
		end

		local dir = cursorShift < 0 and -1 or 1
		for i = 1,math.abs(cursorShift) do
			_moveCursor(self, dir)
		end

		self:reDraw()
		return true
	end

	local str = tostring(self.value)

	if not alwaysBackspace and cursor <= #str then

		-- delete at cursor
		local s1 = string.sub(str, 1, cursor - 1)
		local s3 = string.sub(str, cursor + 1)

		self:setValue(s1 .. s3)
		return true

	elseif cursor > 1 then
		-- backspace
		local s1 = string.sub(str, 1, cursor - 2)
		local s3 = string.sub(str, cursor)

		self:setValue(s1 .. s3)
		self.cursor = cursor - 1
		return true

	else
		return false

	end
end


function _insert(self)
	local cursor = self.cursor
	local str = tostring(self.value)

	local s1 = string.sub(str, 1, cursor - 1)
	local s3 = string.sub(str, cursor)

	local v = self:_getChars()
	if #v == 0 then
		return false
	end

	local c = string.sub(v, 1, 1)
	if not self:setValue(s1 .. c .. s3) then
		return false
	end

	_moveCursor(self, 1)

	return true
end


function _cursorAtEnd(self)
	return self.cursor > #tostring(self.value)
end


function _deleteAction(self, event, alwaysBackspace)
	if self.cursor == 1 and not alwaysBackspace then
		self:playSound("WINDOWHIDE")
		self:hide()
	else
		if _delete(self, alwaysBackspace) then
			self:playSound("CLICK")
		else
			self:playSound("BUMP")
			self:getWindow():bumpRight()
		end
	end
	return EVENT_CONSUME

end


function _insertAction(self)
	if _insert(self) then
		self:playSound("CLICK")
	else
		self:playSound("BUMP")
		self:getWindow():bumpRight()
	end
	return EVENT_CONSUME
end


function _goAction(self, _, bumpAtEnd)
	if _isEntered(self) then
		if bumpAtEnd then
			self:playSound("BUMP")
			self:getWindow():bumpRight()
			return EVENT_CONSUME
		end

		local valid = false

		if self.closure then
			valid = self.closure(self, self:getValue())
		end

		if not valid then
			self:playSound("BUMP")
			self:getWindow():bumpRight()
		end
	elseif self.cursor <= #tostring(self.value) then
		_moveCursor(self, 1)
		self:reDraw()
	else
		self:playSound("BUMP")
		self:getWindow():bumpRight()
	end
	return EVENT_CONSUME
end


function _cursorBackAction(self, _, bumpAtStart)
	if self.cursor == 1 then
		if bumpAtStart then
			self:playSound("BUMP")
			self:getWindow():bumpLeft()
			return EVENT_CONSUME
		else
			self:playSound("WINDOWHIDE")
			self:hide()
		end
	else
		_moveCursor(self, -1)
		self:reDraw()
	end

	return EVENT_CONSUME
end


function _escapeAction(self)
	self:_goToStartAction()

	self:playSound("WINDOWHIDE")
	self:hide()
	return EVENT_CONSUME
end

function _goToStartAction(self)
	self.cursor = 1
	self.indent = 0
	self:reDraw()

	return EVENT_CONSUME
end

function _goToEndAction(self)
	self.cursor = #tostring(self.value) + 1
	self:reDraw()

	return EVENT_CONSUME
end

function _cursorLeftAction(self)
	self:_cursorBackAction(_, true)
	return EVENT_CONSUME
end


function _cursorRightAction(self)
	self:_goAction(_, true)
	return EVENT_CONSUME
end


function _doneAction(self)
	self:_goToEndAction()
	return self:_goAction()
end


function _clearAction(self)
	self:setValue("")
	self:_goToStartAction()

	return EVENT_CONSUME
end


function _isPresetButtonPressEvent(self, event)
	if not event or event:getType() ~= EVENT_KEY_PRESS then
		return false
	end

	local keycode = event:getKeycode()

	return  keycode == KEY_PRESET_0 or
		keycode == KEY_PRESET_1 or
		keycode == KEY_PRESET_2 or
		keycode == KEY_PRESET_3 or
		keycode == KEY_PRESET_4 or
		keycode == KEY_PRESET_5 or
		keycode == KEY_PRESET_6 or
		keycode == KEY_PRESET_7 or
		keycode == KEY_PRESET_8 or
		keycode == KEY_PRESET_9
end


function _eventHandler(self, event)
	local type = event:getType()

	if Framework:isMostRecentInput("ir") or
		Framework:isMostRecentInput("key") or
		Framework:isMostRecentInput("scroll") then
		self.cursorWidth = 1
	else
		self.cursorWidth = 0
	end

	--hold and press left works as cursor left. hold added here since it is intuitive to hold down left to go back several characters.
	--todo: also handle longhold when this is added.
	if (type == EVENT_IR_HOLD or type == EVENT_IR_PRESS) and
	   (event:isIRCode("arrow_left") or
	     event:isIRCode("arrow_right") or
	     event:isIRCode("0") or
	     event:isIRCode("1") or
	     event:isIRCode("2") or
	     event:isIRCode("3") or
	     event:isIRCode("4") or
	     event:isIRCode("5") or
	     event:isIRCode("6") or
	     event:isIRCode("7") or
	     event:isIRCode("8") or
	     event:isIRCode("9")) then
		--left and right and number keys handled in down/repeat handling; consume so that it is not seen as an action
		return EVENT_CONSUME
	end

	if type == EVENT_IR_PRESS then
		--play is delete, add is insert, just like jive
		if event:isIRCode("play") then
			self.numberLetterAccel:stopCurrentCharacter()
			return _goAction(self)
		end
		if event:isIRCode("add") then
			self.numberLetterAccel:stopCurrentCharacter()
			return _insertAction(self)
		end

	elseif type == EVENT_IR_UP and self.upHandlesCursor and (event:isIRCode("arrow_left") or event:isIRCode("arrow_right")) then
		self.upHandlesCursor = false

		--handle right and left on the up while at the ends of the text so that hold/repeat doesn't push past the ends of the screen
		if event:isIRCode("arrow_left") and self.cursor == 1 then
			self:_deleteAction()
		end
		if event:isIRCode("arrow_right") and self:_cursorAtEnd() then
			self:_goAction()
		end

		return EVENT_CONSUME

	elseif type == EVENT_IR_DOWN or type == EVENT_IR_REPEAT or type == EVENT_IR_HOLD then
		local irCode = event:getIRCode()
		if type == EVENT_IR_HOLD then
			if event:isIRCode("rew") then
				return _goToStartAction(self)
			elseif event:isIRCode("fwd") then
				return _goToEndAction(self)
			end
		end

		if type == EVENT_IR_DOWN or type == EVENT_IR_REPEAT then

			--IR left/right
			if event:isIRCode("arrow_left") or event:isIRCode("arrow_right") then
				self.numberLetterAccel:stopCurrentCharacter()
				if self.locked == nil then
					local direction =  self.leftRightIrAccel:event(event, 1, 1, 1, #self:getValue())

					--move cursor, but when ir held down move to ends and stop so the user doesn't
					 --inadvertantly jump into the next page before lifting the the key.
					 --So, on the ends only move on a new press
					if direction < 0 then
						if self.cursor ~= 1 then
							self:_deleteAction()
						elseif type == EVENT_IR_DOWN then
							self.upHandlesCursor = true
						end
					end
					if direction > 0 then
						if not self:_cursorAtEnd() then
							self:_goAction()
						elseif type == EVENT_IR_DOWN then
							self.upHandlesCursor = true
						end
					end
					return EVENT_CONSUME
				end
			end

			--IR down/up
			if event:isIRCode("arrow_up") or event:isIRCode("arrow_down") then
				self.numberLetterAccel:stopCurrentCharacter()
				if self.locked == nil then
					local chars = self:_getChars()
					local idx = string.find(chars, string.sub(tostring(self.value), self.cursor, self.cursor), 1, true)

					-- for ui input types like ir and for input like ip or date, down/up scroll polarity will be reversed
					local polarityModifier = 1
					if self:_reverseScrollPolarityOnUpDownInput() then
						polarityModifier = -1
					end

					_scroll(self, polarityModifier * self.irAccel:event(event, idx, idx, 1, #chars))
					return EVENT_CONSUME
				end
			end
		end
		if type == EVENT_IR_DOWN or type == EVENT_IR_HOLD then
			local consume, switchCharacters, scrollLetter, directLetter = self.numberLetterAccel:handleEvent(event, self:_getChars())
			if consume then
				if switchCharacters and scrollLetter then
					_moveCursor(self, 1)
					self:reDraw()

					_scroll(self, 1, scrollLetter, true)
				elseif scrollLetter then
					_scroll(self, 1, scrollLetter, true)
				
				elseif directLetter then
					_scroll(self, 1, directLetter, true)

					_moveCursor(self, 1)
				
				end
				
				return EVENT_CONSUME
			else
				return EVENT_UNUSED 
			end			
		end

	elseif type == EVENT_SCROLL then
		-- XXX optimize by caching v and i in _scroll?
		self.numberLetterAccel:stopCurrentCharacter()
		local v = self:_getChars()
		local idx = string.find(v, string.sub(tostring(self.value), self.cursor, self.cursor), 1, true)

		_scroll(self, self.scroll:event(event, idx, idx, 1, #v))
		return EVENT_CONSUME

	elseif type == EVENT_CHAR_PRESS then
		self.numberLetterAccel:stopCurrentCharacter()

		--assuming ascii level values for now
		local keyboardEntry = string.char(event:getUnicode())
		if (keyboardEntry == "\b") then --backspace
			return _deleteAction(self, event, true)

		elseif (keyboardEntry == "\27") then --escape
			return _escapeAction(self)

		elseif not string.find(self:_getChars(), keyboardEntry, 1, true) then
			--also check for possibility of uppercase match
			if (string.find(keyboardEntry, "%l")) then
				keyboardEntry = string.upper(keyboardEntry)
			end
			if not string.find(self:_getChars(), keyboardEntry, 1, true) then
				self:playSound("BUMP")
				self:getWindow():bumpRight()
				return EVENT_CONSUME
			end
		end

		-- insert character
		local s1 = string.sub(tostring(self.value), 1, self.cursor - 1)
		local s3 = string.sub(tostring(self.value), self.cursor)
		if self:setValue(s1 .. keyboardEntry .. s3) then
			_moveCursor(self, 1)
		else
			self:playSound("BUMP")
			self:getWindow():bumpRight()
		end

		return EVENT_CONSUME

	elseif type == EVENT_WINDOW_RESIZE then
		self.numberLetterAccel:stopCurrentCharacter()
		_moveCursor(self, 0)

	elseif type == EVENT_KEY_PRESS then
		self.numberLetterAccel:stopCurrentCharacter()
		local keycode = event:getKeycode()

		if keycode == KEY_UP or keycode == KEY_DOWN then
			if self.locked == nil then
				-- for ui input types like ir and for input like ip or date, down/up scroll polarity will be reversed
				local polarityModifier = 1
				if self:_reverseScrollPolarityOnUpDownInput() then
					polarityModifier = -1
				end
				_scroll(self, polarityModifier * (keycode == KEY_DOWN and 1 or -1))
			end

		elseif keycode == KEY_LEFT then
			return _deleteAction(self)
		elseif keycode == KEY_RIGHT then
			if self:_cursorAtEnd() then
				return _goAction(self)
			else
				return _cursorRightAction(self)
			end
		elseif keycode == KEY_REW then
			return _cursorLeftAction(self)
		elseif keycode == KEY_FWD then
			return _cursorRightAction(self)
		elseif keycode == KEY_BACK then
			return _deleteAction(self)
		end
	elseif type == EVENT_KEY_HOLD then
		self.numberLetterAccel:stopCurrentCharacter()
		local keycode = event:getKeycode()

		if keycode == KEY_REW then
			return _goToStartAction(self)
		elseif keycode == KEY_FWD then
			return _goToEndAction(self)
		end
	end

	return EVENT_UNUSED
end


--[[

=head2 jive.ui.Textinput:init(style, value, closure, allowedChars)

Creates a new Textinput widget with initial value I<value>. The I<closure>
is a function that will be called at the end of the text input. This function
should return false if the text is invalid (the window will then bump right)
or return true when the text is valid.
I<allowedChars> is an optional parameter containing the list of chars to propose.

=cut
--]]
function __init(self, style, value, closure, allowedChars)
	_assert(type(style) == "string")
	_assert(value ~= nil)

	local obj = oo.rawnew(self, Widget(style))
	 _globalStrings = locale:readGlobalStringsFile()

	obj.cursor = 1
	obj.indent = 0
	obj.maxWidth = 0
	obj.value = value

	-- default cursor to end to string unless defaultCursorToStart true
	if obj.value and not (obj.value.defaultCursorToStart and obj.value:defaultCursorToStart()) then
		obj.cursor = #tostring(obj.value) + 1
	end

	if Framework:isMostRecentInput("ir") or
		Framework:isMostRecentInput("key") or
		Framework:isMostRecentInput("scroll") then
		obj.cursorWidth = 1
	else
		obj.cursorWidth = 0
	end

	obj.closure = closure
	obj.allowedChars = allowedChars or
		_globalStrings:str("ALLOWEDCHARS_WITHCAPS")
	obj.scroll = ScrollAccel()
	obj.leftRightIrAccel = IRMenuAccel("arrow_right", "arrow_left")
	obj.leftRightIrAccel.onlyScrollByOne = true

	obj.irAccel = IRMenuAccel()
	obj.numberLetterAccel = NumberLetterAccel(
					function()
						obj.lastNumberLetterIrCode = nil
						obj.lastNumberLetterKeyCode = nil
						obj:_moveCursor(1)
						obj:reDraw()
					end
	)
	obj:addActionListener("play", obj, _goAction)
	obj:addActionListener("add", obj, _insertAction)
	obj:addActionListener("go", obj, _goAction)

	--only touch back action will be handled this way (as escape), other back sources are use _cursorBackAction, and are handled directly in the main listener
	obj:addActionListener("back", obj, _escapeAction)

	obj:addActionListener("finish_operation", obj, _doneAction)
	obj:addActionListener("cursor_left", obj, _cursorLeftAction)
	obj:addActionListener("cursor_right", obj, _cursorRightAction)
	obj:addActionListener("clear", obj, _clearAction)
	obj:addActionListener("jump_rew", obj, _cursorLeftAction)
	obj:addActionListener("jump_fwd", obj, _cursorRightAction)
	obj:addActionListener("scanner_rew", obj, _goToStartAction)
	obj:addActionListener("scanner_fwd", obj, _goToEndAction)

	obj:addListener(bit.bor(EVENT_CHAR_PRESS, EVENT_KEY_PRESS, EVENT_KEY_HOLD, EVENT_SCROLL, EVENT_WINDOW_RESIZE, EVENT_IR_ALL),
			function(event)
				return _eventHandler(obj, event)
			end)

	return obj
end


--[[

=head2 jive.ui.Textinput.textValue(default, min, max)

Returns a value that can be used for entering a length bounded text string

=cut
--]]
function textValue(default, min, max)
	local obj = {
		s = default or ""
	}

	setmetatable(obj, {
		__tostring = function(obj)
			return obj.s
		end,

		__index = {
			setValue = function(obj, str)
				obj.s = str
				return true
			end,

			getValue = function(obj)
				return obj.s
			end,

			getChars = function(obj, cursor, allowedChars)
				if max and cursor > max then
					return ""
				end
				return allowedChars
			end,

			isValid = function(obj, cursor)
				if min and #obj.s < min then
					return false
				elseif max and #obj.s > max then
					return false
				else
					return true
				end
			end
		}
	})

	return obj
end


--[[

=head2 jive.ui.Textinput.timeValue(default)

Returns a value that can be used for entering time setting

=cut
--]]
function timeValue(default, format)
	local obj = {}
	if not format then
		format = '24'
	end
	if tostring(format) == '12' then
		setmetatable(obj, {
		     __tostring =
				function(e)
				if type(e) == 'table' and e[3] then
					return e[1] .. ":" .. e[2] .. e[3]
				else
					return table.concat(e, ":")
				end
			end,

		     __index = {
				setValue =
					function(value, str)
						local i = 1
						for dd in string.gmatch(str, "(%d+)") do
							local n = tonumber(dd)
							if n > 12 and i == 1 then
								n = 0
							end
							value[i] = string.format("%02d", n)
							i = i + 1
							if i > 2 then
								break
							end
						end
						local ampm = string.match(str, "[ap]", i)
						value[i] = ampm

						return true
				    	end,
				getValue =
					function(value)
						-- remove leading zeros
						local norm = {}
						for i,v in ipairs(value) do
							if type(v) == 'number' then
								norm[i] = tostring(tonumber(v))
							elseif type(v) == 'string' then
								norm[i] = v
							end
						end
						return norm[1] .. ":" .. norm[2] .. norm[3]
					end,

                               getChars =
					function(value, cursor)
						if cursor == 7 then
							return ""
						end
						local v = tonumber(value[math.floor(cursor/3)+1])
						if cursor == 1 then
							-- first char can only be 1 if hour is 10
							if v == 10 then
								return "1"
							-- first char can be 0 or 1 if hour is 1,2,11,or 12
							elseif v < 3 or v > 10 then
								return "01"
							-- hour 3-9 only allows first num in hour to be 0
							else
								return "0"
							end
						elseif cursor == 2 then
							if v > 9 then
								return "012"
							else
								return "123456789"
							end
						elseif cursor == 3 then
							return ""
						elseif cursor == 4 then
							return "012345"
						elseif cursor == 5 then
							return "0123456789"
						elseif cursor == 6 then
							return "ap"
						end
				end,
				reverseScrollPolarityOnUpDownInput =
					function()
					     return true
					end,

				isValid =
					function(value, cursor)
						return #value == 3
					end
			}
		})
	else
		setmetatable(obj, {
			     __tostring =
				     function(e)
					     return table.concat(e, ":")
				     end,

			     __index = {
				     setValue =
					     function(value, str)
						     local i = 1
						     for dd in string.gmatch(str, "(%d+)") do
							     local n = tonumber(dd)
							     if n > 23 and i == 1 then i = 0 end
							     value[i] = string.format("%02d", n)
							     i = i + 1
							     if i > 2 then break end
						     end
						     return true
					     end,

				     getValue =
					     function(value)
						     -- remove leading zeros
						     local norm = {}
						     for i,v in ipairs(value) do
							     norm[i] = tostring(tonumber(v))
						     end
						     return table.concat(norm, ":")
					     end,

                                     getChars =
                                             function(value, cursor)
							if cursor == 6 then return "" end
							local v = tonumber(value[math.floor(cursor/3)+1])
							if cursor == 1 then
								return "012"
							elseif cursor == 2 then
								if v > 19 then
									return "0123"
								else
									return "0123456789"
								end
							elseif cursor == 3 then
								return ""
							elseif cursor == 4 then
								return "012345"
							elseif cursor == 5 then
								return "0123456789"
							end
                                             end,
				     reverseScrollPolarityOnUpDownInput =
					     function()
						     return true
					     end,

				     isValid =
					     function(value, cursor)
						    return #value == 2
					     end
			     }
		     })
	end

	if default then
		obj:setValue(default)
	end

	return obj
end

--[[

=head2 jive.ui.Textinput.hexValue(default)

Returns a value that can be used for entering an hexadecimal value.

=cut
--]]
function hexValue(default, min, max)
	local obj = {}
	setmetatable(obj, {
		__tostring = function(obj)
			return obj.s
		end,

		__index = {
			setValue = function(obj, str)
				if max and #str > max then
					return false
				end

				obj.s = str
				return true
			end,

			getValue = function(obj)
				return obj.s
			end,

			getChars = function(obj, cursor)
				if max and cursor > max then
					return ""
				end
				return "0123456789ABCDEF"
			end,

			reverseScrollPolarityOnUpDownInput = function()
				return true
			end,

			isValid = function(obj, cursor)
				if min and #obj.s < min then
					return false
				else
					return true
				end
			end,
		}
	})

	obj:setValue(default or "")

	return obj
end


--[[

=head2 jive.ui.Textinput.ipAddressValue(default)

Returns a value that can be used for entering an ip address.

=cut
--]]
function ipAddressValue(default)
	local obj = {}
	setmetatable(obj, {
		__tostring = function(obj)
			if not (Framework:isMostRecentInput("ir")
				or Framework:isMostRecentInput("key")
				or Framework:isMostRecentInput("scroll")) then
				return obj.str
			end

			local s = {}
			for i=1,4 do
				s[i] = string.format("%03d", obj.v[i] or 0)
			end
			return table.concat(s, ".")
		end,

		__index = {
			setValue = function(obj, str)
				local v = {}

				if string.match(str, "%.%.") then
					return false
				end

				local i = 1
				for ddd in string.gmatch(str, "(%d+)") do
					v[i] = tonumber(ddd)

					-- Bug: 10352
					-- Allow changing first digit from 1 to 2 and
					--  then correct to 255 if needed
					-- This allows user to enter / correct from left
					--  to right even for non zero values, i.e.
					--  old: 192 -> new: 292 -> auto corrected: 255
					if v[i] > 255 and v[i] < 300 then
						v[i] = 255
					end

					if v[i] > 255 then
						return false
					end

					i = i + 1
					if i > 5 then
						return false
					end
				end

				obj.v = v
				obj.str = table.concat(v, ".")
				if string.sub(str, -1) == "." then
					obj.str = obj.str .. "."
				end

				return true
			end,

			getValue = function(obj)
				-- remove leading zeros
				local norm = {}
				for i,v in ipairs(obj.v) do
					norm[i] = tostring(tonumber(v))
				end
				return table.concat(norm, ".")
			end,

			getChars = function(obj, cursor)
				-- keyboard input
				if not (Framework:isMostRecentInput("ir")
					or Framework:isMostRecentInput("key")
					or Framework:isMostRecentInput("scroll")) then
					if #obj.v < 4 then
						return "0123456789."
					else
						return "0123456789"
					end
				end

				-- IR input
				local n = (cursor % 4)
				if n == 0 then
					return ""
				end
				local v = tonumber(obj.v[math.floor(cursor/4)+1]) or 0

				local a = math.floor(v / 100)
				local b = math.floor(v % 100 / 10)
				local c = math.floor(v % 10)

				if n == 1 then
					-- Bug: 10352
					-- Allow changing first digit from 1 to 2 and
					--  then correct to 255 if needed
					-- This allows user to enter / correct from left
					--  to right even for non zero values, i.e.
					--  old: 192 -> new: 292 -> auto corrected: 255
					return "012"
				elseif n == 2 then
					if a >= 2 and c > 5 then
						return "01234"
					elseif a >= 2 then
						return "012345"
					else
						return "0123456789"
					end
				elseif n == 3 then
					if a >= 2 and b >= 5 then
						return "012345"
					else
						return "0123456789"
					end
				end
			end,

			reverseScrollPolarityOnUpDownInput = function()
				return true
			end,

			defaultCursorToStart = function()
				if not default or default == "" then
					return true
				else
					return false
				end
			end,

			isValid = function(obj, cursor)
				return #obj.v == 4 and not
					(obj.v[1] == 0 and
					 obj.v[2] == 0 and
					 obj.v[3] == 0 and
					 obj.v[4] == 0)
			end,

			useValueDelete = function(obj)
				--bypass custom delete for touch
				return (Framework:isMostRecentInput("ir")
					or Framework:isMostRecentInput("key")
					or Framework:isMostRecentInput("scroll"))
			end,

			delete = function(obj, cursor)
				local str = tostring(obj)
				if cursor <= #str then
					-- Switch to 0 at cursor
					local s1 = string.sub(str, 1, cursor - 1)
					local s2 = "0"
					local s3 = string.sub(str, cursor + 1)

					local new = s1 .. s2 .. s3

					obj:setValue(new)
					return -1

				elseif cursor > 1 then
					-- just move back one
					return -1

				else
					return false
				end
			end
		}
	})

	obj:setValue(default or "")

	return obj
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

