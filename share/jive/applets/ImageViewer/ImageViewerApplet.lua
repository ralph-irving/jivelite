
--[[
=head1 NAME

applets.ImageViewer.ImageViewerApplet - Slideshow of images from a directory

=head1 DESCRIPTION

Finds images from removable media and displays them as a slideshow

=head1 FUNCTIONS

Applet related methods are described in L<jive.Applet>. 

=cut
--]]


-- stuff we use
local ipairs, tostring, collectgarbage, bit = ipairs, tostring, collectgarbage, bit

local os			= require("os")
local oo			= require("loop.simple")
local math			= require("math")
local lfs			= require("lfs")
local table			= require("jive.utils.table")
local string		= require("jive.utils.string")

local Applet		= require("jive.Applet")
local appletManager	= require("jive.AppletManager")
local Framework		= require("jive.ui.Framework")
local Font			= require("jive.ui.Font")
local Icon			= require("jive.ui.Icon")
local Textarea      = require("jive.ui.Textarea")
local Label			= require("jive.ui.Label")
local Group			= require("jive.ui.Group")
local RadioButton	= require("jive.ui.RadioButton")
local RadioGroup	= require("jive.ui.RadioGroup")
local Surface		= require("jive.ui.Surface")
local Window		= require("jive.ui.Window")
local SimpleMenu	= require("jive.ui.SimpleMenu")
local Popup 		= require("jive.ui.Popup")
local ContextMenuWindow= require("jive.ui.ContextMenuWindow")
local Timer			= require("jive.ui.Timer")
local Task          = require("jive.ui.Task")
local System        = require("jive.System")

--local debug			= require("jive.utils.debug")

local ImageSource		= require("applets.ImageViewer.ImageSource")
local ImageSourceLocalStorage = require("applets.ImageViewer.ImageSourceLocalStorage")
local ImageSourceCard	= require("applets.ImageViewer.ImageSourceCard")
local ImageSourceUSB	= require("applets.ImageViewer.ImageSourceUSB")
local ImageSourceHttp	= require("applets.ImageViewer.ImageSourceHttp")
-- local ImageSourceFlickr	= require("applets.ImageViewer.ImageSourceFlickr")
local ImageSourceServer	= require("applets.ImageViewer.ImageSourceServer")

local FRAME_RATE       = jive.ui.FRAME_RATE
local LAYER_FRAME      = jive.ui.LAYER_FRAME
local LAYER_CONTENT    = jive.ui.LAYER_CONTENT

--local jiveMain = jiveMain

local MIN_SCROLL_INTERVAL = 750

module(..., Framework.constants)
oo.class(_M, Applet)

local transitionBoxOut
local transitionTopDown 
local transitionBottomUp 
local transitionLeftRight
local transitionRightLeft

function init(self)
	-- migrate old <7.5.1 rotation value (yes|no|auto) to boolean
	-- set to true if device can rotate and pref is set to auto or yes
	local rotation = tostring(self:getSettings()["rotation"])
	local deviceCanRotate = System:hasDeviceRotation()
	self:setRotation(deviceCanRotate and (rotation == "true" or rotation == "yes" or rotation == "auto"))
end

function initImageSource(self, imgSourceOverride)
	log:info("init image viewer")

	self.imgSource = nil
	self.listCheckCount = 0
	self.imageCheckCount = 0
	self.initialized = false
	self.isRendering = false
	self.dragStart = -1
	self.dragOffset = 0
	self.imageError = nil

	self:setImageSource(imgSourceOverride)

	self.transitions = { transitionBoxOut, transitionTopDown, transitionBottomUp, transitionLeftRight, transitionRightLeft, 
		Window.transitionFadeIn, Window.transitionPushLeft, Window.transitionPushRight }
end

function setImageSource(self, imgSourceOverride)
	if imgSourceOverride then
		self.imgSource = imgSourceOverride
	else
		local src = self:getSettings()["source"]

		if src == "storage" then
			self.imgSource = ImageSourceLocalStorage(self)
		elseif src == "usb" then
			self.imgSource = ImageSourceUSB(self)
		elseif src == "card" then
			self.imgSource = ImageSourceCard(self)
-- Flickr is now being served by mysb.com, disable standalone applet
-- 		elseif src == "flickr" then
-- 			self.imgSource = ImageSourceFlickr(self)
		-- default to web list - it's available on all players
		else
			self.imgSource = ImageSourceHttp(self)
		end
	end
end

function openImageViewer(self)
	local window = Window("text_list", self:string('IMAGE_VIEWER'))
	local imgpath = self:getSettings()["card.path"] or "/media"
	
	local menu = SimpleMenu("menu", {
		{
			text = self:string("IMAGE_VIEWER_START_SLIDESHOW"), 
			sound = "WINDOWSHOW",
			callback = function(event, menuItem)
				self:startSlideshow(false)
				return EVENT_CONSUME
			end
		},
		{
			text = self:string("IMAGE_VIEWER_SETTINGS"), 
			sound = "WINDOWSHOW",
			callback = function()
				self:openSettings()
				return EVENT_CONSUME
			end
		},
	})
	
	if System:hasLocalStorage() then
		menu:insertItem({
			text = self:string("IMAGE_VIEWER_BROWSE_MEDIA"), 
			sound = "WINDOWSHOW",
			callback = function(event, menuItem)
				self:browseFolder(imgpath)
				return EVENT_CONSUME
			end
		}, 1)
	end
	
	window:addWidget(menu)
	self:tieAndShowWindow(window)
	return window
