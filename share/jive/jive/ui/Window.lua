
--[[
=head1 NAME

jive.ui.Window - The window widget.

=head1 DESCRIPTION

The window widget, extends L<jive.ui.Widget>. This is a container for other widgets on the screen.

=head1 SYNOPSIS

 -- Create a new window with title "Jive" and title style "hometitle"
 local window = jive.ui.Window("text_list", "Jive", "hometitle")

 -- Show the window on the screen
 window:show()

 -- Hide the window from the screen
 window:hide()


=head1 STYLE

The Window includes the following style parameters in addition to the widgets basic parameters.

=over

B<bgImg> : the windows background image.

=head1 METHODS

=cut
--]]


-- stuff we use
local _assert, ipairs, require, tostring, type, unpack, bit = _assert, ipairs, require, tostring, type, unpack, bit

local math                    = require("math")
local debug                   = require("jive.utils.debug")
local oo                      = require("loop.simple")
local table                   = require("jive.utils.table")
local SimpleMenu              = require("jive.ui.SimpleMenu")
local Button                  = require("jive.ui.Button")
local Group                   = require("jive.ui.Group")
local Label                   = require("jive.ui.Label")
local Icon                    = require("jive.ui.Icon")
local Timer                   = require("jive.ui.Timer")
local Widget                  = require("jive.ui.Widget")
local Event                   = require("jive.ui.Event")
local Surface                 = require("jive.ui.Surface")

local debug                   = require("jive.utils.debug")
local log                     = require("jive.utils.log").logger("jivelite.ui")

local max                     = math.max
local min                     = math.min

local tonumber                = tonumber

local EVENT_ALL               = jive.ui.EVENT_ALL
local EVENT_ALL_INPUT         = jive.ui.EVENT_ALL_INPUT
local ACTION                  = jive.ui.ACTION
local EVENT_KEY_ALL           = jive.ui.EVENT_KEY_ALL
local EVENT_MOUSE_HOLD        = jive.ui.EVENT_MOUSE_HOLD
local EVENT_MOUSE_DRAG        = jive.ui.EVENT_MOUSE_DRAG
local EVENT_MOUSE_PRESS       = jive.ui.EVENT_MOUSE_PRESS
local EVENT_MOUSE_DOWN        = jive.ui.EVENT_MOUSE_DOWN
local EVENT_MOUSE_UP          = jive.ui.EVENT_MOUSE_UP
local EVENT_MOUSE_ALL         = jive.ui.EVENT_MOUSE_ALL
local EVENT_ACTION            = jive.ui.EVENT_ACTION
local EVENT_SCROLL            = jive.ui.EVENT_SCROLL
local EVENT_KEY_PRESS         = jive.ui.EVENT_KEY_PRESS
local EVENT_KEY_HOLD          = jive.ui.EVENT_KEY_HOLD
local EVENT_CHAR_PRESS         = jive.ui.EVENT_CHAR_PRESS
local EVENT_WINDOW_PUSH       = jive.ui.EVENT_WINDOW_PUSH
local EVENT_WINDOW_POP        = jive.ui.EVENT_WINDOW_POP
local EVENT_WINDOW_ACTIVE     = jive.ui.EVENT_WINDOW_ACTIVE
local EVENT_WINDOW_INACTIVE   = jive.ui.EVENT_WINDOW_INACTIVE
local EVENT_FOCUS_LOST        = jive.ui.EVENT_FOCUS_LOST
local EVENT_FOCUS_GAINED      = jive.ui.EVENT_FOCUS_GAINED
local EVENT_SHOW              = jive.ui.EVENT_SHOW
local EVENT_HIDE              = jive.ui.EVENT_HIDE
local EVENT_CONSUME           = jive.ui.EVENT_CONSUME
local EVENT_UNUSED            = jive.ui.EVENT_UNUSED

local KEY_BACK                = jive.ui.KEY_BACK
local KEY_GO                  = jive.ui.KEY_GO
local KEY_RIGHT               = jive.ui.KEY_RIGHT

local FRAME_RATE              = jive.ui.FRAME_RATE
local LAYER_ALL               = jive.ui.LAYER_ALL
local LAYER_CONTENT           = jive.ui.LAYER_CONTENT
local LAYER_CONTENT_OFF_STAGE = jive.ui.LAYER_CONTENT_OFF_STAGE
local LAYER_CONTENT_ON_STAGE  = jive.ui.LAYER_CONTENT_ON_STAGE
local LAYER_FRAME             = jive.ui.LAYER_FRAME
local LAYER_TITLE             = jive.ui.LAYER_TITLE
local LAYER_LOWER             = jive.ui.LAYER_LOWER

local LAYOUT_NORTH            = jive.ui.LAYOUT_NORTH
local LAYOUT_EAST             = jive.ui.LAYOUT_EAST
local LAYOUT_SOUTH            = jive.ui.LAYOUT_SOUTH
local LAYOUT_WEST             = jive.ui.LAYOUT_WEST
local LAYOUT_CENTER           = jive.ui.LAYOUT_CENTER
local LAYOUT_NONE             = jive.ui.LAYOUT_NONE

local appletManager           = require("jive.AppletManager")

local HORIZONTAL_PUSH_TRANSITION_DURATION = 500

-- our class
module(...)
oo.class(_M, Widget)


local Framework = require("jive.ui.Framework")


function _bump(self)
	self:playSound("BUMP")
	self:getWindow():bumpRight()
	return EVENT_CONSUME
end

function upAction(self)
	self:playSound("WINDOWHIDE")
	self:getWindow():hide()

	return EVENT_CONSUME
end


