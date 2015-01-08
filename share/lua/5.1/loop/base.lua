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
-- Name   : Base Class Model                                                  --
-- Author : Renato Maia <maia@inf.puc-rio.br>                                 --
-- Version: 2.2 alpha                                                         --
-- Date   : 13/04/2006 17:24                                                  --
--------------------------------------------------------------------------------
-- Exported API:                                                              --
--   class(class)                                                             --
--   new(class, ...)                                                          --
--   classof(object)                                                          --
--   isclass(class)                                                           --
--   instanceof(object, class)                                                --
--   members(class)                                                           --
--------------------------------------------------------------------------------

local type         = type
local pairs        = pairs
local unpack       = unpack
local setmetatable = setmetatable
local getmetatable = getmetatable

module "loop.base"

--------------------------------------------------------------------------------
function rawnew(class, object)
	return setmetatable(object or {}, class)
end
--------------------------------------------------------------------------------
function new(class, ...)
	if type(class.__init) == "function"
		then return class:__init(...)
		else return rawnew(class, ...)
	end
end
--------------------------------------------------------------------------------
function initclass(class)
	if class == nil then class = {} end
	if class.__index == nil then class.__index = class end
	return class
end
--------------------------------------------------------------------------------
local MetaClass = { __call = new }
function class(class)
	return setmetatable(initclass(class), MetaClass)
end
--------------------------------------------------------------------------------
classof = getmetatable
--------------------------------------------------------------------------------
function isclass(class)
	return classof(class) == MetaClass
end
--------------------------------------------------------------------------------
function instanceof(object, class)
	return classof(object) == class
end
--------------------------------------------------------------------------------
members = pairs
