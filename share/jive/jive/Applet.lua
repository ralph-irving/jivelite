
--[[
=head1 NAME

jive.Applet - The applet base class.

=head1 DESCRIPTION

jive.Applet is the base class for all Jive applets. In Jive,
applets are very flexible in the methods they implement; this
class implements a very simple framework to manage localization,
settings and memory management.

=head1 FUNCTIONS

=cut
--]]

local coroutine, package, pairs = coroutine, package, pairs

local oo               = require("loop.base")
local lfs              = require("lfs")

local AppletManager    = require("jive.AppletManager")

local EVENT_WINDOW_POP = jive.ui.EVENT_WINDOW_POP


module(..., oo.class)


--[[

=head2 self:init()

Called to initialize the Applet.

In the object __init method the applet settings and localized strings
are not available.

=cut
--]]
function init(self)
end


--[[

=head2 self:free()

This is called when the Applet will be freed. It must make sure all
data is unreferenced to allow for garbage collection. The method
should return true if the applet can be freed, or false if it should
be left loaded into memory. The default return value in jive.Applet is
true.

=cut
--]]
function free(self)
	return true
end


--[[

=head2 self:tieWindow(window)

Tie the I<window> to this applet. When all tied windows are poped 
from the window stack then this applet is freed.

=cut
--]]
function tieWindow(self, window)
	self._tie = self._tie or {}
	self._tie[window] = true

	window:addListener(EVENT_WINDOW_POP,
		function()
			self._tie[window] = nil
			for _ in pairs(self._tie) do return end
			AppletManager:_freeApplet(self._entry)
		end)
end


--[[

=head2 self:tieWindow(window, ...)

Tie the I<window> to this applet, and then show the I<window>. When all 
tied windows are poped from the window stack then this applet is freed.
The varargs are passed to the windows show() method.

=cut
--]]
function tieAndShowWindow(self, window, ...)
	self:tieWindow(window)
	window:show(...)
end


local function dirIter(self, path)
	local rpath = "applets/" .. self._entry.appletName .. "/" .. path
	
	for dir in package.path:gmatch("([^;]*)%?[^;]*;") do
		dir = dir .. rpath

		local mode = lfs.attributes(dir, "mode")
		
		if mode == "directory" then
			for entry in lfs.dir(dir) do
				if entry ~= "." and entry ~= ".." and entry ~= ".svn" then
					coroutine.yield(rpath .. '/' .. entry)
				end
			end
		end
	end
end

--[[

An iterator over the applets files in path.

--]]
function readdir(self, path)
	local co = coroutine.create(function() dirIter(self, path) end)
	return function()
		local code, res = coroutine.resume(co)
		return res
	end
end


--[[

=head2 jive.Applet:setSettings(settings)

Sets the applet settings to I<settings>.

=cut
--]]
function setSettings(self, settings)
	self._settings = settings
end


--[[

=head2 jive.Applet:getSettings()

Returns a table with the applet settings

=cut
--]]
function getSettings(self)
	return self._settings
end

--[[

=head2 jive.Applet:getDefaultSettings()

Returns a table with the defaultSettings table from the applet's Meta file

=cut
--]]

function getDefaultSettings(self)
	return self._defaultSettings
end

-- storeSettings
-- used by jive.AppletManager to persist the applet settings
function storeSettings(self)
	AppletManager._storeSettings(self._entry)
end


--[[

=head2 jive.Applet:string(token)

Returns a localised version of token

=cut
--]]
function string(self, token, ...)
	return self._stringsTable:str(token, ...)
end


function registerService(self, service, closure)
	AppletManager:registerService(self._entry.name, service, closure)
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