--[[

=head2 jive.ui.Window(style, title, titleStyle, windowId)

Constructs a new window widget. I<style> is the widgets style. The window can have an optional I<title>, an optional titleStyle I<titleStyle>, and an optional windowId string I<windowId>

=cut
--]]
function __init(self, style, title, titleStyle, windowId)
	_assert(type(style) == "string", "style parameter is " .. type(style) .. " expected string - " .. debug.traceback())

	local obj = oo.rawnew(self, Widget(style))

	obj.allowScreensaver = true
	obj.alwaysOnTop = false
	obj.autoHide = false
	obj.showFrameworkWidgets = true
	obj.transparent = false
	obj.transient = false

	obj.windowId = windowId

	obj.widgets = {} -- child widgets
	obj.zWidgets = {} -- child widgets and framework widgets in z order
	obj.layoutRoot = true
	obj.focus = nil

	obj._DEFAULT_SHOW_TRANSITION = transitionPushLeft
	obj._DEFAULT_HIDE_TRANSITION = transitionPushRight

	if title then
		obj:setTitle(title)
		if titleStyle then
			obj:setIconWidget("icon", Icon(titleStyle))
		end

		-- default actions
		obj:setDefaultLeftButtonAction()
		obj:setDefaultRightButtonAction()
		
		--kind of a hack, always resetting the buttons if default so that ShortcutApplet's overrides can be seen in every window
		obj:addListener(EVENT_WINDOW_ACTIVE,
			function(event)
				local left = obj:getIconWidget("lbutton")
				if left and left.isDefaultButtonGroup and obj ~= Framework.windowStack[1] then --exclude home which has alternate button handling due to power
					obj:setDefaultLeftButtonAction()
				end
				local right = obj:getIconWidget("rbutton")
				if right and right.isDefaultButtonGroup and obj ~= Framework.windowStack[1] then --exclude home which has alternate button handling due to power
					obj:setDefaultRightButtonAction()
				end
				return EVENT_UNUSED
			end)
	end

	-- by default, hide the window on BACK actions, add this as a
	-- listener to allow other handlers to act on these events first
	self.defaultActionListenerHandles = {}
	table.insert(self.defaultActionListenerHandles, obj:addActionListener("back", obj, upAction))

	return obj
end


function _ignoreAllInputListener(self, event, excludedActions, ignoredCallback)
	if log:isDebug() then
		log:debug("_ignoreAllInputListener: ", event:tostring())
	end
	
	if event:getType() == ACTION then
		local action = event:getAction()
		if excludedActions then
			for i, excludedAction in ipairs(excludedActions) do
				Framework:assertActionName(excludedAction)
				
				if action == excludedAction then
					log:debug("action excluded from _ignoreAllInputListener: ", action)

					return EVENT_UNUSED
				end
			end
		end

		if log:isDebug() then
			log:debug("Ignoring action: ", event:getAction())
		end
		if ignoredCallback then
			ignoredCallback(event)
		end
		return EVENT_CONSUME
	end

	--else try to convert to action to allow this window the chance to handle actions
	local action = Framework:getAction(event)
	if not action then
		return EVENT_CONSUME
	end

	local actionEvent = Framework:newActionEvent(action)

	--recurse as an action
	return _ignoreAllInputListener(self, actionEvent, excludedActions, ignoredCallback)

end

--[[

=head2 ignoreAllInputExcept(excludedActions, ignoredCallback)

Consume all input events except for i<excludedActions>. Note: The action "soft_reset" is always included in the excluded actions.
if ignoredCallback exists, ignoredCallback(actionEvent) will be called for any ignored action.

=cut
--]]
function ignoreAllInputExcept(self, excludedActions, ignoredCallback)
	if not self.ignoreAllInputHandle then
		--also need to remove any hideOnAllButtonInputHandle, since in the ignoreAllInput case
		-- we want excluded actions to be seen by global listeners. Leaving hideOnAllButtonInputHandle in place would
		-- prevent the event from getting to global listeners
		if self.hideOnAllButtonInputHandle then
			self:removeListener(self.hideOnAllButtonInputHandle)
			self.hideOnAllButtonInputHandle = false
		end

		if not excludedActions then
			excludedActions = {}
		end
		table.insert(excludedActions, "soft_reset")
	
		self.ignoreAllInputHandle = self:addListener(EVENT_ALL_INPUT,
								function(event)
									return _ignoreAllInputListener(self, event, excludedActions, ignoredCallback)
								end)
	end

end

local function hideOnAllButtonInputListener(self, event)

	if event:getType() == ACTION then
		log:warn("Hiding on unconsumed action")

		self:playSound("WINDOWHIDE")
		self:hide()

		return EVENT_CONSUME
	end

	--else convert to action to allow this window the chance to handle actions
	if Framework:convertInputToAction(event) == EVENT_UNUSED then
		--no action was found, so no need to further process it, just hide
		self:playSound("WINDOWHIDE")
		self:hide()
	end

	return EVENT_CONSUME

end

function hideOnAllButtonInput(self)
	if not self.hideOnAllButtonInputHandle then
		self.hideOnAllButtonInputHandle = self:addListener(bit.bor(ACTION, EVENT_KEY_PRESS, EVENT_KEY_HOLD, EVENT_MOUSE_PRESS, EVENT_MOUSE_HOLD, EVENT_MOUSE_DRAG),
								function(event)
									return hideOnAllButtonInputListener(self, event)
								end)

	end

end

function removeDefaultActionListeners(self)
	if self.defaultActionListenerHandles then
		for i, handle in ipairs(self.defaultActionListenerHandles) do
				self:removeListener(handle)		
		end
	end
	self.defaultActionListenerHandles = {}
end

function _goNowPlaying(self, obj)
	local worked = appletManager:callService("goNowPlaying", "browse")
	log:warn(worked)
	if not worked then
		obj:playSound("BUMP")
		obj:bumpRight()
	end
end

--[[

=head2 jive.ui.Window:show(transition)

Show this window, adding it to the top of the window stack. The I<transition> is used to move the window on stage.

=cut
--]]
function show(self, transition)
	local stack = Framework.windowStack

	local idx = 1
	local topwindow = stack[idx]
	while topwindow and topwindow.alwaysOnTop do
		idx = idx + 1
		topwindow = stack[idx]
	end

	if topwindow == self then
		-- we're already on top
		return
	end


	if not self.contextMenu and not self.transient then
		self:hideContextMenus()
	end

	-- remove the window if it is already in the stack
	local onstack = table.delete(stack, self)

	if not onstack then
		-- this window is being pushed to the stack
		self:dispatchNewEvent(EVENT_WINDOW_PUSH)
	end

	-- this window is now active
	self:dispatchNewEvent(EVENT_WINDOW_ACTIVE)

	-- this window and it's widgets are now visible
	self:dispatchNewEvent(EVENT_SHOW)

	-- insert the window in the window stack
	table.insert(stack, idx, self)

	if topwindow then
		-- push transitions
		transition = transition or self._DEFAULT_SHOW_TRANSITION
		Framework:_startTransition(_newTransition(transition, topwindow, self))

		if not self.transparent then
			-- top window is no longer visiable and it is inactive,
			-- if the top window is transparent also dispatch 
			-- events to the lower window(s)
			local window = topwindow
			while window do
				window:dispatchNewEvent(EVENT_HIDE)
				window:dispatchNewEvent(EVENT_WINDOW_INACTIVE)
				if not window:canActivateScreensaver() then
					-- #13412
					appletManager:callService("restartScreenSaverTimer")
				end
				window = window.transparent and window:getLowerWindow() or nil
			end
		end
	end

	-- hide windows with autoHide enabled
	while stack[idx + 1] ~= nil and stack[idx + 1].autoHide do
		stack[idx + 1]:hide()
	end

	Framework:reDraw(nil)
