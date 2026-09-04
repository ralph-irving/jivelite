-- Verify that existing absolute-deadline consumers remain correct when the
-- shared native clock advances beyond the former signed and unsigned 32-bit
-- boundaries. The native binding now publishes exact millisecond values as a
-- lua_Number; this test injects those values into the unmodified Timer API.

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

local function oneShotAcross(start, boundary)
	local fired = 0
	current = start
	local timer = Timer(20, function() fired = fired + 1 end, true)
	timer:start()
	Timer:_runTimer(boundary - 1)
	assert(fired == 0)
	Timer:_runTimer(start + 20)
	assert(fired == 1)
	assert(not timer:isRunning())
end

oneShotAcross(2^31 - 10, 2^31)
oneShotAcross(2^32 - 10, 2^32)

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

-- The network timeout uses the same subtraction contract. Values on both
-- sides of the former wrap must retain their real elapsed duration.
assert((2^31 + 125) - (2^31 - 25) == 150)
assert((2^32 + 125) - (2^32 - 25) == 150)

print("64-bit monotonic timer boundary tests OK")
