
-- Private class to handle player position scanner

local ipairs, tostring, tonumber, bit = ipairs, tostring, tonumber, bit

local oo                     = require("loop.base")
local os                     = require("os")
local math                   = require("math")
local string	             = require("string")

local Framework              = require("jive.ui.Framework")
local Group                  = require("jive.ui.Group")
local Icon                   = require("jive.ui.Icon")
local Label                  = require("jive.ui.Label")
local Popup                  = require("jive.ui.Popup")
local Slider                 = require("jive.ui.Slider")
local Timer                  = require("jive.ui.Timer")
local Window                 = require("jive.ui.Window")

local debug                  = require("jive.utils.debug")
local log                    = require("jive.utils.log").logger("applet.SlimBrowser")


local ACTION                 = jive.ui.ACTION
local EVENT_KEY_ALL          = jive.ui.EVENT_KEY_ALL
local EVENT_KEY_PRESS        = jive.ui.EVENT_KEY_PRESS
local EVENT_KEY_HOLD         = jive.ui.EVENT_KEY_HOLD
local EVENT_KEY_DOWN         = jive.ui.EVENT_KEY_DOWN
local EVENT_KEY_UP           = jive.ui.EVENT_KEY_UP
local EVENT_SCROLL           = jive.ui.EVENT_SCROLL

local EVENT_CONSUME          = jive.ui.EVENT_CONSUME
local EVENT_UNUSED           = jive.ui.EVENT_UNUSED

local KEY_GO                 = jive.ui.KEY_GO
local KEY_BACK               = jive.ui.KEY_BACK
local KEY_FWD                = jive.ui.KEY_FWD
local KEY_REW                = jive.ui.KEY_REW
local KEY_FWD_SCAN           = jive.ui.KEY_FWD_SCAN
local KEY_REW_SCAN           = jive.ui.KEY_REW_SCAN

local appletManager          = appletManager

-- Tuning
local POSITION_STEP = 5
local POPUP_AUTOCLOSE_INTERVAL = 10000  -- close popup after this much inactivity
local AUTOINVOKE_INTERVAL_LOCAL = 400	-- invoke gotoTime after this much inactivity for local tracks
local AUTOINVOKE_INTERVAL_REMOTE = 2000	-- and this much for remote streams
local ACCELERATION_INTERVAL = 350       -- events faster than this cause acceleration
local ACCELERATION_INTERVAL_SLOW = 200  -- but less so unless faster than this


module(..., oo.class)

local function _secondsToString(seconds)
	local hrs  = math.floor(seconds / 3600 )
	local mins = math.floor((seconds % 3600) / 60)
	local secs = seconds % 60

	if secs > 0 and secs < 1 then
		-- the string.format fails if value > 0 and < 1
		secs = 0
	end
	
	if hrs > 0 then
		return string.format("%d:%02d:%02d", hrs, mins, secs)
	end

	return string.format("%d:%02d", mins, secs)
end

local function _updateDisplay(self)
	self.title:setValue(self.applet:string("SLIMBROWSER_SCANNER"))
	self.slider:setValue(tonumber(self.elapsed))
	local strElapsed = _secondsToString(self.elapsed)

	self.heading:setValue(strElapsed)
end


local function _updateElapsedTime(self)
	if not self.popup then
		self.displayTimer:stop()
		self.holdTimer:stop()
		return
	end

	self.elapsed, self.duration = self.player:getTrackElapsed()
	_updateDisplay(self)
end


local function _openPopup(self)
	if self.popup or not self.player then
		return
	end

	-- we need a local copy of the elapsed time
	self.elapsed, self.duration = self.player:getTrackElapsed()
	if not self.elapsed or not self.duration or not self.player:isTrackSeekable() then
		-- don't show the popup if the player state is not loaded
		-- or if we cannot seek in this track
		return
	end
	
	local popup = Popup("scanner_popup")
	popup:setAutoHide(false)
	popup:setAlwaysOnTop(true)

	local title = Label("heading", "")
	popup:addWidget(title)

	local slider = Slider("scanner_slider", 0, tonumber(self.duration), tonumber(self.elapsed),
			function(slider, value, done)
				self.delta = value - self.elapsed
				self.elapsed = value
				_updateSelectedTime(self)
			end)
	self.heading = title
	self.scannerGroup = Group("slider_group", {
		slider = slider,
	})

	popup:addWidget(self.scannerGroup)
	popup:addListener(bit.bor(ACTION, EVENT_KEY_ALL, EVENT_SCROLL),
			  function(event)
				  return self:event(event)
			  end)

	-- we handle events
	popup.brieflyHandler = false

	-- open the popup
	self.popup = popup
	self.title = title
	self.slider = slider

	self.displayTimer:restart()

	if self.player:isRemote() then
		self.autoinvokeTime = AUTOINVOKE_INTERVAL_REMOTE
	else
		self.autoinvokeTime = AUTOINVOKE_INTERVAL_LOCAL
	end

	popup:focusWidget(nil)

	_updateDisplay(self)

	popup:showBriefly(POPUP_AUTOCLOSE_INTERVAL,
		function()
			--This happens on ANY window pop, not necessarily the popup window's pop
			local isPopupOnStack = false
			local stack = Framework.windowStack
			for i in ipairs(stack) do
				if stack[i] == popup then
					isPopupOnStack = true
					break
				end
			end

			--don't clear it out if the pop was from another window
			if not isPopupOnStack then
				self.popup = nil
			end
		end,
		Window.transitionNone,
		Window.transitionNone
	)

