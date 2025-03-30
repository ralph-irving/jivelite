
--[[
=head1 NAME

jive.slim.Player - Squeezebox/Transporter player.

=head1 DESCRIPTION

TODO

=head1 SYNOPSIS

Notifications:

 playerConnected:
 playerNewName:
 playerDigitalVolumeControl:
 playerDisconnected:
 playerPower:
 playerNew (performed by SlimServer)
 playerDelete (performed by SlimServer)
 playerTrackChange
 playerModeChange
 playerPlaylistChange
 playerShuffleModeChange
 playerRepeatModeChange
 playerPlaylistSize
 playerNeedsUpgrade
 playerTitleStatus
 playerLoaded (player and server connected and initial home menu from server has been loaded)
 
=head1 FUNCTIONS

=cut
--]]


-- stuff we need
local _assert, assert, require, setmetatable, tonumber, tostring, ipairs, pairs, type, bit = _assert, assert, require, setmetatable, tonumber, tostring, ipairs, pairs, type, bit

local os             = require("os")
local math           = require("math")
local table          = require("jive.utils.table")
local json           = require("cjson")

local oo             = require("loop.base")

local SocketHttp     = require("jive.net.SocketHttp")
local RequestHttp    = require("jive.net.RequestHttp")
local RequestJsonRpc = require("jive.net.RequestJsonRpc")
local Framework      = require("jive.ui.Framework")
local Popup          = require("jive.ui.Popup")
local Icon           = require("jive.ui.Icon")
local Label          = require("jive.ui.Label")
local Textarea       = require("jive.ui.Textarea")
local Window         = require("jive.ui.Window")
local Group          = require("jive.ui.Group")

local debug          = require("jive.utils.debug")
local string         = require("jive.utils.string")
local log            = require("jive.utils.log").logger("jivelite.player")
local socket         = require("socket")

local EVENT_KEY_ALL    = jive.ui.EVENT_KEY_ALL
local EVENT_CHAR_PRESS = jive.ui.EVENT_CHAR_PRESS
local EVENT_MOUSE_HOLD        = jive.ui.EVENT_MOUSE_HOLD
local EVENT_MOUSE_DRAG        = jive.ui.EVENT_MOUSE_DRAG
local EVENT_MOUSE_PRESS       = jive.ui.EVENT_MOUSE_PRESS
local EVENT_MOUSE_DOWN        = jive.ui.EVENT_MOUSE_DOWN
local EVENT_MOUSE_UP          = jive.ui.EVENT_MOUSE_UP
local EVENT_MOUSE_ALL         = jive.ui.EVENT_MOUSE_ALL
local EVENT_SCROLL     = jive.ui.EVENT_SCROLL
local EVENT_CONSUME    = jive.ui.EVENT_CONSUME
local ACTION           = jive.ui.ACTION

local jnt            = jnt
local jiveMain       = jiveMain
local iconbar        = iconbar


local fmt = string.format

local MIN_KEY_INT    = 150  -- sending key rate limit in ms

-- jive.slim.Player is a base class
module(..., oo.class)


-- we must load these after the module declartion to avoid dependancy loops
local SlimServer     = require("jive.slim.SlimServer")


local DEVICE_IDS = {
	[2] = "squeezebox",
	[3] = "softsqueeze",
	[4] = "squeezebox2",
	[5] = "transporter",
	[6] = "softsqueeze3",
	[7] = "receiver",
	[8] = "squeezeslave",
	[9] = "controller",
	[10] = "boom",
	[11] = "softboom",
	[12] = "squeezeplay",
}

local DEVICE_TYPE = {
	[ "squeezebox" ] = "ip2k",
	[ "softsqueeze" ] = "softsqueeze",
	[ "squeezebox2" ] = "ip3k",
	[ "squeezebox3" ] = "ip3k",
	[ "transporter" ] = "ip3k",
	[ "softsqueeze3" ] = "softsqueeze",
	[ "receiver" ] = "ip3k",
	[ "squeezeslave" ] = "squeezeslave",
	[ "controller" ] = "squeezeplay",
	[ "boom" ] = "ip3k",
	[ "softboom" ] = "softsqueeze",
	[ "squeezeplay" ] = "squeezeplay",
}


-- list of players index by id. this weak table is used to enforce
-- object equality with the server name.
local playerIds = {}
setmetatable(playerIds, { __mode = 'v' })

-- list of player that are active
local playerList = {}

-- current player
local currentPlayer = nil


-- class method to iterate over all players
function iterate(class)
	return pairs(playerList)
end


-- class method, returns the current player
function getCurrentPlayer(self)
	return currentPlayer
end

-- class method, returns whether the player is local
function isLocal(self)
	return false
end

--class method, returns the delay used before which consecutive commands like volume will be suppressed 
function getRateLimitTime(self)
	return MIN_KEY_INT
end

-- class method, returns the first local player found
function getLocalPlayer(self)
	for _,player in pairs(playerList) do
		if player:isLocal() then
			return player
		end
	end

	--no local player
	return nil
end

-- class method, sets the current player
function setCurrentPlayer(class, player)
	local lastCurrentPlayer = currentPlayer

	currentPlayer = player
	SlimServer:setCurrentServer(currentPlayer and currentPlayer.slimServer or nil)

	-- is the last current player still active?
	if lastCurrentPlayer and lastCurrentPlayer.lastSeen == 0 then
		lastCurrentPlayer:free()
	end

	-- notify even if the player has not changed
	jnt:notify("playerCurrent", currentPlayer)
end


function getLastSqueezeCenter(self)
	--not used for remote SC, since the controller isn't the decider for where to return to, the local player is.
	return nil
end


function setLastBrowseIndex(self, key, index)
	local lastBrowse = self:getLastBrowse(key)
	lastBrowse.index = index
end


function getLastBrowseIndex(self, key)
	local lastBrowse = self:getLastBrowse(key)
	return lastBrowse and lastBrowse.index
end


function getLastBrowse(self, key)
	if self.browseHistory[key] then
		return self.browseHistory[key]
	else
		return nil
	end
end

function setLastBrowse(self, key, lastBrowse)
	if not self.browseHistory then
		return
	end
	self.browseHistory[key] = lastBrowse
end

