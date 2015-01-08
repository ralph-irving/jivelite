-----------------------------------------------------------------------------
-- strings.lua
-----------------------------------------------------------------------------

--[[
=head1 NAME

jive.util.string - string utilities

=head1 DESCRIPTION

Assorted utility functions for strings

Builds on Lua's built-in string.* class 

=head1 SYNOPSIS

 -- trim a string at the first 0x00
 local trimmed = jive.util.strings.trim(some_string)

=head1 FUNCTIONS

=cut
--]]


local tonumber, setmetatable = tonumber, setmetatable
local table  = require('jive.utils.table')
local ltable = require("string")

module(...)

-- this is the bit that does the extension.
setmetatable(_M, { __index = ltable })

--[[

=head2 str2hex(s)

Returns a string where each char of s is replaced by its ASCII hex value.

=cut
--]]
function str2hex(s)
	local s_hex = ""
	ltable.gsub(
			s,
			"(.)",
			function (c)
				s_hex = s_hex .. ltable.format("%02X ",ltable.byte(c)) 
			end)
	return s_hex
end


--[[

=head2 trim(s)

Returns s trimmed down at the first 0x00 found.

=cut
--]]
function trim(s)
	local b, e = ltable.find(s, "%z")
	if b then
		return s:sub(1, b-1)
	else
		return s
	end
end

--[[

=head2 split(inSplitPattern, myString, returnTable)

Takes a string pattern and string as arguments, and an optional third argument of a returnTable

Splits myString on inSplitPattern and returns elements in returnTable (appending to returnTable if returnTable is given)

=cut
--]]

function split(inSplitPattern, myString, returnTable)
	if not returnTable then
		returnTable = {}
	end
	local theStart = 1

	if inSplitPattern == '' then
		local length = ltable.len(myString)
		for i=1,length do
			table.insert(returnTable, ltable.sub(myString, i, i) )
		end
	else
		local theSplitStart, theSplitEnd = ltable.find(myString, inSplitPattern, theStart)
		while theSplitStart do
			table.insert(returnTable, ltable.sub(myString, theStart, theSplitStart-1))
			theStart = theSplitEnd + 1
			theSplitStart, theSplitEnd = ltable.find(myString, inSplitPattern, theStart)
		end
		table.insert(returnTable, ltable.sub(myString, theStart))
	end
	return returnTable
end

--[[

=head2 matchLiteral(s, pattern [, init])

Identical to Lua's string.match() method, but escapes all special characters in the substring first

Looks for the first match of pattern in the string s. 

If it finds one, then matchLiteral returns the captures from the pattern; otherwise it returns nil. 

If pattern specifies no captures, then the whole match is returned. 

A third, optional numerical argument init specifies where to start the search; its default value is 1 and can be negative. 

=cut
--]]

function matchLiteral(s, pattern, init)
	-- first escape all special characters in pattern
	local escapedPattern = ltable.gsub(pattern, "[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1")
	return ltable.match(s, escapedPattern, init)
 
end

--[[

=head2 urlDecode(s)

Decodes a URL-encoded string

=cut
==]]

function urlDecode (str)
	str = ltable.gsub(str, "+", " ")
	str = ltable.gsub(str, "%%(%x%x)", 
		function(h) 
			return ltable.char(tonumber(h,16)) 
		end
	)
	str = ltable.gsub (str, "\r\n", "\n")
	return str
end


--[[

=head2 urlEncode(s)

Takes a string as an arg and returns an encoded URL-encoded string

=cut
==]]

function urlEncode (str)
	str = ltable.gsub(str, "\n", "\r\n")
	str = ltable.gsub(str, "([^0-9a-zA-Z ])",
		function(c) 
			return ltable.format("%%%02X", ltable.byte(c)) 
		end
	)
	str = ltable.gsub(str, " ", "+")
	return str
end

--[[


=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

