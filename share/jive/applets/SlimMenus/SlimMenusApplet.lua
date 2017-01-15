
-- stuff we use
local tostring, tonumber, type, sort, setmetatable = tostring, tonumber, type, sort, setmetatable
local pairs, ipairs, select, _assert = pairs, ipairs, select, _assert

local oo                     = require("loop.simple")
local math                   = require("math")
local table                  = require("jive.utils.table")
local string                 = require("string")
                             
local Applet                 = require("jive.Applet")
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
local Keyboard               = require("jive.ui.Keyboard")
local Textarea               = require("jive.ui.Textarea")
local RadioGroup             = require("jive.ui.RadioGroup")
local RadioButton            = require("jive.ui.RadioButton")
local Checkbox               = require("jive.ui.Checkbox")
local SimpleMenu             = require("jive.ui.SimpleMenu")
local Button                 = require("jive.ui.Button")
local DateTime               = require("jive.utils.datetime")
local Task                   = require("jive.ui.Task")
local System                 = require("jive.System")

local DB                     = require("applets.SlimBrowser.DB")
local Volume                 = require("applets.SlimBrowser.Volume")
local Scanner                = require("applets.SlimBrowser.Scanner")
local hasNetworking, Networking  = pcall(require, "jive.net.Networking")

local debug                  = require("jive.utils.debug")

local jiveMain               = jiveMain
local appletManager          = appletManager
local iconbar                = iconbar
local jnt                    = jnt


module(..., Framework.constants)
oo.class(_M, Applet)


local _player = false
local _server = false

local _updatingPlayerPopup = false
local _updatingPromptPopup = false

local _lockedItem = false

local _playerMenus = {}
local _playerScreensaverRegistrations = {}


-- legacy map of item styles to new item style names
-- WARNING - duplicated in SlimBrowserApplet
local styleMap = {
	itemplay = 'item_play',
	itemadd  = 'item_add',
	itemNoAction = 'item_no_arrow',
	albumitem = 'item',
	albumitemplay = 'item_play',
}

-- legacy map of item id/nodes
local itemMap = {
	-- nodes
	myMusic = { "_myMusic", "hidden" , nil, true},
	music_services = { "_music_services", "hidden" },
	music_stores = { "_music_stores", "hidden" },

	-- items
	settingsPlaylistMode = { "settingsPlaylistMode", "advancedSettingsBetaFeatures", 100 },
	playerDisplaySettings = { "playerDisplaySettings", "settingsBrightness", 105 },
}


local idMismatchMap = {
	ondemand = "music_services",
--	radio = "radios" - commented out until we resolve difference between SC and SN regarding Internet radio (SC has as node and items, SN has as single item)

}


-- _safeDeref
-- safely derefence a structure in depth
-- doing a.b.c.d will fail if b or c are not defined
-- _safeDeref(a, "b", "c", "d") will always work (of course, it returns nil if b or c are not defined!)
local function _safeDeref(struct, ...)
	local res = struct
	for i=1, select('#', ...) do
		local v = select(i, ...)
		if type(res) ~= 'table' then return nil end
		if v then
			res = res[v]
			if not res then return nil end
		end
	end
	return res
end

-- defines a new item that inherits from an existing item
local function _uses(parent, value)
        local item = {}
        setmetatable(item, { __index = parent })

        for k,v in pairs(value or {}) do
                if type(v) == "table" and type(parent[k]) == "table" then
                -- recursively inherrit from parent item
                        item[k] = _uses(parent[k], v)
                else
                        item[k] = v
                end
        end

        return item
end


function init(self)
	jnt:subscribe(self)

	self.waitingForPlayerMenuStatus = true
	self.serverHomeMenuItems = {}
end


function notify_serverLinked(self, server)
	if server:isSqueezeNetwork() then
		local currentPlayer = appletManager:callService("getCurrentPlayer")
		if currentPlayer and not (currentPlayer:getSlimServer() and currentPlayer:getSlimServer():isSqueezeNetwork()) then
			--self:_addSwitchToSnMenuItem()
		end
	end
end


function _removeSwitchToSnMenuItem(self)
	log:debug("_removeSwitchToSnMenuItem")

	jiveMain:removeItemById("switchToSn")
end

--service method
function addSwitchToSnMenuItem(self)
	--self:_addSwitchToSnMenuItem(self)
end

--[[
function _addSwitchToSnMenuItem(self)
	log:debug("_addSwitchToSnMenuItem")

	jiveMain:addItem({
		id = 'switchToSn',
		node = 'networkSettings',
		iconStyle = 'hm_advancedSettings',
		text = self:string('MENUS_SQUEEZENETWORK_SWITCH'),
		sound = 'WINDOWSHOW',
		weight = 90,
		callback =      function(event, menuItem)
					if not self:_getSqueezeNetwork() then
						local windowStack = Framework.windowStack
						Framework:playSound("BUMP")
						windowStack[1]:bumpLeft()
						return
					end
					self:_selectMusicSource(function()
									jiveMain:goHome()
								end,
								self:_getSqueezeNetwork())
				end
		})

end
--]]

