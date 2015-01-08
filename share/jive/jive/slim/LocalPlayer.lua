--[[

Player instance for local playback.

--]]

local assert = assert

local oo             = require("loop.simple")

local Framework      = require("jive.ui.Framework")
local Player         = require("jive.slim.Player")
local math           = require("math")

local jiveMain       = jiveMain
local debug          = require("jive.utils.debug")
local log            = require("jive.utils.log").logger("jivelite.player")

-- can be overridden by hardware specific classes
local DEVICE_ID      = 12
local DEVICE_MODEL   = "squeezeplay"
local DEVICE_NAME    = "SqueezePlay"


module(...)
oo.class(_M, Player)


-- class method to set the device type
function setDeviceType(self, model, name)
	 DEVICE_ID = 9
	 DEVICE_MODEL = model
	 DEVICE_NAME = name or model
end


-- class method to get the device type etc.
function getDeviceType(self)
	return DEVICE_ID, DEVICE_MODEL, DEVICE_NAME
end


--class method - disconnect from player and server and re-set "clean (no server)" LocalPlayer as current player (if there is a local player), otherwise set current player to nil
function disconnectServerAndPreserveLocalPlayer(self)
	--disconnect from player and server
	self:setCurrentPlayer(nil)

	--Free server from local player (removed: todo clean up this method name), and re-set current player to LocalPlayer
	local localPlayer = Player:getLocalPlayer()
	if localPlayer then
		if localPlayer:getSlimServer() then
			localPlayer:stop()
		end
		Player:setCurrentPlayer(localPlayer)
	end


end


function getLastSqueezeCenter(self)
	return self.lastSqueezeCenter
end


function setLastSqueezeCenter(self, server)
	log:debug("lastSqueezeCenter set: ", server)

	self.lastSqueezeCenter = server
end


function __init(self, jnt, playerId, uuid)
	local obj = oo.rawnew(self, Player(jnt, playerId))

	-- initialize with default values
	obj:updateInit(nil, {
		name = DEVICE_NAME,
		model = DEVICE_MODEL,
	})

	obj.sequenceNumber = 1

	return obj
end


function incrementSequenceNumber(self)
	self.sequenceNumber = self.sequenceNumber + 1
	return self.getCurrentSequenceNumber()
end

function getCurrentSequenceNumber(self)
	return self.sequenceNumber
end

function isSequenceNumberInSync(self, serverSequenceNumber)
--[[	if sequenceController and sequenceNumber then
		if self.sequenceController ~= sequenceController then
			self.sequenceController = sequenceController
			self.sequenceControllerNumber = sequenceNumber
			return true
		elseif sequenceNumber > (self.sequenceControllerNumber or 0)
			or math.abs(self.sequenceControllerNumber - sequenceNumber) > 100
		then
			self.sequenceControllerNumber = sequenceNumber
			return true
		else
			return false
		end
	elseif sequenceNumber ~= self.sequenceNumber then
		log:debug("server sequence # out of sync. server: ", sequenceNumber, " local: ", self.sequenceNumber)
		return false
	end
--]]	return true
end

--resend local values to server, but only update seq number on last call, so that the next player status comes back with a single increase 
function refreshLocallyMaintainedParameters(self)
	log:debug("refreshLocallyMaintainedParameters()")

	--refresh volume
	self:_volumeNoIncrement(self:getVolume(), true, true)

	--refresh power state
	self:setPower(jiveMain:getSoftPowerState() == "on")

	--todo: pause, mute

end

function isLocal(self)
	return true
end


function getCapturePlayMode(self)
	return false
end


function setCapturePlayMode(self, capturePlayMode)
end


function _volumeNoIncrement(self, vol, send)
--	self:volumeLocal(vol)
	return Player.volume(self, vol, send)
end


function __tostring(self)
	return "LocalPlayer {" .. self:getName() .. "}"
end

--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]
