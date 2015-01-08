
--[[
=head1 NAME

jive.net.RequestHttp - An HTTP request.

=head1 DESCRIPTION

jive.net.RequestHttp implements an HTTP request to be processed
by a L<jive.net.SocketHttp>.

=head1 SYNOPSIS

 -- create a sink to receive XML
 local function sink(chunk, err)
   if err then
     print("error!: " .. err)
   elseif chunk then
     print("received: " .. chunk)
   end
 end
 
 -- create a HTTP socket (see L<jive.net.SocketHttp>)
 local http = jive.net.SocketHttp(jnt, "192.168.1.1", 9000, "slimserver")

 -- create a request to GET http://192.168.1.1:9000/xml/status.xml
 local req = RequestHttp(sink, 'GET', 'http://192.168.1.1:9000/xml/status.xml')

 -- go get it!
 http:fetch(req)

=head1 FUNCTIONS

=cut
--]]
-----------------------------------------------------------------------------
-- Convention: functions/methods starting with t_ are executed in the thread
-----------------------------------------------------------------------------


-- stuff we use
local _assert, pairs, tostring, type = _assert, pairs, tostring, type

local string    = require("string")

local oo        = require("loop.base")
local url       = require("socket.url")
local table     = require("jive.utils.table")
local ltn12       = require("ltn12")

local Task      = require("jive.ui.Task")

local log       = require("jive.utils.log").logger("net.http")
local jnt       = jnt
local jive      = jive

-- our class
module(..., oo.class)


-- catch errors in a sink or source
local function _makeSafe(sourceOrSink, errstr)
	if sourceOrSink == nil then
		return nil
	end

	return function(...)
		       local status, chunk, sink = Task:pcall(sourceOrSink, ...)

		       if not status then
			       log:error(errstr, chunk)
			       return nil, chunk
		       end

		       return chunk, sink
	       end
end


--[[

=head2 jive.net.RequestHttp(sink, method, uri, options)

Creates a RequestHttp. Parameters:

I<sink> : a main thread lnt12 sink. Will be called with nil when data is complete,
in order to be compatible with filters and other ltn12 stuff. However for performance
reasons, data is concatenated on the network thread side.

I<method> : the HTTP method to use, 'POST' or 'GET'. If POST, a POST body source must be provided in I<options>.

I<uri> : the URI to GET/POST to

I<options> : table with optional parameters: I<t_bodySource> is a lnt12 source required for POST operation;
I<headers> is a table with aditional headers to use for the request.

=cut
--]]
function __init(self, sink, method, uri, options)
--	log:debug("RequestHttp:__init()")

--[[
	if sink then
		_assert(type(sink) == 'function', "HTTP sink must be a function")
	end
	_assert(method, "Cannot create a RequestHttp without method")
	_assert(type(method) == 'string', "HTTP method shall be a string")
	_assert(method == 'GET' or method == 'POST', "HTTP methods other than POST or GET not supported")
	_assert(uri, "Cannot create a RequestHttp without uri")
	_assert(type(uri) == 'string', "HTTP uri shall be a string")
--]]
	
	-- default set of request side headers
	local defHeaders = {}
	local t_bodySource, headersSink
	local stream = false

	-- handle the options table
	if options then
		-- validate t_bodySource
		t_bodySource = options.t_bodySource
		if t_bodySource then
--			_assert(type(t_bodySource) == 'function', "HTTP body source shall be a function")
			if method == 'GET' then
				log:warn("Body source provided in HTTP request won't be used by GET request")
			end
		else
--			_assert(method == 'GET', "HTTP POST requires body source")
		end
		
		-- override/add provided headers, if any
		if options.headers then
			for k, v in pairs(options.headers) do
				defHeaders[k] = v
			end
		end
		
		headersSink = options.headersSink
		if headersSink then
			_assert(type(headersSink) == 'function', "HTTP header sink must be a function")
		end

		if options.stream then
			stream = options.stream
		end
	end
	
	-- Default URI settings
	local defaults = {
	    host   = "",
	    port   = 80,
	    path   = "/",
	    scheme = "http"
	}
	
	local parsed = url.parse(uri, defaults)
	
	-- Set the Host header based on the URI if possible
	if parsed.host ~= "" then
		defHeaders["Host"] = parsed.host
		if parsed.port ~= 80 then
			defHeaders["Host"] = defHeaders["Host"] .. ':' .. parsed.port
		end
	end

	return oo.rawnew(self, {
		-- request params
		t_httpRequest = {
			["method"]  = method,
			["uri"]     = parsed,
			["src"]     = t_bodySource,
			["headers"] = defHeaders,
		},
		-- response
		t_httpResponse = {
			["statusCode"]  = false,
			["statusLine"]  = false,
			["headers"]     = false,
			["headersSink"] = headersSink,
			["body"]        = "",
			["done"]        = false,
			["sink"]        = sink,
			["stream"]      = stream,
		},
		-- stash options in case of redirect
		options = options,
	})
end

-- return the parsed URI table
function getURI(self)
	return self.t_httpRequest.uri
end

-- t_hasBody
-- returns if the request has a body to send, i.e. is POST
function t_hasBody(self)
	return self.t_httpRequest.method == 'POST'
end


