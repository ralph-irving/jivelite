
--[[
=head1 NAME

jive.ui.Widget - Base class for UI widgets.

=head1 DESCRIPTION

Base class for UI widgets.

=head1 SYNOPSIS

See examples in subclasses.

=head1 STYLE

All widgets support the following style parameters that can be set in the skin.

=over

B<x> : absolute x co-ordinate in pixels

B<y> : absolute y co-ordinate in pixels

B<w> : width in pixels, or WH_FILL to fill the available space.

B<h> : height in pixels

B<padding> : padding around the widget content in pixels. Defaults to 0.

B<padding-left> : padding on the left of the widget in pixels. Overrides padding is specified.

B<padding-top> : padding on the top of the widget in pixels. Overrides padding is specified.

B<padding-right> : padding on the right of the widget in pixels. Overrides padding is specified.

B<padding-bottom> : padding on the bottom of the widget in pixels. Overrides padding is specified.

B<layer> : the layer can be one of the following values.

=over 4

=item B<LAYER_FRAME>

Widgets in the Frame layer are not animated during window transitions.

=item B<LAYER_CONTENT>

Widgets in the Content layer are animated during window transitions. This is the default value.

=item B<LAYER_CONTENT_OFF_STAGE>

Widgets in  the Content Off Stage layer are only animated when moving off stage. These widgets are not drawn when moving on stage.

=item B<LAYER_CONTENT_ON_STAGE>

Widgets in  the Content On Stage layer are only animated when moving on stage. These widgets are not drawn when moving off stage.

=back

=head1 METHODS

=cut
--]]

-- stuff we use
local _assert, assert, ipairs, require, tostring, type, bit = _assert, assert, ipairs, require, tostring, type, bit

local oo            = require("loop.base")
local string        = require("string")
local table         = require("jive.utils.table")
local Event         = require("jive.ui.Event")
local Timer         = require("jive.ui.Timer")

local debug         = require("jive.utils.debug")
local log           = require("jive.utils.log").logger("jivelite.ui")

local FRAME_RATE    = jive.ui.FRAME_RATE
local EVENT_SHOW    = jive.ui.EVENT_SHOW
local EVENT_HIDE    = jive.ui.EVENT_HIDE
local EVENT_UPDATE  = jive.ui.EVENT_UPDATE
local EVENT_CONSUME = jive.ui.EVENT_CONSUME
local ACTION        = jive.ui.ACTION


-- our class
module(..., oo.class)

local Framework		= require("jive.ui.Framework")


-- Constructs a new widget. This is only used by subclasses
function __init(self, style)
	_assert(type(style) == "string", "Invalid style")

	return oo.rawnew(self, {
		bounds = { 0, 0, 0, 0 },
		-- FIXME: useless to assign nil here
		parent = nil, -- parent widget
		visible = false, -- are we on stage?
		timers = {}, -- all timers associated with this widget
		listeners = {}, -- event callback functions
		animations = {}, -- amination functions
		style = style,
	})
end


--[[

=head2 jive.ui.Widget:iterate(closure)

Calls the function closure for all widgets contained by this widget. This
is overridden by subclasses.

=cut
--]]
function iterate(self, closure)
end


--[[

=head2 jive.ui.Widget:getPosition()

Returns I<x, y> the widgets position.

=cut
--]]
-- C implementation


--[[

=head2 jive.ui.Widget:setBounds(x, y, w, h)

Sets the widgets bounds to I<x, y, w, h>

=cut
--]]
-- C implementation


--[[

=head2 jive.ui.Widget:getSize()

Returns I<w, h> the widgets size.

=cut
--]]
function getSize(self)
	local x,y,w,h = self:getBounds()
	return w,h
end


--[[

=head2 jive.ui.Widget:setSize(w, h)

Sets the widgets size to I<w, h>

=cut
--]]
function setSize(self, w, h)
	_assert(type(w) == "number", "Invalid width")
	_assert(type(h) == "number", "Invalid height")

	self:setBounds(nil, nil, w, h)
end


--[[

=head2 jive.ui.Widget:getPosition()

Returns the widgets x,y position.

=cut
--]]
function getPosition(self)
	local x,y,w,h = self:getBounds()
	return x,y
end


--[[

=head2 jive.ui.Widget:setPosition(x, y)

Sets the widgets x,y position.

=cut
--]]
function setPosition(self, x, y)
	_assert(type(x) == "number", "Invalid x")
	_assert(type(y) == "number", "Invalid y")

	self:setBounds(x, y, nil, nil)
end


--[[

=head2 jive.ui.Widget:getStyle()

Returns the widgets style.

=cut
--]]
function getStyle(self)
	return self.style
end


