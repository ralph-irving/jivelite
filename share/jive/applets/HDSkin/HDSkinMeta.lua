
--[[
=head1 NAME

applets.HDSkin.HDSkinMeta 

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
	jiveMain:registerSkin(self:string("HD_SKIN_1080"), "HDSkin", "skin_1080p", "HDSkin-1080")
	jiveMain:registerSkin(self:string("HD_SKIN_720"),  "HDSkin", "skin_720p", "HDSkin-720")
	jiveMain:registerSkin(self:string("HD_SKIN_1280_1024"),  "HDSkin", "skin_1280_1024", "HDSkin-1280-1024")
	jiveMain:registerSkin(self:string("HD_SKIN_800_480"),  "HDSkin", "skin_800_480", "HDSkin-800x480")
	jiveMain:registerSkin(self:string("HD_SKIN_VGA"),  "HDSkin", "skin_vga", "HDSkin-VGA")
end


