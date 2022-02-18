

--[[


disconnected: no connections to any servers, and no scanning.

searching: we are not connected to a player, in this state we connect
 to all SCs and SN to discover players.

connected: we are connected to a player, only a connection to our
 SC (or SN) is maintained. udp scanning is still performed in the
 background to update the SqueezeCenter list.

probing_player: we are connected to a player, but we must probe all SC/SN
 update our internal state. this is used for example in the choose
 player screen.

probing_server: we are connected to a player, but we must probe all SC/SN
 update our internal state. this is used for example in the choose
 server screen. we do not need to find players via udap or wireless scanning.

--]]


local pairs = pairs


-- stuff we use
local oo            = require("loop.simple")
local string        = require("string")
local table         = require("jive.utils.table")

local Applet        = require("jive.Applet")
local System        = require("jive.System")

local Framework     = require("jive.ui.Framework")
local Timer         = require("jive.ui.Timer")

local SocketUdp     = require("jive.net.SocketUdp")

local hasNetworking, Networking  = pcall(require, "jive.net.Networking")

local Player        = require("jive.slim.Player")
local SlimServer    = require("jive.slim.SlimServer")

local debug         = require("jive.utils.debug")

local jnt           = jnt
local jiveMain      = jiveMain
local appletManager = appletManager


module(..., Framework.constants)
oo.class(_M, Applet)


-- constants
local PORT    = 3483             -- port used to discover SqueezeCenters
local DISCOVERY_TIMEOUT = 120000 -- timeout (in milliseconds) before removing SqueezeCenters and Players
local DISCOVERY_PERIOD = 60000   -- discovery period
local SEARCHING_PERIOD = 10000   -- searching period



-- a ltn12 source that crafts a datagram suitable to discover SqueezeCenters
local function _slimDiscoverySource()
	return table.concat {
		"e",                                                           -- new discovery packet
		'IPAD', string.char(0x00),                                     -- request IP address of server
		'NAME', string.char(0x00),                                     -- request Name of server
		'JSON', string.char(0x00),                                     -- request JSONRPC port 
		'VERS', string.char(0x00),                                     -- request version 
		'UUID', string.char(0x00),                                     -- request uuid
		'JVID', string.char(0x06, 0x12, 0x34, 0x56, 0x78, 0x12, 0x34), -- My ID - FIXME mac of no use!
	}
end


-- processes a udp datagram,
local function _slimDiscoverySink(self, chunk, err)
	log:debug("_processUdp()")
	
	if not chunk or not chunk.data then
		log:error("bad udp packet?")
		return
	end

	if chunk.data:sub(1,1) ~= 'E' then
		return
	end

	local name, ip, port, version, uuid = nil, chunk.ip, nil, nil, nil

	local ptr = 2
	while (ptr <= chunk.data:len() - 5) do
		local t = chunk.data:sub(ptr, ptr + 3)
		local l = string.byte(chunk.data:sub(ptr + 4, ptr + 4))
		local v = chunk.data:sub(ptr + 5, ptr + 4 + l)
		ptr = ptr + 5 + l

		if t and l and v then
			if     t == 'NAME' then name = v
			elseif t == 'IPAD' then ip = v
			elseif t == 'JSON' then port = v
			elseif t == 'VERS' then version = v
			elseif t == 'UUID' then uuid = v
			end
		end
	end

	if name and ip and port then
		-- get instance for SqueezeCenter
		if not uuid then
			uuid = name
		end
		local server = SlimServer(jnt, uuid, name, version)

		-- update SqueezeCenter address
		self:_serverUpdateAddress(server, ip, port, name)
	end
end


function _serverUpdateAddress(self, server, ip, port, name)
	server:updateAddress(ip, port, name)

	if self.state == 'searching'
		or self.state == 'probing_player'
		or self.state == 'probing_server' then

		-- connect to server when searching or probing
		server:connect()
	end
end


