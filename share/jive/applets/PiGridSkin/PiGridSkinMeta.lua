
--[[
=head1 NAME

applets.PiGridSkin.WQVGAsmallSkinMeta 

=head1 DESCRIPTION

See L<applets.WQVGAsmallSkin.WQVGAsmallSkinApplet>.

=head1 FUNCTIONS

See L<jive.AppletMeta> for a description of standard applet meta functions.

=cut
--]]


local tostring, tonumber  = tostring, tonumber

local oo            = require("loop.simple")
local os            = require("os")

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
	
	-- allow user to define a custom screen size
	local screen_width = tonumber(os.getenv('JL_SCREEN_WIDTH') or 0)
	local screen_height = tonumber(os.getenv('JL_SCREEN_HEIGHT') or 0)
	
	-- this skin only really works in landscape mode with a decent ratio of > 1.3
	if screen_width > 300 and screen_height > 200 and screen_width/screen_height >= 1.2 then
		jiveMain:registerSkin(tostring(self:string("PIGRID_SKIN_CUSTOM")) .. " (" .. tostring(screen_width) .. "x" .. tostring(screen_height) .. ")", "PiGridSkin", "skinCustom", "PiGridSkin_Custom")
	elseif screen_width > 0 or screen_height > 0 then
		log:warn("Custom screen size ratio (width/height) must be >= 1.2, is " .. tostring(screen_width/screen_height))
	end
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

