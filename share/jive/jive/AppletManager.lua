
--[[
=head1 NAME

jive.AppletManager - The applet manager.

=head1 DESCRIPTION

The applet manager discovers applets and loads and unloads them from memory dynamically.

=head1 SYNOPSIS

TODO

=head1 FUNCTIONS

=cut
--]]

-- stuff we use
local package, pairs, error, load, loadfile, io, assert, os = package, pairs, error, load, loadfile, io, assert, os
local setfenv, getfenv, require, pcall, unpack = setfenv, getfenv, require, pcall, unpack
local tostring, tonumber, collectgarbage = tostring, tonumber, collectgarbage

local string           = require("jive.utils.string")
                       
local oo               = require("loop.simple")
local io               = require("io")
local lfs              = require("lfs")
                       
local debug            = require("jive.utils.debug")
local utilLog          = require("jive.utils.log")
local log              = require("jive.utils.log").logger("jivelite.applets")
local locale           = require("jive.utils.locale")
local dumper           = require("jive.utils.dumper")
local table            = require("jive.utils.table")

local System           = require("jive.System")

local JIVE_VERSION     = jive.JIVE_VERSION
local EVENT_ACTION     = jive.ui.EVENT_ACTION
local EVENT_WINDOW_POP = jive.ui.EVENT_WINDOW_POP
local EVENT_CONSUME    = jive.ui.EVENT_CONSUME
local EVENT_UNUSED     = jive.ui.EVENT_UNUSED


module(..., oo.class)


-- all the known (found) applets, indexed by applet name
local _appletsDb = {}

-- the jnt
-- note we cannot have a local jnt = jnt above because at the time AppletManager is loaded
-- the global jnt value is nil!
local jnt

-- loop detection
local _sentinel = function () end

-- applet services
local _services = {}

local _defaultSettingsByAppletName = {}
--work in progress-- local _overrideSettingsByAppletName = {}

-- allowed applets, can be used for debugging to limit applets loaded
--[[
local allowedApplets = {
	QVGAportraitSkin = true,
	SqueezeDiscovery = true,
}
--]]



-- _init
-- creates an AppletManager object
-- this just for the side effect of assigning our jnt local
function __init(self, thejnt)
	jnt = thejnt
	_initUserpathdir()
	return oo.rawnew(self, {})
end


function _initUserpathdir()
	_userpathdir = System.getUserDir()
	_usersettingsdir = _userpathdir .. "/settings"
	_userappletsdir = _userpathdir .. "/applets"
	
	log:info("User Path: ", _userpathdir)
	
	_mkdirRecursive(_userpathdir)
	_mkdirRecursive(_usersettingsdir)
	_mkdirRecursive(_userappletsdir)
end

function _mkdirRecursive(dir)
    --normalize to "/"
    local dir = dir:gsub("\\", "/")
   
    local newPath = ""
    for i, element in pairs(string.split('/', dir)) do
        newPath = newPath .. element
        if i ~= 1 then --first element is (for full path): blank for unix , "<drive-letter>:" for windows
            if lfs.attributes(newPath, "mode") == nil then
                log:debug("Making directory: " , newPath)

                local created, err = lfs.mkdir(newPath)
                if not created then
                    error (string.format ("error creating dir '%s' (%s)", newPath, err))
                end	
            end
        end
        newPath = newPath .. "/"
    end
    
end

-- _saveApplet
-- creates entries for appletsDb, calculates paths and module names
local function _saveApplet(name, dir)
	log:debug("Found applet ", name, " in ", dir)
	
	if allowedApplets and not allowedApplets[name] then
		return
	end

	if not _appletsDb[name] then

		local dirpath = dir .. "/" .. name .. "/"

		local newEntry = {
			appletName = name,

			-- file paths
			dirpath = dirpath,
			basename = dirpath .. name,

			settingsFilepath = _usersettingsdir .. "/" .. name .. ".lua",

			-- lua paths
			appletModule = "applets." .. name .. "." .. name .. "Applet",
			metaModule = "applets." .. name .. "." .. name .. "Meta",

			-- logger is automatically set for applets
			appletLogger = utilLog.logger("applet." .. name),

			settings = false,
			metaLoaded = false,
			metaRegistered = false,
			metaConfigured = false,
			appletLoaded = false,
			appletEvaluated = false,
			loadPriority = _getLoadPriority(dir.. "/" .. name)
		}
		_appletsDb[name] = newEntry
	end
