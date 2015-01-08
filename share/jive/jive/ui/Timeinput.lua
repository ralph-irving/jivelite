--[[
=head1 NAME

jive.ui.Timeinput - Base class for timeinput helper methods

=head1 DESCRIPTION

Base class for Timeinpupt helper methods

=head1 METHODS

=cut
--]]


-- stuff we use
local _assert, assert, ipairs, require, tostring, type, tonumber = _assert, assert, ipairs, require, tostring, type, tonumber

local oo            = require("loop.base")
local string        = require("jive.utils.string")
local table         = require("jive.utils.table")
local Event         = require("jive.ui.Event")
local SimpleMenu    = require("jive.ui.SimpleMenu")
local Icon          = require("jive.ui.Icon")
local Window        = require("jive.ui.Window")
local Button        = require("jive.ui.Button")
local Label         = require("jive.ui.Label")
local Group         = require("jive.ui.Group")

local debug         = require("jive.utils.debug")
local log           = require("jive.utils.log").logger("jivelite.ui")

local EVENT_SHOW    = jive.ui.EVENT_SHOW
local EVENT_HIDE    = jive.ui.EVENT_HIDE
local EVENT_UPDATE  = jive.ui.EVENT_UPDATE
local EVENT_CONSUME = jive.ui.EVENT_CONSUME
local ACTION        = jive.ui.ACTION


-- our class
module(..., oo.class)

local Framework		= require("jive.ui.Framework")


function __init(self, window, submitCallback, initTime)
	local obj = oo.rawnew(self, {})

	obj.window = window
	obj.submitCallback = submitCallback

	if initTime and type(initTime) == 'table' then
		obj.initHour   = initTime.hour and tonumber(initTime.hour)
		obj.initMinute = initTime.minute and tonumber(initTime.minute)
		obj.initampm   = initTime.ampm
	end

	obj.window:addActionListener("finish_operation", obj, _doneAction)

	replaceNowPlayingButton(obj)

	addTimeInputWidgets(obj)

	return obj
end

function _minuteString(minute)
	local returnVal
	if minute < 10 then
		returnVal = '0' .. tostring(minute)
	else
		returnVal = tostring(minute)
	end
	return returnVal
end


function _doneAction(self)
	local hour   = self.hourMenu:getItem(self.hourMenu:getMiddleIndex()).text
	local minute = self.minuteMenu:getItem(self.minuteMenu:getMiddleIndex()).text
	local ampm
	if self.ampmMenu then
		ampm   = self.ampmMenu:getItem(self.ampmMenu:getMiddleIndex()).text
	else
		ampm = nil
	end
	self.window:hide()
	self.submitCallback( hour, minute, ampm )
end


function replaceNowPlayingButton(self)
	log:debug('replaceNowPlayingButton')
	self.window:setButtonAction('rbutton', 'finish_operation', 'finish_operation', 'finish_operation', true)

end


function addTimeInputWidgets(self)


	local hours = {}
	local ampm = {}
	local hourMenuMiddle
	
	if self.initampm then
		self.background = Icon('time_input_background_12h')
		self.menu_box   = Icon('time_input_menu_box_12h')

		-- 12h hour menu
		local hourCopies = 100
		for i = 1, hourCopies do
			for j = 1, 12 do
				local value = tostring(j)
				if (i == 1 and j < 3) or (i == hourCopies and j > 10) then
				        value = ""
				end
			        table.insert(hours, value)  
			end	
		end
		hourMenuMiddle = 12 * (hourCopies / 2) + 1
		 

		self.ampmMenu = SimpleMenu('ampmUnselected')
		self.ampmMenu:setDisableVerticalBump(true)
		
		ampm = { '', '', 'PM', 'AM', '', '' }
		if self.initampm == 'AM' then
			ampm = { '', '', 'AM', 'PM', '', '' }
		end

		for i, t in ipairs(ampm) do
			self.ampmMenu:addItem({
				text = t,
				callback = function () return EVENT_CONSUME end,
			})
		end
		self.ampmMenu.itemsBeforeScroll = 2
		self.ampmMenu.snapToItemEnabled = true
		self.ampmMenu:setSelectedIndex(3)
		self.ampmMenu:setHideScrollbar(true)

	else
		self.background = Icon('time_input_background_24h')
		self.menu_box   = Icon('time_input_menu_box_24h')

		local hourCopies = 50
		for i = 1, hourCopies do
			for j = 0, 23 do
				local value = tostring(j)
				if (i == 0 and j < 2) or (i == hourCopies and j > 21) then
				        value = ""
				end
			        table.insert(hours, value)  
			end	
		end
		hourMenuMiddle = 24 * (hourCopies / 2) + 1

