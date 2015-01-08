
--[[
=head1 NAME

applets.HttpAuth.HttpAuthApplet - An applet to configure user/password to SqueezeCenter

=head1 DESCRIPTION

This applets lets the user configure a username and password to SqueezeCenter

=head1 FUNCTIONS

Applet related methods are described in L<jive.Applet>. 
HttpAuthApplet overrides the following methods:

=cut
--]]


-- stuff we use
local ipairs, pairs, tostring = ipairs, pairs, tostring

local table           = require("table")
local string          = require("string")

local oo              = require("loop.simple")

local Applet          = require("jive.Applet")
local Event           = require("jive.ui.Event")
local Framework       = require("jive.ui.Framework")
local SimpleMenu      = require("jive.ui.SimpleMenu")
local Window          = require("jive.ui.Window")
local Icon            = require("jive.ui.Icon")
local Group           = require("jive.ui.Group")
local Label           = require("jive.ui.Label")
local Choice          = require("jive.ui.Choice")
local Textarea        = require("jive.ui.Textarea")
local Textinput       = require("jive.ui.Textinput")
local Keyboard        = require("jive.ui.Keyboard")
local Button          = require("jive.ui.Button")
local Popup           = require("jive.ui.Popup")

local jnt           = jnt
local appletManager = appletManager

local SocketHttp      = require("jive.net.SocketHttp")

local CONNECT_TIMEOUT = 20

module(..., Framework.constants)
oo.class(_M, Applet)


function squeezeCenterPassword(self, server, setupNext, titleStyle, showConnecting)
	self.server = server
	if setupNext then
		self.setupNext = setupNext
	end
	if titleStyle then
		self.titleStyle = titleStyle
	end
	self.showConnecting = showConnecting

	self.inputWindows = {}

	self.topWindow = self:_enterTextWindow("username", "HTTP_AUTH_USERNAME", "HTTP_AUTH_USERNAME_HELP", _enterPassword)
end


function _enterPassword(self)
	self:_enterTextWindow("password", "HTTP_AUTH_PASSWORD", "HTTP_AUTH_PASSWORD_HELP", _enterDone)
end


function _enterDone(self)
	local protected, realm = self.server:isPasswordProtected()

	-- store username/password
	local settings = self:getSettings()
	settings[self.server:getId()] = {
		realm = realm,
		username = self.username,
		password = self.password
	}
	self:storeSettings()

	-- set authorization
	self.server:setCredentials({
		realm = realm,
		username = self.username,
		password = self.password,
	})

	self.username = nil
	self.password = nil

	if self.showConnecting then
		jnt:subscribe(self)
		self:_showConnectToServer(self.server)

		self:_hideInputWindows()

		return
	else
		self.topWindow:hideToTop(Window.transitionPushLeft)
	end
	
	if self.setupNext then
		return self.setupNext()
	end
end


function _hideInputWindows(self)
	for key, window in pairs(self.inputWindows) do
		window:hide(Window.transitionNone)
	end
end


function _showConnectToServer(self,  server)
	self.connectingPopup = Popup("waiting_popup")
	local window = self.connectingPopup
	window:addWidget(Icon("icon_connecting"))
--	window:setAutoHide(false)

	local statusLabel = Label("text", self:string("HTTP_AUTH_CONNECTING_TO"))
	local statusSubLabel = Label("subtext", server:getName())
	window:addWidget(statusLabel)
	window:addWidget(statusSubLabel)

	local timeout = 1

	local cancelAction = function()
		--sometimes timeout not back to 1 next time around, so reset it
		timeout = 1
		self.showConnecting = nil
		window:hide()
	end

	-- disable input
	window:ignoreAllInputExcept({"back", "go_home"})
	window:addActionListener("back", self, cancelAction)
	window:addActionListener("go_home", self, cancelAction)
	window:addTimer(1000,
			function()

				-- we detect when the connect to the new server
				-- with notify_serverConnected

				timeout = timeout + 1
				if timeout > CONNECT_TIMEOUT then
					log:warn("Timeout passed, current count: ", timeout)
					cancelAction()
				end
			end)

	self:tieAndShowWindow(window)
end

function notify_serverAuthFailed(self, server, failureCount)
	if self.showConnecting and self.server == server and failureCount == 1 then
		log:debug("self.waitForConnect:", self.waitForConnect, " ", server)
		self:_httpAuthErrorWindow(server)
	end
end

function notify_serverConnected(self, server)
	if not self.showConnecting or self.server ~= server then
		return
	end
	log:info("notify_serverConnected")
	self.connectingPopup:hide()
	if self.setupNext then
		return self.setupNext()
	end
end


function _httpAuthErrorWindow(self, server)
	local window = Window("help_list", self:string("HTTP_AUTH_PASSWORD_WRONG"), "setuptitle")

	local textarea = Textarea("help_text", self:string("HTTP_AUTH_PASSWORD_WRONG_BODY"))

	local menu = SimpleMenu("menu")

	window:setAutoHide(true)

	menu:addItem({
		text = self:string("HTTP_AUTH_TRY_AGAIN"),
		sound = "WINDOWHIDE",
		callback = function()
				appletManager:callService("squeezeCenterPassword", server, nil, nil, true)
			   end,
	})
	local cancelAction = function()
		window:playSound("WINDOWHIDE")
		window:hide()

		return EVENT_CONSUME
	end

	menu:addActionListener("back", self, cancelAction)
	menu:addActionListener("go_home", self, cancelAction)

	menu:setHeaderWidget(textarea)
	window:addWidget(menu)

	self:tieAndShowWindow(window)
end

function _helpWindow(self, title, token)
	local window = Window("text_list", self:string(title), self.titleStyle)
	window:setAllowScreensaver(false)
	window:addWidget(Textarea("text", self:string(token)))

	self:tieAndShowWindow(window)
	return window
end

function _enterTextWindow(self, key, title, help, next)
	local window = Window("text_list", self:string(title), self.titleStyle)

	local input = Textinput("textinput", self[key] or "",
				function(_, value)
					self[key] = value

					window:playSound("WINDOWSHOW")
					next(self)
					return true
				end)

	--[[ FIXME: this needs updating
	local helpButton = Button( 
				Label( 
					'helpTouchButton', 
					self:string("HTTP_AUTH_HELP")
				), 
				function() 
					self:_helpWindow('HTTP_AUTH', help) 
				end 
	)
        window:addWidget(helpButton)
	--]]

	local keyboard = Keyboard("keyboard", "qwerty", input)
	local backspace = Keyboard.backspace()
        local group = Group('keyboard_textinput', { textinput = input, backspace = backspace } )

        window:addWidget(group)
	window:addWidget(keyboard)
	window:focusWidget(group)

	self.inputWindows[key] = window

	self:tieAndShowWindow(window)
	return window
end

function free(self)
	log:debug("Unsubscribing jnt")
	jnt:unsubscribe(self)

	return true
end

--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

