--[[
=head1 NAME

jive.JiveMain - Main Jive application.

=head1 DESCRIPTION

TODO

=head1 SYNOPSIS

TODO

=head1 FUNCTIONS

JiveMainMenu notifies any change with mainMenuUpdate

=cut
--]]


-- stuff we use
local math          = require("math")
local os            = require("os")
local coroutine     = require("coroutine")
local oo            = require("loop.simple")

local NetworkThread = require("jive.net.NetworkThread")
local Iconbar       = require("jive.Iconbar")
local AppletManager = require("jive.AppletManager")
local System        = require("jive.System")
local locale        = require("jive.utils.locale")
local SimpleMenu    = require("jive.ui.SimpleMenu")
local Window        = require("jive.ui.Window")
local HomeMenu      = require("jive.ui.HomeMenu")
local Framework     = require("jive.ui.Framework")
local Task          = require("jive.ui.Task")
local Timer         = require("jive.ui.Timer")
local Event         = require("jive.ui.Event")
local table         = require("jive.utils.table")

local Canvas        = require("jive.ui.Canvas")

local _inputToActionMap = require("jive.InputToActionMap")

local debug         = require("jive.utils.debug")
local log           = require("jive.utils.log").logger("jivelite")
local logheap       = require("jive.utils.log").logger("jivelite.heap")


--require("profiler")

local EVENT_IR_ALL         = jive.ui.EVENT_IR_ALL
local EVENT_IR_PRESS       = jive.ui.EVENT_IR_PRESS
local EVENT_IR_DOWN        = jive.ui.EVENT_IR_DOWN
local EVENT_IR_UP          = jive.ui.EVENT_IR_UP
local EVENT_IR_REPEAT      = jive.ui.EVENT_IR_REPEAT
local EVENT_IR_HOLD        = jive.ui.EVENT_IR_HOLD
local EVENT_KEY_ALL        = jive.ui.EVENT_KEY_ALL
local ACTION               = jive.ui.ACTION
local EVENT_ALL_INPUT      = jive.ui.EVENT_ALL_INPUT
local EVENT_MOUSE_ALL      = jive.ui.EVENT_MOUSE_ALL
local EVENT_KEY_PRESS      = jive.ui.EVENT_KEY_PRESS
local EVENT_KEY_UP         = jive.ui.EVENT_KEY_UP
local EVENT_KEY_DOWN       = jive.ui.EVENT_KEY_DOWN
local EVENT_CHAR_PRESS      = jive.ui.EVENT_CHAR_PRESS
local EVENT_KEY_HOLD       = jive.ui.EVENT_KEY_HOLD
local EVENT_SCROLL         = jive.ui.EVENT_SCROLL
local EVENT_WINDOW_RESIZE  = jive.ui.EVENT_WINDOW_RESIZE
local EVENT_UNUSED         = jive.ui.EVENT_UNUSED
local EVENT_CONSUME        = jive.ui.EVENT_CONSUME

local KEY_HOME             = jive.ui.KEY_HOME
local KEY_FWD           = jive.ui.KEY_FWD
local KEY_REW           = jive.ui.KEY_REW
local KEY_GO            = jive.ui.KEY_GO
local KEY_BACK          = jive.ui.KEY_BACK
local KEY_UP            = jive.ui.KEY_UP
local KEY_DOWN          = jive.ui.KEY_DOWN
local KEY_LEFT          = jive.ui.KEY_LEFT
local KEY_RIGHT         = jive.ui.KEY_RIGHT
local KEY_PLAY          = jive.ui.KEY_PLAY
local KEY_PAUSE         = jive.ui.KEY_PAUSE
local KEY_VOLUME_UP     = jive.ui.KEY_VOLUME_UP
local KEY_VOLUME_DOWN   = jive.ui.KEY_VOLUME_DOWN
local KEY_ADD           = jive.ui.KEY_ADD

local JIVE_VERSION      = jive.JIVE_VERSION

-- Classes
local JiveMain = oo.class({}, HomeMenu)


-- strings
local _globalStrings

-- several submenus created by applets (settings, controller settings, extras)
-- should not need to have an id passed when creating it
local _idTranslations = {}

_softPowerState = "on"

-- Squeezebox remote IR codes
local irCodes = {
	[ 0x7689c03f ] = KEY_REW,
	[ 0x7689a05f ] = KEY_FWD,
	[ 0x7689807f ] = KEY_VOLUME_UP,
	[ 0x768900ff ] = KEY_VOLUME_DOWN,
}

--require"remdebug.engine"
--  remdebug.engine.start()
  
