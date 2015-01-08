-----------------------------------------------------------------------------
-- RadioButton.lua
-----------------------------------------------------------------------------

--[[
=head1 NAME

jive.ui.RadioButton - A radio button widget.

=head1 DESCRIPTION

A radio button widget, extends L<jive.ui.Widget>. The radio button must be a member of a L<jive.ui.RadioGroup>. Only one radio button in the radio group may be selected at any time.

=head1 SYNOPSIS

 -- Create a new radio group
 local group = jive.ui.RadioGroup()
 
 -- Create buttons in the group
 local button1 = jive.ui.RadioButton(
	"radio1", 
	group, 
	function(object)
		print("radio1 selected")
	end,
	false)
 
 local button2 = jive.ui.RadioButton(
	"radio2", 
	group, 
	function(object)
		print("radio2 selected")
	end,
	true)

 -- Set button as selected
 button1:setSelected()

=head1 STYLE

The Radio Button includes the following style parameters in addition to the widgets basic parameters.

=over

B<img_on> : the image when the Radio Button is selected.

B<img_off> : the image when the Radio Button is not selected.

=head1 METHODS

=cut
--]]


-- stuff we use
local _assert, require, tostring, type = _assert, require, tostring, type

local debug            = require("debug")

local oo               = require("loop.simple")
local Icon             = require("jive.ui.Icon")

local log             = require("jive.utils.log").logger("jivelite.ui")

local EVENT_ACTION     = jive.ui.EVENT_ACTION
local EVENT_KEY_PRESS  = jive.ui.EVENT_KEY_PRESS

local EVENT_CONSUME    = jive.ui.EVENT_CONSUME
local EVENT_UNUSED     = jive.ui.EVENT_UNUSED

local KEY_PLAY         = jive.ui.KEY_PLAY


-- our class
module(...)
oo.class(_M, Icon)

-- loaded late to prevent require loop
local RadioGroup       = require("jive.ui.RadioGroup")

--[[

=head2 jive.ui.RadioButton(style, group, selected)

Constructs a new RadioButton widget. I<style> is the widgets style. The RadioButton belongs to the L<jive.ui.RadioGroup> I<group>. I<selected> is an optional boolean to set if this RadioButton is selected, it defaults to false.  I<closure> is a function that will get called whenever this RadioButton
is selected by the user; the function prototype is:
 function(radioButtonObject)

=cut
--]]
function __init(self, style, group, closure, selected)
	log:debug("RadioButton:_init()");

	_assert(type(style) == "string")
	_assert(oo.instanceof(group, RadioGroup), "group is not RadioGroup - " .. debug.traceback())
	_assert(type(closure) == "function")
	_assert(selected == nil or type(selected) == "boolean")

	local obj = oo.rawnew(self, Icon(style))

	obj.imgStyleName = "img_off"
	obj.group = group

	if selected then
		group:setSelected(obj)
	end

	-- set this here so that closure is nil when we first set the button
	obj.closure = closure

	obj:addListener(EVENT_ACTION,
			 function(event)
				 return obj:_action()
			 end)

	obj:addActionListener("play", obj, _action)
	
	return obj
end


function _action(self)
	log:debug("RadioButton:_action()");

	local oldSelected = self.group.selected
	self.group:setSelected(self)
	if oldSelected ~= self.group.selected then
		self:playSound("SELECT")
	end
	return EVENT_CONSUME
end


--[[

=head2 jive.ui.RadioButton:isSelected()

Returns true if this radio button is selected, otherwise return false.

=cut
--]]
function isSelected(self)
	return self.group:getSelected() == self
end


--[[

=head2 jive.ui.RadioButton:setSelected()

Sets this radio button. The closure is called.

=cut
--]]
function setSelected(self)
	self.group:setSelected(self)
end


-- _set
-- used by RadioGroup to set us on or off
function _set(self, selected)
	log:debug("RadioButton:_set(", tostring(selected));

	if selected then
		self.imgStyleName = "img_on"
		if self.closure then 
			self.closure(self)
		end
	else
		self.imgStyleName = "img_off"
	end

	self:reSkin()
end


function __tostring(self)
	return "RadioButton()"
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

