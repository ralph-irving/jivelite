-----------------------------------------------------------------------------
-- Icon.lua
-----------------------------------------------------------------------------

--[[
=head1 NAME

jive.ui.Icon - An icon widget

=head1 DESCRIPTION

An icon widget, extends L<jive.ui.Widget>. This widget displays an image.

=head1 SYNOPSIS

 -- New 'play' icon
 local right = jive.ui.Icon("icon_playmode_play")

 -- Load icon from URL
 local icon = jive.ui.Icon("icon")
 local http = SocketHttp(jnt, host, port, "example")
 local req = RequestHttp(icon:getSink())
 http:fetch(req)

=head1 STYLE

The Label includes the following style parameters in addition to the widgets basic parameters.

=over

B<img> : the icon image. This can be replaced by the image set in lua.

B<frameWidth> : if this is an animated icon this is the width of each frame.

B<frameRate> : if this is an animated icon this is the desired frame rate.

=head1 METHODS

=cut
--]]


-- stuff we use
local _assert, tostring, type, tolua = _assert, tostring, type, tolua

local oo        = require("loop.simple")
local Widget    = require("jive.ui.Widget")
local Surface   = require("jive.ui.Surface")

local log       = require("jive.utils.log").logger("jivelite.ui")


-- our class
module(...)
oo.class(_M, Widget)


--[[

=head2 jive.ui.Icon(style, image)

Constructs a Icon widget. I<style> is the Icon style. I<image> is an option L<jive.ui.Surface> to display, if not given the icon image is supplied by the active style.

=cut
--]]
function __init(self, style, image)
	_assert(type(style) == "string")
	--_assert(image == nil or tolua.type(image) == "Surface")

	local obj = oo.rawnew(self, Widget(style))
	obj.image = image
	
	return obj
end


--[[

=head2 jive.ui.Icon:getImage()

Returns the L<jive.ui.Surface> displayed by this icon, or nil if the style image is being used.

=cut
--]]
function getImage(self)
	return self.image
end


--[[

=head2 jive.ui.Icon:setValue(image)

Sets the L<jive.ui.Surface> displayed by the icon.

=cut
--]]
-- C implementation

--[[

=head2 jive.ui.Icon:sink()

Returns a LTN12 sink that can be used with the jive.net classes for loading images from the network.

=cut
--]]
function sink(self)
	local f = function(chunk, err)		
			  if err then
				  -- FIXME?
			  elseif chunk then
				  -- unless requested otherwise, the net. sources send a complete chunk,
				  -- then nil
				  self:setValue(Surface:loadImageData(chunk, #chunk))
			  end
			  return true
		  end

	return f
end


function __tostring(self)
	return "Icon(" .. tostring(self.image or self.style) .. ")"
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