-- _getSink
-- returns a sink with a closure to self
-- cmd is passed in so we know what process function to call
-- this sink receives all the data from our Comet interface
local function _getSink(self, cmd)
	return function(chunk, err)
	       	if err then
			log:warn("err in player sink ", err)
			
		elseif chunk then
			local proc = "_process_" .. cmd[1]
			if cmd[1] == 'status' then
				log:debug('stored playlist timestamp: ', self.playlist_timestamp)
				log:debug('   new playlist timestamp: ', chunk.data.playlist_timestamp)
			end
			if self[proc] then
				self[proc](self, chunk)
			end
		end
	end
end


local function _formatShowBrieflyText(msg)
	log:debug("_formatShowBrieflyText")

	-- showBrieflyText needs to deal with both \n instructions within a string 
	-- and also adding newlines between table elements

	-- table msg needs to have elements of only strings/numbers so table.concat will work
	for i, v in ipairs(msg) do
		if type(v) ~= 'string' and type(v) ~= 'number' then
			table.remove(msg, i)
		end
	end

	-- first compress the table elements into a single string with newlines
	local text = table.concat(msg, "\n")
	-- then split the new string on \n instructions within the concatenated string, and into a table
	local split = string.split('\\n', text)
	-- then compress the new table into a string with all newlines as needed
	local text2 = table.concat(split, "\n")

	return text2
end


-- _whatsPlaying(obj)
-- returns the track_id from a playerstatus structure
local function _whatsPlaying(obj)
	local whatsPlaying = nil
	local artwork = nil
	if obj.item_loop then
		if obj.item_loop[1].params then
			if obj.item_loop[1].params.track_id and not obj.remote then
				whatsPlaying = obj.item_loop[1].params.track_id
			elseif obj.item_loop[1].text and obj.remote and type(obj.current_title) == 'string' then
				whatsPlaying = obj.item_loop[1].text .. "\n" .. obj.current_title
			elseif obj.item_loop[1].text then
				whatsPlaying = obj.item_loop[1].text
			end
		end
		artwork = obj.item_loop and obj.item_loop[1]["icon-id"] or obj.item_loop[1].icon
	end
	return whatsPlaying, artwork
end


--[[

=head2 jive.slim.Player(server, jnt, playerId)

Create a Player object with playerId.

=cut
--]]
function __init(self, jnt, playerId)
	log:debug("Player:__init(", playerId, ")")

	-- Only create one player object per id. This avoids duplicates
	-- when moving between servers

	playerId = string.lower(playerId)
	if playerIds[playerId] then
		return playerIds[playerId]
	end

	local obj = oo.rawnew(self,{
		jnt = jnt,

		id = playerId,

		slimServer = false,
		config = false,
		lastSeen = 0,

		-- player info from SC
		info = {},

		-- player state from SC
		state = {},
		mode = "off",

		isOnStage = false,

		-- current song info
		mixedPopup = {},

		-- text info
		popupInfo = {},

		-- icon popup
		popupIcon = {},

		-- browse history
		browseHistory = {}
	})

	playerIds[obj.id] = obj

	return obj
end


-- Update player on start up
function updateInit(self, slimServer, init)
	self.info.name = init.name
	self.info.model = init.model
	self.info.connected = false

	self.lastSeen = 0 -- don't timeout
	playerList[self.id] = self

	if slimServer then
		log:debug(self, " new for ", slimServer)
		self.slimServer = slimServer
		self.slimServer:_addPlayer(self)
	end
end


-- State needed for updateInit
function getInit(self)
	return {
		name = self.info.name,
		model = self.info.model,
	}
end



function setServerRefreshInProgress(self, serverRefreshInProgress)
	self.serverRefreshInProgress = serverRefreshInProgress
end

--[[

=head2 jive.slim.Player:updatePlayerInfo(squeezeCenter, playerInfo, useSequenceNumber, isSequenceNumberInSync)

Updates the player with fresh data from SS.

=cut
--]]
function updatePlayerInfo(self, slimServer, playerInfo, useSequenceNumber, isSequenceNumberInSync)

	log:debug(self, "@", slimServer, ":updatePlayerInfo connected=", playerInfo.connected);
	
	-- ignore updates from a different server if the player
	-- is not connected to it
	if self.slimServer ~= slimServer 
		and tonumber(playerInfo.connected) ~= 1 then
		return
	end

	-- Save old player info
	local oldInfo = self.info
	self.info = {}

	if type(playerInfo.uuid) == "string" then
		self.info.uuid = playerInfo.uuid
	elseif type(playerInfo.uuid) == "number" then
		self.info.uuid = tostring(playerInfo.uuid)	
	else
		--handle json.null case
		self.info.uuid = nil
	end

	-- Update player info, cast to fix perl bugs :)
	self.config = true
	self.info.name = tostring(playerInfo.name)
	self.info.model = tostring(playerInfo.model)
	self.info.connected = tonumber(playerInfo.connected) == 1
	self.info.power = tonumber(playerInfo.power) == 1
	self.info.needsUpgrade = tonumber(playerInfo.player_needs_upgrade) == 1
	self.info.isUpgrading = tonumber(playerInfo.player_is_upgrading) == 1
	self.info.pin = tostring(playerInfo.pin)
	self.info.digitalVolumeControl = tonumber(playerInfo.digital_volume_control) 
	self.info.useVolumeControl = tonumber(playerInfo.use_volume_control) 

	self.lastSeen = Framework:getTicks()

	-- PIN is removed from serverstatus after a player is linked
	if self.info.pin and not playerInfo.pin then
		self.info.pin = nil
	end

	-- Check have we changed SqueezeCenter
	if self.serverRefreshInProgress or self.slimServer ~= slimServer then
 		if self.slimServer == slimServer and self.serverRefreshInProgress then
 		        log:info("Same server but serverRefreshInProgress in progress: ", slimServer)
 		end

		self:setServerRefreshInProgress(false)

		-- delete from old server
		if self.slimServer then
			self:free(self.slimServer)
			
			-- refresh understanding of connected state because free() may have changed it
			self.info.connected = tonumber(playerInfo.connected) == 1
		end

		-- modify the old state, as the player was not connected
		-- to new SqueezeCenter. this makes sure the playerConnected
		-- callback happens.
		oldInfo.connected = false

		-- add to new server
		log:debug(self, " new for ", slimServer)
		self.slimServer = slimServer
		self.slimServer:_addPlayer(self)

		-- update current server
		if currentPlayer == self then
			SlimServer:setCurrentServer(slimServer)
		end

		-- player is now available
		playerList[self.id] = self
		self.jnt:notify('playerNew', self)
	end

	-- Check for player firmware upgrades
	if oldInfo.needsUpgrade ~= self.info.needsUpgrade or oldInfo.isUpgrading ~= self.info.isUpgrading then
		self.jnt:notify('playerNeedsUpgrade', self, self:isNeedsUpgrade(), self:isUpgrading())
	end

	-- Check if the player name has changed & is defined
	if self.info.name and oldInfo.name ~= self.info.name then
		self.jnt:notify('playerNewName', self, self.info.name)
	end

	-- Check if digital volume control has changed
	if oldInfo.digitalVolumeControl ~= self.info.digitalVolumeControl then
		log:debug('notify_playerDigitalVolumeControl: ', self.info.digitalVolumeControl)
		self.jnt:notify('playerDigitalVolumeControl', self, self.info.digitalVolumeControl)
	end

	-- Check if the player power status has changed

	if (not useSequenceNumber or isSequenceNumberInSync) and oldInfo.power ~= self.info.power then
		self.jnt:notify('playerPower', self, self.info.power)
	elseif useSequenceNumber and not isSequenceNumberInSync then
		log:debug("power value ignored(out of sync), revert to old: ", oldInfo.power)
		self.info.power = oldInfo.power
	end

	log:debug('oldInfo.connected says: ', oldInfo.connected, ' self.info.connected says: ', self.info.connected)

	-- Check if the player connected status has changed
	if oldInfo.connected ~= self.info.connected then
		if self.info.connected then
			self.jnt:notify('playerConnected', self)
		else
			self.jnt:notify('playerDisconnected', self)
		end
	end
