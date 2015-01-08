
--[[
=head1 NAME

applets.LogSettings.LogSettingsMeta - LogSettings meta-info

=head1 DESCRIPTION

See L<applets.LogSettings.LogSettingsApplet>.

=head1 FUNCTIONS

See L<jive.AppletMeta> for a description of standard applet meta functions.

=cut
--]]


local oo            = require("loop.simple")

local AppletMeta    = require("jive.AppletMeta")
local System        = require("jive.System")

local appletManager = appletManager
local jiveMain      = jiveMain
local lfs           = require("lfs")


module(...)
oo.class(_M, AppletMeta)


function jiveVersion(meta)
	return 1, 1
end


function registerApplet(meta)
	jiveMain:addItem(meta:menuItem('appletLogSettings', 'advancedSettings', 'DEBUG_LOG', function(applet, ...) applet:logSettings(...) end))
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