end


function _updateSelectedTime(self)
	if not self.popup then
		self.displayTimer:stop()
		self.holdTimer:stop()
		return
	end
	if self.delta == 0 then
		return
	end

	-- Now that the user has changed the position, stop tracking the actual playing position
	self.displayTimer:stop()

	-- keep the popup window open
	self.popup:showBriefly()

	-- accelation
	local now = Framework:getTicks()
	local interval = now - self.lastUpdate
	if self.accelDelta ~= self.delta or interval > ACCELERATION_INTERVAL then
		self.accelCount = 0
	end

	self.accelCount = math.min(self.accelCount + 1, self.duration/15, 50)
	self.accelDelta = self.delta
	self.lastUpdate = now

	-- change position
	local accel
	if interval > ACCELERATION_INTERVAL_SLOW then
		accel = self.accelCount / 15
	else
		accel = self.accelCount / 10
	end
	local new = math.abs(self.elapsed) + self.delta * accel * POSITION_STEP
	
	if new > self.duration then 
		new = self.duration
	elseif new < 0 then
		new = 0
	end

	-- self.elapsed = self.player:gotoTime(new) or self.elapsed
	self.elapsed = new
	_updateDisplay(self)
	
	self.autoInvokeTimer:restart(self.autoinvokeTime)
end


function _gotoTime(self)
	self.autoInvokeTimer:stop()
	if not self.popup then
		return
	end
	self.player:gototime(math.floor(self.elapsed))
	self.displayTimer:restart()
end

function __init(self, applet)
	local obj = oo.rawnew(self, {})

	obj.applet = applet
	obj.lastUpdate = 0
	obj.displayTimer = Timer(1000, function() _updateElapsedTime(obj) end)
	obj.autoInvokeTimer = Timer(AUTOINVOKE_INTERVAL_LOCAL, function() _gotoTime(obj) end, true)
	obj.holdTimer = Timer(100, function() _updateSelectedTime(obj) end)

	return obj
end


function setPlayer(self, player)
	self.player = player
end


function event(self, event)
	--hack to handle screensaver, in volume and scanner, actions are not used due to need for down handling
	appletManager:callService("deactivateScreensaver")
	appletManager:callService("restartScreenSaverTimer")

	local onscreen = true
	if not self.popup then
		onscreen = false
		_openPopup(self)
	end

	local type = event:getType()
	
	if type == EVENT_SCROLL then
		local scroll = event:getScroll()
		
		if scroll > 0 then
			self.delta = 1
		elseif scroll < 0 then
			self.delta = -1
		else
			self.delta = 0
		end
		_updateSelectedTime(self)
	elseif type == ACTION then
		local action = event:getAction()

		-- GO closes the popup & executes any pending change
		if action == "go" then
			if self.autoInvokeTimer:isRunning() then _gotoTime(self) end
			self.popup:showBriefly(0)
			return EVENT_CONSUME
		-- BACK closes the popup & cancels any pending change
		elseif action == "back" then
			self.autoInvokeTimer:stop()
			self.popup:showBriefly(0)
                        return EVENT_CONSUME
		end
		if action == "scanner_fwd" then
			self.delta = 1

			if onscreen then
				_updateSelectedTime(self)
			end

			return EVENT_CONSUME
		end
		if action == "scanner_rew" then
			self.delta = -1

			if onscreen then
				_updateSelectedTime(self)
			end

			return EVENT_CONSUME
		end

		-- any other actions forward to the lower window
		local lower = self.popup:getLowerWindow()
		if self.popup then
			self.popup:showBriefly(0)
		end
		if lower then
			Framework:dispatchEvent(lower, event)
		end

		return EVENT_CONSUME

	elseif type == EVENT_KEY_PRESS then
		return EVENT_UNUSED
	else
		local keycode = event:getKeycode()

		-- we're only interested in volume keys
		if bit.band(keycode, bit.bor(KEY_FWD, KEY_REW, KEY_FWD_SCAN, KEY_REW_SCAN)) == 0 then
			return EVENT_CONSUME
		end

		-- stop volume update on key up
		if type == EVENT_KEY_UP then
			self.delta = 0
			self.muting = false
			self.holdTimer:stop()
			return EVENT_CONSUME
		end

		-- update position
		-- We could add "or type == EVENT_KEY_HOLD" to this test,
		-- in which case the hold-fwd/hold-rew used to enter this mode
		-- would immediately start scanning, but I think that it is better
		-- without this.
		if type == EVENT_KEY_DOWN or type == EVENT_KEY_HOLD then
			if keycode == KEY_FWD or keycode == KEY_FWD_SCAN then
				self.delta = 1
			elseif keycode == KEY_REW or keycode == KEY_REW_SCAN then
				self.delta = -1
			else
				self.delta = 0
			end

			self.holdTimer:restart()
			if onscreen then
				_updateSelectedTime(self)
			end

			return EVENT_CONSUME
		end
	end

	return EVENT_CONSUME
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]
