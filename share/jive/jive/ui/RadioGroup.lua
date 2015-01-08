
--[[
=head1 NAME

jive.ui.RadioGroup - A container for L<jive.ui.RadioButton>s.

=head1 DESCRIPTION

A container for L<jive.ui.RadioButton>s. Only one radio button in the radio group may be selected at any time.

=head1 SYNOPSIS

See L<jive.ui.RadioButton>

=head1 METHODS

=cut
--]]


-- stuff we use
local _assert, require, tostring, type = _assert, require, tostring, type

local oo                = require("loop.simple")
local Widget            = require("jive.ui.Widget")

local EVENT_ACTION      = jive.ui.EVENT_ACTION
local EVENT_KEY_PRESS   = jive.ui.EVENT_KEY_PRESS
local EVENT_CONSUME     = jive.ui.EVENT_CONSUME


-- our class
module(...)
oo.class(_M, Widget)

-- loaded late to prevent require loop
local RadioButton       = require("jive.ui.RadioButton")


--[[

=head2 jive.ui.RadioGroup()

Constructs a new RadioGroup object.

=cut
--]]
function __init(self)
	
	-- the only thing this function does is give Widget a style of ""
	return oo.rawnew(self, Widget(""))
end


--[[

=head2 jive.ui.RadioGroup:getSelected()

Returns the L<jive.ui.RadioButton> currently selected.

=cut
--]]
function getSelected(self)
	return self.selected
end


--[[

=head2 jive.ui.RadioGroup:setSelected(selected)

Sets the L<jive.ui.RadioButton> selected in this RadioGroup.

=cut
--]]
function setSelected(self, selected)
	_assert(oo.instanceof(selected, RadioButton))

	if self.selected == selected then
		return
	end

	local last_selected = self.selected

	self.selected = selected
	
	if last_selected then
		last_selected:_set(false)
	end
	if selected then
		selected:_set(true)
	end
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

