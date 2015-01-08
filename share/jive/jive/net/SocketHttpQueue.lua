
--[[
=head1 NAME

jive.net.SocketHttpQueue - A SocketHttp that uses an external queue

=head1 DESCRIPTION

jive.net.SocketHttpQueue is a subclass of L<jive.net.SocketHttp> designed
to use an external request queue, such as the one proposed by L<jive.net.HttpPool>.

=head1 SYNOPSIS

None provided.

=head1 FUNCTIONS

=cut
--]]
-----------------------------------------------------------------------------
-- Convention: functions/methods starting with t_ are executed in the thread
-----------------------------------------------------------------------------


-- stuff we use
local _assert, tostring = _assert, tostring

local oo         = require("loop.simple")

local SocketHttp = require("jive.net.SocketHttp")

local log        = require("jive.utils.log").logger("net.http")


-- jive.net.SocketHttpQueue is a subclass of jive.net.SocketHttp
module(...)
oo.class(_M, SocketHttp)


--[[

=head2 jive.net.SocketHttpQueue(jnt, address, port, queueObj, name)

Same as L<jive.net.SocketHttp>, save for the I<queueObj> parameter
which must refer to an object implementing a B<t_dequeue> function
that returns a request from its queue and a boolean indicating if
the connection must close.

=cut
--]]
function __init(self, jnt, address, port, queueObj, name)
--	log:debug("SocketHttpQueue:__init(", name, ", ".. address, ", ", port, ")")

--	_assert(queueObj)

	-- init superclass
	local obj = oo.rawnew(self, SocketHttp(jnt, address, port, name))

	obj.httpqueue = queueObj
	
	return obj
end


-- _dequeueRequest
--
function _dequeueRequest(self)
--	log:debug(self, ":_dequeueRequest()")
	
	local request, close = self.httpqueue:t_dequeue(self)
	
	if request then
		return request
	end
	
	if close then
		self:close()
	end

	return nil
end


--[[

=head2 tostring(aSocket)

if I<aSocket> is a L<jive.net.SocketHttpQueue>, prints
 SocketHttpQueue {name}

=cut
--]]
function __tostring(self)
	return "SocketHttpQueue {" .. tostring(self.jsName) .. "}"
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

