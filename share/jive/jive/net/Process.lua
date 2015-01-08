

local oo              = require("loop.base")
local io              = require("io")
local os              = require("os")
local coroutine       = require("coroutine")
local string          = require("string")

local Task            = require("jive.ui.Task")

local debug           = require("jive.utils.debug")
local log             = require("jive.utils.log").logger("net.socket")

-- use ffi as luajit does not appear to support fileno as a method for io objects
local ffi             = require("ffi")
ffi.cdef[[int fileno(void *)]]

module(..., oo.class)


function __init(self, jnt, prog)
	local obj = oo.rawnew(self, {
		jnt = jnt,
		prog = prog,
		_status = "suspended",
	})

	return obj
end


function read(self, sink)
	self.fh, err = io.popen(self.prog, "r")

	if self.fh == nil then
		sink(nil, err)

		self._status = "dead"
		return
	end

	if string.match(os.getenv("OS") or "", "Windows") then
			-- blocking on Windows!
			local chunk = self.fh:read("*a")
			self.fh:close()
			
			sink(chunk)
			sink(nil)
			return
	end

	local task = Task("prog:" .. self.prog,
			nil,
			function(_, ...)
				while true do
					local chunk = self.fh:read(8096)
					sink(chunk)

					if chunk == nil then
						self.fh:close()
						self.jnt:t_removeRead(self)

						self._status = "dead"
						return
					end

					Task:yield()
				end
			end)

	self._status = "running"
	self.jnt:t_addRead(self, task, 0)
end


function status(self, sink)
	return self._status
end

function getfd(self)
	--return self.fh:fileno()
	return ffi.C.fileno(self.fh)
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]