function notify_networkOrServerNotOK(self, iface)
	log:warn('notify_networkOrServerNotOK')
	if iface and iface:isNetworkError() then
		self.networkError = iface
	else
		self.networkError = false
		self.serverError = true
	end

end


function notify_networkAndServerOK(self, iface)
	self.networkError = false
	self.serverError  = false

	if self.diagWindow then
		self.diagWindow:hide()
		self.diagWindow = nil
	end
end


function notify_serverConnected(self, server)
	log:debug("***serverConnected\t", server)
	local currentPlayer = appletManager:callService("getCurrentPlayer")
	local lastSc = currentPlayer and currentPlayer:getLastSqueezeCenter() or nil

	if (server:isSqueezeNetwork() or server == lastSc) and server ~= _server then
		self:_fetchServerMenu(server)
	end
	
	-- Bug 15633: if the server has just connected and we do not have our menus
	-- yet then the request must have been lost in a transient connection interruption,
	-- so reissue the request. 
	if self.waitingForPlayerMenuStatus 
		and _server and server == _server 
		and _player and _player:isConnected()
	then
		--Get initial menus from connected server.
		_server:userRequest(_sinkSetServerMenuChunk(self, server, true) , _player:getId(), { 'menu', 0, 100, "direct:1" })
	end
end



-- goHome
-- pushes the home window to the top
function goHome(self)
	jiveMain:goHome()
end


-- _updatingPlayer
-- full screen popup that appears until menus are loaded
function _updatingPlayer(self)
	log:debug("_updatingPlayer popup show")

	if _updatingPromptPopup then
		_hidePlayerUpdating()
	end

	if _updatingPlayerPopup then
		-- don't open this popup twice
		return
	end

	local popup = Popup("waiting_popup")
	local icon  = Icon("icon_connecting")
	local label = Label("text", self:string('SLIMBROWSER_UPDATING_FIRMWARE_SQUEEZEBOX'))
	local sublabel = Label("subtext", _player:getName())
	popup:addWidget(icon)
	popup:addWidget(label)
	popup:addWidget(sublabel)
	popup:setAlwaysOnTop(true)

	-- add a listener for KEY_PRESS that disconnects from the player and returns to home
	local disconnectPlayer = function()
		if _player:isLocal() then
			_player:disconnectServerAndPreserveLocalPlayer()
		else
			appletManager:callService("setCurrentPlayer", nil)

		end
		popup:hide()
	end

	popup:addActionListener("back", self, disconnectPlayer)
	popup:addActionListener("go_home", self, disconnectPlayer)

	popup:show()

	_updatingPlayerPopup = popup
end


-- _userTriggeredUpdate
-- full screen popup that appears until user hits brightness on player to start upgrade
function _userTriggeredUpdate(self)
	log:debug("_userTriggeredUpdate popup show")


	if _updatingPromptPopup then
		return
	end


	-- only show this window if the player has a brightness button available
	local playerModel = _player:getModel()
	if playerModel == 'receiver' 
		or playerModel == 'softsqueeze'
		or playerModel == 'softsqueeze3'
		or playerModel == 'controller'
		or playerModel == 'squeezeplay'
		or playerModel == 'squeezeslave'
		then
			return
	end

	local window = Window("text_list", self:string('SLIMBROWSER_PLAYER_UPDATE_REQUIRED'))
	local label = Textarea("text", self:string('SLIMBROWSER_USER_UPDATE_FIRMWARE_SQUEEZEBOX', _player:getName()))
	window:addWidget(label)
	window:setAlwaysOnTop(true)
	window:setAllowScreensaver(false)

	-- add a listener for KEY_HOLD that disconnects from the player and returns to home
	local disconnectPlayer = function()
		if _player:isLocal() then
			_player:disconnectServerAndPreserveLocalPlayer()
		else
			appletManager:callService("setCurrentPlayer", nil)

		end
		window:hide()
	end

	window:addActionListener("back", self, disconnectPlayer)
	window:addActionListener("go_home", self, disconnectPlayer)

	window:show()

	_updatingPlayerPopup = false
end


-- _hidePlayerUpdating
-- hide the full screen popup that appears until player is updated
function _hidePlayerUpdating()
	if _updatingPlayerPopup then
		_updatingPlayerPopup:hide()
		_updatingPlayerPopup = false
	end

	if _updatingPromptPopup then
		_updatingPromptPopup:hide()
		_updatingPromptPopup = false
	end
end


--
--add node to home menu only if this is for the current server or it doesn't exist. Only current server responses may replace existing items.
function  _addNode(self, node, isCurrentServer)
	if isCurrentServer then
		jiveMain:addNode(node)
	else
		if not jiveMain:exists(node.id) then
			jiveMain:addNode(node, true)
		else
			log:debug("node already present: ", node.id)
		end
	end
end
--add item to home menu only if this is for the current server or it doesn't exist. Only current server responses may replace existing items.
function  _addItem(self, item, isCurrentServer, addToHome)
	if isCurrentServer or not _playerMenus[item.id] then
		 _playerMenus[item.id] = item
		 jiveMain:addItem(item)
		if addToHome then
			local customHomeItem = _uses(item, {
				id = 'hm_' .. item.id,
				node = 'home',
			})
			jiveMain:addItem(customHomeItem)
		end
	else
		log:debug("item already present: ", item.id)
	end
