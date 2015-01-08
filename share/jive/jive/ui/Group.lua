
--[[
=head1 NAME

jive.ui.Group - A group widget.

=head1 DESCRIPTION

A group widget, extends L<jive.ui.Widget>, it is a container for other widgets. The widgets are arranged horizontally.

=head1 SYNOPSIS

 -- Create a new group
 local group = jive.ui.Group("group", { text = Label("text", "Hello World"), icon = Icon("icon") })

=head1 STYLE

The Group includes the following style parameters in addition to the widgets basic parameters.

=over

B<order> : a table specifing the order of the widgets, by key. For example { "text", "icon" }

=head1 METHODS

=cut
--]]


local _assert, pairs, string, tostring, type, bit = _assert, pairs, string, tostring, type, bit

local oo                = require("loop.simple")
local Widget            = require("jive.ui.Widget")

local table             = require("jive.utils.table")
local debug             = require("jive.utils.debug")
local log               = require("jive.utils.log").logger("jivelite.ui")

local EVENT_ALL         = jive.ui.EVENT_ALL
local EVENT_MOUSE_ALL   = jive.ui.EVENT_MOUSE_ALL
local EVENT_MOUSE_DOWN  = jive.ui.EVENT_MOUSE_DOWN
local EVENT_MOUSE_UP    = jive.ui.EVENT_MOUSE_UP
local EVENT_MOUSE_MOVE    = jive.ui.EVENT_MOUSE_MOVE
local EVENT_UNUSED      = jive.ui.EVENT_UNUSED

local EVENT_SHOW      = jive.ui.EVENT_SHOW
local EVENT_HIDE      = jive.ui.EVENT_HIDE


module(...)
oo.class(_M, Widget)


--[[

=head2 jive.ui.Group(style, widgets)

Constructs a new Group widget. I<style> is the widgets style. I<widgets> is a table with the widgets in this group.

=cut
--]]
function __init(self, style, widgets)
	_assert(type(style) == "string")
	_assert(widgets)

	local obj = oo.rawnew(self, Widget(style))
	obj.widgets = widgets

	for _,widget in pairs(obj.widgets) do
		widget.parent = obj
	end

	-- forward events to contained widgets
	obj:addListener(EVENT_ALL,
			 function(event)
				local notMouse = bit.band(event:getType(), EVENT_MOUSE_ALL) == 0
				local r = EVENT_UNUSED
				if event:getType() == EVENT_MOUSE_MOVE then
					local mouseX, mouseY = event:getMouse()
				end

				for _,widget in pairs(obj.widgets) do
					 if notMouse
					   or self._mouseEventFocusWidget == widget 
					   or (not self._mouseEventFocusWidget and widget:mouseInside(event)) then
						 r = widget:_event(event)
						 if r ~= EVENT_UNUSED then
						        --Consumer of MOUSE_DOWN that is in mouse bounds will be given mouse event focus
							if event:getType() == EVENT_MOUSE_DOWN then
								self:setMouseEventFocusWidget(widget)
							end
							break
						 end
					 end
				end

				if r == EVENT_UNUSED and event:getType() == EVENT_MOUSE_DOWN then
					--no match for the down found, send to closest group member
					local mouseX, mouseY = event:getMouse()
					local closestDistance = 99999
					local closestWidget
					for _,widget in pairs(obj.widgets) do
						local widgetX, widgetY, widgetW, widgetH = widget:getBounds()

						if widgetW > 0 then --widget must have some width to be considered
							local widgetDistance
							if mouseX >= widgetW + widgetX then
								widgetDistance = mouseX - (widgetW + widgetX)
							else
								widgetDistance = widgetX - mouseX
							end

							if widgetDistance < closestDistance then
								closestDistance = widgetDistance
								closestWidget = widget
							end
						end
					end
					if closestWidget then
						r = closestWidget:_event(event)
						if r ~= EVENT_UNUSED then
							--closest Consumer of MOUSE_DOWN will be given mouse event focus
							if event:getType() == EVENT_MOUSE_DOWN then
								self:setMouseEventFocusWidget(closestWidget)
							end
						end
					end
				end

				if event:getType() == EVENT_MOUSE_UP then
					self:setMouseEventFocusWidget(nil)
				end

				return r
			 end)

	return obj
end


function setMouseEventFocusWidget(self, widget)
	self._mouseEventFocusWidget = widget
end


--[[

=head2 jive.ui.Widget:getWidget(key)

Returns a widget in this group.

=cut
--]]
function getWidget(self, key)
	return self.widgets[key]
end


--[[

=head2 jive.ui.Widget:setWidget(key, widget)

Sets or replaces a widget in this group.

=cut
--]]
function setWidget(self, key, widget)
	if self.widgets[key] == widget
		and self.widgets[key].parent == self then
		return
	end

	if self.widgets[key] then
		if self.widgets[key].parent ~= self then
			if self.visible then
				self.widgets[key]:dispatchNewEvent(EVENT_HIDE)
			end

			self.widgets[key].parent = nil
		end
	end

	self.widgets[key] = widget

	if self.widgets[key] then
		self.widgets[key].parent = self
		self.widgets[key]:reSkin()

		if self.visible then
			self.widgets[key]:dispatchNewEvent(EVENT_SHOW)
		end
	end
end


--[[

=head2 jive.ui.Widget:getWidgetValue(widget)

Returns the value of a widget in this Group.

=cut
--]]
function getWidgetValue(self, w)
	return self.widgets[w]:getValue()
end


--[[

=head2 jive.ui.Widget:setWidgetValue(widget, value, ...)

Set the value of a widget in this Group.

=cut
--]]
function setWidgetValue(self, w, value, ...)
	return self.widgets[w]:setValue(value, ...)
end


function __tostring(self)
	local str = {}

	str[1] = "Group("
	for k,v in pairs(self.widgets) do
		str[#str + 1] = tostring(v)
	end
	str[#str + 1] = ")"

	return table.concat(str)
end


function setSmoothScrollingMenu(self, val)
	for _,widget in pairs (self.widgets) do
		widget:setSmoothScrollingMenu(val)
	end
	self.smoothscroll = val
end

--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]