end

function browseFolder(self, folder, title)
	local window = Window("text_list", title or folder)

	log:info("Browse folder for images: " .. folder)

	-- verify validity of the directory
	if lfs.attributes(folder, "mode") ~= 'directory' then
		local text = Textarea("text", tostring(self:string("IMAGE_VIEWER_INVALID_FOLDER")) .. "\n" .. folder)
	
		window:addWidget(text)
		self:tieAndShowWindow(window)
		return window
	end	

	local menu = SimpleMenu("menu")

	for f in lfs.dir(folder) do
		-- exclude any dot file (hidden files/directories)
		if (string.sub(f, 1, 1) ~= ".") then
	
			local fullpath = folder .. "/" .. f

			if lfs.attributes(fullpath, "mode") == "directory" then
				menu:addItem({
					text = f,
					sound = "WINDOWSHOW",
--					icon = "icon_folder",
					callback = function()
						self:browseFolder(fullpath, f)
					end
				})

			elseif lfs.attributes(fullpath, "mode") == "file" then
				-- check for supported file type
				if string.find(string.lower(fullpath), "%pjpe*g")
						or string.find(string.lower(fullpath), "%ppng") 
						or string.find(string.lower(fullpath), "%pbmp") 
						or string.find(string.lower(fullpath), "%pgif") then
					-- log:info(fullpath)
					menu:addItem({
						text = f,
						sound = "WINDOWSHOW",
						style = "item_no_arrow",
						callback = function()
							self:startSlideshow(false, ImageSourceLocalStorage(self, {
								path = folder,
								startImage = f,
								noRecursion = true
							}))
						end
					})
				end
			end
		
		end
	end

	if menu:numItems() > 0 then
		-- allow setting the path for the screensaver mode from a folder context menu
		window:addActionListener("add", menu, function (menu)
			local item = menu:getSelectedItem()
			local path = folder
			
			if item:getWidgetValue('text') then
				path = path .. '/' .. item:getWidgetValue('text')

				-- if current item is a file, use its folder
				if lfs.attributes(path, "mode") == "file" then
					path = folder
				end
			end
			
			if item and path and lfs.attributes(path, "mode") == "directory" then
				local window = ContextMenuWindow(self:string("IMAGE_VIEWER"))
		
				local menu = SimpleMenu("menu", {
					{
						text = tostring(self:string("IMAGE_VIEWER_CURRENT_FOLDER")) .. "\n" .. path,
						style = "item_info"
					},
					{
						text = self:string("IMAGE_VIEWER_USE_FOLDER"),
						sound = "CLICK",
						callback = function()
							self:getSettings()["card.path"] = path
							self:getSettings()["source"] = "storage"
							self:storeSettings()
							window:hide()
							return EVENT_CONSUME
						end
					},
				})
				
				window:addWidget(menu)
				window:show()
			end 

			return EVENT_CONSUME
		end)
		window:addWidget(menu)
	else
		window:addWidget(Textarea("text", self:string("IMAGE_VIEWER_EMPTY_LIST")))
	end
	
	self:tieAndShowWindow(window)
	return window
end


function startScreensaver(self)
	log:info("start standard image viewer screensaver")
	self:startSlideshow(true)
end

function startSlideshow(self, isScreensaver, imgSourceOverride)
	log:info("start image viewer")

	-- initialize the chosen image source
	self:initImageSource(imgSourceOverride)
	self.initialized = true
	self.isScreensaver = isScreensaver and true or false
	self:showInitWindow()
	self:startSlideshowWhenReady()
end


function showInitWindow(self)
	local popup = Window("black_popup", "")

	popup:setAutoHide(true)
	popup:setShowFrameworkWidgets(false)
	
	local icon = self.imgSource:updateLoadingIcon()
	if icon then
		popup:addWidget(icon)
	end

	local sublabel = Label("subtext", self:string("IMAGE_VIEWER_LOADING"))
	popup:addWidget(sublabel)

	self:applyScreensaverWindow(popup)
	popup:addListener(bit.bor(EVENT_KEY_PRESS, EVENT_MOUSE_PRESS),
			function()
				popup:playSound("WINDOWHIDE")
				popup:hide()
			end)

	popup:addListener(bit.bor(EVENT_WINDOW_PUSH, EVENT_WINDOW_POP),
			function(event)
				return EVENT_CONSUME
			end)
			
	self.initWindow = popup
			
	self:tieAndShowWindow(popup, Window.transitionFadeIn)
end

function startSlideshowWhenReady(self)
	-- stop timer
	if self.nextSlideTimer ~= nil then
		self.nextSlideTimer:stop()
	end

	if not self.imgSource:listReady() then
		self.listCheckCount = self.listCheckCount + 1

		log:debug("self.listCheckCount: ", self.listCheckCount)

		if self.listCheckCount == 50 then
			if self.nextSlideTimer ~= nil then
				self.nextSlideTimer:stop()
			end
			self.imgSource:listNotReadyError()
			return
		end

		-- try again in a few moments
		log:debug("image list not ready yet...")
		self.nextSlideTimer = Timer(200,
			function()
				self:startSlideshowWhenReady()
			end,
			true)
		self.nextSlideTimer:restart()		
		return
	end

	-- image list is ready
	self.imgSource:nextImage(self:getSettings()["ordering"])
	self:displaySlide()
