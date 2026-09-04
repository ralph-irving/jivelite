-- Exercise unchanged Lua timer consumers with exact millisecond values beyond
-- the former signed and unsigned 32-bit boundaries.

_G._assert = assert

local current = 0

package.preload["jive.ui.Framework"] = function()
	return {
		getTicks = function()
			return current
		end,
	}
end

package.preload["jive.utils.log"] = function()
	local logger = {
		debug = function() end,
		error = function() end,
		warn = function() end,
	}
	return { logger = function() return logger end }
end

local Timer = assert(require("jive.ui.Timer"))

local function runOneShotAcrossBoundary(boundary)
	local fired = 0
	current = boundary - 10
	local timer = Timer(20, function() fired = fired + 1 end, true)
	timer:start()
	Timer:_runTimer(boundary - 1)
	assert(fired == 0)
	Timer:_runTimer(boundary + 10)
	assert(fired == 1)
	assert(not timer:isRunning())
end

runOneShotAcrossBoundary(2^31)
runOneShotAcrossBoundary(2^32)

current = 2^32 - 5
local order = {}
local later = Timer(20, function() order[#order + 1] = "later" end, true)
local earlier = Timer(10, function() order[#order + 1] = "earlier" end, true)
later:start()
earlier:start()
Timer:_runTimer(2^32 + 5)
Timer:_runTimer(2^32 + 15)
assert(table.concat(order, ",") == "earlier,later")

current = 2^32 - 5
local recurringCount = 0
local recurring = Timer(10, function() recurringCount = recurringCount + 1 end)
recurring:start()
Timer:_runTimer(2^32 + 5)
Timer:_runTimer(2^32 + 15)
assert(recurringCount == 2)
recurring:stop()

assert((2^31 + 125) - (2^31 - 25) == 150)
assert((2^32 + 125) - (2^32 - 25) == 150)

print("Lua tick boundary tests passed")
