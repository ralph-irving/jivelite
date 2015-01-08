
--[[
=head1 NAME

jive.ui.Canvas - A canvas widget

=head1 DESCRIPTION

A canvas widget, this widget provides access to drawing on the screen
in lua.

--]]

-- stuff we use
local _assert, tostring, type, tolua = _assert, tostring, type, tolua

local oo        = require("loop.simple")
local Icon      = require("jive.ui.Icon")
local Surface   = require("jive.ui.Surface")

local log       = require("jive.utils.log").logger("jivelite.ui")


-- our class
module(...)
oo.class(_M, Icon)


function __init(self, style, renderFunc)
	_assert(type(renderFunc) == "function")

	local obj = oo.rawnew(self, Icon(style))
	obj.render = renderFunc

	return obj
end


function draw(self, surface)
	self.render(surface)
end
