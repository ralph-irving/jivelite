
--[[
=head1 NAME

applets.LogSettings.LogSettingsApplet - An applet to control Jive log verbosity.

=head1 DESCRIPTION

This applets collects the log categories defined in the running Jive program
and displays each along with their respective verbosity level. Changing the
level is taken into account immediately.

=head1 FUNCTIONS

Applet related methods are described in L<jive.Applet>. 
LogSettingsApplet overrides the following methods:

=cut
--]]


-- stuff we use
local assert, loadfile, ipairs, pairs, setfenv, type = assert, loadfile, ipairs, pairs, setfenv, type

local oo              = require("loop.simple")

local io              = require("io")
local string          = require("string")
local table           = require("table")
local dumper          = require("jive.utils.dumper")

local Applet          = require("jive.Applet")
local System          = require("jive.System")
local Choice          = require("jive.ui.Choice")
local Framework       = require("jive.ui.Framework")
local SimpleMenu      = require("jive.ui.SimpleMenu")
local Window          = require("jive.ui.Window")
local logger          = require("jivelite.log")

local debug           = require("jive.utils.debug")


module(..., Framework.constants)
oo.class(_M, Applet)


-- _gatherLogCategories
-- workhouse that discovers the log categories and for each, creates a suitable
-- table entry to please SimpleMenu
local function _gatherLogCategories()
	
	local res = {}
	
	-- for all items in the (sub)-table

	local levels = { "Debug", "Info", "Warn", "Error", "Off" }

	for name,cat in pairs(logger.categories()) do
		local level = cat:getLevel()

		local idx = 1
		for i, v in ipairs(levels) do
			if level == string.upper(levels[i]) then
				idx = i
			end
		end
	
		-- create a Choice
		local choice = Choice(
			"choice", 
			levels,
			function(obj, selectedIndex)
				log:debug("set ", name, " to ", levels[selectedIndex])
				cat:setLevel(levels[selectedIndex])
			end,
			idx
		)
		
		-- insert suitable entry for Choice menu
		table.insert(res, 
			{
				text = name,
				style = 'item_choice',
				check = choice,
			}
		)
	end
	
	return res
end


function _saveLogconf()
	local logconf

	-- load existing configuration
	local confin = System:findFile("logconf.lua")
	if confin then
		local f, err = loadfile(confin)
		if f then
			setfenv(f, {})
			logconf = f()
		else
			log:warn("error in logconf: ", err)
		end
	end

	if type(logconf) ~= "table" then
		logconf = {}
		logconf.category = {}
		logconf.appender = {}
	end

	-- update category levels
	for name,cat in pairs(logger.categories()) do
		local level = cat:getLevel()

		if level == "INFO" then
			logconf.category[name] = nil
		else
			logconf.category[name] = level
		end
	end

	-- save configuration
	local confout = System:getUserDir() .. "/logconf.lua"

	System:atomicWrite(confout, dumper.dump(logconf, nil, false))
end


-- logSettings
-- returns a window with Choices to set the level of each log category
-- the log category are discovered
function logSettings(self, menuItem)

	local logCategories = _gatherLogCategories()
	local window = Window("text_list", menuItem.text, 'settingstitle')
	local menu = SimpleMenu("menu", logCategories)
	menu:setComparator(menu.itemComparatorAlpha)

	window:addWidget(menu)

	window:addListener(EVENT_WINDOW_INACTIVE,
		function()
			_saveLogconf()
		end)

	self:tieAndShowWindow(window)
	return window
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

