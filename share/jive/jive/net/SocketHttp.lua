
--[[
=head1 NAME

jive.net.SocketHttp - An HTTP socket.

=head1 DESCRIPTION

This class implements a HTTP socket running in a L<jive.net.NetworkThread>.

=head1 SYNOPSIS

 -- create a HTTP socket to communicate with http://192.168.1.1:9000/
 local http = jive.net.SocketHttp(jnt, "192.168.1.1", 9000, "slimserver")

 -- create a request (see L<jive.net.RequestHttp)
 local req = RequestHttp(sink, 'GET', '/xml/status.xml')

 -- go get it!
 http:fetch(req)


=head1 FUNCTIONS

=cut
--]]
-----------------------------------------------------------------------------
-- Convention: functions/methods starting with t_ are executed in the thread
-----------------------------------------------------------------------------


-- stuff we use
local _assert, ipairs, pairs, setmetatable, tostring, tonumber, type = _assert, ipairs, pairs, setmetatable, tostring, tonumber, type

local math        = require("math")
local table       = require("table")
local string      = require("string")
local coroutine   = require("coroutine")

local oo          = require("loop.simple")
local socket      = require("socket")
local mime        = require("mime")
local ltn12       = require("ltn12")

local System      = require("jive.System")

local Task        = require("jive.ui.Task")

local DNS         = require("jive.net.DNS")
local SocketTcp   = require("jive.net.SocketTcp")
local RequestHttp = require("jive.net.RequestHttp")

local debug       = require("jive.utils.debug")
local locale      = require("jive.utils.locale")
local log         = require("jive.utils.log").logger("net.http")

local JIVE_VERSION = jive.JIVE_VERSION

-- jive.net.SocketHttp is a subclass of jive.net.SocketTcp
module(...)
oo.class(_M, SocketTcp)


local BLOCKSIZE = 4096

-- timeout for socket operations
local SOCKET_CONNECT_TIMEOUT = 10 -- connect in 10 seconds
local SOCKET_BODY_TIMEOUT = 70 -- response in 70 seconds

-- http authentication credentials
local credentials = {}


-- Class method to set HTTP authentication headers
function setCredentials(class, cred)
	_assert(cred.ipport)
	_assert(cred.realm)
	_assert(cred.username)
	_assert(cred.password)

	-- FIXME this only supports one username:password per server
	local key = table.concat(cred.ipport, ":")
	credentials[key] = cred
end


--[[

=head2 jive.net.SocketHttp(jnt, host, port, name)

Creates an HTTP socket named I<name> to interface with the given I<jnt> 
(a L<jive.net.NetworkThread> instance). I<name> is used for debugging and
defaults to "". I<host> and I<port> are the hostname/IP host and port of the HTTP server.

=cut
--]]
function __init(self, jnt, host, port, name)
	log:debug("SocketHttp:__init(", name, ", ", host, ", ", port, ")")

	-- init superclass
	local obj = oo.rawnew(self, SocketTcp(jnt, host, port, name))

	-- hostname
	obj.host = host

	-- init states
	obj.t_httpSendState = 't_sendDequeue'
	obj.t_httpRecvState = 't_recvDequeue'
	
	-- init queues
	obj.t_httpSendRequests = {}
	obj.t_httpSendRequest = false

	obj.t_httpRecvRequests = {}
	obj.t_httpRecvRequest = false
	
	obj.t_httpProtocol = '1.1'
	
	return obj
end


