
--[[
=head1 NAME

jive.net.SocketUdp - A socket for UDP.

=head1 DESCRIPTION

Implements a socket that sends udp packets and returns packets
obtained in response. This is used to discover slimservers on the network.
jive.net.SocketUdb is a subclass of L<jive.net.Socket> to be used with a
L<jive.net.NetworkSocket>.

Note the implementation uses the source and sink concept of luasocket.

=head1 SYNOPSIS

 -- create a source to send some data
 local function mySource()
   return "Hello"
 end

 -- create a sink to receive data from the network
 local function mySink(chunk, err)
   if err then
     print("error!: " .. err)
   elseif chunk then
     print("received: " .. chunk.data .. " from " .. chunk.ip)
   end
 end

 -- create a SocketUdp
 local mySocket = jive.net.SocketUdp(jnt, mySink)

 -- send some data to address 10.0.0.1 on port 3333
 mySocket:send(mySource, "10.0.0.1", 3333)

=head1 FUNCTIONS

=cut
--]]
-----------------------------------------------------------------------------
-- Convention: functions/methods starting with t_ are executed in the thread
-----------------------------------------------------------------------------


-- stuff we use
local _assert, tostring = _assert, tostring

local socket  = require("socket")
local table   = require("table")
local ltn12   = require("ltn12")
local oo      = require("loop.simple")
local coroutine = require("coroutine")

local string  = require("jive.utils.string")
local Socket  = require("jive.net.Socket")

local log     = require("jive.utils.log").logger("net.socket")

-- jive.net.SocketUdp is a subclass of jive.net.Socket
module(...)
oo.class(_M, Socket)


-- _createUdpSocket
-- creates our socket safely
local _createUdpSocket = socket.protect(function(localport)
	--log:debug("_createUdpSocket()")
	
	-- Make sure that we end up with an IPv4 UDP.
	local sock
	if socket.udp4~=nil then
		sock = socket.try(socket.udp4())
	else
		sock = socket.try(socket.udp())
	end

	-- create a try function that closes 'c' on error
    local try = socket.newtry(function() sock:close() end)
    -- do everything reassured c will be closed
	try(sock:setoption("broadcast", true))
	try(sock:settimeout(0))
	
	if localport then
		try(sock:setsockname( '*', localport))
	end	

	return sock
end)


--[[

=head2 jive.net.SocketUdp(jnt, sink, name)

Creates a UDP socket named I<name> to interface with the given I<jnt> 
(a L<jive.net.NetworkThread> instance). I<name> is used for debugging and
defaults to "". I<sink> is the main thread ltn12 sink that will receive the data.
Must be called by subclasses.

The sink receives chunks that are tables. NIL is never sent as the network source
cannot determine the "end" of the stream. The table contains the following members:
=over

B<data> : the data.

B<ip> : the source ip address.

B<port> : the source port


=cut
--]]
function __init(self, jnt, sink, name, localport)
	--log:debug("SocketUdp:__init()")

--	_assert(sink)
	
	-- init superclass
	local obj = oo.rawnew(self, Socket(jnt, name))

	-- create a udp socket
	local sock, err = _createUdpSocket( localport)
	
	if err then
		log:error(err)
	else
	
		-- save the socket, we might need it later :)
		obj.t_sock = sock
		obj.queue = {}
		
		-- add our read function (thread side)
		obj:t_addRead(obj:t_getReadPump(sink), 0)
	end
	
	return obj
end


-- t_getReadPump
-- returns a pump to read udp data using the read sources/sinks
function t_getReadPump(self, sink)

	-- a ltn12 source that reads from a udp socket, including the source address
	-- NOTE: this source produces chunks as tables and cannot be generally chained
	local source = function()
		local dgram, ssIp, ssPort = self.t_sock:receivefrom()

		if dgram ~= nil then
			return {ip = ssIp, port = ssPort, data = dgram}
		else
			-- error in ssIp
			return nil, ssIp
		end
	end

	return function(NetworkThreadErr)
		--log:debug("SocketUdp:readPump()")

		if NetworkThreadErr then
			log:error("SocketUdp:readPump() error:", NetworkThreadErr)
			return
		end

		local err = socket.skip(1, ltn12.pump.step(source, sink))

		if err then
			-- do something
			log:error("SocketUdp:readPump:", err)
		end
	end
end


-- t_getSink
-- returns a sink to write out udp data.
function t_getSink(self, address, port)

	-- a ltn12 sink than sends udp bcast datagrams
	return function(chunk, err)
		if chunk and chunk ~= "" then
			return self.t_sock:sendto(chunk, address, port)
		else
			return 1
		end
	end
end


-- t_getWritePump
-- returns a pump to write out udp data. It removes itself when the 
-- queue is empty after each pump
function t_getWritePump(self, t_source)

	return function(NetworkThreadErr)
		--log:debug("SocketUdp:writePump()")
		
		if NetworkThreadErr then
			log:error("SocketUdp:writePump() error:", NetworkThreadErr)
			-- let it run, we'll return below after removing ourselves...
		end

		local sink = table.remove(self.queue, 1)

		-- stop the pumping when queue is empty
		if sink == nil then
			self:t_removeWrite()
			return
		end

		-- pump data once
		local err = socket.skip(1, ltn12.pump.step(t_source, sink))
		
		if err then
			log:warn("SocketUdp:writePump:", err)
		end
	end
end


--[[

=head2 jive.net.SocketUdp:send(t_source, address, port)

Sends the data obtained through I<t_source> to the 
given I<address> and I<port>. I<t_source> is a ltn12 source called from 
the network thread.

=cut
--]]
function send(self, t_source, address, port)
	--log:debug("SocketUdp:send()")

--	_assert(t_source)
--	_assert(address)
--	_assert(port)

	if self.t_sock then
		if #self.queue == 0 then
			self:t_addWrite(self:t_getWritePump(t_source), 60)
		end
		table.insert(self.queue, self:t_getSink(address, port))
	end
end


--[[

=head2 tostring(aSocket)

if I<aSocket> is a L<jive.net.SocketUdp>, prints
 SocketUdp {name}

=cut
--]]
function __tostring(self)
	return "SocketUdp {" .. tostring(self.jsName) .. "}"
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

