
--[[
=head1 NAME

jive.ui.Checkbox - A checkbox widget

=head1 DESCRIPTION

A checkbox widget, extends L<jive.ui.Widget>.

=head1 SYNOPSIS

 -- New checkbox
 local checkbox = jive.ui.Checkbox(
	"checkbox", 
	function(object, isSelected)
		print("Checkbox is selected: " .. tostring(isSelected))
	end,
	true)

 -- Change checkbox state
 checkbox:setSelected(false)

=head1 STYLE

The Checkbox includes the following style parameters in addition to the widgets basic parameters.

=over

B<img_on> : the image when the checkbox is checked.

B<img_off> : the image when the checkbox is not checked.

=head1 METHODS

=cut
--]]


-- stuff we use
local _assert, tostring, type = _assert, tostring, type

local oo              = require("loop.simple")
local Icon            = require("jive.ui.Icon")

local log             = require("jive.utils.log").logger("jivelite.ui")

local EVENT_ACTION    = jive.ui.EVENT_ACTION
local EVENT_KEY_PRESS = jive.ui.EVENT_KEY_PRESS
local EVENT_CONSUME   = jive.ui.EVENT_CONSUME
local EVENT_UNUSED    = jive.ui.EVENT_UNUSED

local KEY_GO          = jive.ui.KEY_GO
local KEY_PLAY        = jive.ui.KEY_PLAY


-- our class
module(...)
oo.class(_M, Icon)


--[[

=head2 jive.ui.Checkbox(style, closure, isSelected)

Constructs a Checkbox widget. I<style> is the widgets style. I<isSelected> is true if the checkbox is selected, false otherwise (default). I<closure> is a function that will get called whenever the 
checkbox value changes; the function prototype is:
 function(checkboxObject, isSelected)

=cut
--]]
function __init(self, style, closure, isSelected)
	_assert(type(style) == "string")
	
	isSelected = isSelected or false
	_assert(type(isSelected) == "boolean")
	
	local obj = oo.rawnew(self, Icon(style))

	obj:setSelected(isSelected)
	obj.closure = closure

	obj:addListener(EVENT_ACTION,
			function()
				return obj:_action()
			end)

	obj:addActionListener("play", obj, _action)

	return obj
end


function _action(self)
	self:setSelected(not self.selected)
	self:playSound("SELECT")

	if self.closure then
		self.closure(self, self.selected)
	end

	return EVENT_CONSUME
end


--[[

=head2 jive.ui.Checkbox:isSelected()

Returns true if the checkbox is selected, or false otherwise.

=cut
--]]
function isSelected(self)
	return self.selected
end


--[[

=head2 jive.ui.Checkbox:setSelected(isSelected)

Sets the state of the checkbox. I<selected> true if the checkbox is selected, false otherwise.

Note that using this function calls the defined closure.

=cut
--]]
function setSelected(self, isSelected)
	_assert(type(isSelected) == "boolean")

	if self.selected == isSelected then
		return
	end

	self.selected = isSelected

	if isSelected then
		self.imgStyleName = "img_on"
	else
		self.imgStyleName = "img_off"
	end

	self:reSkin()
end


function __tostring(self)
	return "Checkbox()"
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