end

function showTextWindow(self)
	local window = ContextMenuWindow(self:string("IMAGE_VIEWER"))

	local menu = SimpleMenu("menu", {
		{
			text = self:string("IMAGE_VIEWER_SAVE_WALLPAPER"),
			sound = "CLICK",
			callback = function()
				self:_setWallpaper(window)
				return EVENT_CONSUME
			end
		},
	})
	
	local info = self.imgSource:getMultilineText()
	for x, line in ipairs(string.split("\n", info)) do
		if line > "" then
			menu:addItem({
				text = line,
				style = "item_no_arrow",
			})
		end
	end

	window:addWidget(menu)

	window:addActionListener("back", self, 
		function ()
			window:hide()
			return EVENT_CONSUME
		end)

	window:show() 
end

function _setWallpaper(self, window)
	window:hide()

	local screenWidth, screenHeight = Framework:getScreenSize()
	local prefix
	if screenWidth == 320 and screenHeight == 240 then
		prefix = 'bb_'
	elseif screenWidth == 240 and screenHeight == 240 then
		prefix = 'pir_'
	elseif screenWidth == 240 and screenHeight == 320 then
		prefix = 'jive_'
	elseif screenWidth == 480 and screenHeight == 272 then
		prefix = 'fab4_'
	elseif screenWidth == 800 and screenHeight == 480 then
		prefix = 'pcp_'
	else
		prefix = System:getMachine() .. '_'
	end
	
	prefix = prefix .. tostring(self:string("IMAGE_VIEWER_SAVED_SLIDE"))
	
	local path  = System.getUserDir().. "/wallpapers/"
	local file  = prefix .. " " .. tostring(os.date('%Y%m%d%H%M%S')) .. ".bmp"

	log:info("Taking screenshot: " .. path .. file)

	-- take screenshot
	local sw, sh = Framework:getScreenSize()
	local srf = Surface:newRGB(sw, sh)
	self.window:draw(srf, LAYER_ALL)
	srf:saveBMP(path .. file)

--[[ disable popup for now, as something's broken - it wouldn't be shown at all
	local popup = Popup("toast_popup")
	local group = Group("group", {
		text = Label("text", self:string("IMAGE_VIEWER_WALLPAPER_SET", file))
	})
	popup:addWidget(group)

	popup:addTimer(3000, function()
		popup:hide()
	end)
	self:tieAndShowWindow(popup)
]]--

	local player = appletManager:callService("getCurrentPlayer")
	if player then
		player = player:getId()
	end

	appletManager:callService("setBackground", path .. file, player, true)

	-- remove old screenshots, only keep one to make sure we don't run out of disk space
	-- XXX enable more wallpaper files once we have a way to remove them without using ssh...
	local pattern = string.lower(prefix) .. ".*" .. "\\" .. ".bmp"
	for img in lfs.dir(path) do
		if string.find(string.lower(img), pattern) and string.lower(img) ~= string.lower(file) then
			log:warn("removing old saved wallpaper: ", img)
			os.remove(path .. img)
		end 
	end
end

function setupEventHandlers(self, window)

	local nextSlideAction = function (self)
		if self.imgSource:imageReady() and not self.isRendering then
			log:debug("request next slide")
			self.imgSource:nextImage(self:getSettings()["ordering"])
			self:displaySlide()
		else
			log:warn("don't show next image - current image isn't even ready yet")
		end
		return EVENT_CONSUME
	end

	local previousSlideAction = function (self, window)
		if self.imgSource:imageReady() and not self.isRendering then
			log:debug("request prev slide")
			self.useFastTransition = true
			self.imgSource:previousImage(self:getSettings()["ordering"])
			self:displaySlide()
		else
			log:warn("don't show next image - current image isn't even ready yet")
		end
		return EVENT_CONSUME
	end

	local showTextWindowAction = function (self)
		self:showTextWindow()
		return EVENT_CONSUME
	end

	--todo add takes user to meta data page
	window:addActionListener("add", self, showTextWindowAction)
	window:addActionListener("go", self, nextSlideAction)
	window:addActionListener("up", self, nextSlideAction)
	window:addActionListener("down", self, previousSlideAction)
	window:addActionListener("back", self, function () return EVENT_UNUSED end)

	window:addListener(EVENT_MOUSE_PRESS,
		function(event)
			if self.dragOffset > 10 then
				local x, y = event:getMouse()
				local offset = y - self.dragStart
				
				log:debug("drag offset: ", offset)
				if offset > 10 then
					previousSlideAction(self)
				elseif offset < -10 then
					nextSlideAction(self)
				end				

				self.dragStart = -1
				self.dragOffset = 0

				return EVENT_CONSUME
				
			else
				-- on simple tapping the screen we'll wake up
				self:closeRemoteScreensaver()
			end

			return EVENT_UNUSED
		end
	)
	
	window:addListener(EVENT_MOUSE_HOLD,
		function(event)
			showTextWindowAction(self)
			return EVENT_CONSUME
		end
	)
	
	window:addListener(EVENT_MOUSE_DRAG,
		function(event)
			if self.dragStart < 0 then
				local x, y = event:getMouse()
				self.dragStart = y
			end

			self.dragOffset = self.dragOffset + 1
			return EVENT_CONSUME
		end
	)
	
	window:addListener(EVENT_SCROLL,
		function(event)
			local scroll = event:getScroll()

			local dir
			if scroll > 0 then
				dir = 1
			else
				dir = -1
			end
			local now = Framework:getTicks()
			if not self.lastScrollT or
				self.lastScrollT + MIN_SCROLL_INTERVAL < now or
				self.lastScrollDir ~= dir then
				--scrolling a lot or a little only moves by one, since image fetching is relatively slow
				self.lastScrollT = now
				self.lastScrollDir = dir
				if scroll > 0 then
					return nextSlideAction(self)
				else
					return previousSlideAction(self)
				end
			end
			return EVENT_CONSUME
		end
	)
