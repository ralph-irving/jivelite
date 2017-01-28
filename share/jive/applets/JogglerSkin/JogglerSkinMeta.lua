
--[[
=head1 NAME

applets.JogglerSkin.WQVGAsmallSkinMeta 

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
	return { 
		rew = false, 
		play = true, 
		fwd = true,
		repeatMode = false,
		shuffleMode = false,
		volDown = true,
		volSlider = false,
		volUp = true
	}
end

function registerApplet(self)

	self:registerService('getNowPlayingScreenButtons')
	self:registerService('setNowPlayingScreenButtons')

	jiveMain:addItem(
		self:menuItem(
			'npButtonSelector', 
			'screenSettingsNowPlaying', 
			'NOW_PLAYING_BUTTONS', 
			function(applet, ...) 
				applet:npButtonSelectorShow(...) 
			end
		)
	)

	jiveMain:registerSkin(self:string("JOGGLER_SKIN"), "JogglerSkin", "skin")
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

