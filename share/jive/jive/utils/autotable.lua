-----------------------------------------------------------------------------
-- autotable.lua
-----------------------------------------------------------------------------

--[[
=head1 NAME

jive.util.autotable - magic Lua tables

=head1 DESCRIPTION

Creates a table that automatically creates any subtable.

=head1 SYNOPSIS

 -- Create an autotable
 local harry = jive.util.autotable:new()

 -- Automatically add subtables "potter" and "magic"
 harry.potter.magic.wand = 33

=head1 FUNCTIONS

=cut
--]]

-- import some global stuff
local setmetatable, rawset, type = setmetatable, rawset, type


module(...)

--[[

=head2 new()

Creates and returns the autotable.

=cut
--]]
function new()

	-- define the new table
	local newtable = {}
	
	-- define a table to act as a metatable to the first one
	local metatable = {}
	
	-- set the second table to be the metatable of the first
	setmetatable(newtable, metatable)
	
	-- define the metatable __index metamethod
	-- this is called whenever we read access to data.xxx, if xxx is not defined
	metatable["__index"] = function(tab, key)

		-- what we want here is do define xxx as being a table...
		local newtable = {}
		
		-- and well, we want to be called for xxx.yyy so we set ourself as the metatable as well!
		setmetatable(newtable, metatable)
		
		-- create the key in data
		tab[key] = newtable
		
		-- return the table
		return newtable
	end

	-- define the metatable __newindex metamethod
	-- this is called whenever we do data.xxx = qqq, if xxx is not defined
	metatable["__newindex"] =  function(tab, key, value)

		-- if value is a table, set our metatable to it
		if type(value) == 'table' then
			setmetatable(value, metatable)
		end
		
		-- now perform the original intention of the call
		rawset(tab, key, value)

		return value
	end
	
	return newtable
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

