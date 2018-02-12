
--[[
=head1 NAME

applets.LineIn.LineIn

=head1 DESCRIPTION

Applet to manage use of Line In

=head1 FUNCTIONS

Applet related methods are described in L<jive.Applet>. 

=cut
--]]


-- stuff we use
local ipairs, pairs, assert, io, string, tonumber = ipairs, pairs, assert, io, string, tonumber

local oo               = require("loop.simple")
local os               = require("os")

local Applet           = require("jive.Applet")
local RadioGroup       = require("jive.ui.RadioGroup")
local RadioButton      = require("jive.ui.RadioButton")
local Framework        = require("jive.ui.Framework")
local Label            = require("jive.ui.Label")
local Icon             = require("jive.ui.Icon")
local Group            = require("jive.ui.Group")
local Button           = require("jive.ui.Button")
local SimpleMenu       = require("jive.ui.SimpleMenu")
local Surface          = require("jive.ui.Surface")
local Task             = require("jive.ui.Task")
local Textarea         = require("jive.ui.Textarea")
local Window           = require("jive.ui.Window")
local Popup            = require("jive.ui.Popup")
local Player           = require("jive.slim.Player")
local Checkbox         = require("jive.ui.Checkbox")

local localPlayer      = require("jive.slim.LocalPlayer")
local slimServer       = require("jive.slim.SlimServer")

local DNS              = require("jive.net.DNS")

local debug            = require("jive.utils.debug")
local locale           = require("jive.utils.locale")
local string           = require("jive.utils.string")
local table            = require("jive.utils.table")

local appletManager    = appletManager

local jiveMain         = jiveMain
local jnt              = jnt


module(..., Framework.constants)
oo.class(_M, Applet)

function init(self, ...)
	jnt:subscribe(self)
	return self

end

--service method
function addLineInMenuItem(self)
	self.checkbox = Checkbox("checkbox", function(_, checked)
				self:activateLineIn(checked)
			end)
	jiveMain:addItem({
		id = "linein",
		node = "home",
		text = self:string("LINE_IN"),
		style = 'item_choice',
		iconStyle = 'hm_linein',
		check = self.checkbox,
		weight = 50,
	})
--	local popup = Popup("toast_popup_icon")
--	local icon  = Icon("icon_popup_lineIn")
--	local group = Group("group", {
--		icon = icon
--	})
--	popup:addWidget(group)
--	popup:showBriefly(3000, nil, Window.transitionFadeIn, Window.transitionFadeOut )

end

--service method (should only be called when LineIn is connected)
function activateLineIn(self, active, initialPlayMode)
	if not self.checkbox then
		--must be coming from external source, so first create the menu item
		self:addLineInMenuItem()
	end
	self.checkbox:setSelected(active)

	if active then
		self:_activateLineIn(initialPlayMode)
	else
		self:_deactivateLineIn()
	end

end

function _activateLineIn(self, initialPlayMode)
	log:info("_activateLineIn")

	local player = Player:getLocalPlayer()

	player:stop(true)
	player:setCapturePlayMode(initialPlayMode or "play")

	self:_addListeners()
	self:createLineInNowPlaying()

	appletManager:callService("deactivateScreensaver")
	appletManager:callService("restartScreenSaverTimer")

	appletManager:callService("goNowPlaying")
end

function _deactivateLineIn(self)
	log:info("_deactivateLineIn")

	local player = Player:getLocalPlayer()

	player:setCapturePlayMode(nil)

	self:_removeListeners()

	if self.npWindow then
		self.npWindow:hide()
	end
	self.npWindow = nil
end


function notify_playerModeChange(self, player, mode)
	if Player:getLocalPlayer() ~= player then
		return
	end

	if mode == "play" and self:isLineInActive() then
		log:info("player mode changed to play, deactivating line in")
		self:activateLineIn(false)
	end
end

--service method
function isLineInActive(self)
	return (self.npWindow ~= nil)
end


--service method
function getLineInNpWindow(self)
	return self.npWindow
end


--service method
function removeLineInMenuItem(self)
	jiveMain:removeItemById("linein")
	self.checkbox = nil
	self:_deactivateLineIn()
end

function _addListeners(self)
	log:debug("_addListeners")
	if not self.listenerHandles then
		self.listenerHandles = {}
	end
	self:_removeListeners()

	local pauseAction = function(self)

		if Player:getLocalPlayer():getCapturePlayMode() == "play" then
			Player:getLocalPlayer():setCapturePlayMode("pause")
		else
			Player:getLocalPlayer():setCapturePlayMode("play")
		end
		return EVENT_CONSUME
	end
	local stopAction = function(self)
		Player:getLocalPlayer():setCapturePlayMode("pause")
		return EVENT_CONSUME
	end
	local playAction = function(self)
		Player:getLocalPlayer():setCapturePlayMode("play")
		return EVENT_CONSUME
	end
	local nothingAction = function(self)
		return EVENT_CONSUME
	end
	local goNowPlayingAction = function(self)
		log:warn("calling NP")

		appletManager:callService("goNowPlaying")
		return EVENT_CONSUME
	end

	table.insert(self.listenerHandles, Framework:addActionListener("mute", self, pauseAction, .5))
	table.insert(self.listenerHandles, Framework:addActionListener("pause", self, pauseAction, .5))
	table.insert(self.listenerHandles, Framework:addActionListener("stop", self, stopAction, .5))
	table.insert(self.listenerHandles, Framework:addActionListener("play", self, playAction, .5))
	table.insert(self.listenerHandles, Framework:addActionListener("jump_rew", self, nothingAction, .5))
	table.insert(self.listenerHandles, Framework:addActionListener("jump_fwd", self, nothingAction, .5))
	table.insert(self.listenerHandles, Framework:addActionListener("scanner_rew", self, nothingAction, .5))
	table.insert(self.listenerHandles, Framework:addActionListener("scanner_fwd", self, nothingAction, .5))
	table.insert(self.listenerHandles, Framework:addActionListener("go_current_track_info", self, goNowPlayingAction, .5))
	table.insert(self.listenerHandles, Framework:addActionListener("go_playlist", self, goNowPlayingAction, .5))

end


function _removeListeners(self)
	log:debug("_removeListeners")
	if not self.listenerHandles then
		self.listenerHandles = {}
	end

	for _, handle in ipairs(self.listenerHandles) do
		Framework:removeListener(handle)
	end
end


function createLineInNowPlaying(self)
	log:debug("createLineInNowPlaying")

	--todo: don't show if already up

	local window = Window("linein")

	local titleGroup = Group('title', {
		lbutton = window:createDefaultLeftButton(),

		text = Label("text", self:string("LINE_IN")),

		rbutton = nil,
	   })

	local artworkGroup = Group('npartwork', {
			artwork = Icon("icon_linein"),
	})

	local nptrackGroup = Group('nptitle', {
		nptrack = Label('nptrack', self:string("LINE_IN")),
		xofy    = nil,
	})

	window:addWidget(titleGroup)
	window:addWidget(nptrackGroup)
	window:addWidget(artworkGroup)

	self.npWindow = window
end



--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

