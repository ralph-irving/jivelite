
--[[
=head1 NAME

jive.ui.Time - A timer.

=head1 DESCRIPTION

A timer object.

=head1 SYNOPSIS

 -- Create a timer that prints "hi" every second
 local timer = jive.ui.Timer(1000,
			     function()
				     print "hi"
			     end)

 -- stop the timer
 timer:stop()

=head1 METHODS

=cut
--]]


-- stuff we use
local _assert, ipairs, pcall, string, tostring, type = _assert, ipairs, pcall, string, tostring, type

local oo	= require("loop.base")
local table	= require("jive.utils.table")

local Framework = require("jive.ui.Framework")

local debug	= require("jive.utils.debug")
local log   = require("jive.utils.log").logger("jivelite.timer")


-- our class
module(..., oo.class)


-- sorted list of running timers
local timers = {}


--[[

=head2 jive.ui.Timer(interval, closure, once)

Constructs a new timer. The I<closure> is called every I<interval> milliseconds. If <once> is true then the closure is only called once each time the timer is started.

The I<closure> is called with a single argument, the Timer object.

=cut
--]]
function __init(self, interval, callback, once)
	_assert(type(interval) == "number", debug.traceback())
	_assert(type(callback) == "function")

	return oo.rawnew(self, {
		interval = interval,
		callback = callback,
		once = once or false,
	})
end


--[[

=head2 jive.ui.Timer:start()

Starts the timer.

=cut
--]]

function start(self)
	local now = Framework:getTicks()
	self:_insertTimer(now + self.interval)
end


--[[

=head2 jive.ui.Timer:stop()

Stops the timer.

=cut
--]]

function stop(self)
	 table.delete(timers, self)
	 self.expires = nil
end


--[[

=head2 jive.ui.Timer:restart(interval)

Restarts the timer. Optionally the timer interval can be modified
to I<interval>, otherwise the interval is unchanged.

=cut
--]]
function restart(self, interval)
	_assert(interval == nil or type(interval) == "number")

	self:stop()
	if interval then
		self.interval = interval
	end
	self:start()
end


--[[

=head2 jive.ui.Timer:setInterval(interval)

Sets the timers interval to I<interval> and restarts the timer if
it is already running.

=cut
--]]
function setInterval(self, interval)
	_assert(type(interval) == "number")

	if self.expires then
		self:restart(interval)
	else
		self.interval = interval
	end
end


--[[

=head2 jive.ui.Timer:isRunning()

Returns true if the timer is running.

=cut
--]]
function isRunning(self)
	return self.expires ~= nil
end


-- insert the timer into timer queue
function _insertTimer(self, expires)
	if self.expires then
		table.delete(timers, self)
	end
	self.expires = expires

	for i, timer in ipairs(timers) do
		if self.expires < timer.expires then
	 		table.insert(timers, i, self)
			return
		end
	end
	table.insert(timers, self)
end


-- process timer queue
function _runTimer(self, now)
	if timers[1] and not timers[1].expires then
		log:error("stopped timer in timer list")
		debug.dump(timers)
	end

	while timers[1] and timers[1].expires <= now do
		local timer = table.remove(timers, 1)

		-- call back may modify the timer so update it first
		if not timer.once then
			local next = timer.expires + timer.interval
			if next < now then
				next = now + timer.interval
			end
			timer:_insertTimer(next)
		else
			timer.expires = nil
		end

		local status, err = pcall(timer.callback)
		if not status then
			log:warn("timer error: ", err)
		end
	end
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