--[[

=head2 jive.ui.Widget:setStyle(style)

Sets the widgets style.

=cut
--]]
function setStyle(self, style)
	_assert(type(style) == "string", "Invalid style")

	if (self.style == style) then
		return
	end

	self.style = style
	self:reSkin()

	self:iterate(function(widget) widget:reSkin() end)
end


--[[

=head2 jive.ui.Widget:getStyleModifier()

Returns the widgets style modifier.

=cut
--]]
function getStyleModifier(self)
	return self.styleModifier
end


--[[

=head2 jive.ui.Widget:setStyleModifier(styleModifier)

Sets the widgets style modifier.

=cut
--]]
function setStyleModifier(self, styleModifier)
	if self.styleModifier == styleModifier then
		return
	end

	self.styleModifier = styleModifier
	self:reSkin()

	self:iterate(function(widget) widget:reSkin() end)
end


--[[

=head2 jive.ui.Widget:isVisible()

Returns true if the widget is visible, otherwise returns false.

=cut
--]]
function isVisible(self)
	return self.visible
end


--[[

=head2 jive.ui.Widget:hide()

Hides the window containing this widget.

=cut
--]]
function hide(self, ...)
	local window = self:getWindow()
	if window then
		window:hide(...)
	end
end


--[[

=head2 jive.ui.Widget:getParent()

Returns the widgets parent.

=cut
--]]
function getParent(self)
	return self.parent
end


--[[

=head2 jive.ui.Widget:getWindow()

Returns the window containing this widget, or nil if the widget is not in a window.

=cut
--]]
function getWindow(self)
	if self.parent then
		return self.parent:getWindow()
	end
	return nil
end


--[[

=head2 jive.ui.Widget:reSkin()

Called when the widget content or appearence has changed. This will make sure the
widget is packed and any layout updated before it is redrawn.

=cut
--]]
-- C function


--[[

=head2 jive.ui.Widget:reLayout()

Called when the widget has change position or size. This will make sure the widget
is layout is updated before it is redrawn.

=cut
--]]
-- C function


--[[

=head2 jive.ui.Widget:reDraw()

Marks the bounding box of this widget for redrawing.

=cut
--]]
-- C function


--[[

=head2 jive.ui.Widget:checkSkin()

Updates the widgets skin if required.

=cut
--]]
-- C function


--[[

=head2 jive.ui.Widget:checkLayout()

Prepares the widgets contents and performs layout if required. Also calls do
layout on any child widgets.

=cut
--]]
-- C function


function _skin(self)
	-- must be overridden by widgets
	assert(false)
end


function _layout(self)
	-- must be overridden by widgets
	assert(false)
end


function draw(self)
	-- must be overridden by widgets
	assert(false)
end


--[[

=head2 jive.ui.Widget:addListener(mask, listener)

Add a listener I<listener> to the widget. The listener is called for events that match the event mask I<mask>. Returns a I<handle> to use in removeListener().

=cut
--]]
function addListener(self, mask, listener)
	_assert(type(mask) == "number", "Invalid event mask")
	_assert(type(listener) == "function", "Invalid listener")

	local handle = { mask, listener }
	table.insert(self.listeners, 1, handle)

	return handle
end


function addActionListener(self, action, obj, listener)
	_assert(type(listener) == "function")

	local callerInfo = "N/A"
	if log:isDebug() then
		callerInfo = Framework:callerToString()
	end
	
	if not Framework:_getActionEventIndexByName(action) then
		log:error("action name not registered:(" , action, "). Available actions: ", Framework:dumpActions() )
		return 
	end
	log:debug("Creating widget action listener for action: (" , action, ") from source: ", callerInfo)
	
	return self:addListener(ACTION,
			function(event)
				local eventAction = event:getAction()
				if eventAction ~= action then
					return EVENT_UNUSED
				end
				log:debug("Calling widget action listener for action: (" , action, ") from source: ", callerInfo)
				
				local listenerResult = listener(obj, event)
				--default to consume unless the listener specifically wants to set a specific event return
				local eventResult = listenerResult and listenerResult or EVENT_CONSUME
				if eventResult == EVENT_CONSUME then
					log:debug("Action (" , action, ") consumed by widget source: ", callerInfo)
				end
				return eventResult

			end
	)
    
end

--[[

=head2 jive.ui.Widget:removeListener(handle)

Removes the listener I<handle> from the widget.

=cut
--]]
function removeListener(self, handle)
	_assert(type(handle) == "table", "Invalid listener handle")

	table.delete(self.listeners, handle)
end