-- wireless scan complete
function _scanComplete(self, scanTable)
	for ssid, entry in pairs(scanTable) do
		local playerId = Player:ssidIsSqueezebox(ssid)

		if playerId then
			local player = Player(jnt, playerId)
			player:updateSSID(ssid, entry.lastScan)
		end
	end
end


-- removes old servers
local function _squeezeCenterCleanup(self)
	local now = Framework:getTicks()
	local settings = self:getSettings()

	for i, server in SlimServer.iterate() do
		if not server:isConnected() and
			now - server:getLastSeen() > DISCOVERY_TIMEOUT then

			-- Bug 14972: Do not remove last known remote SC from music source list.
			--  This allows to select it as music source and send wake on lan.
			if (server.id == settings.serverUuid) and
			   (server.name == settings.serverName) and
			   (server.mac ~= nil) then
				log:debug("SC cleanup: Leave last known remote SC in list: ", server)
			else
				log:debug("SC cleanup: Removing server ", server)
				server:free()
			end
		end
	end
end


-- removes old unconfigured players
local function _playerCleanup(self)
	local now = Framework:getTicks()

	local currentPlayer = Player:getCurrentPlayer()

	for i, player in Player.iterate() do
		if not player:getSlimServer() and
			currentPlayer ~= player and
			now - player:getLastSeen() > DISCOVERY_TIMEOUT then
		
			log:debug("Removing player ", player)
			player:free(false)
		end
	end
end


-- init
-- Initializes the applet
function init(self, ...)
	-- Get "poll" list settings from the "ChooseMusicSource" applet.
	local cms = appletManager:loadApplet("ChooseMusicSource")

	self.poll = cms["getSettings"](cms)["poll"]

	-- slim discovery socket
	self.socket = SocketUdp(jnt,
		function(...)
			_slimDiscoverySink(self, ...)
		end)

	-- wireless discovery
	if hasNetworking then
		self.wireless = Networking:wirelessInterface(jnt)
	end

	-- discovery timer
	self.timer = Timer(DISCOVERY_PERIOD,
			  function() self:_discover() end)

	-- initial state
	self.state = 'searching'

	-- start discovering
	-- FIXME we need a slight delay here to allow the settings to be loaded
	-- really the settings should be loaded before the applets start.
	self.timer:restart(2000)

	-- subscribe to the jnt so that we get network/server notifications
	jnt:subscribe(self)

	return self
end


function _discover(self)
	-- Broadcast SqueezeCenter discovery
	for i, address in pairs(self.poll) do
		log:debug("sending slim discovery to ", address)
		self.socket:send(_slimDiscoverySource, address, PORT)
	end

	-- Discover players via wireless scanning

	if self.state == 'probing_player' then
		if self.wireless then
			self.wireless:scan(function(scanTable)
				_scanComplete(self, scanTable)
			end)
		end
	end


	-- Special case Squeezenetwork
	--[[
	if System:getUUID() then
		squeezenetwork = SlimServer(jnt, "mysqueezebox.com", "mysqueezebox.com")
		self:_serverUpdateAddress(squeezenetwork, jnt:getSNHostname(), 9000, "mysqueezebox.com")
	end
	--]]

	-- Remove SqueezeCenters that have not been seen for a while
	_squeezeCenterCleanup(self)

	-- Remove unconfigured Players that have not been seen for a while
	_playerCleanup(self)


	if self.state == 'probing_player' or self.state == 'probing_server' and
		Framework:getTicks() > self.probeUntil then

		local currentPlayer = Player:getCurrentPlayer()

		if currentPlayer and currentPlayer:isConnected() then
			self:_setState('connected')
		else
			self:_setState('searching')
		end
	end

	if log:isDebug() then
		self:_debug()
	end

	if self.state == 'connected' then
		self.timer:restart(DISCOVERY_PERIOD)
	else
		self.timer:restart(SEARCHING_PERIOD)
	end
end


