-----------------------------------------------------------------------------
-- log.lua
-----------------------------------------------------------------------------

--[[
=head1 NAME

jive.util.log - logging facility

=head1 DESCRIPTION

A basic logging facility by category and level.

=head1 SYNOPSIS

This module is kept for backwards compatibity, the logging implementation is
now implemented in C.

 -- get the logger for a category that should exist
 local log = jive.utils.log.logger("net.http")

 -- typically at the top of a module, you'd do
 local log = require("jive.utils.log").logger("net.http") 

 -- log something
 log:debug("hello world")
 log:info("hello world")
 log:warn("hello world")
 log:error("hello world")

 -- prints
 161845:39202 DEBUG (somefile.lua:45) - Hello world

The logging functions concatenate data more efficiently than operator .. does,
so for best performance, do 

 log:debug("Welcome ", first_name, ", thanks for visiting us ", time_of_day)

rather than

 log:debug("Welcome " .. first_name .. ", thanks for visiting us " .. time_of_day)

All parameters are cast to strings using tostring() where required. Logs with priority 'error' automatically include a backtrace.

=cut
--]]

local splog     = require("jivelite.log")

local log       = splog:logger("jivelite")

module(...)

DEBUG = "debug"
INFO  = "info"
WARN  = "warn"
ERROR = "error"

function logger(category)
	local obj = splog:logger(category)

	return obj
end


function getCategories()
	return splog:getCategories()
end


-- deprecated
function addCategory(category, initialLevel)
	local obj = splog:logger(category)

	log:error("addCategory is deprecated")

	obj:setLevel(initialLevel)
	return obj
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