end


--service method
function registerRemoteScreensaver(self, serverData)
	serverData.isScreensaver = true
	
	appletManager:callService("addScreenSaver",
			serverData.text,
			"ImageViewer",
			"openRemoteScreensaver", _, _, 100,
			"closeRemoteScreensaver",
			serverData,
			serverData.id
		)
end

--service method
function unregisterRemoteScreensaver(self, id)
	appletManager:callService("removeScreenSaver", "ImageViewer", "openRemoteScreensaver", _, id)
end


function openRemoteScreensaver(self, force, serverData)
	self:startSlideshow(serverData.isScreensaver, ImageSourceServer(self, serverData))
end

function closeRemoteScreensaver(self)
	self:_stopTimers()
	
	if self.initWindow then
		self.initWindow:hide()
		self.initWindow = nil
	end

	if self.window then
		self.window:hide()
		self.window = nil
	end
end

-- callbacks called from media manager
function mmImageViewerMenu(self, devName)
	local imgpath = self:getSettings()["card.path"] or "/media"

	log:info('mmImageViewerMenu: ', imgpath .. devName)
	self:startSlideshow(false, ImageSourceLocalStorage(self, { path = imgpath .. devName }))
end

function mmImageViewerBrowse(self, devName)
	local imgpath = self:getSettings()["card.path"] or "/media"

	log:info('mmImageViewerBrowse: ', imgpath .. devName)
	self:browseFolder(imgpath .. devName)
end

function free(self)
	log:info("destructor of image viewer")
	if self.task then
		self.task:removeTask()
	end

	if self.window then
		self.window:setAllowScreensaver(true)
	end

	self:_stopTimers()

	if self.imgSource ~= nil then
		self.imgSource:free()
	end

	return true
end

function _stopTimers(self)
	if self.nextSlideTimer then
		self.nextSlideTimer:stop()
	end
	if self.checkFotoTimer then
		self.checkFotoTimer:stop()
	end
end

function applyScreensaverWindow(self, window)
	if self.serverData and not self.serverData.allowMotion then
		window:addListener(EVENT_MOTION,
			function()
				window:hide(Window.transitionNone)
				return EVENT_CONSUME
			end)
	end

	window:setAllowScreensaver(false)

	local manager = appletManager:getAppletInstance("ScreenSavers")
	manager:screensaverWindow(window, true, {"add", "go", "up", "down", "back"}, _, 'ImageViewer')
end


function displaySlide(self)
	if not self.initialized then
		self:initImageSource()
		self.initialized = true
	end

	-- stop timer
	if self.checkFotoTimer then
		self.checkFotoTimer:stop()
	end

	if self.nextSlideTimer and self.nextSlideTimer:isRunning() then
		--restart next slide timer to give this image a chance, can happen when displaySlide was manually trigger
		self.nextSlideTimer:restart()
	end

	if not self.imgSource:imageReady() and self.imageCheckCount < 50 then
		self.imageCheckCount = self.imageCheckCount + 1
		
		-- try again in a few moments
		log:debug("image not ready, try again...")

		if not self.checkFotoTimer then
			self.checkFotoTimer = Timer(200, --hmm, this seems to enforce a second wait even if response is fast....
				function()
					self:displaySlide()
				end,
				true)
		end
		self.checkFotoTimer:restart()
		return
	end
	
	self.imageCheckCount = 0

	log:debug("image rendering")
	self.isRendering = true

	--stop next slider Timer since a) we have a good image and, b) this call to displaySlide may have been manually triggered
	if self.nextSlideTimer then
		self.nextSlideTimer:stop()
	end

	self.task = Task("renderImage", self, function() self:_renderImage() end)
	self.task:addTask()
end

