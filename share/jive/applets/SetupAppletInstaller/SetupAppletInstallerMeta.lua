
--[[
=head1 NAME

applets.SetupAppletInstaller.SetupAppletInstallerMeta - SetupAppletInstaller meta-info

=head1 DESCRIPTION

See L<applets.SetupAppletInstaller.SetupAppletInstallerApplet>.

=head1 FUNCTIONS

See L<jive.AppletMeta> for a description of standard applet meta functions.

=cut
--]]


local oo            = require("loop.simple")

local jiveMain      = jiveMain
local AppletMeta    = require("jive.AppletMeta")
local Timer         = require("jive.ui.Timer")

local appletManager = appletManager
local jnt           = jnt
local JIVE_VERSION  = jive.JIVE_VERSION

module(...)
oo.class(_M, AppletMeta)


function jiveVersion(self)
	return 1, 1
end

function defaultSettings(self)
	return { _AUTOUP = false }
end

function registerApplet(self)
	self.menu = self:menuItem('appletSetupAppletInstaller', 'advancedSettings', self:string("APPLET_INSTALLER"), function(applet, ...) applet:appletInstallerMenu(...) end)
	jiveMain:addItem(self.menu)
	self:registerService("appletInstallerMenu")
end

function configureApplet(self)
	-- open the applet installer menu after an upgrade if setting selected
	-- use a timer to hope to reconnect to servers first
	local settings = self:getSettings()

	if settings._AUTOUP and settings._LASTVER and settings._LASTVER ~= JIVE_VERSION then
		Timer(
			5000, 
			function() appletManager:callService("appletInstallerMenu", { text = self:string("APPLET_INSTALLER") }, 'auto') end,
			true
		):start()
	end

	settings._LASTVER = JIVE_VERSION

	self:storeSettings()
end
