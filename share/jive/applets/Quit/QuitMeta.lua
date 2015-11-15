
--[[
=head1 NAME

applets.Quit.QuitMeta - Quit meta-info

=head1 DESCRIPTION

See L<applets.Quit.QuitApplet>.

=head1 FUNCTIONS

See L<jive.AppletMeta> for a description of standard applet meta functions.

=cut
--]]

local bit = bit

local oo            = require("loop.simple")

local AppletMeta    = require("jive.AppletMeta")

local Framework     = require("jive.ui.Framework")

local appletManager = appletManager
local jiveMain      = jiveMain

local EVENT_CONSUME = jive.ui.EVENT_CONSUME
local EVENT_QUIT    = jive.ui.EVENT_QUIT

local arg, ipairs, string = arg, ipairs, string

module(...)
oo.class(_M, AppletMeta)


function jiveVersion(self)
	return 1, 1
end


function registerApplet(self)
end

function configureApplet(self)
	-- don't load on Squeeze Player control instance
	local load = true
	if string.match(arg[0], "jivelite%-sp") then
		load = false
	end
	for _, a in ipairs(arg) do
		if a == "--sp-applets" then
			load = false
		end
	end

	if load then
		-- add ourselves to the end of the main menu
		jiveMain:addItem({
			id = 'appletQuit',
			iconStyle = 'hm_quit',
			node = 'home',
			text = self:string("QUIT"),
			callback = function() 
				-- disconnect from Player/SqueezeCenter
				appletManager:callService("disconnectPlayer")

				Framework:quit()

				return (bit.bor(EVENT_CONSUME, EVENT_QUIT))
			end,
			weight = 1010,
		})
	end
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]
