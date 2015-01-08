
--[[
=head1 NAME

jive.net.Socket - An abstract socket that sends/receives data using a NetworkThread.

=head1 DESCRIPTION

An abstract socket that sends/receives data using a NetworkThread. It proposes
services to close/free sockets and interface with the main thread, along with 
convenient proxy functions.

=head1 SYNOPSIS

 -- jive.net.Socket is abstract so this is not a useful example
 local mySocket = Socket(jnt, "mySocket")

 -- information about the socket
 log:debug("Freeing: ", mySocket)
 -- print
 Freeing: Socket {mySocket}

 -- free the socket
 mySocket:free()


=head1 FUNCTIONS

=cut
--]]
-----------------------------------------------------------------------------
-- Convention: functions/methods starting with t_ are executed in the thread
-----------------------------------------------------------------------------


-- stuff we use
local tostring, _assert = tostring, _assert

local oo            = require("loop.base")

local NetworkThread = require("jive.net.NetworkThread")
local Task          = require("jive.ui.Task")

local log           = require("jive.utils.log").logger("net.socket")


-- jive.net.Socket is a base class
module(..., oo.class)


--[[

=head2 jive.net.Socket(jnt, name)

Creates a socket named I<name> to interface with the given I<jnt> 
(a L<jive.net.NetworkThread> instance). I<name> is used for debugging and
defaults to "".
Must be called by subclasses.

=cut
--]]
function __init(self, jnt, name)
--	log:debug("Socket:__init(", name, ")")

--	_assert(
--		jnt and oo.instanceof(jnt, NetworkThread), 
--		"Cannot create Socket without NetworkThread object"
--	)

	return oo.rawnew(self, {
		jnt = jnt,
		jsName = name or "",
		t_sock = false
	})
end


-- free
-- frees (and closes) the socket
function free(self)
--	log:debug(self, ":free()")

	-- we store nothing so closing is all we need
	self:close()
end


-- close
-- closes the socket
function close(self)
--	log:debug(self, ":close()")

	if self.t_sock then
		self:t_removeRead()
		self:t_removeWrite()
		self.t_sock:close()
		self.t_sock = nil

		self:socketInactive()
	end
end


--[[

=head2 setPriority(priority)

Sets the socket priority.

--]]
function setPriority(self, priority)
	self.priority = priority
end


function socketActive(self)
	if not self.active then
		self.active = true
		self.jnt:networkActive(self)
	end
end


function socketInactive(self)
	if self.active then
		self.active = false
		self.jnt:networkInactive(self)
	end
end



--[[

=head2 tostring(aSocket)

if I<aSocket> is a L<jive.net.Socket>, prints
 Socket {name}

=cut
--]]
function __tostring(self)
	return "Socket {" .. tostring(self.jsName) .. "}"
end


-- Proxy functions for NetworkThread, for convenience of subclasses

local function _taskError(self)
	self:close("task error")
end


-- t_add/remove/read/write
function t_addRead(self, pump, timeout)
	-- task to iterate over all read pumps
	local task = Task(tostring(self) .. "(R)",
			  self,
			  function(self, networkErr)
				  while self.readPump do
					  if not self.readPump(networkErr) then
						  self, networkErr = Task:yield(false)
					  end
				  end
			  end,
			  _taskError,
			  self.priority)

	self.readPump = pump
	self.jnt:t_addRead(self.t_sock, task, timeout)
end

function t_removeRead(self)
	if self.readPump then
		self.readPump = nil
		self.jnt:t_removeRead(self.t_sock)
	end
end

function t_addWrite(self, pump, timeout)
	-- task to iterate over all write pumps
	local task = Task(tostring(self) .. "(W)",
			  self,
			  function(self, networkErr)
				  while self.writePump do
					  if not self.writePump(networkErr) then
						  self, networkErr = Task:yield(false)
					  end
				  end
			  end,
			  _taskError,
			  self.priority)

	self.writePump = pump
	self.jnt:t_addWrite(self.t_sock, task, timeout)
end

function t_removeWrite(self)
	if self.writePump then
		self.writePump = nil
		self.jnt:t_removeWrite(self.t_sock)
	end
end



--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

