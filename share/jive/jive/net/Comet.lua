
--[[
=head1 NAME

jive.net.Comet - An HTTP socket that implements the Cometd Bayeux protocol.

=head1 DESCRIPTION

This class implements a HTTP socket running in a L<jive.net.NetworkThread>.

=head1 SYNOPSIS

 -- create a Comet socket to communicate with http://192.168.1.1:9000/
 local comet = jive.net.Comet(jnt, "192.168.1.1", 9000, "/cometd", "slimserver")

 -- subscribe to an event
 -- will callback to func whenever there is an event
 -- playerid may be nil
 comet:subscribe('/slim/serverstatus', func, playerid, {'serverstatus', 0, 50, 'subscribe:60'})

 -- unsubscribe from an event
 comet:unsubscribe('/slim/serverstatus', func)

 -- or unsubscribe all callbacks
 comet:unsubscribe('/slim/serverstatus')

 -- send a non-subscription request
 -- playerid may be nil
 -- request is a table (array) containing the raw request to pass to SlimServer
 comet:request(func, playerid, request)

 -- add a callback function for an already-subscribed event
 comet:addCallback('/slim/serverstatus', func)

 -- remove a callback function
 comet:removeCallback('/slim/serverstatus', func)

 -- start!
 comet:connect()

 -- disconnect
 comet:disconnect()

 -- batch a set of calls together into one request
  comet:startBatch()
  comet:subscribe(...)
  comet:request(...)
  comet:endBatch()

=head1 FUNCTIONS

=cut
--]]
-----------------------------------------------------------------------------
-- Convention: functions/methods starting with t_ are executed in the thread
-----------------------------------------------------------------------------


-- stuff we use
local assert, ipairs, table, pairs, string, tonumber, tostring = assert, ipairs, table, pairs, string, tonumber, tostring

local oo            = require("loop.simple")
local math          = require("math")

local System        = require("jive.System")
local CometRequest  = require("jive.net.CometRequest")
local HttpPool      = require("jive.net.HttpPool")
local SocketHttp    = require("jive.net.SocketHttp")
local Timer         = require("jive.ui.Timer")
local Task          = require("jive.ui.Task")
local DNS           = require("jive.net.DNS")

local debug         = require("jive.utils.debug")
local log           = require("jive.utils.log").logger("net.comet")

local JIVE_VERSION  = jive.JIVE_VERSION

-- times are in ms
local RETRY_DEFAULT = 5000  -- default delay time to retry connection (5s)
local MAX_BACKOFF   = 60000 -- don't wait longer than this before retrying (60s)

-- jive.net.Comet is a base class
module(..., oo.class)


-- forward declarations
local _addPendingRequests
local _sendPendingRequests
local _state
local _handshake
local _getHandshakeSink
local _connect
local _reconnect
local _connected
local _getEventSink
local _getRequestSink
local _response
local _disconnect
local _handleAdvice
local _handleTimer


-- connection state
local UNCONNECTED    = "UNCONNECTED"    -- not connected
local CONNECTING     = "CONNECTING"     -- handshake request sent
local CONNECTED      = "CONNECTED"      -- handshake completed
local UNCONNECTING   = "UNCONNECTING"   -- disconnect request sent