end


-- parse a mac address and try to guess the player model based on known ranges
-- this is primarily intended for identifying players that are sitting on the network
-- waiting to be setup in ad-hoc mode
-- NOTE: this method will need updating when new mac address ranges are allocated
function macToModel(self, mac)

	if not mac then
		return false
	end
	local prefix, a, b, c = string.match(mac, "(%x%x:%x%x:%x%x):(%x%x):(%x%x):(%x%x)")

	-- further split b chars
	local d, e = string.match(b, "(%x)(%x)")

	-- if we're guessing and it's not a slim vendor id, guess that it's squeezeplay
	if prefix ~= "00:04:20" then
		return 'squeezeplay'
	end

	if a == '04' then
		return "slimp3"
	elseif a == '05' then
		-- more complex code for SB1/SB2 discernment
		-- b between 00 and 9F is an SB1
		if string.find(d, "%a") then
			return 'squeezebox2'
		else
			return 'squeezebox'
		end
	elseif a == '06' or a == '07' then
		return 'squeezebox3'
	elseif a == '08' then
		if b == '01' then
			return 'boom'
		end
	elseif a == '10' or a == '11' then
		return 'transporter'
	elseif a == '12' or a == '13' or a == '14' or a == '15' then
		return "squeezebox3"
	elseif a == '16' or a == '17' or a == '18' or a == '19' then
		return "receiver"
	elseif a == '1a' or a == '1b' or a == '1c' or a == '1d' then
		return "controller"
	elseif a == '1e' or a == '1f' or a == '20' or a == '21' then
		return "boom"
	end

	-- it's a slim product but doesn't fall within these ranges
	-- punt and call it a receiver
	return 'receiver'

end

-- return the Squeezebox mac address from the ssid, or nil if the ssid is
-- not from a Squeezebox in setup mode.
function ssidIsSqueezebox(self, ssid)
	local hasEthernet, mac = string.match(ssid, "logitech([%-%+])squeezebox[%-%+](%x+)")

	if mac then
		mac = string.gsub(mac, "(%x%x)(%x%x)(%x%x)(%x%x)(%x%x)(%x%x)", "%1:%2:%3:%4:%5:%6")
		mac = string.lower(mac)
	end

	return mac, hasEthernet
end


-- Update player state from an SSID
function updateSSID(self, ssid, lastScan)
	local mac = ssidIsSqueezebox(self, ssid)

	assert(self.id, mac)

	-- stale wlan scan results?
	if lastScan < self.lastSeen then
		return
	end

	self.config = "needsNetwork"
	self.configSSID = ssid
	self.info.connected = false

	self.lastSeen = lastScan

	-- player is now available
	playerList[self.id] = self
	self.jnt:notify('playerNew', self)
end


--[[

=head2 jive.slim.Player:free(slimServer)

Deletes the player, if connect to the given slimServer

=cut
--]]
function free(self, slimServer, serverDeleteOnly)
	if self.slimServer ~= slimServer then
		-- ignore, we are not connected to this server
		return
	end

	log:debug(self, " delete for ", self.slimServer)

	if not serverDeleteOnly then
		-- player is gone
		self.lastSeen = 0
		self.jnt:notify('playerDelete', self)
	end

	if self == currentPlayer then
		self.jnt:notify('playerDisconnected', self)
		self.info.connected = false
		-- dont' delete state if this is the current player
		return
	end

	-- player is no longer active
	if not self:isLocal() and not serverDeleteOnly then
		playerList[self.id] = nil
	end

	if self.slimServer then
		if self.isOnStage then self:offStage() end

		self.slimServer:_deletePlayer(self)
		self.slimServer = false
	end

	-- The global players table uses weak values, it will be removed
	-- when all references are freed.
end


-- Subscribe to events for this player
function subscribe(self, ...)
	if not self.slimServer then
		return
	end

	self.slimServer.comet:subscribe(...)
end


-- Unsubscribe to events for this player
function unsubscribe(self, ...)
	if not self.slimServer then
		return
	end

	self.slimServer.comet:unsubscribe(...)
end


--[[

=head2 jive.slim.Player:getTrackElapsed()

Returns the amount of time elapsed on the current track, and the track
duration (if known). eg:

  local elapsed, duration = player:getTrackElapsed()
  local remaining
  if duration then
	  remaining = duration - elapsed
  end

=cut
--]]
function getTrackElapsed(self)
	if not self.trackTime then
		return nil
	end

	if self.mode == "play" then
		local now = Framework:getTicks() / 1000

		-- multiply by rate to allow for trick modes
		self.trackCorrection = self.rate * (now - self.trackSeen)
	end

	if self.trackCorrection <= 0 then
		return self.trackTime, self.trackDuration
	else
		local trackElapsed = self.trackTime + self.trackCorrection
		return trackElapsed, self.trackDuration
	end
	
end

--[[

=head2 jive.slim.Player:getModel()

returns the model of player

=cut
--]]
function getModel(self)
	return self.info.model
end

