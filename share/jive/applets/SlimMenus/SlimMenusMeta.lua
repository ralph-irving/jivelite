local oo            = require("loop.simple")

local AppletMeta    = require("jive.AppletMeta")

local appletManager = appletManager
local jiveMain      = jiveMain


module(...)
oo.class(_M, AppletMeta)


function jiveVersion(self)
	return 1, 1
end


function registerApplet(self)
	self:registerService('goHome')
	self:registerService('hideConnectingToPlayer')
	self:registerService('warnOnAnyNetworkFailure')

	-- add a menu item for myMusic
	jiveMain:addItem(self:menuItem('myMusicSelector', 'home', 'MENUS_MY_MUSIC', function(applet, ...) applet:myMusicSelector(...) end, 2, nil, "hm_myMusicSelector"))
	jiveMain:addItem(self:menuItem('otherLibrary', '_myMusic', 'MENUS_OTHER_LIBRARY', function(applet, ...) applet:otherLibrarySelector(...) end, 100, nil, "hm_otherLibrary"))

	appletManager:loadApplet("SlimMenus")
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