--[[

=head2 jive.net.Comet(jnt, ip, port, path, name)

Creates A Comet socket named I<name> to interface with the given I<jnt> 
(a L<jive.net.NetworkThread> instance). I<name> is used for debugging and
defaults to "".

Notifications:

 cometConnected(self)
 cometDisconnected(self)

=cut
--]]
function __init(self, jnt, name)
	log:debug("Comet: __init(", name, ")")

	-- init superclass
	local obj = oo.rawnew( self, {} )
	
	obj.uri            = false
	obj.chttp          = false
	obj.rhttp          = false
	
	obj.jnt            = jnt
	obj.name           = name
	obj.aggressive     = false    -- agressive reconnects

	obj.isactive       = false    -- is the connection active
	obj.state          = UNCONNECTED -- connection state:

	obj.clientId       = nil      -- clientId provided by server
	obj.reqid          = 1        -- used to identify non-subscription requests
	obj.advice         = {}       -- advice from server on how to handle reconnects
	obj.failures       = 0        -- count of connection failures
	obj.batch          = 0        -- are we batching queries?
	
	obj.subs           = {}       -- all subscriptions
	obj.pending_unsubs = {}       -- pending unsubscribe requests
	obj.pending_reqs   = {}       -- pending requests to send with connect
	obj.sent_reqs      = {}       -- sent requests, awaiting a response
	obj.notify         = {}       -- callbacks to notify

	-- Reconnection timer
	obj.reconnect_timer = Timer(0, function() _handleTimer(obj) end, true)

	-- Subscribe to networkConnected events, which happen if we change wireless networks
	jnt:subscribe(obj)
	
	return obj
end


-- Enable aggressive reconnections
function aggressiveReconnect(self, aggressive)
	self.aggressive = aggressive
end


-- setEndpoint:
-- I<ip> and I<port> are the IP address and port of the HTTP server.
-- I<path> is the absolute path to the servers cometd handler and defaults to
-- '/cometd'.
function setEndpoint(self, ip, port, path)
	log:debug(self, ": setEndpoint state=", self.state, ", ", ip, ", ", port, ", ", path)

	local oldState = self.state

	-- Force disconnection
	_state(self, UNCONNECTED)
	
	self.uri = 'http://' .. ip .. ':' .. port .. path
	
	-- Comet uses 2 pools, 1 for chunked responses and 1 for requests
	self.chttp = SocketHttp(self.jnt, ip, port, self.name .. "_Chunked")
	self.rhttp = SocketHttp(self.jnt, ip, port, self.name .. "_Request")

	self.chttp:setPriority(Task.PRIORITY_HIGH)
	self.rhttp:setPriority(Task.PRIORITY_HIGH)

	if oldState == CONNECTING or oldState == CONNECTED then
		-- Reconnect
		_handshake(self)
	end
end


function connect(self)
	log:debug(self, ": connect state=", self.state)

	assert(self.uri)

	self.isactive = true

	if self.state == CONNECTING or self.state == CONNECTED then
		-- Already connecting/connected
		return
	end

	if self.state == UNCONNECTING then
		-- Force disconnection
		_state(self, UNCONNECTED)
	end

	_handshake(self)
end


function disconnect(self)
	log:debug(self, ": disconnect state=", self.state)

	self.isactive = false

	if self.state == UNCONNECTED or self.state == UNCONNECTING then
		-- Already disconnecting/unconnected
		return
	end

	if self.state == CONNECTING then
		-- Force disconnection
		_state(self, UNCONNECTED)
		return
	end

	_disconnect(self)
end


function notify_networkConnected(self)
	if self.state == CONNECTING or self.state == CONNECTED then
		log:info(self, ": Got networkConnected event, will try to reconnect")

		-- Force disconnection, and reconnect
		_state(self, UNCONNECTED)
		self:connect()

	else
		log:debug(self, ": Got networkConnected event, but not currently connected")
	end
end


