--[[
=head1 NAME

jive.util.table - table utilities

=head1 DESCRIPTION

Assorted utility functions for tables. This extends 
the lua built-in table.* functions.

=head1 SYNOPSIS

 local table = require("jive.utils.table")

 -- Iterator over a table in the order of its keys
 for name, line in table.pairsByKeys(lines) do
 	print(name, line)
 end

 -- Sort table (from lua table module)
 table.sort(t1)

=head1 FUNCTIONS

=cut
--]]


local ipairs, pairs, setmetatable = ipairs, pairs, setmetatable

local ltable = require("table")

module(...)


-- this is the bit that does the extension.
setmetatable(_M, { __index = ltable })


--[[

=head2 table.pairsByKeys(t, f)

Returns an iterator that traverses a table C<t> following the order of its keys. An option
parameter C<f> allows the specifiction of an alternative order.

Taken from I<Programming in LUA> page 173.

=cut
--]]
function pairsByKeys (t, f)
	local a = {}
	for n in pairs(t) do a[#a + 1] = n end
	ltable.sort(a, f)
	local i = 0  -- iterator variable
	return function ()  -- iterator function
		i = i + 1
		return a[i], t[a[i]]
	end
end


--[[

=head2 table.delete(table, value)

Deletes an element from the table, shifting down any other elements.

Returns true if an element was deleted.

=cut
--]]
function delete(table, value)
	for i, v in ipairs(table) do
		if v == value then
			ltable.remove(table, i)
			return true
		end
	end

	return false
end


--[[

=head2 table.contains(table, value)

Returns true if the table contains the value, otherwise returns false

=cut
--]]
function contains(table, value)
	for i, v in ipairs(table) do
		if v == value then
			return true
		end
	end

	return false
end

--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

