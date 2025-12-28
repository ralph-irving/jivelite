
--[[
=head1 NAME

jive.slim.SlimServer - SlimServer object

=head1 DESCRIPTION

Represents and interfaces with a real SlimServer on the network.

=head1 SYNOPSIS

 -- Create a SlimServer
 local myServer = SlimServer(jnt, '192.168.1.1', 'Raoul', 'Raoul')

 -- Allow some time here for newtork IO to occur

 -- Get the SlimServer version
 local myServerVersion = myServer:getVersion()

Notifications:

 serverNew (performed by SlimServers)
 serverDelete (performed by SlimServers)
 serverConnected(self)
 serverDisconnected(self, numUserRequests)

=head1 FUNCTIONS

=cut
--]]

-- our stuff
local _assert, assert, tostring, type, tonumber = _assert, assert, tostring, type, tonumber
local pairs, ipairs, require, setmetatable = pairs, ipairs, require, setmetatable

local os          = require("os")
local table       = require("jive.utils.table")
local string      = require("jive.utils.string")

local oo          = require("loop.base")

local System      = require("jive.System")

local Comet       = require("jive.net.Comet")
local HttpPool    = require("jive.net.HttpPool")
local Surface     = require("jive.ui.Surface")
local RequestHttp = require("jive.net.RequestHttp")
local SocketHttp  = require("jive.net.SocketHttp")
local WakeOnLan   = require("jive.net.WakeOnLan")

local Task        = require("jive.ui.Task")
local Framework   = require("jive.ui.Framework")

local ArtworkCache = require("jive.slim.ArtworkCache")

local debug       = require("jive.utils.debug")
local log         = require("jive.utils.log").logger("squeezebox.server")
local logcache    = require("jive.utils.log").logger("squeezebox.server.cache")

local JIVE_VERSION = jive.JIVE_VERSION
local jnt          = jnt

local SERVER_DISCONNECT_LAG_TIME = 10000

-- jive.slim.SlimServer is a base class
module(..., oo.class)


-- we must load this after the module declartion to dependancy loops
local Player      = require("jive.slim.Player")
local LocalPlayer = require("jive.slim.LocalPlayer")


-- minimum support server version, can be set per device
local minimumVersion = "7.4"

-- oldest firmware version which is supposed to be compatible with this firmware
-- use this value to prevent downgrading firmwares unless really necessary
-- XXXX - to be updated with real version/revision
local MINIMUM_COMPATIBLE_FIRMWARE = "7.6 r0"

-- list of servers index by id. this weak table is used to enforce
-- object equality with the server name.
local serverIds = {}
setmetatable(serverIds, { __mode = 'v' })

-- list of servers, that are active
local serverList = {}

-- current server
local currentServer = nil

-- credential list for http auth
local credentials = {}

local lastServerSwitchT = nil

--holds the server for which a local connection request has been made. Will be nilled out when SERVER_DISCONNECT_LAG_TIME has passed.
local locallyRequestedServers = {}

-- class function to iterate over all SqueezeCenters
function iterate(class)
	return pairs(serverList)
end


--class method
function getServerByAddress(self, address)
	local serverByAddress

	for id, server in self:iterate() do
		if server.ip == address then
			serverByAddress = server
			break
		end
	end
	return serverByAddress
end


-- class method to return current server
function getCurrentServer(class)
	return currentServer
end


-- class method to add the locally requested server (mihgt be more than one - one for local player and one for remote player, for instance)
function addLocallyRequestedServer(class, server)
	table.insert(locallyRequestedServers, server)
end


-- class method to set the current server
function setCurrentServer(class, server)
	if lastCurrentServer and ( (server and lastCurrentServer ~= server) or (not server and lastCurrentServer) ) then
		log:debug("setting lastServerSwitchT for server: ", server)

		lastServerSwitchT = Framework:getTicks()
	end

	lastCurrentServer = currentServer

	currentServer = server

	-- is the current server still active, it not clean up?
	if lastCurrentServer and lastCurrentServer.lastSeen == 0 then
		lastCurrentServer:free()
	end
end


-- _getSink
-- returns a sink
local function _getSink(self, name)

	local func = self[name]
	if func and type(func) == "function" then

		return function(chunk, err)
			
			if err then
				log:error(self, ": ", err, " during ", name)
			else
				func(self, chunk)
			end
		end

	else
		log:error(self, ": no function called [", name .."]")
	end
end


