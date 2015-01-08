
--[[
=head1 NAME

jive.net.RequestJsonRpc - A JSON request over HTTP.

=head1 DESCRIPTION

jive.net.RequestJsonRpc implements the JSON-RPC protocol
over POST HTTP. It is a subclass of L<jive.net.RequestHttp>.

Note the implementation uses the source and sink concept of luasocket.

=head1 SYNOPSIS

 -- create a sink to receive JSON
 local function mySink(chunk, err)
   if err then
     print("error!: " .. err)
   elseif chunk then
     print("received: " .. chunk.id)
   end
 end
 
 -- create a RequestJsonRpc
 local myRequest = RequestJsonRpc(mySink, '/jsonservice.js', 'secretmethod', {1, 2 , 3})

 -- use a SocketHttp to fetch
 http:fetch(myRequest)

=head1 FUNCTIONS

=cut
--]]
-----------------------------------------------------------------------------
-- Convention: functions/methods starting with t_ are executed in the thread
-----------------------------------------------------------------------------


-- stuff we use
local _assert, tostring, type = _assert, tostring, type

local string      = require("string")

local oo          = require("loop.simple")
local ltn12       = require("ltn12")
local socket      = require("socket")

local RequestHttp = require("jive.net.RequestHttp")
local jsonfilters = require("jive.utils.jsonfilters")

local log         = require("jive.utils.log").logger("net.http")


-- jive.net.RequestJsonRpc is a subclass of jive.net.RequestHttp
module(...)
oo.class(_M, RequestHttp)


-- _getBodySource (OVERRIDE)
-- returns the body
-- FIXME: we no longer have the problem with loop, change it to static during __init
function _getBodySource(json)
	local sent = false
	return ltn12.source.chain(
		function()
			if sent then
				return nil
			else
				sent = true
				return {
					["method"] = json.method,
					["params"] = json.params,
					["id"] = json.id,
				}
			end
		end, 
		jsonfilters.encode
	)
end


--[[

=head2 jive.net.RequestJsonRpc(sink, uri, method, params, options)

Creates a RequestJsonRpc. Parameters:

I<sink> : a main thread sink that accepts a table built from the JSON data returned by the server

I<uri> : the URI of the JSON service (on the HTTP server pointed by the L<jive.net.SocketHttp> this request will be sent to)

I<method> : the method field of JSON

I<params> : the params field of JSON (a table that this class will convert to JSON)

I<options> : options as defined by L<jive.net.RequestHttp>. This class defines the request body.

Note the class calculates a JSON ID.
=cut
--]]
function __init(self, sink, uri, method, params, options)
	--log:debug("RequestJsonRpc:__init()")

--	_assert(method)
--	_assert(uri)
--	_assert(sink)
	if not params then
		params = {}
	end
	
	local json = {
		["method"] = method,
		["params"] = params,
	}
	local id = string.sub(tostring(json), 9)
	json.id = id
	
	if not options then
		options = {}
	end
	options.t_bodySource = _getBodySource(json)

	local obj = oo.rawnew(self, RequestHttp(sink, 'POST', uri, options))

	obj.json = json

	return obj
end


-- t_setResponseBody
-- HTTP socket data to process, along with a safe sink to send it to customer
function t_setResponseBody(self, data)
	--log:debug("RequestJsonRpc:t_setResponseBody()")
--	log:info(data)

	log:error("here")

	local sink = self:t_getResponseSink()
	
	-- abort if we have no sink
	if sink then
	
		-- the HTTP layer has read any data coming with a 404, but we do not care
		-- only send data back in case of 200!
		local code, err = self:t_getResponseStatus()
		if code == 200 then
			local mySink = ltn12.sink.chain(
				jsonfilters.decode,
				sink
			)
			mySink(data)
		else
			sink(nil, err)
		end
	end
end

--[[

=head2 getJsonId()

Returns the JsonId assigned to this request

=cut
--]]
function getJsonId(self)
	return self.json.id
end


--[[

=head2 tostring(aRequest)

If I<aRequest> is a L<jive.net.RequestJsonRpc>, prints
 RequestJsonRpc {id}

=cut
--]]
function __tostring(self)
	return "RequestJsonRpc {" .. tostring(self.json.id) .."}"
end
--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

