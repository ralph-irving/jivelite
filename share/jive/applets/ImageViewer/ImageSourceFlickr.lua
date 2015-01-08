--[[ !!!!!! PLEASE NOTE: This module is obsolete - it's been replace with a mysb.com based app. !!!!!!! ]]--

--[[
=head1 NAME

applets.ImageViewer.ImageSourceFlickr - Image source for Image Viewer

=head1 DESCRIPTION
Reads image list from Flickr

=head1 FUNCTIONS

Applet related methods are described in L<jive.Applet>. 

=cut
--]]


-- stuff we use
local ipairs, pairs = ipairs, pairs

local oo			= require("loop.simple")
local math			= require("math")
local table			= require("jive.utils.table")
local string		= require("jive.utils.string")
local Group			= require("jive.ui.Group")
local Keyboard		= require("jive.ui.Keyboard")
local SimpleMenu	= require("jive.ui.SimpleMenu")
local RadioButton	= require("jive.ui.RadioButton")
local RadioGroup	= require("jive.ui.RadioGroup")
local Textinput     = require("jive.ui.Textinput")
local Window        = require("jive.ui.Window")
local SocketHttp	= require("jive.net.SocketHttp")
local RequestHttp	= require("jive.net.RequestHttp")
local URL       	= require("socket.url")
local Surface		= require("jive.ui.Surface")
local json		= require("json")
local jnt = jnt
local apiKey		= "6505cb025e34a7e9b3f88daa9fa87a04"

local log 		= require("jive.utils.log").logger("applet.ImageViewer")
local require = require
local ImageSource	= require("applets.ImageViewer.ImageSource")

module(...)
ImageSourceFlickr = oo.class(_M, ImageSource)

function __init(self, applet)
	log:info("initialize ImageSourceFlickr")
	obj = oo.rawnew(self, ImageSource(applet))

	obj.imgFiles = {}
	obj:readImageList()
	obj.photo = nil
	obj.url = ""

	return obj
end

function readImageList(self)
	local method, args

	local displaysetting = self.applet:getSettings()["flickr.display"]
	if displaysetting == nil then
		displaysetting = "interesting"
	end

	if displaysetting == "recent" then
		method = "flickr.photos.getRecent"
		args = { per_page = 1, extras = "owner_name" }
	elseif displaysetting == "contacts" then
		method = "flickr.photos.getContactsPublicPhotos"
		args = { per_page = 100, extras = "owner_name", user_id = self.applet:getSettings()["flickr.id"], include_self = 1 }
	elseif displaysetting == "own" then
		method = "flickr.people.getPublicPhotos"
		args = { per_page = 100, extras = "owner_name", user_id = self.applet:getSettings()["flickr.id"] }
	elseif displaysetting == "favorites" then
		method = "flickr.favorites.getPublicList"
		args = { per_page = 100, extras = "owner_name", user_id = self.applet:getSettings()["flickr.id"] }
	elseif displaysetting == "tagged" then
		method = "flickr.photos.search"
		args = { per_page = 100, extras = "owner_name", tags = URL.escape(self.applet:getSettings()["flickr.tags"]) }
	else 
		method = "flickr.interestingness.getList"
		args = { per_page = 100, extras = "owner_name" }
	end

	local host, port, path = self:_flickrApi(method, args)
	if host then
		local socket = SocketHttp(jnt, host, port, "flickr")
		local req = RequestHttp(
			function(chunk, err)
				if chunk then
					log:debug("got chunk ", chunk)
					local obj = json.decode(chunk)

					-- add photos to queue
					for i,photo in ipairs(obj.photos.photo) do
						self.imgFiles[#self.imgFiles + 1] = photo
					end
				end
				self.lstReady = true
			end,
			'GET',
			path)
		socket:fetch(req)

		return true
	else
		return false, port -- port is err!
	end
end


function _getPhotoUrl(self, photo, size)
	local server = "farm" .. photo.farm .. ".static.flickr.com"
	local path = "/" .. photo.server .. "/" .. photo.id .. "_" .. photo.secret .. (size or "") .. ".jpg"

	return server, 80, path
end


function nextImage(self, ordering)
	if #self.imgFiles == 0 then
		self.lstReady = false
		self.imgReady = false
		self.photo = nil
		self:readImageList()
		return
	end
	oo.superclass(ImageSourceFlickr).nextImage(self, ordering)
	self:requestImage()
end


function previousImage(self, ordering)
	self:nextImage(ordering)
end

function requestImage(self)
	log:debug("request new image")
	-- request current image
	self.imgReady = false

	-- get URL from configuration
	photo = table.remove(self.imgFiles, self.currentImage)
	
	local host, port, path = self:_getPhotoUrl(photo)
	self.url = "http://" .. host .. ":" .. port .. path

	log:info("photo URL: ", self.url)

	-- request photo
	-- create a HTTP socket (see L<jive.net.SocketHttp>)
	local http = SocketHttp(jnt, host, port, "ImageSourceHttp")
	local req = RequestHttp(function(chunk, err)
			if chunk then
				local image = Surface:loadImageData(chunk, #chunk)
				self.image = image
				log:debug("image ready")
			elseif err then
				log:warn("error loading picture")
			end
			self.imgReady = true
		end,
		'GET', path)
	http:fetch(req)
end

function getText(self)
	return photo.owner,"",photo.title
end

function getCurrentImagePath(self)
	return self.url
end


function settings(self, window)

	window:addWidget(SimpleMenu("menu",
		{
			{
				text = self.applet:string("IMAGE_VIEWER_FLICKR_FLICKR_ID"),
				sound = "WINDOWSHOW",
				callback = function(event, menuItem)
					self:defineFlickrId(menuItem)
					return EVENT_CONSUME
				end
			},
			{
				text = self.applet:string("IMAGE_VIEWER_FLICKR_DISPLAY"), 
				sound = "WINDOWSHOW",
				callback = function(event, menuItem)
					self:displaySetting(menuItem)
					return EVENT_CONSUME
				end
			},
			{
				text = self.applet:string("IMAGE_VIEWER_FLICKR_TAGS"),
				sound = "WINDOWSHOW",
				callback = function(event, menuItem)
					self:defineTags(menuItem)
					return EVENT_CONSUME
				end
			},		}))

    return window
end

function defineFlickrId(self, menuItem)

    local window = Window("text_list", self.applet:string("IMAGE_VIEWER_FLICKR_FLICKR_ID"), flickrTitleStyle)

	local flickrid = self.applet:getSettings()["flickr.idstring"]
	if flickrid == nil then
		flickrid = ""
	end

	local input = Textinput("textinput", flickrid,
		function(_, value)
			if #value < 4 then
				return false
			end

			local v = string.gsub(value, " ", "")

			log:debug("Input " .. v)
			self:setFlickrIdString(v)

			window:playSound("WINDOWSHOW")
			window:hide(Window.transitionPushLeft)
			return true
		end)

	local keyboard  = Keyboard("keyboard", "qwerty", input)
        local backspace = Keyboard.backspace()
        local group     = Group('keyboard_textinput', { textinput = input, backspace = backspace } )

        window:addWidget(group)
        window:addWidget(keyboard)
        window:focusWidget(group)

    self.applet:tieAndShowWindow(window)
    return window
end

function defineTags(self, menuItem)

    local window = Window("text_list", self.applet:string("IMAGE_VIEWER_FLICKR_TAGS"), flickrTitleStyle)

	local tags = self.applet:getSettings()["flickr.tags"]
	if tags == nil then
		tags = ""
	end

	local input = Textinput("textinput", tags,
		function(_, value)
			self:setTags(value)

			window:playSound("WINDOWSHOW")
			window:hide(Window.transitionPushLeft)
			return true
		end)

	local keyboard  = Keyboard("keyboard", "qwerty", input)
        local backspace = Keyboard.backspace()
        local group     = Group('keyboard_textinput', { textinput = input, backspace = backspace } )

        window:addWidget(group)
        window:addWidget(keyboard)
        window:focusWidget(group)

	self:_helpAction(window, "IMAGE_VIEWER_FLICKR_TAGS", "IMAGE_VIEWER_FLICKR_QUERY_TAGS")
    self.applet:tieAndShowWindow(window)

    return window
end


function displaySetting(self, menuItem)
	local group = RadioGroup()

	local display = self.applet:getSettings()["flickr.display"]
	
	local window = Window("text_list", menuItem.text, flickrTitleStyle)
	window:addWidget(SimpleMenu("menu",
		{
			{
				text = self.applet:string("IMAGE_VIEWER_FLICKR_DISPLAY_OWN"),
				style = 'item_choice',
				check = RadioButton(
					"radio",
					group,
					function()
						self:setDisplay("own")
					end,
					display == "own"
				),
			},
			{
				text = self.applet:string("IMAGE_VIEWER_FLICKR_DISPLAY_FAVORITES"),
				style = 'item_choice',
				check = RadioButton(
					"radio",
					group,
					function()
						self:setDisplay("favorites")
					end,
					display == "favorites"
				),
			},           
			{
				text = self.applet:string("IMAGE_VIEWER_FLICKR_DISPLAY_CONTACTS"),
				style = 'item_choice',
				check = RadioButton(
					"radio",
					group,
					function()
						self:setDisplay("contacts")
					end,
					display == "contacts"
				),
			},
			{
				text = self.applet:string("IMAGE_VIEWER_FLICKR_DISPLAY_INTERESTING"), 
				style = 'item_choice',
				check = RadioButton(
					"radio", 
					group, 
					function() 
						self:setDisplay("interesting") 
					end,
					display == "interesting"
				),
			},
			{ 
				text = self.applet:string("IMAGE_VIEWER_FLICKR_DISPLAY_RECENT"), 
				style = 'item_choice',
				check = RadioButton(
					"radio", 
					group, 
					function() 
						self:setDisplay("recent") 
					end,
					display == "recent"
				),
			},
			{ 
				text = self.applet:string("IMAGE_VIEWER_FLICKR_DISPLAY_TAGGED"), 
				style = 'item_choice',
				check = RadioButton(
					"radio", 
					group, 
					function() 
						self:setDisplay("tagged") 
					end,
					display == "tagged"
				),
			},
		}
	))
	
	self.applet:tieAndShowWindow(window)
	return window
end

function setDisplay(self, display)
	if self.applet:getSettings()["flickr.id"] == "" and (display == "own" or display == "contacts" or display == "favorites") then
		self:popupMessage(self.applet:string("IMAGE_VIEWER_FLICKR_ERROR"), self.applet:string("IMAGE_VIEWER_FLICKR_INVALID_DISPLAY_OPTION"))
	else
		self.applet:getSettings()["flickr.display"] = display
		self.applet:storeSettings()
	end
end

function setFlickrIdString(self, flickridString)
	self.applet:getSettings()["flickr.idstring"] = flickridString
	self.applet:getSettings()["flickr.id"] = ""
	self.applet:storeSettings()
	self:resolveFlickrIdByEmail(flickridString)
end

function setFlickrId(self, flickrid)
	self.applet:getSettings()["flickr.id"] = flickrid
	self.applet:storeSettings()
end

function setTags(self, tags)
	self.applet:getSettings()["flickr.tags"] = tags
	self.applet:storeSettings()
end

function _flickrApi(self, method, args)
	local url = {}	
	url[#url + 1] = "method=" .. method

	for k,v in pairs(args) do
		url[#url + 1] = k .. "=" .. v
	end

	url[#url + 1] = "api_key=" .. apiKey
	url[#url + 1] = "format=json"
	url[#url + 1] = "nojsoncallback=1"
	
	url = "/services/rest/?" .. table.concat(url, "&")
	log:info("service=", url)

	return "api.flickr.com", 80, url
end

function _findFlickrIdByEmail(self, searchText)
	return self:_flickrApi("flickr.people.findByEmail",
		{
			find_email = searchText
		}
	)
end


function _findFlickrIdByUserID(self, searchText)
	return self:_flickrApi("flickr.people.findByUsername",
		{
			username = searchText
		}
	)
end

function resolveFlickrIdByEmail(self, searchText)
	-- check whether searchText is an email
	local host, port, path = self:_findFlickrIdByEmail(searchText)
	log:info("find by email: ", host, ":", port, path)

	local http = SocketHttp(jnt, host, port, "flickr3")
	local req = RequestHttp(function(chunk, err)
			if chunk then
				local obj = json.decode(chunk)
				if obj.stat == "ok" then
					log:info("flickr id found: " .. obj.user.nsid)
					self:setFlickrId(obj.user.nsid)
				else
					log:warn("search by email failed: ", searchText)
					self:resolveFlickrIdByUsername(searchText)
				end
			end
		end,
		'GET',
		path)
	http:fetch(req)

	return true
end

function resolveFlickrIdByUsername(self, searchText)
	-- check whether searchText is a username
	local host, port, path = self:_findFlickrIdByUserID(searchText)
	log:info("find by userid: ", host, ":", port, path)
	local http = SocketHttp(jnt, host, port, "flickr4")
	local req = RequestHttp(function(chunk, err)
			if chunk then
				local obj = json.decode(chunk)
				if obj.stat == "ok" then
					log:info("flickr id found: " .. obj.user.nsid)
					self:setFlickrId(obj.user.nsid)
				else
					log:warn("search by userid failed")
					self:popupMessage(self.applet:string("IMAGE_VIEWER_FLICKR_ERROR"), self.applet:string("IMAGE_VIEWER_FLICKR_USERID_ERROR"))
				end
			end
		end,
		'GET',
		path)
	http:fetch(req)

	return true
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.


=cut
--]]

