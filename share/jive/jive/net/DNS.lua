--[[
=head1 NAME

jive.net.DNS - non-blocking dns queries.

=head1 DESCRIPTION

Implements non-block dns queries using the same api a luasocket. These
functions must be called in a Task.

--]]


local assert = assert

local oo          = require("loop.base")
local table       = require("table")
local string      = require("string")

local Framework   = require("jive.ui.Framework")
local Task        = require("jive.ui.Task")

local debug       = require("jive.utils.debug")
local log         = require("jive.utils.log").logger("net.socket")

local jive_dns    = require("jive.dns")


-- jive.net.DNS is a base class
module(..., oo.class)


-- singleton instance
local _instance = false


function __init(self, jnt)
	if _instance then
		return _instance
	end

	local obj = oo.rawnew(self, {})
	obj.sock = jive_dns:open()
	obj.dnsQueue = {}

	jnt:t_addRead(obj.sock,
		Task("DNS",
		     obj,
		     function()
			     while true do
				     Task:yield(false)

				     -- read host entry
				     local hostent, err = obj.sock:read()

				     -- wake up requesting task
				     local task = table.remove(obj.dnsQueue, 1)
				     if task then
					     task:addTask(hostent, err)
				     end
			     end
		     end),
		0) -- no timeout

	_instance = obj
	return obj
end


function isip(self, address)
	-- XXXX crude check
	return string.match(address, "%d+%.%d+%.%d+%.%d+")
end


-- Converts from IP address to host name. See socket.dns.tohostname.
function tohostname(self, address)
	local task = Task:running()
	assert(task, "DNS:tohostname must be called in a Task")

	-- queue request
	_instance.sock:write(address)

	-- wait for reply
	table.insert(_instance.dnsQueue, task)
	local _, hostent, err = Task:yield(false)

	if err then
		return nil, err
	else
		return hostent.name, hostent
	end
end


-- Coverts from host name to IP address. See socket.dns.toip.
function toip(self, address)
	local task = Task:running()
	assert(task, "DNS:toip must be called in a Task")

	-- queue request
	_instance.sock:write(address)

	-- wait for reply
	table.insert(_instance.dnsQueue, task)
	local _, hostent, err = Task:yield(false)

	if err then
		return nil, err
	else
		return hostent.ip[1], hostent
	end
end