function _setState(self, state)
	if self.state == state then
		self.timer:restart(0)
		return -- no change
	end

	-- restart discovery if we were disconnected
	if self.state == 'disconnected' then
		self.timer:restart(0)
	end

	self.state = state

	if state == 'disconnected' then
		self.timer:stop()
		self:_disconnect()

	elseif state == 'searching' then
		self.timer:restart(0)
		self:_connect()

	elseif state == 'connected' then
		self:_idleDisconnect()

	elseif state == 'probing_player' or state == 'probing_server' then
		self.probeUntil = Framework:getTicks() + 60000
		self.timer:restart(0)
		self:_connect()

	else
		log:error("unknown state=", state)
	end

	if log:isDebug() then
		self:_debug()
	end
end


function _debug(self)
	local now = Framework:getTicks()

	local currentPlayer = Player:getCurrentPlayer()

	log:info("----")
	log:info("State: ", self.state)
	log:info("CurrentPlayer: ", currentPlayer)
	log:info("CurrentServer: ", SlimServer:getCurrentServer())
	log:info("Servers:")
	for i, server in SlimServer.iterate() do
		log:info("\t", server:getName(), " [", server:getIpPort(), "] connected=", server:isConnected(), " timeout=", DISCOVERY_TIMEOUT - (now - server:getLastSeen()), " version=", server:getVersion())
	end
	log:info("Players:")
	for i, player in Player.iterate() do
		log:info("\t", player:getName(), " [", player:getId(), "] uuid=", player:getUuid() ," server=", player:getSlimServer(), " connected=", player:isConnected(), " available=", player:isAvailable(), " timeout=", DISCOVERY_TIMEOUT - (now - player:getLastSeen()))
	end
	log:info("----")
end


-- connect to all servers
function _connect(self)
	for i, server in SlimServer:iterate() do
		server:connect()
	end
end


-- disconnect from all servers
function _disconnect(self)
	for i, server in SlimServer:iterate() do
		server:disconnect()
	end
end


-- disconnect from idle servers
function _idleDisconnect(self)
	local currentServer = SlimServer:getCurrentServer()

	for i, server in SlimServer:iterate() do
		if server ~= currentServer then
			--allow up to 30 seconds for any remaining server requests to complete
			server:setIdleTimeout(30)
		else
			server:setIdleTimeout(0)
			server:connect()
		end
	end
end


-- restart discovery if the player is disconnect from SqueezeCenter
function notify_playerDisconnected(self, player)
	log:debug("playerDisconnected")

	if Player:getCurrentPlayer() ~= player then
		return
	end

	-- start discovery looking for the player
	self:_setState('searching')
end


-- stop discovery if the player is reconnects
function notify_playerConnected(self, player)
	log:debug("playerConnected")

	local currentPlayer = Player:getCurrentPlayer()
	if currentPlayer ~= player then
		return
	end

	log:info("connected ", player:getName())

	-- stop discovery, we have the player
	self:_setState('connected')

	-- refresh the current player, this means that other applets don't
	-- need to watch the player connection notifications
	Player:setCurrentPlayer(currentPlayer)
end


-- restart discovery if SqueezeCenter disconnects
function notify_serverDisconnected(self, slimserver)
	log:debug("serverDisconnected ", slimserver)

	local currentPlayer = Player:getCurrentPlayer()
	if not currentPlayer or currentPlayer:getSlimServer() ~= slimserver then
		return
	end

	-- start discovery looking for the player
	if self.state == 'connected' then
		self:_setState('searching')
	end
end


-- stop discovery if SqueezeCenter reconnects
function notify_serverConnected(self, slimserver)
	log:debug("serverConnected")

	local currentPlayer = Player:getCurrentPlayer()
	if not currentPlayer or currentPlayer:getSlimServer() ~= slimserver then
		return
	end

	-- stop discovery, we have the player
	self:_setState('connected')
end


-- restart discovery on new network connection
function notify_networkConnected(self)
	log:debug("networkConnected")

	if self.state == 'disconnected' then
		return
	end

	if self.state == 'connected' then
		-- force re-connection to the current player
		local currentPlayer = Player:getCurrentPlayer()
		currentPlayer:getSlimServer():disconnect()
		currentPlayer:getSlimServer():connect()
	else
		-- force re-connection to all servers
		self:_disconnect()
		self:_connect()
	end