-- _serverstatusSink
-- processes the result of the serverstatus call
function _serverstatusSink(self, event, err)
	log:debug(self, ":_serverstatusSink()")

	local data = event.data

	-- check we have a result 
	if not data then
		log:error(self, ": chunk with no data ??!")
		log:error(event)
		return
	end

	-- remember players from server, avoid possibly inaccurate player information that can happen in race conditions when SlimProto socket disconnection is not
	 -- registered yet when the serverstatus response occurs
	local now = Framework:getTicks()
	local serverPlayers = nil
	if lastServerSwitchT and lastServerSwitchT + SERVER_DISCONNECT_LAG_TIME < now then
		--after SERVER_DISCONNECT_LAG_TIME, no need to consider locallyRequestedServers in the bad server player data check
		locallyRequestedServers = {}
	end
	if data.players_loop then
		serverPlayers = {}

		for _, player_info in ipairs(data.players_loop) do
			if ((#locallyRequestedServers > 0 and not table.contains(locallyRequestedServers, self)) or (#locallyRequestedServers == 0 and self ~= currentServer))
			  and tonumber(player_info.connected) == 1
			  and Player:getCurrentPlayer() and player_info.playerid == Player:getCurrentPlayer().id
			  and lastServerSwitchT and lastServerSwitchT + SERVER_DISCONNECT_LAG_TIME > now then
				--SlimProto disconnects can take several seconds to "take", during which time a disconnected player might still be in the serverstatus list
				log:info("Ignoring potentially inaccurate player data for current player in serverstatus from other servers (excluding any locally requested server) until SERVER_DISCONNECT_LAG_TIME passes: server:", self)
			else
				table.insert(serverPlayers, player_info)
			end
		end
	end
	
	data.players_loop = nil

	-- remember our state
	local selfState = self.state
	
	-- update in one shot
	self.state = data
	self.lastSeen = Framework:getTicks()
	
	-- manage rescan
	-- use tostring to handle nil case (in either server of self data)
	if tostring(self.state["rescan"]) ~= tostring(selfState["rescan"]) then
		-- rescan has changed
		if not self.state["rescan"] then
			-- rescanning
			self.jnt:notify('serverRescanning', self)
		else
			self.jnt:notify('serverRescanDone', self)
		end
	end
	
	-- update players
	
	-- copy all players we know about
	local selfPlayers = {}
	local player
	
	for k,v in pairs(self.players) do
		selfPlayers[k] = k
	end

	local pin = false

	if tonumber(data["player count"]) > 0 then

		for i, player_info in ipairs(serverPlayers) do

			local playerId = player_info.playerid

			if player_info.pin then
				pin = player_info.pin
			end

			-- remove the player from our list since it is reported by the server
			selfPlayers[playerId] = nil
	
			-- create new players
			if not self.players[playerId] then
				if playerId == System:getMacAddress() then
					self.players[playerId] = LocalPlayer(self.jnt, playerId)
				else
					self.players[playerId] = Player(self.jnt, playerId)
				end
			end
			
			local player = self.players[playerId]

			-- update player state

			local useSequenceNumber = false
			local isSequenceNumberInSync = true
			if player:isLocal() and player_info.seq_no then
				useSequenceNumber = true
				if not player:isSequenceNumberInSync(tonumber(player_info.seq_no)) then
					isSequenceNumberInSync = false
				end
			end
			
			-- Bug 16295: ignore serverStatus updates with information about the current player
			-- because serverStatus from SN can contain out-of-date information (cached query);
			-- just rely on (player)status notifications for that information,
			-- unless this status indicates a change of server (possibly from none) for the player
			-- or the connected status has changed (should be reliable).
			--
			-- It is important that these tests allow the first serverstatus for the current player
			-- to be used because otherwise the correct notifications are not issued and various
			-- necessary initialization functions are not run, including those that subscribe to
			-- (player)status notifications.
			
			if Player:getCurrentPlayer() ~= player
				or player:getSlimServer() ~= self
				or player:isConnected() ~= (tonumber(player_info.connected) == 1)
			then
				player:updatePlayerInfo(self, player_info, useSequenceNumber, isSequenceNumberInSync)
			end
		end
	else
		log:debug(self, ": has no players!")
	end

	--pin check here also used by non SN to know when first serverstatus for new server is complete
	if self.pin ~= pin then
		self.pin = pin
		self.jnt:notify('serverLinked', self)
	end

	-- any players still in the list are gone...
	for k,v in pairs(selfPlayers) do
		player = self.players[k]
		-- wave player bye bye
		player:free(self)
		self.players[k] = nil
	end
	
end


function _upgradeSink(self, chunk, err)
	local url

	if err then
		log:warn("Error in upgrade sink: ", err)
		return
	end

	-- store firmware upgrade url
	-- Bug 6828, use a relative URL from SC to handle dual-homed servers
	if chunk.data.relativeFirmwareUrl then
		url = 'http://' .. self.ip .. ':' .. self.port .. chunk.data.relativeFirmwareUrl
	elseif chunk.data.firmwareUrl then
		url = chunk.data.firmwareUrl
	end

	local oldUpgradeUrl = self.upgradeUrl
	local oldUpgradeForce = self.upgradeForce

	self.upgradeUrl = url
	self.upgradeForce = false

	--[[
	if url then
		local machine = System:getMachine()
		
		local versionNew, revisionNew = string.match(url, "\/" .. machine .. "\_([^_]+)_r([^_]+)\.bin")
		local versionOld, revisionOld = string.match(JIVE_VERSION, "(.+) r(.+)")
		local versionOldest, revisionOldest = string.match(MINIMUM_COMPATIBLE_FIRMWARE, "(.+) r(.+)")

		log:debug("old version:  ", versionOld,  ", new version:  ", versionNew)
		log:debug("old revision: ", revisionOld, ", new revision: ", revisionNew)
		
		if (not versionNew) or (not revisionNew) then
			log:info("missing firmware version/revision - ignoring")

		elseif versionOld == versionNew and revisionOld == revisionNew then
			log:info("we're up to date - no firmware change")

		elseif self:isMoreRecent(versionOld, versionNew) then
			log:info("we don't downgrade, even if lower versioned firmware is of more recent revision - ignoring")

		elseif self:isMoreRecent(versionNew, versionOld) or revisionNew > revisionOld then
			log:info("there's a new firmware available - update!")
			self.upgradeForce = true

		elseif self:isMoreRecent(versionOldest, versionNew) or revisionOldest > revisionNew then
			log:info("firmware offered is older than oldest known compatible - downgrade")
			self.upgradeForce = true
		end
	end
	--]]

	log:info(self.name, " firmware=", self.upgradeUrl, " force=", self.upgradeForce)

	if oldUpgradeUrl ~= self.upgradeUrl
		or oldUpgradeForce ~= self.upgradeForce then
		self.jnt:notify('firmwareAvailable', self)
	end
end


-- package private method to delete a player
function _deletePlayer(self, player)
	self.players[player:getId()] = nil
end


function _addPlayer(self, player)
	self.players[player:getId()] = player
end


-- can be called as a object or class method
function setCredentials(self, cred, id)
	if not id then
		-- object method
		id = self:getId()

		self.authFailureCount = 0

		SocketHttp:setCredentials({
			ipport = { self:getIpPort() },
			realm = cred.realm,
			username = cred.username,
			password = cred.password,
		})

		-- force re-connection
		self:reconnect()
	end

	credentials[id] = cred
end


--[[

=head2 jive.slim.SlimServer(jnt, ip, name, version)

Create a SlimServer object at IP address I<ip> with name I<name>. Once created, the
object will immediately connect to slimserver to discover players and other attributes
of the server.

=cut
--]]
function __init(self, jnt, id, name, version)
	-- Only create one server object per server. This avoids duplicates
	-- following a server disconnect.

	if serverIds[id] then
		return serverIds[id]
	end

	log:debug("SlimServer:__init(", name, ")", " ", id)

	local obj = oo.rawnew(self, {
		id = id,
		name = name,
		jnt = jnt,

		-- connection stuff
		lastSeen = 0,
		ip = false,
		port = false,

		-- data from SqueezeCenter
		state = {},

		-- firmware upgrade url
		upgradeUrl = false,
		upgradeForce = false,

		-- players
		players = {},

		-- our comet connection, initially not connected
		comet = Comet(jnt, name),

		-- are we connected to the server?
		-- 'disconnected' = not connected
		-- 'connecting' = trying to connect
		-- 'connected' = connected
		netstate = 'disconnected',

		-- number of user activated requests
		userRequests = {},

		-- artwork state below here

		-- artwork http pool, initially not connected
		artworkPool = false,

		-- artwork cache: Weak table storing a surface by iconId
		artworkCache = ArtworkCache(),

		-- Icons waiting for the given iconId
		artworkThumbIcons = {},

		-- queue of artwork to fetch
		artworkFetchQueue = {},
		artworkFetchCount = 0,

		-- loaded images
		imageCache = {},
	})

	obj.state.version = version

	-- subscribe to server status, max 50 players every 60 seconds.
	-- FIXME: what if the server has more than 50 players?
	obj.comet:aggressiveReconnect(true)
	obj.comet:subscribe('/slim/serverstatus',
		_getSink(obj, '_serverstatusSink'),
		nil,
		{ 'serverstatus', 0, 50, 'subscribe:60' }
	)

	local inSetup = jnt.inSetupHack and 1 or 0

	local machine = System:getMachine()
	-- this is not relevant to desktop SP
	--[[
	if machine ~= 'squeezeplay' then
		obj.comet:subscribe('/slim/firmwarestatus',
			_getSink(obj, '_upgradeSink'),
			nil,
			{
				'firmwareupgrade',
				'firmwareVersion:' .. JIVE_VERSION,
				'inSetup:' .. tostring(inSetup),
				'machine:' .. machine,
				'subscribe:0'
			}
		)
	end
	--]]

	setmetatable(obj.imageCache, { __mode = "kv" })

	serverIds[obj.id] = obj

	-- subscribe to comet events
	jnt:subscribe(obj)

	-- task to fetch artwork while browsing
	obj.artworkFetchTask = Task("artwork", obj, processArtworkQueue)
	
	return obj
end


-- Update server on start up
function updateInit(self, init)
	if serverList[self.id] then
		-- already initialized
		return
	end

	self.ip = init.ip
	self.mac = init.mac

	self.lastSeen = 0 -- don't timeout
	serverList[self.id] = self
end


-- State needed for updateInit
function getInit(self)
	return {
		ip = self.ip,
		mac = self.mac,
	}
end


--[[

=head2 jive.slim.SlimServer:updateAddress(ip, port, name)

Called to update (or initially set) the ip address and port for SqueezeCenter

=cut
--]]
function updateAddress(self, ip, port, name)
	if self.ip ~= ip or self.port ~= port or self.name ~= name then
		log:debug(self, ": address set to ", ip , ":", port, " netstate=", self.netstate, " name: ", name)

		local oldstate = self.netstate

		-- close old connections
		self:disconnect()

		-- open new comet connection
		self.ip = ip
		self.port = port
		if name then
			self.name = name
		end

		-- http authentication
		local cred = credentials[self.id]
		if cred then
			self.authFailureCount = 0
			SocketHttp:setCredentials({
				ipport = { ip, port },
				realm = cred.realm,
				username = cred.username,
				password = cred.password,
			})
		end

		if not self:isSqueezeNetwork() then
			-- artwork http pool
			self.artworkPool = HttpPool(self.jnt, self.name, ip, port, 2, 1, Task.PRIORITY_LOW)
		end

		-- comet
		self.comet:setEndpoint(ip, port, '/cometd')

		-- reconnect, if we were already connected
		if oldstate ~= 'disconnected' then
			self:connect()
		end
	end

	local oldLastSeen = self.lastSeen
	self.lastSeen = Framework:getTicks()

	-- server is now active
	if oldLastSeen == 0  then
		serverList[self.id] = self
		self.jnt:notify('serverNew', self)
	end
end


--[[

=head2 jive.slim.SlimServer:free()

Deletes a SlimServer object, frees memory and closes connections with the server.

=cut
--]]
function free(self)
	log:debug(self, ":free")

	-- clear cache
	self.artworkCache:free()
	self.artworkThumbIcons = {}

	-- server is gone
	self.lastSeen = 0
	self.jnt:notify("serverDelete", self)

	if self == currentServer then
		-- dont' delete state if this is the current server
		return
	end

	-- close connections
	self:disconnect()

	-- delete players
	for id, player in pairs(self.players) do
		player:free(self)
	end
	self.players = {}

	self.upgradeUrl = false
	self.upgradeForce = false

	self.appParameters = {}

	-- server is no longer active
	serverList[self.id] = nil

	-- don't remove the server from serverIds, the weak value means
	-- this instance will be deleted when it is no longer referenced
	-- by any other code
end


function wakeOnLan(self)
	if not self.mac or self:isSqueezeNetwork() then
		log:warn('wakeOnLan(): SKIPPING WOL, self.mac: ', self.mac, ', self:isSqueezeNetwork(): ', self:isSqueezeNetwork())
		return
	end

	log:info("wakeOnLan(): Sending WOL to ", self.mac)

	-- send WOL packet to SqueezeCenter
	local wol = WakeOnLan(self.jnt)
	wol:wakeOnLan(self.mac)
end


-- connect to SqueezeCenter
function connect(self)
	if self.netstate == 'connected' or self.netstate == 'connecting' then
		return
	end

	if self.lastSeen == 0 then
		log:debug("Server ip address is not known")
		return
	end

	log:debug(self, ":connect")

	assert(self.comet)

	self.authFailureCount = 0

	if not self:isSqueezeNetwork() then
		assert(self.artworkPool)
	end

	self.netstate = 'connecting'

	-- artwork pool connects on demand
	self.comet:connect()
end


function _disconnectServerInternals(self)

	self.netstate = 'disconnected'

	if not self:isSqueezeNetwork() then
		self.artworkPool:close()
	end
	
	self.comet:disconnect()

end


-- force disconnect to SqueezeCenter
function disconnect(self)
	if self.netstate == 'disconnected' then
		return
	end

	log:debug(self, ":disconnect")

	self:_disconnectServerInternals()
end


-- force reconnection to SqueezeCenter
function reconnect(self)
	log:debug(self, ":reconnect")

	self:disconnect()
	self:connect()
end


-- if >0, disconnect from server idleTimeout seconds after the most recent request
function setIdleTimeout(self, idleTimeout)
	self.comet:setIdleTimeout(idleTimeout)
end


-- comet has connected to SC
function notify_cometConnected(self, comet)
	if self.comet ~= comet then
		return
	end

	log:info("connected ", self.name)

	self.netstate = 'connected'
	self.jnt:notify('serverConnected', self)

	self.authFailureCount = 0

	-- auto discovery SqueezeCenter's mac address
 	self.jnt:arp(self.ip, function(chunk, err)
		if err then
			log:debug("arp: " .. err)
		else
			log:info('self.mac being set to---->', self.mac)
			self.mac = chunk
		end
	end)
end

-- comet is disconnected from SC
function notify_cometDisconnected(self, comet, idleTimeoutTriggered)
	if self.comet ~= comet then
		return
	end

	log:info("disconnected ", self.name, " idleTimeoutTriggered: ", idleTimeoutTriggered)

	if idleTimeoutTriggered then
		log:info("idle disconnected ", self.name)
		--disconnect self - normally self triggers a clean comet disconnect during self:disconnect, except in the idleDisconnect case
		self:_disconnectServerInternals()
	else
		if self.netstate == 'connected' then
			log:debug(self, " disconnected")

			self.netstate = 'connecting'
		end
	end

	-- always send the notification
	self.jnt:notify('serverDisconnected', self, #self.userRequests)
end

-- comet http error
function notify_cometHttpError(self, comet, cometRequest)
	if cometRequest:t_getResponseStatus() == 401 then

		local authenticate = cometRequest:t_getResponseHeader("WWW-Authenticate")

		self.realm = string.match(authenticate, 'Basic realm="(.*)"')
		if not self:isConnected() then
			if not self.authFailureCount then
				self.authFailureCount = 0
			end
			if self.authFailureCount > 0 then
				--don't count first auth error as a failure, to allow challenge to complete
				log:info("failed auth. Count: ", self.authFailureCount, " server: ", self, " state: ", self.netstate)
				self.jnt:notify('serverAuthFailed', self, self.authFailureCount)

			end
			self.authFailureCount = self.authFailureCount + 1
		end
	end
end


-- Always false now since SqueezeNetwork is no more
function isSqueezeNetwork(self)
	return false
end


--[[

=head2 jive.slim.SlimServer:getPin()

Returns the PIN for SqueezeNetwork, if it needs to be registered. Returns
nil if the state is unknown, or false if the player is already linked.

=cut
--]]
function getPin(self)
	return self.pin
end


--todo clean up usage of pin for linked and isSpRegisteredWithSn
-- If the SN comet connection returns a client id starting with "1x", SP is not registered with it.
function isSpRegisteredWithSn(self)
	if not self.comet then
		log:info("not registered: no comet")
		return nil
	end
	if not self.comet.clientId then
		log:info("not registered: no clientId")
		return nil
	end

	if self.comet.clientId and  string.sub(self.comet.clientId, 1, 2) == "1X" then
		log:debug("not registered: ", self.comet.clientId)

		return false
	end

	log:debug("registered: ", self.comet.clientId)

	return true
end


--[[

=head2 jive.slim.SlimServer:linked(pin)

Called once the server or player are linked on SqueezeNetwork.

=cut
--]]
function linked(self, pin)
	if self.pin == pin then
		self.pin = false
	end

	for id, player in pairs(self.players) do
		if player:getPin() == pin then
			player:clearPin()
		end
	end
end


-- convert artwork to a resized image
local function _loadArtworkImage(self, cacheKey, chunk, size)
	-- create a surface
	local image = Surface:loadImageData(chunk, #chunk)

	local w, h = image:getSize()

	-- don't display empty artwork
	if w == 0 or h == 0 then
		self.imageCache[cacheKey] = true
		return nil
	end

	-- parse size specification for width and height if in format <W>x<H>
	local sizeW = tonumber(string.match(size, "(%d+)x%d+") or size)
	local sizeH = tonumber(string.match(size, "%d+x(%d+)") or size)

	-- Resize image
	-- Note this allows for artwork to be resized to a larger
	-- size than the original.  This is intentional so smaller cover
	-- art will still fill the space properly on the Now Playing screen
	if w ~= sizeW and h ~= sizeH then
		local tmp = image:resize(sizeW, sizeH, true)
		image:release()
		image = tmp
		if logcache:isDebug() then
			local wnew, hnew = image:getSize()
			logcache:debug("Resized artwork from ", w, "x", h, " to ", wnew, "x", hnew)
		end
	end

	-- cache image
	self.imageCache[cacheKey] = image

	return image
end


-- _getArworkThumbSink
-- returns a sink for artwork so we can cache it as Surface before sending it forward
local function _getArtworkThumbSink(self, cacheKey, size, url)

	assert(size)
	
	return function(chunk, err)

		if err or chunk then
			-- allow more artwork to be fetched
			self.artworkFetchCount = self.artworkFetchCount - 1
			self.artworkFetchTask:addTask()
		end

		-- on error, print something...
		if err then
			logcache:error("_getArtworkThumbSink(", url, ") error: ", err)
		end
		-- if we have data
		if chunk then
			logcache:debug("_getArtworkThumbSink(", url, ", ", size, ")")

			-- store the compressed artwork in the cache
			self.artworkCache:set(cacheKey, chunk)

			local image = _loadArtworkImage(self, cacheKey, chunk, size)

			-- set it to all icons waiting for it
			local icons = self.artworkThumbIcons
			for icon, key in pairs(icons) do
				if key == cacheKey then
					icon:setValue(image)
					icons[icon] = nil
				end
			end
		end
	end
end


function processArtworkQueue(self)
	while true do
		while self.artworkFetchCount < 4 and #self.artworkFetchQueue > 0 do
			-- remove tail entry
			local entry = table.remove(self.artworkFetchQueue)

			--log:debug("ARTWORK ID=", entry.key)
			local req = RequestHttp(
				_getArtworkThumbSink(self, entry.key, entry.size, entry.url),
				'GET',
				entry.url
			)

			self.artworkFetchCount = self.artworkFetchCount + 1

			if string.find(entry.url, "^http") then
				-- image from remote server

				-- XXXX manage pool of connections to remote server
				local uri  = req:getURI()
				local http = SocketHttp(self.jnt, uri.host, uri.port, uri.host)
 
				http:fetch(req)
			elseif self.artworkPool then
				-- slimserver icon id
				self.artworkPool:queue(req)
			else
				log:error("Server ", self.name, " cannot handle artwork for ", entry.url)
				self.artworkFetchCount = self.artworkFetchCount - 1
			end

			-- try again
			Task:yield(true)
		end

		Task:yield(false)
	end
end



--[[

=head2 jive.slim.SlimServer:artworkThumbCached(iconId, size, imgFormat)

Returns true if artwork for iconId and size are in the cache.  This may be used to decide
whether to display the thumb straight away or wait before fetching it.

=cut

--]]

function artworkThumbCached(self, iconId, size, imgFormat)
	local cacheKey = iconId .. "@" .. size .. "/" .. (imgFormat or '')	
	if self.artworkCache:get(cacheKey) then
		return true
	else
		return false
	end
end


--[[

=head2 jive.slim.SlimServer:cancelArtworkThumb(icon)

Cancel loading the artwork for icon.

=cut
--]]
function cancelArtwork(self, icon)
	-- prevent artwork being display when it has been loaded
	if icon then
		if icon:getImage() then
			--only set nil if not already nil
			icon:setValue(nil)
		end
		self.artworkThumbIcons[icon] = nil
	end
end


--[[

=head2 jive.slim.SlimServer:cancelArtworkThumb(icon)

Cancel loading the artwork for icon.

=cut
--]]
function cancelAllArtwork(self, icon)

	for i, entry in ipairs(self.artworkFetchQueue) do
		local cacheKey = entry.key

		-- release cache marker
		self.artworkCache:set(cacheKey, nil)

		-- release icons
		local icons = self.artworkThumbIcons
		for icon, key in pairs(icons) do
			if key == cacheKey then
				icons[icon] = nil
			end
		end
	end

	-- clear the queue
	self.artworkFetchQueue = {}
end


--[[

=head2 jive.slim.SlimServer:fetchArtwork(iconId, icon, size, imgFormat)

The SlimServer object maintains an artwork cache. This function either loads from the cache or
gets from the network the thumb for I<iconId>. A L<jive.ui.Surface> is used to perform
I<icon>:setValue(). This function computes the URI to request the artwork from the server from I<iconId>. I<imgFormat> is an optional
argument to control the image format.

=cut
--]]
function fetchArtwork(self, iconId, icon, size, imgFormat)
	logcache:debug(self, ":fetchArtwork(", iconId, ", ", size, ", ", imgFormat, ")")

	assert(size)

	local cacheKey = iconId .. "@" .. size .. "/" .. (imgFormat or '')

	-- do we have an image already cached?
	local image = self.imageCache[cacheKey]
	if image then
		logcache:debug("..image in cache")

		-- are we requesting it already?
		if image == true then
			if icon then
				icon:setValue(nil)
				self.artworkThumbIcons[icon] = cacheKey
			end
			return
		else
			if icon then
				icon:setValue(image)
				self.artworkThumbIcons[icon] = nil
			end
			return
		end
	end
	
	-- or is the compressed artwork cached?
	local artwork = self.artworkCache:get(cacheKey)
	if artwork then
		if artwork == true then
			logcache:debug("..artwork already requested")
			if icon then
				icon:setValue(nil)
				self.artworkThumbIcons[icon] = cacheKey
			end
			return
		else
			logcache:debug("..artwork in cache")
			if icon then
				image = _loadArtworkImage(self, cacheKey, artwork, size)
				icon:setValue(image)
				self.artworkThumbIcons[icon] = nil
			end
			return
		end
	end

	-- parse size specification for width and height if in format <W>x<H>
	local sizeW = string.match(size, "(%d+)x%d+") or size
	local sizeH = string.match(size, "%d+x(%d+)") or size

	-- request SqueezeCenter resizes the thumbnail, use 'm' for
	-- original aspect ratio
	local resizeFrag = '_' .. sizeW .. 'x' .. sizeH .. '_m'

	local url
	if string.match(iconId, "^[%x%-]+$") then
		-- if the iconId is a hex digit, this is a coverid or remote track id (a negative id)
		url = '/music/' .. iconId .. '/cover' .. resizeFrag
		if imgFormat then
		 	url = url .. "." .. imgFormat
		end
	else
		if string.find(iconId, "^http") then
			-- Bug 13937, if URL references a private IP address, don't use imageproxy
			-- Tests for a numeric IP first to avoid extra string.find calls
			if string.find(iconId, "^http://%d") and (
				string.find(iconId, "^http://192%.168") or
				string.find(iconId, "^http://172%.16%.") or
				string.find(iconId, "^http://10%.")
			) then
				url = iconId
				
			-- if we're dealing with a recent LMS, we can have it do the heavy lifting
			elseif self:isMoreRecent(self:getVersion(), '7.8.0') then
				url = '/imageproxy/' .. string.urlEncode(iconId) .. '/image' .. resizeFrag
				
			else
				-- fetch image direct (previously used SN image resizer, rely on improved resizing in jivelite)
				url = iconId
			end
		-- contributor artwork doesn't come with an extension
		elseif string.find(iconId, "^contributor/%w+/image") then
			url = iconId .. resizeFrag
		else
			url = string.gsub(iconId, "(.+)(%.%a+)", "%1" .. resizeFrag .. "%2")

			if not string.find(url, "^/") then
				-- Bug 7123, Add a leading slash if needed
				url = "/" .. url
			end
		end
		
		logcache:debug(self, ":fetchArtwork(", iconId, " => ", url, ")")
	end

	-- generate a request for the artwork
	self.artworkCache:set(cacheKey, true)
	if icon then
		icon:setValue(nil)
		self.artworkThumbIcons[icon] = cacheKey
	end
	logcache:debug("..fetching artwork")

	-- queue up the request on a lifo
	table.insert(self.artworkFetchQueue, {
			     key = cacheKey,
			     id = iconId,
			     url = url,
			     size = size,
		     })
	self.artworkFetchTask:addTask()
end

function getAppParameters(self, appType)
	if not self.appParameters then
		return nil
	end

	if not self.appParameters[appType] then
		return nil
	end

	return self.appParameters[appType]
end

--set a app specific parameter, such as the iconId for facebook
function setAppParameter(self, appType, parameter, value)
	log:debug("Setting ", appType, " parameter ", parameter , " to: ", value)
	
	if not self.appParameters then
		self.appParameters = {}
	end

	if not self.appParameters[appType] then
		self.appParameters[appType] = {}
	end

	self.appParameters[appType][parameter] = value
end

--[[

=head2 tostring(aSlimServer)

if I<aSlimServer> is a L<jive.slim.SlimServer>, prints
 SlimServer {name}

=cut
--]]
function __tostring(self)
	return "SlimServer {" .. tostring(self.name) .. "}"
end


-- Accessors

--[[

=head2 jive.slim.SlimServer:getVersion()

Returns the server version

=cut
--]]
function getVersion(self)
	return self.state.version
end


-- return true if the server is compatible with this controller, false
-- if an upgrade is needed, or nil if the server version is not currently
-- known.
function isCompatible(self)
	if self:isSqueezeNetwork() then
		return true
	end

	if not self.state.version then
		return nil
	end
	
	return self:isMoreRecent(self.state.version, minimumVersion)
end

function isMoreRecent(self, new, old)
	local newVer = string.split("%.", new)
	local oldVer = string.split("%.", old)

	for i,v in ipairs(newVer) do
		if oldVer[i] and tonumber(v) > tonumber(oldVer[i]) then
			return true
		elseif oldVer[i] and tonumber(v) < tonumber(oldVer[i]) then
			return false
		end
	end

	return false
end


-- class method to set the minimum useable server version
function setMinimumVersion(class, minVersion)
	minimumVersion = minVersion
end


--[[

=head2 jive.slim.SlimServer:getIpPort()

Returns the server IP address and HTTP port

=cut
--]]
function getIpPort(self)
	return self.ip, self.port
end


--[[

=head2 jive.slim.SlimServer:getName()

Returns the server name

=cut
--]]
function getName(self)
	return self.name
end


--[[

=head2 jive.slim.SlimServer:getId()

Returns the server id

=cut
--]]
function getId(self)
	return self.id
end


--[[

=head2 jive.slim.SlimServer:getLastSeen()

Returns the time at which the last indication the server is alive happened,
either data from the server or response to discovery. This is used by
L<jive.slim.SlimServers> to delete old servers.

=cut
--]]
function getLastSeen(self)
	return self.lastSeen
end


--[[

=head2 jive.slim.SlimServer:isConnected()

Returns the state of the long term connection with the server. This is used by
L<jive.slim.SlimServers> to delete old servers.

=cut
--]]
function isConnected(self)
	return self.netstate == 'connected'
end


-- returns true if a password is needed
function isPasswordProtected(self)
	if self.realm and self.netstate ~= 'connected' then
		return true, self.realm
	else
		return false
	end
end


-- returns upgrade url and force flag
function getUpgradeUrl(self)
	return self.upgradeUrl, self.upgradeForce
end


--[[

=head2 jive.slim.SlimServer:allPlayers()

Returns all players iterator

 for id, player in allPlayers() do
     xxx
 end

=cut
--]]
function allPlayers(self)
	return pairs(self.players)
end


-- Proxies


-- user request. if not connected to SC, this will try to reconnect and also
-- sends WOL
function userRequest(self, func, ...)
	if self.netstate ~= 'connected' then
		self:wakeOnLan()
		self:connect()
	end

	local req = { func, ... }
	table.insert(self.userRequests, req)

	req.cometRequestId = self.comet:request(
		function(...)
			table.delete(self.userRequests, req)
			if func then
				func(...)
			end
		end,
		...)
end

--different from cancel since the callback would still return if the response was pending, so this is currently only
--useful if the connection is down and we don't want our request(s) fulfilled on reconnection
function removeAllUserRequests(self)
	for _,request in ipairs(self.userRequests) do
		if not self.comet:removeRequest(request.cometRequestId) then
			log:warn("Couldn't remove request: ")
			debug.dump(request)
		end
	end

	self.userRequests = {}
end


-- background request
function request(self, ...)
	self.comet:request(...)
end

--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

