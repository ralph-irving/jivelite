
local assert, error, ipairs, pairs, tostring, type, unpack = assert, error, ipairs, pairs, xotostring, type, unpack


local coroutine        = require("coroutine")

local oo               = require("loop.base")
local debug            = require("jive.utils.debug")
local table            = require("jive.utils.table")
local coxpcall         = require("jive.utils.coxpcall")

local log              = require("jive.utils.log").logger("jivelite.task")


module(..., oo.class)


-- constants
PRIORITY_AUDIO = 1
PRIORITY_HIGH = 2
PRIORITY_LOW = 3


-- the task list is modified while iterating over the entries,
-- we use a linked list to make the iteration easier
-- three queues: streaming, high and low
local taskHead = { nil, nil, nil }

-- the task that is active, or nil for the main thread
local taskRunning = nil


function __init(self, name, obj, f, errf, priority)
	assert(type(f) == "function")
	assert(errf == nil or type(errf) == "function")
	assert(priority == nil or type(priority) == "number")

	local obj = oo.rawnew(self, {
				      name = name,
				      obj = obj,
				      args = {},
				      thread = coroutine.create(f),
				      errf = errf,
				      priority = priority or PRIORITY_LOW,
			      })

	return obj
end


-- returns true if the task is suspened or false if it is completed
function resume(self)
	log:debug("task: ", self.name)

	taskRunning = self

	local nerr, val = coroutine.resume(self.thread, self.obj, unpack(self.args))

	taskRunning = nil
	if nerr then
		if val == nil then
			val = (coroutine.status(self.thread) ~= "dead")
		end

		if val then
			-- continue to run task
			return true
		else
			-- suspend task
			self:removeTask()
			return false
		end
	else
		-- task has error
		log:error("task error ", self.name, ": ", val)
		self:removeTask()
		self.state = "error"

		if self.errf then
			self.errf(self.obj)
		end
		return false
	end
end


-- set the arguments passed to the co-routine function or yield
function setArgs(self, ...)
	self.args = { ... }
end


-- add task to the end of the task list
function addTask(self, ...)
	log:debug("addTask ", self.name)

	if self.state == "error" then
		log:warn("task ", self.name, " in error state")
		return false
	end

	if self.state == "active" then
		return true
	end

	self.args = { ... }
	self.state = "active"
	self.next = nil

	if taskHead[self.priority] == nil then
		taskHead[self.priority] = self
	else
		local entry = taskHead[self.priority]
		while entry do
			if not entry.next then
				entry.next = self
				break
			end

			entry = entry.next
		end
	end

	return true
end


-- remove task from task list
function removeTask(self)
	log:debug("removeTask ", self.name)

	self.state = "suspended"

	-- unlink from linked list
	if not taskHead then
		return
	end

	if taskHead[self.priority] == self then
		if taskHead[self.priority].next then
			taskHead[self.priority] = self.next
		else
			taskHead[self.priority] = nil
		end
		return
	end

	local entry = taskHead[self.priority]
	while entry do
		if entry.next == self then
			entry.next = self.next
			return
		end

		entry = entry.next
	end
end


function yield(class, ...)
	return coroutine.yield(...)
end


function pcall(class, f, ...)
	return coxpcall.coxpcall(f, debug.traceback, ...)
end


function xpcall(class, ...)
	return coxpcall.coxpcall(...)
end


function running(class)
	return taskRunning
end


function dump(class)
	local header = false

	for i,v in pairs(taskHead) do
		local entry = taskHead[i]

		if entry and not header then
			log:info("Task queue:")
			header = true
		end

		while entry do
			log:info(i, ": ", entry.name, " (", entry, ")")
			entry = entry.next
		end
	end
end


-- iterate over the task list. it is safe to add or remove tasks while
-- iterating.
function iterator(class)
	local entry = true
	local priority = 1

	return function()
		       if entry == true then
			       entry = taskHead[priority]
		       else
			       entry = entry.next
		       end

		       while entry == nil and priority < PRIORITY_LOW do
			       priority = priority + 1
 			       entry = taskHead[priority]
		       end

		       return entry
	       end
end


function __tostring(self)
	return "Task(" .. self.name .. ")"
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]