local _defaultSkin
local _fullscreen

function JiveMain:goHome()
		local windowStack = Framework.windowStack

		if #windowStack > 1 then
			Framework:playSound("JUMP")
			jiveMain:closeToHome(true)
		else
			Framework:playSound("BUMP")
			windowStack[1]:bumpLeft()
		end
end

function JiveMain:disconnectPlayer( event) --self, event not used in our case, could be left out
	appletManager:callService("setCurrentPlayer", nil)
	JiveMain:goHome()
end


--fallback IR->KEY handler after widgets have had a chance to listen for ir - probably will be removed - still using for rew/fwd and volume for now
local function _irHandler(event)
	local irCode = event:getIRCode()
	local buttonName = Framework:getIRButtonName(irCode)

	if log:isDebug() then
		log:debug("IR event in fallback _irHandler: ", event:tostring(), " button:", buttonName )
	end
	if not buttonName then
		--code may have come from a "foreign" remote that the user is using
		return EVENT_CONSUME
	end

	local keyCode = irCodes[irCode]
	if (keyCode) then
		if event:getType() == EVENT_IR_PRESS  then
			Framework:pushEvent(Event:new(EVENT_KEY_PRESS, keyCode))
			return EVENT_CONSUME
		elseif event:getType() == EVENT_IR_HOLD then
			Framework:pushEvent(Event:new(EVENT_KEY_HOLD, keyCode))
			return EVENT_CONSUME
		elseif event:getType() == EVENT_IR_DOWN  then
			Framework:pushEvent(Event:new(EVENT_KEY_DOWN, keyCode))
			return EVENT_CONSUME
		elseif event:getType() == EVENT_IR_UP  then
			Framework:pushEvent(Event:new(EVENT_KEY_UP, keyCode))
			return EVENT_CONSUME
		end
	end

	return EVENT_UNUSED
end

function _goHomeAction(self)
	JiveMain:goHome()

	return EVENT_CONSUME
end


function _goFactoryTestModeAction(self)
	local key = "factoryTest"

	if jiveMain:getMenuTable()[key] then
		Framework:playSound("JUMP")
		jiveMain:getMenuTable()[key].callback()
	end

	return EVENT_CONSUME
end


function JiveMain:getSoftPowerState()
	return _softPowerState
end


--Note: Jive does not use setSoftPowerState since it doesn't have a soft power concept
function JiveMain:setSoftPowerState(softPowerState, isServerRequest)
	if _softPowerState == softPowerState then
		--already in the desired state, leave (can happen for instance when notify_playerPower comes back after a local power change)
		 return
	end

	_softPowerState = softPowerState
	local currentPlayer = appletManager:callService("getCurrentPlayer")
	if _softPowerState == "off" then
		log:info("Turn soft power off")
		if currentPlayer and (currentPlayer:isConnected() or currentPlayer:isLocal()) then
			currentPlayer:setPower(false, nil, isServerRequest)
		end
		--todo: also pause/power off local player since local player might be playing and not be the current player
		appletManager:callService("activateScreensaver", isServerRequest)
	elseif _softPowerState == "on" then
		log:info("Turn soft power on")
		--todo: Define what should happen for a non-jive remote player. Currently if a server is down, locally a SS will engage, but when the server
		--       comes back up the server is considered the master power might soft power SP back on 
		if currentPlayer and (currentPlayer:isConnected() or currentPlayer:isLocal()) then
			if currentPlayer.slimServer then
				currentPlayer.slimServer:wakeOnLan()
			end
			currentPlayer:setPower(true, nil, isServerRequest)
		end

		appletManager:callService("deactivateScreensaver")
		appletManager:callService("restartScreenSaverTimer")

	else
		log:error("unknown desired soft power state: ", _softPowerState)
	end
end

function JiveMain:togglePower()
	local powerState = JiveMain:getSoftPowerState()
	if powerState == "off" then
		JiveMain:setSoftPowerState("on")
	elseif powerState == "on" then
		JiveMain:setSoftPowerState("off")
	else
		log:error("unknown current soft power state: ", powerState)
	end

end

local function _powerAction()
	Framework:playSound("SELECT")
	JiveMain:togglePower()
	return EVENT_CONSUME
end

local function _powerOffAction()
	JiveMain:setSoftPowerState("off")
	return EVENT_CONSUME
end

local function _powerOnAction()
	JiveMain:setSoftPowerState("on")
	return EVENT_CONSUME
end


function _defaultContextMenuAction(self)
	if not Framework:isMostRecentInput("mouse") then -- don't bump on touch press hold, is visually distracting...
		Framework:playSound("BUMP")
		Framework.windowStack[1]:bumpLeft()
	end
	return EVENT_CONSUME