--[[

=head2 jive.slim.Player:getPlaylistTimestamp()

returns the playlist timestamp for a given player object
the timestamp is an indicator of the last time the playlist changed
it serves as a good check to see whether playlist items should be refreshed

=cut
--]]
function getPlaylistTimestamp(self)
	return self.playlist_timestamp
end


--[[

=head2 jive.slim.Player:getPlaylistSize()

returns the playlist size for a given player object

=cut
--]]
function getPlaylistSize(self)
	return self.playlistSize
end


--[[

=head2 jive.slim.Player:getPlaylistCurrentIndex()

returns the playlist index of the currently selected track

=cut
--]]
function getPlaylistCurrentIndex(self)
	return self.playlistCurrentIndex
end


--[[

=head2 jive.slim.Player:getPlayerMode()

returns the playerMode for a given player object

=cut
--]]
function getPlayerMode(self)
	return self.mode
end


--[[

=head2 jive.slim.Player:getPlayerStatus()

returns the playerStatus information for a given player object

=cut
--]]
function getPlayerStatus(self)
	return self.state
end


--[[

=head2 tostring(aPlayer)

if I<aPlayer> is a L<jive.slim.Player>, prints
 Player {name}

=cut
--]]
function __tostring(self)
	return "Player {" .. self:getName() .. "}"
end


--[[

=head2 jive.slim.Player:getName()

Returns the player name

=cut
--]]
function getName(self)
	if self.info.name then
		return self.info.name
	else
		return "Squeezebox " .. string.gsub(string.sub(self.id, 10), ":", "")
	end
end


--[[

=head2 jive.slim.Player:isPowerOn()

Returns true if the player is powered on

=cut
--]]
function isPowerOn(self)
	return self.info.power
end


--[[

=head2 jive.slim.Player:getId()

Returns the player id (in general the MAC address)

=cut
--]]
function getId(self)
	return self.id
end


-- Returns the player ssid if in setup mode, or nil
function getSSID(self)
	if self.config == 'needsNetwork' then
		return self.configSSID
	else
		return nil
	end
end


--[[

=head2 jive.slim.Player:getUuid()

Returns the player uuid.

=cut
--]]
function getUuid(self)
	return self.info.uuid
end


--[[

=head2 jive.slim.Player:getMacAddress()

Returns the player mac address, or nil for http players.

=cut
--]]
function getMacAddress(self)
	if DEVICE_TYPE[self.info.model] == "ip3k"
	   or DEVICE_TYPE[self.info.model] == "squeezeplay" then
		return string.gsub(self.id, "[^%x]", "")
	end

	return nil
end


--[[

=head2 jive.slim.Player:getPin()

Returns the SqueezeNetwork PIN for this player, if it needs to be registered

=cut
--]]
function getPin(self)
	return self.info.pin
end


-- Clear the SN pin when the player is linked
function clearPin(self)
	self.info.pin = nil
end


--[[

=head2 jive.slim.Player:getSlimServer()

Returns the player SlimServer (a L<jive.slim.SlimServer>).

=cut
--]]
function getSlimServer(self)
	return self.slimServer
end


-- call
-- sends a command
function call(self, cmd, useBackgroundRequest)
	log:debug("Player:call():")
--log:error('traceback')
--debug.dump(cmd)

	if useBackgroundRequest then
		self.slimServer:request(
			_getSink(self, cmd),
			self.id,
			cmd
		)
		return
	end

	local reqid = self.slimServer:userRequest(
		_getSink(self, cmd),
		self.id,
		cmd
	)

	return reqid
end


-- send
-- sends a command but does not look for a response
function send(self, cmd, useBackgroundRequest)
	log:debug("Player:send():")
--	log:debug(cmd)
	if useBackgroundRequest then
		self.slimServer:request(
			nil,
			self.id,
			cmd
		)
		return
	end

	self.slimServer:userRequest(
		nil,
		self.id,
		cmd
	)
end


function hideWindows(self)
	self.mixedPopup.window:hide()
	self.popupInfo.window:hide()
	self.popupIcon.window:hide()
end


function hideAction(self)
	self:hideWindows()
	return EVENT_CONSUME
end


-- onStage
-- we're being browsed!
function onStage(self)
	log:debug("Player:onStage()")

	self.isOnStage = true
	
	-- Batch these queries together
	self.slimServer.comet:startBatch()
	
	-- subscribe to player status updates
	local cmd = { 'status', '-', 10, 'menu:menu', 'useContextMenu:1', 'subscribe:600' }
	self.slimServer.comet:subscribe(
		'/slim/playerstatus/' .. self.id,
		_getSink(self, cmd),
		self.id,
		cmd
	)

	-- subscribe to displaystatus
	cmd = { 'displaystatus', 'subscribe:showbriefly' }
	self.slimServer.comet:subscribe(
		'/slim/displaystatus/' .. self.id,
		_getSink(self, cmd),
		self.id,
		cmd
	)
	
	self.slimServer.comet:endBatch()

	-- create window to display current song info
	self.mixedPopup.window = Popup("toast_popup_mixed")
	self.mixedPopup.window:setAllowScreensaver(true)
	self.mixedPopup.window:setAlwaysOnTop(true)
	self.mixedPopup.artIcon = Icon("icon_art")
	self.mixedPopup.text = Label("text", "")
	self.mixedPopup.subtext = Label("subtext", "")
	self.mixedPopup.badge = Icon('badge_none')

	self.mixedPopup.window:addWidget(self.mixedPopup.text)
	self.mixedPopup.window:addWidget(self.mixedPopup.artIcon)
	self.mixedPopup.window:addWidget(self.mixedPopup.subtext)
	self.mixedPopup.window:addWidget(self.mixedPopup.badge)

	-- create window to display current song info
	self.popupInfo.window = Popup("toast_popup_text")
	self.popupInfo.window:setAllowScreensaver(true)
	self.popupInfo.window:setAlwaysOnTop(true)
	self.popupInfo.textarea = Textarea("toast_popup_textarea", '')

	local infoGroup = Group("group", {
			text = self.popupInfo.textarea,
	      })

	self.popupInfo.window:addWidget(infoGroup)

	--don't let the textarea get the focus, because we want the window to manage events
	self.popupInfo.window:focusWidget(nil)

	-- create window to display current song info
	self.popupIcon.window = Popup("toast_popup_icon")
	self.popupIcon.window:setAllowScreensaver(true)
	self.popupIcon.window:setAlwaysOnTop(true)
	self.popupIcon.icon = Icon("icon")
	self.popupIcon.window:addWidget(self.popupIcon.icon)

	local popups = { self.mixedPopup.window, self.popupInfo.window, self.popupIcon.window }

	for i, popup in ipairs(popups) do
		--all input cancels the popups, and for all but 'back', 'go' and mouse clicks, input is forwarded to main window
		popup:addListener(bit.bor(ACTION, EVENT_SCROLL, EVENT_MOUSE_PRESS, EVENT_MOUSE_HOLD, EVENT_MOUSE_DRAG),
			function(event)

				local prev = popup:getLowerWindow()
				--might be more than one of our windows here, look for first non player popup window
				while prev and table.contains(popups, prev) do
				        prev = prev:getLowerWindow()
			        end
				self:hideWindows()

				if prev then
					Framework:dispatchEvent(prev, event)
				end
				return EVENT_CONSUME
			end)

		popup:addActionListener("back", self, hideAction)
		popup:addActionListener("go", self, hideAction)
		popup.brieflyHandler = 1
	end