end

function notify_playerPower(self,  player, power)
	if Player:getCurrentPlayer() == player and System:hasSoftPower() then
		--only work for devices that have a dedicated power button
		log:info("notify_playerPower: ", power)
		if power then
			jiveMain:setSoftPowerState("on", true)
		else
			jiveMain:setSoftPowerState("off", true)
		end
	end
end

function notify_playerCurrent(self, player)
	local settings = self:getSettings()
	local saveSettings = false

	local playerId = player and player:getId() or false

	if settings.playerId ~= playerId then
		-- update player
		settings.playerId = playerId
		settings.playerInit = player and player:getInit()

		-- legacy setting
		settings.currentPlayer = playerId

		saveSettings = true
	end

	local server = player and player:getSlimServer() or false
	local ipChanged
	local macChanged = false
	if server then
		local serverIp = server:getInit() and server:getInit().ip or nil
		local settingsIp = settings.serverInit and settings.serverInit.ip or nil
		ipChanged = serverIp ~= settingsIp

		local serverMac = server:getInit() and server:getInit().mac or nil
		local settingsMac = settings.serverInit and settings.serverInit.mac or nil
		macChanged = serverMac ~= settingsMac

	end

	if server and
		( settings.squeezeNetwork ~= server:isSqueezeNetwork()
		  or ipChanged or macChanged
		  or settings.serverName ~= server:getName() ) then
		settings.squeezeNetwork = server:isSqueezeNetwork()

		-- remember server if it's not SN
		if not settings.squeezeNetwork then
			settings.serverName = server:getName()
			settings.serverUuid = server:getId()
			settings.serverInit = server:getInit()
		end

		saveSettings = true
	end

	if saveSettings then
		self:storeSettings()
	end

	-- restart discovery when we have no player
	if player and player:isConnected() then
		self:_setState('connected')
	else
		self:_setState('searching')
	end

end

-- store the new player name if the local player's name has been changed
function notify_playerNewName(self, player, playerName)
	if Player:getCurrentPlayer() ~= player then
		return
	end
	
	log:debug("playerNewName: setting new name for the local player")

	local settings = self:getSettings()
	settings.playerInit = {
		name  = playerName,
		model = settings.playerInit.model
	}
	self:storeSettings()
end


--todo:uses serverName but should use uuid when that comes online
--service method
function getInitialSlimServer(self)
	local serverName = self:getSettings().serverName
	if self:getSettings().squeezeNetwork then
		serverName = "mysqueezebox.com"
	end

	if serverName then
		for i, server in SlimServer:iterate() do
			if server:getName() == serverName then
				log:debug("found initial server: ", server)

				return server
			end
		end
	end
	log:debug("could not find initial server: ", server)

	return nil
end


function getCurrentPlayer(self)
	return Player:getCurrentPlayer()
end


function setCurrentPlayer(self, player)
	log:info("selected ", player and player:getName() or nil)

	Player:setCurrentPlayer(player)
end


function discoverPlayers(self)
	self:_setState("probing_player")
end


function discoverServers(self)
	self:_setState("probing_server")
end


function connectPlayer(self)
	local player = Player:getCurrentPlayer()

	if currentPlayer and currentPlayer:isConnected() then
		self:_setState("connected")
	else
		self:_setState("searching")
	end
end


function disconnectPlayer(self)
	self:_setState("disconnected")

	local player = Player:getCurrentPlayer()
	if player then
		player:disconnectFromServer()
	end
end


function iteratePlayers(self)
	return Player:iterate()
end


function iterateSqueezeCenters(self)
	return SlimServer:iterate()
end


function countPlayers(self)
	local count = 0
	for i, player in Player:iterate() do
		count = count + 1
	end

	return count
end


function getPollList(self)
	return self.poll
end


function setPollList(self, poll)
	self.poll = poll

	-- get going with the new poll list
	self:discoverPlayers()
end



--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

