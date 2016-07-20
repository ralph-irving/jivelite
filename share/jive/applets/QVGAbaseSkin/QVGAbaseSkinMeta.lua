
--[[
=head1 NAME

applets.QVGAbaseSkin.QVGAbaseSkinMeta - base class for 240 x 320 and 320 x 240 resolutions

=head1 DESCRIPTION

See L<applets.QVGAbaseSkin.QVGAbaseSkinApplet>.

=head1 FUNCTIONS

See L<jive.AppletMeta> for a description of standard applet meta functions.

=cut
--]]


local oo            = require("loop.simple")

local AppletMeta    = require("jive.AppletMeta")

local appletManager = appletManager
local jiveMain      = jiveMain
local debug         = require('jive.utils.debug')


module(...)
oo.class(_M, AppletMeta)


function jiveVersion(self)
	return 1, 1
end

function defaultSettings(self)
	return {}
end

function registerApplet(self)

end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

