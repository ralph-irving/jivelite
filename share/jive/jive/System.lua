
--[[
=head1 NAME

jive.System - system properties

=head1 DESCRIPTION

Access system specific properties, including files.


=head2 System:getUUID()

Return the SqueezePlay UUID.

=head2 System:getMacAddress()

Return the mac address, used as a unique id by SqueezePlay.

=head2 System:getArch()

Return the system architecture (e.g. i386, armv5tejl, etc).

=head2 System:getMachine()

Return the machine (e.g. squeezeplay, jive, etc).

=head2 System:getUserPath()

Return the user-specific path that holds settings, 3rd-party applets, wallpaper, etc. The path is part of the overall Lua path.

=head2 System:findFile(path)

Find a file on the lua path. Returns the full path of the file, or nil if it was not found.

--]]
local tonumber, tostring, type, pairs = tonumber, tostring, type, pairs

local oo           = require("loop.simple")
local log           = require("jive.utils.log").logger("jivelite")


-- our class
module(...)
oo.class(_M, System)


function isHardware(class)
	return (class:getMachine() ~= "jivelite") -- FIXME???
end

-- NOTE: this table does not set default capabilities for all players, but rather is a simple list of all of the possible capabilities used
-- to add a capability, go to the platform-specific applet (e.g. SqueezeboxFab4Applet) and add the capability there.
-- if it is not set for the device, the assumption is that it does not have that capability
local allCapabilities = {
	["touch"] = 1,
	["ir"] = 1,
	["powerKey"] = 1,
	["presetKeys"] = 1,
	["alarmKey"] = 1,
	["homeAsPowerKey"] = 1,
	["muteKey"] = 1,
	["volumeKnob"] = 1,
	["audioByDefault"] = 1,
	["wiredNetworking"] = 1,
	["deviceRotation"] = 1,
	["coreKeys"] = 1,
	["sdcard"] = 1,
	["usb"] = 1,
	["batteryCapable"] = 1,
	["hasDigitalOut"] = 1,
	["hasTinySC"] = 1,
	["IRBlasterCapable"] = 1,
}

local _capabilities = {} -- of form string, 1 so

local _touchpadBottomCorrection = 0

function setCapabilities(self, capabilities)

	for capability, value in pairs(capabilities) do
		if not allCapabilities[capability] then
			log:warn("Unknown capability: ", capability)
		end
	end
	
	_capabilities = capabilities
end

function hasTinySC(self)
	return _capabilities["hasTinySC"] ~= nil
end

function hasDigitalOut(self)
	return _capabilities["hasDigitalOut"] ~= nil
end

function hasTouch(self)
	return _capabilities["touch"] ~= nil
end

function hasIr(self)
	return _capabilities["ir"] ~= nil
end

function hasHomeAsPowerKey(self)
	return _capabilities["homeAsPowerKey"] ~= nil
end

function hasPowerKey(self)
	return _capabilities["powerKey"] ~= nil
end

function hasMuteKey(self)
	return _capabilities["muteKey"] ~= nil
end

function hasVolumeKnob(self)
	return _capabilities["volumeKnob"] ~= nil
end

function hasAudioByDefault(self)
	return _capabilities["audioByDefault"] ~= nil
end

function hasWiredNetworking(self)
	return _capabilities["wiredNetworking"] ~= nil
end

function hasSoftPower(self)
	return ( self:hasTouch() or self:hasPowerKey() )
end

function hasDeviceRotation(self)
	return _capabilities["deviceRotation"] ~= nil
end

function hasCoreKeys(self)
	return _capabilities["coreKeys"] ~= nil
end

function hasPresetKeys(self)
	return _capabilities["presetKeys"] ~= nil
end

function hasAlarmKey(self)
	return _capabilities["alarmKey"] ~= nil
end


function getTouchpadBottomCorrection(self)
	return _touchpadBottomCorrection
end

function setTouchpadBottomCorrection(self, value)
	_touchpadBottomCorrection = value
end

function hasUSB(self)
	return _capabilities["usb"] ~= nil
end

function hasSDCard(self)
	return _capabilities["sdcard"] ~= nil
end

function hasLocalStorage(self)
	return self:hasUSB() or self:hasSDCard() or not self:isHardware()
end

function hasBatteryCapability(self)
	return _capabilities["batteryCapable"] ~= nil
end

function hasIRBlasterCapability(self)
	return _capabilities["IRBlasterCapable"] ~= nil
end

-- rest is C implementation


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

