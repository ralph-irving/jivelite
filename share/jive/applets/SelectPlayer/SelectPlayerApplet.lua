
--[[
=head1 NAME

applets.SelectPlayer.SelectPlayerApplet - Applet to select currently active player

=head1 DESCRIPTION

Gets list of all available players and displays for selection. Selection should cause main menu to update (i.e., so things like "now playing" are for the selected player)

=head1 FUNCTIONS

Applet related methods are described in L<jive.Applet>. 

=cut
--]]


-- stuff we use
local assert, pairs, ipairs, tostring = assert, pairs, ipairs, tostring

local oo                 = require("loop.simple")
local os                 = require("os")
local string             = require("string")

local Applet             = require("jive.Applet")
local System             = require("jive.System")
local SimpleMenu         = require("jive.ui.SimpleMenu")
local RadioGroup         = require("jive.ui.RadioGroup")
local RadioButton        = require("jive.ui.RadioButton")
local Window             = require("jive.ui.Window")
local Popup              = require("jive.ui.Popup")
local Group              = require("jive.ui.Group")
local Icon               = require("jive.ui.Icon")
local Label              = require("jive.ui.Label")
local Framework          = require("jive.ui.Framework")
local Surface            = require("jive.ui.Surface")
--local LocalPlayer        = require("jive.slim.LocalPlayer")

local hasNetworking, Networking  = pcall(require, "jive.net.Networking")

local debug              = require("jive.utils.debug")

--local SetupSqueezeboxApplet = require("applets.SetupSqueezebox.SetupSqueezeboxApplet")

local jnt                = jnt
local jiveMain           = jiveMain
local appletManager      = appletManager

module(..., Framework.constants)
oo.class(_M, Applet)


local LOCAL_PLAYER_WEIGHT = 1
local PLAYER_WEIGHT = 5
local SERVER_WEIGHT = 10
local ACTIVATE_WEIGHT = 20

function init(self, ...)
	self.playerItem = {}
	self.serverItem = {}
	self.scanResults = {}

	if hasNetworking then
		self.wireless = Networking:wirelessInterface(jnt)
	end

	jnt:subscribe(self)
	self:manageSelectPlayerMenu()
end


function notify_playerDelete(self, player)
	local mac = player:getId()

	manageSelectPlayerMenu(self)

	if self.playerMenu then
		if self.playerItem[mac] then
			self.playerMenu:removeItem(self.playerItem[mac])
			self.playerItem[mac] = nil
		end

		if player:getSlimServer() then
			self:_updateServerItem(player:getSlimServer())
		end
	end
end


function notify_playerNew(self, player)
	-- get number of players. if number of players is > 1, add menu item
	local mac = player:getId()

	manageSelectPlayerMenu(self)

	if self.playerMenu then
		self:_addPlayerItem(player)

		if player:getSlimServer() then
			self:_updateServerItem(player:getSlimServer())
		end
	end
end


function notify_playerCurrent(self, player)
	self.selectedPlayer = player
	self:manageSelectPlayerMenu()
end


function notify_serverConnected(self, server)
	if not self.playerMenu then
		return
	end

	self:_updateServerItem(server)

	for id, player in server:allPlayers() do
		self:_refreshPlayerItem(player)
	end
	
	self:manageSelectPlayerMenu()

end


function notify_serverDisconnected(self, server)
	if not self.playerMenu then
		return
	end

	self:_updateServerItem(server)

	for id, player in server:allPlayers() do
		self:_refreshPlayerItem(player)
	end

	self:manageSelectPlayerMenu()
end


function manageSelectPlayerMenu(self)
	local _numberOfPlayers = appletManager:callService("countPlayers") or 0
	local currentPlayer    = appletManager:callService("getCurrentPlayer") or nil

	-- if _numberOfPlayers is > 1 and selectPlayerMenuItem doesn't exist, create it
	if _numberOfPlayers > 1 or not currentPlayer or not currentPlayer:isConnected() then
		if not self.selectPlayerMenuItem then
			local node = "home"
			local weight = 103
			if System:hasAudioByDefault() then
				node = "settings"
				weight = 50
			end

			local menuItem = {
				id = 'selectPlayer',
				iconStyle = 'hm_selectPlayer',
				node = node,
				text = self:string("SELECT_PLAYER"),
				sound = "WINDOWSHOW",
				callback = function() self:setupShowSelectPlayer() end,
				weight = weight,
			}
			jiveMain:addItem(menuItem)
			self.selectPlayerMenuItem = menuItem
		end

	-- if numberOfPlayers < 2 and we're connected to a player and selectPlayerMenuItem exists, get rid of it
	elseif _numberOfPlayers < 2 and currentPlayer and self.selectPlayerMenuItem then
		jiveMain:removeItemById('selectPlayer')
		self.selectPlayerMenuItem = nil
	end
