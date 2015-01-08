
--[[
=head1 NAME

applets.SlimServers.SlimServersApplet - Menus to edit the Slimserver address

=head1 DESCRIPTION

This applet allows users to define IP addresses for their slimserver.  This is useful if
the automatic discovery process does not work - normally because the server and jive are on different subnets meaning
that UDP broadcasts probing for servers do not get through.

Users may add one or more slimserver IP addresses, these will be probed by the server discovery mechanism
implemented in SlimDiscover.  Removing all explicit server IP addresses returns to broadcast discovery.

=head1 FUNCTIONS


=cut
--]]


-- stuff we use
local pairs, setmetatable, tostring, tonumber, ipairs  = pairs, setmetatable, tostring, tonumber, ipairs

local oo            = require("loop.simple")
local string        = require("string")
local table         = require("jive.utils.table")

local Applet        = require("jive.Applet")

local Framework     = require("jive.ui.Framework")
local Event         = require("jive.ui.Event")
local Checkbox      = require("jive.ui.Checkbox")
local Label         = require("jive.ui.Label")
local Button        = require("jive.ui.Button")
local Group         = require("jive.ui.Group")
local SimpleMenu    = require("jive.ui.SimpleMenu")
local Window        = require("jive.ui.Window")
local Textarea      = require("jive.ui.Textarea")
local Textinput     = require("jive.ui.Textinput")
local Keyboard      = require("jive.ui.Keyboard")
local Popup         = require("jive.ui.Popup")
local Icon          = require("jive.ui.Icon")
local SlimServer    = require("jive.slim.SlimServer")

local debug         = require("jive.utils.debug")
local iconbar       = iconbar

local jnt           = jnt
local jiveMain      = jiveMain
local appletManager = appletManager


module(..., Framework.constants)
oo.class(_M, Applet)


local CONNECT_TIMEOUT = 20


--temp during dev
function settingsShow(self)
	selectMusicSource(self)
end

function selectCompatibleMusicSource(self)
	self.offerCompatibleSourcesOnly = true
	selectMusicSource(self)
end

-- service to select server for a player. Note a current player must exist before calling this method
-- if specificServer is set to false, then offer a list even if only one server exists. If specificServer, if only on server exists,
--  it will automatically be selected.
function selectMusicSource(self, playerConnectedCallback, titleStyle, includedServers, specificServer, serverForRetry, ignoreServerConnected, confirmOnChange, offerSn)

	if includedServers then
		self.includedServers = includedServers
	end

	if playerConnectedCallback then
		self.playerConnectedCallback = playerConnectedCallback
	else
		self.playerConnectedCallback = 	function()
							appletManager:callService("goHome")
						end
	end

	if titleStyle then
		self.titleStyle = titleStyle
	end

	jnt:subscribe(self)

	self.serverList = {}
	self.ignoreServerConnected = ignoreServerConnected
	self.confirmOnChange = confirmOnChange
	self.offerSn = false --offerSn

	if specificServer then
		log:debug("selecting specific server ", specificServer)

		self:selectServer(specificServer, nil, serverForRetry)
		return
	end

	local offerListIfOnlyOneServerExists
	if specificServer == false then
		offerListIfOnlyOneServerExists = true
	end

	self:_showMusicSourceList(offerListIfOnlyOneServerExists)
end


function _showMusicSourceList(self, offerListIfOnlyOneServerExists)

	local window = Window("text_list", self:string("SLIMSERVER_SERVERS"), self.titleStyle)
	local menu = SimpleMenu("menu", items)
	menu:setComparator(SimpleMenu.itemComparatorWeightAlpha)
	window:addWidget(menu)
	window:setAllowScreensaver(false)

	menu:addActionListener("back", self,  function ()
							window:playSound("WINDOWHIDE")
							self:_cancelSelectServer()
							window:hide()

							return EVENT_CONSUME
						end)

	local current = appletManager:callService("getCurrentPlayer")

	self.serverMenu = menu
	self.serverList = {}

	-- subscribe to the jnt so that we get notifications of servers added/removed
	jnt:subscribe(self)


	-- Discover players in this window
	appletManager:callService("discoverServers")
	window:addTimer(1000, function() appletManager:callService("discoverServers") end)


	-- squeezecenter on the poll list
	log:debug("Polled Servers:")
	local poll = appletManager:callService("getPollList")
	for address,_ in pairs(poll) do
		log:debug("\t", address)
		if address ~= "255.255.255.255" then
			self:_addServerItem(nil, address)
		end
	end


	-- discovered squeezecenters
	log:debug("Discovered Servers:")
	for _,server in appletManager:callService("iterateSqueezeCenters") do
		log:debug("\t", server)
		self:_addServerItem(server, _)
	end

	-- Store the applet settings when the window is closed
	window:addListener(EVENT_WINDOW_POP,
			   function()
				self:storeSettings()
		   	end
	)

	window._isChooseMusicSourceWindow = true

	--if list contains only one item, select it directly
	local singleServer
	for address,item in pairs(self.serverList) do
		if singleServer then
			--more than one found, so not single server situation
			singleServer = nil
			break
		end
		singleServer = item.server
	end

	if not offerListIfOnlyOneServerExists and singleServer then
		log:info("Only one server found, select it directly: ", singleServer)

		self:selectServer(singleServer)
		return
	end

	self:tieAndShowWindow(window)