--[[
	--Only 'back' and mouse clicks clear the popup, all other input is forwarded to main window
	self.mixedPopup.window:addListener(ACTION | EVENT_SCROLL | EVENT_MOUSE_PRESS | EVENT_MOUSE_HOLD | EVENT_MOUSE_DRAG,
		function(event)

			if (event:getType() & EVENT_MOUSE_ALL) > 0 then
				return hideAction(self) 
			end

			local prev = self.mixedPopup.window:getLowerWindow()
			if prev then
				Framework:dispatchEvent(prev, event)
			end
			return EVENT_CONSUME
		end)

	self.mixedPopup.window:addActionListener("back", self, hideAction)
	self.mixedPopup.window.brieflyHandler = 1

	self.popupInfo.window:addListener(ACTION | EVENT_SCROLL | EVENT_MOUSE_PRESS | EVENT_MOUSE_HOLD | EVENT_MOUSE_DRAG,
		function(event)

			if (event:getType() & EVENT_MOUSE_ALL) > 0 then
				return hideAction(self) 
			end

			local prev = self.popupInfo.window:getLowerWindow()
			if prev then
				Framework:dispatchEvent(prev, event)
			end
			return EVENT_CONSUME
		end)

	self.popupInfo.window:addActionListener("back", self, hideAction)
	self.popupInfo.window.brieflyHandler = 1
--]]

end


-- offStage
-- go back to the shadows...
function offStage(self)
	log:debug("Player:offStage()")

	self.isOnStage = false
	
	iconbar:setPlaymode(nil)
	iconbar:setRepeat(nil)
	iconbar:setShuffle(nil)

	self.browseHistory = {}

	-- unsubscribe from playerstatus and displaystatus events
	self.slimServer.comet:startBatch()
	self.slimServer.comet:unsubscribe('/slim/playerstatus/' .. self.id)
	self.slimServer.comet:unsubscribe('/slim/displaystatus/' .. self.id)
	self.slimServer.comet:endBatch()

	self.mixedPopup = {}
end


-- updateIconbar
function updateIconbar(self)
	log:debug("Player:updateIconbar()")
	
	if self.isOnStage and self.state then
		-- set the playmode (nil, stop, play, pause)

		iconbar:setPlaymode(self:getEffectivePlayMode())
		
		-- set the shuffle (nil, 0=off, 1=by song, 2=by album)
		iconbar:setShuffle(self.state["playlist shuffle"])

		if self.state['sleep'] and tonumber(self.state['sleep']) > 0 then
			iconbar:setSleep('ON')
		else
			iconbar:setSleep('OFF')
		end

		-- alarm icon in iconbar is set directly via AlarmSnoozeApplet

		-- set the repeat (nil, 0=off, 1=single track, 2=all playlist tracks)
		iconbar:setRepeat(self.state['playlist repeat'])

		--[[ useful for layout skinning debug, set all modes to show icons
			iconbar:setPlaymode('play')
			iconbar:setShuffle('1')
			iconbar:setSleep('ON')
			iconbar:setAlarm('ON')
			iconbar:setRepeat('1')
		--]]

	else
		--still set play mode (for local offline playback)
		iconbar:setPlaymode(self.state["mode"] or self.mode)
	end
end


