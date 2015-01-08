
--[[
=head1 NAME

jive.utils.locale - Deliver strings based on locale (defaults to EN) and path

=head1 DESCRIPTION

Parses strings.txt from appropriate directory and sends it back as a table

=head1 FUNCTIONS

setLocale(locale)

readStringsFile(thisPath)

=cut
--]]

-- stuff we use
local ipairs, pairs, io, select, setmetatable, string, tostring = ipairs, pairs, io, select, setmetatable, string, tostring

local log              = require("jive.utils.log").logger("jivelite")

local System           = require("jive.System")
local Task             = require("jive.ui.Task")

module(...)


-- current locale
local globalLocale = "EN"

-- all locales seen in strings.txt files
local allLocales = {}

-- weak table containing loaded locales
local loadedFiles = {}
setmetatable(loadedFiles, { __mode = "v" })

-- weak table containing global strings
local globalStrings = {}

-- contains type of machine
local globalMachine = false

--[[
=head 2 setLocale(newLocale)

Set a new locale. All strings already loaded are reloaded from the strings
file for the new locale.

=cut
--]]
function setLocale(self, newLocale, doYield)
	if newLocale == globalLocale then
		return
	end

	globalLocale = newLocale or "EN"
	readGlobalStringsFile(self)

	-- reload existing strings files
	for k, v in pairs(loadedFiles) do
		if doYield then
			Task:yield(true)
		end
		_parseStringsFile(self, newLocale, k, v)
	end
end


--[[
=head2 getLocale()

Returns the current locale.

=cut
--]]
function getLocale(self)
	return globalLocale
end


--[[
=head2 getAllLocales()

Returns all locales.

=cut
--]]
function getAllLocales(self)
	local array = {}
	for locale, _ in pairs(allLocales) do
		array[#array + 1] = locale
	end
	return array
end

--[[

=head2 readStringsFile(self, fullPath, stringsTable)

Parse strings.txt file and put all locale translations into a lua table
that is returned. The strings are for the current locale.

=cut
--]]

function readGlobalStringsFile(self)
	local globalStringsPath = System:findFile("jive/global_strings.txt")
	if globalStringsPath == nil then
		return globalStrings
	end
	globalStrings = _parseStringsFile(self, globalLocale, globalStringsPath, globalStrings)
	setmetatable(globalStrings, { __index = self , mode = "_v" })
	return globalStrings
end

function readStringsFile(self, fullPath, stringsTable)
	log:debug("loading strings from ", fullPath)
	--local defaults = getDefaultStrings(self)

	stringsTable = stringsTable or {}
	loadedFiles[fullPath] = stringsTable
	setmetatable(stringsTable, { __index = globalStrings })
	stringsTable = _parseStringsFile(self, globalLocale, fullPath, stringsTable)

	return stringsTable
end

function _parseStringsFile(self, myLocale, myFilePath, stringsTable)
	log:debug("parsing ", myFilePath)

	globalMachine = "_" .. string.upper(System:getMachine())

	local stringsFile = io.open(myFilePath)
	if stringsFile == nil then
		return stringsTable
	end
	stringsTable = stringsTable or {}

	-- meta table for strings
	local strmt = {
		__tostring = function(e)
				     return e.str -- .. "{" .. myLocale .. "}"
			     end,
	}

	local token, fallback
	while true do
		local line = stringsFile:read()
		if not line then
			break
		end

		-- remove trailing spaces and/or control chars
		line = string.gsub(line, "[%c ]+$", '')

		-- lines that begin with an uppercase char are the strings to translate
		if string.match(line, '^%u') then
			-- fallback for previous token
			if token and fallback and not stringsTable[token].str then
				log:debug("EN fallback=", fallback)
				stringsTable[token].str = fallback
			end

			-- next token
			token = line
			log:debug("token=", token)

			-- wrap the string in a table to allow the localized
			-- value to be changed if a different locale is
			-- later loaded.
			if not stringsTable[token] then
				local str = {}
				setmetatable(str, strmt)
				stringsTable[token] = str
			end

			stringsTable[token].str = false
		end

		-- look for matching translation lines.
		-- defined here as one or more tabs
		-- followed by one or more non-spaces (lang)
		-- followed by one or more tabs
		-- followed by the rest (the translation)
		local locale, translation  = string.match(line, '^\t+([^%s]+)\t+(.+)')

		if locale and translation and token then
			-- remember all locales seen
			allLocales[locale] = true

			if locale == myLocale then
				log:debug("translation=", translation)

				-- convert \n
				translation = string.gsub(translation, "\\n", "\n")
				stringsTable[token].str = translation
			end

			if locale == "EN" then
				fallback = translation
				-- convert \n
				fallback = string.gsub(fallback, "\\n", "\n")
			end
		end
	end

	-- fallback for last token
	if token and fallback and not stringsTable[token].str then
		log:debug("EN fallback=", fallback)
		stringsTable[token].str = fallback
	end

	stringsFile:close()

	return stringsTable
end


--[[

=head2 loadAllStrings(self, filePath)

Parse strings.txt file and put all locale translations into a lua table
that is returned. Strings for all locales are returned.

=cut
--]]
function loadAllStrings(self, myFilePath)
	local stringsFile = io.open(myFilePath)
	if stringsFile == nil then
		return {}
	end
	
	local allStrings = {}
	local token 
	while true do
		local line = stringsFile:read()
		if not line then
			break
		end

		-- remove trailing spaces and/or control chars
		line = string.gsub(line, "[%c ]+$", '')
		-- lines that begin with an uppercase char are the strings to translate
		if string.match(line, '^%u') then
			token = line
			log:debug("this is a string to be matched |", token, "|")
		else
			-- look for matching translation lines.
			-- defined here as one or more tabs
			-- followed by one or more non-spaces (lang)
			-- followed by one or more tabs
			-- followed by the rest (the translation)
			local locale, translation  = string.match(line, '^\t+([^%s]+)\t+(.+)')

			if token and translation then
				-- convert \n to \n
				translation = string.gsub(translation, "\\n", "\n")

				if allStrings[locale] == nil then
					allStrings[locale] = {}
				end

				allStrings[locale][token] = translation
			end
		end
	end
	stringsFile:close()

	return allStrings
end


function str(self, token, ...)
	token = token.str or token
	local machineToken = token .. globalMachine

	if select('#', ...) == 0 then
		return self[machineToken] or self[token] or token
	else
		if self[machineToken] then
			return string.format(self[machineToken].str or machineToken, ...)
		elseif self[token] then
			return string.format(self[token].str or token, ...)
		else
			return string.format(token, ...)
		end
	end
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