function _renderImage(self)
	-- get device orientation and features
	local screenWidth, screenHeight = Framework:getScreenSize()
	
	local rotation = self:getSettings()["rotation"]
	local fullScreen = self:getSettings()["fullscreen"]
	local ordering = self:getSettings()["ordering"]
	local textinfo = self:getSettings()["textinfo"]

	local deviceLandscape = ((screenWidth/screenHeight) > 1)

	local image = self.imgSource:getImage()
	local w, h;
	
	if image ~= nil then
		w, h = image:getSize()
	end

	-- give SP some time to breath...	
	self.task:yield()

	if image ~= nil and w > 0 and h > 0 then
	
		self.imageError = nil
	
		if self.imgSource:useAutoZoom() then
			local imageLandscape = ((w/h) > 1)

			-- determine whether to rotate
			if rotation then
				-- rotation allowed
				if deviceLandscape ~= imageLandscape then
					-- rotation needed, so let's do it
					image = image:rotozoom(-90, 1, 1)
					w, h = image:getSize()

					-- rotating the image is exhausting...	
					self.task:yield()
				end
			end

			-- determine scaling factor
			local zoomX = screenWidth / w
			local zoomY = screenHeight / h
			local zoom = 1

			--[[
			log:info("pict " .. w .. "x" .. h)
			log:info("screen " .. screenWidth .. "x" .. screenHeight)
			log:info("zoomX " .. zoomX)
			log:info("zoomY " .. zoomY)
			log:info("deviceCanRotate " .. tostring(deviceCanRotate))
			log:info("rotation " .. rotation)
			log:info("fullscreen " .. tostring(fullScreen))
			--]]

			if fullScreen then
				zoom = math.max(zoomX, zoomY)
			else
				zoom = math.min(zoomX, zoomY)
			end

			-- scale image if needed
			if zoom ~= 1 then
				image = image:rotozoom(0, zoom, 1)
				w, h = image:getSize()
			end

			-- zooming is hard work!	
			self.task:yield()
		end

		-- place scaled image centered to empty picture
		local totImg = Surface:newRGBA(screenWidth, screenHeight)
		totImg:filledRectangle(0, 0, screenWidth, screenHeight, 0x000000FF)
		local x, y = math.floor ((screenWidth - w) / 2), math.floor ((screenHeight - h) / 2)

		-- draw image
		image:blit(totImg, x, y)

		image = totImg

		if textinfo then
			-- add text to image
			local txtLeft, txtCenter, txtRight = self.imgSource:getText()

			if txtLeft or txtCenter or txtRight then
				image:filledRectangle(0,screenHeight-20,screenWidth,screenHeight, 0x000000FF)
				local fontBold = Font:load("fonts/FreeSansBold.ttf", 10)
				local fontRegular = Font:load("fonts/FreeSans.ttf", 10)

				if txtLeft then
					-- draw left text
					local txt1 = Surface:drawText(fontBold, 0xFFFFFFFF, txtLeft)
					txt1:blit(image, 5, screenHeight-15 - fontBold:offset())
				end

				if txtCenter then
					-- draw center text
					local titleWidth = fontRegular:width(txtCenter)
					local txt2 = Surface:drawText(fontRegular, 0xFFFFFFFF, txtCenter)
					txt2:blit(image, (screenWidth-titleWidth)/2, screenHeight-15-fontRegular:offset())
				end

				if txtRight then
					-- draw right text
					local titleWidth = fontRegular:width(txtRight)
					local txt3 = Surface:drawText(fontRegular, 0xFFFFFFFF, txtRight)
					txt3:blit(image, screenWidth-5-titleWidth, screenHeight-15-fontRegular:offset())
				end
			end
		end

		local window = Window('window')
		window:addWidget(Icon("icon", image))

		-- give SP some time to breath...	
		self.task:yield()

		if self.isScreensaver then
			self:applyScreensaverWindow(window)
		else
			self:setupEventHandlers(window)
		end

		-- replace the window if it's already there
		if self.window then
			self:tieWindow(window)
			local transition
			if self.useFastTransition then
				transition = Window.transitionFadeIn
				self.useFastTransition = false
			else
				transition = self:getTransition()
			end
			self.window = window
			self.window:showInstead(transition)
		-- otherwise it's new
		else
			self.window = window
			self:tieAndShowWindow(window, window.transitionFadeIn) -- fade in for smooth consistent start 
		end

		-- no screensavers por favor
		self.window:setAllowScreensaver(false)

		--no iconbar
		self.window:setShowFrameworkWidgets(false)

	else
		if self.imageError == nil then
			self.imageError = tostring(self.imgSource:getErrorMessage())
			log:error("Invalid image object found: " .. self.imageError)

			local popup = self.imgSource:popupMessage(self:string("IMAGE_VIEWER_INVALID_IMAGE"), self.imageError)
			popup:addTimer(self:getSettings()["delay"], function()
				popup:hide()
				popup = nil
			end)
		end
	end

	-- start timer for next photo in 'delay' milliseconds
	local delay = self:getSettings()["delay"]
	self.nextSlideTimer = self.window:addTimer(delay,
		function()
			self.imgSource:nextImage(self:getSettings()["ordering"])
			self:displaySlide()
		end
	)
	

	log:debug("image rendering done")

	-- free memory as quickly as possible - resizing large images might have consumed a lot of it
	collectgarbage("collect")

	self.isRendering = false
	self.task:removeTask()
end


-- Configuration menu

