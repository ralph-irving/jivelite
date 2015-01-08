
--[[
=head1 NAME

jive.Iconbar - icon raw at the bottom of the screen

=head1 DESCRIPTION

The Iconbar class implements the Jive iconbar at the bottom of the screen. It refreshes itself every second.

=head1 SYNOPSIS

 -- Create the iconbar (this done for you in JiveMain)
 iconbar = Iconbar()

 -- Update playmode icon
 iconbar:setPlaymode('stop')

 -- force iconbar update
 iconbar:update()

=head1 FUNCTIONS

=cut
--]]

-- stuff we use
local tostring  = tostring

local os        = require("os")
local math      = require("math")
local string    = require("string")

local oo        = require("loop.base")

local Framework = require("jive.ui.Framework")
local Icon      = require("jive.ui.Icon")
local Label     = require("jive.ui.Label")
local Group     = require("jive.ui.Group")

local hasDecode, decode = pcall(require, "squeezeplay.decode")

local datetime  = require("jive.utils.datetime")
local log       = require("jive.utils.log").logger("jivelite.iconbar")


-- our class
module(..., oo.class)


-- to debug buffer fullness
local bufferFullness = false


--[[

=head2 Iconbar:setPlaymode(val)

Set the playmode icon of the iconbar. Values are nil (off), "stop", "play" or "pause".

=cut
--]]
function setPlaymode(self, val)
	log:debug("Iconbar:setPlaymode(", val, ")")
	self.iconPlaymode:setStyle("button_playmode_" .. string.upper((val or "OFF")))
end

--[[

=head2 Iconbar:setRepeat(val)

Set the repeat icon of the iconbar. Values are nil (no repeat), 1 for repeat single track and 2 for repeat all playlist tracks.

=cut
--]]
function setRepeat(self, val)
	log:debug("Iconbar:setRepeat(", val, ")")
	self.iconRepeat:setStyle("button_repeat_" .. string.upper((val or "OFF")))
end


--[[

=head2 Iconbar:setAlarm(val)

Sets the alarm icon on the iconbar. Values are OFF and ON

=cut
--]]
function setAlarm(self, val)
	log:debug("Iconbar:setAlarm(", val, ")")
	self.iconAlarm:setStyle("button_alarm_" .. string.upper((val or "OFF")))
end


--[[

=head2 Iconbar:setSleep(val)

Sets the sleep icon on the iconbar. Values are OFF (Sleep Off), and ON (Sleep On)

=cut
--]]
function setSleep(self, val)
	log:debug("Iconbar:setSleep(", val, ")")
	self.iconSleep:setStyle("button_sleep_" .. string.upper((val or "OFF")))
end


--[[

=head2 Iconbar:setShuffle(val)

Set the shuffle icon of the iconbar. Values are nil (no shuffle), 1 for shuffle by track and 2 for shuffle by album.

=cut
--]]
function setShuffle(self, val)
	log:debug("Iconbar:setShuffle(", val, ")")
	self.iconShuffle:setStyle("button_shuffle_" .. string.upper((val or "OFF")))
end


--[[

=head2 Iconbar:setBattery(val)

Set the state of the battery icon of the iconbar. Values are nil (no battery), CHARGING, AC or 0-4.

=cut
--]]
function setBattery(self, val)
	log:debug("Iconbar:setBattery(", val, ")")
	self.iconBattery:setStyle("button_battery_" .. string.upper((val or "NONE")))
end


--[[

=head2 Iconbar:setWirelessSignal(val)

Set the state of the network icon of the iconbar.
Wireless val: ERROR or 0, 1, 2, 3, 4
Ethernet val: ETHERNET_ERROR or ETHERNET
self.serverError: ERROR, nil or OK

=cut
--]]
function setWirelessSignal(self, val, iface)
	log:debug("Iconbar:setWireless(", val, ")")

	local networkAndServerState = false

	self.wirelessSignal = val
	self.iface = iface

	-- No ethernet link, ip, gateway or dns
	if val == "ETHERNET_ERROR" then
		self.iconWireless:setStyle("button_ethernet_ERROR")
	-- No wireless link, ip, gateway or dns
	elseif (val == "ERROR") or (val == 0) then
		self.iconWireless:setStyle("button_wireless_ERROR")
	-- Ethernet ok, but no server connection
	elseif (val == "ETHERNET") and (self.serverError == "ERROR" or self.serverError == nil) then
		self.iconWireless:setStyle("button_ethernet_SERVERERROR")
	-- Wireless ok, but no server connection
	elseif (val ~= "ETHERNET") and (self.serverError == "ERROR" or self.serverError == nil) then
		self.iconWireless:setStyle("button_wireless_SERVERERROR")
	-- Etherent and server connection ok
	elseif val == "ETHERNET" then
		networkAndServerState = true
		self.iconWireless:setStyle("button_ethernet")
	-- Wireless and server connection ok, show signal strength
	else
		networkAndServerState = true
		self.iconWireless:setStyle("button_wireless_" .. (val or "NONE"))
	end

	-- Send notification about network and server state
	if self.oldNetworkAndServerState ~= networkAndServerState then
		if networkAndServerState == true then
			log:debug("Network and server ok")

			self.jnt:notify("networkAndServerOK", iface)
		else
			log:debug("Network or server not ok")

			self.jnt:notify("networkOrServerNotOK", iface)
		end
	end
	self.oldNetworkAndServerState = networkAndServerState
end


--[[

=head2 Iconbar:setServerError(val)

Set the state of the SqueezeCenter connection. Values are nil, OK or ERROR.

=cut
--]]
function setServerError(self, val)
	self.serverError = val
	self:setWirelessSignal(self.wirelessSignal, self.iface)
end



-- show debug in place of the time in the iconbar, for elapsed seconds
function showDebug(self, value, elapsed)
	self.button_time:setValue(value)

	self.debugTimeout = Framework:getTicks() + ((elapsed or 10) * 1000)
end


--[[

=head2 Iconbar:update()

Updates the iconbar.

=cut
--]]
function update(self)
	log:debug("Iconbar:update()")

	if self.debugTimeout and Framework:getTicks() < self.debugTimeout then
		return
	end

	self.button_time:setValue(datetime:getCurrentTime())
end


--[[

=head2 Iconbar()

Creates the iconbar.

=cut
--]]
function __init(self, jnt)
	log:debug("Iconbar:__init()")

	local obj = oo.rawnew(self, {
		iconPlaymode = Icon("button_playmode_OFF"),
		iconRepeat   = Icon("button_repeat_OFF"),
		iconShuffle  = Icon("button_shuffle_OFF"),
		iconBattery  = Icon("button_battery_NONE"),
		iconWireless = Icon("button_wireless_NONE"),
		iconSleep    = Icon("button_sleep_OFF"),
		iconAlarm    = Icon("button_alarm_OFF"),
		button_time  = Label("button_time", "XXXX"),

		jnt = jnt
	})

	obj.iconbarGroup = Group("iconbar_group", {
					play = obj.iconPlaymode,
					repeat_mode = obj.iconRepeat,  -- repeat is a Lua reserved word
					shuffle = obj.iconShuffle,
					alarm = obj.iconAlarm,
					sleep = obj.iconSleep,
					battery = obj.iconBattery,
					wireless = obj.iconWireless,
				})

	obj:update()

	Framework:addWidget(obj.iconbarGroup)
	Framework:addWidget(obj.button_time)

	obj.button_time:addTimer(1000,  -- every second
			      function() 
				      obj:update()
			      end)
	
	return obj
end
--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

