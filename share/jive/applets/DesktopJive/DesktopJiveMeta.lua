
local oo            = require("loop.simple")
local io            = require("io")
local math          = require("math")
local string        = require("string")
local table         = require("jive.utils.table")
local os            = require("os")

local AppletMeta    = require("jive.AppletMeta")
local Framework     = require("jive.ui.Framework")
local System        = require("jive.System")
local SlimServer        = require("jive.slim.SlimServer")

local appletManager = appletManager
local jiveMain      = jiveMain
local jive          = jive
local jnt           = jnt


module(...)
oo.class(_M, AppletMeta)


function jiveVersion(meta)
	return 1, 1
end


function defaultSettings(meta)
	return { 
		uuid = false
	}
end


function registerApplet(meta)
	-- profile functions, 1 second warn, 10 second die - this cuts down app performance so only use for testing....
--	jive.perfhook(1000, 10000)


	--disable arp to avoid os calls, which is problematic on windows - popups, vista permissions -  disabling disables WOL functionality
	if string.match(os.getenv("OS") or "", "Windows") then
		jnt:setArpEnabled(false)
	end


	local settings = meta:getSettings()

	local store = false

	if not settings.uuid then
		store = true

		local uuid = {}
		for i = 1,16 do
			uuid[#uuid + 1] = string.format('%02x', math.random(255))
		end

		settings.uuid = table.concat(uuid)
	end

	-- fix bogus mac addresses from bad check
	if settings.mac and string.match(settings.mac, "00:04:20") then
		settings.mac = nil
	end

	if not settings.mac then
		settings.mac = System:getMacAddress()
		store = true
	end

	if not settings.mac then
		-- random fallback
		mac = {}
		for i = 1,6 do
			mac[#mac + 1] = string.format('%02x', math.random(255))
		end

		store = true
		settings.mac = table.concat(mac, ":")
	end

	if store then
		log:debug("Mac Address: ", settings.mac)
		meta:storeSettings()
	end

	-- set mac address and uuid
	System:init({
		macAddress = settings.mac,
		uuid = settings.uuid,
	})

	System:setCapabilities({
	--	["touch"] = 1,
	--	["ir"] = 1,
		["powerKey"] = 1,
		["muteKey"] = 1,
		["alarmKey"] = 1,
	--	["audioByDefault"] = 1,
		["wiredNetworking"] = 1,
	--	["deviceRotation"] = 1,
		["coreKeys"] = 1,
		["presetKeys"] = 1,
	})

	appletManager:addDefaultSetting("ScreenSavers", "whenStopped", "false:false")

	-- this is the startup skin - expect user to select an alternative
	jiveMain:setDefaultSkin("HDSkin-VGA")

	Framework:addActionListener("soft_reset", self, _softResetAction, true)

end


--disconnect from player and server and re-set "clean (no server)" LocalPlayer as current player
function _softResetAction(self, event)
	jiveMain:goHome()
end

--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