end


function _addPlayerItem(self, player)
	local mac = player:getId()
	local playerName = player:getName()
	local playerWeight = PLAYER_WEIGHT

	-- 08/29/09 - fm
	-- Only allow Controller to setup not yet setup players (i.e. Receiver)
	-- If other squeezeplay based devices need to be able to setup players
	--  additional work is needed as soon as this devices not only have
	--  a wireless interface but ethernet also. If such a device is using
	--  ethernet itself it can only setup a player to also using ethernet
	--  since wireless parameters are not available.
	if System:hasAudioByDefault() and player.config == "needsNetwork" then
		return
	end

	-- create a lookup table of valid models, 
	-- so Choose Player does not attempt to render a style that doesn't exist
	local validModel = {
		softsqueeze = true,
		transporter = true,
		squeezebox2 = true,
		squeezebox3 = true,
		squeezebox  = true,
		slimp3      = true,
		receiver    = true,
		boom        = true,
		controller  = true,
		squeezeplay = true,
		http        = true,
		fab4        = true,
		baby        = true,
	}

	local playerModel = player:getModel()
	log:debug("Player: ", player, ' is model: ', playerModel)

	-- guess model by mac address if we don't have one available
	-- this is primarily used for players on the network waiting to be setup
	if playerModel == nil then
		playerModel = player:macToModel(mac)
	end

	if not validModel[playerModel] then
		-- use a generic style when model lists as not valid
		playerModel = 'squeezeplay'
	end

	if player:isLocal() then
		playerWeight = LOCAL_PLAYER_WEIGHT
	end
    
	-- if waiting for a SN pin modify name
	if player:getPin() then
		if not self.setupMode then
			-- Only include Activate SN during setup
			return
		end

		playerName = self:string("SQUEEZEBOX_ACTIVATE", player:getName())
		playerWeight = ACTIVATE_WEIGHT
	end

	local item = {
		id = mac,
		style = 'item',
		iconStyle = "player_" .. playerModel,
		text = playerName,
		sound = "WINDOWSHOW",
		callback = function()
			log:info("select player item: ", player)
			if self:selectPlayer(player) then
				log:info("going to setupnext: : ", self.setupNext)
				self.setupNext()
			end
		end,
		focusGained = function(event)
			self:_showWallpaper(mac)
			return EVENT_UNUSED
		end,
		weight = playerWeight
	}

	if player == self.selectedPlayer and player:isConnected() then
		item.style = "item_checked"
	end

	self.playerMenu:addItem(item)
	self.playerItem[mac] = item
	
	if self.selectedPlayer == player then
		self.playerMenu:setSelectedItem(item)
	end

	-- we already have a player in the menu, set a flag to not use the scanning popup
	self.playersFound = true
	-- and hide it if it's already on screen
	self:_hidePopulatingPlayersPopup()

end


function _refreshPlayerItem(self, player)
	local mac = player:getId()

	if player:isAvailable() then
		local item = self.playerItem[mac]
		if not item then
			-- add player
			self:_addPlayerItem(player)

		else
			-- update player state
			if player == self.selectedPlayer then
				item.style = "item_checked"
			end
		end

	else
		-- not connected
		if self.playerItem[mac] then
			self.playerMenu:removeItem(self.playerItem[mac])
			self.playerItem[mac] = nil
		end
	end
end


-- Add password protected servers
function _updateServerItem(self, server)
	local id = server:getName()

	if not server:isPasswordProtected() then
		if self.serverItem[id] then
			self.playerMenu:removeItem(self.serverItem[id])
			self.serverItem[id] = nil
		end
		return
	end

	local item = {
		id = id,
		text = server:getName(),
		sound = "WINDOWSHOW",
		callback = function()
			appletManager:callService("squeezeCenterPassword", server, nil, nil, true)
		end,
		weight = SERVER_WEIGHT,
	}

	self.playerMenu:addItem(item)
	self.serverItem[id] = item
end


function _showWallpaper(self, playerId)
	log:debug("previewing background wallpaper for ", playerId)
	appletManager:callService("showBackground", nil, playerId)
end