-- _process_status
-- processes the playerstatus data and calls associated functions for notification
function _process_status(self, event)
	log:debug("Player:_process_playerstatus()")

	if event.data.error then
		-- ignore player status sent with an error
		return
	end
	-- update our state in one go
	local oldState = self.state
	self.state = event.data


	-- used for calculating getTrackElapsed(), getTrackRemaining()
	self.rate = tonumber(event.data.rate)
	self.trackSeen = Framework:getTicks() / 1000
	self.trackCorrection = 0
	self.trackTime = tonumber(event.data.time)
	self.trackDuration = tonumber(event.data.duration)
	self.playlistSize = tonumber(event.data.playlist_tracks)
	-- add 1 to playlist_cur_index to get 1-based place in playlist
	self.playlistCurrentIndex = event.data.playlist_cur_index and tonumber(event.data.playlist_cur_index) + 1
	self.definedPresets = event.data.preset_loop
	-- alarm snooze seconds for player, defaults to 540
	self.alarmSnoozeSeconds  = event.data.alarm_snooze_seconds
	-- alarm timeout seconds for player, defaults to 3600 (same as server default)
	self.alarmTimeoutSeconds = event.data.alarm_timeout_seconds

	-- Bug 15814: flag for when the audio hasn't started streaming yet but mode is play
	self.waitingToPlay = event.data.waitingToPlay or false

	-- update our player state, and send notifications
	-- create a playerInfo table, to allow code reuse
	local playerInfo = {}
	playerInfo.uuid = self.info.uuid
	playerInfo.name = event.data.player_name
	playerInfo.digital_volume_control = event.data.digital_volume_control
	playerInfo.use_volume_control = event.data.use_volume_control
	playerInfo.model = self.info.model
	playerInfo.connected = event.data.player_connected
	playerInfo.power = event.data.power
	playerInfo.player_needs_upgrade = event.data.player_needs_upgrade
	playerInfo.player_is_upgrading = event.data.player_is_upgrading
	playerInfo.pin = self.info.pin
	playerInfo.seq_no = event.data.seq_no

	local useSequenceNumber = false
	local isSequenceNumberInSync = true

	if self:isLocal() and playerInfo.seq_no then
		useSequenceNumber = true
		if not self:isSequenceNumberInSync(tonumber(playerInfo.seq_no)) then
			isSequenceNumberInSync = false
		end
	end
	self:updatePlayerInfo(self.slimServer, playerInfo, useSequenceNumber, isSequenceNumberInSync)

	-- update track list
	local nowPlaying, artwork = _whatsPlaying(event.data)

	if self.state.mode ~= oldState.mode then
		-- self.mode is set immedidately by togglePause and stop methods to give immediate user feedback in e.g. iconbar
		-- getPlayerMode method uses self.mode not self.state.mode, so we need to set self.mode again here to be certain it's correct                                          
		log:debug('notify_playerModeChange')
		self.mode = self.state.mode
		self.jnt:notify('playerModeChange', self, self.state.mode)
	end

	log:debug("self.state['alarm_state']: ", self.state['alarm_state'], ",  oldState['alarm_state']: ", oldState['alarm_state'])
	log:debug("self.state['alarm_next']: ", self.state['alarm_next'], ",  oldState['alarm_next']: ", oldState['alarm_next'])

	log:debug("self.state['alarm_version']: ", self.state['alarm_version'], ",  oldState['alarm_version']: ", oldState['alarm_version'])
	log:debug("self.state['alarm_next2']: ", self.state['alarm_next2'], ",  oldState['alarm_next2']: ", oldState['alarm_next2'])
	log:debug("self.state['alarm_repeat']: ", self.state['alarm_repeat'], ",  oldState['alarm_repeat']: ", oldState['alarm_repeat'])
	log:debug("self.state['alarm_days']: ", self.state['alarm_days'], ",  oldState['alarm_days']: ", oldState['alarm_days'])

	if self.state['alarm_state'] ~= oldState['alarm_state'] or
	   self.state['alarm_next'] ~= oldState['alarm_next'] or
	   self.state['alarm_version'] ~= oldState['alarm_version'] or
	   self.state['alarm_next2'] ~= oldState['alarm_next2'] or
	   self.state['alarm_repeat'] ~= oldState['alarm_repeat'] or
	   self.state['alarm_days'] ~= oldState['alarm_days'] then
		log:debug('notify_playerAlarmState')
		-- none from server for alarm_state changes this to nil
		if self.state['alarm_state'] == 'none' then
			self.alarmState = nil
			self.alarmNext  = nil
--			self.jnt:notify('playerAlarmState', self, 'none', nil)
		else
			self.alarmState = self.state['alarm_state']
			self.alarmNext  = tonumber(self.state['alarm_next'])
--			self.jnt:notify('playerAlarmState', self, self.state['alarm_state'], self.state['alarm_next'] and tonumber(self.state['alarm_next']) or nil)
		end

		self.alarmVersion = tonumber(self.state['alarm_version'])
		self.alarmNext2 = tonumber(self.state['alarm_next2'])
		self.alarmRepeat = tonumber(self.state['alarm_repeat'])
		self.alarmDays = self.state['alarm_days']
		self.jnt:notify('playerAlarmState', self, self.state['alarm_state'], self.alarmNext, self.alarmVersion, self.alarmNext2, self.alarmRepeat, self.alarmDays)

	end

	if self.state['playlist shuffle'] ~= oldState['playlist shuffle'] then
		log:debug('notify_playerShuffleModeChange')
		self.jnt:notify('playerShuffleModeChange', self, self.state['playlist shuffle'])
	end

	if self.state['sleep'] ~= oldState['sleep'] then
		log:debug('notify_playerSleepChange')
		self.jnt:notify('playerSleepChange', self, self.state['sleep'])
	end

	if self.state['playlist repeat'] ~= oldState['playlist repeat'] then
		log:debug('notify_playerRepeatModeChange')
		self.jnt:notify('playerRepeatModeChange', self, self.state['playlist repeat'])
	end

	if self.nowPlaying ~= nowPlaying or self.nowPlayingArtwork ~= artwork then
		log:debug('notify_playerTrackChange')
		self.nowPlaying = nowPlaying
		self.nowPlayingArtwork = artwork
		self.jnt:notify('playerTrackChange', self, nowPlaying, artwork)
	end

	if self.state.playlist_timestamp ~= oldState.playlist_timestamp then
		log:debug('notify_playerPlaylistChange')
		self.jnt:notify('playerPlaylistChange', self)
	end

	--Ignore fractional component of volume
	self.state["mixer volume"] = self.state["mixer volume"] and math.floor(tonumber(self.state["mixer volume"])) or nil

	--might use server volume
	if useSequenceNumber then
		if isSequenceNumberInSync then
			local serverVolume = self.state["mixer volume"]
			if serverVolume ~= self:getVolume() then
				--update local volume so that it is persisted locally (actual volume will have already been changed by audg sub)
				if serverVolume == 0 and self:getVolume() and self:getVolume() < 0 then
					--When muted, server sends a 0 vol, ignore it
					self.state["mixer volume"] = oldState["mixer volume"] 
				else
					-- only persist the state here - the actual volume is changed with audg
					-- (we are effectively casting a Player to a LocalPlayer here, on the basis of useSequenceNumber;
					-- knowing this, we could just do: self.playback:setVolume(vol, stateOnly) but that would
					-- be breaking the encapsulation even more)
					self:volumeLocal(serverVolume, false, true)
				end
			end
		else
			log:debug("volume value ignored(out of sync), revert to old: ", oldState["mixer volume"])
			self.state["mixer volume"] = oldState["mixer volume"]
		end

		--finally if we were out of sync at the receipt of playerstatus, refresh so server is in sync with all value
		if not isSequenceNumberInSync then
			self:refreshLocallyMaintainedParameters()
		end
	end
	-- update iconbar
	self:updateIconbar()
end

function _alertWindow(self, title, textValue)

	local showMe = true
	local currentWindow = Window:getTopNonTransientWindow()
	if currentWindow and currentWindow:getWindowId() == textValue then
		showMe = false
	end

	if showMe then
		local window = Window('help_list', title)
		window:setAllowScreensaver(false)
		window:showAfterScreensaver()
		local text = Textarea("text", textValue)
		window:setWindowId(textValue)
		window:addWidget(text)

		local s = {}
		s.window = window
		self:tieWindow(window)
		return s
	else
		return nil
	end
end


