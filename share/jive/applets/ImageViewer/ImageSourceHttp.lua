
--[[
=head1 NAME

applets.ImageViewer.ImageSourceHttp - Image source for Image Viewer

=head1 DESCRIPTION
Reads image list from URL

=head1 FUNCTIONS

Applet related methods are described in L<jive.Applet>. 

=cut
--]]


-- stuff we use
local oo			= require("loop.simple")
local math			= require("math")
local string		= require("jive.utils.string")
local Group			= require("jive.ui.Group")
local Keyboard		= require("jive.ui.Keyboard")
local Textinput     = require("jive.ui.Textinput")
local Window        = require("jive.ui.Window")
local SocketHttp	= require("jive.net.SocketHttp")
local RequestHttp	= require("jive.net.RequestHttp")
local URL       	= require("socket.url")
local Surface		= require("jive.ui.Surface")

local jnt = jnt

local log 		= require("jive.utils.log").logger("applet.ImageViewer")
local require = require
local ImageSource	= require("applets.ImageViewer.ImageSource")

module(...)
ImageSourceHttp = oo.class(_M, ImageSource)

function __init(self, applet)
	log:info("initialize ImageSourceHttp")
	obj = oo.rawnew(self, ImageSource(applet))

	obj:_fixImageListURL()

	obj.imgFiles = {}
	obj:readImageList()

	return obj
end

function readImageList(self)
	-- get URL from configuration
	local urlString = self.applet:getSettings()["http.path"]

	local defaults = {
	    host   = "",
	    port   = 80,
	    path   = "/",
	    scheme = "http"
	}
	local parsed = URL.parse(urlString, defaults)

	-- create a HTTP socket (see L<jive.net.SocketHttp>)
	local http = SocketHttp(jnt, parsed.host, parsed.port, "ImageSourceHttp")
	local req = RequestHttp(
		function(chunk, err)
			if err then
				self:popupMessage(self.applet:string("IMAGE_VIEWER_ERROR"), self.applet:string("IMAGE_VIEWER_HTTP_ERROR"))
				log:warn("error!: " .. err)
			elseif chunk then
				for l in string.gmatch(chunk, "[^\r\n]*\r*\n*") do
					l = string.gsub(l, "\n*", "")
					l = string.gsub(l, "\r*", "")
					if l ~= "" then
						self.imgFiles[#self.imgFiles+1] = l 
						log:debug(l)
					end
				end
			end
			self.lstReady = true
		end, 'GET', urlString)

	 -- go get it!
	 http:fetch(req)
end

function nextImage(self, ordering)
	oo.superclass(ImageSourceHttp).nextImage(self, ordering)

	-- refresh url list when we've reached the last item
	if self.currentImage >= #self.imgFiles then
		self:readImageList()
	end

	self:requestImage()
end

function previousImage(self, ordering)
	oo.superclass(ImageSourceHttp).previousImage(self, ordering)
	self:requestImage()
end

function requestImage(self)
	log:debug("request new image")
	-- request current image
	self.imgReady = false

	-- get URL from configuration
	local urlString = self.imgFiles[self.currentImage]

	-- Default URI settings
	local defaults = {
	    host   = "",
	    port   = 80,
	    path   = "/",
	    scheme = "http"
	}
	local parsed = URL.parse(urlString, defaults)

	log:debug("url: " .. urlString)

	-- create a HTTP socket (see L<jive.net.SocketHttp>)
	local http = SocketHttp(jnt, parsed.host, parsed.port, "ImageSourceHttp")
	local req = RequestHttp(function(chunk, err)
			if chunk then
				local image = Surface:loadImageData(chunk, #chunk)
				self.image = image
				log:debug("image ready")
			elseif err then
				self.image = nil
				log:warn("error loading picture")
			end
			self.imgReady = true
		end,
		'GET', urlString)
	http:fetch(req)
end


function settings(self, window)

	local imgpath = self.applet:getSettings()["http.path"]

	local textinput = Textinput("textinput", imgpath,
		function(_, value)
			if #value < 4 then
				return false
			end

			log:debug("Input " .. value)
			self.applet:getSettings()["http.path"] = value
			self.applet:storeSettings()
			
			self:_fixImageListURL();

			window:playSound("WINDOWSHOW")
			window:hide(Window.transitionPushLeft)
			return true
		end)
	local backspace = Keyboard.backspace()
	local group = Group('keyboard_textinput', { textinput = textinput, backspace = backspace } )

	window:addWidget(group)
	window:addWidget(Keyboard('keyboard', 'qwerty', textinput))
	window:focusWidget(group)

	self:_helpAction(window, "IMAGE_VIEWER_HTTP_PATH", "IMAGE_VIEWER_HTTP_PATH_HELP")

	return window
end


-- in an attempt to escape the URL input screen people often accidentally invalidate the default url
-- if the new value is a sub-string of the default value, revert it
function _fixImageListURL(self)
	local urlString  = self.applet:getSettings()["http.path"]
	local defaultUrl = self.applet:getDefaultSettings()["http.path"]
	
	if (urlString ~= defaultUrl and string.find(defaultUrl, urlString, 1, true)) then
		log:warn("Invalid URL: " .. urlString)
		log:warn("Replacing with default value")
		self.applet:getSettings()["http.path"] = defaultUrl
		self.applet:storeSettings()
	end 
end

--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.


=cut
--]]

