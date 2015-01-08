
--[[
=head1 NAME

applets.SetupDateTime.SetupDateTime - Add a main menu option for setting up date and time formats

=head1 DESCRIPTION

Allows user to select different date and time settings

=head1 FUNCTIONS

Applet related methods are described in L<jive.Applet>. 

=cut
--]]


-- stuff we use
local ipairs, pairs, io, string, tostring, pcall = ipairs, pairs, io, string, tostring, pcall

local oo               = require("loop.simple")
local hasSqueezeos, squeezeos = pcall(function() return require("squeezeos_bsp") end)

local Applet           = require("jive.Applet")
local Choice	       = require("jive.ui.Choice")
local RadioButton      = require("jive.ui.RadioButton")
local RadioGroup       = require("jive.ui.RadioGroup")
local Framework        = require("jive.ui.Framework")
local Label            = require("jive.ui.Label")
local SimpleMenu       = require("jive.ui.SimpleMenu")
local Textarea         = require("jive.ui.Textarea")
local Window           = require("jive.ui.Window")

local locale           = require("jive.utils.locale")
local datetime         = require("jive.utils.datetime")
local table            = require("jive.utils.table")

local appletManager    = appletManager

local datetimeTitleStyle = 'settingstitle'

module(..., Framework.constants)
oo.class(_M, Applet)

function settingsShow(self, menuItem)
	local window = Window("text_list", menuItem.text, datetimeTitleStyle)

	local curHours = ""
	if self:getSettings()["hours"] == 12 then
		curHours = 1
	else
		curHours = 2
	end

	local curWeekStart
	if self:getSettings()["weekstart"] == "Monday" then
		curWeekStart = 2
	else
		curWeekStart = 1
	end

	window:addWidget(SimpleMenu("menu",
		{
			{	
				text = self:string("DATETIME_TIMEFORMAT"),
				sound = "WINDOWSHOW",
				callback = function(obj, selectedIndex)
						self:timeSetting(menuItem)
					end
			},
			{
				text = self:string("DATETIME_DATEFORMAT"),
				sound = "WINDOWSHOW",
				callback = function(event, menuItem)
						self:dateFormatSetting(menuItem)
						return EVENT_CONSUME
					end
			},
			{
				text = self:string("DATETIME_SHORTDATEFORMAT"),
				sound = "WINDOWSHOW",
				callback = function(event, menuItem)
						self:shortDateFormatSetting(menuItem)
						return EVENT_CONSUME
					end
			},
			{
				text = self:string("DATETIME_WEEKSTART"),
				sound = "WINDOWSHOW",
				callback = function(event, menuItem)
						self:weekstartSetting(menuItem)
					end
			},
		}
	))


	window:addListener(EVENT_WINDOW_POP, 
		function()
			self:storeSettings()
		end
	)

	self:tieAndShowWindow(window)
	return window
end

function timeSetting(self, menuItem)
	local window = Window("text_list", menuItem.text, datetimeTitleStyle)
	local group = RadioGroup()

	local current = self:getSettings()["hours"]

	local menu = SimpleMenu("menu", {
		{
			text = self:string("DATETIME_TIMEFORMAT_12H"),
			style = 'item_choice',
			check = RadioButton("radio", group, function(event, menuItem)
					self:setHours("12")
				end,
			current == "12")
		},
		{
			text = self:string("DATETIME_TIMEFORMAT_24H"),
			style = 'item_choice',
			check = RadioButton("radio", group, function(event, menuItem)
					self:setHours("24")
				end,
			current == "24")
		},
	})

	window:addWidget(menu)

	self:tieAndShowWindow(window)
	return window;
end

