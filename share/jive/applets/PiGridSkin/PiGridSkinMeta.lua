
--[[
=head1 NAME

applets.PiGridSkin.WQVGAsmallSkinMeta 

=head1 DESCRIPTION

See L<applets.WQVGAsmallSkin.WQVGAsmallSkinApplet>.

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
	jiveMain:registerSkin(self:string("PIGRID_SKIN"), "PiGridSkin", "skin", "PiGridSkin")
	jiveMain:registerSkin(self:string("PIGRID_SKIN_1024_600"), "PiGridSkin", "skin1024x600", "PiGridSkin_1024x600")
	jiveMain:registerSkin(self:string("PIGRID_SKIN_1280_800"), "PiGridSkin", "skin1280x800", "PiGridSkin_1280x800")
	jiveMain:registerSkin(self:string("PIGRID_SKIN_1366_768"), "PiGridSkin", "skin1366x768", "PiGridSkin_1366x768")
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