end


--[[

=head2 jive.ui.Window:showInstead(transition)

Shows this window as a replacement for the window at the top of the window stack. The I<transition> is used to move the window on stage.

=cut
--]]
function showInstead(self, transition)
	local stack = Framework.windowStack

	local idx = 1
	local topwindow = stack[idx]
	while topwindow and topwindow.alwaysOnTop do
		idx = idx + 1
		topwindow = stack[idx]
	end

	self:show(transition)
	topwindow:hide()
end


--[[

Push window below any screensavers on the window stack, this window will then be visible when the screensaver exits. If no screensavers are on the stack then the window is shown.

--]]
function showAfterScreensaver(self, transition)
	local stack = Framework.windowStack

	local idx = 1
	local topwindow = stack[idx]
	while topwindow and topwindow.isScreensaver do
		idx = idx + 1
		topwindow = stack[idx]
	end

	if idx == 1 then
		return self:show(transition)
	end

	table.insert(stack, idx, self)
end


--[[

=head2 jive.ui.Window:replace(toReplace, transition)

Replaces toReplace window with a new window object


=cut
--]]

function replace(self, toReplace, transition)
	local stack = Framework.windowStack

	local topWindow = 1
	for i in ipairs(stack) do
		if stack[i] == toReplace then
			if i == topWindow then
				self:showInstead(transition)
			else
				-- the old window may still be visible under
				-- a transparent window, if so hide it
				local oldwindow = stack[i]
				if oldwindow.visible then
					oldwindow:dispatchNewEvent(EVENT_HIDE)
				end

				-- old windw is being removed from the window
				-- stack
				oldwindow:dispatchNewEvent(EVENT_WINDOW_POP)

				-- remove the window if it is already in the
				-- stack
				local onstack = table.delete(stack, self)

				if not onstack then
					-- this window is being pushed to the
					-- stack
					self:dispatchNewEvent(EVENT_WINDOW_PUSH)
				end


				stack[i] = self

				-- if the old window was visible, the new one
				-- is now 
				if oldwindow.visible then
					self:dispatchNewEvent(EVENT_SHOW)
				end
			end
		end
	end
end

--[[

=head2 jive.ui.Window:showBriefly(msecs, closure, pushTransition, popTransition)

Shows this window briefly for I<msecs> milliseconds. When the timeout occurs, or a key has been pressed then window is hidden and the I<closure> is called. The I<pushTransition> and I<popTransition> transitions are used to move the window on and off stage.

If the window has already been displayed with showBriefly then the timer is restarted with the new I<msecs> value.

=cut
--]]
function showBriefly(self, msecs, callback,
		     pushTransition,
		     popTransition)

	self:setTransient(true)
	if not self.visible and self.brieflyTimer ~= nil then
		--other source may have hidden then window, but not cleaned up the timer.
		 -- Without this visible check, the "briefly" window would not appear until the old timer timeout
		self.brieflyTimer:stop()
		self.brieflyTimer = nil

	end

	if self.brieflyTimer ~= nil then
		if msecs then
			self.brieflyTimer:setInterval(msecs)
		else
			self.brieflyTimer:restart()
		end

		return

	elseif msecs == nil then
		return
	end

	if callback then
		self:addListener(EVENT_WINDOW_POP, callback)
	end

	if self.brieflyHandler == nil then
		self.brieflyHandler =
			self:addListener(bit.bor(ACTION, EVENT_CHAR_PRESS, EVENT_KEY_PRESS, EVENT_SCROLL, EVENT_MOUSE_PRESS, EVENT_MOUSE_HOLD, EVENT_MOUSE_DRAG),
					 function(event)
						 self:hide(popTransition, "NONE")
						 return EVENT_CONSUME
					 end)
	end

	self.brieflyTimer = Timer(msecs,
				  function(timer)
					  self.brieflyTimer = nil
					  self:hide(popTransition, "NONE")
				  end,
				  true)
	self.brieflyTimer:start()

	self:show(pushTransition)
end


--static method
function getTopNonTransientWindow(self)
	local stack = Framework.windowStack

	local idx = 1
	local topwindow = stack[idx]
	while topwindow and topwindow.transient do
		idx = idx + 1
		topwindow = stack[idx]
	end

	return topwindow
end


function hideContextMenus(self)
	local top = getTopNonTransientWindow(self)
	while top and top:isContextMenu() do
		top:hide()
		top = getTopNonTransientWindow(self)
	end
end

--[[

=head2 jive.ui.Window:hide(transition)

Hides this window. It it is currently at the top of the window stack then the I<transition> is used to move the window off stage.

=cut
--]]
function hide(self, transition)
	local stack = Framework.windowStack

	local wasVisible = self.visible

	-- remove the window from window stack
	table.delete(stack, self)

	-- find top window, ignoring always on top windows
	local idx = 1
	local topwindow = stack[idx]
	while topwindow and topwindow.alwaysOnTop do
		idx = idx + 1
		topwindow = stack[idx]
	end

	if wasVisible and topwindow then
		-- top window is now active and visible, if the top window
		-- is transparent also dispatch events to the lower window(s)
		local window = topwindow
		while window do
			window:dispatchNewEvent(EVENT_WINDOW_ACTIVE)
			window:dispatchNewEvent(EVENT_SHOW)

			window = window.transparent and window:getLowerWindow() or nil
		end

		topwindow:reDraw()

		-- push transitions
		transition = transition or self._DEFAULT_HIDE_TRANSITION
		Framework:_startTransition(_newTransition(transition, self, topwindow))
	end

	if self.visible then
		-- this window and widgets are now not visible
		self:dispatchNewEvent(EVENT_HIDE)

		-- this window is inactive
		if not self:canActivateScreensaver() then
			-- #13412
			appletManager:callService("restartScreenSaverTimer")
		end
		self:dispatchNewEvent(EVENT_WINDOW_INACTIVE)
	end

	self:dispatchNewEvent(EVENT_WINDOW_POP)
end


