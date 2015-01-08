
--[[
=head1 NAME

applets.SelectPlayer.SelectPlayerMeta - SelectPlayer meta-info

=head1 DESCRIPTION

See L<applets.SelectPlayer.SelectPlayer>.

=head1 FUNCTIONS

See L<jive.AppletMeta> for a description of standard applet meta functions.

=cut
--]]


local oo            = require("loop.simple")

local AppletMeta    = require("jive.AppletMeta")

local appletManager = appletManager
local jiveMain      = jiveMain


module(...)
oo.class(_M, AppletMeta)

function defaultSettings(meta)
	return {}
end

function jiveVersion(meta)
	return 1, 1
end


function registerApplet(meta)

	meta:registerService('setupShowSelectPlayer')
	meta:registerService('selectPlayer')

	-- SelectPlayer is a resident Applet, Applet loads all menus necessary
	appletManager:loadApplet("SelectPlayer")

end

--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]