function setupShowSelectPlayer(self, setupNext, windowStyle)

	if not windowStyle then
		windowStyle = 'settingstitle'
	end
	-- get list of slimservers
	local window = Window("choose_player", self:string("SELECT_PLAYER"), windowStyle)
	window:setAllowScreensaver(false)

        local menu = SimpleMenu("menu")
	menu:setComparator(SimpleMenu.itemComparatorWeightAlpha)

	self.playerMenu = menu
	self.setupMode = setupNext ~= nil
	self.setupNext = setupNext or 
		function()
			jiveMain:closeToHome()
		end

	self.selectedPlayer = appletManager:callService("getCurrentPlayer")
	for mac, player in appletManager:callService("iteratePlayers") do
		_addPlayerItem(self, player)
	end

	-- Display password protected servers
	for id, server in appletManager:callService("iterateSqueezeCenters") do
		_updateServerItem(self, server)
	end

	-- 08/29/09 - fm
	-- Only allow Controller to setup not yet setup players (i.e. Receiver)
	-- If other squeezeplay based devices need to be able to setup players
	--  additional work is needed as soon as this devices not only have
	--  a wireless interface but ethernet also. If such a device is using
	--  ethernet itself it can only setup a player to also using ethernet
	--  since wireless parameters are not available.

	-- Bug 6130 add a Set up Squeezebox option, only in Setup not Settings
	if setupNext and not System:hasAudioByDefault() then
		self.playerMenu:addItem({
			text = self:string("SQUEEZEBOX_SETUP"),
			sound = "WINDOWSHOW",
			callback = function()
				appletManager:callService("setupSqueezeboxShow", self.setupNext)
			end,
			iconStyle = 'receiver',
			style = 'item',
			weight = 10,
		})
	end

	window:addWidget(menu)

	window:addTimer(5000, function() 
				-- only scan if this window is on top, not under a transparent popup
				if Framework.windowStack[1] ~= window then
					return
				end
				self:_scan() 
			end)

	window:addTimer(10000, function() 
				self:_hidePopulatingPlayersPopup()
			end)

	window:addListener(EVENT_WINDOW_ACTIVE,
			   function()
				   self:_scan()
			   end)

	self:tieAndShowWindow(window)

	if self.setupMode then
		self.populatingPlayers = self:_showPopulatingPlayersPopup()
	end

	return window
end

function _hidePopulatingPlayersPopup(self, timer)

	if self.populatingPlayers then
		self.populatingPlayers:hide()
		self.populatingPlayers = false
	end

end

function _showPopulatingPlayersPopup(self, timer)

        if self.populatingPlayers or self.playersFound then
                return
        end

        local popup = Popup("waiting_popup")
        local icon  = Icon("icon_connecting")
        local label = Label("text", self:string("SEARCHING"))
        popup:addWidget(icon)
        popup:addWidget(label)
        popup:setAlwaysOnTop(true)

        popup:show()
	return popup

end

function _scan(self)
	-- SqueezeCenter and player discovery
	appletManager:callService("discoverPlayers")
end


function selectPlayer(self, player)
	-- if connecting to SqueezeNetwork, first check we are linked
	if player:getPin() then
		-- as we are not linked this is a dummy player, after we need linked we
		-- need to return to the choose player screen
		log:info("calling enterPin")
		appletManager:callService("enterPin", nil, player)

		return false
	end

	-- set the current player
	self.selectedPlayer = player
	appletManager:callService("setCurrentPlayer", player)

	-- network configuration needed?
	if player:needsNetworkConfig() then
		log:info("needsNetworkConfig")
		-- setup networking
		appletManager:callService("startSqueezeboxSetup",
			player:getId(),
			player:getSSID(),
			function()
				if self.setupMode then
					self.setupNext()
				elseif player:needsMusicSource() then
					-- then choose a server
					appletManager:callService("selectMusicSource")
				end
			end)
		return false
	end

	-- udap setup needed?
	if player:needsMusicSource() and not self.setupMode then
		log:info("selectMusicSource")
		--todo review this with new SlimMenus changes
		--until server is connected, we offer sn switch since the user should be allowed to choose SC or SN in this limbo state
		--appletManager:callService("addSwitchToSnMenuItem")
		appletManager:callService("selectMusicSource", nil, nil, nil, nil, nil, nil, nil, true)
		return false
	end

	return true
end


function free(self)

	-- load the correct wallpaper on exit
	if self.selectedPlayer and self.selectedPlayer:getId() then
		self:_showWallpaper(self.selectedPlayer:getId())
	else
		self:_showWallpaper('wallpaper')
	end
	
	-- Never free this applet
	return false
end

--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

