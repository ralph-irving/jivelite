
--[[
=head1 NAME

jive.net.HttpPool - Manages a set of HTTP sockets.

=head1 DESCRIPTION

This class manages 2 queues of a requests, processed using a number
of HTTP sockets (see L<jive.net.SocketHttp>). The sockets are opened
dynamically as the queue size grows, and are closed once all requests
have been serviced.

=head1 SYNOPSIS

 -- create a pool for http://192.168.1.1:9000
 -- with a max of 4 connections, threshold of 2 requests
 local pool = HttpPool(jnt, "192.168.1.1", 9000, 4, 2, 'slimserver'),

 -- queue a request
 pool:queue(aRequest)


=head1 FUNCTIONS

=cut
--]]
-----------------------------------------------------------------------------
-- Convention: functions/methods starting with t_ are executed in the thread
-----------------------------------------------------------------------------


-- stuff we use
local _assert, ipairs, tostring, type = _assert, ipairs, tostring, type

local table           = require("table")
local math            = require("math")

local oo              = require("loop.base")

local SocketHttpQueue = require("jive.net.SocketHttpQueue")
local Timer           = require("jive.ui.Timer")

local log             = require("jive.utils.log").logger("net.http")

local KEEPALIVE_TIMEOUT = 60000 -- timeout idle connections after 60 seconds

-- jive.net.HttpPool is a base class
module(..., oo.class)


--[[

=head2 jive.net.HttpPool(jnt, name, ip, port, quantity, threshold, priority)

Creates an HTTP pool named I<name> to interface with the given I<jnt> 
(a L<jive.net.NetworkThread> instance). I<name> is used for debugging and
defaults to "". I<ip> and I<port> are the IP address and port of the HTTP server.

I<quantity> is the maximum number of connections to open, depending on
the number of requests waiting for service. This is controlled using the
I<threshold> parameter which indicates the ratio of requests to connections.
For example, if I<threshold> is 2, a single connection is used until 2 requests
are pending, at which point a second connection is used. A third connection
will be opened as soon as the number of queued requests reaches 6.
I<priority> identifies the pool for processing at lower priority.

=cut
--]]
function __init(self, jnt, name, ip, port, quantity, threshold, priority)
--	log:debug("HttpPool:__init(", name, ", ", ip, ", ", port, ", ", quantity, ")")

	-- let used classes worry about ip, port existence
--	_assert(jnt)
	
	local obj = oo.rawnew(self, {
		jnt           = jnt,
		poolName      = name or "",
		pool          = {
			active    = 1,
			threshold = threshold or 10,
			jshq      = {}
		},
		reqQueue      = {},
		reqQueueCount = 0,
		timeout_timer = nil,
	})
	
	
	-- init the pool
	local q = quantity or 1
	for i = 1, q do
		obj.pool.jshq[i] = SocketHttpQueue(jnt, ip, port, obj, obj.poolName .. i)
		obj.pool.jshq[i]:setPriority(priority)
	end
	
	return obj
end


--[[

=head2 jive.net.HttpPool:free()

Frees the pool, close and free all connections.

=cut
--]]
function free(self)
	for i=1,#self.pool.jshq do
		self.pool.jshq[i]:free()
		self.pool.jshq[i] = nil
	end
end


--[[

=head2 jive.net.HttpPool:close()

Close all connects to the server.

=cut
--]]
function close(self)
	for i=1,#self.pool.jshq do
		self.pool.jshq[i]:close()
	end
end


--[[

=head2 jive.net.HttpPool:queue(request)

Queues I<request>, a L<jive.net.RequestHttp> instance. All previously
queued requests will be serviced before this one.

=cut
--]]
function queue(self, request)
--	log:warn(self, " enqueues ", request)

	table.insert(self.reqQueue, request)
	self.reqQueueCount = self.reqQueueCount + 1
	
	-- calculate threshold
--[[
	local active = math.floor(self.reqQueueCount / self.pool.threshold) + 1
	if active > #self.pool.jshq then
		active = #self.pool.jshq
	end
	self.pool.active = active
--]]
	self.pool.active = #self.pool.jshq


--	log:debug(self, ":", self.reqQueueCount, " requests, ", self.pool.active, " connections")

	-- kick all active queues
	for i = 1, self.pool.active do
		self.pool.jshq[i]:t_sendDequeueIfIdle()
	end
end


-- t_dequeue
-- returns a request if there is any
-- called by SocketHttpQueue
function t_dequeue(self, socket)
--	log:debug(self, ":t_dequeue()")
		
	local request = table.remove(self.reqQueue, 1)
	if request then
		if type(request) == "function" then
			request = request()
		end

		self.reqQueueCount = self.reqQueueCount - 1
--		log:warn(self, " dequeues ", request)
			
		if self.timeout_timer then
			self.timeout_timer:stop()
			self.timeout_timer = nil
		end
			
		return request, false
	end
	
	self.reqQueueCount = 0
	
	-- close the first connection after a timeout expires
	if not self.timeout_timer then
		self.timeout_timer = Timer(
			KEEPALIVE_TIMEOUT,
			function()
				log:debug(self, ": closing idle connection")
				for i = 1, self.pool.active do
					self.pool.jshq[1]:close('keep-alive timeout')
				end
			end,
			true -- run once
		)
		self.timeout_timer:start()
	end			

	-- close all but the first one (active = 1)
	return nil, false
end


--[[

=head2 tostring(aPool)

if I<aPool> is a L<jive.net.HttpPool>, prints
 HttpPool {name}

=cut
--]]
function __tostring(self)
	return "HttpPool {" .. tostring(self.poolName) .. "}"
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