function openSettings(self)
	log:info("image viewer settings")
	self:initImageSource()
	
	local window = Window("text_list", self:string("IMAGE_VIEWER_SETTINGS"), 'settingstitle')

	local settingsMenu = {
		{
			text = self:string("IMAGE_VIEWER_SOURCE_SETTINGS"), 
			sound = "WINDOWSHOW",
			callback = function(event, menuItem)
				self:sourceSpecificSettings(menuItem)
				return EVENT_CONSUME
			end
		},
		{
			text = self:string("IMAGE_VIEWER_DELAY"),
			sound = "WINDOWSHOW",
			callback = function(event, menuItem)
				self:defineDelay(menuItem)
				return EVENT_CONSUME
			end
		},
		{
			text = self:string("IMAGE_VIEWER_ORDERING"),
			sound = "WINDOWSHOW",
			callback = function(event, menuItem)
				self:defineOrdering(menuItem)
				return EVENT_CONSUME
			end
		},
		{
			text = self:string("IMAGE_VIEWER_TRANSITION"),
			sound = "WINDOWSHOW",
			callback = function(event, menuItem)
				self:defineTransition(menuItem)
				return EVENT_CONSUME
			end
		},
		{
			text = self:string("IMAGE_VIEWER_ZOOM"),
			sound = "WINDOWSHOW",
			callback = function(event, menuItem)
				self:defineFullScreen(menuItem)
				return EVENT_CONSUME
			end
		},
		{
			text = self:string("IMAGE_VIEWER_TEXTINFO"),
			sound = "WINDOWSHOW",
			callback = function(event, menuItem)
				self:defineTextInfo(menuItem)
				return EVENT_CONSUME
			end
		},
	}
	
	if System:hasDeviceRotation() then
		table.insert(settingsMenu, 5, {
			text = self:string("IMAGE_VIEWER_ROTATION"),
			sound = "WINDOWSHOW",
			callback = function(event, menuItem)
				self:defineRotation(menuItem)
				return EVENT_CONSUME
			end
		})
	end
	
	-- no need for a source setting on baby - we don't have any choice
	if System:hasLocalStorage() then
		table.insert(settingsMenu, 1, {
			text = self:string("IMAGE_VIEWER_SOURCE"), 
			sound = "WINDOWSHOW",
			callback = function(event, menuItem)
				self:defineSource(menuItem)
				return EVENT_CONSUME
			end
		})
	end
	
	window:addWidget(SimpleMenu("menu", settingsMenu))

	self:tieAndShowWindow(window)
	return window
end


function sourceSpecificSettings(self, menuItem)
	local window = Window("window", menuItem.text)

	window = self.imgSource:settings(window)

	self:tieAndShowWindow(window)
	return window
end

function defineOrdering(self, menuItem)
	local group = RadioGroup()

	local trans = self:getSettings()["ordering"]
	
	local window = Window("text_list", menuItem.text, 'settingstitle')
	window:addWidget(SimpleMenu("menu",
	{
            {
                text = self:string("IMAGE_VIEWER_ORDERING_SEQUENTIAL"),
		style = 'item_choice',
                check = RadioButton(
                    "radio",
                    group,
                    function()
                        self:setOrdering("sequential")
                    end,
                    trans == "sequential"
                ),
            },
            {
                text = self:string("IMAGE_VIEWER_ORDERING_RANDOM"),
		style = 'item_choice',
                check = RadioButton(
                    "radio",
                    group,
                    function()
                        self:setOrdering("random")
                    end,
                    trans == "random"
                )
			},
		}))

	self:tieAndShowWindow(window)
	return window
end

function defineTransition(self, menuItem)
	local group = RadioGroup()

	local trans = self:getSettings()["transition"]
	
	local window = Window("text_list", menuItem.text, 'settingstitle')
	window:addWidget(SimpleMenu("menu",
	{
            {
                text = self:string("IMAGE_VIEWER_TRANSITION_RANDOM"),
		style = 'item_choice',
                check = RadioButton(
                    "radio",
                    group,
                    function()
                        self:setTransition("random")
                    end,
                    trans == "random"
                ),
            },
            {
                text = self:string("IMAGE_VIEWER_TRANSITION_FADE"),
		style = 'item_choice',
                check = RadioButton(
                    "radio",
                    group,
                    function()
                        self:setTransition("fade")
                    end,
                    trans == "fade"
                )
	},
            {
                text = self:string("IMAGE_VIEWER_TRANSITION_INSIDE_OUT"),
		style = 'item_choice',
                check = RadioButton(
                    "radio",
                    group,
                    function()
                        self:setTransition("boxout")
                    end,
                    trans == "boxout"
                )
	},
 			{
                text = self:string("IMAGE_VIEWER_TRANSITION_TOP_DOWN"),
		style = 'item_choice',
				check = RadioButton(
				   "radio", 
				   group, 
				   function() 
					   self:setTransition("topdown") 
				   end,
				   trans == "topdown"
				),
			},
			{ 
                text = self:string("IMAGE_VIEWER_TRANSITION_BOTTOM_UP"),
		style = 'item_choice',
				check = RadioButton(
				   "radio", 
				   group, 
				   function() 
					   self:setTransition("bottomup") 
				   end,
				   display == "bottomup"
				),
			},
			{ 
                text = self:string("IMAGE_VIEWER_TRANSITION_LEFT_RIGHT"),
		style = 'item_choice',
				check = RadioButton(
				   "radio", 
				   group, 
				   function() 
					   self:setTransition("leftright") 
				   end,
				   trans == "leftright"
				),
			},
			{ 
                text = self:string("IMAGE_VIEWER_TRANSITION_RIGHT_LEFT"),
		style = 'item_choice',
				check = RadioButton(
				   "radio", 
				   group, 
				   function() 
					   self:setTransition("rightleft") 
				   end,
				   trans == "rightleft"
				),
			},
			{ 
                text = self:string("IMAGE_VIEWER_TRANSITION_PUSH_LEFT"),
		style = 'item_choice',
				check = RadioButton(
				   "radio", 
				   group, 
				   function() 
					   self:setTransition("pushleft") 
				   end,
				   trans == "pushleft"
				),
			},
			{ 
                text = self:string("IMAGE_VIEWER_TRANSITION_PUSH_RIGHT"),
		style = 'item_choice',
				check = RadioButton(
				   "radio", 
				   group, 
				   function() 
					   self:setTransition("pushright") 
				   end,
				   trans == "pushright"
				),
			},
		}))

	self:tieAndShowWindow(window)
	return window