-- Add any pending requests to the request data
_addPendingRequests = function(self, data)

	-- Add pending unsubscribe requests
	-- Do this before pending subscription requests in case
	-- a timing window with network reconnects results in the
	-- possibility of an old unsubscribe negating a newer subscribe.
	for i, v in ipairs( self.pending_unsubs ) do
		local unsub = {
			channel = '/slim/unsubscribe',
			id      = v.reqid,
			data    = {
				unsubscribe = '/' .. self.clientId .. v.subscription,
			},
		}

		table.insert( data, unsub )
		table.insert( self.sent_reqs, unsub )
	end

	-- Clear out pending requests
	self.pending_unsubs = {}

	-- Add any pending subscription requests
	for i, v in ipairs( self.subs ) do
		if v.pending then
			local cmd = {
				v.playerid or '',
				v.request
			}
			
			-- Prepend clientId to subscription name
			local subscription = '/' .. self.clientId .. v.subscription

			local sub = {
				channel = '/slim/subscribe',
				id      = v.reqid,
				data    = {
					request  = cmd,
					response = subscription,
					priority = v.priority,
				},
			}

			-- Add callback
			if not self.notify[v.subscription] then
				self.notify[v.subscription] = {}
			end
			self.notify[v.subscription][v.func] = v.func
			
			-- Remove pending status from this sub
			v.pending = nil
	
			table.insert( data, sub )
			table.insert( self.sent_reqs, sub )
		end
	end

	-- Add pending requests
	for i, v in ipairs( self.pending_reqs ) do
		local cmd = {
			v.playerid or '',
			v.request
		}
	
		local req = {
			channel = '/slim/request',
			data    = {
				request  = cmd,
				response = '/' .. self.clientId .. '/slim/request',
				priority = v.priority,
			},
		}

		-- Only ask for a response if we have a callback function
		if v.func then
			req.id = v.reqid
				
			-- Store this request's callback
			local subscription = '/slim/request|' .. v.reqid
			if not self.notify[subscription] then
				self.notify[subscription] = {}
			end
			self.notify[subscription][v.func] = v.func

			table.insert( self.sent_reqs, req )
		end

		table.insert( data, req )
	end

	-- Clear out pending requests
	self.pending_reqs = {}
end


-- Send any pending subscriptions and requests
_sendPendingRequests = function(self, data)

	-- add all pending unsub requests, and any others we need to send
	if not data then
		data = {}
	end
	_addPendingRequests(self, data)
	
	-- Only continue if we have some data to send
	if data[1] then
		if log:isDebug() then
			log:debug("Sending pending request(s):")
			debug.dump(data, 5)
		end

		local req = CometRequest(
			_getRequestSink(self),
			 self.uri,
			 data
		)
		-- always use the long lived connection's (chttp) ip address, otherwise the ip address of rhttp can change from chhtp's. 
		if DNS:isip(self.chttp.t_tcp.address) then
			log:debug("caching chttp ip address: ", self.chttp.t_tcp.address, " for: ", self.uri)
			self.rhttp.cachedIp = self.chttp.t_tcp.address
		end
		self.rhttp:fetch(req)
	end
end


function subscribe(self, subscription, func, playerid, request, priority)
	local id = self.reqid

	if log:isDebug() then
		log:debug(self, ": subscribe(", subscription, " ", func, ", reqid:", id, ", ", playerid, ", ", table.concat(request, ","), ", priority:", priority, ")")
	end
	
	-- Remember subs to send during connect now, or if we get
	-- disconnected
	table.insert( self.subs, {
		reqid        = id,
		subscription = subscription,
		playerid     = playerid,
		request      = request,
		func         = func,
		priority     = priority,
		pending      = true, -- pending means we haven't sent this sub request yet
	} )

	-- Bump reqid for the next request
	self.reqid = id + 1

	-- Send immediately unless we're batching queries
	if self.state ~= CONNECTED or self.batch ~= 0 then
		return
	end

	-- Send all pending requests and subscriptions
	_sendPendingRequests(self)
end


function unsubscribe(self, subscription, func)
	local id = self.reqid

	log:debug(self, ": unsubscribe(", subscription, ", ", func, " reqid:", id, ")")
	
	-- Remove from notify list
	if func then
		-- Remove only the given callback
		self.notify[subscription][func] = nil
	else
		-- Remove all callbacks
		self.notify[subscription] = nil
	end
	
	-- If we unsubscribed the last one for this subscription, clear it out
	if self.notify[subscription] then
		return
	end

	log:debug("No more callbacks for ", subscription, " unsubscribing at server")
		
	-- Remove from subs list
	for i, v in ipairs( self.subs ) do
		if v.subscription == subscription then
			table.remove( self.subs, i )
			break
		end
	end

	-- Add to pending unsubs
	table.insert(self.pending_unsubs, {
		reqid = id,
		subscription = subscription,
	} )

	-- Bump reqid for the next request
	self.reqid = id + 1

	-- Send immediately unless we're batching queries
	if self.state ~= CONNECTED or self.batch ~= 0 then
		return
	end

	-- Send all pending requests
	_sendPendingRequests(self)
