--------------------------------------------------------------------------------
---------------------- ##       #####    #####   ######  -----------------------
---------------------- ##      ##   ##  ##   ##  ##   ## -----------------------
---------------------- ##      ##   ##  ##   ##  ######  -----------------------
---------------------- ##      ##   ##  ##   ##  ##      -----------------------
---------------------- ######   #####    #####   ##      -----------------------
----------------------                                   -----------------------
----------------------- Lua Object-Oriented Programming ------------------------
--------------------------------------------------------------------------------
-- Title  : LOOP - Lua Object-Oriented Programming                            --
-- Name   : General utilities functions for table manipulation                --
-- Author : Renato Maia <maia@inf.puc-rio.br>                                 --
-- Version: 2.2 alpha                                                         --
-- Date   : 13/04/2006 17:24                                                  --
--------------------------------------------------------------------------------
-- These functions are used in many package implementations and may also be   --
-- usefull in applications.                                                   --
--------------------------------------------------------------------------------

local next = next
local pairs = pairs
local setmetatable = setmetatable

local table = require "table"

module "loop.table"

setmetatable(_M, { __index = table })

--------------------------------------------------------------------------------
-- Copies all elements stored in a table into another.

-- Each pair of key and value stored in table 'source' will be set into table
-- 'destiny'.
-- If no 'destiny' table is defined, a new empty table is used.

-- @param source Table containing elements to be copied.
-- @param destiny [optional] Table which elements must be copied into.

-- @return Table containing copied elements.

-- @usage copied = loop.table.copy(results)
-- @usage loop.table.copy(results, newcopy)

function copy(source, destiny)
	if source then
		if not destiny then destiny = {} end
		for field, value in pairs(source) do
			destiny[field] = value
		end
	end
	return destiny
end

--------------------------------------------------------------------------------
-- Clears all contens of a table.

-- All pairs of key and value stored in table 'source' will be removed by
-- setting nil to each key used to store values in table 'source'.

-- @param tab Table which must be cleared.
-- @usage return loop.table.clear(results)

function clear(tab)
	local elem = next(tab)
	while elem do
		tab[elem] = nil
		elem = next(tab)
	end
	return tab
end
