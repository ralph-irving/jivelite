
--[[
=head1 NAME

applets.ImageViewer.ImageSourceStorage - use local storage as image source for Image Viewer

=head1 DESCRIPTION

Finds images from removable media

=head1 FUNCTIONS

Applet related methods are described in L<jive.Applet>. 

=cut
--]]


-- stuff we use
local pairs         = pairs
local oo            = require("loop.simple")
--local debug         = require("jive.utils.debug")
local math          = require("math")
local table         = require("jive.utils.table")
local string        = require("jive.utils.string")
local lfs           = require('lfs')
local Group         = require("jive.ui.Group")
local Keyboard      = require("jive.ui.Keyboard")
local Task          = require("jive.ui.Task")
local Textinput     = require("jive.ui.Textinput")
local Window        = require("jive.ui.Window")
local Surface       = require("jive.ui.Surface")

local log 		= require("jive.utils.log").logger("applet.ImageViewer")
local require = require
local ImageSource	= require("applets.ImageViewer.ImageSource")

module(...)
ImageSourceLocalStorage = oo.class(_M, ImageSource)

function __init(self, applet, paramOverride)
	log:debug("initialize ImageSourceLocalStorage")
	obj = oo.rawnew(self, ImageSource(applet))

	obj.imgFiles = {}
	obj.scanning = false
	
	-- caller can force a path
	if paramOverride and paramOverride.path then
		log:debug("overriding configured image path: ", paramOverride.path)
		obj.pathOverride = paramOverride.path
	end

	if paramOverride and paramOverride.startImage then
		log:debug("start slideshow with image: ", paramOverride.startImage)
		obj.startImage = paramOverride.startImage
	end

	if paramOverride and paramOverride.noRecursion then
		log:debug("don't search subfolders")
		obj.noRecursion = true
	end

	return obj
end

function listNotReadyError(self)
	self:popupMessage(self.applet:string("IMAGE_VIEWER_ERROR"), self.applet:string("IMAGE_VIEWER_CARD_ERROR"))
end

function scanFolder(self, folder)

	if self.scanning then
		return
	end
	
	self.scanning = true
	
	self.task = Task("scanImageFolder", self, function()
		local dirstoscan = { folder }
		local dirsscanned= {}
		local x = 0
	
		for i, nextfolder in pairs(dirstoscan) do

			if not dirsscanned[nextfolder] then
			
				for f in lfs.dir(nextfolder) do

					-- idle this task after every 100 items				
					x = x+1
					if x > 100 then
						x = 0
						self.task:yield()
					end
				
					-- exclude any dot file (hidden files/directories)
					if (string.sub(f, 1, 1) ~= ".") then
				
						local fullpath = nextfolder .. "/" .. f
			
						if (not self.norecursion) and lfs.attributes(fullpath, "mode") == "directory" then
		
							-- push this directory on our list to be scanned
							table.insert(dirstoscan, fullpath)
		
						elseif lfs.attributes(fullpath, "mode") == "file" then
							-- check for supported file type
							if string.find(string.lower(fullpath), "%pjpe*g")
									or string.find(string.lower(fullpath), "%ppng") 
									or string.find(string.lower(fullpath), "%pbmp") 
									or string.find(string.lower(fullpath), "%pgif") then
								
								-- log:info(fullpath)
								table.insert(self.imgFiles, fullpath)
								
								if self.startImage and self.startImage == f then
									self.currentImage = #self.imgFiles - 1
								end
							end
						end
					
					end

					-- 1000 images should be enough...
					if #self.imgFiles > 1000 then
						break
					end
				end
				
				-- don't scan this folder twice - just in case
				dirsscanned[nextfolder] = true
			end

			if #self.imgFiles > 1000 then
				log:warn("we're not going to show more than 1000 pictures - stop here")
				break
			end

			self.task:yield()
		end

		self.scanning = false
	end)
	
	self.task:addTask()
end


function readImageList(self)

	local imgpath = self:getFolder()

	if lfs.attributes(imgpath, "mode") == "directory" then
		self:scanFolder(imgpath)
	end
end

function getFolder(self)
	return self.pathOverride or self.applet:getSettings()["card.path"]
end

function getImage(self)
	if self.imgFiles[self.currentImage] ~= nil then
		local file = self.imgFiles[self.currentImage]
		log:info("Next image in queue: ", file)
		local image = Surface:loadImage(file)
		return image
	end
end

function nextImage(self, ordering)
	oo.superclass(ImageSourceLocalStorage).nextImage(self, ordering)
	self.imgReady = true
end

function previousImage(self, ordering)
	oo.superclass(ImageSourceLocalStorage).previousImage(self, ordering)
	self.imgReady = true
end

function listReady(self)

	if #self.imgFiles > 0 then
		return true
	end

	obj:readImageList()
	return false
end

function getErrorMessage(self)
	return self:getCurrentImagePath() or self.applet:string("IMAGE_VIEWER_CARD_NOT_DIRECTORY")
end


function settings(self, window)

	local imgpath = self.applet:getSettings()["card.path"]

	local textinput = Textinput("textinput", imgpath,
		function(_, value)
			if #value < 4 then
				return false
			end

			log:debug("Input " .. value)
			self.applet:getSettings()["card.path"] = value
			self.applet:getSettings()["source"] = "storage"
			self.applet:storeSettings()
			
			window:playSound("WINDOWSHOW")
			window:hide(Window.transitionPushLeft)

			if lfs.attributes(value, "mode") ~= "directory" then
				log:warn("Invalid folder name: " .. value)
				self:popupMessage(self.applet:string("IMAGE_VIEWER_ERROR"), self.applet:string("IMAGE_VIEWER_CARD_NOT_DIRECTORY"))
			end

			return true
		end)
	local backspace = Keyboard.backspace()
	local group = Group('keyboard_textinput', { textinput = textinput, backspace = backspace } )

	window:addWidget(group)
	window:addWidget(Keyboard('keyboard', 'qwerty', textinput))
	window:focusWidget(group)

	self:_helpAction(window, "IMAGE_VIEWER_CARD_PATH_HELP", "IMAGE_VIEWER_CARD_PATH_HELP")

	return window
end

function free(self)
	if self.task then
		self.task:removeTask()
	end
end

--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.


=cut
--]]

