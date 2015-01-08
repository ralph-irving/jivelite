
--[[
=head1 NAME

jive.AppletMeta - The applet meta base class.

=head1 DESCRIPTION

This is a base class for the applet meta, a small class that is
loaded at boot to perform (a) versioning verification and (b)
hook the applet into the menu system or whatever so that it can 
be accessed and loaded on demand.

=head1 FUNCTIONS

=cut
--]]

local error = error

local oo = require("loop.base")

local log = require("jive.utils.log").logger("jivelite.applets")

local appletManager = appletManager

module(..., oo.class)


--[[

=head2 self:jiveVersion()

Should return the min and max version of Jive supported by the applet.
Jive does not load applets incompatible with itself. Required.

=cut
--]]
function jiveVersion(self)
	error("jiveVersion() required")
end


--[[

=head2 self:registerApplet()

Should register the applet as a screensaver, or add it to a menu,
or otherwise do something that makes the applet accessible or useful.
If the meta determines the applet cannot run in the current environment,
it should simply not register the applet in anything. Required.

=cut
--]]
function registerApplet(self)
	error("registerApplet() required")
end


--[[

=head2 self:configureApplet()

Called after all applets have been registered, this can be used to
configure the applet.

=cut
--]]
function configureApplet(self)
	-- optional
end


--[[

=head2 self:defaultSettings()

Returns a table with the default settings for this applet, or nil
if not settings are used.

=cut
--]]
function defaultSettings(self)
	return nil
end

--[[

=head2 self:upgradeSettings()

Returns a table with the upgraded settings for this applet, or the existing settings

=cut
--]]
function upgradeSettings(self, settings)
	return settings
end


--[[

=head2 self:getSettings()

Returns the settings for this applet.

=cut
--]]
function getSettings(self)
	return self._settings
end


-- storeSettings
-- used by jive.AppletManager to persist the applet settings
function storeSettings(self)
	appletManager._storeSettings(self._entry)
end


local lastMenuApplet = false

--[[

=head2 self:menuItem(label, closure)

Convenience method that returns a MenuItem to be used in the SimpleMenu
to open an applet. I<label> is a string token, and I<closure>
is the function executed when the MenuItem is selected. 

=cut
--]]
function menuItem(self, id, node, label, closure, weight, extras, iconStyle)
	if not iconStyle then
		--bug #12510
		iconStyle = "hm_advancedSettings"
	end
	return {
		id = id,
		iconStyle = iconStyle,
		node = node,
		text = self:string(label),
		weight = weight,
		sound = "WINDOWSHOW",
		callback = function(event, menuItem)
			if lastMenuApplet ~= self._entry.appletName then
				log:info("entering ", self._entry.appletName)
				lastMenuApplet = self._entry.appletName
			end

			local applet = appletManager:loadApplet(self._entry.appletName)
			return closure(applet, menuItem)
		end,
		extras = extras
	}
end


function string(self, token, ...)
	return self._stringsTable:str(token, ...)
end


function registerService(self, service)
	appletManager:registerService(self._entry.appletName, service)
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

