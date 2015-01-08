
--[[
=head1 NAME

jive.utils.debug - Debug utilities.

=head1 DESCRIPTION

Provides a utility to trace lua functions and another to dump
tables. This modules extends the lua debug module.

=head1 SYNOPSIS

 -- require us
 local debug = require("jive.utils.debug")

 -- Turn on line tracing
 debug.trace()

 -- Dump a table
 local aTable = {a = 'bla', c = {}}
 debug.dump(aTable)
 
 -- print:
 { --table: 0x11aedd0
   a = "bla",
   c = { --table: 0x11aee30 },
 }

 -- Trackback (from lua debug module)
 debug.traceback()

=head1 FUNCTIONS

=cut
--]]

local print, setmetatable, tostring  = print, setmetatable, tostring
local ldebug  = require("debug")
local Viewer = require("loop.debug.Viewer")

module(...)

setmetatable(_M, { __index = ldebug })

-- _info_str
-- returns the data for a Lua function
local function _info_str (info, line)
	local str
	local name=info.name or "?"
	str = info.short_src .. ":" .. line .. " TRACE (in " .. name .. ")"
	return str
end


-- _trace_line
-- function set as hook to print each call
local function _trace_line (event, line)
	print(_info_str(ldebug.getinfo(2), line))
end


--[[

=head2 traceon()

Traces Lua calls, line by line. Use traceoff() to turn off tracing. This is very verbose,
but can help trace performance or strange behavioral issues. It also gives a glimpse on
the inner working of the Lua engine.

=cut
--]]
function traceon ()
	ldebug.sethook(_trace_line, "l")
end


--[[

=head2 traceff()

Turns off tracing Lua calls, line by line.

=cut
--]]
function traceoff ()
	ldebug.sethook(nil, "l")
end


--[[

=head2 dump(table, depth)

Dumps a table. Default depth is 2.
Quick and dirty way of using loop.debug.Viewer, which offers
many more options.

=cut
--]]
function dump(table, depth)
	local viewer = Viewer({
		maxdepth = depth,
	})
	viewer:print(table)
end

--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