end


function request(self, func, playerid, request, priority)
	local id = self.reqid

	if log:isDebug() then
		local _request = {}
		for i,v in ipairs(request) do
			_request[i] = tostring(v)
		end

		log:debug(self, ": request(", func, ", reqid:", id, ", ", playerid, ", ", table.concat(_request, ","), ", priority:", priority, ")")
	end

	-- Add to pending requests
	table.insert(self.pending_reqs, {
		reqid = id,
		func = func,
		playerid = playerid,
		request = request,
		priority = priority,
	})

	-- Bump reqid for the next request
	self.reqid = id + 1

	-- SlimServer.lua may think that we are reconnecting but actually we are not
	-- because we got reconnect advice of 'none' previously.
	-- But this request is likely user-initiated so we should try again now.
	if self.state == UNCONNECTED or self.state == UNCONNECTING then
		_reconnect(self)
	end

	-- Send immediately unless we're batching queries
	if self.state ~= CONNECTED or self.batch ~= 0 then
		if self.state ~= CONNECTED then
			self.jnt:notify('cometDisconnected', self, self.idleTimeoutTriggered)
			self.idleTimeoutTriggered = nil
		end

		return id
	end

	-- Send all pending requests
	_sendPendingRequests(self)

	return id
end


function addCallback(self, subscription, func)
	log:debug(self, ": addCallback(", subscription, ", ", func, ")")

	if not self.notify[subscription] then
		self.notify[subscription] = {}
	end
	
	self.notify[subscription][func] = func
end


function removeCallback(self, subscription, func)
	log:debug(self, ": removeCallback(", subscription, ", ", func, ")")
	
	self.notify[subscription][func] = nil
end


-- Begin a set of batched queries
function startBatch(self)
	log:debug(self, ": startBatch ", self.batch)

	self.batch = self.batch + 1
end


-- End batch mode, send all batched queries together
function endBatch(self)
	log:debug(self, ": endBatch ", self.batch)
	
	self.batch = self.batch - 1
	if self.batch ~= 0 then
		return
	end

	if self.state ~= CONNECTED then
		return
	end

	-- Send all pending requests and subscriptions
	_sendPendingRequests(self)
end


-- Notify changes in connection state
_state = function(self, state)
        if self.state == state then
		return
	end

	-- Stop reconnect timer
	self.reconnect_timer:stop()

	-- Set the state before the notifications, so any re-rentrant calls
	-- work correctly
	self.state = state
	log:debug(self, ": state is ", state)

	if state == CONNECTED then
		-- Reset error count
		self.failures = 0

		self.jnt:notify('cometConnected', self)

	elseif state == UNCONNECTED then
		-- Force connections closed
		self.chttp:close()
		self.rhttp:close()

		self.jnt:notify('cometDisconnected', self, self.idleTimeoutTriggered)
		self.idleTimeoutTriggered = nil

	end
end


