--[[
=head1 NAME

jive.ui.NumberLetterAccel

=head1 DESCRIPTION

Class to handle numberLetter (2=abc, etc..) entry.

--]]

-- stuff we use
local _assert, getmetatable, ipairs, setmetatable = _assert, getmetatable, ipairs, setmetatable
local tonumber, tostring, type, unpack = tonumber, tostring, type, unpack

local oo                   = require("loop.simple")
local math                 = require("math")

local ScrollWheel          = require("jive.ui.ScrollWheel")
local Timer                = require("jive.ui.Timer")

local debug                = require("jive.utils.debug")
local string               = require("jive.utils.string")
local log                  = require("jive.utils.log").logger("jivelite.ui")

local ACTION               = jive.ui.ACTION
local EVENT_IR_PRESS       = jive.ui.EVENT_IR_PRESS

local EVENT_IR_DOWN        = jive.ui.EVENT_IR_DOWN
local EVENT_IR_REPEAT      = jive.ui.EVENT_IR_REPEAT

local NUMBER_LETTER_OVERSHOOT_TIME = 150 --ms
local NUMBER_LETTER_TIMER_TIME = 1100 --ms

-- our class
module(..., oo.class)

-- layout is from SC
local numberLettersMixed = {
	[0x76899867] = ' 0',         -- 0
	[0x7689f00f] = '1.,"?!@-',   -- 1
	[0x768908f7] = 'abcABC2',    -- 2
	[0x76898877] = 'defDEF3',    -- 3
	[0x768948b7] = 'ghiGHI4',    -- 4
	[0x7689c837] = 'jklJKL5',    -- 5
	[0x768928d7] = 'mnoMNO6',    -- 6
	[0x7689a857] = 'pqrsPQRS7',  -- 7
	[0x76896897] = 'tuvTUV8',    -- 8
	[0x7689e817] = 'wxyzWXYZ9'   -- 9
}

local numberLettersMixedPreset = {
	['play_preset_0'] = ' 0',         -- 0
	['play_preset_1'] = '1.,"?!@-',   -- 1
	['play_preset_2'] = 'abcABC2',    -- 2
	['play_preset_3'] = 'defDEF3',    -- 3
	['play_preset_4'] = 'ghiGHI4',    -- 4
	['play_preset_5'] = 'jklJKL5',    -- 5
	['play_preset_6'] = 'mnoMNO6',    -- 6
	['play_preset_7'] = 'pqrsPQRS7',  -- 7
	['play_preset_8'] = 'tuvTUV8',    -- 8
	['play_preset_9'] = 'wxyzWXYZ9'   -- 9
}

--[[
=head2 IrMenuAccel(switchTimeoutCallback)


=cut
--]]
function __init(self, switchTimeoutCallback)
	local obj = oo.rawnew(self, {})

	obj.switchTimeoutCallback = switchTimeoutCallback
	obj.lastNumberLetterIrCode = nil
	obj.lastNumberLetterT = nil
	obj.numberLetterTimer = Timer(NUMBER_LETTER_TIMER_TIME, 
				function ()
					obj.currentScrollLetter = nil
					switchTimeoutCallback()
				end,
				true)
	obj.currentScrollLetter = nil
	
	return obj
end

function stopCurrentCharacter(self)
	self.numberLetterTimer:stop()
	self.currentScrollLetter = nil
end

function handleEvent(self, event, validChars)
		local timerWasRunning = self.numberLetterTimer:isRunning()

		local irCode, action, numberLetters
		local evtype = event:getType()
		
		if evtype == EVENT_IR_PRESS then
			irCode = event:getIRCode()
			numberLetters = numberLettersMixed[irCode]
		elseif evtype == ACTION then
			action = event:getAction()
			numberLetters = numberLettersMixedPreset[action]
		end

		log:debug("validChars: ", validChars)

		if numberLetters then
			self.numberLetterTimer:stop()
			local switchCharacters, scrollLetter
			
			if timerWasRunning and self.lastNumberLetterIrCode and irCode ~= self.lastNumberLetterIrCode then
				switchCharacters = true
				local availableNumberLetters = tostring(_getMatchingChars(self, numberLetters, validChars))
				if availableNumberLetters:len() > 0 then
					scrollLetter = string.sub(availableNumberLetters, 1, 1)
					self.currentScrollLetter = scrollLetter
				end
			else
				---First check for "overshoot"
				if self.lastNumberLetterT then
					local numberLetterTimeDelta = event:getTicks() - self.lastNumberLetterT
					if not timerWasRunning and numberLetterTimeDelta > NUMBER_LETTER_TIMER_TIME and
							numberLetterTimeDelta < NUMBER_LETTER_TIMER_TIME + NUMBER_LETTER_OVERSHOOT_TIME then
						--If timer has just fired and another press on the same key is entered,
						 -- follow observed SC behavior: don't use the input, making for
						 -- less unexpected input due to the key press happening right
						 -- as the timer fired even though the user meant for the press to refer to the last letter.
						return true
					end
				end

				----continue scroll if timer was active, otherwise start new scroll

				local availableNumberLetters = tostring(_getMatchingChars(self, numberLetters, validChars))

				local numberChar = string.match(availableNumberLetters, "%d")
				if type == EVENT_IR_HOLD and numberChar then
					-- on hold, select the number character directly , if it is available
					local directLetter = tostring(numberChar)
					self.lastNumberLetterIrCode = nil

					return true, nil, nil, directLetter
				end
				
				--move to next letter
				if availableNumberLetters:len() > 0 then
					if not self.currentScrollLetter then
						scrollLetter =  string.sub(availableNumberLetters, 1, 1)
					else
						local loc = string.find(availableNumberLetters, self.currentScrollLetter, 1, true)
						if not loc then
							log:debug("unusual - last scrollLetter was in the set, restart")
							scrollLetter =  string.sub(availableNumberLetters, 1, 1)
						elseif loc == availableNumberLetters:len() then
							--at end,restart
							scrollLetter =  string.sub(availableNumberLetters, 1, 1)
						else
							--get next
							scrollLetter = string.sub(availableNumberLetters, loc + 1, loc + 1)
						end
											
					end
					self.currentScrollLetter = scrollLetter
				end
			end

			self.lastNumberLetterIrCode = irCode

			self.lastNumberLetterT = event:getTicks()
			self.numberLetterTimer:restart()

			log:debug("switchCharacters: ", switchCharacters, " scrollLetter: ", scrollLetter)

			return true, switchCharacters, scrollLetter

		end

		return false
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


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]