end


function free(self)

	if self.playerConnectedCallback then
		log:warn("Unexpected free when playerConnectedCallback still exists (could happen on regular back)")
	end
	log:debug("Unsubscribing jnt")
	jnt:unsubscribe(self)

	return true
end


function _createRemoteServer(self, address)
	--look first for existing server with same address to avoid having two server instances for same server
	local server = SlimServer:getServerByAddress(address)
	if not server then
		server = SlimServer(jnt, address, address)
		server:updateInit({ip=address}, 9000)
	else
		log:info("Using existing server with same ip address: ", server)
	end

	return server
end


function _addServerItem(self, server, address)
	log:debug("\t_addServerItem ", server, " " , address)

	if not self.serverMenu then
		--happens on selectMusicSource with specificServer
		log:info("Ignoring addServer Item when no serverMenu")
		return
	end
	--not sure this is used anymore, consider removing
	if self.includedServers then
		local found = false
		-- filter server list only showing those found in includedServers
		for _, includedServer in ipairs(self.includedServers) do
			if includedServer == server then
				log:debug("found server: ", server)
				found = true
				break
			end
		end
		if not found then
			log:debug("server not found: ", server)
			return
		end
	end

	if server and server:isSqueezeNetwork() and not self.offerSn then
		log:debug("Exclude SN")
		return
	end
	
	-- Bug 15860: need to test if we know the server name:
	-- not knowing it probably means we do not know if it is compatible,
	-- so we need to offer it just in case.
	if self.offerCompatibleSourcesOnly and server and not server:isCompatible() then
		log:info("Exclude non-compatible source: ", server)
		return
	end

	local id
	if server then
		id = server:getIpPort()
	else
		id = address
		server = self:_createRemoteServer(address)
	end

	log:debug("\tid for this server set to: ", id)

	local currentPlayer    = appletManager:callService("getCurrentPlayer")

	-- remove existing entry
	if self.serverList[id] then
		self.serverMenu:removeItem(self.serverList[id])
	end

	if server then
		if self.serverList[server:getIpPort()] then
			self.serverMenu:removeItem(self.serverList[server:getIpPort()])
		end

		-- new entry
		local item = {
			server = server,
			text = server:getName(),
			sound = "WINDOWSHOW",
			callback = function()
				self:selectServer(server)
                	end,
			weight = 1,
		}

		self.serverMenu:addItem(item)
		self.serverList[id] = item

		if currentPlayer and currentPlayer:getSlimServer() == server then
			item.style = 'item_checked'
			self.serverMenu:setSelectedItem(item)
		end
	end
end


function _delServerItem(self, server, address)
	-- remove entry
	local id = server or address
	if self.serverList[id] then
		self.serverMenu:removeItem(self.serverList[id])
		self.serverList[id] = nil
	end

	-- new entry if server is on poll list
	if server then
		local poll = appletManager:callService("getPollList")
		local address = server:getIpPort()
		if poll[address] then
			self:_addServerItem(nil, address)
		end
	end
end

function notify_serverAuthFailed(self, server, failureCount)
	log:debug("self.waitForConnect:", self.waitForConnect, " ", server)

	if self.waitForConnect and self.waitForConnect.server and self.waitForConnect.server == server and failureCount == 1 then
		self:_httpAuthErrorWindow(server)
	end
end

function notify_serverNew(self, server)
	self:_addServerItem(server)