_handshake = function(self)
	log:debug(self, ': _handshake(), calling: ', self.uri)

	assert(self.state == UNCONNECTED)

	if not self.isactive then
		log:info(self, ': _handshake() connection not active')
		return
	end

	-- Go through all existing subscriptions and reset the pending flag
	-- so they are re-subscribed to during _connect()
	for i, sub in ipairs( self.subs ) do
		log:debug("Will re-subscribe to ", sub.subscription, " id=", sub.reqid)
		sub.pending = true
		
		-- Also remove them from the set of requests waiting to be sent
		-- They will get readded later and we do not want duplicates
		for j, request in ipairs(self.sent_reqs) do
			if sub.reqid == request.id then
				table.remove( self.sent_reqs, j )
			end
		end
	end

	-- Reset clientId
	self.clientId  = nil

	local data = { {
		channel                  = '/meta/handshake',
		version                  = '1.0',
		supportedConnectionTypes = { 'streaming' },
		ext                      = {
			rev = JIVE_VERSION,
			uuid = System:getUUID(),
		},
	} }

	data[1].ext.mac = System:getMacAddress()

	-- XXX: according to the spec this should be sent as application/x-www-form-urlencoded
	-- with message=<url-encoded json> but it works as straight JSON

	_state(self, CONNECTING)

	local req = CometRequest(
			_getHandshakeSink(self),
			self.uri,
			data
		)

	self.chttp:fetch(req)
end


_getHandshakeSink = function(self)
	return function(chunk, err, cometRequest)
		if self.state ~= CONNECTING then
			return
		end

		-- On error, print something...
		if err then
			log:info(self, ": _handshake error: ", err)

			-- Try to reconnect according to advice
			return _handleAdvice(self, cometRequest)
		end

		-- If we have data
		if not chunk then
			return
		end

		local data = chunk[1]

		-- Update advice if any
		if data.advice then
			self.advice = data.advice
			log:debug(self, ": _handshake, advice updated from server")
		end

		if data.successful then
			self.clientId  = data.clientId
			self.advice    = data.advice

			log:debug(self, ": _handshake OK, clientId: ", self.clientId)

			-- Rewrite clientId in requests to be resent
			for i, req in ipairs(self.sent_reqs) do
				if req.data.response then
					req.data.response = string.gsub(req.data.response, "/([%xX]+)/", "/" .. self.clientId .. "/")
				end
			end


			-- Continue with connect phase, note we are still not CONNECTED
			_connect(self)
		else
			log:warn(self, ": _handshake error: ", data.error)
			return _handleAdvice(self)
		end
	end
end


_connect = function(self)
	log:debug(self, ': _connect()')
	
	-- Connect and subscribe to all events for this clientId
	local data = { {
		channel        = '/meta/connect',
		clientId       = self.clientId,
		connectionType = 'streaming',
	},
	{
		channel      = '/meta/subscribe',
		clientId     = self.clientId,
		subscription = '/' .. self.clientId .. '/**',
	} }

	-- This will be our last request on this connection, it is now only
	-- for listening for responses

	local req = CometRequest(
			_getEventSink(self),
			self.uri,
			data
		)
	
	self.chttp:fetch(req)
end


-- Reconnect to the server, try to maintain our previous clientId
_reconnect = function(self)
	log:debug(self, ': _reconnect(), calling: ', self.uri)

	assert(self.state == UNCONNECTED)

	if not self.isactive then
		log:info(self, ': _reconnect() connection not active')
		return
	end
	
	if not self.clientId then
		log:debug(self, ": _reconnect error: cannot reconnect without clientId, handshaking instead")
		return _handshake(self)
	end
	
	local data = { {
		channel        = '/meta/reconnect',
		clientId       = self.clientId,
		connectionType = 'streaming',
	},
	
	-- Need to include the /meta/subscribe here just in case the one from the 
	-- /meta/connect was lost (see _connect()) due to a network problem 
	{
		channel      = '/meta/subscribe',
		clientId     = self.clientId,
		subscription = '/' .. self.clientId .. '/**',
	} }

	_state(self, CONNECTING)
	
	local req = CometRequest(
			_getEventSink(self),
			self.uri,
			data
		)

	self.chttp:fetch(req)
end


_connected = function(self)
	local data = { }

	-- Add any un-acknowledged requests to the outgoing data
	for i, v in ipairs(self.sent_reqs) do
		table.insert(data, v)
	end

	_sendPendingRequests(self, data)
	_state(self, CONNECTED)
end