--[[

=head2 jive.net.SocketHttp:fetch(request)

Use the socket to fetch an HTTP request.
I<request> must be an instance of class L<jive.net.RequestHttp>.
The class maintains an internal queue of requests to fetch.

=cut
--]]
function fetch(self, request)
	_assert(oo.instanceof(request, RequestHttp), tostring(self) .. ":fetch() parameter must be RequestHttp - " .. type(request) .. " - ".. debug.traceback())

	-- push the request
	table.insert(self.t_httpSendRequests, request)

	log:debug(self, " queuing ", request, " - ", #self.t_httpSendRequests, " requests in queue")
		
	-- start the state machine if it is idle
	self:t_sendDequeueIfIdle()
end


-- t_nextSendState
-- manages the http state machine for sending stuff to the server
function t_nextSendState(self, go, newState)
	log:debug(self, ":t_nextSendState(", go, ", ", newState, ")")

	if newState then
		_assert(self[newState] and type(self[newState]) == 'function')
		self.t_httpSendState = newState
	end
	
	if go then
		-- call the function
		-- self:XXX(bla) is really the same as self["XXX"](self, bla)
		self[self.t_httpSendState](self)
	end
end


-- t_dequeueRequest
-- removes a request from the queue, can be overridden by sub-classes
function _dequeueRequest(self)
	if #self.t_httpSendRequests > 0 then
		return table.remove(self.t_httpSendRequests, 1)
	end

	return nil
end


-- t_sendDequeue
-- removes a request from the queue
function t_sendDequeue(self)
	log:debug(self, ":t_sendDequeue()")

	self.t_httpSendRequest = self:_dequeueRequest()

	if self.t_httpSendRequest then
		log:debug(self, " send processing ", self.t_httpSendRequest)
		if self:connected() then
			self:t_nextSendState(true, 't_sendRequest')
		else
			self:t_nextSendState(true, 't_sendResolve')
		end
		return
	end
end


-- t_sendDequeueIfIdle
-- causes a dequeue and processing on the send queue if possible
function t_sendDequeueIfIdle(self)
	log:debug(self, ":t_sendDequeueIfIdle state=", self.t_httpSendState)

	if self.t_httpSendState == 't_sendDequeue' then
		self:t_nextSendState(true)
	end
end


-- t_sendResolve
-- resolve the hostname to an ip address
function t_sendResolve(self)
	log:debug(self, ":t_sendResolve()")

	if self.cachedIp then
		log:debug("Using cached ip address: ", self.cachedIp, " for: ", self.host)
		-- don't lookup an ip address
		self.t_tcp.address = self.cachedIp
		self:t_nextSendState(true, 't_sendConnect')
		return
	end

	if DNS:isip(self.host) then
		-- don't lookup an ip address
		self.t_tcp.address = self.host
		self:t_nextSendState(true, 't_sendConnect')
		return
	end

	local t = Task(tostring(self) .. "(D)", self, function()
		log:debug(self, " DNS loopup for ", self.host)
		local ip, err = DNS:toip(self.host)

		-- make sure the socket has not closed while
		-- resolving DNS
		if self.t_httpSendState ~= 't_sendResolve' then
			log:debug(self, " socket closed during DNS request")
			return
		end

		log:debug(self, " IP=", ip)
		if not ip then
		self:close(self.host .. " " .. err)
			return
		end

		self.t_tcp.address = ip
		self:t_nextSendState(true, 't_sendConnect')
	end)

	t:addTask()
end


-- t_sendConnect
-- open our socket
function t_sendConnect(self)
	log:debug(self, ":t_sendConnect()")

	local err = socket.skip(1, self:t_connect())
	
	if err then
		log:error(self, ":t_sendConnect: ", err)
		self:close(err)
		return
	end
		
	self:t_nextSendState(true, 't_sendRequest')
end


-- t_getSendHeaders
-- calculates the headers to send from a socket perspective
function t_getSendHeaders(self)
	log:debug(self, ":t_getSendHeaders()")

	-- default set
	local headers = {
		["User-Agent"] = table.concat({
			'SqueezePlay-',
			System:getMachine(),
			'/',
			string.gsub(JIVE_VERSION, "%s", "-"),
			' (',
			System:getArch(),
			')'})
	}
	
	local ip, port = self:t_getAddressPort()

	local req_headers = self.t_httpSendRequest:t_getRequestHeaders()
	if not req_headers["Host"] then
		if port == 80 then
			headers["Host"] = self.host
		else
			headers["Host"] = self.host .. ":" .. port
		end
	end
	
	if self.t_httpSendRequest:t_hasBody() then
		headers["Content-Length"] = #self.t_httpSendRequest:t_body()
	end

	req_headers["Accept-Language"] = string.lower(locale.getLocale())

	-- http authentication?
	local cred = credentials[ip .. ":" .. port]
	if cred then
		req_headers["Authorization"] = "Basic " .. mime.b64(cred.username .. ":" .. cred.password)
	end

	return headers
end


-- keep-open-non-blocking socket sink
-- our "keep-open" sink, added to the socket namespace so we can use it like any other
-- our version is non blocking
socket.sinkt["keep-open-non-blocking"] = function(sock)
	local first = 0
	return setmetatable(
		{
			getfd = function() return sock:getfd() end,
			dirty = function() return sock:dirty() end
		}, 
		{
			__call = function(self, chunk, err)
				log:debug("keep-open-non-blocking sink(", chunk and #chunk, ", ", tostring(err), ", ", tostring(first), ")")
				if chunk then 
					local res, err
					-- if send times out, err is 'timeout' and first is updated.
					res, err, first = sock:send(chunk, first+1)
					log:debug("keep-open-non-blocking sent - first is ", tostring(first), " returning ", tostring(res), ", " , tostring(err))
					-- we return the err
					return res, err
				else 
					return 1 
				end
			end
		}
	)
end


-- t_sendRequest
-- send the headers, aggregates request and socket headers
function t_sendRequest(self)
	log:debug(self, ":t_sendRequest()")

	local source = function()
		local line1 = string.format("%s HTTP/%s", self.t_httpSendRequest:t_getRequestString(), self.t_httpProtocol)

		local t = {}
		
		table.insert(t, line1)
		
		for k, v in pairs(self:t_getSendHeaders()) do
			table.insert(t, k .. ": " .. v)
		end
		for k, v in pairs(self.t_httpSendRequest:t_getRequestHeaders()) do
			table.insert(t, k .. ": " .. v)
		end
		
		table.insert(t, "")
		if self.t_httpSendRequest:t_hasBody() then
			table.insert(t, self.t_httpSendRequest:t_body())
		else
			table.insert(t, "")
		end

		return table.concat(t, "\r\n")
	end

	local sink = socket.sink('keep-open-non-blocking', self.t_sock)
	
	local pump = function (NetworkThreadErr)
		log:debug(self, ":t_sendRequest.pump()")
		
		if NetworkThreadErr then
			log:error(self, ":t_sendRequest.pump: ", NetworkThreadErr)
			self:close(NetworkThreadErr)
			return
		end
		
		local ret, err = ltn12.pump.step(source, sink)
		
		
		if err then
			-- do nothing on timeout, we will be called again to send the rest of the data...
			if err == 'timeout' then
				return
			end

			-- handle any "real" error
			log:error(self, ":t_sendRequest.pump: ", err)
			self:close(err)
			return
		end
		
		-- no error, we're done, move on!
		self:t_removeWrite()
		self:t_nextSendState(true, 't_sendComplete')
	end

	self:socketActive()

	self:t_addWrite(pump, SOCKET_CONNECT_TIMEOUT)
end


function t_sendComplete(self)
	if self.t_httpSendRequest then
		table.insert(self.t_httpRecvRequests, self.t_httpSendRequest)
		self.t_httpSendRequest = false
	end

	self:t_nextSendState(true, 't_sendDequeue')

	if self.t_httpRecvState == 't_recvDequeue' then
		self:t_nextRecvState(true)
	end
end


-- t_nextRecvState
-- manages the http state machine for receiving stuff to the server
function t_nextRecvState(self, go, newState)
	log:debug(self, ":t_nextRecvState(", go, ", ", newState, ")")

	if newState then
		_assert(self[newState] and type(self[newState]) == 'function')
		self.t_httpRecvState = newState
	end
	
	if go then
		-- call the function
		-- self:XXX(bla) is really the same as self["XXX"](self, bla)
		self[self.t_httpRecvState](self)
	end
end


-- t_recvDequeue
-- removes a request from the queue
function t_recvDequeue(self)
	log:debug(self, ":t_recvDequeue() queueLength=", #self.t_httpRecvRequests)

	_assert(not self.t_httpRecvRequest, "Already dequeued in t_recvDequeue")

	self.t_httpRecvRequest = table.remove(self.t_httpRecvRequests, 1)

	if self.t_httpRecvRequest then
		log:debug(self, " recv processing ", self.t_httpRecvRequest)
		self:t_nextRecvState(true, 't_rcvHeaders')
		return
	end
	
	-- back to idle
	log:debug(self, ": no request recv in queue")

	if self:connected() then
		local pump = function(NetworkThreadErr)
				     self:close("idle close")
			     end

		self:t_addRead(pump)
	end
end



-- t_rcvHeaders
--
function t_rcvHeaders(self)
	log:debug(self, ":t_rcvHeaders()")

	local line, err, partial = true
	local source = function()
		line, err, partial = self.t_sock:receive('*l', partial)
		if err then
			if err == 'timeout' then
				return false, err
			end

			log:error(self, ":t_rcvHeaders.pump:", err)
			self:close(err)
			return false, err
		end

		return line
	end


	local headers = {}
	local statusCode = false
	local statusLine = false

	local pump = function (NetworkThreadErr)
		log:debug(self, ":t_rcvHeaders.pump()")
		if NetworkThreadErr then
			log:error(self, ":t_rcvHeaders.pump:", NetworkThreadErr)
			self:close(NetworkThreadErr)
			return
		end

		-- read status line
		if not statusCode then
			local line, err = source()
			if err then
				return
			end

			local data = socket.skip(2, string.find(line, "HTTP/%d*%.%d* (%d%d%d)"))

			if data then
				statusCode = tonumber(data)
				statusLine = line
			else
				self:close(err)
				return
			end
		end

		-- read headers
		while true do
			local line, err = source()
			if err then
				return
			end

			if line ~= "" then
				local name, value = socket.skip(2, string.find(line, "^(.-):%s*(.*)"))
				if not (name and value) then
					err = "malformed reponse headers"
					log:warn(err)
					self:close(err)
					return
				end

				headers[name] = value
			else
				-- we're done
				self.t_httpRecvRequest:t_setResponseHeaders(statusCode, statusLine, headers)

				-- move on to our future...
				self:t_nextRecvState(true, 't_rcvResponse')
				return
			end
		end
	end
	
	self:t_addRead(pump, SOCKET_BODY_TIMEOUT)
end


-- jive-until-close socket source
-- our "until-close" source, added to the socket namespace so we can use it like any other
-- the code is identical to the one in socket, except we return the closed error when 
-- it happens. The source/sink concept is based on the fact sources are called until 
-- they signal no more data (by returning nil). We can't use that however since the 
-- pump won't be called in select!
socket.sourcet["jive-until-closed"] = function(sock, self)
	local done
	local partial
	return setmetatable(
		{
			getfd = function() return sock:getfd() end,
			dirty = function() return sock:dirty() end
		}, 
		{
			__call = function()
			
				if done then 
					return nil 
				end
			
				local chunk, err
				chunk, err, partial = sock:receive(BLOCKSIZE, partial)
				
				if not err then 
					return chunk
				elseif err == "closed" then
					--close the socket using self
					SocketTcp.close(self)
					done = true
					return partial, 'done'
				else -- including timeout
					return nil, err 
				end
			end
		}
	)
end


-- jive-by-length socket source
-- same principle as until-close, we need to return somehow the fact we're done
socket.sourcet["jive-by-length"] = function(sock, length)
	local partial
	return setmetatable(
		{
			getfd = function() return sock:getfd() end,
			dirty = function() return sock:dirty() end
		}, 
		{
			__call = function()
				if length <= 0 then 
					return nil, 'done' 
				end
		
				local size = math.min(BLOCKSIZE, length)

				local chunk, err
				chunk, err, partial = sock:receive(size, partial)
				
				if err then -- including timeout
					return nil, err 
				end
				length = length - string.len(chunk)
				if length <= 0 then
					return chunk, 'done'
				else
					return chunk
				end
			end
		}
	)
end


-- jive-http-chunked source
-- same as the one in http, except does not attempt to read headers after
-- last chunk and returns 'done' pseudo error
socket.sourcet["jive-http-chunked"] = function(sock)
	local partial
	local schunk
	local pattern = '*l'
	local step = 1
	return setmetatable(
		{
			getfd = function() return sock:getfd() end,
			dirty = function() return sock:dirty() end
		}, 
		{
			__call = function()

				-- read
				local chunk, err
				chunk, err, partial = sock:receive(pattern, partial)

				log:debug("SocketHttp.jive-http-chunked.source(", chunk and #chunk, ", ", err, ")")

				if err then
					log:debug("SocketHttp.jive-http-chunked.source - RETURN err")
					return nil, err 
				end
				
				if step == 1 then
					-- read size
					local size = tonumber(string.gsub(chunk, ";.*", ""), 16)
					if not size then 
						return nil, "invalid chunk size" 
					end
					log:debug("SocketHttp.jive-http-chunked.source - size: ", tostring(size))
			
					-- last chunk ?
					if size > 0 then
						step = 2
						pattern = size
						return nil, 'timeout'
					else
						return nil, 'done'
					end
				end
				
				if step == 2 then
					log:debug("SocketHttp.jive-http-chunked.source(", chunk and #chunk, ", ", err, ", ", part and #part, ")")
					
					-- remember chunk, go read terminating CRLF
					step = 3
					pattern = '*l'
					schunk = chunk
					return nil, 'timeout'
				end
				
				if step == 3 then
					log:debug("SocketHttp.jive-http-chunked.source 3 (", chunk and #chunk, ", ", err, ", ", part and #part, ")")
					
					-- done
					step = 1
					return schunk
				end
			end
		}
	)
end


local sinkt = {}


-- jive-concat sink
-- a sink that concats chunks and forwards to the request once done
sinkt["jive-concat"] = function(request)
	local data = {}
	return function(chunk, src_err)
		log:debug("SocketHttp.jive-concat.sink(", chunk and #chunk, ", ", src_err, ")")
		
		if src_err and src_err ~= "done" then
			-- let the pump handle errors
			return nil, src_err
		end
		
		-- concatenate any chunk
		if chunk and chunk ~= "" then
			table.insert(data, chunk)
		end

		if not chunk or src_err == "done" then
			local blob = table.concat(data)
			-- let request decide what to do with data
			request:t_setResponseBody(blob)
			log:debug("SocketHttp.jive-concat.sink: done ", #blob)
			return nil
		end
		
		return true
	end
end


-- jive-by-chunk sink
-- a sink that forwards each received chunk as complete data to the request
sinkt["jive-by-chunk"] = function(request)
	return function(chunk, src_err)
		log:debug("SocketHttp.jive-by-chunk.sink(", chunk and #chunk, ", ", src_err, ")")
	
		if src_err and src_err ~= "done" then
			-- let the pump handle errors
			return nil, src_err
		end

		-- forward any chunk
		if chunk and chunk ~= "" then
			-- let request decide what to do with data
			log:debug("SocketHttp.jive-by-chunk.sink: chunk bytes: ", #chunk)
			request:t_setResponseBody(chunk)
		end

		if not chunk or src_err == "done" then
			log:debug("SocketHttp.jive-by-chunk.sink: done")
			request:t_setResponseBody(nil)
			return nil
		end
	
		return true
	end
end


-- _getSink
-- returns a sink for the request
local function _getSink(mode, request, customerSink)
	local f = sinkt[mode]
	if not f then 
		log:error("Unknown mode: ", mode, " - using jive-concat")
		f = sinkt["jive-concat"]
	end
	return f(request, customerSink)
end


-- t_rcvResponse
-- acrobatics to read the response body
function t_rcvResponse(self)
	local mode
	local len

	if self.t_httpRecvRequest:t_getResponseHeader('Transfer-Encoding') == 'chunked' then
	
		mode = 'jive-http-chunked'

		-- don't count the chunked connections as active, these are
		-- long term connections used for server push
		self:socketInactive()
	else
			
		if self.t_httpRecvRequest:t_getResponseHeader("Content-Length") then
			-- if we have a length, use it!
			len = tonumber(self.t_httpRecvRequest:t_getResponseHeader("Content-Length"))
			mode = 'jive-by-length'
			
		else
			-- by default we close and we start from scratch for the next request
			mode = 'jive-until-closed'
		end
	end

	local connectionClose = self.t_httpRecvRequest:t_getResponseHeader('Connection') == 'close'
	
	local source = socket.source(mode, self.t_sock, len or self)
	
	local sinkMode = self.t_httpRecvRequest:t_getResponseSinkMode()
	local sink = _getSink(sinkMode, self.t_httpRecvRequest)

	local pump = function (NetworkThreadErr)
		log:debug(self, ":t_rcvResponse.pump(", mode, ", ", tostring(nt_err) , ")")
		
		if NetworkThreadErr then
			log:error(self, ":t_rcvResponse.pump() error:", NetworkThreadErr)
			self:close(NetworkThreadErr)
			return
		end
		
		
		local continue, err = ltn12.pump.step(source, sink)
		
		-- shortcut on timeout
		if err == 'timeout' then
			return
		end
		
		if not continue then
			-- we're done
			log:debug(self, ":t_rcvResponse.pump: done (", err, ")")
			
			-- remove read handler
			self:t_removeRead()
			
			-- handle any error
			if err and err ~= "done" then
				self:close(err)
				return
			end

			if connectionClose then
				-- just close the socket, don't reset our state
				SocketTcp.close(self)
			end

			-- move on to our future
			self:t_nextRecvState(true, 't_recvComplete')
		end
	end
	
	self:t_addRead(pump, SOCKET_BODY_TIMEOUT)
end


function t_recvComplete(self)
	self:socketInactive()

	self.t_httpRecvRequest = false
	self:t_nextRecvState(true, 't_recvDequeue')
end


-- free
-- frees our socket
function free(self)
	log:debug(self, ":free()")

	-- dump queues
	-- FIXME: should it free requests?
	self.t_httpSendRequests = {}
	self.t_httpSendRequest = false

	self.t_httpRecvRequests = {}
	self.t_httpRecvRequest = false
	
	SocketTcp.free(self)
end


-- close
-- close our socket
function close(self, err)
	log:debug(self, " closing with err: ", err)

	-- close the socket
	SocketTcp.close(self)

	-- cancel all requests 'on the wire'
	local errorSendRequest = self.t_httpSendRequest
	local errorRecvRequests = self.t_httpRecvRequests
	if self.t_httpRecvRequest then
		table.insert(errorRecvRequests, 1, self.t_httpRecvRequest)
	end

	self.t_httpSendRequest = false
	self.t_httpRecvRequest = false
	self.t_httpRecvRequests = {}

	-- start again
	self:t_nextSendState(true, 't_sendDequeue')
	self:t_nextRecvState(true, 't_recvDequeue')

	-- the http state must be updated before here, the errorSink's
	-- may re-enter this object with a new http request

	-- error for send requests
	if errorSendRequest then
		local errorSink = errorSendRequest:t_getResponseSink()
		if errorSink then
			errorSink(nil, err)
		end
	end

	-- error for recv requests, including pipeline
	for i, request in ipairs(errorRecvRequests) do
		local errorSink = request:t_getResponseSink()
		if errorSink then
			errorSink(nil, err)
		end
	end
end


--[[

=head2 tostring(aSocket)

if I<aSocket> is a L<jive.net.SocketHttp>, prints
 SocketHttp {name}

=cut
--]]
function __tostring(self)
	return "SocketHttp {" .. tostring(self.jsName) .. "}"
end

--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

