

local tonumber = tonumber


local oo          = require("loop.simple")
local string      = require("string")
local table       = require("table")

local SocketUdp   = require("jive.net.SocketUdp")

local log         = require("jive.utils.log").logger("net.http")


module(...)
oo.class(_M, SocketUdp)


function __init(self, jnt)
	return oo.rawnew(self, SocketUdp(jnt, function() end))
end


function wakeOnLan(self, hwaddr)
	local mac = {}
	for v in string.gmatch(hwaddr, "(%x%x)") do
		mac[#mac + 1] = string.char(tonumber(v, 16))
	end
	mac = table.concat(mac)

	local packet = string.rep(string.char(0xFF), 6) .. string.rep(mac, 16)

	self:send(function() return packet end, "255.255.255.255", 7)
end
