--[[
=head1 NAME

jive.utils.datetime - stores datetime settings for use in all the applets

=head1 DESCRIPTION

This object should provide all Date/Time related functions
- Timezone info
- Locale Based Date and Time formats

=head1 FUNCTIONS

getAllDateFormats(self)
setWeekstart(self, day)
isClockSet(self)
getWeekstart(self)
setDateFormat(self, dateformat)
getDateFormat(self)
getShortDateFormat(self)
getCurrentTime(self)
getTimeZone(self, timezone)
getAllTimeZones(self)
setTimeZone(self, timezone)
setHours(self, hours)
getHours(self)
secondsFromMidnight(self, hhmm)
timeFromSFM(self, secondsFromMidnight)

=cut
--]]


-- stuff we use
local ipairs, pairs, io, select, setmetatable = ipairs, pairs, io, select, setmetatable
local string, type, tonumber, tostring = string, type, tonumber, tostring

local os               = require("os")
local math             = require("math")
local locale           = require("jive.utils.locale")

local log              = require("jive.utils.log").logger("jivelite")


module(...)

-- FIXME: i8n
local globalWeekstart = "Sunday"
local globalDateFormat = "%a, %B %d %Y"
local globalShortDateFormat = "%d.%m.%Y"
local globalHours = "12"
local globalTimeZone = "GMT"

local _globalStrings

local timeSet = false

local DateFormats = {
	"%a %d %b %Y",
	"%a %d. %b %Y",
	"%a, %b %d, '%y",
	"%a, %d %b, %Y",
	"%a, %d. %b, %Y",
	"%A %d %B %Y",
	"%A %d. %B %Y",
	"%A, %B %d, %Y",
	"%A, %B. %d, %Y",
	"%d %B %Y",
	"%d. %B %Y",
	"%B %d, %Y",
	"%Y-%m-%d",
	"%Y-%m-%d %A",
	"%Y-%m-%d (%a)",
	"%Y/%m/%d",
	"%Y/%m/%d %A",
	"%Y/%m/%d (%a)",
	"%d-%m-%Y",
	"%d-%m-%y",
	"%d.%m.%Y",
	"%d.%m.%y",
	"%d/%m/%Y",
	"%d/%m/%y",
	"%m-%d-%Y",
	"%m-%d-%y",
	"%m.%d.%Y",
	"%m.%d.%y",
	"%m/%d/%Y",
	"%m/%d/%y"
}

local ShortDateFormats = {
	"%m.%d.%Y",
	"%d.%m.%Y",
}

local TimeZones = {
        GMT = {
                offset = 0,
                text = "GMT"
        },

        CET = {
                offset = 1,
                text = "Berlin, Zurich"
        },
}

--[[
=head2 getAllDateFormats(self)

Returns all available Date Formats defined in the local table DateFormat

=cut
--]]
function getAllDateFormats(self)
	return DateFormats
end


--[[
=head2 getAllShortDateFormats(self)

Returns all available Short Date Formats defined in the local table ShortDateFormat

=cut
--]]
function getAllShortDateFormats(self)
	return ShortDateFormats
end


--[[
=head2 setWeekstart(self, day)

Sets the day with which the week starts.
Usualy Monday in Europe and Sunday in the USA

=cut
--]]
function setWeekstart(self, day)
	if day == nil then
		log:error("setWeekstart() - day is nil")
		return
	end

	if day == "Sunday" then
		globalWeekstart = day
	elseif day == "Monday" then
		globalWeekstart = day
	else
		log:error("Invalid Weekstart: " .. day)
	end
end

--[[
=head2 getWeekstart(self)

Returns the current setting for the first day in the week.

=cut
--]]
function getWeekstart(self)
	return globalWeekstart
end


--[[
=head2 setShortDateFormat(self, dateformat)

Set the default short date format.

=cut
--]]
function setShortDateFormat(self, dateformat)
	globalShortDateFormat = dateformat
end


