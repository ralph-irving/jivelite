
--[[
=head1 NAME

applets.SetupDateTime.SetupDateTimeMeta - SetupDateTime meta-info

=head1 DESCRIPTION

See L<applets.SetupDateTime.SetupDateTimeApplet>.

=head1 FUNCTIONS

See L<jive.AppletMeta> for a description of standard applet meta functions.

=cut
--]]


local oo            = require("loop.simple")
local locale	    = require("jive.utils.locale")
local datetime      = require("jive.utils.datetime")

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
		weekstart = "Sunday",
		dateformat = "%a %d %b %Y",
		shortdateformat = "%m.%d.%Y",
		hours = "12",
	}
end

function initDateTimeObject(meta)
	local dt = datetime
	dt:setWeekstart(meta:getSettings()["weekstart"])
	dt:setDateFormat(meta:getSettings()["dateformat"])
	dt:setShortDateFormat(meta:getSettings()["shortdateformat"])
	dt:setHours(meta:getSettings()["hours"])
end

function registerApplet(meta)

	-- Init Date Time Object for later use
	initDateTimeObject(meta)

	meta:registerService("setupDateTimeSettings")
	meta:registerService("setDateTimeDefaultFormats")

        -- Menu for configuration
        jiveMain:addItem(meta:menuItem('appletSetupDateTime', 'screenSettings', "DATETIME_TITLE", function(applet, ...) applet:settingsShow(...) end))
end



--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--
--]]