end


function notify_serverDelete(self, server)
	self:_delServerItem(server)
end

function notify_serverConnected(self, server)
	if not self.waitForConnect or self.waitForConnect.server ~= server then
		return
	end
	log:info("notify_serverConnected")

	iconbar:setServerError("OK")

	-- hide connection error window (useful when server was down and comes back up)
	-- but we need a check here for other case (can't find it now...) where we need to wait until player current
	local isLocalPlayer = self.waitForConnect.player:isLocal()
	-- cancelling here not applicable for remote players since serverConnected is always called for a remote server switch, but there
	--  may be cases where with a remote player the cancel doesn't occur. I currently don't have a use case for that 
	if self.connectingPopup and not self.ignoreServerConnected and isLocalPlayer then
		self:_cancelSelectServer()
	end
end

function _updateServerList(self, player)
	local server = player and player:getSlimServer() and player:getSlimServer():getIpPort()

	for id, item in pairs(self.serverList) do
		if server == id then
			item.style = 'item_checked'
		else
			item.style = nil
		end
		self.serverMenu:updatedItem(item)
	end
end


function notify_playerNew(self, player)
	local currentPlayer = appletManager:callService("getCurrentPlayer")
	if player ~= currentPlayer then
		return
	end

	_updateServerList(self, player)
end


function notify_playerDelete(self, player)
	local currentPlayer = appletManager:callService("getCurrentPlayer")
	if player ~= currentPlayer then
		return
	end

	_updateServerList(self, player)
end


function notify_playerCurrent(self, player)
	_updateServerList(self, player)

	if not player then
		log:warn("Unexpected nil player when waiting for new player or server")
		--todo might this happen if player loses connection during this connection attempt
		-- if so what to do here? Maybe inform user of player disconnection and start over?
		 self:_cancelSelectServer()

	end
end



-- server selected in menu
function selectServer(self, server, passwordEntered, serverForRetry)
	-- ask for password if the server uses http auth
	if not passwordEntered and server:isPasswordProtected() then
		appletManager:callService("squeezeCenterPassword", server,
			function()
				self:selectServer(server, true)
			end, self.titleStyle)
		return
	end

	if server:getVersion() and not server:isCompatible() then
		--we only know if compatible if serverstatus has come back, other version will be nil, and we shouldn't assume not compatible
		_serverVersionError(self, server)
		return
	end


	local currentPlayer = appletManager:callService("getCurrentPlayer")

	if not currentPlayer then
		log:warn("Unexpected nil player when waiting for new player or server")
		--todo might this happen if player loses connection during this connection attempt
		-- if so what to do here? Maybe inform user of player disconnection and start over?
		 self:_cancelSelectServer()
	end


	-- is the player already connected to the server?
	if currentPlayer:getSlimServer() == server and currentPlayer:isConnected() and not self.ignoreServerConnected then

		if self.playerConnectedCallback then
			local callback = self.playerConnectedCallback
			self.playerConnectedCallback = nil
			callback(server)
		end
		return
	end

	--Confirmation check.  Also, don't show confirmation if current player is not playing or there are no tracks in the playlist.
	if not self.confirmOnChange or not currentPlayer:getSlimServer() or currentPlayer:getSlimServer() == server
		or (currentPlayer:getPlayMode() ~= "play" or (not currentPlayer:getPlaylistSize() or currentPlayer:getPlaylistSize() == 0) ) then
       	        self:connectPlayerToServer(currentPlayer, server)
	else
		self:_confirmServerSwitch(currentPlayer, server, serverForRetry)
	end

end

function _httpAuthErrorWindow(self, server)
	local window = Window("help_list", self:string("SWITCH_PASSWORD_WRONG"), "setuptitle")

	local textarea = Textarea("help_text", self:string("SWITCH_PASSWORD_WRONG_BODY"))

	local menu = SimpleMenu("menu")

	window:setAutoHide(true)

	menu:addItem({
		text = self:string("SQUEEZEBOX_TRY_AGAIN"),
		sound = "WINDOWHIDE",
		callback = function()
				appletManager:callService("squeezeCenterPassword", server,
					function()
						self:selectServer(server, true)
					end, self.titleStyle)
			   end,
	})
	local cancelAction = function()
		window:playSound("WINDOWHIDE")
		self:_cancelSelectServer()

		return EVENT_CONSUME
	end

	menu:addActionListener("back", self, cancelAction)
	menu:addActionListener("go_home", self, cancelAction)

	menu:setHeaderWidget(textarea)
	window:addWidget(menu)

	window._isChooseMusicSourceWindow = true

	self:tieAndShowWindow(window)
end



--todo: this should hide if connection returns
function _confirmServerSwitch(self, currentPlayer, server, serverForRetry)
	local window = Window("help_list", self:string("SWITCH_SERVER_TITLE"), "setuptitle")
	window:setAllowScreensaver(false)

	local textarea = Textarea("help_text", self:string("SWITCH_SERVER_TEXT"))

	local menu = SimpleMenu("menu")

	menu:addItem({
		text = (self:string("SWITCH_BUTTON", server.name)),
		sound = "WINDOWSHOW",
		callback = function()
				self:connectPlayerToServer(currentPlayer, server)
				window:hide(Window.transitionNone)
			   end,
	})
	if serverForRetry then
		menu:addItem({
			text = (self:string("CHOOSE_RETRY", serverForRetry.name)),
			sound = "WINDOWHIDE",
			callback = function()
					log:debug("serverForRetry:", serverForRetry)
					self:connectPlayerToServer(currentPlayer, serverForRetry)
					window:hide(Window.transitionNone)
				   end,
		})
	end
	local cancelAction = function()
		self.playerConnectedCallback = nil
		window:hide()

		return EVENT_CONSUME
	end

	menu:addActionListener("back", self, cancelAction)
	menu:addActionListener("go_home", self, cancelAction)

	menu:setHeaderWidget(textarea)
	window:addWidget(menu)

	window._isChooseMusicSourceWindow = true

	self:tieAndShowWindow(window)
end


-- hideConnectingToPlayer
-- hide the full screen popup that appears until server and menus are loaded
function hideConnectingToServer(self)
	log:info("Hiding popup, exists?: " , self.connectingPopup)

	if self.connectingPopup then
		log:info("connectingToServer popup hide")

		--perform callback if we've successfully switched to desired player/server
		if self.waitForConnect then
			log:info("waiting for ", self.waitForConnect.player, " on ", self.waitForConnect.server)

			if self.waitForConnect.server == self.waitForConnect.player:getSlimServer() then
				if self.waitForConnect.server.upgradeForce then
					--finish up, don't steal focus away from upgrade applet, which will have an upgrade window up in this state
					self:_cancelSelectServer(true)
					return
				end

				if self.playerConnectedCallback then
					local callback = self.playerConnectedCallback
					self.playerConnectedCallback = nil
					callback(self.waitForConnect.player:getSlimServer())
					self.ignoreServerConnected = nil
				end
			else
				log:warn("server mismatch for player: ", self.waitForConnect.player, "  Expected: ", self.waitForConnect.server,
				" got: ", self.waitForConnect.player:getSlimServer())
			end
			self.waitForConnect = nil
		end

		self.connectingPopup:hide()
		self.connectingPopup = nil

	end

	--pop any applet windows that are on top (so when current server comes back on line, choose music source exits)
	while Framework.windowStack[1] and Framework.windowStack[1]._isChooseMusicSourceWindow do
		log:debug("Hiding ChooseMusicSource window")

		Framework.windowStack[1]:hide()
	end
end


--service method
function showConnectToServer(self, playerConnectedCallback, server)
	log:debug("showConnectToServer", server)

	self.playerConnectedCallback = playerConnectedCallback
	self:_showConnectToServer(appletManager:callService("getCurrentPlayer"), server)
end

function _showConnectToServer(self, player, server)

	if not self.connectingPopup then
		self.connectingPopup = Popup("waiting_popup")
		local window = self.connectingPopup
		window:addWidget(Icon("icon_connecting"))
		window:setAutoHide(false)

		local statusLabel = Label("text", self:string("SLIMSERVER_CONNECTING_TO"))
		local statusSubLabel = Label("subtext", server:getName())
		window:addWidget(statusLabel)
		window:addWidget(statusSubLabel)

		local timeout = 1

		local cancelAction = function()
			--sometimes timeout not back to 1 next time around, so reset it
			timeout = 1
			self:_connectPlayerFailed(player, server)

			self.connectingPopup:hide()
			self.connectingPopup = nil
		end

		-- disable input
		window:ignoreAllInputExcept({"back", "go_home", "go_home_or_now_playing", "volume_up", "volume_down", "stop", "pause", "power"})
		window:addActionListener("back", self, cancelAction)
		window:addActionListener("go_home", self, cancelAction)
		window:addActionListener("go_home_or_now_playing", self, cancelAction)

		window:addTimer(1000,
				function()
					-- scan all servers waiting for the player
					appletManager:callService("discoverServers")

					-- we detect when the connect to the new server
					-- with notify_playerNew

					timeout = timeout + 1
					if timeout > CONNECT_TIMEOUT or player:hasConnectionFailed() then
						log:warn("Connection failure or Timeout, current count: ", timeout)
						cancelAction()
					end
				end)

		window._isChooseMusicSourceWindow = true

		self:tieAndShowWindow(window)
	end
end


-- connect player to server
function connectPlayerToServer(self, player, server)
	log:info('connectPlayerToServer() ', player, " ", server)
	-- if connecting to SqueezeNetwork, first check jive is linked
	if server:getPin() then
		appletManager:callService("enterPin", server, nil,
			       function()
				       self:connectPlayerToServer(player, server)
			       end)
		return
	end


	self:_showConnectToServer(player, server)

	-- we are now ready to connect to SqueezeCenter
	if not server:isSqueezeNetwork() then
		self:_doConnectPlayer(player, server)
		return
	end

	-- make sure the player is linked on SqueezeNetwork, this may return an
	-- error if the player can't be linked, for example it is linked to another
	-- account already.
	local cmd = { 'playerRegister', player:getUuid(), player:getId(), player:getName() }

	local playerRegisterSink = function(chunk, err)
		if chunk.error then
			self:_playerRegisterFailed(chunk.error)
		else
			self:_doConnectPlayer(player, server)
		end
	end

	server:userRequest(playerRegisterSink, nil, cmd)
end


function _doConnectPlayer(self, player, server)
	-- tell the player to move servers

	self.waitForConnect = {
		player = player,
		server = server
	}
	player:connectToServer(server)
end


function _playerRegisterFailed(self, error)
	local window = Window("error", self:string("SQUEEZEBOX_PROBLEM"), setupsqueezeboxTitleStyle)
	window:setAllowScreensaver(false)

	local textarea = Textarea("text", error)

	local menu = SimpleMenu("menu",
				{
					{
						text = self:string("SQUEEZEBOX_GO_BACK"),
						sound = "WINDOWHIDE",
						callback = function()
								   window:hide()
							   end

					},
				})


	window._isChooseMusicSourceWindow = true
	menu:setHeaderWidget(textarea)
	window:addWidget(menu)

	self:tieAndShowWindow(window)
end


function _cancelSelectServer(self, noHide)
	log:info("Cancelling Server Selection")

	self.ignoreServerConnected = true
	self.waitForConnect = nil
	self.playerConnectedCallback = nil
	if not noHide then
		self:hideConnectingToServer()
	end

end


-- failed to connect player to server
function _connectPlayerFailed(self, player, server)
	local window = Window("error", self:string("SQUEEZEBOX_PROBLEM"), setupsqueezeboxTitleStyle)
	window:setAllowScreensaver(false)

	local cancelAction = function()
		self:_cancelSelectServer()
		window:hide()

		return EVENT_CONSUME
	end

	local menu = SimpleMenu("menu",
				{
					{
						text = self:string("SQUEEZEBOX_TRY_AGAIN"),
						sound = "WINDOWSHOW",
						callback = function()
								   self:connectPlayerToServer(player, server)
								   window:hide()
							   end
					},
					{
						text = self:string("CHOOSE_OTHER_LIBRARY"),
						sound = "WINDOWSHOW",
						callback = function()
								   self:_showMusicSourceList()	
							   end
					},
				})

	menu:addActionListener("back", self, cancelAction)
	menu:addActionListener("go_home", self, cancelAction)

	local helpToken = "SQUEEZEBOX_PROBLEM_HELP"
	if server:isSqueezeNetwork() then
		helpToken = "SQUEEZEBOX_PROBLEM_HELP_GENERIC"
	end
	local help = Textarea("help_text", self:string(helpToken, server:getName()))

	menu:setHeaderWidget(help)
	window:addWidget(menu)
	window._isChooseMusicSourceWindow = true

	self:tieAndShowWindow(window)
end


-- failed to connect player to server
function _serverVersionError(self, server)
	local window = Window("error", self:string("SQUEEZECENTER_VERSION"), setupsqueezeboxTitleStyle)
	window:setAllowScreensaver(false)

	local help = Textarea("help_text", self:string("SQUEEZECENTER_VERSION_HELP", server:getName(), server:getVersion()))

	window:addWidget(help)

	-- timer to check if server has been upgraded
	window:addTimer(1000, function()
		if server:isCompatible() then
			self:selectServer(server)
			window:hide(Window.transitionPushLeft)
		end
	end)

	window._isChooseMusicSourceWindow = true

	self:tieAndShowWindow(window)
end


function _addRemoteServer(self, address)
	log:debug("SlimServerApplet:_addRemoteServerself: ", address)


	local list = self:getSettings().poll
	list[address] = address

	--make sure broadcast is still in the list
	list["255.255.255.255"] = "255.255.255.255",

	appletManager:callService("setPollList", list)
	self:getSettings().poll = list
	self:storeSettings()
end

function _removeRemoteServer(self, address)
	log:debug("SlimServerApplet:_removeRemoteServer: ", address)

	local list = self:getSettings().poll

	list[address] = nil

	self:getSettings().poll = list
	self:storeSettings()
end


function remoteServersWindow(self)
	local window = Window("text_list", self:string("REMOTE_LIBRARIES"))

	self._remoteServersWindow = window
	self:_refreshRemoteServersWindow()


	self:tieAndShowWindow(window)
end

function _refreshRemoteServersWindow(self)
	local window = self._remoteServersWindow
	if not window then
		return
	end

	--replace current menu, if any
	if self._remoteServersMenu then
		window:removeWidget(self._remoteServersMenu)
	end

	local menu = SimpleMenu("menu")
	self._remoteServersMenu = menu

	menu:addItem(
		{
			text = self:string("ADD_NEW_LIBRARY"),
			sound = "WINDOWSHOW",
			callback = function()
					   self:_inputRemoteServer()
				   end
		})

	for i,address in pairs(self:getSettings().poll) do
		if address ~= "255.255.255.255" then
			menu:addItem(
				{
					text = address,
					sound = "WINDOWSHOW",
					callback = function()
							   self:remoteServerDetailWindow(address)
						   end
				})
		end
	end

	window:addWidget(menu)
end

function remoteServerDetailWindow(self, address)
	local window = Window("text_list", self:string("REMOVE_LIBRARY"))

	local menu = SimpleMenu("menu",
				{
					{
						text = self:string("REMOVE_LIBRARY"),
						sound = "WINDOWSHOW",
						callback = function()
								   self:_removeRemoteServer(address)
								   self:_refreshRemoteServersWindow()
								   window:hide()
							   end,
					},
				})

	window:addWidget(menu)

	self:tieAndShowWindow(window)
	return window
end

function addRemoteServerSuccessWindow(self, address)
	local window = Window("text_list", self:string("LIBRARY_ADDED"))

	local menu = SimpleMenu("menu",
				{
					{
						text = self:string("CONNECT_TO_THIS_LIBRARY"),
						sound = "WINDOWSHOW",
						callback = function()
								--look first for existing server with same address to avoid having two server instances for same server
								local server = self:_createRemoteServer(address)

								local callback = function()
									jiveMain:goHome()
									jiveMain:openNodeById('_myMusic', true)
								end
								self:selectMusicSource(callback, nil, nil, server, nil, false, false)
							   end,
					},
				})

	window:addWidget(menu)

	self:tieAndShowWindow(window)
	return window
end

-- ip address input window
function _inputRemoteServer(self)
	local window = Window("text_list", self:string("ADD_NEW_LIBRARY"))

	local v = Textinput.ipAddressValue(nil)
	local input = Textinput("textinput", v,
				function(_, value)
					local address = value:getValue()
					self:_addRemoteServer(address)

					self:_refreshRemoteServersWindow()

					window:playSound("WINDOWSHOW")
					self:addRemoteServerSuccessWindow(address)
					window:hide(Window.transitionPushLeft)

					return true
				end
	)

	local keyboard = Keyboard("keyboard", "ip", input)
	local backspace = Keyboard.backspace()
        local group = Group('keyboard_textinput', { textinput = input, backspace = backspace } )

        window:addWidget(group)
	window:addWidget(keyboard)
	window:focusWidget(group)

	self:tieAndShowWindow(window)
	return window
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