end


function defineSource(self, menuItem)
	local group = RadioGroup()

	local source = self:getSettings()["source"]
	
	local sourceMenu = {
		{
			text = self:string("IMAGE_VIEWER_SOURCE_HTTP"),
			style = 'item_choice',
				check = RadioButton(
					 "radio",
					 group,
					 function()
						self:setSource("http")
					 end,
					 source == "http"
				),
		},

		{
			text = self:string("IMAGE_VIEWER_SOURCE_FLICKR"), 
			style = 'item_choice',
			check = RadioButton(
				"radio", 
				group, 
				function() 
					self:setSource("flickr")
				end,
				source == "flickr"
			),
		},
	}
	
	-- add support for local media if available
	if System:hasSDCard() then
		table.insert(sourceMenu, 1, {
			text = self:string("IMAGE_VIEWER_SOURCE_CARD"),
			style = 'item_choice',
			check = RadioButton(
				"radio",
				group,
				function()
					self:setSource("card")
				end,
				source == "card"
			)
		})
	end

	if System:hasUSB() then
		table.insert(sourceMenu, 1, {
			text = self:string("IMAGE_VIEWER_SOURCE_USB"),
			style = 'item_choice',
			check = RadioButton(
				"radio",
				group,
				function()
					self:setSource("usb")
				end,
				source == "usb"
			)
		})
	end

	if System:hasLocalStorage() then
		table.insert(sourceMenu, 1, {
			text = self:string("IMAGE_VIEWER_SOURCE_LOCAL_STORAGE"),
			style = 'item_choice',
			check = RadioButton(
				"radio",
				group,
				function()
					self:setSource("storage")
				end,
				source == "storage"
			)
		})
	end

	local window = Window("text_list", menuItem.text, 'settingstitle')
	window:addWidget(SimpleMenu("menu", sourceMenu))

	self:tieAndShowWindow(window)
	return window
end


function defineDelay(self, menuItem)
	local group = RadioGroup()

	local delay = self:getSettings()["delay"]

	local window = Window("text_list", menuItem.text, 'settingstitle')
	window:addWidget(SimpleMenu("menu",
		{
			{
				text = self:string("IMAGE_VIEWER_DELAY_5_SEC"),
				style = 'item_choice',
				check = RadioButton("radio", group, function() self:setDelay(5000) end, delay == 5000),
			},
			{
				text = self:string("IMAGE_VIEWER_DELAY_10_SEC"),
				style = 'item_choice',
				check = RadioButton("radio", group, function() self:setDelay(10000) end, delay == 10000),
			},
			{ 
				text = self:string("IMAGE_VIEWER_DELAY_20_SEC"),
				style = 'item_choice',
				check = RadioButton("radio", group, function() self:setDelay(20000) end, delay == 20000),
			},
			{ 
				text = self:string("IMAGE_VIEWER_DELAY_30_SEC"),
				style = 'item_choice',
				check = RadioButton("radio", group, function() self:setDelay(30000) end, delay == 30000),
			},
			{
				text = self:string("IMAGE_VIEWER_DELAY_1_MIN"),
				style = 'item_choice',
				check = RadioButton("radio", group, function() self:setDelay(60000) end, delay == 60000),
			},
		}))

	self:tieAndShowWindow(window)
	return window
end


function defineFullScreen(self, menuItem)
	local group = RadioGroup()

	local fullscreen = self:getSettings()["fullscreen"]
	
	local window = Window("text_list", menuItem.text, 'settingstitle')
	window:addWidget(SimpleMenu("menu",
		{
            {
                text = self:string("IMAGE_VIEWER_ZOOM_PICTURE"),
		style = 'item_choice',
                check = RadioButton(
                    "radio",
                    group,
                    function()
                        self:setFullScreen(false)
                    end,
                    fullscreen == false
	            ),
            },
            {
                text = self:string("IMAGE_VIEWER_ZOOM_SCREEN"),
		style = 'item_choice',
                check = RadioButton(
                    "radio",
                    group,
                    function()
                        self:setFullScreen(true)
                    end,
                    fullscreen == true
	            ),
            },           
		}))

	self:tieAndShowWindow(window)
	return window
end


function defineRotation(self, menuItem)
	local group = RadioGroup()

	local rotation = self:getSettings()["rotation"]
	
	local window = Window("text_list", menuItem.text, 'settingstitle')
	window:addWidget(SimpleMenu("menu",
		{
            {
                text = self:string("IMAGE_VIEWER_ROTATION_YES"),
		style = 'item_choice',
                check = RadioButton(
                    "radio",
                    group,
                    function()
                        self:setRotation(true)
                    end,
                    rotation
	            ),
            },
            {
                text = self:string("IMAGE_VIEWER_ROTATION_NO"),
		style = 'item_choice',
                check = RadioButton(
                    "radio",
                    group,
                    function()
                        self:setRotation(false)
                    end,
                    not rotation
	            ),
            },           
		}))

	self:tieAndShowWindow(window)
	return window
end

