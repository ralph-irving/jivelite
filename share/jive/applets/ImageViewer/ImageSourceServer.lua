
--[[
=head1 NAME

applets.ImageViewer.ImageSourceServer - Image source for Image Viewer

=head1 DESCRIPTION

Reads image list from SC or SN, currently just continuous photo streams, not fixed list based

=head1 FUNCTIONS

Applet related methods are described in L<jive.Applet>. 

=cut
--]]


-- stuff we use
local ipairs = ipairs

local oo			= require("loop.simple")
local table			= require("jive.utils.table")
local string		= require("jive.utils.string")
local json          = require("cjson")
local math			= require("math")
local debug         = require("jive.utils.debug")
local SocketHttp	= require("jive.net.SocketHttp")
local SlimServer    = require("jive.slim.SlimServer")
local RequestHttp	= require("jive.net.RequestHttp")
local URL       	= require("socket.url")
local Icon  		= require("jive.ui.Icon")
local Surface		= require("jive.ui.Surface")
local Framework		= require("jive.ui.Framework")
local System        = require("jive.System")

local jnt = jnt
local jiveMain = jiveMain

local log 		= require("jive.utils.log").logger("applet.ImageViewer")
local require = require
local ImageSource	= require("applets.ImageViewer.ImageSource")

module(...)
oo.class(_M, ImageSource)

function __init(self, applet, serverData)
	log:info("initialize ImageSourceServer")
	obj = oo.rawnew(self, ImageSource(applet))

	obj.imgFiles = {}

	obj.serverData = serverData

	obj.imageDataHistory = {}
	obj.imageDataHistoryMax = 30
	
	obj:readImageList()
	
	obj.error = nil

	return obj
end


function readImageList(self)
	local cmd = self.serverData.cmd
	local playerId = self.serverData.playerId
	local server = self.serverData.server

	self.lstReady = false
	
	if server and server:isConnected() then
		log:debug("readImageList: server:", server, " id: ", self.serverData.id, " playerId: ", playerId)
	
		server:request(
			imgFilesSink(self),
			playerId,
			cmd
		)
	else
		self.imgReady = false
		log:warn("readImageList: server ", server, " is not available")
		self.error = self.applet:string("IMAGE_VIEWER_LIST_NOT_READY_SERVER")

		local popup = self:listNotReadyError()
		popup:addTimer(self.applet:getSettings()["delay"], function()
			popup:hide()
			popup = nil
		end)
	end
end