-- _process_displaystatus
-- receives the display status data
function _process_displaystatus(self, event)
	log:debug("Player:_process_displaystatus()")
	
	local data = event.data

	if data.display then
		local display = data.display
		local type    = display["type"] or 'text'
		local special = display and (type == 'icon' and display.style)
		local alertWindow = display and type == 'alertWindow'
		local playMode = display["play-mode"]
		local isRemote = display["is-remote"] and (display["is-remote"] == 1) or false

		local s
		local textValue = _formatShowBrieflyText(display['text'])

		local transitionOn = Window.transitionFadeIn
		local transitionOff = Window.transitionFadeOut
		local duration = tonumber(display['duration'] or 3000)

		local usingIR = Framework:isMostRecentInput('ir') or Framework:isMostRecentInput('key')

		-- this showBriefly should be displayed unless there's a good reason not to
		local showMe = true
		if alertWindow then
			local title = display['title'] or ''
			s = self:_alertWindow(title, textValue)
			if not s then
				showMe = false
			end

		elseif special then
			s = self.popupIcon
			local style = 'icon_popup_' .. special
			s.icon:setStyle(style)	
			transitionOn = Window.transitionNone
			transitionOff = Window.transitionNone
			
			-- icon-based showBrieflies only appear for IR
			if not usingIR then
				showMe = false
			end
			if not isRemote and playMode and playMode == "play" then
				-- Provide quicker feedback on NP screen that a new track is playing,
				-- other display delay for next local track can be long.
				-- Bug 17758: force long duration on title so that we do not get oscillation;
				-- it will get updated with new playerStatus.
				self.jnt:notify('playerTitleStatus', self, textValue, 10000)
			end
		elseif type == 'mixed' or type == 'popupalbum' then
			s = self.mixedPopup
			local text = display['text'][1] or ''
			local subtext = display['text'][2] or ''
			s.text:setValue(text)
			s.text:animate(true)
			s.subtext:setValue(subtext)
			s.subtext:animate(true)
			if display['style'] == 'favorite' then
				s.badge:setStyle('badge_favorite')
			elseif display['style'] == 'add' then
				s.badge:setStyle('badge_add')
			else
				s.badge:setStyle('none')
			end
			self.slimServer:fetchArtwork(display["icon-id"] or display["icon"], s.artIcon, jiveMain:getSkinParam('POPUP_THUMB_SIZE'), 'png')
		elseif type == 'song' then
			self.jnt:notify('playerTitleStatus', self, textValue, duration)
			showMe = false
		else
			s = self.popupInfo
			s.textarea:setValue(textValue)
		end
		if showMe then
			if alertWindow or tonumber(duration) == -1 then
				s.window:show()
			else
				s.window:showBriefly(duration, nil, transitionOn, transitionOff)
			end
		end
	end
end


-- togglePause
--
function togglePause(self)

	if not self.state then return end
	
	local paused = self.mode
	log:debug("Player:togglePause(", paused, ")")

	if paused == 'stop' or paused == 'pause' then
		self:unpause()
	elseif paused == 'play' then
		self:pause()
	end
end


function stopPreview(self)
	if not self.state then return end
	self:call({'playlist', 'preview', 'cmd:stop' })
	self:updateIconbar()

end


function pause(self, useBackgroundRequest)
	if not self.state then return end

	self:call({'pause', '1'}, useBackgroundRequest)
	self.mode = 'pause'

	self:updateIconbar()
end


function unpause(self)
	if not self.state then return end

	local paused = self.mode

	if paused == 'stop' or paused == 'pause' then
		-- reset the elapsed time epoch
		self.trackSeen = Framework:getTicks() / 1000
		self:call({'pause', '0'})

		self.mode = 'play'
	end

	self:updateIconbar()
end

-- optional continueAudio flag cancels alarm without pausing audio
function stopAlarm(self, continueAudio)
	if not self.state then return end

	if not continueAudio then
		self:pause()
	end

	self.alarmState = 'none'
	self:call({'jivealarm', 'stop:1'})
	self:updateIconbar()

end


function snooze(self)
	if not self.state then return end

	if self.alarmState == 'active' then
		self.alarmState = 'snooze'
		self:call({'jivealarm', 'snooze:1'})
	end
	self:updateIconbar()
end

-- isPaused
--
function isPaused(self)
	if self.state then
		return self.mode == 'pause'
	end
end


function isPresetDefined(self, preset)
	if self.definedPresets and tonumber(self.definedPresets[preset]) == 0 then
		return false
	else
		return true
	end
end


function isWaitingToPlay(self)
	return self.waitingToPlay
end


function setWaitingToPlay(self, value)
	self.waitingToPlay = value
end


function getAlarmState(self)
	return self.alarmState
end


-- Bug 16100 - Sound comes from headphones although Radio is set to use speaker
-- We need to be able to set the alarm state for fallback alarms
function setAlarmState(self, state)
	self.alarmState = state
end

-- getPlayMode returns nil|stop|play|pause
--
function getPlayMode(self)
	if self.state then
		return self.mode
	end
end

--identical for non-local player
function getEffectivePlayMode(self)
	return self:getPlayMode()
end

-- isCurrent
--
function isCurrent(self, index)
	if self.state then
		return self.state.playlist_cur_index == index - 1
	end
end


function isNeedsUpgrade(self)
	return self.info.needsUpgrade
end

function isUpgrading(self)
	return self.info.isUpgrading
end

-- play
-- 
function play(self)
	log:debug("Player:play()")

	if self.mode ~= 'play' then
		-- reset the elapsed time epoch
		self.trackSeen = Framework:getTicks()
	end

	self:call({'mode', 'play'})
	self.mode = 'play'
	self:updateIconbar()
end


-- stop
-- 
function stop(self)
	log:debug("Player:stop()")
	self:call({'mode', 'stop'})
	self.mode = 'stop'
	self:updateIconbar()
end


-- playlistJumpIndex
--
function playlistJumpIndex(self, index)
	log:debug("Player:playlistJumpIndex(", index, ")")
	if index < 1 then return end
	self:call({'playlist', 'index', index - 1})
end


-- playlistDeleteIndex(self, index)
--
function playlistDeleteIndex(self, index)
	log:debug("Player:playlistDeleteIndex(", index, ")")
	if index < 1 then return end
	self:call({'playlist', 'delete', index - 1})
end


-- playlistZapIndex(self, index)
--
function playlistZapIndex(self, index)
	log:debug("Player:playlistZapIndex(", index, ")")
	if index < 1 then return end
	self:call({'playlist', 'zap', index - 1})
end



-- _process_button
--
function _process_button(self, event)
	log:debug("_process_button()")
	self.buttonTo = nil
