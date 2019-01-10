
--[[
=head1 NAME

applets.SlimBrowser.SlimBrowserApplet - Browse music and control players.

=head1 DESCRIPTION

TODO

=head1 SYNOPSIS

TODO

=head1 FUNCTIONS

=cut
--]]

-- stuff we use
local tostring, tonumber, type, sort = tostring, tonumber, type, sort
local pairs, ipairs, select, _assert, bit = pairs, ipairs, select, _assert, bit

local oo                     = require("loop.simple")
local math                   = require("math")
local table                  = require("jive.utils.table")
local string                 = require("string")
local json                   = require("cjson")
                             
local Applet                 = require("jive.Applet")
local System                 = require("jive.System")
local Player                 = require("jive.slim.Player")
local SlimServer             = require("jive.slim.SlimServer")
local Framework              = require("jive.ui.Framework")
local Window                 = require("jive.ui.Window")
local Popup                  = require("jive.ui.Popup")
local Group                  = require("jive.ui.Group")
local Event                  = require("jive.ui.Event")
local Menu                   = require("jive.ui.Menu")
local Label                  = require("jive.ui.Label")
local Icon                   = require("jive.ui.Icon")
local Choice                 = require("jive.ui.Choice")
local Slider                 = require("jive.ui.Slider")
local Timer                  = require("jive.ui.Timer")
local Textinput              = require("jive.ui.Textinput")
local Timeinput              = require("jive.ui.Timeinput")
local Keyboard               = require("jive.ui.Keyboard")
local Textarea               = require("jive.ui.Textarea")
local RadioGroup             = require("jive.ui.RadioGroup")
local RadioButton            = require("jive.ui.RadioButton")
local Checkbox               = require("jive.ui.Checkbox")
local SimpleMenu             = require("jive.ui.SimpleMenu")
local Button                 = require("jive.ui.Button")
local DateTime               = require("jive.utils.datetime")
local ContextMenuWindow      = require("jive.ui.ContextMenuWindow")

local DB                     = require("applets.SlimBrowser.DB")
local Volume                 = require("applets.SlimBrowser.Volume")
local Scanner                = require("applets.SlimBrowser.Scanner")

local debug                  = require("jive.utils.debug")
-- log automatically assigned
local logd                   = require("jive.utils.log").logger("applet.SlimBrowser.data")

local jiveMain               = jiveMain
local appletManager          = appletManager
local iconbar                = iconbar
local jnt                    = jnt


module(..., Framework.constants)
oo.class(_M, Applet)


--[[

The 'step' contains the browser state for each request. It has the following
attributes:
	origin	- the parent step, or nil if this is a root
	sink	- the comet sink for this step
	db	- a sparse database of menu items and render state
	loaded	- an optional callback, called when this step has loaded
	window	- the steps window
	menu	- the steps menu
	data	- opaque data for the step
	cancelled	- a flag, set to true if the step is cancelled
	actionModifier	- action modifier (used for playlist actions)

XXXX I think these are unused attributes:
	destination - the child step

--]]


--==============================================================================
-- Local variables (globals)
--==============================================================================

-- The string function, for easy reference
local _string

-- The player we're browsing and it's server
local _player = false
local _server = false

local _networkError = false
local _serverError  = false
local _diagWindow   = false

-- The path of enlightenment
local _stepStack = {}

-- Our main menu/handlers
local _playerKeyHandler = false

-- The last entered text
local _lastInput = ""
local _inputParams = {}

-- legacy map of menuStyles to windowStyles
-- this allows SlimBrowser to make an educated guess at window style when one is not sent but a menu style is
local menu2window = {
	album    = 'icon_list',
	playlist = 'play_list',
}

-- legacy map of item styles to new item style names
local styleMap = {
	itemplay = 'item_play',
	itemadd  = 'item_add',
	itemNoAction = 'item_no_arrow',
	albumitem = 'item',
	albumitemplay = 'item_play',
}


--==============================================================================
-- Local functions
--==============================================================================


-- Forward declarations 
local _newDestination
local _actionHandler


-- _safeDeref
-- safely derefence a structure in depth
-- doing a.b.c.d will fail if b or c are not defined
-- _safeDeref(a, "b", "c", "d") will always work (of course, it returns nil if b or c are not defined!)
local function _safeDeref(struct, ...)
--	log:debug("_safeDeref()")
--	log:debug(struct)
	local res = struct
	for i=1, select('#', ...) do
		local v = select(i, ...)
		if type(res) ~= 'table' then return nil end
--		log:debug(v)
		if v then
			res = res[v]
			if not res then return nil end
		end
	end
--	log:debug("_safeDeref =>")
--	log:debug(res)
	return res
end

