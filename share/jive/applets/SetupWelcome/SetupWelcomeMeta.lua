
--[[
=head1 NAME

applets.SetupWelcome.SetupWelcomeMeta - SetupWelcome meta-info

=head1 DESCRIPTION

See L<applets.SetupWelcome.SetupWelcomeApplet>.

=head1 FUNCTIONS

See L<jive.AppletMeta> for a description of standard applet meta functions.

=cut
--]]


local oo            = require("loop.simple")
local AppletMeta    = require("jive.AppletMeta")
local appletManager = appletManager

module(...)
oo.class(_M, AppletMeta)


function jiveVersion(meta)
	return 1, 1
end


function defaultSettings(meta)
	return {
		[ "setupDone" ] = false
	}
end


function registerApplet(meta)
	meta:registerService("setupFirstStartup")
end


function configureApplet(meta)
	if not meta:getSettings().setupDone then
		appletManager:callService("setupFirstStartup")
	end
end

--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]
