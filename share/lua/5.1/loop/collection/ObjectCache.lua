--------------------------------------------------------------------------------
---------------------- ##       #####    #####   ######  -----------------------
---------------------- ##      ##   ##  ##   ##  ##   ## -----------------------
---------------------- ##      ##   ##  ##   ##  ######  -----------------------
---------------------- ##      ##   ##  ##   ##  ##      -----------------------
---------------------- ######   #####    #####   ##      -----------------------
----------------------                                   -----------------------
----------------------- Lua Object-Oriented Programming ------------------------
--------------------------------------------------------------------------------
-- Project: LOOP Class Library                                                --
-- Release: 2.2 alpha                                                         --
-- Title  : Cache of Objects Created on Demand                                --
-- Author : Renato Maia <maia@inf.puc-rio.br>                                 --
-- Date   : 13/12/2004 13:51                                                  --
--------------------------------------------------------------------------------
-- Notes:                                                                     --
--   Storage of keys 'retrieve' and 'default' are not allowed.                --
--------------------------------------------------------------------------------

local rawget = rawget
local rawset = rawset

local oo   = require "loop.base"

module("loop.collection.ObjectCache", oo.class)

__mode = "k"

function __index(self, key)
	if key ~= nil then
		local value = rawget(self, "retrieve")
		if value then
			value = value(self, key)
		else
			value = rawget(self, "default")
		end
		rawset(self, key, value)
		return value
	end
end