function defineTextInfo(self, menuItem)
	local group = RadioGroup()

	local textinfo = self:getSettings()["textinfo"]
	
	local window = Window("text_list", menuItem.text, 'settingstitle')
	window:addWidget(SimpleMenu("menu",
		{
            {
                text = self:string("IMAGE_VIEWER_TEXTINFO_YES"),
		style = 'item_choice',
                check = RadioButton(
                    "radio",
                    group,
                    function()
                        self:setTextInfo(true)
                    end,
                    textinfo == true
	            ),
            },
            {
                text = self:string("IMAGE_VIEWER_TEXTINFO_NO"),
		style = 'item_choice',
                check = RadioButton(
                    "radio",
                    group,
                    function()
                        self:setTextInfo(false)
                    end,
                    textinfo == false
	            ),
            },           
		}))

	self:tieAndShowWindow(window)
	return window
end


-- Configuration helpers

function setOrdering(self, ordering)
	self:getSettings()["ordering"] = ordering
	self:storeSettings()
end

function setDelay(self, delay)
	self:getSettings()["delay"] = delay
	self:storeSettings()
end


function setSource(self, source)
	self:getSettings()["source"] = source
	self:storeSettings()
	self:setImageSource()
end


function setTransition(self, transition)
	self:getSettings()["transition"] = transition
	self:storeSettings()
end


function setRotation(self, rotation)
	self:getSettings()["rotation"] = rotation
	self:storeSettings()
end


function setFullScreen(self, fullscreen)
	self:getSettings()["fullscreen"] = fullscreen
	self:storeSettings()
end

function setTextInfo(self, textinfo)
	self:getSettings()["textinfo"] = textinfo
	self:storeSettings()
end


-- Transitions

function transitionBoxOut(oldWindow, newWindow)
	local frames = FRAME_RATE * 2 -- 2 secs
	local screenWidth, screenHeight = Framework:getScreenSize()
	local incX = screenWidth / frames / 2
	local incY = screenHeight / frames / 2
	local x = screenWidth / 2
	local y = screenHeight / 2
	local i = 0

	return function(widget, surface)
       local adjX = i * incX
       local adjY = i * incY

       newWindow:draw(surface, LAYER_FRAME)
       oldWindow:draw(surface, LAYER_CONTENT)

       surface:setClip(x - adjX, y - adjY, adjX * 2, adjY * 2)
       newWindow:draw(surface, LAYER_CONTENT)

       i = i + 1
       if i == frames then
	       Framework:_killTransition()
       end
    end
end

function transitionBottomUp(oldWindow, newWindow)
    local frames = FRAME_RATE * 2 -- 2 secs
    local screenWidth, screenHeight = Framework:getScreenSize()
    local incY = screenHeight / frames
    local i = 0

    return function(widget, surface)
        local adjY = i * incY

        newWindow:draw(surface, LAYER_FRAME)
        oldWindow:draw(surface, LAYER_CONTENT)

        surface:setClip(0, screenHeight-adjY, screenWidth, screenHeight)
        newWindow:draw(surface, LAYER_CONTENT)

        i = i + 1
        if i == frames then
            Framework:_killTransition()
        end
    end
end

function transitionTopDown(oldWindow, newWindow)
    local frames = FRAME_RATE * 2 -- 2 secs
    local screenWidth, screenHeight = Framework:getScreenSize()
    local incY = screenHeight / frames
    local i = 0

    return function(widget, surface)
        local adjY = i * incY

        newWindow:draw(surface, LAYER_FRAME)
        oldWindow:draw(surface, LAYER_CONTENT)

        surface:setClip(0, 0, screenWidth, adjY)
        newWindow:draw(surface, LAYER_CONTENT)

        i = i + 1
        if i == frames then
            Framework:_killTransition()
        end
    end
end

function transitionLeftRight(oldWindow, newWindow)
    local frames = FRAME_RATE * 2 -- 2 secs
    local screenWidth, screenHeight = Framework:getScreenSize()
    local incX = screenWidth / frames
    local i = 0

    return function(widget, surface)
        local adjX = i * incX

        newWindow:draw(surface, LAYER_FRAME)
        oldWindow:draw(surface, LAYER_CONTENT)

        surface:setClip(0, 0, adjX, screenHeight)
        newWindow:draw(surface, LAYER_CONTENT)

        i = i + 1
        if i == frames then
                Framework:_killTransition()
        end
    end
end

function transitionRightLeft(oldWindow, newWindow)
    local frames = FRAME_RATE * 2 -- 2 secs
    local screenWidth, screenHeight = Framework:getScreenSize()
    local incX = screenWidth / frames
    local i = 0

    return function(widget, surface)
        local adjX = i * incX

        newWindow:draw(surface, LAYER_FRAME)
        oldWindow:draw(surface, LAYER_CONTENT)

        surface:setClip(screenWidth-adjX, 0, screenWidth, screenHeight)
        newWindow:draw(surface, LAYER_CONTENT)

        i = i + 1
        if i == frames then
            Framework:_killTransition()
        end
    end
end

function getTransition(self)
	local transition
	local trans = self:getSettings()["transition"]
	if trans == "random" then
		transition = self.transitions[math.random(#self.transitions)]
	elseif trans == "boxout" then
		transition = transitionBoxOut
	elseif trans == "topdown" then
		transition = transitionTopDown
	elseif trans == "bottomup" then
		transition = transitionBottomUp
	elseif trans == "leftright" then
		transition = transitionLeftRight
	elseif trans == "rightleft" then
		transition = transitionRightLeft
	elseif trans == "fade" then
		transition = Window.transitionFadeIn
	elseif trans == "pushleft" then
		transition = Window.transitionPushLeft
	elseif trans == "pushright" then
		transition = Window.transitionPushRight
	end	
	return transition
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