end


-- _findApplets
-- find the available applets and store the findings in the appletsDb
local function _findApplets()
	log:debug("_findApplets")

	-- Find all applets/* directories on lua path
	for dir in package.path:gmatch("([^;]*)%?[^;]*;") do repeat
	
		dir = dir .. "applets"
		log:debug("..in ", dir)
		
		local mode = lfs.attributes(dir, "mode")
		if mode ~= "directory" then
			break
		end

		for entry in lfs.dir(dir) do repeat
			local entrydir = dir .. "/" .. entry
			local entrymode = lfs.attributes(entrydir, "mode")

			if entry:match("^%.") or entrymode ~= "directory" then
				break
			end

			local metamode = lfs.attributes(entrydir  .. "/" .. entry .. "Meta.lua", "mode")
			if metamode == "file" then
				_saveApplet(entry, dir)
			end
		until true end
	until true end
end


-- _loadMeta
-- loads the meta information of applet entry
local function _loadMeta(entry)
	log:debug("_loadMeta: ", entry.appletName)

	local p = entry.metaLoaded
	if p then
		if p == _sentinel then
			error (string.format ("loop or previous error loading meta '%s'", entry.appletName))
		end
		return p
	end
	local f, err = loadfile(entry.basename .. "Meta.lua")
	if not f then
		error (string.format ("error loading meta `%s' (%s)", entry.appletName, err))
	end

	-- load applet resources
	_loadLocaleStrings(entry)
	_loadSettings(entry)
	
	entry.metaLoaded = _sentinel
	
	-- give the function the global environment
	-- sandboxing would happen here!
	setfenv(f, getfenv(0))
	
	local res = f(entry.metaModule)
	if res then
		entry.metaLoaded = res
	end
	if entry.metaLoaded == _sentinel then
		entry.metaLoaded = true
	end
	return entry.metaLoaded
end


-- _ploadMeta
-- pcall of _loadMeta
local function _ploadMeta(entry)
--	log:debug("_ploadMeta: ", entry.appletName)
	
	local ok, resOrErr = pcall(_loadMeta, entry)
	if not ok then
		entry.metaLoaded = false
		log:error("Error while loading meta for ", entry.appletName, ":", resOrErr)
		return nil
	end
	return resOrErr
end


-- _evalMeta
-- evaluates the meta information of applet entry
local function _registerMeta(entry)
	log:debug("_evalMeta: ", entry.appletName)

	entry.metaRegistered = true

	local class = require(entry.metaModule)
	class.log = entry.appletLogger

	local obj = class()
 
	-- check Applet version
-- FIXME the JIVE_VERSION has changed from '1' to '7.x'. lets not break
-- the applets now.
--	local ver = tonumber(string.match(JIVE_VERSION, "(%d+)"))
	local ver = 1
	local min, max = obj:jiveVersion()
	if min < ver or max > ver then
		error("Incompatible applet " .. entry.appletName)
	end

	entry.defaultSettings = obj:defaultSettings()

	if not entry.settings then
		entry.settings = obj:defaultSettings()

		--apply global defaults
		local globalDefaultSettings = _getDefaultSettings(entry.appletName)
	
		if globalDefaultSettings then		
			if not entry.settings then
				entry.settings = {}
			end
			
			for settingName, settingValue in pairs(globalDefaultSettings) do
				--global defaults override applet default settings
				log:debug("Setting global default: ", settingName, "=", settingValue)
				entry.settings[settingName] = settingValue
			end
		end

	else
		entry.settings = obj:upgradeSettings(entry.settings)
	end

	--apply global overrides
--	local overrideSettings = _getOverrideSettings(entry.appletName)
--
--	if defaultSettings then
--		if not entry.settings then
--			entry.settings = {}
--		end
--		
--		for settingName, settingValue in pairs(defaultSettings) do
--			--global defaults override applet default settings
--			entry.settings[settingName] = settingValue
--		end
--	end
	
	obj._entry = entry
	obj._settings = entry.settings
	obj._defaultSettings = entry.settings
	obj._stringsTable = entry.stringsTable

	entry.metaObj = obj

	-- we're good to go, the meta should now hook the applet
	-- so it can be loaded on demand.
	log:info("Registering: ", entry.appletName)
	entry.metaObj:registerApplet()
end


local function _configureMeta(entry)
	entry.metaConfigured = true

	entry.metaObj:configureApplet()
end


local function _pregisterMeta(entry)
	if entry.metaLoaded and not entry.metaRegistered then
		local ok, resOrErr = pcall(_registerMeta, entry)
		if not ok then
			entry.metaConfigured = false
			entry.metaRegistered = false
			entry.metaLoaded = false
			log:error("Error registering meta for ", entry.appletName, ":", resOrErr)
			return nil
		end
	end

	return true
end

-- _loadAndRegisterMetas
-- loads and registers the meta-information of all applets
local function _loadAndRegisterMetas()
	log:debug("_loadAndRegisterMetas")

	for name, entry in pairs(getSortedAppletDb(_appletsDb)) do
		if not entry.metaLoaded then
			_ploadMeta(entry)
			if not entry.metaRegistered then
				_pregisterMeta(entry)
			end
		end
	end

end
-- _evalMetas
-- evaluates the meta-information of all applets
local function _evalMetas()
	log:debug("_evalMetas")

	for name, entry in pairs(getSortedAppletDb(_appletsDb)) do
		if entry.metaLoaded and not entry.metaConfigured then
			local ok, resOrErr = pcall(_configureMeta, entry)
			if not ok then
				entry.metaConfigured = false
				entry.metaRegistered = false
				entry.metaLoaded = false
				log:error("Error configuring meta for ", entry.appletName, ":", resOrErr)
			end
		end
	end

	-- at this point, we have loaded the meta, the applet strings and settings
	-- performed the applet registration and we try to remove all traces of the 
	-- meta by removing it from package.loaded, deleting the string table, etc.
	
	-- we keep settings around to that we minimize writing to flash. If we wanted to
	-- trash them , we would need to store them here (to reload them if the applet ever runs)
	-- because the meta might have changed them.

	for name, entry in pairs(getSortedAppletDb(_appletsDb)) do
		entry.metaObj = nil

		-- trash the meta in all cases, it's done it's job
		package.loaded[entry.metaModule] = nil
	
		-- remove strings eating up mucho valuable memory
--		entry.stringsTable = nil
	end
end


-- discover
-- finds and loads applets
function discover(self)
	log:debug("AppletManager:loadApplets")

	_findApplets()
	_loadAndRegisterMetas()
	_evalMetas()
end


function getSortedAppletDb(hash)
    local sortedTable = {};
    for k, value in pairs(hash) do
        table.insert(sortedTable, value);
    end
    table.sort(sortedTable, _comparatorLoadPriorityThenAlphabetic)
    return sortedTable;
end

function _comparatorLoadPriorityThenAlphabetic(a, b)
	if (a.loadPriority ~= b.loadPriority) then
		return a.loadPriority < b.loadPriority
	else
		return a.appletName < b.appletName				
	end	
end


-- _loadApplet
-- loads the applet 
local function _loadApplet(entry)
	log:debug("_loadApplet: ", entry.appletName)

	-- check to see if Applet is already loaded
	local p = entry.appletLoaded
	if p then
		if p == _sentinel then
			error (string.format ("loop or previous error loading applet '%s'", entry.appletName))
		end
		return p
	end
	local f, err = loadfile(entry.basename .. "Applet.lua")
	if not f then
		--error (string.format ("error loading applet `%s' (%s)\n", entry.appletName, err))
		error (string.format ("%s|%s", entry.appletName, err))
	end

	-- load applet resources
	_loadLocaleStrings(entry)
	_loadSettings(entry)

	entry.appletLoaded = _sentinel
	
	-- give the function the global environment
	-- sandboxing would happen here!
	setfenv(f, getfenv(0))

	local res = f(entry.appletModule)
	if res then
		entry.appletLoaded = res
	end
	if entry.appletLoaded == _sentinel then
		entry.appletLoaded = true
	end
	return entry.appletLoaded
end


-- _ploadApplet
-- pcall of _loadApplet
local function _ploadApplet(entry)
--	log:debug("_ploadApplet: ", entry.appletName)
	
	local ok, resOrErr = pcall(_loadApplet, entry)
	if not ok then
		entry.appletLoaded = false
		log:error("Error while loading applet ", entry.appletName, ":", resOrErr)
		return nil
	end
	return resOrErr
end


-- _evalApplet
-- evaluates the applet
local function _evalApplet(entry)
	log:debug("_evalApplet: ", entry.appletName)

	entry.appletEvaluated = true

	local class = require(entry.appletModule)
	class.log = entry.appletLogger

	local obj = class()

	-- we're run protected
	-- if something breaks, the pcall will catch it

	obj._entry = entry
	obj._settings = entry.settings
	obj._defaultSettings = entry.defaultSettings
	obj._stringsTable = entry.stringsTable

	obj:init()

	entry.appletEvaluated = obj

	return obj
end


-- _pevalApplet
-- pcall of _evalApplet
local function _pevalApplet(entry)
--	log:debug("_pevalApplet: ", entry.appletName)
	
	local ok, resOrErr = pcall(_evalApplet, entry)
	if not ok then
		entry.appletEvaluated = false
		entry.appletLoaded = false
		package.loaded[entry.appletModule] = nil
		log:error("Error while evaluating applet ", entry.appletName, ":", resOrErr)
		return nil
	end
	return resOrErr
end


-- load
-- loads an applet. returns an instance of the applet
function loadApplet(self, appletName)
	log:debug("AppletManager:loadApplet: ", appletName)

	local entry = _appletsDb[appletName]
	
	-- exists?
	if not entry then
		log:error("Unknown applet: ", appletName)
		return nil
	end
	
	-- already loaded?
	if entry.appletEvaluated then
		return entry.appletEvaluated
	end
	
	-- meta processed?
	if not entry.metaRegistered then
		if not entry.metaLoaded and not _ploadMeta(entry) then
			return nil
		end
		if not _pregisterMeta(entry) then
			return nil
		end
	end
	
	-- already loaded? (through meta calling load again)
	if entry.appletEvaluated then
		return entry.appletEvaluated
	end
	
	
	if _ploadApplet(entry) then
		local obj = _pevalApplet(entry)
		if obj then
			log:debug("Loaded: ", appletName)
		end
		return obj
	end
end


-- returns true if the applet can be loaded
function hasApplet(self, appletName)
	return _appletsDb[appletName] ~= nil
end


--[[

=head2 jive.AppletManager.getAppletInstance(appletName)

Returns the loaded instance of applet I<appletName>, if any.

=cut
--]]
function getAppletInstance(self, appletName)
	local entry = _appletsDb[appletName]

	-- exists?
	if not entry then
		return nil
	end
	
	-- already loaded?
	-- appletEvaluated is TRUE while the applet is being loaded
	if entry.appletEvaluated and entry.appletEvaluated ~= true then
		return entry.appletEvaluated
	end

	return nil
end


-- _loadLocaleStrings
--
function _loadLocaleStrings(entry)
	if entry.stringsTable then
		return
	end

	log:debug("_loadLocaleStrings: ", entry.appletName)
	entry.stringsTable = locale:readStringsFile(entry.dirpath .. "strings.txt")
end


-- _loadSettings
--
function _loadSettings(entry)
	if entry.settings then
		-- already loaded
		return
	end

	log:debug("_loadSettings: ", entry.appletName)

	local fh = io.open(entry.settingsFilepath)
	if fh == nil then
		-- no settings file, look for legacy settings - remove legacy usage after in two public releases
		return _loadSettingsLegacy(entry)
	end

	local f, err = load(function() return fh:read() end)
	fh:close()

	if not f then
		log:error("Error reading ", entry.appletName, " settings: ", err)
	else
		-- evalulate the settings in a sandbox
		local env = {}
		setfenv(f, env)
		f()

		entry.settings = env.settings
	end
end

-- _loadSettingsLegacy - remove legacy usage after in two public releases
--
function _loadSettingsLegacy(entry)
	if entry.settings then
		-- already loaded
		return
	end

	log:debug("_loadSettingsLegacy: ", entry.appletName)

	local fh = io.open(entry.dirpath .. "settings.lua")
	if fh == nil then
		-- no settings file
		return
	end

	local f, err = load(function() return fh:read() end)
	fh:close()

	if not f then
		log:error("Error reading ", entry.appletName, " legacy settings: ", err)
	else
		-- evalulate the settings in a sandbox
		local env = {}
		setfenv(f, env)
		f()

		entry.settings = env.settings
	end
end

-- _getLoadPriority
--
function _getLoadPriority(appletDir)

	log:debug("_getLoadPriority: ", appletDir)

	local fh = io.open(appletDir .. "/" .. "loadPriority.lua")
	if fh == nil then
		-- no loadPriority file, retrun default priority
		return 100
	end

	local f, err = load(function() return fh:read() end)
	fh:close()

	if not f then
		log:error("Error reading ", appletDir, " loadPriority: ", err)
	else
		-- evalulate in a sandbox
		local env = {}
		setfenv(f, env)
		f()

		return env.loadPriority
	end
end


-- _storeSettings
--
function _storeSettings(entry)
	assert(entry)

	log:info("store settings: ", entry.appletName)

	System:atomicWrite(entry.settingsFilepath,
		dumper.dump(entry.settings, "settings", true))
end


-- freeApplet
-- frees the applet and all resources used. returns true if the
-- applet could be freed
function freeApplet(self, appletName)
	local entry = _appletsDb[appletName]
	
	-- exists?
	if not entry then
		log:error("Cannot free unknown applet: ", appletName)
		return
	end

	_freeApplet(self, entry)
end


-- _freeApplet
--
function _freeApplet(self, entry)
	log:debug("freeApplet: ", entry.appletName)

	if entry.appletEvaluated then

		local continue = true

		-- swallow any error
		local status, err = pcall(
			function()
				continue = entry.appletEvaluated:free()
			end
		)

		if continue == nil then
			-- warn if applet returns nil
			log:error(entry.appletName, ":free() returned nil")
		end

		if continue == false then
			-- the only way for continue to be false is to have the loaded applet have a free funtion
			-- that successfully executes and returns false.
			return
		end
	end
	
	log:debug("Freeing: ", entry.appletName)
	
	entry.appletEvaluated = false
	entry.appletLoaded = false
	package.loaded[entry.appletModule] = nil
end

function _getDefaultSettings(appletName)
	return _defaultSettingsByAppletName[appletName]
end

function _setDefaultSettings(appletName, settings)
	if not _defaultSettingsByAppletName[appletName] then
		_defaultSettingsByAppletName[appletName] = {}
	end
	_defaultSettingsByAppletName[appletName] = settings
end

function addDefaultSetting(self, appletName, settingName, settingValue)
	if not _defaultSettingsByAppletName[appletName] then
		_defaultSettingsByAppletName[appletName] = {}
	end
	_defaultSettingsByAppletName[appletName][settingName] = settingValue
end


function registerService(self, appletName, service)
	log:debug("registerService appletName=", appletName, " service=", service)

	if _services[service] then
		log:warn('WARNING: registerService called an already existing service name: ', service)
	end
	_services[service] = appletName

end


function hasService(self, service)
	log:debug("hasService service=", service)

	return _services[service] ~= nil
end


function callService(self, service, ...)
	log:debug("callService service=", service)

	local _appletName = _services[service]

	if not _appletName then
		return
	end

	local _applet = self:loadApplet(_appletName)
	if not _applet then
		return
	end

	return _applet[service](_applet, ...)
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

