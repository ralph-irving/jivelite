
--[[
=head1 NAME

jive.net.CometRequest - A Comet request over HTTP.

=head1 DESCRIPTION

jive.net.CometRequest encapsulates a Comet HTTP request
over POST HTTP. It is a subclass of L<jive.net.RequestHttp>.

Note the implementation uses the source and sink concept of luasocket.

=head1 SYNOPSIS

 -- create a sink to receive the JSON response
 local function mySink(chunk, err)
   if err then
     print("error!: " .. err)
   elseif chunk then
     print("received: " .. chunk.id)
   end
 end
 
 -- create a CometRequest, passing in the full URI and data to encode into JSON
 local req = CometRequest(mySink, uri, data)

 -- use a Comet socket to fetch
 comet:fetch(myRequest)

=head1 FUNCTIONS

=cut
--]]
-----------------------------------------------------------------------------
-- Convention: functions/methods starting with t_ are executed in the thread
-----------------------------------------------------------------------------


-- stuff we use
local oo          = require("loop.simple")
local ltn12       = require("ltn12")

local RequestHttp = require("jive.net.RequestHttp")
local jsonfilters = require("jive.utils.jsonfilters")

local log         = require("jive.utils.log").logger("net.comet")

-- jive.net.CometRequest is a subclass of jive.net.RequestHttp
module(...)
oo.class(_M, RequestHttp)


-- _getBodySource (OVERRIDE)
-- returns the body
-- FIXME: we no longer have the problem with loop, change it to static during __init
function _getBodySource(data)
	local sent = false
	return ltn12.source.chain(
		function()
			if sent then
				return nil
			else
				sent = true
				return data
			end
		end, 
		jsonfilters.encode
	)
end


--[[

=head2 jive.net.CometRequest(sink, uri, data, options)

Creates a CometRequest. Parameters:

I<sink> : a main thread sink that accepts a table built from the JSON data returned by the server

I<uri> : the URI of the Comet service

I<data> : data to encode as JSON in the request

I<options> : options to pass to L<jive.net.RequestHttp>

=cut
--]]
function __init(self, sink, uri, data, options)
	--log:debug("CometRequest:__init()")
	
	if not options then
		options = {
			headers = {
				['Content-Type'] = 'text/json',
			}
		}
	end
	
	options.t_bodySource = _getBodySource(data)

	local obj = oo.rawnew( self, RequestHttp(sink, 'POST', uri, options) )

	return obj
end

-- Tells SocketHttp whether to return us chunks or the whole response
function t_getResponseSinkMode(self)
	if self:t_getResponseHeader("Transfer-Encoding") then
		return 'jive-by-chunk'
	else
		return 'jive-concat'
	end
end

-- t_setResponseBody
-- HTTP socket data to process, along with a safe sink to send it to customer
function t_setResponseBody(self, data)
--	log:debug("CometRequest:t_setResponseBody()")
--	log:info(data)

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
			mySink(data, nil, self)
		else
			sink(nil, err, self)
		end
	end
end

--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