--[[
=head2 getShorDateFormat(self)

Return the default short date format.

=cut
--]]
function getShortDateFormat(self)
	return globalShortDateFormat
end


--[[
=head2 setDateFormat(self, dateformat)

Set the default date format.

=cut
--]]
function setDateFormat(self, dateformat)
	globalDateFormat = dateformat
end

--[[
=head2 getDateFormat(self)

Return the default date format.

=cut
--]]
function getDateFormat(self)
	return globalDateFormat
end

--[[
=head2 getCurrentDate(self)

Returns a date string using the set date format.

=cut
--]]
function getCurrentDate(self, format)
	local formattedDate = format or globalDateFormat
	local date = os.date("*t")

	-- now we're going to try to localise the date string...
	if _globalStrings == nil then
		_globalStrings = locale:readGlobalStringsFile()
	end
	
	-- long day format
	formattedDate = string.gsub(formattedDate, "%%A", tostring(_globalStrings:str("DAY_" .. date.wday)))
	-- short day format
	formattedDate = string.gsub(formattedDate, "%%a", tostring(_globalStrings:str("DAYSHORT_" .. date.wday)))
	-- long month format
	formattedDate = string.gsub(formattedDate, "%%B", tostring(_globalStrings:str("MONTH_" .. date.month)))
	-- short month format
	formattedDate = string.gsub(formattedDate, "%%b", tostring(_globalStrings:str("MONTHSHORT_" .. date.month)))

	-- fill in the remaining items
	return os.date(formattedDate)
end

--[[
=head2 getTimeZone

Returns the current time zone.

=cut
--]]
function getTimeZone(self, timezone)
	for k, v in pairs(TimeZones) do
		if k == timezone then
			return v
		end
	end

	return nil
end

--[[
=head2 getAllTimeZones(self)

Returns all available time zones defined in the table TimeZones.

=cut
--]]
function getAllTimeZones(self)
	return TimeZones
end

--[[
=head2 setTimeZone(self, timezone)

Set the current time zone. The function checks if the timezone is available.
Returns true if the timezone could be set.

=cut
--]]
function setTimeZone(self, timezone)
	local test_tz = self:getTimeZone(timezone)

	if test_tz == nil then
		log:error("Set Invalid TimeZone")
		return false
	else
		globalTimeZone = timezone
		return true
	end
end

--[[
=head2 setHours(self, hours)

Sets the Hours used in the clock. 24h or AM,PM (12h)

=cut
--]]
function setHours(self, hours)
	if type(hours) == "string"  then
		if hours == "12" or hours == "24" then
			globalHours = hours
		else 
			log:error("datetime:setHours() - hours is not 12 or 24")
		end
	elseif type(hours) == "number" then
		if hours == 12 then
			globalHours = "12"
		elseif hours == 24 then 
			globalHours = "24"
		else
			log:error("datetime:setHours() - hours is not 12 or 24")
		end
	else
		log:error("Invalid Parameter for datetime:setHours()")
	end
end

--[[
=head2 getLocale()

Returns the current setting for hours. 24h or AM,PM (12h)

=cut
--]]
function getHours(self)
	return globalHours
end

--[[
=head2 secondsFromMidnight()

Takes hhmm format and returns seconds from midnight

=cut
--]]
function secondsFromMidnight(self, hhmm)
	local timeElements = {}
	local i = 1
	local secondsFromMidnight = 0
	local _hhmm = tostring(hhmm)
	for element in string.gmatch(_hhmm, "(%d%d)") do
		-- element 1 is hh, element 2 is mm
		timeElements[i] = tonumber(element)
		i = i+1
	end
	
	-- convert ampm hours to 24h for method calculation
	if string.find(_hhmm, 'p') then
		if timeElements[1] ~= 12 then
			timeElements[1] = timeElements[1] + 12
		end
	elseif string.find(_hhmm, 'a') then
		if timeElements[1] == 12 then
			timeElements[1] = 0
		end
	end

	-- punt if this isn't a valid hh mm array
	if (timeElements[1] > 23 or timeElements[2] > 59) then
		return secondsFromMidnight
	end

	secondsFromMidnight = (timeElements[1] * 3600) + (timeElements[2] * 60)
	return secondsFromMidnight