end


-- button
-- 
function button(self, buttonName)
	local now = Framework:getTicks()
	if self.buttonTo == nil or self.buttonTo < now then
		log:debug("Sending button: ", buttonName)
		self:call({'button', buttonName })
		self.buttonTo = now + MIN_KEY_INT
	else
		log:debug("Suppressing button: ", buttonName)
	end
end

function repeatToggle(self)
	self:button('repeat')
end


function sleepToggle(self)
	self:button('sleep')
end


function shuffleToggle(self)
	self:button('shuffle')
end

function powerToggle(self)
	self:button('power')
end

function numberHold(self, number)
	self:button(number .. '.hold')
end

function presetPress(self, number)
	self:button("preset_" .. number .. '.single')
end


-- scan_rew
-- what to do for the rew button when held
-- use button so that the reverse scan mode is triggered.
function scan_rew(self)
	self:button('scan_rew')
end

-- scan_fwd
-- what to do for the fwd button when held
-- use button so that the forward scan mode is triggered.
function scan_fwd(self)
	self:button('scan_fwd')
end

-- rew
-- what to do for the rew button
-- use button so that the logic of SS (skip to start of current or previous song) is used
function rew(self)
	log:debug("Player:rew()")
	self:button('jump_rew')
end

-- fwd
-- what to do for the fwd button
-- use button so that the logic of SS (skip to start of current or previous song) is used
function fwd(self)
	log:debug("Player:fwd()")
	self:button('jump_fwd')
end


function setPower(self, on, sequenceNumber, isServerRequest)
	if isServerRequest then return end -- don't loop the request back to the server.
	if not self.state then return end

	log:debug("Player:setPower(", on, ")")

	if not on then
		if sequenceNumber then
			self:call({'power', '0', false, "seq_no:" ..  sequenceNumber}, true)
		else
			self:call({'power', '0'}, true)
		end
	else
		if sequenceNumber then
			self:call({'power', '1', false, "seq_no:" ..  sequenceNumber}, true)
		else
			self:call({'power', '1'}, true)
		end
	end
end

-- volume
-- send new volume value to SS, returns a negitive value if the player is muted
function volume(self, vol, send, sequenceNumber)
	local now = Framework:getTicks()
	if self.mixerTo == nil or self.mixerTo < now or send then
		log:debug("Sending player:volume(", vol, ")")
		if sequenceNumber then
			self:send({'mixer', 'volume', vol, "seq_no:" ..  sequenceNumber})
		else
			self:send({'mixer', 'volume', vol})
		end
		self.mixerTo = now + MIN_KEY_INT
		self.state["mixer volume"] = vol
		return vol
	else
		log:debug("Suppressing player:volume(", vol, ")")
		return nil
	end
end

-- gototime
-- jump to new time in song
function gototime(self, time)
	self.trackSeen = Framework:getTicks() / 1000
	self.trackTime = time
	log:debug("Sending player:time(", time, ")")
	self:send({'time', time })
	self:setWaitingToPlay(1)
	return nil
end

-- isTrackSeekable
-- Try to work out if SC can seek in this track - only really a guess
function isTrackSeekable(self)
	return self.trackDuration and self.state["can_seek"]
end

-- isRemote
function isRemote(self)
	return self.state.remote
end

-- mute
-- mutes or ummutes the player, returns a negitive value if the player is muted
function mute(self, mute, sequenceNumber)
	local vol = self.state["mixer volume"]
	if mute and vol >= 0 then
		-- mute
		if sequenceNumber then
			self:send({'mixer', 'muting', "toggle", "seq_no:" ..  sequenceNumber})
		else
			self:send({'mixer', 'muting'})
		end
		vol = -math.abs(vol)

	elseif vol < 0 then
		-- unmute
		if sequenceNumber then
			self:send({'mixer', 'muting', "toggle", "seq_no:" ..  sequenceNumber})
		else
			self:send({'mixer', 'muting'})
		end
		vol = math.abs(vol)
	end

	self.state["mixer volume"] = vol
	return vol
end


-- getVolume
-- returns current volume (from last status update)
function getVolume(self)
	if self.state then
		return self.state["mixer volume"] or 0
	end
end


-- returns true if this player can connect to another server
function canConnectToServer(self)
	return DEVICE_TYPE[self.info.model] == "ip3k"
	   or DEVICE_TYPE[self.info.model] == "squeezeplay"
end


-- tell the player to connect to another server
function connectToServer(self, server)

	-- make sure the server we are connecting to is awake
	server:wakeOnLan()

	if self.config == "needsServer" then
		SlimServer:addLocallyRequestedServer(server)
		_udapConnect(self, server)
		return

	elseif self.slimServer then
		local ip, port = server:getIpPort()

		--disconnect else serverstatus not being sent (TW: but how to force a serverstatus instead)
		server:disconnect()

		SlimServer:addLocallyRequestedServer(server)
		self:send({'connect', ip}, true)
		return true

	else
		log:warn("No method to connect ", self, " to ", server)
		return false
	end
end


function parseip(str)
	local ip = 0
	for w in string.gmatch(str, "%d+") do
		ip = ip / 256
		ip = bit.bor(ip, tonumber(w))
	end
	return ip
end


function disconnectFromServer(self)
	-- nothing to do for remote player
end


function getLastSeen(self)
	return self.lastSeen
end

function getAlarmSnoozeSeconds(self)
	return self.alarmSnoozeSeconds or 540
end

-- 0 is fixed volume
-- 1 is not-fixed volume (default, if nothing stored in player object)
function getDigitalVolumeControl(self)
	return self.info.digitalVolumeControl or 1
end

-- 0 is don't use volume control
-- 1 is use volume control (default, if nothing stored in player object)
function useVolumeControl(self)
	return self.info.useVolumeControl or self.info.digitalVolumeControl or 1
end


function getAlarmTimeoutSeconds(self)
	return self.alarmTimeoutSeconds or 3600
end

function isConnected(self)
	return self.slimServer and self.slimServer:isConnected() and self.info.connected
end

-- Has the connection attempt actually failed
-- stub that can be overridden in subclass
function hasConnectionFailed(self)
	return false
end

-- return true if the player is available, that is when it is connected
-- to SqueezeCenter, or in configuration mode (udap or wlan adhoc)
function isAvailable(self)
	return self.config ~= false
end


function needsNetworkConfig(self)
	return self.config == "needsNetwork"
end


function needsMusicSource(self)
	return self.config == "needsServer"
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