end

-- __init
-- creates our JiveMain main object
function JiveMain:__init()
	log:info("JiveLite version ", JIVE_VERSION)

	print(package.path)

	-- Seed the rng
	local initTime = os.time()
	math.randomseed(initTime)

	-- Initialise UI
	Framework:init()

	-- Singleton instances (globals)
	jnt = NetworkThread()

	appletManager = AppletManager(jnt)
	iconbar = Iconbar(jnt)
	
	-- Singleton instances (locals)
	_globalStrings = locale:readGlobalStringsFile()

	Framework:initIRCodeMappings()

	-- register the default actions
	Framework:registerActions(_inputToActionMap)

	-- create the main menu
	jiveMain = oo.rawnew(self, HomeMenu(_globalStrings:str("HOME"), nil, "hometitle"))


--	profiler.start()

	-- menu nodes to add...these are menu items that are used by applets
	JiveMain:jiveMainNodes(_globalStrings)

	-- init our listeners
	jiveMain.skins = {}


	Framework:addListener(EVENT_IR_ALL,
		function(event) return _irHandler(event) end,
		false
	)

	-- global listener: resize window (only desktop versions)
	Framework:addListener(EVENT_WINDOW_RESIZE,
		function(event)
			jiveMain:reloadSkin()
			return EVENT_UNUSED
		end,
		10)		

	Framework:addActionListener("go_home", self, _goHomeAction, 10)

	--before NP exists (from SlimBrowseApplet), have go_home_or_now_playing go home
	Framework:addActionListener("go_home_or_now_playing", self, _goHomeAction, 10)

	Framework:addActionListener("add", self, _defaultContextMenuAction, 10)

	Framework:addActionListener("go_factory_test_mode", self, _goFactoryTestModeAction, 9999)

	--Consume up and down actions
	Framework:addActionListener("up", self, function() return EVENT_CONSUME end, 9999)
	Framework:addActionListener("down", self, function() return EVENT_CONSUME end, 9999)

	Framework:addActionListener("power", self, _powerAction, 10)
	Framework:addActionListener("power_off", self, _powerOffAction, 10)
	Framework:addActionListener("power_on", self, _powerOnAction, 10)

	Framework:addActionListener("nothing", self, function() return EVENT_CONSUME end, 10)

	--Last input type tracker (used by, for instance, Menu, to determine wheter selected style should be displayed)
	Framework:addListener(EVENT_ALL_INPUT,
		function(event)
			local type = event:getType()
			if (bit.band(type, EVENT_IR_ALL)) > 0 then
				if (Framework:isValidIRCode(event)) then
					Framework.mostRecentInputType = "ir"
				end
			end
			if (bit.band(type, EVENT_KEY_ALL)) > 0 then
				Framework.mostRecentInputType = "key"
			end
			if (bit.band(type, EVENT_SCROLL)) > 0 then
				Framework.mostRecentInputType = "scroll"
			end
			if (bit.band(type, EVENT_MOUSE_ALL)) > 0 then
				Framework.mostRecentInputType = "mouse"
			end
			--not sure what to do about char, since it is a bit of a hybrid input type. So far usages don't care.
			
			return EVENT_UNUSED
		end,
		true
	)

	--Ignore foreign remote codes
	Framework:addListener( EVENT_IR_ALL,
		function(event)
			if (not Framework:isValidIRCode(event)) then
				--is foreign remote code, consume so it doesn't appear as input to the app (future ir blaster code might still care)
				if log:isDebug() then
					log:debug("Consuming foreign IR event: ", event:tostring())
				end
				return EVENT_CONSUME
			end

			return EVENT_UNUSED
		end,
		true
	)

	-- show our window!
	jiveMain.window:show()

	-- load style and applets
	jiveMain:reload()

	-- debug: set event warning thresholds (0 = off)
	--Framework:perfwarn({ screen = 50, layout = 1, draw = 0, event = 50, queue = 5, garbage = 10 })
	--jive.perfhook(50)

	-- show splash screen for five seconds, or until key/scroll events
	Framework:setUpdateScreen(false)
	local splashHandler = Framework:addListener(bit.bor(ACTION, EVENT_CHAR_PRESS, EVENT_KEY_ALL, EVENT_SCROLL),
							    function()
							        JiveMain:performPostOnScreenInit()
								Framework:setUpdateScreen(true)
								return EVENT_UNUSED
							    end)
	local splashTimer = Timer(2000 - (os.time() - initTime),
		function()
			JiveMain:performPostOnScreenInit()
			Framework:setUpdateScreen(true)
			Framework:removeListener(splashHandler)
		end,
		true)
	splashTimer:start()

	local heapTimer = Timer(60000,
		function()
			if not logheap:isDebug() then
				return
			end

			local s = jive.heap()
			logheap:debug("--- HEAP total/new/free ---")
			logheap:debug("number=", s["number"]);
			logheap:debug("integer=", s["integer"]);
			logheap:debug("boolean=", s["boolean"]);
			logheap:debug("string=", s["string"]);
			logheap:debug("table=", s["table"], "/", s["new_table"], "/", s["free_table"]);
			logheap:debug("function=", s["function"], "/", s["new_function"], "/", s["free_function"]);
			logheap:debug("thread=", s["thread"], "/", s["new_thread"], "/", s["free_thread"]);
			logheap:debug("userdata=", s["userdata"], "/", s["new_userdata"], "/", s["free_userdata"]);
			logheap:debug("lightuserdata=", s["lightuserdata"], "/", s["new_lightuserdata"], "/", s["free_lightuserdata"]);
		end)
	heapTimer:start()

	-- run event loop
	Framework:eventLoop(jnt:task())

	Framework:quit()

