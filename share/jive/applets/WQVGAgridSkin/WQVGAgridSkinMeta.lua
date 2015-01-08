
--[[
=head1 NAME

applets.WQVGAgridSkin.WQVGAgridSkinMeta 

=head1 DESCRIPTION

See L<applets.WQVGAgridSkin.WQVGAgridSkinApplet>.

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


function jiveVersion(self)
	return 1, 1
end

function defaultSettings(self)
	return {}
end

function registerApplet(self)
	--[[ disabled as this skin is not actively developed
	jiveMain:registerSkin(self:string("WQVGA_GRID_SKIN"), "WQVGAgridSkin", "skin")
	--]]
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