end

--register remote ss only if it doesn't exist. Only current server responses may replace existing items.
function  _registerRemoteScreensaver(self, serverData)

	-- when switching music sources, re-register screensavers as the old server might go away
	if _playerScreensaverRegistrations[serverData.id] and _playerScreensaverRegistrations[serverData.id].server ~= serverData.server then
		log:debug("ss already registered, but from different server: ", serverData.id, 
		          " - new: ", serverData.server, 
		          " - old: ", _playerScreensaverRegistrations[serverData.id].server)
		appletManager:callService("unregisterRemoteScreensaver", serverData.id)
		_playerScreensaverRegistrations[serverData.id] = nil
	end

	if not _playerScreensaverRegistrations[serverData.id] then 
		 _playerScreensaverRegistrations[serverData.id] = serverData
		appletManager:callService("registerRemoteScreensaver", serverData)
	else
		log:debug("ss already registered: ", serverData.id)
	end
end


--various compatiblilty hacks
function _massageItem(item)
	if idMismatchMap[item.id] then
		log:debug("fixing mismatch item: ", item.id)

		item.id = idMismatchMap[item.id]
	end

	if itemMap[item.id] then
		local id = item.id
		item.id = itemMap[id][1]
		item.node = itemMap[id][2]
		if itemMap[id][3] then
			item.weight = itemMap[id][3]
		end
		if itemMap[id][4] then
			item.isANode = itemMap[id][4]
		end
	end


	--items such as my apps items that aren't on the home menu come in blank
	if item.node == "" then
		item.node = "hidden"
		item.hiddenWeight = item.weight
	end

	if itemMap[item.node] then
		local node = item.node
		item.node = itemMap[node][1]
	end


end



function _getAppType(request)
	if not request or #request == 0 then
		return nil
	end
	local appType = request[1]

	return appType
end


function _addMyAppsNode(self)
	local version = _player and _player:getSlimServer() and _player:getSlimServer():getVersion()
	local myApps = { id = 'myApps', iconStyle = 'hm_myApps', node = 'home', text = self:string('MENUS_MY_APPS'), weight = 30  } 
	jiveMain:addNode( myApps )
	_playerMenus['myApps'] = myApps

	-- remove the old style My Apps item, if it exists
	jiveMain:removeItemById('opmlmyapps')
	self.myAppsNode = true
	return
end