--	profiler.stop()
end


function JiveMain:registerPostOnScreenInit(callback)
	if not JiveMain.postOnScreenInits then
		JiveMain.postOnScreenInits = {}
	end
	table.insert(JiveMain.postOnScreenInits, callback)

end

-- perform activities that need to run once the skin is loaded and the screen is visible
function JiveMain:performPostOnScreenInit()
	if not JiveMain.postOnScreenInits then
		return
	end

	for i, callback in ipairs(JiveMain.postOnScreenInits) do
		log:info("Calling postOnScreenInits callback")
		callback()
	end
	JiveMain.postOnScreenInits = {}
end

function JiveMain:jiveMainNodes(globalStrings)

	-- this can be called after language change, 
	-- so we need to bring in _globalStrings again if it wasn't provided to the method
	if globalStrings then
		_globalStrings = globalStrings
	else
		_globalStrings = locale:readGlobalStringsFile()
	end

	jiveMain:addNode( { id = 'hidden', node = 'nowhere' } )
	jiveMain:addNode( { id = 'extras', node = 'home', text = _globalStrings:str("EXTRAS"), weight = 50, hiddenWeight = 91  } )
	jiveMain:addNode( { id = 'radios', iconStyle = 'hm_radio', node = 'home', text = _globalStrings:str("INTERNET_RADIO"), weight = 20  } )
	jiveMain:addNode( { id = '_myMusic', iconStyle = 'hm_myMusic', node = 'hidden', text = _globalStrings:str("MY_MUSIC"), synthetic = true , hiddenWeight = 2  } )
	jiveMain:addNode( { id = 'games', node = 'extras', text = _globalStrings:str("GAMES"), weight = 70  } )
	jiveMain:addNode( { id = 'settings', iconStyle = 'hm_settings', node = 'home', noCustom = 1, text = _globalStrings:str("SETTINGS"), weight = 1005, })
	jiveMain:addNode( { id = 'advancedSettings', iconStyle = 'hm_advancedSettings', node = 'settings', text = _globalStrings:str("ADVANCED_SETTINGS"), weight = 105, windowStyle = 'text_only' })
	jiveMain:addNode( { id = 'screenSettings', iconStyle = 'hm_settingsScreen', node = 'settings', text = _globalStrings:str("SCREEN_SETTINGS"), weight = 60, windowStyle = 'text_only' })
	jiveMain:addNode( { id = 'screenSettingsNowPlaying', node = 'screenSettings', text = _globalStrings:str("NOW_PLAYING"), windowStyle = 'text_only' })
	jiveMain:addNode( { id = 'factoryTest', node = 'advancedSettings', noCustom = 1, text = _globalStrings:str("FACTORY_TEST"), weight = 120, windowStyle = 'text_only' })
	jiveMain:addNode( { id = 'advancedSettingsBetaFeatures', node = 'advancedSettings', noCustom = 1, text = _globalStrings:str("BETA_FEATURES"), weight = 100, windowStyle = 'text_only' })
	jiveMain:addNode( { id = 'networkSettings', node = 'advancedSettings', noCustom = 1, text = _globalStrings:str("NETWORK_NETWORKING"), weight = 100, windowStyle = 'text_only' })
	jiveMain:addNode( { id = 'settingsAudio', iconStyle = "hm_settingsAudio", node = 'settings', noCustom = 1, text = _globalStrings:str("AUDIO_SETTINGS"), weight = 40, windowStyle = 'text_only' })
	jiveMain:addNode( { id = 'settingsBrightness', iconStyle = "hm_settingsBrightness", node = 'settings', noCustom = 1, text = _globalStrings:str("BRIGHTNESS_SETTINGS"), weight = 45, windowStyle = 'text_only' })