--		-- 24h hour menu
--		hours = { '22', '23', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12', '13', '14', '15', '16', '17', '18', '19', '20', '21', '22', '23', '0', '1' }
--		-- deal with inital hour setting
--		if self.initHour then
--			if self.initHour == 0 then
--				hours = { '22', '23', '0' }
--			elseif self.initHour == 1 then
--				hours = { '23', '0', '1' }
--			else
--				hours = { tostring(self.initHour - 2), tostring(self.initHour - 1), tostring(self.initHour) }
--			end
--			local nextItem = self.initHour + 1
--			local inc = 0
--			while inc < 25 do
--				if nextItem > 23 then
--					nextItem = 0
--				end
--				table.insert(hours, tostring(nextItem))
--				nextItem = nextItem + 1
--				inc = inc + 1
--			end
--		end
	end

	-- construction of hour menu from here on is not specific to 12h/24h
	self.hourMenu = SimpleMenu("hour")
	self.hourMenu:setDisableVerticalBump(true)
	
	for i, hour in ipairs(hours) do
		self.hourMenu:addItem({
			text = hour,
			callback = function () return EVENT_CONSUME end,
		})
	end

	self.hourMenu.itemsBeforeScroll = 2
	self.hourMenu.snapToItemEnabled = true
	if self.initHour then
		-- subtract one for initial hour in 12h menu
		if self.initampm then
			self.hourMenu:setSelectedIndex(hourMenuMiddle + self.initHour - 1)
		else
			self.hourMenu:setSelectedIndex(hourMenuMiddle + self.initHour)
		end
	else
		self.hourMenu:setSelectedIndex(hourMenuMiddle)
	end


	-- minute menu the same between 12h and 24h
	self.minuteMenu = SimpleMenu('minuteUnselected')
	self.minuteMenu:setDisableVerticalBump(true)

	local minutes = {}
	local minuteCopies = 20
	for i = 1, minuteCopies do
	        for j = 0, 59 do
			local value = _minuteString(j)
			if (i == 1 and j < 2) or (i == minuteCopies and j > 57) then
				value = ""
			end
			table.insert(minutes, value)  
		end	
	end
	local minuteMenuMiddle = 60 * (minuteCopies / 2) + 1
	
	for i, minute in ipairs(minutes) do
		self.minuteMenu:addItem({
			text = minute,
			callback = function () return EVENT_CONSUME end,
		})
	end
	local minute = 0

	self.minuteMenu.itemsBeforeScroll = 2
	if self.initMinute then
		self.minuteMenu:setSelectedIndex(minuteMenuMiddle + self.initMinute)
	else
		self.minuteMenu:setSelectedIndex(minuteMenuMiddle)
	end

	self.minuteMenu.snapToItemEnabled = true

	self.hourMenu:setHideScrollbar(true)
	self.minuteMenu:setHideScrollbar(true)

	self.hourMenu:addActionListener('back', self, function() self.window:hide() end)
	self.hourMenu:addActionListener('go', self, 
		function() 
			self.hourMenu:setStyle('hourUnselected')
			self.minuteMenu:setStyle('minute')
			--next is evil, but not sure how to get style change for a menu the right way, trying various options. Richard?
			Framework:styleChanged()
			self.window:focusWidget(self.minuteMenu)
		end
	)

	self.minuteMenu:addActionListener('go', self, 
		function() 
			if self.ampmMenu then
				self.ampmMenu:setStyle('ampm')
				self.minuteMenu:setStyle('minuteUnselected')
				--next is evil, but not sure how to get style change for a menu the right way, trying various options. Richard?
				Framework:styleChanged()
				self.window:focusWidget(self.ampmMenu)
			else
				local hour   = self.hourMenu:getItem(self.hourMenu:getMiddleIndex()).text
				local minute = self.minuteMenu:getItem(self.minuteMenu:getMiddleIndex()).text
				self.window:hide() 
				self.submitCallback( hour, minute, nil )
			end
		end)
	self.minuteMenu:addActionListener('back', self, 
		function() 
			self.hourMenu:setStyle('hour')
			self.minuteMenu:setStyle('minuteUnselected')
			--next is evil, but not sure how to get style change for a menu the right way, trying various options. Richard?
			Framework:styleChanged()
			self.window:focusWidget(self.hourMenu)
		end)

	if self.ampmMenu then
		self.ampmMenu:addActionListener('go', self, 
			function() 
				local hour   = self.hourMenu:getItem(self.hourMenu:getMiddleIndex()).text
				local minute = self.minuteMenu:getItem(self.minuteMenu:getMiddleIndex()).text
				local ampm   = self.ampmMenu:getItem(self.ampmMenu:getMiddleIndex()).text
				self.window:hide() 
				self.submitCallback( hour, minute, ampm )
			end)
		self.ampmMenu:addActionListener('back', self, 
			function() 
				self.ampmMenu:setStyle('ampmUnselected')
				self.minuteMenu:setStyle('minute')
				--next is evil, but not sure how to get style change for a menu the right way, trying various options. Richard?
				Framework:styleChanged()
				self.window:focusWidget(self.minuteMenu)
			end)
	end

	self.window:addWidget(self.background)
	self.window:addWidget(self.menu_box)
	self.window:addWidget(self.minuteMenu)
	self.window:addWidget(self.hourMenu)
	if self.ampmMenu then
		self.window:addWidget(self.ampmMenu)
	end
	self.window:focusWidget(self.hourMenu)

end

