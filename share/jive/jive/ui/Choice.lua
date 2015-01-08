-----------------------------------------------------------------------------
-- Choice.lua
-----------------------------------------------------------------------------

--[[
=head1 NAME

jive.ui.Choice - A widget to select an item from a list.

=head1 DESCRIPTION

A choice widget, extends L<jive.ui.Widget>. This widget lets the user select a value from a set of options.

=head1 SYNOPSIS

 -- New choice with options On and Off, Off is selected
 local choice = jive.ui.Choice(
	"choice", 
	{ "On", "Off" },
    function(object, selectedIndex)
	    print("Choice is " .. tostring(selectedIndex))
    end,
	2
 )

 -- Change checkbox state
 choice:setSelectedIndex(1)

=head1 STYLE

The Choice includes the following style parameters in addition to the widgets basic parameters.

=over

B<bg> : the background color, defaults to no background color.

B<fg> : the foreground color, defaults to black.

B<bg_img> : the background image.

B<font> : the text font, a L<jive.ui.Font> object.

B<line_height> : the line height to use, defaults to the font ascend height.
=back

B<text_align> : the text alignment.

B<icon_align> : the icon alignment.

=head1 METHODS

=cut
--]]


-- stuff we use
local _assert, tostring, type = _assert, tostring, type

--local debug = require("debug")

local oo               = require("loop.simple")
local Label            = require("jive.ui.Label")

local EVENT_ACTION     = jive.ui.EVENT_ACTION
local EVENT_KEY_PRESS  = jive.ui.EVENT_KEY_PRESS
local EVENT_CONSUME    = jive.ui.EVENT_CONSUME
local KEY_GO           = jive.ui.KEY_GO
local KEY_FWD          = jive.ui.KEY_FWD
local KEY_REW          = jive.ui.KEY_REW
local KEY_LEFT        = jive.ui.KEY_LEFT
local KEY_RIGHT       = jive.ui.KEY_RIGHT

local log              = require("jive.utils.log").logger("jivelite.ui")

-- our class
module(...)
oo.class(_M, Label)


-- _keyPress
-- handles events on the Choice widget
local function _keyPress(self, event)
--	log:debug("Choice:_keyPress() - ", debug.traceback())

	local eventType = event:getType()

	if eventType == EVENT_ACTION then

		return _changeAndselectChoiceAction(self, event)

	end

	return EVENT_UNUSED
end


--[[

=head2 jive.ui.Choice(style, options, closure, selectedIndex)

Constructs a Choice widget. I<style> is the widgets style. I<options> is a table containing the list of options. I<selectedIndex> is the index of the selected option, this defaults to 1 (i.e. the first option in the list). I<closure> is a function that will get called whenever the selected value is changed by the
user; the function prototype is:
 function(choiceObject, selectedIndex)

=cut
--]]
function __init(self, style, options, closure, selectedIndex)
	_assert(type(style) == "string")
	_assert(type(options) == "table")
	_assert(type(closure) == "function")

	selectedIndex = selectedIndex or 1
	_assert(type(selectedIndex) == "number")

	local obj = oo.rawnew(self, Label(style, options[selectedIndex]))

	obj.selectedIndex = selectedIndex
	obj.options = options
	obj.closure = closure

	obj:addActionListener("go", obj, _changeAndselectChoiceAction)
	obj:addListener(EVENT_ACTION,
			 function(event)
				 return _keyPress(obj, event)
			 end)

	return obj
end

function _changeAndselectChoiceAction(self, event)
	local newSelectedIndex = self.selectedIndex + 1

	self:setSelectedIndex(newSelectedIndex)
	self:playSound("SELECT")

	return EVENT_CONSUME
end

--[[

=head2 jive.ui.Choice:getSelectedIndex()

Returns the selected option index.

=cut
--]]
function getSelectedIndex(self)
	return self.selectedIndex
end


--[[

=head2 jive.ui.Choice:getSelected()

Returns the selected option.

=cut
--]]
function getSelected(self)
	return self.options[self.selectedIndex]
end


--[[

=head2 jive.ui.Choice:setSelectedIndex(selectedIndex)

Sets the selected option index. I<selectedIndex> is the index of the option to select; 
it is coerced to the next option if out of bounds (i.e. setSelectedIndex(#options + 1) 
selects the first option).

Note that using this function calls the closure.

=cut
--]]
function setSelectedIndex(self, selectedIndex)
	_assert(type(selectedIndex) == "number")

	if self.selectedIndex == selectedIndex then
		return
	end

	if selectedIndex > #self.options then
		selectedIndex = 1
	elseif selectedIndex < 1 then
		selectedIndex = #self.options
	end
	self.selectedIndex = selectedIndex

	self:setValue(self.options[self.selectedIndex])
	self.closure(self, self.selectedIndex)
end


function __tostring(self)
	return "Choice()"
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