end

--[[

=head2 jive.JiveMain:addHelpMenuItem()

Adds a 'Help' menu item to I<menu> if the most recent input was not touch or mouse (which generally would have a help button instead)

=cut
--]]
function JiveMain:addHelpMenuItem(menu, obj, callback, textToken, iconStyle)
	-- only deliver an icon if specified
	if not iconStyle then
		iconStyle = "_BOGUS_"
	end
	if not Framework:isMostRecentInput("mouse") then
		menu:addItem({
			iconStyle = iconStyle,
			text = textToken and _globalStrings:str(textToken) or _globalStrings:str("GLOBAL_HELP"),
			sound = "WINDOWSHOW",
			callback =      function ()
						callback(obj)
					end,
			weight = 100
		})
	end
end



-- reload
-- 
function JiveMain:reload()
	log:debug("reload()")

	-- reset the skin
	jive.ui.style = {}

	-- manage applets
	appletManager:discover()

	-- make sure a skin is selected
	if not self.selectedSkin then
		for askin in pairs(self.skins) do
			self:setSelectedSkin(askin)
			break
		end
	end
	assert(self.selectedSkin, "No skin")
end


function JiveMain:registerSkin(name, appletName, method, skinId)
	log:debug("registerSkin(", name, ",", appletName, ", ", skinId or "", ")")
	-- skinId allows multiple entry methods to single applet to give multiple skins
	if skinId == nil then
		skinId = appletName
	end
	self.skins[skinId] = { appletName, name, method }
end


function JiveMain:skinIterator()
	local _f,_s,_var = pairs(self.skins)
	return function(_s,_var)
		local skinId, entry = _f(_s,_var)
		if skinId then
			return skinId, entry[2]
		else
			return nil
		end
	end,_s,_var
end


function JiveMain:getSelectedSkin()
	return self.selectedSkin
end


local function _loadSkin(self, skinId, reload, useDefaultSize)
	if not self.skins[skinId] then
		return false
	end

	local appletName, name, method = unpack(self.skins[skinId])
	local obj = appletManager:loadApplet(appletName)
	assert(obj, "Cannot load skin " .. appletName)

	-- reset the skin
	jive.ui.style = {}

	obj[method](obj, jive.ui.style, reload==nil and true or reload, useDefaultSize)
	self._skin = obj

	Framework:styleChanged()

	return true
end


function JiveMain:isFullscreen()
	return _fullscreen
end


function JiveMain:setFullscreen(fullscreen)
	_fullscreen = fullscreen
end


function JiveMain:setSelectedSkin(skinId)
	log:info("select skin: ", skinId)
	local oldSkinId = self.selectedSkin
	if _loadSkin(self, skinId, false, true) then
		self.selectedSkin = skinId
		jnt:notify("skinSelected")
		if oldSkinId and self.skins[oldSkinId] and self.skins[oldSkinId][1] ~= self.skins[skinId][1] then
			jiveMain:freeSkin(oldSkinId)
		end
	end
end


function JiveMain:getSkinParamOrNil(key)
	if self._skin then
		local param = self._skin:param()

		if key and param[key] ~= nil then
			return param[key]
		end
	end

	return nil
end


function JiveMain:getSkinParam(key)
	if self._skin then
		local param = self._skin:param()

		if key and param[key] ~= nil then
			return param[key]
		end
	end

	log:error('no value for skinParam ', key, ' found') 
	return nil
end


-- reloadSkin
-- 
function JiveMain:reloadSkin(reload)
	_loadSkin(self, self.selectedSkin, true);
end

function JiveMain:freeSkin(skinId)
	if skinId == nil then
		skinId = self.selectedSkin
	end
	log:info("freeSkin: ", skinId)

	if not self.skins[skinId] then
		return false
	end
	appletManager:freeApplet(self.skins[skinId][1])
end

function JiveMain:setDefaultSkin(skinId)
	log:debug("setDefaultSkin(", skinId, ")")
	_defaultSkin = skinId
end


function JiveMain:getDefaultSkin()
	return _defaultSkin or "QVGAportraitSkin"
end


-----------------------------------------------------------------------------
-- main()
-----------------------------------------------------------------------------

-- we create an object
JiveMain()


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