--[[

=head2 jive.ui.Widget:addAnimation(animation, frameRate)

Add an animation function I<animation> to the widget. This function will be called before the frame is drawn at the requested I<frameRate>. Returns a I<handle> to use in removeAnimation().

=cut
--]]
function addAnimation(self, animation, frameRate)
	_assert(type(animation) == "function", "Invalid animation function")
	_assert(type(frameRate) == "number", "Invalid frame rate")

	frameRate = FRAME_RATE / frameRate

	local handle = { animation, frameRate, frameRate }
	self.animations[#self.animations + 1] = handle

	if self.visible then
		Framework:_addAnimationWidget(self)
	end

	return handle
end


--[[

=head2 jive.ui.Widget:removeAnimation(handle)

Remove the animation function I<handle> from the widget.

=cut
--]]
function removeAnimation(self, handle)
	_assert(type(handle) == "table", "Invalid animation handle")

	table.delete(self.animations, handle)

	if self.visible then
		Framework:_removeAnimationWidget(self)
	end
end


--[[

=head2 jive.ui.Widget:dispatchNewEvent(eventType, ...)

Send a new event of type I<type> with value I<value> to this widgets listeners. The additional args are event specific.

=cut
--]]
function dispatchNewEvent(self, eventType, ...)
	_assert(type(eventType) == "number", "Invalid event type")

	local event = Event:new(eventType, ...)
	return Framework:dispatchEvent(self, event)
end


--[[

=head2 jive.ui.Widget:dispatchUpdateEvent(value)

Send an EVENT_UPDATE with value I<value> to this widgets listeners.

=cut
--]]
function dispatchUpdateEvent(self, value)
	_assert(type(value) == "number", "Invalid value")

	local event = Event:new(EVENT_UPDATE, value)
	return Framework:dispatchEvent(self, event)
end


--[[

=head2 jive.ui.Widget:addTimer(interval, closure, once)

Add a timer to this timer that calls I<closure> in I<interval> milliseconds. The timer is only called while the widget is shown on the screen.

=cut
--]]
function addTimer(self, interval, callback, once)
	_assert(type(interval) == "number", "Invalid interval")
	_assert(type(callback) == "function", "Invalid callback")

	timer = Timer(interval, callback, once) 
	self.timers[#self.timers + 1] = timer

	if self.visible then
		timer:start()
	end

	return timer
end


--[[

=head2 jive.ui.Widget:removeTimer(timer)

Remove timer I<timer> from this Widget.

=cut
--]]
function removeTimer(self, timer)
	_assert(oo.instanceof(timer, Timer), "Invalid timer")

	timer:stop()
	table.delete(self.timers, timer)
end


--[[

=head2 jive.ui.Widget:setAccelKey(key)

Sets the key letter displayed in an accelerated menu.

=cut
--]]
function setAccelKey(self, key)
	self.accelKey = key
end


--[[

=head2 jive.ui.Widget:getAccelKey()

Returns the key letter displayed in an accelerated menu.

=cut
--]]
function getAccelKey(self)
	return self.accelKey
end


--[[

=head2 jive.ui.Widget:playSound(sound)

Play the sound when the widget is visible.

=cut
--]]
function playSound(self, sound)
	if self.visible then
		Framework:playSound(sound)
	end
end


function _event(self, event)
	local type = event:getType()
	if type == EVENT_SHOW and not self.visible then
		self.visible = true
		if #self.animations > 0 then
			Framework:_addAnimationWidget(self)
		end
		for i,timer in ipairs(self.timers) do
			timer:start()
		end
	elseif type == EVENT_HIDE and self.visible then
		self.visible = false
		if #self.animations > 0 then
			Framework:_removeAnimationWidget(self)
		end
		for i,timer in ipairs(self.timers) do
			timer:stop()
		end
	end

	local r = 0
	for i,v in ipairs(self.listeners) do
		local mask,callback = v[1], v[2]
		if bit.band(type, mask) ~= 0 then
			r = bit.bor(r, (callback(event) or 0))

			if bit.band(r, EVENT_CONSUME) ~= 0 then
				break
			end
		end
	end

	return r
end


function dump(self, level)
	local str = {}
	local pad = string.rep(" ", (level or 0) * 2)

	level = (level or 0) + 1

	table.insert(str, pad .. tostring(self) .. " [" .. self:peerToString() .. " " .. tostring(self.visible) .. "]")

	self:iterate(function(child)
			     table.insert(str, child:dump(level))
		     end)

	return table.concat(str, "\n")
end


function shortWidgetToString(self)
	local widgetToString = tostring(self)
	local parenLoc = string.find(widgetToString, "%(")
	if not parenLoc then
		return widgetToString
	end

	return string.sub(widgetToString, 0, parenLoc - 1)
end


function setSmoothScrollingMenu(self, val)
	self.smoothscroll = val
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

