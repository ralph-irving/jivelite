
--[[
=head1 NAME

jive.net.NetworkThread - thread for network IO

=head1 DESCRIPTION

Implements a separate thread (using luathread) for network functions. The base class for network protocols is Socket. Messaging from/to the thread uses mutexed queues. The queues contain functions executed once they leave the queue in the respective thread.
The network thread queue is polled repeatedly. The main thread queue shall serviced by the main code; currently, an event EVENT_SERVICE_JNT exists for this purpose.

FIXME: Subscribe description

=head1 SYNOPSIS

 -- Create a NetworkThread (done for you in JiveMain stored in global jnt)
 jnt = NetworkThread()

 -- Create an HTTP socket that uses this jnt
 local http = SocketHttp(jnt, '192.168.1.1', 80)

=head1 FUNCTIONS

=cut
--]]
-----------------------------------------------------------------------------
-- Convention: functions/methods starting with t_ are executed in the thread
-----------------------------------------------------------------------------


-- stuff we use
local _assert, next, tostring, table, ipairs, pairs, pcall, select, setmetatable, type  = _assert, next, tostring, table, ipairs, pairs, pcall, select, setmetatable, type

local io                = require("io")
local os                = require("os")
local socket            = require("socket")
local string            = require("jive.utils.string")
local table             = require("jive.utils.table")
local debug             = require("jive.utils.debug")
local oo                = require("loop.base")

local System            = require("jive.System")
local Event             = require("jive.ui.Event")
local Framework         = require("jive.ui.Framework")
local Task              = require("jive.ui.Task")
local DNS               = require("jive.net.DNS")
local Process           = require("jive.net.Process")

local debug             = require("jive.utils.debug")
local log               = require("jive.utils.log").logger("net.thread")

local perfhook          = jive.perfhook

local EVENT_SERVICE_JNT = jive.ui.EVENT_SERVICE_JNT
local EVENT_CONSUME     = jive.ui.EVENT_CONSUME

--allow for not making arp calls
local _isArpEnabled = true

-- jive.net.NetworkThread is a base class
module(..., oo.class)

local squeezenetworkHostname = "www.squeezenetwork.com"


-- _add
-- adds a socket to the read or write list
-- timeout == 0 => no time out!
local function _add(sock, task, sockList, timeout)
	if not sock then 
		return
	end

	if not sockList[sock] then
		-- add us if we're not already in there
		table.insert(sockList, sock)

		sockList[sock] = {
			lastSeen = Framework:getTicks()
		}
	elseif sockList[sock].task and sockList[sock].task ~= task then
		-- else remove previous task if different
		sockList[sock].task:removeTask()
	end	

	-- remember the pump, the time and the desired timeout
	sockList[sock].task = task
	sockList[sock].timeout = (timeout or 60) * 1000
end


-- _remove
-- removes a socket from the read or write list
local function _remove(sock, sockList)
	if not sock then 
		return 
	end

	-- remove the socket from the sockList
	if sockList[sock] then
		sockList[sock].task:removeTask()
		
		sockList[sock] = nil
		table.delete(sockList, sock)
	end
end


-- t_add/remove/read/write
-- add/remove sockets api
function t_addRead(self, sock, task, timeout)
--	log:warn("NetworkThread:t_addRead()", sock)

	_add(sock, task, self.t_readSocks, timeout)
end

function t_removeRead(self, sock)
--	log:warn("NetworkThread:t_removeRead()", sock)
	
	_remove(sock, self.t_readSocks)
end

function t_addWrite(self, sock, task, timeout)
--	log:warn("NetworkThread:t_addWrite()", sock)
	
	_add(sock, task, self.t_writeSocks, timeout)
end

function t_removeWrite(self, sock)
--	log:warn("NetworkThread:t_removeWrite()", sock)
	
	_remove(sock, self.t_writeSocks)
end


-- _timeout
-- manages the timeout of our sockets
local function _timeout(now, sockList)
--	log:debug("NetworkThread:_timeout()")

	for v, t in pairs(sockList) do
		-- the sockList contains both sockList[i] = sock and sockList[sock] = {pumpIt=,lastSeem=}
		-- we want the second case, the sock is a userdata (implemented by LuaSocket)
		-- we also want the timeout to exist and have expired
		if type(v) == "userdata" and t.timeout > 0 and now - t.lastSeen > t.timeout then
			log:warn("network thread timeout for ", t.task)
			t.task:addTask("inactivity timeout")
		end
	end
end