end


--[[
=head2 timeTableFromSFM()

Takes seconds from midnight and returns table of { hour, minute, ampm } ( ampm nil when format is 24 )

=cut
--]]
function timeTableFromSFM(self, secondsFromMidnight, format)

	if not format then
		format = '24'
	end

	local sfm = tonumber(secondsFromMidnight)
	-- 24h format
	if format == '24' then
		if (sfm >= 86400 or sfm < 0) then
			return { 
				hour   = 0, 
				minute = 0, 
				ampm   = nil,
			}
		end

		local hours   = tonumber(math.floor(sfm/3600))
		local minutes = tonumber(math.floor((sfm % 3600) / 60 ))
	
		return { 
			hour   = hours, 
			minute = minutes, 
			ampm   = nil 
		}
	-- 12h format
	else
		local ampm
		if (sfm >= 86400 or sfm < 0) then
			return { 
				hour   = 12, 
				minute = 0, 
				ampm   = 'PM',
			}
		end

		if (sfm < 43200) then
			ampm = 'AM'
		else
			ampm = 'pm'
		end

		local hours   = tonumber(math.floor(sfm/3600))
		local minutes = tonumber(math.floor((sfm % 3600) / 60 ))

		if hours < 1 then
			hours = 12
		elseif hours > 12 then
			hours = hours - 12
		end
	
		return { 
			hour   = hours, 
			minute = minutes, 
			ampm   = ampm,
		}
	end
end


--[[
=head2 timeFromSFM()

Takes seconds from midnight and returns time format (24h for now)

=cut
--]]
function timeFromSFM(self, secondsFromMidnight, format)

	if not format then
		format = '24'
	end

	local sfm = tonumber(secondsFromMidnight)
	-- 24h format
	if format == '24' then
		if (sfm >= 86400 or sfm < 0) then
			return "00:00"
		end

		local hours   = tonumber(math.floor(sfm/3600))
		local minutes = tonumber(math.floor((sfm % 3600) / 60 ))
	
		local formattedTime = string.format("%02d:%02d", hours, minutes)
		return formattedTime
	-- 12h format
	else
		local ampm
		if (sfm >= 86400 or sfm < 0) then
			return "12:00a"
		end

		if (sfm < 43200) then
			ampm = 'a'
		else
			ampm = 'p'
		end

		local hours   = tonumber(math.floor(sfm/3600))
		local minutes = tonumber(math.floor((sfm % 3600) / 60 ))

		if hours < 1 then
			hours = 12
		elseif hours > 12 then
			hours = hours - 12
		end
	
		local formattedTime = string.format("%02d:%02d%s", hours, minutes, ampm)
		return formattedTime
	end
end

--[[
=head2 isClockSet()

Returns a boolean as to whether the clock appears to be set correctly

=cut
--]]
function isClockSet()
	if tonumber(os.date("%Y")) < 2010 then
		return false
	end
	return true

end


--[[
=head2 getCurrentTime(self, format)

Returns the current, formatted time.
If date format given, return the time in that format.

Example: 	21:57 (24h format)
		 9:57PM (AM/PM)
		 9:57 ('%I:%M' format sent as optional argument)
=cut
--]]
function getCurrentTime(self, format)

	-- if the time has not been set, return an empty string
	if not timeSet then
		if tonumber(os.date("%Y")) < 2010 then
			return ""
		end

		timeSet = true
	end

	local str
	if format then
		str = os.date(format)
	elseif globalHours == "12" then
		str = os.date("%I:%M%p")		
	else
		str = os.date("%H:%M")
	end	
	-- replace leading 0 with space
	str = string.gsub(str, "^0", " ", 1)

	return str
end