-- _menuSink
-- returns a sink with a closure to self
-- cmd is passed in so we know what process function to call
-- this sink receives all the data from our Comet interface
local function _menuSink(self, isCurrentServer, server)
	return function(chunk, err)
		local isMenuStatusResponse = not server

		local menuItems, menuDirective, playerId
		if isMenuStatusResponse then
			--this is a menustatus response for the connected player
			if not _player then
				log:warn("catch race condition if we've switch player")
				return
			end

			-- process data from a menu notification
			-- each chunk.data[2] contains a table that needs insertion into the menu
			menuItems = chunk.data[2]
			-- directive for these items is in chunk.data[3]
			menuDirective = chunk.data[3]
			-- the player ID this notification is for is in chunk.data[4]
			playerId = chunk.data[4]

			if playerId ~= 'all' and playerId ~= _player:getId() then
				log:debug('This menu notification was not for this player')
				log:debug("Notification for: ", playerId)
				log:debug("This player is: ", _player:getId())
				return
			end

			if _server and menuDirective == "add" then
				self:_addServerHomeMenuItems(_server, menuItems)
			end
		else
			--this is a response from a "menu" command for a non-connected player
			menuItems = chunk.data.item_loop
			self:_addServerHomeMenuItems(server, menuItems)

		end

		-- if we get here, it was for this player. set menuReceived to true
		_menuReceived = true

		log:info("_menuSink(" .. #menuItems ..") ", server, " menuDirective: ", menuDirective, " isCurrentServer:" , isCurrentServer)

		for k, v in pairs(menuItems) do

			local addAppToHome = false
			local item = {
					id = v.id,
					node = v.node,
					isApp = v.isApp,
					iconStyle = v.iconStyle,
					style = v.style,
					text = v.text,
					homeMenuText = v.homeMenuText,
					weight = v.weight,
					window = v.window,
					windowStyle = v.windowStyle,
					sound = "WINDOWSHOW",
					screensavers = v.screensavers
			}

			if item.isApp == 1 then
				if not self.myAppsNode then
					self:_addMyAppsNode()
				end
				if item.node == 'home' then
					addAppToHome = true
				end
				item.node = 'myApps'
			end

			local itemIcon
			if v.window then
				itemIcon = v.window['icon-id'] or v.window['icon']
			else
				itemIcon = v['icon-id'] or v['icon']
			end

			if not v.window then
				v.window = {}
			end
			if not v.window.windowId then
				v.window.windowId = v.id
			end

			if itemIcon then
				-- Fetch artwork if we're connected, or it's remote
				-- XXX: this is wrong, it fetches *all* icons in the menu even if they aren't displayed
				--item["icon-id"] = itemIcon
				local iconServer
				if server then
					iconServer = server
				else
					iconServer = _server
				end
				local _size = jiveMain:getSkinParam('THUMB_SIZE_MENU')
				item.icon = Icon('icon')
				iconServer:fetchArtwork(itemIcon, item.icon, _size, 'png')

				-- Hack alert: redefine the checkSkin function
				-- to reload images when the skin changes. We
				-- should replace this with resizable icons.
				local _style = item.icon.checkSkin
				item.icon.checkSkin = function(...)
					local s = jiveMain:getSkinParam('THUMB_SIZE_MENU')
					if s ~= _size then
						_size = s
						iconServer:fetchArtwork(itemIcon, item.icon, _size, 'png')
					end

					_style(...)
				end

				local appType = _getAppType(_safeDeref(v, 'actions', 'go', 'cmd'))
				if appType then
					iconServer:setAppParameter(appType, "iconId", itemIcon)
				end
			else
				-- make a style
				if item.id and not item.iconStyle then
					local iconStyle = 'hm_' .. item.id
					item.iconStyle = iconStyle
				end
			end

			if isCurrentServer and item.screensavers then
				for _, serverData in ipairs(item.screensavers) do
					serverData.id = table.concat(serverData.cmd, " ")
					serverData.playerId = _player:getId()
					serverData.server = _server
					serverData.appParameters = _server:getAppParameters(_getAppType(_safeDeref(v, 'actions', 'go', 'cmd')))

					self:_registerRemoteScreensaver(serverData)
				end
			end

			-- hack to modify styles from SC
			if item.style and styleMap[item.style] then
				item.style = styleMap[item.style]
			end
			local choiceAction = _safeDeref(v, 'actions', 'do', 'choices')

			_massageItem(item, item)

			if not item.id then
				log:info("no id for menu item: ", item.text)
			elseif item.id == 'opmlmyapps' and self.myAppsNode then
				--ignore, if self.myAppsNode is set that means we're delivering My Apps via a node and opml home menu items
			elseif item.id == "playerpower" and System:hasSoftPower() and System:getMachine() ~= 'squeezeplay' then
				--ignore, playerpower no longer shown to users since we use power button, unless this is a device without a power button
			elseif item.id == "settingsPIN" then
				--ignore, pin no longer shown to users since we use user/pass now
			elseif item.id == "settingsPlayerNameChange" and not isCurrentServer then
				--ignore, only applicable to currently selected server
			elseif item.id == "settingsSleep" and not isCurrentServer then
				--ignore, only applicable to currently selected server
			elseif item.id == "settingsAudio"  then
				--ignore, now shown locally
			elseif item.id == "radios" then
				--ignore, shown locally
			elseif item.id == "music_services" or item.id == "_music_services" then
				--ignore, handled with app store

			elseif item.id == "settingsAlarm" then
				--ignore as we can't render time input at present
				-- FIXME - remove when time input can be rendered in HD skins

			elseif item.node == "music_services" or item.node == "_music_services" then
				--ignore, handled with app store
			elseif item.id == "music_stores" or item.id == "_music_stores" then
				--ignore, handled with app store
			elseif item.node == "music_stores" or item.node == "_music_stores" then
				--ignore, handled with app store
			elseif v.isANode or item.isANode then
				if item.id ~= "_myMusic" then
					self:_addNode(item, isCurrentServer)
				else
					log:info("Eliminated myMusic node from server, since now handled locally")

				end
			elseif menuDirective == 'remove' then
				--todo: massage SN request to remove myMusicMusicFolder
				jiveMain:removeItemById(item.id)

			elseif isCurrentServer and choiceAction then
--				debug.dump(choiceAction, 4)

				local selectedIndex = 1
				if v.selectedIndex then
					selectedIndex = tonumber(v.selectedIndex)
				end

				local choice = Choice(
					"choice",
					v.choiceStrings,
					function(obj, selectedIndex)
						local jsonAction = v.actions['do'].choices[selectedIndex]
						appletManager:callService("browserJsonRequest", _server, jsonAction)
					end,
					selectedIndex
				)
				
				item.style = 'item_choice'
				item.check = choice

				item.removeOnServerChange = true

				--add the item to the menu
				self:_addItem(item, isCurrentServer, addAppToHome)

			else
				local actionInternal = function (noLocking)
							log:debug("send browserActionRequest request")
							local alreadyUnlocked = false
							local step = appletManager:callService("browserActionRequest", nil, v,
								function()
									jiveMain:unlockItem(item)
									_lockedItem = false
									alreadyUnlocked = true
								end)

							if not v.input then -- no locks for an input item, which is immediate
								_lockedItem = item
								if not alreadyUnlocked and not noLocking then
									jiveMain:lockItem(item, function()
										appletManager:callService("browserCancel", step)
									end)
								end
							end
						end

				if _safeDeref(v, 'actions', 'play') then
					--used with, for instance, RandomPlay
					item.isPlayableItem = true
				end

				item.callback = function(_, _, noLocking)
					local action = function () actionInternal(noLocking) end
					local switchToSn =
						function()
							local lastSc
							if _server and not _server:isSqueezeNetwork() then
								lastSc = _server
							elseif _player then
								lastSc = _player:getLastSqueezeCenter()
							end
							self:_selectMusicSource(action, self:_getSqueezeNetwork(), lastSc, true)
						end

					local switchToSc =
						function()
							self:_selectMusicSource(action, _player and _player:getLastSqueezeCenter() or nil,
							  self:_getSqueezeNetwork(), true)
						end

					local switchToSnForSnOnlyItem =
						function()
							self:_selectMusicSource(action, self:_getSqueezeNetwork(),
							 nil, true)
						end

					local switchToScForScOnlyItem =
						function()
							self:_selectMusicSource(action, _player and  _player:getLastSqueezeCenter() or nil,
							  nil, true)
						end

					local currentPlayer = appletManager:callService("getCurrentPlayer")

					-- if we know there is a network error condition, push on a diags window immediately
					-- Bug 16552: don't push to diags window if player has tinySC and tinySC is running
					if self.networkError and not ( System:hasTinySC() and appletManager:callService("isBuiltInSCRunning") ) then
						log:warn('Network reported as not OK')
						self.diagWindow = appletManager:callService("networkTroubleshootingMenu", self.networkError)
						-- make sure we got a window generated to confirm we can leave this method
						if self.diagWindow then
							log:warn("we've pushed a diag window, so we're done here")
							return
						end
					end

					if not _server then
						--should only happen if we load SN disconnected items and user selects one prior to _server being set on notify_playerCurrent
						-- maybe we should wait in this case until it is loaded, but for how long, and then what after timeout?
						--this case is a bit ugly. We don't know if SC will be able to serve it, so we shouldn't switch to SC
						local initServer = appletManager:callService("getInitialSlimServer")
						if not initServer  or (initServer and not initServer:isSqueezeNetwork() and  self:_canSqueezeNetworkServe(item)) then
							log:info("Switch to SN when _server is nil")
							switchToSn()
						else
							log:info("Switch to SC when _server is nil")
							switchToSc()
						end
					else
						--_server exists
						if self.playerOrServerChangeInProgress then
							--happens on failed attempt to chose a different server, re-connect to same
							if _server:isSqueezeNetwork() then
								log:info("switching to SN from SC, server change failure: ", _server)
								if _player then
									_player:setServerRefreshInProgress(true)
								end
								_server:disconnect()
								switchToSn()
							else
								log:info("switching to SC from SN, server change failure: ", _server)
								if _player then
									_player:setServerRefreshInProgress(true)
								end
								_server:disconnect()
								switchToSc()
							end
						else
							if not _server:isConnected() then
								if not _server:isSqueezeNetwork() and self:_canSqueezeNetworkServe(item) then
									log:info("switching to SN from SC, connection issue: ", _server)
									switchToSn()
								elseif _server:isSqueezeNetwork() and self:_canSqueezeCenterServe(item) then
									log:info("switching to SC from SN, connection issue: ", _server)
									switchToSc()
								else
									log:info("only the current server can serve, let slim browse handle the connection issue")
									action()
								end
							else
								--server is connected
								if _server:isSqueezeNetwork() and not self:_canSqueezeNetworkServe(item) then
									log:debug("switching to SC for SC-only item: ", _server)
									switchToScForScOnlyItem()
								elseif not _server:isSqueezeNetwork() and not self:_canSqueezeCenterServe(item) then
									log:debug("switching to SN for SN-only item ")
									switchToSnForSnOnlyItem()
								else
									log:debug("Current server can serve: ", server)
									action()
								end
							end

						end
					end
				end

				self:_addItem(item, isCurrentServer, addAppToHome)
			end
		end

		if _menuReceived and isCurrentServer then
			log:info("hiding any 'connecting to server' popup after menu response from current server, ", _server)

			self.waitingForPlayerMenuStatus = false
			jnt:notify("playerLoaded", _player)
			appletManager:callService("hideConnectingToServer")

			--[[
			if _server:isSqueezeNetwork() then
				self:_removeSwitchToSnMenuItem()
			else
				self:_addSwitchToSnMenuItem()
			end
			--]]

		end
         end
end


--service method
function warnOnAnyNetworkFailure(self, successCallback, failureCallback)
	if not hasNetworking then
		successCallback()
		return
	end

	Task("checkNetworkConnection", self,
		function()
			log:debug("warnOnAnyNetworkFailure: checkNetworkConnection task")

			local iface = Networking:activeInterface()

			if not iface then
				log:error("Post-setup, there should always be an active interface")
			else
				if iface:isWireless() then
					-- wireless strength
					local percentage = iface:getSignalStrength()
					if not percentage or percentage == 0 then
						return failureCallback(self:_networkFailureWindow(false, successCallback))
					end
				else
					-- wired
					local status = iface:status()
					if not status.link then
						return failureCallback(self:_networkFailureWindow(true, successCallback))
					end
				end
			end
			successCallback()
		end):addTask()

end


function _networkFailureWindow(self, isWired, successCallback)
	local window = Window("error", self:string("MENUS_CONNECTION_ERROR"))
	window:setAllowScreensaver(false)

	local menu = SimpleMenu("menu",
				{
					{
						text = self:string("MENUS_TRY_AGAIN"),
						sound = "WINDOWSHOW",
						callback = function()
								   window:hide()
							   end
					},
					{
						text = self:string("MENUS_CHOOSE_DIFFERENT_NETWORK"),
						sound = "WINDOWSHOW",
						callback = function()
								   appletManager:callService("settingsNetworking")
							   end
					},
				})

	-- Fab4 only - If built in SC (TinySC) is running allow to continue without a network
	if (System:getMachine() == "fab4") and appletManager:callService("isBuiltInSCRunning") then
		menu:addItem({
			text = self:string("MENUS_CONTINUE_WITHOUT_NETWORK"),
			sound = "WINDOWSHOW",
			callback = function()
				window:hide()
				successCallback()
			end
		})
	end

	local helpText
	if isWired then
		helpText = self:string("MENUS_ATTACH_CABLE_DETAILED")
	else
		helpText = self:string("MENUS_NO_WIRELESS_DETAILED")
	end

	menu:setHeaderWidget(Textarea("help_text", helpText))
	window:addWidget(menu)

	window:show()

	return window
end


function _canSqueezeCenterServe(self, item)
	local sc = _server:isSqueezeNetwork() and _player:getLastSqueezeCenter() or _server
	--_player:getLastSqueezeCenter() will fail for remote player
	return self:_canServerServe(sc, item)
end

function _canSqueezeNetworkServe(self, item)
	return self:_canServerServe(self:_getSqueezeNetwork(), item)
end


function _canServerServe(self, server, item)
	local menuItems = self.serverHomeMenuItems[server]
	if not menuItems then
		log:error("server can not serve, menus not here (yet). item: ", item.id, " server: ", server)
	        return false
	end

	if menuItems[item.id] then
		log:debug("Server can serve item: ", item.id, " server: ", server)
		return true
	end

	log:debug("Server can not serve item: ", item.id, " server: ", server)

	return false
end

function _getSqueezeNetwork(self)
	for server, items in pairs(self.serverHomeMenuItems) do
		if server:isSqueezeNetwork() then
			return server
		end
	end

	return nil
end


function _addServerHomeMenuItems(self, server, menuItems)
	if not self.serverHomeMenuItems[server] then
		self.serverHomeMenuItems[server] = {}
	end

	for i, v in ipairs(menuItems) do
		log:debug("adding cached item: ", v.id, " for server:", server)

		if v.id then
			self.serverHomeMenuItems[server][v.id] = v
		else
			log:info("No id for:", v.text)
			debug.dump(v)
		end
	end
end


function _updateMyMusicTitle(self, serverName)
	local myMusicNode = jiveMain:getMenuTable()["_myMusic"]
	-- it is possible on some branches for there to be no myMusicNode
	if not myMusicNode then
		return
	end

	if not myMusicNode.originalNodeText then
		myMusicNode.originalNodeText = myMusicNode.text
		--todo: this doesn't handle on-the-fly language change well
	end

	if not serverName or serverName == "mysqueezebox.com" then
		myMusicNode.text = myMusicNode.originalNodeText
	else
		myMusicNode.text =  serverName
	end
end

-- notify_playerNewName
-- this is called when the player name changes
-- we update our main window title
function notify_playerNewName(self, player, newName)
	log:debug("SlimMenusApplet:notify_playerNewName(", player, ",", newName, ")")

	-- if this concerns our player
	if _player == player then
		jiveMain:setTitle(newName)
	end
end

function _addServerNameToHomeTitle(self, name)
	log:debug("_addServerNameToHomeTitle:, ", _server)

	if _server then
		name = name .. "(" .. _server.name ..")"
	end

	return name
end


function _showInstallServerWindow(self)
	local window = Window("help_list", self:string("MENUS_MY_MUSIC"), "setuptitle")

	local textarea = Textarea("help_text", self:string("INSTALL_SC_TEXT"))

	local cancelAction = function()
		self.playerConnectedCallback = nil
		window:hide()

		return EVENT_CONSUME
	end

	window:addActionListener("back", self, cancelAction)
	window:addActionListener("go_home", self, cancelAction)

	window:addWidget(textarea)

	window:show()
end


function _anyKnownSqueezeCenters(self)
	--Note: this logic is a bit of a duplicate of the servers accumulation code in ChooseMusicSource code 
	-- squeezecenter on the poll list
	local poll = appletManager:callService("getPollList")
	for address,_ in pairs(poll) do
		log:debug("\t", address)
		if address ~= "255.255.255.255" then
			log:debug("Found polled server: ", address)
			return true
		end
	end


	-- discovered squeezecenters
	log:debug("Discovered Servers:")
	for _,server in appletManager:callService("iterateSqueezeCenters") do
		if not server:isSqueezeNetwork() then
			log:debug("Found server: ", server)
			return true
		end
	end

	return false
end

function _selectMusicSource(self, callback, specificServer, serverForRetry, confirmOnChange)
	local successCallback = function()
					self:_selectMusicSourceInternal(callback, specificServer, serverForRetry, confirmOnChange)
				end
	local failureCallback = function(failureWindow)
					--todo auto hide failure window if reconnection successful
				end
	self:warnOnAnyNetworkFailure(successCallback, failureCallback)
end


function _selectMusicSourceInternal(self, callback, specificServer, serverForRetry, confirmOnChange)

	local currentPlayer = appletManager:callService("getCurrentPlayer")
--	if not currentPlayer or not currentPlayer.info.connected then
	--todo: handle situation where player is down; above code also fails when server is down, not what we want
	--issue also happened where player mac changed (might not be real world scenerio)
	if not currentPlayer then
		log:info("No player yet, first select player (which will trigger choose music soure, then go home")
		appletManager:callService("setupShowSelectPlayer")
		return
	end

	appletManager:callService("selectMusicSource",
							callback,
							nil,
							nil,
							specificServer,
							serverForRetry,
							self.waitingForPlayerMenuStatus,
							confirmOnChange
						)
end


function myMusicSelector(self)
	--first check for "new device, no SC situation"
	local initialServer = appletManager:callService("getInitialSlimServer")
	if (not initialServer or initialServer:isSqueezeNetwork()) and not self:_anyKnownSqueezeCenters() then
		self:_showInstallServerWindow()
		return
	end

	if not _player then
		--this can happen when SN was last server, but SN is down/can't be connected to
		local connectServer = _server
		if _server and _server:isSqueezeNetwork() then
			--can't get "My Music" from SN, try to get lastSC from current player
			local currentPlayer = appletManager:callService("getCurrentPlayer")
			connectServer = currentPlayer and currentPlayer:getLastSqueezeCenter() or nil
		end
		self:_selectMusicSource(function()
						jiveMain:goHome()
						self:_updateMyMusicTitle(_server and _server.name or nil)
						jiveMain:openNodeById('_myMusic', true)
					end,
					connectServer)
	elseif not _server then
		self:_selectMusicSource(function()
						jiveMain:goHome()
						self:_updateMyMusicTitle(_server and _server.name or nil)
						jiveMain:openNodeById('_myMusic', true)
					end)

	elseif _server:isSqueezeNetwork() then
		--offer switch back to SC
		self:_selectMusicSource(function()
						self:_updateMyMusicTitle(_server and _server.name or nil)
						jiveMain:openNodeById('_myMusic', true)
					end,
					_player:getLastSqueezeCenter(), nil, true)
	else
		if not appletManager:callService("getCurrentPlayer") then
			appletManager:callService("setupShowSelectPlayer")
		else
			if _server:isConnected() then
				if self.waitingForPlayerMenuStatus then
					log:warn("server found, but menus not loaded, so show waiting popup")

					appletManager:callService("showConnectToServer",
								function()
									self:_updateMyMusicTitle(_server and _server.name or nil)
									jiveMain:openNodeById('_myMusic', true)
								end,
								_server)
				else
					self:_updateMyMusicTitle(_server and _server.name or nil)
					jiveMain:openNodeById('_myMusic')
				end
			else
				self:_selectMusicSource(function()
								self:_updateMyMusicTitle(_server and _server.name or nil)
								jiveMain:openNodeById('_myMusic', true)
							end,
							_server)
			end
		end
	end
end

function otherLibrarySelector(self)
	self:_selectMusicSource(function()
					jiveMain:goHome()
					self:_updateMyMusicTitle(_server and _server.name or nil)
					jiveMain:openNodeById('_myMusic', true)
				end, false)
end


-- notify_playerCurrent
-- this is called when the current player changes (possibly from no player)
function notify_playerCurrent(self, player)
	log:info("SlimMenusApplet:notify_playerCurrent(", player, ")")

	-- has the player actually changed?
	if _player == player and not self.waitingForPlayerMenuStatus then
		if player then
			if _server == player:getSlimServer() and not self.playerOrServerChangeInProgress then
				log:debug("player and server didn't change , not changing menus: ", player)
				return
			else
				-- Bug 17172
				self.myAppsNode = false

				-- server changed, ergo playerMenus may also be different. Remove the existing ones
				for id, v in pairs(_playerMenus) do
					jiveMain:removeItem(v)
				end

				_server = player:getSlimServer()

				local playerName = _player:getName()
				self:_updateMyMusicTitle(_server and _server.name or nil)

				jiveMain:setTitle(playerName)

			end
		else
			--no current or old player yet
			return
		end
	end

	if player and not player:getSlimServer() then
		log:info("player changed from:", _player, " to ", player, " but server not yet present")
	end

	if _player ~= player then
		-- free current player, since it has changed from one player to another
		if _player then
			self:free()
		end
		
		--recache homemenu items from disconnected server
		if self.serverInitComplete then
			local lastSc = player and player:getLastSqueezeCenter() or nil
			for _,server in appletManager:callService("iterateSqueezeCenters") do
				if server:isCompatible() and (server:isSqueezeNetwork() or server == lastSc) and server ~= _server then
					self:_fetchServerMenu(server)
				elseif not server:getVersion() then
					--todo: server version can now be learned from discovery data
					log:warn("Compatibility not yet known, menu data may be lost: ", server)
				else
					log:debug("not compatible: ", server)
				end
			end
		end
	end

	-- nothing to do if we don't have a player
	-- NOTE don't move this, the code above needs to run when disconnecting
	-- for all players.
	if not player then
		return
	end

	if not _server and not self.serverInitComplete then
		--serverInitComplete check to avoid reselecting server on a soft_reset
		self.serverInitComplete = true
		_server = appletManager:callService("getInitialSlimServer")
		log:info("No server, Fetching initial server, ", _server)
	end

	--can't subscribe to menustatus until we have a server
	if not player:getSlimServer() then
		return
	end

	if not player:getSlimServer():isConnected() then
		log:info("player changed from:", _player, " to ", player, " but server not yet connected")
		return
	end

	self.playerOrServerChangeInProgress = false

	log:info("player changed from:", _player, " to ", player, " for server: ", player:getSlimServer(), " from server: ", _server)

	_player = player
	_server = player:getSlimServer()

	local _playerId = _player:getId()

	self.waitingForPlayerMenuStatus = true
	log:info('\nSubscribing to /slim/menustatus/\n', _playerId)
	local cmd = { 'menustatus' }
	_player:subscribe(
		'/slim/menustatus/' .. _playerId,
		_menuSink(self, true, nil),
		_playerId,
		cmd
	)

	--Get initial menus from connected server.
	_server:userRequest(_sinkSetServerMenuChunk(self, _server, true) , _playerId, { 'menu', 0, 100, "direct:1" })

	-- add a fullscreen popup that waits for the _menuSink to load
	_menuReceived = false

	if player:isLocal() and not _server:isSqueezeNetwork() then
		--local player keep track of previous SC connected to so "return to SC" can occur when re-attempting local content after being on SN
		player:setLastSqueezeCenter(_server)
	end

	if player:getSlimServer() then

		local playerName = _player:getName()
--		playerName = self:_addServerNameToHomeTitle(playerName)
		self:_updateMyMusicTitle(_server.name)

		jiveMain:setTitle(playerName)

		-- display upgrade pops (if needed)
		self:notify_playerNeedsUpgrade(player)
	end

end


function notify_playerNeedsUpgrade(self, player, needsUpgrade, isUpgrading)
	if _player ~= player then
		return
	end

	if _player:isNeedsUpgrade() then
		if _player:isUpgrading() then
			_updatingPlayer(self)
		else
			_userTriggeredUpdate(self)
		end
	else
		_hidePlayerUpdating()
	end
end

-- notify_playerDelete
-- this is called when the player disappears
function notify_playerDelete(self, player)
	log:debug("notify_playerDelete(", player, ")")

	if _player == player then
		-- unsubscribe from this player's menustatus
		if _player then
			_player:unsubscribe('/slim/menustatus/' .. _player:getId())
		end
		self.playerOrServerChangeInProgress = true
	end
end


function _fetchServerMenu(self, server)
	log:debug("Fetching menu for server: ", server)

	if server:isSqueezeNetwork() and (not server:isConnected() or not server:isSpRegisteredWithSn()) then
		log:info("not registered or not yet connected with SN, so not fetching SN menus. connected:", server:isConnected())
		return
	end

	local playerId
	if _player then
		playerId = _player:getId()
	else
		--_player might not be set yet(during startup), so fallback to getCurrentPlayer()
		local currentPlayer = appletManager:callService("getCurrentPlayer")
		if currentPlayer then
			playerId = currentPlayer:getId()
		else
			-- Use local player ID if we don't have a controlling player
			local localPlayer = Player:getLocalPlayer()
			if localPlayer then --might not have a local player either
				playerId = localPlayer:getId()
			end
		end
	end
	if playerId then
		server:userRequest(_sinkSetServerMenuChunk(self, server) , playerId, { 'menu', 0, 100, "direct:1" })
	end

end

function _sinkSetServerMenuChunk(self, server, isConnectedServer)
	return function(chunk, err)
		local menuItems = chunk.data.item_loop
		for _, item in pairs(menuItems) do
			local oldId = item.id

			_massageItem(item)
		end

		self:_mergeServerMenuToHomeMenu(server, menuItems, isConnectedServer)
	end
end




function _mergeServerMenuToHomeMenu(self, server, menuItems, isConnectedServer)
	log:debug("MERGE menus:", server)
	--create chunk wrapper
	local chunk = {}
	chunk.data = {}
	chunk.data.item_loop = menuItems

	_menuSink(self, isConnectedServer, server)(chunk)

end


function free(self)

	self.serverHomeMenuItems = {}

	self.waitingForPlayerMenuStatus = true

	-- unsubscribe from this player's menustatus
	if _player then
		_player:unsubscribe('/slim/menustatus/' .. _player:getId())
	end

	-- remove player menus
	jiveMain:setTitle(nil)

	-- Bug 17172
	self.myAppsNode = false

	for id, v in pairs(_playerMenus) do
		jiveMain:removeItem(v)
	end
	_playerMenus = {}

	for id, v in pairs(_playerScreensaverRegistrations) do
		appletManager:callService("unregisterRemoteScreensaver", id)
	end
	_playerScreensaverRegistrations = {}

	-- make sure any home menu itema are unlocked
	if _lockedItem then
		jiveMain:unlockItem(_lockedItem)
		_lockedItem = false
	end

	_hidePlayerUpdating()

	_player = false
	_server = false
end
