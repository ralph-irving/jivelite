
--[[
=head1 NAME

jive.ui.Label - A label widget.

=head1 DESCRIPTION

A label widget, extends L<jive.ui.Widget>. A label displays multi-line text.

Any lua value can be set as Label value, tostring() is used to convert the value to a string before it is displayed.

=head1 SYNOPSIS

 -- Create a new label to display 'Hello World'
 local label = jive.ui.Label("text", "Hello World")

 -- Update the label to multi-line text
 label.setValue("Multi-line\ntext")

=head1 STYLE

The Label includes the following style parameters in addition to the widgets basic parameters.

=over

B<bg> : the background color, defaults to no background color.

B<fg> : the foreground color, defaults to black.

B<bgImg> : the background image.

B<font> : the text font, a L<jive.ui.Font> object.

B<lineHeight> : the line height to use, defaults to the font ascend height.
=back

B<align> : the text alignment.

B<line> : optionally an array of I<font>, I<lineHeight>, I<fg> and I<sh> attribtues foreach line in the Label.

=head1 METHODS

=cut
--]]


-- stuff we use
local _assert, string, tostring, type = _assert, string, tostring, type

local oo           = require("loop.simple")
local Widget       = require("jive.ui.Widget")
local Icon         = require("jive.ui.Icon")
local Timer        = require("jive.ui.Timer")

local log          = require("jive.utils.log").logger("jivelite.ui")

local EVENT_ALL    = jive.ui.EVENT_ALL
local EVENT_UNUSED = jive.ui.EVENT_UNUSED

local EVENT_SHOW      = jive.ui.EVENT_SHOW
local EVENT_HIDE      = jive.ui.EVENT_HIDE
local EVENT_FOCUS_GAINED = jive.ui.EVENT_FOCUS_GAINED
local EVENT_FOCUS_LOST   = jive.ui.EVENT_FOCUS_LOST


-- our class
module(...)
oo.class(_M, Widget)


--[[

=head2 jive.ui.Label(style, value)

Constructs a new Label widget. I<style> is the widgets style. I<value> is the text displayed in the widget.

=cut
--]]
function __init(self, style, value)
	_assert(type(style) == "string")
	
	local obj = oo.rawnew(self, Widget(style))

	obj.value = value

	obj:addListener(EVENT_FOCUS_GAINED, function() obj:animate(true) end)
	obj:addListener(EVENT_FOCUS_LOST, function() obj:animate(false) end)

	-- work around scrolling labels not returning to home
	-- NowPlaying also needs fix, as this overwrites 'textStopCallback'
	obj.textStopCallback = function(label) label:reDraw() end

	return obj
end


--[[

=head2 jive.ui.Label:getValue()

Returns the text displayed in the label.

=cut
--]]
function getValue(self)
	return self.value
end


--[[

=head2 jive.ui.Label:setValue(value)

Sets the text displayed in the label.

If I<priorityDuration>, value will be set for priorityDuration ms, after which the value will revert to the previous text.
Only another setValue with a priorityDuration will replace the current text during the priorityDuration time.

=cut
--]]
function setValue(self, value, priorityDuration)

	if priorityDuration then
		if not self.priorityTimer then
			self.priorityTimer = Timer(
						0,
							function ()
								if not self.previousPersistentValue then
									self.previousPersistentValue = ""
								end
								self:_setValue(self.previousPersistentValue)
							end,
						true)
		end
		self:_setValue(value)
		self.priorityTimer:restart(priorityDuration)

	else
		if not (self.priorityTimer and self.priorityTimer:isRunning()) then
			self:_setValue(value)
		end
		self.previousPersistentValue = value
	end
end


function _setValue(self, value)
	if self.value ~= value then
		self.value = value
		self:reLayout()
	end
end


function __tostring(self)
	return "Label(" .. string.gsub(tostring(self.value), "[%c]", " ") .. ")"
end


--[[ C optimized:

jive.ui.Icon:pack()
jive.ui.Icon:draw()

--]]

--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

