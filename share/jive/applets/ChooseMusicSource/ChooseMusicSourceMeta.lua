
--[[
=head1 NAME

applets.ChooseMusicSource.ChooseMusicSourceMeta

=head1 DESCRIPTION

See L<applets.ChooseMusicSource.ChooseMusicSourceApplet>.

=head1 FUNCTIONS

See L<jive.AppletMeta> for a description of standard applet meta functions.

=cut
--]]


local oo            = require("loop.simple")

local AppletMeta    = require("jive.AppletMeta")

local appletManager = appletManager
local jiveMain      = jiveMain
local jnt           = jnt
local _player       = false

module(...)
oo.class(_M, AppletMeta)


function jiveVersion(meta)
	return 1, 1
end


function defaultSettings(meta)
	return {
		poll = { ["255.255.255.255"] = "255.255.255.255" }
	}
end


function registerApplet(meta)

	meta:registerService("selectCompatibleMusicSource")
	meta:registerService("selectMusicSource")
	meta:registerService("connectPlayerToServer")
	meta:registerService("hideConnectingToServer")
	meta:registerService("showConnectToServer")

end

function configureApplet(meta)

	-- set the poll list for discovery of slimservers based on our settings
	if appletManager:hasService("setPollList") then
		appletManager:callService("setPollList", meta:getSettings().poll)
	end

	jiveMain:addItem(
		meta:menuItem(
			'appletRemoteSlimservers',
			'networkSettings',
			"REMOTE_LIBRARIES",
			function(applet, ...)
				applet:remoteServersWindow(...)
			end,
			11
		)
	)

end

--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