--[[

=head2 jive.ui.Window:hideToTop(transition)

Hide from this window to the top if the window stack.

=cut
--]]
function hideToTop(self, transition)
	local stack = Framework.windowStack

	for i=1,#stack do
		if stack[i] == self then
			for j=i,1,-1 do
				stack[j]:hide(transition)
			end
		end
	end
end

function moveToTop(self, transition)
	if Framework:isCurrentWindow(self) then
		return
	end
	self:hide()
	self:show(transition)
end

--[[

=head2 jive.ui.Window:autoHide(enabled)

If autoHide is enabled then the window is automatically
hidden when another window is shown above it. This is useful
for hiding popup windows so they do not appear if the user
moves back.

==cut
--]]
function setAutoHide(self, enabled)
	self.autoHide = enabled and true or nil
end


function bumpDown(self)
	Framework:_startTransition(self:transitionBumpDown(self))
end


function bumpUp(self)
	Framework:_startTransition(self:transitionBumpUp(self))
end

--[[

=head2 jive.ui.Window:bumpLeft()

Makes the window bump left.

=cut
--]]
function bumpLeft(self)
	Framework:_startTransition(self:transitionBumpLeft(self))
end


--[[

=head2 jive.ui.Window:bumpRight()

Makes the window bump right.

=cut
--]]
function bumpRight(self)
	Framework:_startTransition(self:transitionBumpRight(self))
end


--[[

=head2 jive.ui.Window:hideAll()

Hides all windows, removing them from the window stack.

=cut
--]]
function hideAll(self)
	local stack = Framework.windowStack

	-- hide windows in reverse order
	for i=#stack, 1, -1 do
		stack[i]:hide()
	end

	-- FIXME window events
end


--[[

=head2 jive.ui.Window:getWindowId()

Returns the windowId of a window

=cut
--]]
function getWindowId(self)
	return self.windowId
end


--[[

=head2 jive.ui.Window:setWindowId()

Sets the windowId of a window

=cut
--]]
function setWindowId(self, id)
	self.windowId = id
end


--[[

=head2 jive.ui.Window:getTitle()

Returns the text of the title widget.

=cut
--]]
function getTitle(self)
	if self.title then
		if self.title:getWidget('text') then
			return self.title:getWidget('text'):getValue()
		end
	end
	return nil
end

--[[

=head2 jive.ui.Window:getTitleWidget()

Returns the window's title widget.

=cut
--]]
function getTitleWidget(self)
	if self.title then
		return self.title
	end
	return nil
end


--[[

=head2 jive.ui.Window:getTitleStyle()

Returns the style of the title widget.

=cut
--]]
function getTitleStyle(self)
	if self.title then
		if self.title:getWidget('text') then
			return self.title:getWidget('text'):getStyle()
		end
	end
	return nil
end


--[[

=head2 jive.ui.Window:setTitle(title)

Sets the windows title to I<title>.

=cut
--]]
function setTitle(self, title)
	if self.title then
		self.title:setWidgetValue("text", title)
	else
		self:setIconWidget("text", Label("text", title))
	end
end


--[[

Sets (or adds) a widget into the title. This is used by Menu to add a 'position' widget with "X of Y" text into the appropraite windows.

--]]
function setIconWidget(self, widgetKey, widget)
	if not self.title then
		self:setTitleWidget(Group("title", {}))
	end

	self.title:setWidget(widgetKey, widget)
end


function getIconWidget(self, widgetKey)
	if not self.title then
		return nil
	end

	return self.title:getWidget(widgetKey)
end


--[[

Sets the style of a title widget, default options are 'icon', 'lbutton', 'rbutton', 'text'. This probably would only be used to modify the icon style.

--]]
function setIconStyle(self, widgetKey, widgetStyle)
	self.title:getWidget(widgetKey):setStyle(widgetStyle)
end


function setDefaultLeftButtonAction(self)
	self:setIconWidget("lbutton", self:createDefaultLeftButton())
end


function setDefaultRightButtonAction(self)
	self:setIconWidget("rbutton", self:createDefaultRightButton())
end


--static method
function createDefaultLeftButton(self)
	return self:createButtonActionButton("title_left_press", "title_left_hold", "soft_reset", true)
end

--static method
function createDefaultRightButton(self)
	return self:createButtonActionButton("title_right_press", "title_right_hold", "soft_reset", true)
end

--[[

Sets a button action. This sets both the action and button style (using "button_" .. buttonAction).

--]]
function setButtonAction(self, buttonKey, buttonAction, buttonHoldAction, buttonLongHoldAction, isDefaultButtonGroup)
	self:setIconWidget(buttonKey, self:createButtonActionButton(buttonAction, buttonHoldAction, buttonLongHoldAction, isDefaultButtonGroup))
end


--static method
function createButtonActionButton(self, buttonAction, buttonHoldAction, buttonLongHoldAction, isDefaultButtonGroup)
	local buttonFunc = nil
	local buttonHoldFunc = nil
	local buttonLongHoldFunc = nil

	if buttonAction then
		buttonFunc = function()
			Framework:pushAction(buttonAction)
		end
	end
	if buttonHoldAction then
		buttonHoldFunc = function()
			Framework:pushAction(buttonHoldAction)
		end
	end
	if buttonLongHoldAction then
		buttonLongHoldFunc = function()
			Framework:pushAction(buttonLongHoldAction)
		end
	end

	local actionStyle = Framework:getActionToActionTranslation(buttonAction)
	if not actionStyle or actionStyle == "disabled" then
		actionStyle = "none"
	end

	local group = Group("button_" .. actionStyle, {
		icon = Icon("icon"),
		icon_text = Label("text"),
	})

	local button = Button(group, buttonFunc, buttonHoldFunc, buttonLongHoldFunc)
	button.isDefaultButtonGroup = isDefaultButtonGroup

	return button
end


-- deprecated
function setTitleIcon(self, iconName, iconStyle)
	assert(false)
end


--[[

=head2 jive.ui.Window:setTitleStyle(style)

Sets the windows title style to I<style>.

Deprecated, still used by SlimBrowser.

=cut
--]]
function setTitleStyle(self, style)
	if self.title then
		self.title:setStyle(style)
	end
end


--[[

=head2 jive.ui.Window:setTitleWidget(titleWidget)

Sets the windows title to I<titleWidget>.

Deprecated, still used by SlimBrowser.

=cut
--]]
function setTitleWidget(self, titleWidget)
	_assert(oo.instanceof(titleWidget, Widget), "setTitleWidget(widget): widget is not an instance of Widget!")

	if self.title then
		self.title:_event(Event:new(EVENT_FOCUS_LOST))
		self:removeWidget(self.title)
	end

	self.title = titleWidget
	self:_addWidget(self.title)
	self.title:_event(Event:new(EVENT_FOCUS_GAINED))