function t_body(self)
	if not self.t_httpRequest.body and self:t_hasBody() then
		local body = {}
		local bodySink = ltn12.sink.table(body)

		ltn12.pump.all(self:t_getBodySource(), bodySink)

		self.t_httpRequest.body = table.concat(body)
	end
	return self.t_httpRequest.body
end


-- t_getRequestString
-- returns the HTTP request string, i.e. "GET uri"
function t_getRequestString(self)
	local uri = self.t_httpRequest.uri
	local str = {
		self.t_httpRequest.method,
		" ",
		uri.path
	}

	if str[1] == "GET" then
		if uri.params then
			str[#str + 1] = ";"
			str[#str + 1] = uri.params
		end
		if uri.query then
			str[#str + 1] = "?"
			str[#str + 1] = uri.query
		end
		if uri.fragment then
			str[#str + 1] = "#"
			str[#str + 1] = uri.fragment
		end
	end

	return table.concat(str)
end


-- t_getRequestHeaders
-- returns the request specific headers
function t_getRequestHeaders(self)
	return self.t_httpRequest.headers
end


-- t_getRequestHeader
-- returns a specific request header
function t_getRequestHeader(self, key)
	return self.t_httpRequest.headers[key]
end


-- t_getBodySource
-- returns the body source
function t_getBodySource(self)
	--log:debug("RequestHttp:t_getBodySource()")
	return _makeSafe(self.t_httpRequest.src, "Body source:")
end


-- t_setResponseHeaders
-- receives the response headers from the HTTP layer
function t_setResponseHeaders(self, statusCode, statusLine, headers)
--	log:debug(
--		"RequestHttp:t_setResponseHeaders(", 
--		self, 
--		": ", 
--		statusCode, 
--		", ", 
--		statusLine, 
--		")"
--	)
	
	local mappedHeaders = {}
	for k, v in pairs(headers) do
		mappedHeaders[string.lower(k)] = v;
	end
	
	self.t_httpResponse.statusCode = statusCode
	self.t_httpResponse.statusLine = statusLine
	self.t_httpResponse.headers = mappedHeaders
	
	local sink = self.t_httpResponse.headersSink
	
	-- abort if we have no sink
	if sink then
		sink(headers)
	end
end


-- t_getResponseHeader
-- returns a response header
function t_getResponseHeader(self, key)
	if self.t_httpResponse.headers then
		return self.t_httpResponse.headers[string.lower(key)]
	else
		return nil
	end
end


-- t_getResponseStatus
-- returns the status code and the status line
function t_getResponseStatus(self)
	return self.t_httpResponse.statusCode, self.t_httpResponse.statusLine
end


-- t_getResponseSinkMode
-- returns the sink mode
function t_getResponseSinkMode(self)
--	log:debug("RequestHttp:t_getResponseSinkMode()")

	if self.t_httpResponse.stream then
		return "jive-by-chunk"
	else
		return "jive-concat"
	end
end


-- t_getResponseSink
-- returns the sink mode
function t_getResponseSink(self)
--	log:debug("RequestHttp:t_getResponseSink()")

	return _makeSafe(self.t_httpResponse.sink, "Response sink:")
end


-- t_setResponseBody
-- HTTP socket data to process, along with a safe sink to send it to customer
function t_setResponseBody(self, data)
--	log:info("RequestHttp:t_setResponseBody(", self, ")")

	local sink = self:t_getResponseSink()

	-- abort if we have no sink
	if sink then
	
		local code, err = self:t_getResponseStatus()

		-- handle 200 OK
		if code == 200 then

			if self.t_httpResponse.stream then
				sink(data, nil, self)
			else
				if data and data ~= "" then
					sink(data, nil, self)
					sink(nil, nil, self)
				end
			end

		-- handle redirects	
		elseif (code == 301 or code == 302 or code == 307) and self.t_httpRequest.method == 'GET' and
		       (not self.redirect or self.redirect < 5) then

			local redirectUrl = self:t_getResponseHeader("Location")
			log:info(code, " redirect: ", redirectUrl)

			-- recreate headers and parsed uri
			local defaults = {
				host   = "",
				port   = 80,
				path   = "/",
				scheme = "http"
			}
			local parsed = url.parse(redirectUrl, defaults)
			
			local defHeaders = {}
			if self.options and self.options.headers then
				for k, v in pairs(self.options.headers) do
					defHeaders[k] = v
				end
			end
			if parsed.host ~= "" then
				defHeaders["Host"] = parsed.host
				if parsed.port ~= 80 then
					defHeaders["Host"] = defHeaders["Host"] .. ':' .. parsed.port
				end
			end

			self.redirect = (self.redirect or 0) + 1

			self.t_httpRequest.headers     = defHeaders
			self.t_httpRequest.uri         = parsed

			self.t_httpResponse.statusCode = false
			self.t_httpResponse.statusLine = false
			self.t_httpResponse.headers    = false
			self.t_httpResponse.body       = ""
			self.t_httpResponse.done       = false

			jive.net.SocketHttp(jnt, parsed.host, parsed.port, url):fetch(self)

		-- handle errors
		else
			if not err then
				err = "HTTP request failed with code" .. code
			end
			sink(nil, err, self)
		end
	end
end


--[[

=head2 tostring(aRequest)

If I<aRequest> is a L<jive.net.RequestHttp>, prints
 RequestHttp {name}

=cut
--]]
function __tostring(self)
	return "RequestHttp {" .. self:t_getRequestString() .. "}"
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

