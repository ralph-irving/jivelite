--[[
=head1 NAME

jive.net.SocketTcpServer - A TCP server socket for accepting client connections

=head1 DESCRIPTION

Implements a tcp socket to accept client connections.

(c) Adrian Smith, 2013

=head1 SYNOPSIS

 local listener = SocketTcpServer(jnt, "localhost", "9006", "listener sock")
 listener:t_addRead(function()
						local newsock = listener:t_accept()
						local pump = function()
										 -- do something 
									 end
						newsock:t_addRead(pump)
					end
	)

=cut
--]]

local _assert, tostring = _assert, tostring

local socket   = require("socket")
local oo       = require("loop.simple")

local Socket   = require("jive.net.Socket")
local SocketTcp= require("jive.net.SocketTcp")

local log      = require("jive.utils.log").logger("net.http")


module(...)
oo.class(_M, Socket)


function __init(self, jnt, address, port, name)
	log:debug("SocketTcp:__init(", name, ", ", address, ", ", port, ")")

	_assert(address, "Cannot create SocketTcpServer without hostname/ip address - " .. debug.traceback())
	_assert(port, "Cannot create SocketTcpServer without port")

	local obj = oo.rawnew(self, Socket(jnt, name))

	obj.t_tcp = {
		address = address,
		port = port,
	}

	obj.connection = 0
	obj.jnt = jnt

	local sock = socket.tcp()

	local err = socket.skip(1, sock:bind(address, port))
	if err == nil then
		err = socket.skip(1, sock:listen(10))
	end

	if err then
		log:warn(err)
		return nil
	end

	sock:settimeout(1)
		
	obj.t_sock = sock

	return obj
end


function t_accept(self)
	local newsock, err = self.t_sock:accept()
	if newsock == nil or err then
		if err then
			log:warn(err)
		end
		return nil, err
	end

	self.connection = self.connection + 1

	local sockTcp = SocketTcp(self.jnt, "unknown", "unknown", self.jsName .. " [connection #" .. self.connection .. "]")
	sockTcp.t_sock = newsock
	sockTcp:t_setConnected(true)

	return sockTcp
end


function t_addRead(self, pump)
	-- wrap this so timeout is never set
	Socket.t_addRead(self, pump, 0)
end