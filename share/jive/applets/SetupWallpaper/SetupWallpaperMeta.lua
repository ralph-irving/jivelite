
--[[
=head1 NAME

applets.SetupWallpaper.SetupWallpaperMeta - SetupWallpaper meta-info

=head1 DESCRIPTION

See L<applets.SetupWallpaper.SetupWallpaperApplet>.

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


function jiveVersion(meta)
	return 1, 1
end


function defaultSettings(meta)
	return { 
		WQVGAsmallSkin = "fab4_encore.png",
	}
end

function registerApplet(meta)
	meta:registerService("showBackground")
	meta:registerService("setBackground")
	-- add a menu item for configuration
	jiveMain:addItem(meta:menuItem('appletSetupWallpaper', 'screenSettings', 'WALLPAPER', function(applet, ...) applet:settingsShow(...) end))

end

function configureApplet(meta)
	-- load default wallpaper before connecting to a player (nil will load default)
	appletManager:callService("setBackground", nil)
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

