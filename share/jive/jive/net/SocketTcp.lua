
--[[
=head1 NAME

jive.net.SocketTcp - A TCP socket to send/recieve data using a NetworkThread

=head1 DESCRIPTION

Implements a tcp socket that sends/receive data using a NetworkThread. 
jive.net.SocketTcp is a subclass of L<jive.net.Socket> and therefore inherits
its methods.
This class is mainly designed as a superclass for L<jive.net.SocketHttp> and
therefore is not fully useful as is.

=head1 SYNOPSIS

 -- create a jive.net.SocketTcp
 local mySocket = jive.net.SocketTcp(jnt, "192.168.1.1", 9090, "cli")

 -- print the connected state
 if mySocket:connected() then
   print(tostring(mySocket) .. " is connected")
 end

=head1 FUNCTIONS

=cut
--]]
-----------------------------------------------------------------------------
-- Convention: functions/methods starting with t_ are executed in the thread
-----------------------------------------------------------------------------


-- stuff we use
local _assert, tostring = _assert, tostring

local debug    = require("debug")

local socket   = require("socket")
local oo       = require("loop.simple")

local Socket   = require("jive.net.Socket")

local log      = require("jive.utils.log").logger("net.http")


-- jive.net.SocketTcp is a subclass of jive.net.Socket
module(...)
oo.class(_M, Socket)


--[[

=head2 jive.net.SocketTcp(jnt, address, port, name)

Creates a TCP/IP socket named I<name> to interface with the given I<jnt> 
(a L<jive.net.NetworkThread> instance). I<name> is used for debugging and
defaults to "". I<address> and I<port> are the hostname/IP address and port to 
send/receive data from/to.
Must be called by subclasses.

=cut
--]]
function __init(self, jnt, address, port, name)
	--log:debug("SocketTcp:__init(", name, ", ", address, ", ", port, ")")

	_assert(address, "Cannot create SocketTcp without hostname/ip address - " .. debug.traceback())
	_assert(port, "Cannot create SocketTcp without port")

	local obj = oo.rawnew(self, Socket(jnt, name))

	obj.t_tcp = {
		address = address,
		port = port,
		connected = false,
	}

	return obj
end


-- t_connect
-- connects our socket
function t_connect(self)
	--log:debug(self, ":t_connect()")
	
	-- create a tcp socket
	self.t_sock = socket.tcp()

	-- set a long timeout for connection
	self.t_sock:settimeout(0)
	local err = socket.skip(1, self.t_sock:connect(self.t_tcp.address, self.t_tcp.port))

	if err and err ~= "timeout" then
	
		log:error("SocketTcp:t_connect: ", err)
		return nil, err
	
	end
	
	return 1
end


-- t_setConnected
-- changes the connected state. Mutexed because main thread clients might care about this status
function t_setConnected(self, state)
	--log:debug(self, ":t_setConnected(", state, ")")

	local stcp = self.t_tcp

	if state ~= stcp.connected then
		stcp.connected = state
	end
end


-- t_getConnected
-- returns the connected state, network thread side (i.e. safe, no mutex)
function t_getConnected(self)
	return self.t_tcp.connected
end


-- free
-- frees our socket
function free(self)
	--log:debug(self, ":free()")
	
	-- we store nothing, just call superclass
	Socket.free(self)
end


-- close
-- closes our socket
function close(self)
	--log:debug(self, ":close()")
	
	self:t_setConnected(false)
	
	Socket.close(self)
end


-- t_getIpPort
-- returns the Address and port
function t_getAddressPort(self)
	return self.t_tcp.address, self.t_tcp.port
end


--[[

=head2 jive.net.SocketTcp:connected()

Returns the connected state of the socket. This is mutexed
to enable querying the state from the main thread while operations
on the socket occur network thread-side.

=cut
--]]
function connected(self)

	local connected = self.t_tcp.connected
	
	--log:debug(self, ":connected() = ", connected)
	return connected
end


--[[

=head2 tostring(aSocket)

if I<aSocket> is a L<jive.net.SocketTcp>, prints
 SocketTcp {name}

=cut
--]]
function __tostring(self)
	return "SocketTcp {" .. tostring(self.jsName) .. "}"
end


-- Overrides to manage connected state

-- t_add/read/write
function t_addRead(self, pump, timeout)
	local newpump = function(...)
		if not self.t_tcp.connected then self:t_setConnected(true) end
		pump(...)
	end
	Socket.t_addRead(self, newpump, timeout)
end

function t_addWrite(self, pump, timeout)
	local newpump = function(...)
		if not self.t_tcp.connected then self:t_setConnected(true) end
		pump(...)
	end
	Socket.t_addWrite(self, newpump, timeout)
end

--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