function shortDateFormatSetting(self, menuItem)
	local window = Window("text_list", menuItem.text, datetimeTitleStyle)
	local group = RadioGroup()

	local current = self:getSettings()["shortdateformat"]

	local menu = SimpleMenu("menu", {})

	for k,v in pairs(datetime:getAllShortDateFormats()) do
		menu:addItem({
				text = datetime:getCurrentDate(v),
				style = 'item_choice',
				check = RadioButton("radio", group, function(event, menuItem)
						self:setShortDateFormat(v)
					end,
				current == v)
		})
	end

	window:addWidget(menu)

	self:tieAndShowWindow(window)
	return window
end


function dateFormatSetting(self, menuItem)
	local window = Window("text_list", menuItem.text, datetimeTitleStyle)
	local group = RadioGroup()

	local current = self:getSettings()["dateformat"]

	local menu = SimpleMenu("menu", {})

	for k,v in pairs(datetime:getAllDateFormats()) do
		menu:addItem({
				text = datetime:getCurrentDate(v),
				style = 'item_choice',
				check = RadioButton("radio", group, function(event, menuItem)
						self:setDateFormat(v)
					end,
				current == v)
		})
	end

	window:addWidget(menu)

	self:tieAndShowWindow(window)
	return window
end

function weekstartSetting(self, menuItem)
	local window = Window("text_list", menuItem.text, datetimeTitleStyle)
	local group = RadioGroup()

	local current = self:getSettings()["weekstart"]

	local menu = SimpleMenu("menu", {
		{
			text = self:string("DATETIME_SUNDAY"),
			style = 'item_choice',
			check = RadioButton("radio", group, function(event, menuItem)
					self:setWeekStart("Sunday")
				end,
			current == "Sunday")
		},
		{
			text = self:string("DATETIME_MONDAY"),
			style = 'item_choice',
			check = RadioButton("radio", group, function(event, menuItem)
					self:setWeekStart("Monday")
				end,
			current == "Monday")
		},
	})

	window:addWidget(menu)

	self:tieAndShowWindow(window)
	return window;
end

function setDateFormat(self, format)
	self:getSettings()["dateformat"] = format
	datetime:setDateFormat(format)
end

function setShortDateFormat(self, format)
	self:getSettings()["shortdateformat"] = format
	datetime:setShortDateFormat(format)
end


function setWeekStart(self, day)
	self:getSettings()["weekstart"] = day
	datetime:setWeekstart(day)
end

function setHours(self, hours)
	self:getSettings()["hours"] = hours
	datetime:setHours(hours)
end

-- wrapper method to allow other applets to get these settings through service API
function setupDateTimeSettings(self)
	return self:getSettings()
end

-- service callback to allow other applets to set default formats depending on language and time zone
function setDateTimeDefaultFormats(self)
	if not hasSqueezeos then
		log:warn('no squeezeos found, do nothing')
		return
	end

	local tz = tostring(squeezeos.getTimezone())
	local lang = locale:getLocale()
	log:debug("Using language (", lang, ") and time zone (", tz, ") to determine date/time default formats")
	
	-- default to 12h display for some select countries (EN speaking in some countries)
	-- see http://en.wikipedia.org/wiki/12-hour_clock#Use_by_country & SetupTZApplet.lua
	if tostring(lang) == 'EN' and ( 
		string.match(tz, "^America") 
		or string.match(tz, "^Australia")
		or string.match(tz, "^Pacific")			-- New Zealand
--		or string.match(tz, "^Asia/Calcutta")	-- India/Pakistan
--		or string.match(tz, "^Asia/Kabul")
	) then
		self:setHours("12")
	else
		self:setHours("24")
	end
	
	self:setDateFormat(tostring(self:string("DATETIME_LONGDATEFORMAT_DEFAULT")) or "%a %d %b %Y")
	self:setShortDateFormat(tostring(self:string("DATETIME_SHORTDATEFORMAT_DEFAULT")) or "%m.%d.%Y")

	-- make US customers use Monday as the week start
	if tostring(lang) == 'EN' and string.match(tz, "^America") then
		self:setWeekStart("Monday")
	else
		self:setWeekStart("Sunday")
	end

	self:storeSettings()
end

--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

