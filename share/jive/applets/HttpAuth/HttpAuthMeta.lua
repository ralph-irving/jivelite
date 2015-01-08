
--[[
=head1 NAME

applets.HttpAuth.HttpAuthMeta - HttpAuth meta-info

=head1 DESCRIPTION

See L<applets.HttpAuth.HttpAuthMeta>.

=head1 FUNCTIONS

See L<jive.AppletMeta> for a description of standard applet meta functions.

=cut
--]]

local pairs = pairs

local oo            = require("loop.simple")

local AppletMeta    = require("jive.AppletMeta")
local Framework     = require("jive.ui.Framework")

local SlimServer    = require("jive.slim.SlimServer")

local appletManager = appletManager
local jiveMain      = jiveMain

module(...)
oo.class(_M, AppletMeta)

function jiveVersion(meta)
	return 1, 1
end

function defaultSettings(meta)
        return { }
end

function registerApplet(meta)

	meta:registerService('squeezeCenterPassword')

	local settings = meta:getSettings()

	for serveruuid, cred in pairs(settings) do
		SlimServer:setCredentials(cred, serveruuid)
	end

end

--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]