-- _t_select
-- runs our sockets through select
local function _t_select(self, timeout)
--	log:debug("_t_select(r", #self.t_readSocks, " w", #self.t_writeSocks, ")")

	local r,w,e = socket.select(self.t_readSocks, self.t_writeSocks, timeout)

	local now = Framework:getTicks()
		
	if e then
		-- timeout is a normal error for select if there's nothing to do!
		if e ~= 'timeout' then
			log:error(e)
		end

	else
		-- call the write pumps
		for i,v in ipairs(w) do
			self.t_writeSocks[v].lastSeen = now
			if not self.t_writeSocks[v].task:addTask() then
				_remove(v, self.t_writeSocks)
			end
		end
		
		-- call the read pumps
		for i,v in ipairs(r) do
			self.t_readSocks[v].lastSeen = now
			if not self.t_readSocks[v].task:addTask() then
				_remove(v, self.t_readSocks)
			end
		end
	end

	-- manage timeouts
	_timeout(now, self.t_readSocks)
	_timeout(now, self.t_writeSocks)
end


-- _thread
-- the thread function with the endless loop
local function _run(self, timeout)
	local ok, err

	log:debug("NetworkThread starting...")

	while true do
		local timeoutSecs = timeout / 1000
		if timeoutSecs < 0 then
			timeoutSecs = 0
		end

		ok, err = pcall(_t_select, self, timeoutSecs)
		if not ok then
			log:error("error in _t_select: " .. err)
		end

		_, timeout = Task:yield(true)
	end
end


function task(self)
	return Task("networkTask", self, _run)
end


function t_perform(self, func, priority)
	-- XXXX deprecated
	log:error("t_perform: ", debug.traceback())
end
function perform(self, func)
	-- XXXX deprecated
	log:error("perform: ", debug.traceback())
end


-- add/remove subscriber
function subscribe(self, object)
--	log:debug("NetworkThread:subscribe()")
	
	if not self.subscribers[object] then
		self.subscribers[object] = 1
	end
end


function unsubscribe(self, object)
--	log:debug("NetworkThread:unsubscribe()")
	
	if self.subscribers[object] then
		self.subscribers[object] = nil
	end
end


-- notify
function notify(self, event, ...)
	-- detailed logging for events
	local a = {}
	for i=1, select('#', ...) do
		a[i] = tostring(select(i, ...))
	end
	log:debug("NOTIFY: ", event, "(", table.concat(a, ", "), ")")
	
	local method = "notify_" .. event
	
	for k,v in pairs(self.subscribers) do
		if k[method] and type(k[method]) == 'function' then
        		local ok, resOrErr = pcall(k[method], k, ...)
	        	if not ok then
				log:error("Error running ", method, ":", resOrErr)
			else
				if k._entry and k._entry.appletName then
					log:debug(method, ' sent to ', k._entry.appletName)
				end
			end
		end
        end
end


-- Called by the network layer when the network is active
function networkActive(self, obj)
	self.networkActiveCount[obj] = 1

	local isempty = next(self.networkActiveCount)

	if isempty and not self.networkIsActive then
		if self.networkActiveCallback then
			self.networkActiveCallback(true)
		end

		self.networkIsActive = true
	end
end


-- Called by the network layer when the network is inactive
function networkInactive(self, obj)
	self.networkActiveCount[obj] = nil

	local isempty = next(self.networkActiveCount)

	if not isempty and self.networkIsActive then
		if self.networkActiveCallback then
			self.networkActiveCallback(false)
		end

		self.networkIsActive = false
	end
end


-- Register a network active callback for power management
function registerNetworkActive(self, callback)
	self.networkActiveCallback = callback
end


-- Called by the network layer when the cpu is active (used for audio
-- playback)
function cpuActive(self, obj)
	self.cpuActiveCount[obj] = 1

	local isempty = next(self.cpuActiveCount)

	if isempty and not self.cpuIsActive then
		if self.cpuActiveCallback then
			self.cpuActiveCallback(true)
		end

		self.cpuIsActive = true
	end
end


-- Called by the network layer when the cpu is inactive (used for audio
-- playback)
function cpuInactive(self, obj)
	self.cpuActiveCount[obj] = nil

	local isempty = next(self.cpuActiveCount)

	if not isempty and self.cpuIsActive then
		if self.cpuActiveCallback then
			self.cpuActiveCallback(false)
		end

		self.cpuIsActive = false
	end
end


-- Register a cpu active callback for power management
function registerCpuActive(self, callback)
	self.cpuActiveCallback = callback
end


-- deprecated
function getUUID(self)
	return System:getUUID(), System:getMacAddress()
end


function setUUID(self, uuid, mac)
	_assert(false, "NetworkThread:setUUID is deprecated")
end


function isArpEnabled(self)
    return _isArpEnabled
end

function setArpEnabled(self, enabled)
    _isArpEnabled = enabled
end

--[[

=head2 getSNHostname()

Retreive the hostname to be used to connect to SqueezeNetwork

=cut
--]]
function getSNHostname(self)
	return squeezenetworkHostname
end


-- Set the squeezenetwork hostname, used with test.squeezenetwork.com
function setSNHostname(self, hostname)
	squeezenetworkHostname = hostname
end


--[[

=head2 arp(host)

Look up hardware address for host. This is async and the sink function
is called when the hardware address is known, or with an error.

=cut
--]]
function arp(self, host, sink)
    if not self:isArpEnabled() then
        return sink(nil, "Arp disabled")
    end

	local arp = ""

	local cmd = "arp " .. host
	if string.match(os.getenv("OS") or "", "Windows") then
			cmd = "arp -a " .. host
	end

	local proc = Process(self, cmd)
	proc:read(function(chunk, err)
			if err then
					return sink(nil, err)
			end

			if chunk then
					arp = arp .. chunk
			else
					local mac = string.match(arp, "%x+[:-]%x+[:-]%x+[:-]%x+[:-]%x+[:-]%x+")
					if mac then
							mac = string.gsub(mac, "-", ":")
							--pad 0 to front of any single character element (needed for at least OS X)
							local elements = string.split(":", mac)
							mac = ""
							for i,element in ipairs(elements) do
								if string.len(element) == 1 then
									mac = mac .. "0"
								end
								mac = mac .. element

								if i < #elements then
									mac = mac .. ":"
								end
							end
					end

					sink(mac)
			end
	end)
end


--[[

=head2 __init()

Creates a new NetworkThread. The thread starts immediately.

=cut
--]]
function __init(self)
--	log:debug("NetworkThread:__init()")

	local obj = oo.rawnew(self, {
		-- list of sockets for select
		t_readSocks = {},
		t_writeSocks = {},

		-- list of objects for notify
		subscribers = {},

		networkActiveCount = {},
		networkIsActive = false,

		cpuActiveCount = {},
		cpuIsActive = false,
	})

	-- subscriptions are gc weak
	setmetatable(obj.subscribers, { __mode = 'k' })

	-- create dns resolver
	DNS(obj)

	return obj
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

