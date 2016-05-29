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
		-- nothing to see here, move along, move along
	}
end

function registerApplet(self)

end

function configureApplet(self)

	appletManager:callService("addScreenSaver",
		self:string("SCREENSAVER_CLOCK_STYLE_ANALOG"), 
		"Clock", 
		"openAnalogClock", _, _, 23
	)

	appletManager:callService("addScreenSaver",
		self:string("SCREENSAVER_CLOCK_STYLE_DIGITAL"), 
		"Clock", 
		"openDetailedClock", _, _, 24
	)

	appletManager:callService("addScreenSaver",
		self:string("SCREENSAVER_CLOCK_STYLE_DIGITAL_BLACK"), 
		"Clock", 
		"openDetailedClockBlack", _, _, 25
	)

	appletManager:callService("addScreenSaver",
		self:string("SCREENSAVER_CLOCK_STYLE_DIGITAL_TRANSPARENT"), 
		"Clock", 
		"openDetailedClockTransparent", _, _, 26
	)

	appletManager:callService("addScreenSaver",
		self:string("SCREENSAVER_CLOCK_STYLE_DOTMATRIX"), 
		"Clock", 
		"openStyledClock", _, _, 27
	)
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]