end


--[[

=head2 jive.ui.Window:getWindow()

Returns I<self>.

=cut
--]]
function getWindow(self)
	return self
end


--[[

=head2 jive.ui.Window:lowerWindow(self)

Returns the window beneath this window in the window stack.

=cut
--]]
function getLowerWindow(self)
	for i = 1,#Framework.windowStack do
		if Framework.windowStack[i] == self then
			return Framework.windowStack[i + 1]
		end
	end
	return nil
end


--[[

=head2 jive.ui.Window:addWidget(widget)

Add the widget I<widget> to the window.

=cut
--]]
function addWidget(self, widget)
	_assert(oo.instanceof(widget, Widget), "addWidget(widget): widget is not an instance of Widget!")

	if widget.parent then
		log:error("Adding widget (", widget, ") to window, but it already has a parent (", widget.parent, ")")
	end

	_addWidget(self, widget)

	-- FIXME last widget added always has focus
	self:focusWidget(widget)
end

function _addWidget(self, widget)
	self.widgets[#self.widgets + 1] = widget
	widget.parent = self
	widget:reSkin()

	if self:isVisible() then
		widget:dispatchNewEvent(EVENT_SHOW)
	end
end


--[[

=head2 jive.ui.Window:removeWidget(widget)

Remove the widget I<widget> from the window.

=cut
--]]
function removeWidget(self, widget)
	_assert(oo.instanceof(widget, Widget))

	if widget.parent ~= self then
		log:error("Removing widget (", widget, ") from window, but is has a different parent (", widget.parent, ")")
	end

	if self:isVisible() then
		widget:dispatchNewEvent(EVENT_HIDE)
	end
	widget.parent = nil

	table.delete(self.widgets, widget)

	self:reLayout()
end


--[[

=head2 jive.ui.Window:focusWidget(widget)

Make the I<widget> have the focus. This widget will be forwarded
events from the window, and should animate (if applicable).

=cut
--]]
function focusWidget(self, widget)
	_assert(widget == nil or oo.instanceof(widget, Widget))
	_assert(widget == nil or table.contains(self.widgets, widget))

	if self.focus and self.focus ~= self.title then
		self.focus:_event(Event:new(EVENT_FOCUS_LOST))
	end

	self.focus = widget
	if self.focus then
		self.focus:_event(Event:new(EVENT_FOCUS_GAINED))
	end
end


function getAllowScreensaver(self)
	return self.allowScreensaver
end


function setAllowScreensaver(self, allowScreensaver)
	_assert(type(allowScreensaver) == "boolean" or type(allowScreensaver) == "function")

	self.allowScreensaver = allowScreensaver
	-- FIXME disable screensaver if active?
end


function canActivateScreensaver(self)
	if self.allowScreensaver == nil then
		return true
	elseif type(self.allowScreensaver) == "function" then
		return self.allowScreensaver()
	else
		return self.allowScreensaver
	end
end


function getIsScreensaver(self)
	return self.isScreensaver
end


function setIsScreensaver(self, isScreensaver)
	self.isScreensaver = isScreensaver
end


function getAllowPowersave(self)
	return self.allowPowersave
end


function setAllowPowersave(self, allowPowersave)
	_assert(type(allowPowersave) == "boolean" or type(allowPowersave) == "function")

	self.allowPowersave = allowPowersave
end


function canActivatePowersave(self)
	if self.allowPowersave == nil then
		return true
	elseif self.allowPowersave == "function" then
		return self.allowPowersave()
	else
		return self.allowPowersave
	end
end


function getAlwaysOnTop(self)
	return self.alwaysOnTop
end


function setAlwaysOnTop(self, alwaysOnTop)
	_assert(type(alwaysOnTop) == "boolean")

	self.alwaysOnTop = alwaysOnTop
	-- FIXME modify window position if already shown?
end

--Used, for example, by context menu handling so that a context menu doesn't exit when Popups and showBrieflies occur
function getTransient(self)
	return self.transient
end


function setTransient(self, transient)
	_assert(type(transient) == "boolean")

	self.transient = transient
end


function getShowFrameworkWidgets(self)
	return self.showFrameworkWidgets
end


function setShowFrameworkWidgets(self, showFrameworkWidgets)
	_assert(type(showFrameworkWidgets) == "boolean")

	self.showFrameworkWidgets = showFrameworkWidgets
	self:reLayout()
end


function getTransparent(self)
	return self.transparent
end


function setTransparent(self, transparent)
	_assert(type(transparent) == "boolean")

	self.transparent = transparent
	self:reLayout()
end


function setContextMenu(self, contextMenu)
	_assert(type(contextMenu) == "boolean")

	self.contextMenu = contextMenu
	self:reLayout()
end


function isContextMenu(self)
	return self.contextMenu
end


function setSkin(self, skin)
	 self.skin = skin
end


function getSkin(self)
	 return self.skin
end


function __tostring(self)
	if self.title then
		return "Window(" .. tostring(self.title) .. ")"
	else
		return "Window()"
	end
end


-- Create a new transition. This wrapper is lets transitions to be used
-- underneath transparent windows (e.g. popups)
function _newTransition(transition, oldwindow, newwindow)
	local f = transition(oldwindow, newwindow)
	if not f then
		return f
	end

	local idx = 1
	local windows = {}

	local w = Framework.windowStack[idx]
	while w ~= oldwindow and w ~= newwindow and w.transparent do
		table.insert(windows, 1, w)

		idx = idx + 1
		w = Framework.windowStack[idx]
	end

	if #windows then
		return function(widget, surface)
			       f(widget, surface)

			       for i,w in ipairs(windows) do
				       w:draw(surface, LAYER_CONTENT)
			       end
		       end
	else
		return f
	end
end


--[[

=head2 jive.ui.Window:transitionNone()

Returns an empty window transition. i.e. the window is just displayed without any animations.

=cut
--]]
function transitionNone(self)
	return nil
end


--with animation in both directions
function transitionBumpDown(self)

	local frames = 1
	local screenWidth = Framework:getScreenSize()
	local inReturn = false
	return function(widget, surface)
			local y = frames * 3

			self:draw(surface, bit.bor(LAYER_FRAME, LAYER_LOWER))
			surface:setOffset(0, y / 2)
			self:draw(surface, bit.bor(LAYER_CONTENT, LAYER_CONTENT_OFF_STAGE, LAYER_CONTENT_ON_STAGE, LAYER_TITLE))
			surface:setOffset(0, 0)

			if not inReturn and frames < 2 then
				frames = frames + 1

			else
				inReturn = true
				frames = frames - 1
			end

			if frames == 0 then
				Framework:_killTransition()
			end
		end
end

--with animation in both directions
function transitionBumpUp(self)

	local frames = 1
	local screenWidth = Framework:getScreenSize()
	local inReturn = false
	return function(widget, surface)
			local y = frames * 3

			self:draw(surface, bit.bor(LAYER_FRAME, LAYER_LOWER))
			surface:setOffset(0, -y / 2)
			self:draw(surface, bit.bor(LAYER_CONTENT, LAYER_CONTENT_OFF_STAGE, LAYER_CONTENT_ON_STAGE, LAYER_TITLE))
			surface:setOffset(0, 0)

			if not inReturn and frames < 2 then
				frames = frames + 1

			else
				inReturn = true
				frames = frames - 1
			end

			if frames == 0 then
				Framework:_killTransition()
			end
		end
end

--[[

=head2 jive.ui.Window:transitionBumpLeft()

Returns a bump left window transition.

=cut
--]]
function transitionBumpLeft(self)

	local frames = 2
	local screenWidth = Framework:getScreenSize()

	return function(widget, surface)
			local x = frames * 3

			if widget._bg then
				widget._bg:blit(surface, 0, 0)
			end
			self:draw(surface, LAYER_LOWER)
			surface:setOffset(x, 0)
			self:draw(surface, bit.bor(LAYER_CONTENT, LAYER_CONTENT_OFF_STAGE, LAYER_CONTENT_ON_STAGE, LAYER_TITLE))
			surface:setOffset(0, 0)
			self:draw(surface, LAYER_FRAME)

			frames = frames - 1
			if frames == 0 then
				Framework:_killTransition()
			end
		end
end


--[[

=head2 jive.ui.Window:transitionBumpRight()

Returns a bump right window transition.

=cut
--]]
function transitionBumpRight(self)

	local frames = 2
	local screenWidth = Framework:getScreenSize()

	return function(widget, surface)
			local x = frames * 3

			if widget._bg then
				widget._bg:blit(surface, 0, 0)
			end
			self:draw(surface, LAYER_LOWER)
			surface:setOffset(-x, 0)
			self:draw(surface, bit.bor(LAYER_CONTENT, LAYER_CONTENT_OFF_STAGE, LAYER_CONTENT_ON_STAGE, LAYER_TITLE))
			surface:setOffset(0, 0)
			self:draw(surface, LAYER_FRAME)

			frames = frames - 1
			if frames == 0 then
				Framework:_killTransition()
			end
		end
end


function transitionPushLeftStaticTitle(oldWindow, newWindow)
	return _transitionPushLeft(oldWindow, newWindow, true)
end

--[[

=head2 jive.ui.Window:transitionPushLeft(newWindow)

Returns a push right window transition.

=cut
--]]
function transitionPushLeft(oldWindow, newWindow)
	return _transitionPushLeft(oldWindow, newWindow, false)
end


function _transitionPushLeft(oldWindow, newWindow, staticTitle)
	_assert(oo.instanceof(oldWindow, Widget))
	_assert(oo.instanceof(newWindow, Widget))

	local startT
	local transitionDuration = HORIZONTAL_PUSH_TRANSITION_DURATION
	local remaining = transitionDuration
	local screenWidth = Framework:getScreenSize()
	local scale = (transitionDuration * transitionDuration * transitionDuration) / screenWidth
	local animationCount = 0
	return function(widget, surface)
			if animationCount == 0 then
				--getting start time on first loop avoids initial delay that can occur
				startT = Framework:getTicks()
			end
			local x = math.ceil(screenWidth - ((remaining * remaining * remaining) / scale))

			surface:setOffset(0, 0)
			if oldWindow._bg then
				oldWindow._bg:blit(surface, 0, 0)
			end
			if staticTitle then
				newWindow:draw(surface, bit.bor(LAYER_LOWER, LAYER_TITLE))
			else
				newWindow:draw(surface, LAYER_LOWER)
			end

			surface:setOffset(-x, 0)
			if staticTitle then
				oldWindow:draw(surface, bit.bor(LAYER_CONTENT, LAYER_CONTENT_OFF_STAGE) )
			else
				oldWindow:draw(surface, bit.bor(LAYER_CONTENT, LAYER_CONTENT_OFF_STAGE, LAYER_TITLE))
			end

			surface:setOffset(screenWidth - x, 0)
			if staticTitle then
				newWindow:draw(surface, bit.bor(LAYER_CONTENT, LAYER_CONTENT_ON_STAGE))
			else
				newWindow:draw(surface, bit.bor(LAYER_CONTENT, LAYER_CONTENT_ON_STAGE, LAYER_TITLE))
			end

			surface:setOffset(0, 0)
			newWindow:draw(surface, LAYER_FRAME)
			
			local elapsed = Framework:getTicks() - startT
			remaining = transitionDuration - elapsed

			if remaining <= 0 or x >= screenWidth then
				Framework:_killTransition()
			end
			animationCount = animationCount + 1
		end
end


function transitionPushRightStaticTitle(oldWindow, newWindow)
	return _transitionPushRight(oldWindow, newWindow, true)
end


--[[

=head2 jive.ui.Window:transitionPushRight(newWindow)

Returns a push right window transition.

=cut
--]]
function transitionPushRight(oldWindow, newWindow)
	return _transitionPushRight(oldWindow, newWindow, false)
end


function _transitionPushRight(oldWindow, newWindow, staticTitle)
	_assert(oo.instanceof(oldWindow, Widget))
	_assert(oo.instanceof(newWindow, Widget))

	local startT
	local transitionDuration = HORIZONTAL_PUSH_TRANSITION_DURATION
	local remaining = transitionDuration
	local screenWidth = Framework:getScreenSize()
	local scale = (transitionDuration * transitionDuration * transitionDuration) / screenWidth
	local animationCount = 0
	return function(widget, surface)
			if animationCount == 0 then
				--getting start time on first loop avoids initial delay that can occur
				startT = Framework:getTicks()
			end
			local x = math.ceil(screenWidth - ((remaining * remaining * remaining) / scale))

			surface:setOffset(0, 0)
			if oldWindow._bg then
				oldWindow._bg:blit(surface, 0, 0)
			end
			if staticTitle then
				newWindow:draw(surface, bit.bor(LAYER_LOWER, LAYER_TITLE))
			else
				newWindow:draw(surface, LAYER_LOWER)
			end

			surface:setOffset(x, 0)
			if staticTitle then
				oldWindow:draw(surface, bit.bor(LAYER_CONTENT, LAYER_CONTENT_OFF_STAGE) )
			else
				oldWindow:draw(surface, bit.bor(LAYER_CONTENT, LAYER_CONTENT_OFF_STAGE, LAYER_TITLE) )
			end

			surface:setOffset(x - screenWidth, 0)
			if staticTitle then
				newWindow:draw(surface, bit.bor(LAYER_CONTENT, LAYER_CONTENT_ON_STAGE) )
			else
				newWindow:draw(surface, bit.bor(LAYER_CONTENT, LAYER_CONTENT_ON_STAGE, LAYER_TITLE) )
			end

			surface:setOffset(0, 0)
			newWindow:draw(surface, LAYER_FRAME)

			local elapsed = Framework:getTicks() - startT
			remaining = transitionDuration - elapsed

			if remaining <= 0 or x >= screenWidth then
				Framework:_killTransition()
			end
			animationCount = animationCount + 1
		end
end


--[[

=head2 jive.ui.Window:transitionFadeIn(newWindow)

Returns a fade in window transition.

=cut
--]]
function transitionFadeIn(oldWindow, newWindow)
	return _transitionFadeIn(oldWindow, newWindow, 400)
end

function transitionFadeInFast(oldWindow, newWindow)
	return _transitionFadeIn(oldWindow, newWindow, 100)
end


function _transitionFadeIn(oldWindow, newWindow, duration)
	_assert(oo.instanceof(oldWindow, Widget))
	_assert(oo.instanceof(newWindow, Widget))


	local startT
	local transitionDuration = duration
	local remaining = transitionDuration
	local screenWidth = Framework:getScreenSize()
	local scale = (transitionDuration * transitionDuration * transitionDuration) / screenWidth
	local animationCount = 0

	local scale = 255 / transitionDuration

	local bgImage = Framework:getBackground()

	local sw, sh = Framework:getScreenSize()
	local srf = Surface:newRGB(sw, sh)

	-- assume old window is not updating
	bgImage:blit(srf, 0, 0, sw, sh)
	oldWindow:draw(srf, LAYER_ALL)

	return function(widget, surface)
			if animationCount == 0 then
				--getting start time on first loop avoids initial delay that can occur
				startT = Framework:getTicks()
			end
			local x = tonumber(math.floor((remaining * scale) + .5))

			--support background surfaces, used for instance by ContextMenuWindow
			if newWindow._bg then
				newWindow._bg:blit(surface, 0, 0)
			end
			newWindow:draw(surface, LAYER_ALL)
			srf:blitAlpha(surface, 0, 0, x)

			local elapsed = Framework:getTicks() - startT
			remaining = transitionDuration - elapsed

			if remaining <= 0 then
				Framework:_killTransition()
			end
			animationCount = animationCount + 1
		end
end


--[[

=head2 jive.ui.Window:transitionPushPopupUp(newWindow)

Returns a push up window transition for use with popup windows.

=cut
--]]
function transitionPushPopupUp(oldWindow, newWindow)
	_assert(oo.instanceof(oldWindow, Widget))
	_assert(oo.instanceof(newWindow, Widget))

	local _, screenHeight = Framework:getScreenSize()

	local frames = math.ceil(FRAME_RATE / 6)
	local _,_,_,windowHeight = newWindow:getBounds()
	local scale = (frames * frames * frames) / windowHeight

	return function(widget, surface)
			local y = ((frames * frames * frames) / scale)

			surface:setOffset(0, 0)
			oldWindow:draw(surface, LAYER_ALL)

			surface:setOffset(0, y)
			newWindow:draw(surface, bit.bor(LAYER_CONTENT, LAYER_CONTENT_OFF_STAGE) )

			surface:setOffset(0, 0)

			frames = frames - 1
			if frames == 0 then
				Framework:_killTransition()
			end
		end
end


--[[

=head2 jive.ui.Window:transitionPushPopupDown(newWindow)

Returns a push down window transition for use with popup windows.

=cut
--]]
function transitionPushPopupDown(oldWindow, newWindow)
	_assert(oo.instanceof(oldWindow, Widget))
	_assert(oo.instanceof(newWindow, Widget))

	local _, screenHeight = Framework:getScreenSize()

	local frames = math.ceil(FRAME_RATE / 6)
	local _,_,_,windowHeight = oldWindow:getBounds()
	local scale = (frames * frames * frames) / windowHeight

	return function(widget, surface)
			local y = ((frames * frames * frames) / scale)

			surface:setOffset(0, 0)
			newWindow:draw(surface, LAYER_ALL)

			surface:setOffset(0, windowHeight - y)
			oldWindow:draw(surface, bit.bor(LAYER_CONTENT, LAYER_CONTENT_OFF_STAGE) )

			surface:setOffset(0, 0)

			frames = frames - 1
			if frames == 0 then
				Framework:_killTransition()
			end
		end
end


--[[

=head2 jive.ui.Window:noLayout()

Layout function that does not modify the window layout

=cut
--]]
function noLayout(self)
	-- maximum window size is bounded by screen
	local sw, sh = Framework:getScreenSize()

	-- prefered window size set in style
	local _wx, _wy, _ww, _wh = self:getPreferredBounds()
	local wlb,wtb,wrb,wbb = self:getBorder()
	ww = (_ww or sw) - wlb - wrb
	wh = (_wh or sh) - wtb - wbb

	self:setBounds(wx, wy, ww, wh)
end


--[[

=head2 jive.ui.Window:borderLayout(window)

Layout function similar to the Java Border Layout.

=cut
--]]
function borderLayout(self, fitWindow)
	-- maximum window size is bounded by screen
	local sw, sh = Framework:getScreenSize()

	-- prefered window size set in style
	local _wx, _wy, _ww, _wh = self:getPreferredBounds()
	local wlb,wtb,wrb,wbb = self:getBorder()
	ww = (_ww or sw) - wlb - wrb
	wh = (_wh or sh) - wtb - wbb

	-- utility function to limit bounds to window size
	local maxBounds = function(x, y, w, h)
				  w = min(ww, w)
				  h = min(wh, h)
				  return x, y, w, h
			  end

	-- find prefered widget sizes
	local maxN, maxE, maxS, maxW, maxX, maxY = 0, 0, 0, 0, 0, 0
	self:iterate(
		function(widget)
			local x,y,w,h = widget:getPreferredBounds()
			local lb,tb,rb,bb = widget:getBorder()
			local position = widget:styleInt("position") or LAYOUT_CENTER

			--log:debug("x=", x, " y=", y, " w=", w, " h=", h)

			if position == LAYOUT_NORTH then
				h = h + tb + bb or tb + bb
				maxN = max(h, maxN)

				if w then
					w = w + lb + rb
					w = min(w, sw - lb - rb)
					maxX = max(w, maxX)
				end

			elseif position == LAYOUT_SOUTH then
				h = h + tb + bb or tb + bb
				maxS = max(h, maxS)

				if w then
					w = w + lb + rb
					w = min(w, sw - lb - rb)
					maxX = max(w, maxX)
				end

			elseif position == LAYOUT_EAST then
				w = w + lb + rb or lb + rb
				w = min(w, sw - lb - rb)
				maxE = max(w, maxE)

			elseif position == LAYOUT_WEST then
				w = w + lb + rb or lb + rb
				w = min(w, sw - lb - rb)
				maxW = max(w, maxW)

			elseif position == LAYOUT_CENTER then
				if w then
					w = w + lb + rb
					w = min(w, sw - lb - rb)
					maxX = max(w, maxX)
				end
				if h then
					h = h + tb + bb
					maxY = max(h, maxY)
				end

			end
		end
	)

	--log:debug(" maxN=", maxN, " maxE=", maxE, " maxS=", maxS, " maxW=", maxW, " maxX=", maxX, " maxY=", maxY)

	-- adjust window bounds to fit content
	if fitWindow then
		if _wh == nil and maxY > 0 then
			wh = wtb + maxN + maxY + maxS + wbb
		end
		if _ww == nil and maxX > 0 then
			ww = wlb + maxE + maxX + maxW + wrb
		end
	end
	wx = (_wx or (sw - ww) / 2)
	wy = (_wy or (sh - wh) / 2)


	-- set widget bounds
	local cy = 0
	self:iterate(
		function(widget)
			local x,y,w,h = widget:getPreferredBounds()
			local lb,tb,rb,bb = widget:getBorder()
			local position = widget:styleInt("position") or LAYOUT_CENTER

			rb = rb + lb
			bb = bb + tb

			if position == LAYOUT_NORTH then
				x = x or 0
				y = y or 0
				w = w or ww
				w = min(ww, w) - rb

				widget:setBounds(maxBounds(wx + x + lb, wy + y + tb, w, h))

			elseif position == LAYOUT_SOUTH then
				x = x or 0
				y = y or (wh - maxS)
				w = w or ww
				w = min(ww, w) - rb

				widget:setBounds(maxBounds(wx + x + lb, wy + y + tb, w, h))

			elseif position == LAYOUT_EAST then
				x = x or (ww - maxE)
				y = y or 0
				widget:setBounds(maxBounds(wx + x + lb, wy + y + tb, w, wh - bb))

			elseif position == LAYOUT_WEST then
				x = x or 0
				y = y or 0
				widget:setBounds(maxBounds(wx + x + lb, wy + y + tb, w, wh - bb))

			elseif position == LAYOUT_CENTER then
				-- FIXME why does w-rb work, but h-bb lays out incorrectly?
				h = h or (wh - maxN - maxS)
				h = min(wh - maxN - maxS, h)
				w = w or (ww - maxW - maxE)
				w = min(ww - maxW - maxE, w) - rb

				widget:setBounds(maxBounds(wx + lb, wy + maxN + tb + cy, w, h))
				cy = cy + h + bb

			elseif position == LAYOUT_NONE then
				widget:setBounds(maxBounds(wx + x, wy + y, w, h))
			end
		end
	)

	-- set window bounds
	self:setBounds(wx, wy, ww, wh)
end


function _event(self, event)
	local notMouse = bit.band(event:getType(), EVENT_MOUSE_ALL) == 0

	local r
	if notMouse then
		r = self:_eventHandler(event)
	else
		--handle mouse locally, no need for C optimization on mouse platforms
		r = self:iterate(
			function(widget)
				if self._mouseEventFocusWidget == widget or (not self._mouseEventFocusWidget and widget:mouseInside(event)) then
					local rClosure = widget:_event(event)
					if rClosure ~= EVENT_UNUSED then
						--Consumer of MOUSE_DOWN that is in mouse bounds will be given mouse event focus
						if event:getType() == EVENT_MOUSE_DOWN then
							self:setMouseEventFocusWidget(widget)
						end
						return rClosure
					end

				end
			end
		)

		if event:getType() == EVENT_MOUSE_UP then
			self:setMouseEventFocusWidget(nil)
		end

	end

	if bit.band(r, EVENT_CONSUME) == 0 then
		r = Widget._event(self, event)
	end

	return r
end


function setMouseEventFocusWidget(self, widget)
	log:debug("setMouseEventFocusWidget: ", widget)

	self._mouseEventFocusWidget = widget
end


function _layout(self)
	local stableSortCounter = 1

	self.zWidgets = {}
	if self:getShowFrameworkWidgets() then
		--framework widgets added to iterator list first so that if default zorder is used,
		 -- framework widgets are drawn first - This is needed
		 -- to support, for instance, the SeupLanguage screen where iconbar (a framework widget) is shown behind
		 -- a mini-help window.
		for i, widget in ipairs(Framework:getWidgets()) do
			if widget then
				widget._stableSortIndex = stableSortCounter
				table.insert(self.zWidgets, widget)
				stableSortCounter = stableSortCounter + 1
			end
		end
	end

	for i, widget in ipairs(self.widgets) do
		if widget then
			widget._stableSortIndex = stableSortCounter
			table.insert(self.zWidgets, widget)

			stableSortCounter = stableSortCounter + 1
		end
	end


	table.sort(self.zWidgets,
		function(a, b)
			--stable sort (since quicksort isn't stable by default) --  also check for unset (happens before pack)
			if a:getZOrder() == b:getZOrder() or not a:getZOrder() or not b:getZOrder()then
				return a._stableSortIndex < b._stableSortIndex
			end
			return a:getZOrder() < b:getZOrder()
		end)

	self:_skinLayout()
end


--[[ C optimized:

jive.ui.Window:pack()
jive.ui.Window:draw()
jive.ui.Window:_eventHandler()

--]]

--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