function _resetIdleTimer(self)
	if not self.idleTimeout or self.idleTimeout == 0 then
		return
	end

	if not self.idleTimer then
		self.idleTimer = Timer( 0,
					function()
						if self.state == CONNECTED then
							log:debug(self, " disconnect after idleTimeout: ", self.idleTimeout)
							self.idleTimeoutTriggered = true
							_disconnect(self)
						end
					end,
					true)
	end
	self.idleTimer:restart(self.idleTimeout * 1000)
end


-- if >0, disconnect from server idleTimeout seconds after the most recent request
function setIdleTimeout(self, idleTimeout)
	self.idleTimeout = idleTimeout

	if not idleTimeout or idleTimeout == 0 then
		if self.idleTimer then
			self.idleTimer:stop()
		end
	else
		-- >0 time, adjust timer
		self:_resetIdleTimer()
	end
end


-- sink for chunked connection, handle advice on error
_getEventSink = function(self)
	return function(chunk, err, cometRequest)
		-- On error, print something...
		if err then
			log:info(self, ": _getEventSink error: ", err)
			
			-- Try to reconnect according to advice
			return _handleAdvice(self, cometRequest)
		end

		_response(self, chunk)
	end
end


-- sink for request connection, resend requests on error
_getRequestSink = function(self)
	return function(chunk, err, cometRequest)
		-- On error, print something...
		if err then
			log:info(self, ": _getRequestSink error: ", err)
			return _handleAdvice(self, cometRequest)
		end

		-- if we have data
		if chunk then
			_response(self, chunk)
		end
	end
end

function removeRequest(self, requestId)
	if self.state == CONNECTED then
		log:warn("Can't remove sent request while connection is active. ", requestId)
		return false
	end

	--try both sent and pending, since request may have been sent prior to knowing server was down
	for i, request in ipairs( self.sent_reqs ) do
		if request.id == requestId then
			table.remove( self.sent_reqs, i )
			return true
		end
	end

	for i, request in ipairs( self.pending_reqs ) do
		if request.reqid == requestId then
			table.remove( self.pending_reqs, i )
			return true
		end
	end

	log:warn("request not found to remove, unexpected. ", requestId )
end


-- handle responses for both request and chunked connections
_response = function(self, chunk)
	-- If we have data
	if not chunk then
		return
	end

	-- Process each response event
	for i, event in ipairs(chunk) do

		-- Update advice if any
		if event.advice then
			self.advice = event.advice
			log:debug(self, ": _response, advice updated from server")
		end

		-- Log response
		if event.error then
			log:warn(self, ": _response, ", event.channel, " id=", event.id, " failed: ", event.error)
			if event.advice then
				return _handleAdvice(self)
			end
		else
			log:debug(self, ": _response, ", event.channel, " id=", event.id, " OK")
		end

		-- Remove request from sent queue
		for i, v in ipairs( self.sent_reqs ) do
			if v.id == tonumber(event.id) then
				table.remove( self.sent_reqs, i )
				break
			end
		end

		-- Handle response
		if event.channel == '/meta/connect' then
		 	if event.successful then
				_connected(self)
			else
				return _handleAdvice(self)
			end
		elseif event.channel == '/meta/disconnect' then
			if event.successful then
				-- we may have started CONNECTING again, ignore
				-- disconnects if we are in the wrong state
				if self.state == UNCONNECTING then
					self.clientId = nil
					_state(self, UNCONNECTED)
				end
			else
				return _handleAdvice(self)
			end
		elseif event.channel == '/meta/reconnect' then
			if event.successful then
				_connected(self)
			else
				return _handleAdvice(self)
			end
		elseif event.channel == '/meta/subscribe' then
			-- no action
		elseif event.channel == '/meta/unsubscribe' then
			-- no action
		elseif event.channel == '/slim/subscribe' then
			-- no action
		elseif event.channel == '/slim/unsubscribe' then
			-- no action
		elseif event.channel == '/slim/request' and event.successful then
			-- no action
		elseif event.channel then
			local subscription    = event.channel
			local onetime_request = false
					
			-- strip clientId from channel
			subscription = string.gsub(subscription, "^/[0-9A-Za-z]+", "")
				
			if string.find(subscription, '/slim/request') then
				-- an async notification from a normal request
				if not event.id then
					log:error("No id. event:")
					return
				end
				subscription = subscription .. '|' .. event.id
				onetime_request = true
			end

			if self.notify[subscription] then
				log:debug(self, ": _response, notifiying callbacks for ", subscription)
				
				for _, func in pairs( self.notify[subscription] ) do
					log:debug("  callback to: ", func)
					func(event)
				end
						
				if onetime_request then
					-- this was a one-time request, so remove the callback
					self.notify[subscription] = nil
				end
			else
				-- this is normal, since unsub's are delayed by a few seconds, we may receive events
				-- after we unsubscribed but before the server is notified about it
				log:debug(self, ": _response, got data for an event we aren't subscribed to, ignoring -> ", subscription)
			end
		else
			log:warn(self, ": _response, unknown error: ", event.error)
			return _handleAdvice(self)
		end
		
		-- If there are still sent requests for which we have not had responses, and we had an error
		-- response, then maybe some requests were lost by the server and we need to plan to resend them
		-- after a short timeout.
		
	end