-- turns a jsonAction table into a string that can be saved for a browseHistory key
local function _stringifyJsonRequest(jsonAction)

	if not jsonAction then
		return nil
	end

	local command = {}

	-- jsonActions can be uniquely identified by the cmd and params components
	if jsonAction.cmd then
		for i, v in ipairs(jsonAction.cmd) do
			command[#command + 1] = ' ' .. v
		end
	end
	if jsonAction.params then
		local sortedParams = table.sort(jsonAction.params)
		for k in table.pairsByKeys (jsonAction.params) do
			if jsonAction.params[k] ~= json.null then
				command[#command + 1] = ' ' .. k .. ":" .. jsonAction.params[k]
			end
		end
	end

	return table.concat(command)
end

local function _getNewStartValue(index)
	-- start with the first item if we have no history
	if not index then
		return 0
	end
	local BLOCK_SIZE = DB:getBlockSize()

	-- if we have history, we want what is going to be the selected item to be included in the first chunk requested
	return math.floor(index/BLOCK_SIZE) * BLOCK_SIZE
end


-- _decideFirstChunk
-- figures out the from values for performJSONAction, including logic for finding the previous browse index in this list
local function _decideFirstChunk(step, jsonAction)
	local db = step.db
	local qty           = DB:getBlockSize()

	if not _player then
		return 0, qty
	end

	local isContextMenu = false
	if step and step.window and step.window:isContextMenu() then
		isContextMenu = true
	end

	local commandString = _stringifyJsonRequest(jsonAction)
	local lastBrowse    = _player:getLastBrowse(commandString)
	step.commandString = commandString

	local from = 0

	log:debug('Saving this json command to browse history table:')
	log:debug(commandString)


	-- don't save browse history for context menus or searches
	if lastBrowse and not isContextMenu and not string.match(commandString, 'search:') and not string.match(commandString, 'mode:randomalbums') then
		from = _getNewStartValue(_player:getLastBrowseIndex(commandString))
	else
		lastBrowse = { index = 1 }
		_player:setLastBrowse(commandString, lastBrowse)
	end

	log:debug('We\'ve been here before, lastBrowse index was: ', lastBrowse.index)
	step.lastBrowseIndexUsed = false

	--don't use lastBrowse index if position is first element, breaks windows that have zero sized menu (textarea, for example), and
	-- by default the first item is selected without the need of lastBrowse
	if _player:getLastBrowseIndex(commandString) == 1 then
		_player:setLastBrowseIndex(commandString, nil)
	end

	return from, qty

end

-- _priorityAssign(key, defaultValue, table1, table2, ...)
-- returns the first non nil value of table1[key], table2[key], etc.
-- if no table match, defaultValue is returned
local function _priorityAssign(key, defaultValue, ...)
--	log:debug("_priorityAssign(", key, ")")
	for i=1, select('#', ...) do
		local v = select(i, ...)
--		log:debug(v)
		if v then 
			local res = v[key]
			if res then return res end
		end
	end
	return defaultValue
end


local function _backButton(self)
	return Window:createDefaultLeftButton()
end


local function _invisibleButton(self)
	return Group("button_none", { Icon("icon") })
end


local function _nowPlayingButton(self, absolute)
	if not absolute then
		return Window:createDefaultRightButton()
	end

	return Button(
		Group("button_go_now_playing", { Icon("icon") }),
		function()
			Framework:pushAction("go_now_playing")
			return EVENT_CONSUME
		end,
		function()
			Framework:pushAction("title_right_hold") 
			return EVENT_CONSUME
		end,
		function()
			Framework:pushAction("soft_reset")
			return EVENT_CONSUME
		end
	)
end


local function _dumpStepStack()
	log:debug("---Step Stack")

	for i, step in ipairs(_stepStack) do
		if step.window then
			log:debug("window: ", step.window, " menu: ", step.menu)
		else
			log:debug("no window")
		end
	end

	log:debug("------Window Stack")
	for i, window in ipairs(Framework.windowStack) do
		if window then
			log:debug("window: ", window)
		else
			log:debug("no window")
		end
	end

end

local function _getCurrentStep()
	if #_stepStack == 0 then
		return nil
	end

	return _stepStack[#_stepStack]
end


local function _pushStep(step)
	--CM windows auto-hide, but step stack / window stack gets out of order unless we close any CM prior to pushing the next window
	if step.window and not step.window:isContextMenu() then
		Window:hideContextMenus()
	end
	
	table.delete(_stepStack, step) -- duplicate what window:hide does (deosn't allow same window on the stack twice)

	table.insert(_stepStack, step)
	if log:isDebug() then
		log:debug("Pushed")
		_dumpStepStack()
	end
end


local function _popStep()
	if #_stepStack == 0 then
		return nil
	end

	local popped = table.remove(_stepStack)

	if log:isDebug() then
		log:debug("Popped")
		_dumpStepStack()
	end

	return currentStep
end


local function _getGrandparentStep()
	if #_stepStack < 3 then
		return nil
	end

	return _stepStack[#_stepStack - 2]
end


local function _getParentStep()
	if #_stepStack < 2 then
		return nil
	end

	return _stepStack[#_stepStack - 1]
end


local function _stepSetMenuItems(step, data)
	step.menu:setItems(step, step.db:menuItems(data))
end


local function _stepLockHandler(step, loadedCallback, skipMenuLock)
	if not step then
		return
	end

	local currentStep = _getCurrentStep()
	if currentStep and currentStep.menu and not skipMenuLock then
		currentStep.menu:lock(
			function()
				step.cancelled = true
			end)
		if currentStep.simpleMenu then
			currentStep.simpleMenu:lock(
				function()
					step.cancelled = true
				end)
		end
	end
	step.loaded = function()
		if currentStep and currentStep.menu then
			currentStep.menu:unlock()
		end
		if currentStep and currentStep.simpleMenu then
			currentStep.simpleMenu:unlock()
		end

		loadedCallback()
      	end
end


-- skipMenuLock is given as true when no lock treatment is needed on the menu 
-- (e.g., for when _pushToWindow is being used outside a menu like in titlebar CM touch button)
local function _pushToNewWindow(step, skipMenuLock)
	_stepLockHandler(
		step,  
		function()
			_pushStep(step)
			step.window:show()
		end, 
		skipMenuLock
	)
end


-- _newWindowSpec
-- returns a Window spec based on the concatenation of base and item
-- window definition
local function _newWindowSpec(db, item, isContextMenu)
	log:debug("_newWindowSpec()")

	local bWindow
	local iWindow = _safeDeref(item, 'window')

	if db then
		bWindow = _safeDeref(db:chunk(), 'base', 'window')
	end
	
	local help = _safeDeref(item, 'window', 'help', 'text')

	-- determine style
	local menuStyle = _priorityAssign('menuStyle', "", iWindow, bWindow)
	local windowStyle = (iWindow and iWindow['windowStyle']) or menu2window[menuStyle] or 'text_list'
	local windowId = (bWindow and bWindow.windowId) or (iWindow and iWindow.windowId) or nil

	-- FIXME JIVELITE: special case of playlist - override server based windowStyle to play_list
	-- (requires another patch in _browseSink)
	if item.type and item.type == 'playlist' then
		windowStyle = "play_list"
	end

	return {
		["isContextMenu"]    = isContextMenu,
		['windowId']         = windowId,
		["windowStyle"]      = windowStyle,
		["labelTitleStyle"]  = 'title',
		["menuStyle"]        = "menu",
		["labelItemStyle"]   = "item",
		['help']             = help,
		["text"]             = _priorityAssign('text',       item["text"],    iWindow, bWindow),
		["icon-id"]          = _priorityAssign('icon-id',    item["icon-id"], iWindow, bWindow),
		["icon"]             = _priorityAssign('icon',       item["icon"],    iWindow, bWindow),
	} 

end


-- _artworkItem
-- updates a group widget with the artwork for item
local function _artworkItem(step, item, group, menuAccel)
	local icon = group and group:getWidget("icon")
	local iconSize

	-- FIXME JIVELITE: select icon size based on whether playlist icon or not - used for playlist in gridview
	if icon and icon:getStyle() == 'icon_no_artwork_playlist' then
		iconSize = jiveMain:getSkinParamOrNil("THUMB_SIZE_PLAYLIST") or jiveMain:getSkinParam("THUMB_SIZE")
	else
		iconSize = jiveMain:getSkinParam("THUMB_SIZE")
	end
	
	local iconId = item["icon-id"] or item["icon"]

	if iconId then
		if menuAccel and not _server:artworkThumbCached(iconId, iconSize) then
			-- Don't load artwork while accelerated
			_server:cancelArtwork(icon)
		else
			-- Fetch an image from SlimServer
			_server:fetchArtwork(iconId, icon, iconSize)
		end
	elseif item["trackType"] == 'radio' and item["params"] and item["params"]["track_id"] then
		if menuAccel and not _server:artworkThumbCached(item["params"]["track_id"], iconSize) then
			-- Don't load artwork while accelerated
			_server:cancelArtwork(icon)
               	else
			-- workaround: this needs to be png not jpg to allow for transparencies
			_server:fetchArtwork(item["params"]["track_id"], icon, iconSize, 'png')
		end
	else
		_server:cancelArtwork(icon)

	end
end

-- _getTimeFormat
-- loads SetupDateTime and returns current setting for date time format
local function _getTimeFormat()
	local SetupDateTimeSettings = appletManager:callService("setupDateTimeSettings")
	local format = '12'
	if SetupDateTimeSettings and SetupDateTimeSettings['hours'] then
		format = SetupDateTimeSettings['hours']
	end
	return format
end

-- _checkboxItem
-- returns a checkbox button for use on a given item
local function _checkboxItem(item, db)
	local checkboxFlag = tonumber(item["checkbox"])
	if checkboxFlag and not item["_jive_button"] then
		item["_jive_button"] = Checkbox(
			"checkbox",
			function(_, checkboxFlag)
				log:debug("checkbox updated: ", checkboxFlag)
				if (checkboxFlag) then
					log:info("ON: ", checkboxFlag)
					_actionHandler(nil, nil, db, nil, nil, 'on', item) 
				else
					log:info("OFF: ", checkboxFlag)
					_actionHandler(nil, nil, db, nil, nil, 'off', item) 
				end
			end,
			checkboxFlag == 1
		)
	end
	return item["_jive_button"]
end

-- _choiceItem
-- returns a choice set for use on a given item
local function _choiceItem(item, db)
	local choiceFlag = tonumber(item["selectedIndex"])
	local choiceActions = _safeDeref(item, 'actions', 'do', 'choices')

	if choiceFlag and choiceActions and not item["_jive_button"] then
		item["_jive_button"] = Choice(
			"choice",
			item['choiceStrings'],
			function(_, index) 
				log:info('Callback has been called: ', index) 
				_actionHandler(nil, nil, db, nil, nil, 'do', item, index) 
			end,
			choiceFlag
		)
	end
	return item["_jive_button"]
end


-- _radioItem
-- returns a radio button for use on a given item
local function _radioItem(item, db)
	local radioFlag = tonumber(item["radio"])
	if radioFlag and not item["_jive_button"] then
		item["_jive_button"] = RadioButton(
			"radio",
			db:getRadioGroup(),
			function() 
				log:info('Callback has been called') 
				_actionHandler(nil, nil, db, nil, nil, 'do', item) 
			end,
			radioFlag == 1
		)
	end
	return item["_jive_button"]
end


-- _decoratedLabel
-- updates or generates a label cum decoration in the given labelStyle
local function _decoratedLabel(group, labelStyle, item, step, menuAccel)
	local db = step.db
	local windowStyle = db:windowStyle() 

	-- if item is a windowSpec, then the icon is kept in the spec for nothing (overhead)
	-- however it guarantees the icon in the title is not shared with (the same) icon in the menu.
	local showIcons = true
	if windowStyle == 'text_list' then
		showIcons = false
	end
	
	-- if multiline_text_list is the window style, use a textarea not a Label for the text
	local useTextArea = false
	if windowStyle == 'multiline_text_list' then
		useTextArea = true
	end

	if not group then

		if labelStyle == 'title' then
			group = Group(labelStyle, { 
				text = Label("text", ""),
				icon = Icon("icon"), 
				lbutton = _backButton(),
				rbutton = _nowPlayingButton(),
			})
		elseif useTextArea then
			local textarea = Textarea("multiline_text", "")
			textarea:setHideScrollbar(true)
			textarea:setIsMenuChild(true)
			group = Group(labelStyle, {
				icon  = Icon("icon"), 
				text  = textarea, 
				arrow = Icon('arrow'),
				check = Icon('check'),
			})
			

		else
			local textLabel = Label("text", "")
			--label never changes the group size, so optimize it with layoutRoot, layout won't trickle up the chain now
			textLabel.layoutRoot = true

			group = Group(labelStyle, { 
				icon = Icon("icon"), 
				text = textLabel, 
				arrow = Icon('arrow'),
				check = Icon('check'),
			})
		end
	end

	if item then
		-- special case here. windows that use Textareas for their text widget have a 
		-- + handler for bringing up a context menu window that has the entirety of the text
		if useTextArea then
			local moreAction = function()
				local window = ContextMenuWindow("")
				local text = Textarea('multiline_text', item.text)
				window:addWidget(text)
				window:setShowFrameworkWidgets(false)
				window:show(Window.transitionFadeIn)
				return EVENT_CONSUME
			end		
			group:addActionListener('add', step, moreAction)
			group:addActionListener('go', step, moreAction)
		end

		group:setWidgetValue("text", item.text)

		-- FIXME JIVELITE: select icon style based on whether window is playlist or not
		local iconStyle = 'icon_no_artwork'
		if windowStyle == 'play_list' then
			iconStyle = 'icon_no_artwork_playlist'
		end

		if showIcons then
			--set "no artwork" unless it has already been set (avoids high cpu looping)
			local iconWidget = group:getWidget('icon')
			if iconWidget then
				if group:getWidget('icon'):getStyle() ~= iconStyle then
					group:setWidget('icon', Icon(iconStyle))
				end
			end
		end

		-- set an acceleration key, but not for playlists
		if item.textkey or (item.params and item.params.textkey) then
			-- FIXME the, el, la, etc articles
			group:setAccelKey(item.textkey or item.params.textkey)
		end

		if item["radio"] then
			group._type = "radio"
			group:setWidget("check", _radioItem(item, db))

		elseif item["checkbox"] then
			group._type = "checkbox"
			group:setWidget("check", _checkboxItem(item, db))

		elseif item['selectedIndex'] then
			group._type = 'choice'
			group:setWidget('check', _choiceItem(item, db))

		else
			if group._type then
				if showIcons then
					group:setWidget("icon", Icon(iconStyle))
				end
				group._type = nil
			end
			_artworkItem(step, item, group, menuAccel)
		end
		group:setStyle(labelStyle)

	else
		if group._type then
			if showIcons then
				group:setWidget("icon", Icon(iconStyle))
			end
			group._type = nil
		end

		group:setWidgetValue("text", "")
		group:setStyle(labelStyle .. "waiting_popup")
	end

	return group
end


-- _performJSONAction
-- performs the JSON action...
local function _performJSONAction(jsonAction, from, qty, step, sink, itemType, cachedResponse)
	log:debug("_performJSONAction(from:", from, ", qty:", qty, "):")

	local useCachedResponse = false
	if cachedResponse and type(cachedResponse) == 'table' then
	        log:warn("using cachedResponse: ", cachedResponse)
		useCachedResponse = true
	end
	

	local cmdArray = jsonAction["cmd"]
	-- sanity check
	if not cmdArray or type(cmdArray) ~= 'table' then
		log:error("JSON action for ", actionName, " has no cmd or not of type table")
		return
	end
	
	-- replace player if needed
	local playerid = jsonAction["player"]
	if _player and (not playerid or tostring(playerid) == "0") then
		playerid = _player:getId()
	end
	
	-- look for multiple input keys in inputParamKeys
	local newparams = {}
	local inputParamKeys = jsonAction['inputParamKeys']
	if inputParamKeys then
		newparams = {}
		for k, v in pairs(inputParamKeys) do
			table.insert( newparams, k .. ":" .. v)
		end
	end

	-- look for __INPUT__ as a param value
	local params = jsonAction["params"]
	if params then
		newparams = {}
		for k, v in pairs(params) do
			if v == '__INPUT__' then
				table.insert( newparams, _lastInput )
			elseif v == '__TAGGEDINPUT__' then
				table.insert( newparams, k .. ":" .. _lastInput )
			else
				if v ~= json.null then
					table.insert( newparams, k .. ":" .. v )
				end
			end
		end
		-- tells SC to give response that includes context menu handler
		table.insert( newparams, 'useContextMenu:1')
	end
	
	local request = {}
	
	for i, v in ipairs(cmdArray) do
		table.insert(request, v)
	end
	
	table.insert(request, from)
	table.insert(request, qty)
	
	for i, v in ipairs(newparams) do
		table.insert(request, v)
	end

	if step then
		step.jsonAction = request
	end

	if itemType == "slideshow" or (params and params["slideshow"]) then
		table.insert( request, 'slideshow:1')
		
		local serverData = {}
		serverData.id = table.concat(request, " ")
		serverData.playerId = playerid
		serverData.cmd = request
		serverData.server = _server
		serverData.appParameters = _server:getAppParameters(_getAppType(request))
		serverData.allowMotion = true

		appletManager:callService("openRemoteScreensaver", true, serverData)

		local currentStep = _getCurrentStep()
		if currentStep and currentStep.menu then
			currentStep.menu:unlock()
		end

		return
	end

	-- it's very helpful at times to dump the request table here to see what command is being issued
	 --debug.dump(request)

	-- there's an existing network or server error, so trap this request and push to a diags troubleshooting window
	-- Bug 15662: don't push a diags window when tinySC is available on the system and running
	if _networkError and not ( System:hasTinySC() and appletManager:callService("isBuiltInSCRunning") ) then
		log:warn('_networkError is not false, therefore push on an error window for diags')
		local currentStep = _getCurrentStep()
		_diagWindow = appletManager:callService("networkTroubleshootingMenu", _networkError)
		-- make sure we got a window generated to confirm we can leave this method
		if _diagWindow then
			-- FIXME: this part doesn't work. Menu item on home menu shows "locked" spinny icon after hitting back arrow from diags window
			if currentStep then
				if currentStep.menu then
					currentStep.menu:unlock()
				end
			end
			return
		end
	end

	if not useCachedResponse then
		-- send the command
		_server:userRequest(sink, playerid, request)
	else
                log:info("using cachedResponse")
		sink(cachedResponse)
	end
end


function _getAppType(request)
	if not request or #request == 0 then
		return nil
	end
	local appType = request[1]

	return appType
end


-- for a given step, rerun the json request that created that slimbrowser menu
local function _refreshJSONAction(step)
	if not _player then
		return
	end

	if not step.jsonAction then
		log:warn('No jsonAction request defined for this step')
		return
	end

	local playerid = _player:getId()
	if not playerid then
		log:warn('no player!')
		return
	end

	_server:userRequest(step.sink, playerid, step.jsonAction)

end

-- _inputInProgress
-- full screen popup that appears until action from text input is complete
local function _inputInProgress(self, msg)
	local popup = Popup("waiting_popup")
	local icon  = Icon("icon_connecting")
	popup:addWidget(icon)
	if msg then
		local label = Label("text", msg)
		popup:addWidget(label)
	end
	popup:show()
end


-- _renderSlider
-- special case when SlimBrowse item is configured for a slider widget
local function _renderSlider(step, item)

	log:debug('_renderSlider()')
	if not step and step.window then
		return
	end
	_assert(item)
	_assert(item.min)
	_assert(item.max)
	_assert(item.actions['do'])

	if not item.adjust then
		item.adjust = 0
	end

	local sliderInitial
	if not item.initial then
		sliderInitial = item.min + item.adjust
	else
		sliderInitial = item.initial + item.adjust
	end

	local sliderMin = tonumber(item.min) + tonumber(item.adjust)
	local sliderMax = tonumber(item.max) + tonumber(item.adjust)

	local slider = Slider("settings_slider", sliderMin, sliderMax, sliderInitial,
                function(slider, value, done)
			local jsonAction = item.actions['do']
			local valtag = _safeDeref(item, 'actions', 'do', 'params', 'valtag')
			if valtag then
				item.actions['do'].params[valtag] = value - item.adjust
			end
			_performJSONAction(jsonAction, nil, nil, nil, nil)
			--[[ FIXME - this would never have worked!
                        if done then
                                window:playSound("WINDOWSHOW")
                                window:hide(Window.transitionPushLeft)
							end
			--]]
                end)
	local help, text
	if item.text then
		text = Textarea("text", item.text)
		step.window:addWidget(text)
	end
	if item.help then
        	help = Textarea("help_text", item.help)
		step.window:addWidget(help)
	end

	local sliderStyle
	if item.sliderIcons == 'volume' then
		sliderStyle = 'settings_volume_group'
	else
		sliderStyle = 'settings_slider_group'
	end

	step.window:addWidget(Group(sliderStyle, {
		div1 = Icon('div1'),
		div2 = Icon('div2'),
		down  = Button(
			Icon('down'),
				function()
					local e = Event:new(EVENT_SCROLL, -1)
					Framework:dispatchEvent(slider, e)
					return EVENT_CONSUME
				end
                               ),
		slider = slider,
		up  = Button(
			Icon('up'),
				function()
					local e = Event:new(EVENT_SCROLL, 1)
					Framework:dispatchEvent(slider, e)
					return EVENT_CONSUME
				end
                       ),
	}))



end


-- add a help button to a window with the data from the help arg delivered in the help window
local function _addHelpButton(self, help, setupWindow, menu)
	local titleText = self:getTitle()
	local helpWindow = function()
		Framework:playSound('WINDOWSHOW')
		local window = Window("text_list")
		window:setAllowScreensaver(false)
		local nowPlaying = _nowPlayingButton()
		if setupWindow == 1 then
			nowPlaying = _invisibleButton()
		end
		window:setTitleWidget(
			Group('title', { 
				text = Label("text", titleText), 
				lbutton = _backButton(),
				rbutton = nowPlaying,
			})	
		)
		local textarea = Textarea("text", help)
		window:addWidget(textarea)
		window:show()
	end
	self:addActionListener("help", _, helpWindow)
	self:setButtonAction("rbutton", "help")
	if menu then
		jiveMain:addHelpMenuItem(menu, self, helpWindow)
	end

end
	

-- _bigArtworkPopup
-- special case sink that pops up big artwork
local function _bigArtworkPopup(chunk, err)

	log:debug("Rendering artwork")
	local popup = Popup("image_popup")
	popup:setAllowScreensaver(true)

	local icon = Icon("image")

	local screenW, screenH = Framework:getScreenSize()
	local shortDimension = screenW
	if screenW > screenH then
		shortDimension = screenH
	end
	
	local artworkId
	if chunk.data then
		artworkId = chunk.data.artworkId or chunk.data.artworkUrl
	end

	log:debug("Artwork width/height will be ", shortDimension)
	if artworkId then
		_server:fetchArtwork(artworkId, icon, shortDimension)
	end
	popup:addWidget(icon)
	popup:show()
	return popup
end


local function _refreshMe(setSelectedIndex)
	local step = _getCurrentStep()
	if step then
		local timer = Timer(100,
			function()
				_refreshJSONAction(step)
				if step.menu and setSelectedIndex then
					step.menu:setSelectedIndex(setSelectedIndex)
					step.lastBrowseIndexUsed = setSelectedIndex
				end
			end, true)
		timer:start()
	end

end

local function _refreshGrandparent(setSelectedIndex)
	local step = _getGrandparentStep()
	if step then
		local timer = Timer(100,
			function()
				_refreshJSONAction(step)
				if step.menu and setSelectedIndex then
					step.menu:setSelectedIndex(setSelectedIndex)
					step.lastBrowseIndexUsed = setSelectedIndex
				end
			end, true)
		timer:start()
	end
end


local function _refreshOrigin(setSelectedIndex)
	local step = _getParentStep()
	if step then
		local timer = Timer(100,
			function()
				_refreshJSONAction(step)
				if step.menu and setSelectedIndex then
					step.menu:setSelectedIndex(setSelectedIndex)
					step.lastBrowseIndexUsed = setSelectedIndex
				end
				if step.window and step.simpleMenu then
					-- Bug 16336, ghosted menu over menu after refreshing origin
					log:warn('removing simpleMenu overlay when refreshing origin')
					step.window:removeWidget(step.simpleMenu)
				end
			end, true)
		timer:start()
	end
end


-- _hideMe
-- hides the top window and refreshes the parent window, via a new request. Optionally, noRefresh can be set to true and the parent window will not be refreshed
local function _hideMe(noRefresh, silent, setSelectedIndex)

	if not silent then
		Framework:playSound("WINDOWHIDE")
	end
	_getCurrentStep().window:hide()

	--hiding triggers a stepStack pop, so no need to do it here

	local currentStep = _getCurrentStep()
	if currentStep and not noRefresh then
		local timer = Timer(1000,
			function()
				_refreshJSONAction(currentStep)
				if currentStep.menu and setSelectedIndex then
					currentStep.menu:setSelectedIndex(setSelectedIndex)
					currentStep.lastBrowseIndexUsed = setSelectedIndex
				end
			end, true)
		timer:start()
	end
end

-- _hideToX
-- hides all windows back to window named X, or top of stack, whichever comes first
local function _hideToX(windowId, setSelectedIndex)
	log:debug("_hideToX, x=", windowId)

	while _getCurrentStep() and _getCurrentStep().window and _getCurrentStep().window:getWindowId() ~= windowId do
		log:info('hiding ', _getCurrentStep().window:getWindowId())
		_getCurrentStep().window:hide()
	end

	if _getCurrentStep() and _getCurrentStep().window and _getCurrentStep().window:getWindowId() == windowId then
		log:info('refreshing window: ', windowId)
		local timer = Timer(1000,
			function()
				local currentStep = _getCurrentStep()
				_refreshJSONAction(currentStep)
				if _getCurrentStep().menu and setSelectedIndex then
					_getCurrentStep().menu:setSelectedIndex(setSelectedIndex)
					_getCurrentStep().lastBrowseIndexUsed = setSelectedIndex
				end
			end, true)
		timer:start()
	end

end


-- _hideMeAndMyDad
-- hides the top window and the parent below it, refreshing the 'grandparent' window via a new request
local function _hideMeAndMyDad(setSelectedIndex)
	log:debug("_hideMeAndMyDad")

	_hideMe(true)
	_hideMe(_, _, setSelectedIndex)
end

-- _goNowPlaying
-- pushes next window to the NowPlaying window
local function _goNowPlaying(transition, silent, direct)
	Window:hideContextMenus()
	
	--first hide any "NP related" windows (playlist, track info) that are on top
	while _getCurrentStep() and _getCurrentStep()._isNpChildWindow do
		log:info("Hiding NP child window")

		_hideMe(true, true)

	end

	if not transition then
		transition = Window.transitionPushLeft
	end
	if not silent then
		Framework:playSound("WINDOWSHOW")
	end
	appletManager:callService('goNowPlaying', transition, direct)
end

-- _goPlaylist
-- pushes next window to the Playlist window
local function _goPlaylist(silent)
	if not silent then
		Framework:playSound("WINDOWSHOW")
	end
	showPlaylist()
end

-- _devnull
-- sinks that silently swallows data
-- used for actions that go nowhere (play, add, etc.)
local function _devnull(chunk, err)
	log:debug('_devnull()')
	log:debug(chunk)
end


--destination that does nothing, but handles step.cancelled and step.loaded
local function _emptyDestination(step)
	local step = {}

	step.sink = function(chunk, err)
		-- are we cancelled?
		if step.cancelled then
			log:debug("_devnull(): , action cancelled...")
			return
		end

		if step.loaded then
			step.loaded()
			step.loaded = nil
		end
	end

	return step, step.sink
end


-- _goNow
-- go immediately to a particular destination
local function _goNow(destination, transition)
	if not transition then
		transition = Window.transitionPushRight
	end
	if destination == 'nowPlaying' then
		_goNowPlaying(transition)
	elseif destination == 'home' then
		goHome()
	elseif destination == 'playlist' then
		_goPlaylist()
	end
end

-- _browseSink
-- sink that sets the data for our go action
local function _browseSink(step, chunk, err)
	log:debug("_browseSink()")

	-- are we cancelled?
	if step.cancelled then
		log:debug("_browseSink(): ignoring data, action cancelled...")
		return
	end

	-- function to perform when the data is loaded? 
	if step.loaded then
		step.loaded()
		step.loaded = nil
	end

	if chunk then
		local data

		-- move result key up to top-level
		if chunk.result then
			data = chunk.result
		else
			data = chunk.data
		end
		if logd:isDebug() then
			debug.dump(chunk, 8)
		end

		if step.window and data and data.goNow then
			_goNow(data.goNow)
		end

		local useSimpleMenuOverlay = false
		if _safeDeref(data, 'window', 'textarea') or _safeDeref(data, 'window', 'textareaToken') then
			useSimpleMenuOverlay = true
		end

		local setupWindow = _safeDeref(data, 'base', 'window', 'setupWindow')
		if step.window and setupWindow then
			step.window:setAllowScreensaver(false)
		end

		if data.networkerror then
			if step.menu then
				step.window:removeWidget(step.menu)
			end
			local textArea = Textarea("text", data.networkerror)
			if step.window then
				step.window:setTitle(_string("SLIMBROWSER_PROBLEM_CONNECTING"), 'settingstitle')
				step.window:addWidget(textArea)
			end
		elseif data and data.count and tonumber(data.count) == 1 and data.item_loop and data.item_loop[1].slider then
			-- no menus here, thankyouverymuch
			if step.menu then
				step.window:removeWidget(step.menu)
			end

			_renderSlider(step, data.item_loop[1])

		-- avoid infinite request loop on count == 0
		elseif step.menu and data and data.count and tonumber(data.count) == 0 then
			-- this will render a blank menu, which is typically undesirable 
			-- but we don't want to reach the next clause
			-- count == 0 responses should not be typical

			--textarea only case
			if step.window and data and data.window and data.window.textarea then
				if step.menu then
					step.window:removeWidget(step.menu)
				end
				local text = string.gsub(data.window.textarea, '\\n', '\n')
				local textArea = Textarea("text", text)
				step.window:addWidget(textArea)
			end
		elseif step.menu then

			-- FIXME JIVELITE: override server based icon_list style for playlists...
			-- (requires another patch in _newWindowSpec)
			if step.window and step.window:getStyle() == 'play_list' then
				if data.window.windowStyle == 'icon_list' then
					log:debug("overriding server based playlist window style")
					data.window.windowStyle = 'play_list'
				end
			end

			_stepSetMenuItems(step, data)

			if _player then
				local lastBrowseIndex = _player:getLastBrowseIndex(step.commandString)
				-- we don't do browse history callback when we're using a simple menu overlay so the help text doesn't get lost
				if lastBrowseIndex and not step.lastBrowseIndexUsed and not useSimpleMenuOverlay then
					log:debug("Selecting  lastBrowseIndex: ", lastBrowseIndex)
					step.menu:setSelectedIndex(lastBrowseIndex)
					step.lastBrowseIndexUsed = true
					if _player.loadedCallback then
						local loadedCallback = _player.loadedCallback
						_player.loadedCallback = nil

						loadedCallback(step)
						_pushStep(step)
						step.window:show()

					end
				end
			end

			-- update the window properties
			--step.menu:setStyle(step.db:menuStyle())
			local titleBar = step.window:getTitleWidget()
			-- styling both the menu and title with icons is problematic to the layout
			if step.db:menuStyle() == 'albummenu' and titleBar:getStyle() == 'albumtitle' then
				titleBar:setWidget('icon', nil)
				step.window:setTitleStyle('title')
			end

			if data.window and data.window.windowId then
				step.window:setWindowId(data.window.windowId)
			end

			if not data.window and (data.base and data.base.window) then
				data.window =  data.base.window
			end
			if not step.window:isContextMenu() and (data.window or data.base and data.base.window) then
				local windowStyle = data.window and data.window.windowStyle or
							data.base and data.base.window and data.base.window.windowStyle
				if windowStyle then
					step.window:setStyle(data.window['windowStyle'])
				end
				-- if a titleStyle is being sent or prevWindow or setupWindow params are given, we need to setTitleWidget completely
				if data.window.titleStyle or data.window['icon-id'] or data.window['icon'] or data.window.setupWindow == 1 or data.window.prevWindow == 0 then

					local titleText, titleStyle, titleIcon
					local titleWidget = step.window:getTitleWidget()
					-- set the title text if specified
					if data.window.text then
						titleText = data.window.text
					-- otherwise default back to what's currently in the title widget
					else	
						titleText = step.window:getTitle()
						if not titleText then
							log:warn('no title found in existing title widget')
							titleText = ''
						end
					end
					if data.window.titleStyle then
						titleStyle = data.window.titleStyle .. 'title'
					else
						titleStyle = step.window:getTitleStyle()
					end
					
					-- add the icon if it's been specified in the window params
					local iconId = data.window['icon-id'] or data.window['icon']
					if iconId then
						-- Fetch an image from SlimServer
						titleIcon = Icon("icon")
						_server:fetchArtwork(iconId, titleIcon, jiveMain:getSkinParam("THUMB_SIZE"))
					-- only allow the existing icon to stay if titleStyle isn't being changed
					elseif not data.window.titleStyle and titleWidget:getWidget('icon') then
						titleIcon = titleWidget:getWidget('icon')
					else
						titleIcon = Icon("icon")
					end
					
					local backButton, nowPlayingButton
					if data.window.prevWindow == 0 then
						backButton = _invisibleButton()
					else
						backButton = _backButton()
					end
					if data.window.setupWindow == 1 then
						nowPlayingButton = _invisibleButton()
					else
						nowPlayingButton = _nowPlayingButton()
					end

					local newTitleWidget = 
						Group('title', { 
							text = Label("text", titleText), 
							icon = titleIcon,
							lbutton = backButton,
							rbutton = nowPlayingButton,
						})	
					step.window:setTitleWidget(newTitleWidget)
				-- change the text as specified if no titleStyle param was also sent
				elseif data.window.text then
					step.window:setTitle(data.window.text)
				elseif data.title then
					step.window:setTitle(data.title)
				end

				-- textarea data for the window
				if data.window and ( data.window.textarea or data.window.textareaToken ) then

					if data.window.textareaToken then
						data.window.textarea = _string(data.window.textareaToken)
					end

					local text = string.gsub(tostring(data.window.textarea), '\\n', "\n")
					local textarea = Textarea('help_text', text)
					if step.menu then
						local item_loop = _safeDeref(step.menu, 'list', 'db', 'last_chunk', "item_loop")
						if item_loop then
							local maxItems = 100
							if #item_loop > maxItems then
								log:warn("item_loop exceeds max items, not showing textarea: ", #item_loop)
							else
								step.menu:setStyle("menu_hidden")
								-- Make a SimpleMenu to support headerWidget, in place of the step menu, but keep the step menu around, which has the item listener logic
								local menu = SimpleMenu("menu")

								step.simpleMenu = menu
								for i, item in ipairs(item_loop) do
									if item.text then
										menu:addItem( {
												text = item.text,
												sound = "WINDOWSHOW",
												callback = function(event, menuItem)
													--hack alert, selecting item from hidden step menu, but since not really rendered, forcing numWidgets size to 100 so all
													--  step menu widgets are available. Limits menu size to maxItems for menus with textarea
													step.menu:setSelectedIndex(i)
													step.menu.numWidgets = maxItems
													step.menu:_updateWidgets()
													step.menu:_event(Event:new(EVENT_ACTION))
												end,
										})
									end
								end

								if data.window and data.window.help  then
									_addHelpButton(step.window, data.window.help, data.window.setupWindow, menu)
								end


								step.window:addWidget(menu)
								menu:setHeaderWidget(textarea)
							end

						else
							log:warn("Can't extract item loop, not showing textarea")

						end
					end
				end
				-- contextual help comes from data.window.help
				if data.window and data.window.help and not data.window.textarea then
					_addHelpButton(step.window, data.window.help, data.window.setupWindow, step.menu)
				end
			end

			-- what's missing?
			local lastBrowseIndex = _player and _player:getLastBrowseIndex(step.commandString)
			local from, qty = step.db:missing(lastBrowseIndex)

			if from then
				_performJSONAction(step.data, from, qty, step, step.sink)
			end
		end
		
	else
		log:error(err)
	end
end



-- _globalActions
-- provides a function for default button behaviour, called outside of the context of the browser
local _globalActions = {
	["rew"] = function()
	        Framework:playSound("PLAYBACK")
		_player:rew()
		return EVENT_CONSUME
	end,

	["rew-hold"] = function(self, event)
		return self.scanner:event(event)
	end,

	["fwd"] = function()
	        Framework:playSound("PLAYBACK")
		_player:fwd()
		return EVENT_CONSUME
	end,

	["fwd-hold"] = function(self, event)
		return self.scanner:event(event)
	end,

	["volup-down"] = function(self, event)
		return self.volume:event(event)
	end,

	["volup"] = function(self, event)
		return self.volume:event(event)
	end,

	["voldown-down"] = function(self, event)
		return self.volume:event(event)
	end,
	["voldown"] = function(self, event)
		return self.volume:event(event)
	end,
--[[	
	["go-hold"] = function(self, event)
		return self.scanner:event(event)
	end,
--]]
}


function _goMenuTableItem(key)
	if jiveMain:getMenuTable()[key] then
		if Window:getTopNonTransientWindow():getWindowId() == key then
			Framework:playSound("BUMP")
			Window:getTopNonTransientWindow():bumpLeft()
		else
			Framework:playSound("JUMP")
			jiveMain:getMenuTable()[key].callback(nil, nil, true)
		end
	end
end

function _goNowPlayingAction()
	_goNow('nowPlaying', Window.transitionPushLeft)
	return EVENT_CONSUME
end

function _goSearchAction()
	local player = appletManager:callService("getCurrentPlayer")

--	if player and player:getSlimServer() and not player:getSlimServer():isSqueezeNetwork() then
--		_goMenuTableItem("opmlsearch")
--	else
		_goMenuTableItem("globalSearch")
--		_goMenuTableItem("myMusicSearch")
--	end                                            

	return EVENT_CONSUME
end

function _goMusicLibraryAction()
	_goMenuTableItem("_myMusic")
	return EVENT_CONSUME
end


function _goPlaylistAction()
	_goPlaylist()
	return EVENT_CONSUME
end


function _goFavoritesAction()
	_goMenuTableItem("favorites")
	return EVENT_CONSUME
end


function _goPlaylistsAction()
	_goMenuTableItem("myMusicPlaylists")
	return EVENT_CONSUME
end


function _goRhapsodyAction()
	_goMenuTableItem("opmlrhapsodydirect")
	return EVENT_CONSUME
end

function _goAlarmsAction()
	_goMenuTableItem("settingsAlarm")
	return EVENT_CONSUME
end


function _goBrightnessAction()
	_goMenuTableItem("settingsBrightness")
	return EVENT_CONSUME
end

function _goSettingsAction()
	_goMenuTableItem("settings")
	return EVENT_CONSUME
end


function _goRepeatToggleAction()
	_player:repeatToggle()
	return EVENT_CONSUME
end


function _goShuffleToggleAction()
	_player:shuffleToggle()
	return EVENT_CONSUME
end


function _goSleepAction()
	_player:sleepToggle()
	return EVENT_CONSUME
end


function _goPlayPresetAction(self, event)
	local action = event:getAction()
	local number = string.sub(action, -1 , -1)
	if not number or not string.find(number, "%d") then
		log:error("Expected last character of action string would be numeric, for action :", action)
		return EVENT_CONSUME
	end

	if _player and _player:isPresetDefined(tonumber(number)) then
		_player:presetPress(number)
		_goNowPlayingAction()
	else
		Framework:playSound("BUMP")
		Window:getTopNonTransientWindow():bumpLeft()
	end

	return EVENT_CONSUME
end


function _goCurrentTrackInfoAction()
	showCurrentTrack()
	return EVENT_CONSUME	
end

-- _globalActions
-- provides a function for default button behaviour, called outside of the context of the browser
--TRANSITIONING from old _globalAction style to new system wide action event model, will rename this when old one is eliminated
--not sure yet how to deal with things like rew and vol which need up/down/press considerations
local _globalActionsNEW = {

	["go_now_playing"] = _goNowPlayingAction,
	["go_now_playing_or_playlist"] = _goNowPlayingAction,
	["go_playlist"] = _goPlaylistAction,
	["go_search"] = _goSearchAction,
	["go_favorites"] = _goFavoritesAction,
	["go_playlists"] = _goPlaylistsAction,
	["go_music_library"] = _goMusicLibraryAction,
	["go_rhapsody"] = _goRhapsodyAction,
	["go_alarms"] = _goAlarmsAction,
	["go_current_track_info"] = _goCurrentTrackInfoAction,
	["repeat_toggle"] = _goRepeatToggleAction,
	["shuffle_toggle"] = _goShuffleToggleAction,
	["sleep"] = _goSleepAction,
	["go_settings"] = _goSettingsAction,
	["go_brightness"] = _goBrightnessAction,
	["play_preset_0"] = _goPlayPresetAction,
	["play_preset_1"] = _goPlayPresetAction,
	["play_preset_2"] = _goPlayPresetAction,
	["play_preset_3"] = _goPlayPresetAction,
	["play_preset_4"] = _goPlayPresetAction,
	["play_preset_5"] = _goPlayPresetAction,
	["play_preset_6"] = _goPlayPresetAction,
	["play_preset_7"] = _goPlayPresetAction,
	["play_preset_8"] = _goPlayPresetAction,
	["play_preset_9"] = _goPlayPresetAction,
	
	["go_home_or_now_playing"] = function()
		local windowStack = Framework.windowStack

		-- are we in home?
		if #windowStack > 1 then
			_goNow('home')
		else
			_goNow('nowPlaying', Window.transitionPushLeft)
		end

		return EVENT_CONSUME
	end,

	["go_home"] = function()
		_goNow('home')
		return EVENT_CONSUME
	end,

	["play"] = function()
	        Framework:playSound("PLAYBACK")
	        if _player:getPlaylistSize() and _player:getPlaylistSize() > 0 and _player:getPlayMode() ~= 'play' then
			_player:play()
			return EVENT_CONSUME
		else
			return EVENT_UNUSED
		end
	end,

	["pause"] = function()
	        Framework:playSound("PLAYBACK")
		_player:togglePause()
		return EVENT_CONSUME
	end,

	["stop"] = function()
	        Framework:playSound("PLAYBACK")
		_player:stop()
		return EVENT_CONSUME
	end,

	["mute"] = function(self, event)
		return self.volume:event(event)
	end,

	["volume_up"] = function(self, event)
		return self.volume:event(event)
	end,

	["volume_down"] = function(self, event)
		return self.volume:event(event)
	end,

	["jump_rew"] = function()
	        Framework:playSound("PLAYBACK")
		_player:rew()
		return EVENT_CONSUME
	end,
	["jump_fwd"] = function()
	        Framework:playSound("PLAYBACK")
		_player:fwd()
		return EVENT_CONSUME
	end,


	["scanner_rew"] = function(self, event)
		return self.scanner:event(event)
	end,

	["scanner_fwd"] = function(self, event)
		return self.scanner:event(event)
	end,

	["quit"] = function()
		-- disconnect from Player/SqueezeCenter
		appletManager:callService("disconnectPlayer")
		return (bit.bor(EVENT_CONSUME, EVENT_QUIT))
	end,
}


-- _defaultActions
-- provides a function for each actionName for which Jive provides a default behaviour
-- the function prototype is the same than _actionHandler (i.e. the whole shebang to cover all cases)
local _defaultActions = {
	
	-- default commands in Now Playing
	
	["play-status"] = function(_1, _2, _3, dbIndex)
		if _player:isPaused() and _player:isCurrent(dbIndex) then
			_player:togglePause()
		else
			-- the DB index IS the playlist index + 1
			_player:playlistJumpIndex(dbIndex)
		end
		return EVENT_CONSUME
	end,

	--FIXME: add and add-hold should instead be delivered by the context menu
	["add-status"] = function(_1, _2, _3, dbIndex)
		_player:playlistDeleteIndex(dbIndex)
		return EVENT_CONSUME
	end,

	["add-hold-status"] = function(_1, _2, _3, dbIndex)
		_player:playlistZapIndex(dbIndex)
		return EVENT_CONSUME
	end,

}

-- Liberace says: "touch is play"
_defaultActions['go-status'] = _defaultActions['play-status']


--maps actionName to item action alias
local _actionAliasMap = {
	["play"]      = "playAction",
	["play-hold"] = "playHoldAction",
	["add"]       = "addAction",
	["go"]        = "goAction",	
}


-- _actionHandler
-- sorts out the action business: item action, base action, default action...
_actionHandler = function(menu, menuItem, db, dbIndex, event, actionName, item, selectedIndex)
	log:debug("_actionHandler(", actionName, ")")

	if log:isDebug() then
--		debug.dump(item, 4)
	end

	local choiceAction

	-- some actions work (f.e. pause) even with no item around
	if item then
		local chunk = db:chunk()
		local bAction
		local iAction
		local onAction
		local offAction
		local nextWindow
		--nextWindow on the base
		local bNextWindow
		--nextWindow on the item
		local iNextWindow
		--nextWindow on the action
		local aNextWindow

		-- cache context menu actions for next window
		local bActionContextMenu
		local iActionContextMenu
		
		-- setSelectedIndex will set the selected index of a menu. To be used in concert with nextWindow
		local iSetSelectedIndex
		local bSetSelectedIndex
		local aSetSelectedIndex

		-- onClick handler, for allowing refreshes of this window when using a checkbox/radio/choice item (or 1 above, or 2 steps above)
		local iOnClick
		local bOnClick
		
		-- we handle no action in the case of an item telling us not to
		if item['action'] == 'none' then
			return EVENT_UNUSED
		end

		-- dissect base and item for nextWindow params
		bNextWindow = _safeDeref(chunk, 'base', 'nextWindow')
		iNextWindow = item['nextWindow']

		-- same for setSelectedIndex
		bSetSelectedIndex = _safeDeref(chunk, 'base', 'setSelectedIndex')
		iSetSelectedIndex = item['setSelectedIndex']
		
		bOnClick = _safeDeref(chunk, 'base', 'onClick')
		iOnClick = item['onClick']
		local onClick = iOnClick or bOnClick -- item onClick wins over base onClick

		local useNextWindow
		local actionHandlersExist = _safeDeref(item, 'actions') or _safeDeref(chunk, 'base', 'actions')
		if (iNextWindow or bNextWindow) and not actionHandlersExist and actionName == 'go' then
			useNextWindow = true
		end

		--if item instructs us to use a different Action for the given action, tranform to the new Action
		--todo handle all alias names and handle base aliases
		local aliasName = _actionAliasMap[actionName]
		if aliasName then
			local aliasActionName = item[aliasName]
			if aliasActionName then
				actionName = aliasActionName
				log:debug("item for action after transform: ", actionName )
			end
		end

		-- special cases for go action:
		if actionName == 'go' then
			
			-- check first for a hierarchical menu or a input to perform 
			if item['count'] or (item['input'] and not item['_inputDone']) then
				log:debug("_actionHandler(", actionName, "): hierachical or input")

				menuItem:playSound("WINDOWSHOW")

				-- make a new window
				local step, sink = _newDestination(_getCurrentStep(), item, _newWindowSpec(db, item), _browseSink)

				_pushToNewWindow(step)

				-- the item is the data, wrapped into a result hash
				local res = {
					["result"] = item,
				}
				-- make base accessible
				_browseSink(step, res)
				return EVENT_CONSUME
			end
			

			-- call local service which has previously been registered with applet manager
			-- this allows SlimBrowser menus to link to local applets
			if item.actions and item.actions.go and item.actions.go.localservice then
				log:debug("_actionHandler calling ", item.actions.go.localservice)
				menuItem:playSound("WINDOWSHOW")
				appletManager:callService(item.actions.go.localservice, { text = item.text })
				return EVENT_CONSUME
			end
       

			-- check for a 'do' action (overrides a straight 'go')
			-- actionName is corrected below!!
			bAction = _safeDeref(chunk, 'base', 'actions', 'do')
			bActionContextMenu = _safeDeref(chunk, 'base', 'actions', 'more')
			iAction = _safeDeref(item, 'actions', 'do')
			iActionContextMenu = _safeDeref(item, 'actions', 'more')
			onAction = _safeDeref(item, 'actions', 'on')
			offAction = _safeDeref(item, 'actions', 'off')

		-- preview is a special action handler for previewing alarm sounds
		elseif actionName == 'preview' then
			bAction = _safeDeref(chunk, 'base', 'actions', 'preview')
			iAction = _safeDeref(item, 'actions', 'preview')
		end

		local isContextMenu = _safeDeref(item, 'actions', actionName, 'params', 'isContextMenu')
			or _safeDeref(chunk, 'base', 'actions', actionName, 'window', 'isContextMenu')

		local itemType = _safeDeref(item, 'actions', actionName, 'params', 'type')

		choiceAction = _safeDeref(item, 'actions', 'do', 'choices')

		-- now check for a run-of-the mill action
		if not (iAction or bAction or onAction or offAction or choiceAction) then
			bAction = _safeDeref(chunk, 'base', 'actions', actionName)
			iAction = _safeDeref(item, 'actions', actionName)
		elseif actionName == 'preview' then
			-- allow actionName of preview to stay that way

		else
			-- if we reach here, it's a DO action...
			-- okay to call on or off this, as they are just special cases of 'do'
			actionName = 'do'
		end
		-- is there a nextWindow on the action
		aNextWindow = _safeDeref(item, 'actions', actionName, 'nextWindow') or _safeDeref(chunk, 'base', 'actions', actionName, 'nextWindow')
		aSetSelectedIndex = _safeDeref(item, 'actions', actionName, 'setSelectedIndex') or _safeDeref(chunk, 'base', 'actions', actionName, 'setSelectedIndex')

		-- actions take precedence over items/base, item takes precendence over base
		nextWindow = aNextWindow or iNextWindow or bNextWindow

		setSelectedIndex = aSetSelectedIndex or iSetSelectedIndex or bSetSelectedIndex
		setSelectedIndex = tonumber(setSelectedIndex)

		-- in the presence of a setSelectedIndex directive default to nextWindow = 'refresh' if nothing is set
		if setSelectedIndex and not nextWindow then 
			nextWindow = 'refresh'
		end

		-- XXX: After an input box is used, chunk is nil, so base can't be used
	
		if iAction or bAction or choiceAction or nextWindow then
			-- the resulting action, if any
			local jsonAction
			local jsonActionContextMenu
	
			-- this block is solely for caching the callback for the more command for use in the next window
			if iActionContextMenu then
				if type(iActionContextMenu) == 'table' then
					jsonActionContextMenu = iActionContextMenu
				end
			elseif bActionContextMenu then
				jsonActionContextMenu = bActionContextMenu
				local paramName = jsonActionContextMenu["itemsParams"]
				local iParams = item[paramName]
				if iParams then
					-- found 'em!
					-- add them to the command
					-- make sure the base has a params item!
					local params = jsonActionContextMenu["params"]
					if not params then
						params = {}
						jsonActionContextMenu["params"] = params
					end
					for k,v in pairs(iParams) do
						params[k] = v
					end
				end
			end
			-- special case, handling a choice item action
			if choiceAction and selectedIndex then
				jsonAction = _safeDeref(item, 'actions', actionName, 'choices', selectedIndex)
			-- process an item action first
			elseif iAction then
				log:debug("_actionHandler(", actionName, "): item action")
			
				-- found a json command
				if type(iAction) == 'table' then
					jsonAction = iAction
				end
			
			-- not item action, look for a base one
			-- Bug 13097, if we have nextWindow, don't look for an action,------ breaks "touch to play", reverted
			elseif bAction then
				log:debug("_actionHandler(", actionName, "): base action")
			
				-- found a json command
				if type(bAction) == 'table' then
			
					jsonAction = bAction
				
					-- this guy may want to be completed by something in the item
					-- base gives the name of item key in key itemParams
					-- we're looking for item[base.itemParams]
					local paramName = jsonAction["itemsParams"]
					log:debug("..paramName:", paramName)
					if paramName then
					
						-- sanity check
						if type(paramName) ~= 'string' then
							log:error("Base action for ", actionName, " has itemParams field but not of type string!")
							return EVENT_UNUSED
						end

						local iParams = item[paramName]
						if iParams then
						
							-- sanity check, can't hurt
							if type(iParams) ~= 'table' then
								log:error("Base action for ", actionName, " has itemParams: ", paramName, " found in item but not of type table!")
								return EVENT_UNUSED
							end
						
							-- found 'em!
							-- add them to the command
							-- make sure the base has a params item!
							local params = jsonAction["params"]
							if not params then
								params = {}
								jsonAction["params"] = params
							end
							for k,v in pairs(iParams) do
								params[k] = v
							end
						else
							log:debug("No ", paramName, " entry in item, no action taken")
							return EVENT_UNUSED
						end
					end
				end
			end -- elseif bAction
	
			-- now we may have found a command
			if jsonAction or useNextWindow then
				log:debug("_actionHandler(", actionName, "): json action")
				if menuItem and not (nextWindow and nextWindow == "home") then
					menuItem:playSound("WINDOWSHOW")
				end

				local skipNewWindowPush = false
				-- set good or dummy sink as needed
				-- prepare the window if needed
				local step, sink
				local from, qty
				-- cover all our "special cases" first, custom navigation, artwork popup, etc.
				if nextWindow == 'nowPlaying' then
					skipNewWindowPush = true

					step, sink = _emptyDestination(step)
					_stepLockHandler(step, function () _goNowPlaying(nil, true, true ) end)

				elseif actionName == 'preview' then
					skipNewWindowPush = true

					step, sink = _emptyDestination(step)
					_stepLockHandler(step, function () _alarmPreviewWindow(iAction and iAction.title) end )

				elseif nextWindow == 'playlist' then
					_goPlaylist(true)
				elseif nextWindow == 'home' then
					-- bit of a hack to notify serverLinked after factory reset SN menu
					if item['serverLinked'] then
						log:info("serverlinked: pin: ", _server:getPin())
						_server.jnt:notify('serverLinked', _server, true)
					end
					goHome()
					
				elseif nextWindow == 'parentNoRefresh' then
					_hideMe(true, _, setSelectedIndex)
				elseif nextWindow == 'parent' then
					_hideMe(_, _, setSelectedIndex)
				elseif nextWindow == 'grandparent' then
					local currentStep = _getCurrentStep()
					if currentStep and currentStep.window and currentStep.window:isContextMenu() then
						Window:hideContextMenus()
						--bug 15824: also refresh the underlying window from the CM
						_refreshMe(setSelectedIndex)
					else
						_hideMeAndMyDad(setSelectedIndex)
					end
				elseif onClick == 'refreshGrandparent' then
					_refreshGrandparent(setSelectedIndex)
				elseif nextWindow == 'refreshOrigin' or onClick == 'refreshOrigin' then
					_refreshOrigin(setSelectedIndex)
				elseif nextWindow == 'refresh' or onClick == 'refreshMe' then
					_refreshMe(setSelectedIndex)
				-- if we have a nextWindow but none of those reserved words above, hide back to that named window
				elseif nextWindow then
					-- Bug 15960 - Fix app install when returning to App Gallery
					-- 'from' and 'qty' need to be defined (i.e. not nil) else the returned list
					--  does _not_ contain the just added app when returning to the App Gallery window.
					-- If that patch causes issues in other cases another solution would be to
					--  return to the Home Menu instead of returning to the App Gallery.
					from, qty = 0, 200

					_hideToX(nextWindow, setSelectedIndex)
				elseif itemType == "slideshow" or (item and item["slideshow"]) then
					from, qty = 0, 200
					
					skipNewWindowPush = true

				elseif item["showBigArtwork"] then
					sink = _bigArtworkPopup
				elseif actionName == 'go' or actionName == 'play-hold' then
					step, sink = _newDestination(_getCurrentStep(), item, _newWindowSpec(db, item, isContextMenu), _browseSink, jsonAction, jsonActionContextMenu)
					if step.menu then
						from, qty = _decideFirstChunk(step, jsonAction)
					end
				-- context menu handler
				elseif actionName == 'more' or
					actionName == "add" and (item['addAction'] == 'more' or
					-- using addAction is temporary to ensure backwards compatibility 
					-- until all 'add' commands are removed in SC in favor of 'more'
					_safeDeref(chunk, 'base', 'addAction') == 'more') or
					isContextMenu then
					log:debug('Context Menu')
					-- Bug 14061: send command flag to have XMLBrowser fork CM response off to get playback controls
					if jsonAction.params then
						jsonAction.params.xmlBrowseInterimCM = 1
					end


					step, sink = _newDestination(_getCurrentStep(), item, _newWindowSpec(db, item, isContextMenu), _browseSink, jsonAction)
					if step.menu then
						from, qty = _decideFirstChunk(step, jsonAction)
					end
				end

				if jsonAction then
					if not skipNewWindowPush then
						_pushToNewWindow(step)
					end
					_performJSONAction(jsonAction, from, qty, step, sink, itemType)
				else
					-- if there's not jsonAction, sink is a nextWindow function, so just call it
					if sink or not nextWindow then -- still try if "not nextWindow" so error occurs, since sink should exist in those cases
						sink()
					end
				end
			
				return EVENT_CONSUME
			end
		end
	end
	
	-- fallback to built-in
	-- these may work without an item
	
	-- Note the assumption here: event handling happens for front window only
	if _getCurrentStep() and _getCurrentStep().actionModifier then
		local builtInAction = actionName .. _getCurrentStep().actionModifier

		local func = _defaultActions[builtInAction]
		if func then
			log:debug("_actionHandler(", builtInAction, "): built-in")
			return func(menu, menuItem, db, dbIndex, event, builtInAction, item)
		end
	end
	
	local func = _defaultActions[actionName]
	if func then
		log:debug("_actionHandler(", actionName, "): built-in")
		return func(menu, menuItem, db, dbIndex, event, actionName, item)
	end
	
	-- no success here for this event
	return EVENT_UNUSED
end

function _alarmPreviewWindow(title)

	-- popup
	local window = Window("alarm_popup", _string('SLIMBROWSER_ALARM_PREVIEW'))
        local icon = Icon('icon_alarm')
        local label = Label('preview_text', title )
        local headerGroup = Group('alarm_header', {
                icon = icon,
                time = label,
        })

	local hideAction = function()
		log:warn('hide alarm preview')
		window:hide(Window.transitionNone)
		return EVENT_CONSUME
	end

	local windowPopAction = function()
		log:warn('window goes pop!')
		_player:stopPreview()
		return EVENT_CONSUME
	end

        local menu = SimpleMenu('menu')
        menu:addItem({
                text = _string("SLIMBROWSER_DONE"),
                sound = "WINDOWHIDE",
                callback = hideAction,
        })

	window:ignoreAllInputExcept({"go", "back", "go_home", "go_home_or_now_playing", "volume_up", "volume_down", "stop", "pause", "power"})

	window:addListener(EVENT_WINDOW_POP,
		windowPopAction
	)

	menu:setHeaderWidget(headerGroup)

	window:setButtonAction('rbutton', 'cancel')
	window:addActionListener("cancel", window, hideAction)

        window:setButtonAction('lbutton', nil, nil)

        window:addWidget(menu)
        window:setShowFrameworkWidgets(false)
        window:setAllowScreensaver(false)
        window:show(Window.transitionFadeIn)
	return EVENT_CONSUME

end


-- map from a key to an actionName
local _keycodeActionName = {
	[KEY_VOLUME_UP] = 'volup', 
	[KEY_VOLUME_DOWN] = 'voldown', 
	[KEY_FWD]   = 'fwd',
	[KEY_REW]   = 'rew',
}

-- map from a key to an actionName
local _actionToActionName = {
	["go_home_or_now_playing"] = 'home',
	["pause"]   = 'pause',
	["stop"]   = 'pause-hold',
	["play"]    = 'play',
	["set_preset_0"]    = 'set-preset-0',
	["set_preset_1"]    = 'set-preset-1',
	["set_preset_2"]    = 'set-preset-2',
	["set_preset_3"]    = 'set-preset-3',
	["set_preset_4"]    = 'set-preset-4',
	["set_preset_5"]    = 'set-preset-5',
	["set_preset_6"]    = 'set-preset-6',
	["set_preset_7"]    = 'set-preset-7',
	["set_preset_8"]    = 'set-preset-8',
	["set_preset_9"]    = 'set-preset-9',
	["create_mix"]    = 'play-hold',
	["add"]     = 'more',
	["add_end"]     = 'add',
	["play_next"]     = 'add-hold',
	["go"]      = 'go',
	["go_hold"]      = 'go-hold',

}

-- internal actionNames:
--				  'inputDone'

-- _browseMenuListener
-- called 
local function _browseMenuListener(menu, step, menuItem, dbIndex, event)
	local db = step.db

	log:debug("_browseMenuListener(", event:tostring(), ", " , index, ")")
	

	-- ok so joe did press a key while in our menu...
	-- figure out the item action...
	local evtType = event:getType()

	local currentlySelectedIndex =step.menu:getSelectedIndex()
	if _player and _player:getLastBrowse(step.commandString) and evtType == EVENT_FOCUS_GAINED then
		if currentlySelectedIndex then
			log:debug("step.commandString: ", step.commandString, " menu: ", step.menu, " currentlySelectedIndex: ", currentlySelectedIndex)
			_player:setLastBrowseIndex(step.commandString, currentlySelectedIndex)
		else
			_player:setLastBrowseIndex(step.commandString, nil)
		end
	end


	-- we don't care about focus: we get one everytime we change current item
	-- and it just pollutes our logging.
	if evtType == EVENT_FOCUS_GAINED
		or evtType == EVENT_FOCUS_LOST
		or evtType == EVENT_HIDE
		or evtType == EVENT_SHOW then
		return EVENT_UNUSED
	end

	-- we don't care about events not on the current window
	-- assumption for event handling code: _curStep corresponds to current window!
	if _getCurrentStep() and _getCurrentStep().menu ~= menu then
		log:debug("_getCurrentStep(): ", _getCurrentStep())

		log:error("Ignoring, not visible, or step/windowStack out of sync: current step menu: ", _getCurrentStep().menu, " window menu: ", menu)
		return EVENT_UNUSED
	end
	
	local item = db:item(dbIndex)

	-- special case: an action of "preview", which is used to preview alarm sounds before listening
	if item and item.actions and item.actions.preview then
		if evtType == ACTION then
			log:warn('--->Trapped what Squeezeplay thinks is an attempt to preview an alarm sound')
			local action = event:getAction()
			local actionName = _actionToActionName[action]
			if actionName == 'play' or actionName == 'more' then
				return _actionHandler(menu, menuItem, db, dbIndex, event, 'preview', item)
			end
		end
	end

	-- we don't want to do anything if this menu item involves an active decoration
	-- like a radio, checkbox, or set of choices
	-- further, we want the event to propagate to the active widget, so return EVENT_UNUSED
	if item and item["_jive_button"] then
		return EVENT_UNUSED
	end

	
	-- actions on button down
	if evtType == EVENT_ACTION then
		log:debug("_browseMenuListener: EVENT_ACTION")
		
		if item then
			-- check for a local action
			local func = item._go
			if func then
				log:debug("_browseMenuListener: Calling found func")
				menuItem:playSound("WINDOWSHOW")
				return func()
			end
		
			-- otherwise, check for a handler
			return _actionHandler(menu, menuItem, db, dbIndex, event, 'go', item)
		end

	elseif evtType == ACTION then
		log:debug("_browseMenuListener: ACTION")
		local action = event:getAction()
		local actionName = _actionToActionName[action]
		if actionName then
			return _actionHandler(menu, menuItem, db, dbIndex, event, actionName, item)
		end

	elseif evtType == EVENT_KEY_PRESS then
		log:debug("_browseMenuListener: EVENT_KEY_PRESS")
		
		local actionName = _keycodeActionName[event:getKeycode()]

		if actionName then
			return _actionHandler(menu, menuItem, db, dbIndex, event, actionName, item)
		end
		
	elseif evtType == EVENT_KEY_HOLD then
		log:debug("_browseMenuListener: EVENT_KEY_HOLD")
		
		local actionName = _keycodeActionName[event:getKeycode()]

		if actionName then
			return _actionHandler(menu, menuItem, db, dbIndex, event, actionName .. "-hold", item)
		end
	end

	-- if we reach here, we did not handle the event :(
	return EVENT_UNUSED
end


-- _browseMenuRenderer
-- renders a basic menu
local function _browseMenuRenderer(menu, step, widgets, toRenderIndexes, toRenderSize)
	local db = step.db

	--	log:debug("_browseMenuRenderer(", toRenderSize, ", ", db, ")")
	-- we must create or update the widgets for the indexes in toRenderIndexes.
	-- this last list can contain null, so we iterate from 1 to toRenderSize

	local labelItemStyle = db:labelItemStyle()
	
	local menuAccel, dir = menu:isAccelerated()
	if menuAccel then
		_server:cancelAllArtwork()
	end

	for widgetIndex = 1, toRenderSize do
		local dbIndex = toRenderIndexes[widgetIndex]
		
		if dbIndex then
			
			-- the widget in widgets[widgetIndex] shall correspond to data[dataIndex]
--			log:debug(
--				"_browseMenuRenderer: rendering widgetIndex:",
--				widgetIndex, ", dataIndex:", dbIndex, ")"
--			)
			
			local widget = widgets[widgetIndex]

			local item, current = db:item(dbIndex)

			local style = labelItemStyle

			if style == 'item' then
				local chunk = db:chunk()
			end
			
			if current then
				style = "albumcurrent"
			elseif item and item["style"] then
				style = item["style"]
			end

			-- support legacy styles for play and add
			if styleMap[style] then
				style = styleMap[style]
			end
			if item and (item['checkbox'] or item['radio'] or item['selectedIndex']) then
				style = 'item_choice'
			end
			widgets[widgetIndex] = _decoratedLabel(widget, style, item, step, menuAccel)
		end
	end

	if menuAccel or toRenderSize == 0 then
		return
	end

	-- preload artwork in the direction of scrolling
	-- FIXME wrap around cases
	local startIndex
	if dir > 0 then
		startIndex = toRenderIndexes[toRenderSize]
	else
		startIndex = toRenderIndexes[1] - toRenderSize
	end

	for dbIndex = startIndex, startIndex + toRenderSize do
		local item = db:item(dbIndex)
		if item then
			_artworkItem(step, item, nil, false)
		end
	end
end


-- _browseMenuAvailable
-- renders a basic menu
local function _browseMenuAvailable(menu, step, dbIndex, dbVisible)
	local db = step.db

	-- check range
	local minIndex = math.max(1, dbIndex)
	local maxIndex = math.min(dbIndex + dbVisible, db:size())

	-- only check first and last item, this assumes that the middle
	-- items are available
	return (db:item(minIndex) ~= nil) and (db:item(maxIndex) ~= nil)
end


-- _browseInput: method to render a textinput/keyboard for SlimBrowse input
local function _browseInput(window, item, db, inputSpec, last, timeFormat)

	local titleWidgetComplete = false
	if not inputSpec then
		log:error('no input spec')
		return
	end
	-- never allow screensavers in an input window
	window:setAllowScreensaver(false)
	if inputSpec.title then
		window:setTitle(inputSpec.title)
	end

	local nowPlayingButton
	if inputSpec.setupWindow == 1 then
		nowPlayingButton = _invisibleButton()
	else
		nowPlayingButton = _nowPlayingButton()
	end

	local titleText = window:getTitle()
	if inputSpec.title then
		titleText = inputSpec.title
	end

	if titleText then
		titleWidgetComplete = true
	end

	local newTitleWidget = Group('title', {
		text = Label("text", titleText),
		lbutton = _backButton(),
		rbutton = nowPlayingButton,
	})	
	window:setTitleWidget(newTitleWidget)
	
	-- make sure it's a number for the comparison below
	-- Lua insists on checking type while Perl couldn't care less :(
	inputSpec.len = tonumber(inputSpec.len)
	
	-- default allowedChars
	if not inputSpec.allowedChars then
		if inputSpec._kbType and string.match(inputSpec._kbType, 'email') then
			inputSpec.allowedChars = _string("ALLOWEDCHARS_EMAIL")
		else
			inputSpec.allowedChars = _string("ALLOWEDCHARS_WITHCAPS")
		end
	end
	local v = ""
	local initialText = inputSpec.initialText
	local inputStyle  = inputSpec._inputStyle

	if initialText then
		v = tostring(initialText)
	end

	local inputValue
	-- time input now handled without a textinput widget
	if inputStyle == 'time' then
		local initTime   = DateTime:timeTableFromSFM(v, timeFormat)
		local submitCallback = function( hour, minute, ampm)

			log:debug('Time entered as: ', hour, ':', minute, ' ', ampm)
			local totalSecs = ( tonumber(hour) * 3600 ) + ( tonumber(minute) * 60 )

			if ampm == 'AM' and tonumber(hour) == 12 then
				totalSecs = minute * 60
			elseif ampm == 'PM' and tonumber(hour) < 12 then
				totalSecs = totalSecs + 43200
			end
			-- input is done
			item['_inputDone'] = true
			-- set _lastInput to the total seconds from midnight
			_lastInput = tostring(totalSecs)
			-- do the action
			_actionHandler(nil, nil, db, nil, nil, 'go', item)
			-- close the window if this is a "do" action
			local doAction = _safeDeref(item, 'actions', 'do')
			local nextWindow = _safeDeref(item, 'nextWindow')

			--Close the window, unless the 'do' item also has a nextWindow param, which trumps
			if doAction and not nextWindow then
				-- close the window
				window:playSound("WINDOWHIDE")
				window:hide()
			else
				window:playSound("WINDOWSHOW")
			end
		end
		local timeInput = Timeinput(window, submitCallback, initTime)

		return true

	elseif inputStyle == 'ip' then
		if not initialText then
			initialText = ''
		end
		v = Textinput.ipAddressValue(initialText)
		inputValue = v
	elseif inputSpec.len and tonumber(inputSpec.len) > 0 then
		inputValue = Textinput.textValue(v, tonumber(inputSpec.len), 200)
	else
		inputValue = v
	end

	-- create a text input
	local input = Textinput(
		"textinput", 
		inputValue,
		function(_, value)
			_lastInput = tostring(value)
			--table.insert(_inputParams, value)
			item['_inputDone'] = tostring(value)
			
			-- popup time
			local displayPopup = _safeDeref(inputSpec, 'processingPopup')
			local displayPopupText = _safeDeref(inputSpec, 'processingPopup', 'text')
			if displayPopup then
				_inputInProgress(window, displayPopupText)
			end
			-- now we should perform the action !
			_actionHandler(nil, nil, db, nil, nil, 'go', item)
			-- close the text input if this is a "do"
			local doAction = _safeDeref(item, 'actions', 'do')
			local nextWindow = _safeDeref(item, 'nextWindow')

			--Close the window, unless the 'do' item also has a nextWindow param, which trumps
			if doAction and not nextWindow then
				-- close the window
				window:playSound("WINDOWHIDE")
				window:hide()
			else
				window:playSound("WINDOWSHOW")
			end
			return true
		end,
		inputSpec.allowedChars
	)

	--[[ FIXME: removing help (all platforms) until a per-platform solution can be made for help
	-- fix up help
	local helpText
	if inputSpec.help then
		local help = inputSpec.help
		helpText = help.text
		if not helpText then
			if help.token then
				helpText = _string(help.token)
			end
		end
	end
	
	local softButtons = { inputSpec.softbutton1, inputSpec.softbutton2 }
	local helpStyle = 'help'

	if softButtons[1] or softButtons[2] then
		helpStyle = 'softHelp'
	end

	if helpText then
		local help = Textarea(helpStyle, helpText)
		window:addWidget(help)
	end

	if softButtons[1] then
		window:addWidget(Label("softButton1", softButtons[1]))
	end
	if softButtons[2] then
		window:addWidget(Label("softButton2", softButtons[2]))
	end
	--]]
	
	local kbType = inputSpec._kbType or 'qwerty'
	if kbType == 'qwertyLower' then
		kbType = 'qwerty'
	end
	local keyboard = Keyboard("keyboard", kbType, input)
	local backspace = Keyboard.backspace()
	local group = Group('keyboard_textinput', { textinput = input, backspace = backspace } )

	window:addWidget(group)
	window:addWidget(keyboard)
	window:focusWidget(group)

	return titleWidgetComplete
end

-- _newDestination
-- origin is the step we are coming from
-- item is the source item
-- windowSpec is the window spec, generally computed by _newWindowSpec to aggregate base and item
-- sink is the sink this destination will use: we must create a closure so that on receiving the data
--  the destination can be retrieved (i.e. reunite data and window)
-- data is generic data that is stored in the step; it is used f.e. to keep the json action between the
--  first incantation and the subsequent ones needed to capture all data (see _browseSink).
-- containerContextMenu is the json action of the more command (if any) from the previous menu item
_newDestination = function(origin, item, windowSpec, sink, data, containerContextMenu)
	log:debug("_newDestination():")
	log:debug(windowSpec)

	-- a DB (empty...) 
	local db = DB(windowSpec)

	local window
	local titleWidgetComplete = false

	if windowSpec.isContextMenu then
		window = ContextMenuWindow("", windowSpec.windowId) -- todo localize or decide what title text should be
	else
		window = Window(windowSpec.windowStyle or 'text_list', _, _, windowSpec.windowId)
		-- XXX: the command in containerContextMenu needs to be 'contextmenu' or else do not do this
		-- eventually it would be good to have this functionality for XMLBrowse items, but without this
		-- it will turn the title text into a button in unwanted spots along XMLBrowse trees
		if containerContextMenu and containerContextMenu.cmd and containerContextMenu.cmd[1] == 'contextmenu' then
			log:debug('Turn the title text into a button')
			local titleWidget = Group('title', { 
					text = Button( 
						Label("textButton", windowSpec.text),
						function()
							local step, sink = _newDestination(_getCurrentStep(), item, _newWindowSpec(db, item, true), _browseSink, containerContextMenu)
							local from, qty
							if step.menu then
								from, qty = _decideFirstChunk(step, containerContextMenu)
							end
							_pushToNewWindow(step, true)
							_performJSONAction(containerContextMenu, from, qty, step, sink, _)
	                                        end
					),

					icon = Icon("icon"), 
					lbutton = _backButton(),
					rbutton = _nowPlayingButton(),
			})
			window:setTitleWidget(titleWidget)
			titleWidgetComplete = true
		end
	end

	local timeFormat = nil
	local menu
	-- if the item has an input field or fields, we must ask for it
	if item and item['input'] and not item['_inputDone'] then

		if item['input'] and item['input']['_inputStyle'] == 'time' then
			timeFormat = _getTimeFormat()
			if timeFormat == '12' then
				window:setStyle('input_time_12h')
			else
				window:setStyle('input_time_24h')
			end
		else
			window:setStyle('input')
		end
		inputSpec = item.input

		-- multiple input
		if #inputSpec > 0 then
			for i, v in ipairs(inputSpec) do
				local last = false
				if i == #inputSpec then
					last = true
				end
				titleWidgetComplete = _browseInput(window, item, db, v, last, timeFormat)
			end
		-- single input
		else
			titleWidgetComplete = _browseInput(window, item, db, inputSpec, true, timeFormat)
		end

	else
	
		-- create a cozy place for our items...
		-- a db above
	
		-- a menu. We manage closing ourselves to guide our path
		menu = Menu(db:menuStyle(), _browseMenuRenderer, _browseMenuListener, _browseMenuAvailable)
		
		-- alltogether now
		window:addWidget(menu)

		-- add support for help text on a regular menu
		local helpText
		if windowSpec.help then
			helpText = windowSpec.help
			if helpText then
				local help = Textarea('help', helpText)
				window:addWidget(help)
			end
		end

	end
	
	
	-- a step for our enlightenment path
	local step = {
		origin          = origin,   -- origin step
		destination     = false,    -- destination step
		window          = window,   -- step window
		menu            = menu,     -- step menu
		db              = db,       -- step db
		sink            = false,    -- sink closure embedding this step
		data            = data,     -- data (generic)
		actionModifier  = false,    -- modifier
	}
	
	log:debug("new step: " , step)


	if not windowSpec.isContextMenu and not titleWidgetComplete then
		window:setTitleWidget(_decoratedLabel(nil, 'title', windowSpec, step, false))
	end


	if step.menu then
		if windowSpec.isContextMenu then
			step.menu:setDisableVerticalBump(true)
		end
		_stepSetMenuItems(step)
                step.menu.textIndexHandler = {
                        getTextIndexes = function ()             
                                return step.db:getTextIndexes()
                        end,
                        getIndex = function (char)
				for i, wrapper in ipairs(step.db:getTextIndexes()) do
					if wrapper.key == char then
						return wrapper.index
					end
				end

                                return nil
                        end,
                        getValidChars =  function ()             
                                local validChars = ""
                                
				for i, wrapper in ipairs(step.db:getTextIndexes()) do
					validChars = validChars .. wrapper.key
				end
				
				return validChars
                        end,
		}
	end
	
	if windowSpec.disableBackButton then
		window:addListener(bit.bor(EVENT_KEY_PRESS, EVENT_ACTION),
			function(event)
				local type = event:getType()
				if type == ACTION then
					local action = event:getAction()
					if action == 'back' then
						Framework:playSound("BUMP")
						window:bumpLeft()
						return EVENT_CONSUME
					end
				elseif type == EVENT_KEY_PRESS then
					local keycode = event:getKeycode()
					if keycode == KEY_BACK then
						Framework:playSound("BUMP")
						window:bumpLeft()
						return EVENT_CONSUME
					end
				end
				return EVENT_UNUSED
			end
		)
	end

	-- make sure closing our windows do keep the path alive!
	window:addListener(EVENT_WINDOW_POP,
		function(evt)
			-- clear it if present, so we can start again the textinput
			if item then
				item['_inputDone'] = nil
			end

			-- cancel the step to prevent new data being loaded
			step.cancelled = true
			log:debug("EVENT_WINDOW_POP called")
			_popStep()

		end
	)
		
	-- manage sink
	step.sink = function(chunk, err)
		sink(step, chunk, err)
	end

	return step, step.sink
end


local function _installPlayerKeyHandler(self)
	if _playerKeyHandler then
		return
	end

	_playerKeyHandler = Framework:addListener(bit.bor(EVENT_KEY_DOWN, EVENT_KEY_PRESS, EVENT_KEY_HOLD, EVENT_IR_ALL),
		function(event)
			local type = event:getType()

			if (bit.band(type, EVENT_IR_ALL) ) > 0 then
				if event:isIRCode("volup") or event:isIRCode("voldown") then
					return self.volume:event(event)
				end
				return EVENT_UNUSED
			end

			local actionName = _keycodeActionName[event:getKeycode()]
			if not actionName then
				return EVENT_UNUSED
			end

			if type == EVENT_KEY_DOWN then
				actionName = actionName .. "-down"
			elseif type == EVENT_KEY_HOLD then
				actionName = actionName .. "-hold"
			end

			local func = _globalActions[actionName]

			if not func then
				return EVENT_UNUSED
			end

			-- call the action
			return func(self, event)
		end,
		false
	)
end


local function _removePlayerKeyHandler(self)
	if not _playerKeyHandler then
		return
	end

	Framework:removeListener(_playerKeyHandler)
	_playerKeyHandler = false
end

local function _installActionListeners(self)
	if _actionListenerHandles then
		return
	end
	
	_actionListenerHandles = {}
	
	for action, func in pairs( _globalActionsNEW ) do
		local handle = Framework:addActionListener(action, self, func, false)
		table.insert(_actionListenerHandles, handle)
	end
	
end

local function _removeActionListeners(self)
	if not _actionListenerHandles then
		return
	end

	for i, handle in ipairs( _actionListenerHandles ) do
		Framework:removeListener(handle)
	end

	_actionListenerHandles = false
end


--==============================================================================
-- SlimBrowserApplet public methods
--==============================================================================

-- goHome
-- pushes the home window to the top
function goHome(self, transition)
	appletManager:callService("goHome")
end


function findSqueezeNetwork(self)
	-- get squeezenetwork object
        for mac, server in appletManager:callService("iterateSqueezeCenters") do
		if server:isSqueezeNetwork() then
                        log:debug("found SN")
                        return server
                end
        end
	log:error('SN not found')
	return nil
end


function squeezeNetworkRequest(self, request, inSetup, successCallback)
	local squeezenetwork = findSqueezeNetwork()

	if not squeezenetwork or not request then
		return
	end

	self.inSetup = inSetup

	_server = squeezenetwork

	-- create a window for SN signup
	local step, sink = _newDestination(
		nil,
		nil,
		{
			text = self:string("SN_SIGNUP"),
			menuStyle = 'menu',
			labelItemStyle   = "item",
			windowStyle = 'text_list',
			disableBackButton = true,
		},
		_browseSink
	)
	local sinkWrapper = sink
	if successCallback then
		sinkWrapper =  function(...)
				sink(...)
				log:info("Calling successCallback after initial SN request succeeded")
				--first request is always a welcome screen. return success callback including whether this is an already registered SP 
				successCallback(squeezenetwork:isSpRegisteredWithSn())
			end
	end
	_pushToNewWindow(step)
        squeezenetwork:userRequest( sinkWrapper, nil, request )

end


-- XXXX
function browserJsonRequest(self, server, jsonAction)
	-- XXXX allow any server

	if not _player then
		local currentPlayer = appletManager:callService("getCurrentPlayer")
		--notify_playerCurrent might not have been called yet.
		_attachPlayer(self, currentPlayer)
	end

	_performJSONAction(jsonAction, nil, nil, nil, nil)
end


-- XXXX
function browserActionRequest(self, server, v, loadedCallback)
	-- XXXX allow any server

	if not _player then
		local currentPlayer = appletManager:callService("getCurrentPlayer")
		--notify_playerCurrent might not have been called yet.
		_attachPlayer(self, currentPlayer)
	end

	local jsonAction, from, qty, step, sink
	local doAction = _safeDeref(v, 'actions', 'do')
	local goAction = _safeDeref(v, 'actions', 'go')

	if doAction then
		jsonAction = v.actions['do']
	elseif goAction then
		jsonAction = v.actions.go
	else
		return false
	end

	-- we need a new window for go actions, or do actions that involve input
	if goAction or (doAction and v.input) or v.id == "playerpower" then --slightly hackish, not sure how to handle playerpower case generically
		log:debug(v.nextWindow)
		if v.nextWindow then
			if loadedCallback then
				loadedCallback(step)
			end
			if v.nextWindow == 'home' then
				sink = function () goHome() end
			elseif v.nextWindow == 'playlist' then
				sink = _goPlaylist
			elseif v.nextWindow == 'nowPlaying' then
				sink = function () _goNowPlaying() end
			end
		else
			if doAction and v.id == "playerpower" then --slightly hackish, not sure how to handle playerpower case generically
				step, sink = _emptyDestination(step)
				step.loaded = function()
					if  loadedCallback then
						loadedCallback(step)
					end
				end
			else
				step, sink =_newDestination(nil,
					v,
					_newWindowSpec(nil, v),
					_browseSink,
					jsonAction
				)

				if v.input then
					step.window:show()
					_pushStep(step)
				else
					from, qty = _decideFirstChunk(step, jsonAction)

					step.loaded = function()
						--if lastBrowseIndex then defer callback until lastBrowseIndex chunk received.
						local lastBrowseIndex = _player:getLastBrowseIndex(step.commandString)
						if not lastBrowseIndex and loadedCallback then
							loadedCallback(step)
							_pushStep(step)
							step.window:show()
						else
							_player.loadedCallback = loadedCallback
						end
					end
				end
			end
		end
	end

	if not v.input then
		_performJSONAction(jsonAction, from, qty, step, sink)
	end

	return step
end


function browserCancel(self, step)
	 step.cancelled = true
end


function notify_networkOrServerNotOK(self, iface)
	log:warn("notify_networkOrServerNotOK()")
	if iface and iface:isNetworkError() then
		log:warn("this is a network error")
		_networkError = iface -- store the interface object in _networkError
	else
		log:warn("this is a server error")
		_serverError = true
	end
end


function notify_networkAndServerOK(self, iface)
	_networkError = false
	_serverError  = false
	if _diagWindow then
		_diagWindow:hide()
		_diagWindow = false
	end
end


function notify_serverConnected(self, server)
	if _server ~= server then
		return
	end

	iconbar:setServerError("OK")

	-- hide connection error window
	if self.serverErrorWindow then
		self.serverErrorWindow:hide(Window.transitionNone)
		self.serverErrorWindow = false
	end
end


function notify_serverDisconnected(self, server, numUserRequests)
	if _server ~= server then
		return
	end

	iconbar:setServerError("ERROR")

	if numUserRequests == 0 or self.serverErrorWindow then
		return
	end

	self:_problemConnectingPopup(server)
end


function _removeRequestAndUnlock(self, server)
							if server then
								server:removeAllUserRequests()
							end
							local currentStep = _getCurrentStep()
							if currentStep then
								if currentStep.menu then
									currentStep.menu:unlock()
								end
							end

end


function _problemConnectingPopup(self, server)
	log:debug("_problemConnectingPopup")
	local successCallback = function()
					self:_problemConnectingPopupInternal(server)
				end
	local failureCallback = self:_networkFailureCallback(server)

	appletManager:callService("warnOnAnyNetworkFailure", successCallback, failureCallback)
end


function _problemConnectingPopupInternal(self, server)
	log:info("_problemConnectingPopupInternal")
	-- attempt to reconnect, this may send WOL
	server:wakeOnLan()
	server:connect()

	-- popup
	local popup = Popup("waiting_popup")
	popup:addWidget(Icon("icon_connecting"))
	popup:addWidget(Label("text", self:string("SLIMBROWSER_CONNECTING_TO")))
	popup:addWidget(Label("subtext", server:getName()))

	popup:ignoreAllInputExcept({"back", "go_home", "go_home_or_now_playing", "volume_up", "volume_down", "stop", "pause", "power"})
	local cancelAction =    function ()
					log:info("Cancel reconnect window")

					self:_removeRequestAndUnlock(server)
					self.serverErrorWindow = nil
					popup:hide()

					return EVENT_CONSUME
				end
	popup:addActionListener("back", self,  cancelAction )
	popup:addActionListener("go_home", self,  cancelAction )
	popup:addActionListener("go_home_or_now_playing", self,  cancelAction )

	local count = 0
	popup:addTimer(1000,
		function()
			count = count + 1
			if count == 20 or _player:hasConnectionFailed() then
				self:_problemConnecting(server)
			end
		end)

	-- once the server is connected the popup is closed in
	-- notify_serverConnected
	self.serverErrorWindow = popup
	popup:show()
end


function _networkFailureCallback(self, server)
	return function(failureWindow)
		self.serverErrorWindow = failureWindow
		failureWindow:addListener(EVENT_WINDOW_POP,
			function()
				self.serverErrorWindow = false
				self:_removeRequestAndUnlock(server)
			end)
	end
end


function _problemConnecting(self, server)
	log:debug("_problemConnecting")
	local successCallback = function()
					self:_problemConnectingInternal(server)
				end
	local failureCallback = self:_networkFailureCallback(server)

	appletManager:callService("warnOnAnyNetworkFailure", successCallback, failureCallback)
end


function _problemConnectingInternal(self, server)
	log:info("_problemConnectingInternal")
	-- open connection error window
	local window = Window("text_list", self:string("SLIMBROWSER_PROBLEM_CONNECTING"), 'settingstitle')

	local menu = SimpleMenu("menu")

	local player = _player

	-- try again, reconnect to server
	menu:addItem({
			     text = self:string("SLIMBROWSER_TRY_AGAIN"),
			     callback = function()
						window:hide()

						self:_problemConnectingPopup(server)
						appletManager:callService("setCurrentPlayer", player)
					end,
			     sound = "WINDOWSHOW",
		     })

	if server:isPasswordProtected() then
		-- password protection has been enabled
		menu:addItem({
			text = self:string("SLIMBROWSER_ENTER_PASSWORD"),
			callback = function()
				appletManager:callService('squeezeCenterPassword', server)
			end,
			sound = "WINDOWSHOW",
		})
	end

	if _anyCompatibleSqueezeCenterFound() then
		menu:addItem({
				     text = self:string("SLIMBROWSER_CHOOSE_MUSIC_SOURCE"),
				     callback = function()
							self.inSetup = false
							self:_removeRequestAndUnlock(server)
							appletManager:callService("selectCompatibleMusicSource")
						end,
				     sound = "WINDOWSHOW",
			     })
	end
	
	if not self.inSetup then
		--bug 12843 - offer "go home" (rather than try to autoswitch) since it is difficult/impossible to autoswitch to the desired item.
		menu:addItem({
				text = self:string("SLIMBROWSER_GO_HOME"),
				callback = function()
					self:_removeRequestAndUnlock(server)
					goHome()
				end,
			})


			-- change player, only if multiple players
			-- NOTE also only display this if we have a player selected, this is
			-- to fix Bug 11457 where Choose Player should not be shown during
			-- fab4 setup.
			local numPlayers = appletManager:callService("countPlayers")
			if numPlayers > 1 and appletManager:hasApplet("SelectPlayer") and player then
				menu:addItem({
						     text = self:string("SLIMBROWSER_CHOOSE_PLAYER"),
						     callback = function()
									self:_removeRequestAndUnlock(server)
									if player:isLocal() then
										--avoid disconnecting local player (user might cancel inside "Choose Player")
										player:disconnectServerAndPreserveLocalPlayer()
									else
										appletManager:callService("setCurrentPlayer", nil)

									end
									appletManager:callService("setupShowSelectPlayer")
								end,
						     sound = "WINDOWSHOW",
					     })
			end

	else
		--in setup
		window:setAllowScreensaver(false)
		--Offer local SC's in setup if they exist
		if Player:getCurrentPlayer() then
			-- don't offer choose player if the current player can be selected
		else
			menu:addItem({
					     text = self:string("SLIMBROWSER_CHOOSE_PLAYER"),
					     callback = function()
								appletManager:callService("setupShowSelectPlayer")
							end,
					     sound = "WINDOWSHOW",
				     })

		end
		menu:addItem({
				text = self:string("SLIMBROWSER_DIAGNOSTICS"),
				callback = function()
					appletManager:callService("diagnosticsMenu")
				end,
			        sound = "WINDOWSHOW",
			})
	end

	local cancelAction =    function ()
					self:_removeRequestAndUnlock(server)
					window:hide()

					return EVENT_CONSUME
				end
	menu:addActionListener("back", self, cancelAction)
	menu:addActionListener("go_home", self,  cancelAction )

	menu:setHeaderWidget(Textarea("help_text", self:string("SLIMBROWSER_PROBLEM_CONNECTING_HELP", tostring(_server:getName()))))
	window:addWidget(menu)

	self.serverErrorWindow = window
	window:addListener(EVENT_WINDOW_POP,
			   function()
				   self.serverErrorWindow = false
			   end)

	window:show()
end


function _anyCompatibleSqueezeCenterFound()
	local anyFound = false
	for _,server in appletManager:callService("iterateSqueezeCenters") do
		if server:isCompatible() and not server:isSqueezeNetwork() then
			log:debug("At least one compatible SC found. First found: ", server)
			anyFound = true
			break
		end
	end

	return anyFound
end


--[[
********************************************************************************

Playlist management code is below here. This really should be refactored into
a different applet, but at the moment it is a little bit too tangled with the
SlimBrowser code.

This section includes the volume and scanner popups.


********************************************************************************
--]]


local _statusStep = false
local _emptyStep = false

-- _requestStatus
-- request the next chunk from the player status (playlist)
local function _requestStatus()
	local step = _statusStep

	local from, qty = step.db:missing()
	if from then
		-- note, this is not a userRequest as the playlist is
		-- updated when the playlist changes
		_server:request(
				step.sink,
				_player:getId(),
				{ 'status', from, qty, 'menu:menu', 'useContextMenu:1' }
			)
	end
end


-- _statusSink
-- sink that sets the data for our status window(s)
local function _statusSink(step, chunk, err)
	log:debug("_statusSink()")
		
	-- currently we're not going anywhere with current playlist...
	_assert(step == _statusStep)

	local data = chunk.data
	if data then

		local hasSize = _safeDeref(data, 'item_loop', 1)
		if not hasSize then return end

		if logd:isDebug() then
			debug.dump(data, 8)
		end
		
		-- handle the case where the player disappears
		-- return silently
		if data.error then
			log:info("_statusSink() chunk has error: returning")
			return
		end
		
		-- FIXME: this can go away once we dispense of the upgrade messages
		-- if we have a data.item_loop[1].text == 'READ ME', 
		-- we've hit the SC upgrade message and shouldn't be dropping it into NOW PLAYING
		if data.item_loop and data.item_loop[1].text == 'READ ME' then
			log:debug('This is not a message suitable for the current playlist')
			return
		end

		_stepSetMenuItems(step, data)
		_requestStatus()

	else
		log:error(err)
	end
end


-- showEmptyPlaylist
-- if the player playlist is empty, we replace _statusStep with this window
function showEmptyPlaylist(token)

	local window = Window("play_list", _string('SLIMBROWSER_PLAYLIST'))
	local menu = SimpleMenu("menu")
	menu:addItem({
		     text = _string(token),
			style = 'item_no_arrow'
	})
	window:addWidget(menu)

	window:setButtonAction("rbutton", nil, nil)

	_emptyStep = {}
	_emptyStep.window = window
	_emptyStep._isNpChildWindow = true

	return window

end


function _leavePlayListAction()
	local windowStack = Framework.windowStack
	-- if this window is #2 on the stack there is no NowPlaying window
	-- (e.g., when playlist is empty)
	if #windowStack == 2 then
		_goNow('home')
	else
		_goNow('nowPlaying')
	end
	return EVENT_CONSUME
end


-- showPlaylist
--
function showPlaylist()
	if _statusStep then

		-- current playlist should select currently playing item 
		-- if there is only one item in the playlist, bring the selected item to top
		local playerStatus = _player:getPlayerStatus()
		local playlistSize = _player:getPlaylistSize() 


		if playlistSize == 0 or not playlistSize then
			if _emptyStep and _emptyStep.window and _emptyStep.window == Window:getTopNonTransientWindow() then 
			        log:debug("emptyPlaylist already on screen")
				return EVENT_CONSUME
			end
			local customWindow = showEmptyPlaylist('SLIMBROWSER_NOTHING')
			customWindow:show()
			return EVENT_CONSUME
		end

		-- arrange so that menuListener works
		_pushStep(_statusStep)

		if playlistSize == nil or (playlistSize and playlistSize <= 1) then
			_statusStep.menu:setSelectedIndex(1)
		-- where we are in the playlist is stored in the item list as currentIndex
		elseif _statusStep.db and _statusStep.db:playlistIndex() then
			_statusStep.menu:setSelectedIndex(_statusStep.db:playlistIndex())
		end

		_statusStep.window:addActionListener("back", _statusStep, _leavePlayListAction)

		_statusStep.window:setButtonAction("rbutton", "go_now_playing", "go_playlist")


		_statusStep.window:show()


		return EVENT_CONSUME
	end
	return EVENT_UNUSED

end


-- showTrackOne
--
-- pushes the song info window for track one on stage
-- this method is used solely by NowPlaying Applet for
-- skipping the playlist screen when the playlist size == 1
function showTrackOne()
	showTrack(1)
end


function showCurrentTrack()
	local currentIndex = _player:getPlaylistCurrentIndex()
	showTrack(currentIndex)
end

function setPresetCurrentTrack(self, preset)
	local key = tostring(preset)
	local currentIndex = _player:getPlaylistCurrentIndex()

	local serverIndex = currentIndex - 1
	local jsonAction = {
		player = 0,
		cmd = { 'jivefavorites', 'set_preset' },
		itemsParams = 'params',
		params = {
			playlist_index = serverIndex,
			key = key,
		},
	}

	-- send the command
	_performJSONAction(jsonAction, nil, nil, nil, nil)
end


function showTrack(index, cachedResponse)

	local useCachedResponse = false
	if cachedResponse and type(cachedResponse) == 'table' then
		useCachedResponse = true
	end

	local serverIndex = index - 1
	local jsonAction = {
		cmd = { 'contextmenu' },
		itemsParams = 'params',
		window = {
			isContextMenu = 1,
		},
		player = 0,
		params = {
			playlist_index = serverIndex,
			menu = 'track',
			context = 'playlist',
		},
	}
	-- determine style
	local newWindowSpec = {
		['isContextMenu']    = true,
		["menuStyle"]        = "menu",
		["labelItemStyle"]   = "item",
	}		

	local step, sink = _newDestination(nil, nil, newWindowSpec, _browseSink)
	if not useCachedResponse then
		step.window:addActionListener("back", step, _goNowPlayingAction)
		step._isNpChildWindow = true
	end
	step.window:show()
	_pushStep(step)

	-- send the command
	_performJSONAction(jsonAction, 0, 200, step, sink, nil, cachedResponse)
end


--serviceMethod
function showCachedTrack(self, cachedResponse)
	showTrack(-1, cachedResponse)
end


function notify_playerPower(self, player, power)
	log:debug('SlimBrowser.notify_playerPower')
	if _player ~= player then
		return
	end
	local playerStatus = player:getPlayerStatus()
	if not playerStatus then
		log:info('no player status')
		return
	end

	local playlistSize = playerStatus.playlist_tracks
	local mode = player:getPlayMode()

	-- when player goes off, user should get single item styled 'Off' playlist
	local step = _statusStep
	local emptyStep = _emptyStep

	if step and step.menu then
		if power then
			if step.window then
				if emptyStep then
					step.window:replace(emptyStep.window, Window.transitionFadeIn)
				end
			end
		end
	end
end


function notify_playerModeChange(self, player, mode)
	-- BUG 11819, Current Playlist window should always show Current Playlist, so do nothing
end


function notify_playerPlaylistChange(self, player)
	log:debug('SlimBrowser.notify_playerPlaylistChange')
	if _player ~= player then
		return
	end

	local playerStatus = player:getPlayerStatus()
	local playlistSize = _player:getPlaylistSize()
	local step         = _statusStep
	local emptyStep    = _emptyStep

	-- display 'NOTHING' if the player is on and there aren't any tracks in the playlist
	if _player:isPowerOn() and playlistSize == 0 then
		local customWindow = showEmptyPlaylist('SLIMBROWSER_NOTHING')
		if emptyStep then
			customWindow:replace(emptyStep.window, Window.transitionFadeIn)
		end
		if step.window then
			customWindow:replace(step.window, Window.transitionFadeIn)
		end
		--also hide any nowPlaying window
		appletManager:callService("hideNowPlaying")

		return
	-- Bug 17529: Only push to NowPlaying if the playlist now has size, and an emptyStep window currently exists
	-- in other words, we're moving from an empty playlist (special case NP window that says "Nothing") to a non-empty playlist
	-- so in this case only, we need to explicitly push to NowPlaying and remove the emptyStep window
	elseif _player:isPowerOn() and playlistSize and emptyStep and emptyStep.window then 
		-- only move into NowPlaying if screensaver is allowed
		if Window:getTopNonTransientWindow():canActivateScreensaver() then
			_goNowPlaying(nil, true)
		end
		emptyStep.window:hide()
		_emptyStep = nil
	end

	-- update the window
	step.db:updateStatus(playerStatus)
	step.menu:reLayout()

	-- does the playlist need loading?
	_requestStatus()

end


function notify_playerTrackChange(self, player, nowplaying)
	log:debug('SlimBrowser.notify_playerTrackChange')

	if _player ~= player then
		return
	end

	if not player:isPowerOn() then
		return
	end

	local playerStatus = player:getPlayerStatus()
	local playlistSize = _player:getPlaylistSize()
	local step = _statusStep

	step.db:updateStatus(playerStatus)
	if step.db:playlistIndex() then
		step.menu:setSelectedIndex(step.db:playlistIndex())
	else
		step.menu:setSelectedIndex(1)
	end
	step.menu:reLayout()

end


-- notify_playerDelete
-- this is called when the player disappears
function notify_playerDelete(self, player)
	log:debug("SlimBrowserApplet:notify_playerDelete(", player, ")")

	-- if this concerns our player
	if _player == player then
		-- panic!
		log:error("Player gone while browsing it ! -- packing home!")
		self:free()
	end
end


-- notify_playerLoaded
-- this is called when the current player changes (possibly from no player) and the new menus are loaded
function notify_playerLoaded(self, player)
	log:debug("SlimBrowserApplet:notify_playerCurrent(", player, ")")
	_attachPlayer(self, player)
end


function notify_playerDigitalVolumeControl(self, player, digitalVolumeControl)
	if player ~= _player then
		return
	end

	log:info('notify_playerDigitalVolumeControl()', digitalVolumeControl)

	if digitalVolumeControl == 0 then
		log:warn('set volume to 100, cache previous volume as: ', self.cachedVolume)
		self.cachedVolume = player:getVolume()
		if player:isLocal() then
			player:volumeLocal(100)
		end
		player:volume(100, true)
	elseif self.cachedVolume then
		log:warn('reset volume to cached level: ', self.cachedVolume)
		if player:isLocal() then
			player:volumeLocal(self.cachedVolume)
		end
		player:volume(self.cachedVolume, true)
	end
end


function _attachPlayer(self, player)
	-- has the player actually changed?
	if _player == player then
		return
	end

	log:debug("SlimBrowserApplet:_attachPlayer(", player, ")")

	-- free current player
	if _player then
		log:debug("Freeing current player")
		self:free()
	end

	-- clear any errors, we may have changed servers
	iconbar:setServerError("OK")

	-- new player, no cached volume
	self.cachedVolume = nil

	-- update the volume object
	if self.volume then
		self.volume:setPlayer(player)
	end

	-- update the scanner object
	self.scanner:setPlayer(player)
	self.volume:setOffline(false)

	-- nothing to do if we don't have a player or server
	-- NOTE don't move this, the code above needs to run when disconnecting
	-- for all players.
	if not player or not player:getSlimServer() then
		return
	end

	-- assign our locals
	_player = player
	_server = player:getSlimServer()
	local _playerId = _player:getId()

	-- create a window for the current playlist, this is our _statusStep
	local step, sink = _newDestination(
		nil,
		nil,
		_newWindowSpec(
			nil, 
			{
				text = _string("SLIMBROWSER_PLAYLIST"),
				window = { 
					["menuStyle"] = "playlist", 
				}
			}
		),
		_statusSink
	)
	_statusStep = step
	_statusStep.window:setAllowScreensaver(false)
	
	-- make sure it has our modifier (so that we use different default action in Now Playing)
	_statusStep.actionModifier = "-status"
	_statusStep._isNpChildWindow = true

	-- showtime for the player
	_server.comet:startBatch()
	_player:onStage()
	_requestStatus()
	_server.comet:endBatch()

	_installActionListeners(self)
	_installPlayerKeyHandler(self)
	
end


--[[

=head2 applets.SlimBrowser.SlimBrowserApplet:free()

Overridden to close our player.

=cut
--]]
function free(self)
	log:debug("SlimBrowserApplet:free()")

	if _player then
		_player:offStage()
	end

	_removePlayerKeyHandler(self)
	_removeActionListeners(self)
	
	_player = false
	_server = false

	-- walk down our path and close...
	local currentStep = _getCurrentStep()
	while currentStep do
		--hide will trigger POP event which will call _popStep, so eventually _getCurrentStep() will empty and be nil
		currentStep.window:hide()

		local candidateCurrentStep = _getCurrentStep()
		if candidateCurrentStep == currentStep then
			log:error("POP event should have been handled, popping the stepStack, but the stepStack pop didn't occur")
			goHome()
			return true
		else
			currentStep = candidateCurrentStep
		end
	end

	if _statusStep then
		_statusStep.window:hide()
	end

	if _emptyStep and _emptyStep.window then
		_emptyStep.window:hide()
	end
	_emptyStep = nil

	return true
end


--service method
function getAudioVolumeManager(self)
	return self.volume
end


function init(self)
	_string = function(token)
		return self:string(token)
	end

	jnt:subscribe(self)

	self.volume = Volume(self)
	self.scanner = Scanner(self)
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]


