
--[[
=head1 NAME

applets.SetupLanguage.SetupLanguage - Add a main menu option for setting up language

=head1 DESCRIPTION

Allows user to select language used in Jive

=head1 FUNCTIONS

Applet related methods are described in L<jive.Applet>. 

=cut
--]]


-- stuff we use
local ipairs, pairs, io, string = ipairs, pairs, io, string

local oo               = require("loop.simple")

local Applet           = require("jive.Applet")
local RadioGroup       = require("jive.ui.RadioGroup")
local RadioButton      = require("jive.ui.RadioButton")
local Framework        = require("jive.ui.Framework")
local Label            = require("jive.ui.Label")
local SimpleMenu       = require("jive.ui.SimpleMenu")
local Textarea         = require("jive.ui.Textarea")
local Window           = require("jive.ui.Window")
local Popup            = require("jive.ui.Popup")
local Icon             = require("jive.ui.Icon")
local Timer            = require("jive.ui.Timer")
local Task             = require("jive.ui.Task")

local locale           = require("jive.utils.locale")
local table            = require("jive.utils.table")
local debug            = require("jive.utils.debug")

local appletManager    = appletManager
local jiveMain         = jiveMain

module(..., Framework.constants)
oo.class(_M, Applet)

-- the second value is used as weight for the language list
local locales = {
	NO = {'Norsk', 10},
	SV = {'Svenska', 10},
	FI = {'Suomi', 10},
	DA = {'Dansk', 10},
	DE = {'Deutsch', 2},
	EN = {'English', 1},
	ES = {'Español', 10},
	FR = {'Français', 4},
	IT = {'Italiano', 10},
	NL = {'Nederlands', 3},
	RU = {'русский', 10},
	PL = {'Polski', 10},
	CS = {'Čeština', 10},
}


function _jumpToDemo(self)
	appletManager:callService("jumpToInStoreDemo")
end

-- Second part of demo listener (Fab4 only)
function _addDemoListener(self)
	log:warn('ADD DEMO LISTENER')
	self.window:addActionListener("go_now_playing_or_playlist", self, _jumpToDemo)
end


function setupShowSetupLanguage(self, setupNext, helpText)
	local currentLocale = locale:getLocale()
	log:info("locale currently is ", currentLocale)

	-- this uses private data/methods from Applet and locale. don't do this elsewhere,
	-- but it's needed for speed here
	self.allStrings = locale:loadAllStrings(self._entry.dirpath .. "strings.txt")

	-- setup menu
	local window = Window("text_list", self:string("CHOOSE_LANGUAGE"), "setuptitle")
	window:setAllowScreensaver(false)

	self.window = window
	-- Demo listener for devices with hard buttons: Jive and Baby
	window:addActionListener("start_demo", self, _jumpToDemo)
	-- Demo listener for devices with touch screen: Fab4
	window:addActionListener("go_now_playing_or_playlist", self, _addDemoListener)

	window:setButtonAction("lbutton", nil)
	window:setButtonAction("rbutton", nil)

	local menu = SimpleMenu("menu")

	for _, locale in ipairs(locale:getAllLocales()) do 
		if not locales[locale] then
			log:warn("unknown lang ", locale)
		else
			menu:addItem({
				locale = locale,
				text = locales[locale][1],
				sound = "WINDOWSHOW",
				callback = function()
					self:setLang(locale, setupNext)
				end,
				focusGained = function() self:_showLang(locale) end,
				weight = locales[locale][2]
			})
		end
	end

	menu:setComparator(SimpleMenu.itemComparatorWeightAlpha)

	for i, item in menu:iterator() do
		if item.locale == currentLocale then
			menu:setSelectedIndex(i)
		end
	end

	if helpText ~= false then
		menu:setHeaderWidget(Textarea("help_text", self:string("CHOOSE_LANGUAGE_HELP")))
	end
	window:addWidget(menu)

	-- Store the selected language when the menu is exited
        window:addListener(EVENT_WINDOW_INACTIVE,
                function()
			self:_showLang(nil)
                        self:storeSettings()
                end
        )

	-- You have to select your language, no way to close this menu
	menu:setCloseable(false)

	self:tieAndShowWindow(window)
	return window
end


function settingsShow(self, menuItem)
	local currentLocale = locale:getLocale()
	log:info("locale currently is ", currentLocale)

	-- this uses private data/methods from Applet and locale. don't do this elsewhere,
	-- but it's needed for speed here
	self.allStrings = locale:loadAllStrings(self._entry.dirpath .. "strings.txt")

	-- setup menu
	local window = Window("text_list", self:string("LANGUAGE"), 'settingstitle')
	local menu = SimpleMenu("menu")

	local group = RadioGroup()
	for _, locale in ipairs(locale:getAllLocales()) do 
		if not locales[locale] then
			log:warn("unknown lang ", locale)
		else
			local button = RadioButton(
				"radio", 
				group, 
				function() self:setLang(locale) end, 
				locale == currentLocale
			)
			menu:addItem({
				locale = locale,
				text = locales[locale][1],
				style = 'item_choice',
				check = button,
				focusGained = function() self:_showLang(locale) end,
				weight = locales[locale][2]
			})
		end
	end
	menu:setComparator(SimpleMenu.itemComparatorWeightAlpha)

	for i, item in menu:iterator() do
		if item.locale == currentLocale then
			menu:setSelectedIndex(i)
			break
		end
	end
	window:addWidget(menu)

	-- Store the selected language when the menu is exited
        window:addListener(EVENT_WINDOW_POP,
                function()
			self:_showLang(nil)
                        self:storeSettings()
                end
        )

	self:tieAndShowWindow(window)
	return window
end


function _showLang(self, choice)
	if not choice then
		choice = self:getSettings().locale
	end

	-- this modifies the Applets strings directly. don't do this elsewhere, but it's
	-- needed for speed here
	for k,v in pairs(self._stringsTable) do
		v.str = self.allStrings[choice][k] or self.allStrings["EN"][k]
	end

	Framework:styleChanged()
end

function setLang(self, choice, next)
	log:info("Locale choice set to ", choice)

	self:_showLang(choice)

	self:getSettings().locale = choice

	-- FIXME SlimBrowser should use notification
	-- if connected to a player, ask for the menu again
	local player = appletManager:callService("getCurrentPlayer")
	if player then
		local server = player:getSlimServer()
		if server then
			 server:userRequest(nil, player:getId(), { 'menu', 0, 100 })
		end
	end

	-- changing the locale is slow, do this in a task with a spinny
	self.popup = Popup("waiting_popup")
	self.popup:setAllowScreensaver(false)
	self.popup:setAlwaysOnTop(true)
	self.popup:setAutoHide(false)
	self.popup:ignoreAllInputExcept()

	self.popup:addWidget(Icon("icon_connecting"))
  	local stringChoice = "LOADING_LANGUAGE"
	self.popup:addWidget(Label("text", self:string(stringChoice)))
   	self.popup:show()

	self.task = Task('setLang', self, 
			 function(self)
				 locale:setLocale(choice, true)

				 -- FIXME jiveMainNodes should use notification
				 jiveMain:jiveMainNodes()
				 Framework:styleChanged()

				 self.popup:hide()

				 if next then
					 next()
				 end
			 end
		 ):addTask()
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

