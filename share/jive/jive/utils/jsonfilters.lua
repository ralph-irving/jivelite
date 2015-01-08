-----------------------------------------------------------------------------
-- jsonfilters.lua
-----------------------------------------------------------------------------

--[[
=head1 NAME

jive.util.jsonfilters - json filters

=head1 DESCRIPTION

A set of ltn12 filters that encode/decode JSON.

=head1 SYNOPSIS

 -- transform a source returning Lua arrays (luasource) in json
 local jsonsource = ltn12.source.chain(
     luasource,
     jive.utils.jsonfilters.encode)

 -- transform a sink accepting Lua arrays (luasink) into one that accepts json
 local jsonsink = ltn12.sink.chain(
     jive.utils.jsonfilters.decode,
     luasink)

=head1 FUNCTIONS

=cut
--]]

local json = require("cjson")

module(...)


--[[

=head2 decode(chunk)

Decodes a JSON chunk (string) into a Lua array

=cut
--]]
function decode(chunk)
--	log:debug("jsondecodefilter()")
	if chunk == nil then
		return nil
	elseif chunk == "" then
		return ""
	elseif chunk then
		return json.decode(chunk)
	end
end


--[[

=head2 encode(chunk)

Encodes a Lua array into JSON chunk (string)

=cut
--]]
function encode(chunk)
--	log:debug("jsonencodefilter()")
	if chunk == nil then
		return nil
	elseif chunk == "" then
		return ""
	elseif chunk then
		return json.encode(chunk)
	end
end
--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