end


_disconnect = function(self)
	assert(self.state == CONNECTED)

	log:debug(self, ': disconnect()')
		
	-- Mark all subs as pending so they can be resubscribed later
	for i, v in ipairs( self.subs ) do
		log:debug("Will re-subscribe to ", v.subscription, " on next connect")
		v.pending = true
	end

	-- As we are disconnecting we no longer care about waiting for
	-- a reply from the sent requests
	self.sent_reqs = {}

	local data = { {
		channel  = '/meta/disconnect',
		clientId = self.clientId,
	} }

	_state(self, UNCONNECTING)

	local req = CometRequest(
		_getRequestSink(self),
		self.uri,
		data
	)

	self.rhttp:fetch(req)
end


-- Decide what to do if we get disconnected or get an error while handshaking/connecting
_handleAdvice = function(self, cometRequest)
	log:info(self, ": handleAdvice state=", self.state)

	if self.state == UNCONNECTED then
		-- do nothing 
		return
	end

	-- FIXME can handle HTTP errors here

	-- HTTP authorization failure?
	if cometRequest and cometRequest:t_getResponseStatus() == 401 then
		self.jnt:notify('cometHttpError', self, cometRequest)
		-- keep trying to connect
	end

	-- force connection closed
	_state(self, UNCONNECTED)

	self.failures = self.failures + 1
	local reconnect = self.advice.reconnect or "retry"
	local retry_interval = tonumber(self.advice.interval) or RETRY_DEFAULT

	if retry_interval == 0 then
		-- Retry immediately
	elseif self.aggressive then
		-- Retry using a random interval between 1 - advice.interval seconds
		retry_interval = math.random(1000, retry_interval)
	else
		-- Keep retrying after multiple failures but backoff gracefully
		retry_interval = retry_interval * self.failures

		if retry_interval > MAX_BACKOFF then
			retry_interval = MAX_BACKOFF
		end
	end
	
	if reconnect == 'none' then
		self.clientId  = nil
		log:info(self, ": advice is ", reconnect, " server told us not to reconnect")

	else
		log:info(self, ": advice is ", reconnect, ", connect in ",
			 retry_interval / 1000, " seconds")
	
		self.reconnect_timer:restart(retry_interval)	
	end
end


_handleTimer = function(self)
	log:debug(self, ": handleTimer state=", self.state, " advice=", self.advice)

	if self.state ~= UNCONNECTED then
		log:debug(self, ": ignoring timer while ", self.state)
		return
	end

	local reconnect = self.advice.reconnect or "retry"

	if reconnect == 'handshake' then
		_handshake(self)

	elseif reconnect == 'retry' then
		_reconnect(self)

	end
end


function __tostring(self)
	return "Comet {" .. self.name .. "}"
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]
