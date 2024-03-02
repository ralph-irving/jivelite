
--[[
=head1 NAME

applets.Slideshow.SlideshowMeta - Slideshow meta-info

=head1 DESCRIPTION

See L<applets.Slideshow.SlideshowMeta>.

=head1 FUNCTIONS

See L<jive.AppletMeta> for a description of standard applet meta functions.

=cut
--]]


local oo            = require("loop.simple")

local System        = require("jive.System")
local AppletMeta    = require("jive.AppletMeta")
local appletManager = appletManager
local jiveMain      = jiveMain


module(...)
oo.class(_M, AppletMeta)


function jiveVersion(meta)
	return 1, 1
end


function registerApplet(meta)
	jiveMain:addItem(meta:menuItem('appletImageViewer', 'settings', "IMAGE_VIEWER", 
		function(applet, ...) applet:openImageViewer(...) end, 58, nil, "hm_appletImageViewer"))
	
	meta:registerService("registerRemoteScreensaver")
	meta:registerService("unregisterRemoteScreensaver")
	meta:registerService("openRemoteScreensaver")
	meta:registerService("mmImageViewerMenu")
	meta:registerService("mmImageViewerBrowse")
end


function configureApplet(self)
	appletManager:callService("addScreenSaver",
		self:string("IMAGE_VIEWER"),
		"ImageViewer",
		"startScreensaver",
		self:string("IMAGE_VIEWER_SETTINGS"),
		"openSettings",
		90,
		"closeRemoteScreensaver"
	)

	appletManager:callService("mmRegisterMenuItem", {
		serviceMethod = "mmImageViewerMenu",
		menuText      = self:string('IMAGE_VIEWER_START_SLIDESHOW')
	})

	appletManager:callService("mmRegisterMenuItem", {
		serviceMethod = "mmImageViewerBrowse",
		menuText      = self:string('IMAGE_VIEWER_BROWSE_IMAGES')
	})
end


function defaultSettings(self)
	local defaultSetting = {}
	defaultSetting["delay"] = 10000
	defaultSetting["rotation"] = System:hasDeviceRotation()
	defaultSetting["fullscreen"] = false
	defaultSetting["transition"] = "fade"
	defaultSetting["ordering"] = "sequential"
	defaultSetting["textinfo"] = false

	defaultSetting["source"] = "http"
	defaultSetting["card.path"] = "/media"
	defaultSetting["http.path"] = "http://ralph.irving.sdf.org/static/images/imageviewer/sbtouch.lst"

	if System:getMachine() == "baby" then
		defaultSetting["http.path"] = "http://ralph.irving.sdf.org/static/images/imageviewer/sbradio.lst"
	end

	if System:getMachine() == "jive" then
		defaultSetting["http.path"] = "http://ralph.irving.sdf.org/static/images/imageviewer/sbcontroller.lst"
	end

	return defaultSetting
end

--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