function imgFilesSink(self)
	return function(chunk, err)
		if err then
			log:warn("err in sink ", err)

		elseif chunk then
			if log:isDebug() then
				log:debug("imgFilesSink:")
				debug.dump(chunk, 5)
			end
			if chunk and chunk.data and chunk.data.data then
				self.imgFiles = _cleanseNilListData(chunk.data.data)
				self.currentImageIndex = 0
				self.lstReady = true

				log:debug("Image list response count: ", #self.imgFiles)
			end
		end
	end

end

function _cleanseNilListData(inputList)
	local outputList = {}

	for _,data in ipairs(inputList) do
		if data.image ~= json.null then
			table.insert(outputList, data)
		end
	end

	return outputList
end

function nextImage(self)
	if #self.imgFiles == 0 then
		self:readImageList()
		self:emptyListError()
		return
	end

	self.currentImageIndex = self.currentImageIndex + 1
	if self.currentImageIndex <= #self.imgFiles then
		local imageData = self.imgFiles[self.currentImageIndex]
		self:requestImage(imageData, true)
	end
	--else might exceed if connection is down, if so don't try to reload another pic, just keep retrying until success

	if self.currentImageIndex >= #self.imgFiles then
		--queue up next list
		self:readImageList()
	end
end

function previousImage(self, ordering)
	if #self.imageDataHistory == 1 then
		return
	end

	--remove from history, similar to browser back history, except forward always move to next fetched image.
	table.remove(self.imageDataHistory, #self.imageDataHistory) -- remove current
	local imageData = table.remove(self.imageDataHistory, #self.imageDataHistory) -- get previous

	self:requestImage(imageData)
end

function _updateImageDataHistory(self, imageData)
	table.insert(self.imageDataHistory, imageData)

	if #self.imageDataHistory > self.imageDataHistoryMax then
		table.remove(self.imageDataHistory, 1)
	end

end


function requestImage(self, imageData)
	log:debug("request new image")
	-- request current image
	self.imgReady = false

	local screenWidth, screenHeight = Framework:getScreenSize()

	local urlString = imageData.image
	
	-- Bug 13937, if URL references a private IP address, don't use imageproxy
	-- Tests for a numeric IP first to avoid extra string.find calls
	if string.find(urlString, "^http://%d") and (
		string.find(urlString, "^http://192%.168") or
		string.find(urlString, "^http://172%.16%.") or
		string.find(urlString, "^http://10%.")
	) then
		-- use raw urlString
	
	elseif not string.find(urlString, "^http://") then
		-- url on current server
		local server = SlimServer:getCurrentServer()
		
		-- if an image url has the {resizeParams} placeholder, add Squeezebox server resizing parameters
		local resizeParams = "_" .. screenWidth .. "x" .. screenHeight

		if self.applet:getSettings()["fullscreen"] then
			resizeParams = resizeParams .. "_c"

		-- if the device can rotate (Jive) make sure we get whatever is the bigger ratio
		elseif self.applet:getSettings()["rotation"] and (screenWidth < screenHeight) then
			resizeParams = "_" .. screenHeight .. "x" .. (math.floor(screenHeight * screenHeight / screenWidth)) .. "_f"
		end
		
		urlString = string.gsub(urlString, "{resizeParams}", resizeParams)
		
		if server then
			local ip, port = server:getIpPort()
			if ip and port then
				urlString = "http://" .. ip .. ":" .. port .. "/" .. urlString
			end
		end
		
	else
		--use SN image proxy for resizing
		urlString = 'http://' .. jnt:getSNHostname() .. '/public/imageproxy?w=' .. screenWidth .. '&h=' .. screenHeight .. '&f=' .. ''  .. '&u=' .. string.urlEncode(urlString)
	end

	self.currentImageFile = urlString

	local textLines = {}
	if imageData.caption and imageData.caption ~= "" then
		table.insert(textLines, imageData.caption)
	end
	if imageData.date and imageData.date ~= "" then
		table.insert(textLines, imageData.date)
	end
	if imageData.owner and imageData.owner ~= "" then
		table.insert(textLines, imageData.owner)
	end

	self.currentCaption = ""
	self.currentCaptionMultiline = ""
	for i,line in ipairs(textLines) do
		self.currentCaption = self.currentCaption .. line
		self.currentCaptionMultiline = self.currentCaptionMultiline .. line
		if i < #textLines then
			self.currentCaption = self.currentCaption .. " - "
			self.currentCaptionMultiline = self.currentCaptionMultiline .. "\n\n"
		end
	end

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
	local http = SocketHttp(jnt, parsed.host, parsed.port, "ImageSourceServer")
	local req = RequestHttp(function(chunk, err)
			if chunk then
				local image = Surface:loadImageData(chunk, #chunk)
				self.image = image
				log:debug("image ready")
				self.error = nil
				self:_updateImageDataHistory(imageData)
			elseif err then
				self.image = nil
				self.error = self.applet:string("IMAGE_VIEWER_HTTP_ERROR_IMAGE") 
				log:warn("error loading picture")
			end
			self.imgReady = true
		end,
		'GET', urlString)
	http:fetch(req)
end

function getText(self)
	return self.currentCaption
end


function getMultilineText(self)
	return self.currentCaptionMultiline
end


function settings(self, window)
	return window
end

function updateLoadingIcon(self)
	local icon = Icon("icon_photo_loading")

	if self.serverData.appParameters and self.serverData.appParameters.iconId 
		and not string.match(self.serverData.appParameters.iconId, "MyApps") then

		-- don't display the My Apps icon in case we're browsing flickr/facebook through the My Apps menu
		self.serverData.server:fetchArtwork(self.serverData.appParameters.iconId, icon, jiveMain:getSkinParam('POPUP_THUMB_SIZE'), 'png')
	end
	
	return icon
end

function getErrorMessage(self)
	return self.error or self.applet:string("IMAGE_VIEWER_HTTP_ERROR_IMAGE")
end

function listNotReadyError(self)
	return self:popupMessage(self.applet:string("IMAGE_VIEWER_ERROR"), self.applet:string("IMAGE_VIEWER_LIST_NOT_READY_SERVER"))
end

--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.


=cut
--]]

