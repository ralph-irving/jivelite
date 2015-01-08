
local assert, ipairs, pairs, type, tostring, tonumber, setmetatable = assert, ipairs, pairs, type, tostring, tonumber, setmetatable

local oo            = require("loop.base")
local table         = require("jive.utils.table")
local string        = require("jive.utils.string")

local Framework     = require("jive.ui.Framework")
local SimpleMenu    = require("jive.ui.SimpleMenu")
local Window        = require("jive.ui.Window")
local Icon          = require("jive.ui.Icon")

local debug         = require("jive.utils.debug")
local log           = require("jive.utils.log").logger("jivelite.ui")

local appletManager = require("jive.AppletManager")

local EVENT_WINDOW_ACTIVE         = jive.ui.EVENT_WINDOW_ACTIVE
local EVENT_WINDOW_INACTIVE       = jive.ui.EVENT_WINDOW_INACTIVE
local EVENT_UNUSED                = jive.ui.EVENT_UNUSED


-- our class
module(..., oo.class)

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

local function bumpAction(self)
	self.window:playSound("BUMP")
	self.window:bumpLeft()

	return EVENT_CONSUME

end

-- create a new menu
function __init(self, name, style, titleStyle)
	local obj = oo.rawnew(self, {
		window = Window(style or "home_menu", name),
		windowTitle = name,
		menuTable = {},
		nodeTable = {},
		customMenuTable = {},
		customNodes = {},
	})

	local menu = SimpleMenu("menu")
	menu:setComparator(SimpleMenu.itemComparatorComplexWeightAlpha)

	-- home menu is not closeable
	menu:setCloseable(false)

	obj.window:addWidget(menu)
	obj.nodeTable['home'] = {
		menu = menu, 
		items = {}
	}
	
	--Avoid inadvertantly quitting the app.
	obj.window:addActionListener("back", obj, bumpAction)

	local homeRootHandler = function()
					local windowStack = Framework.windowStack

					-- if not at root of home, go to root of home :bug #14066
					if #windowStack == 1 then
						local homeMenu = obj.nodeTable["home"].menu
						if homeMenu:getSelectedIndex() and homeMenu:getSelectedIndex() > 1 then
							Framework:playSound("JUMP")
							homeMenu:setSelectedIndex(1)
							return EVENT_CONSUME
						end
					end

					--otherwise let standard action hanlder take over
					return EVENT_UNUSED
				end

	obj.window:addActionListener("go_home", obj, homeRootHandler)
	obj.window:addActionListener("go_home_or_now_playing", obj, homeRootHandler)


	-- power button, delayed display so that "back back back power" is avoided (if power button is selected as home press
	obj.window:setButtonAction("lbutton", "home_title_left_press", "home_title_left_hold", "soft_reset", true)

	obj.window:addListener( EVENT_WINDOW_ACTIVE,
				function()
					--only do timer when we know "home press" is power (still might be missing from INACTIVE handling if shortcuts changed recently) 
					if Framework:getActionToActionTranslation("home_title_left_press") == "power" then
						obj.window:addTimer(    1000,
									function ()
										obj.window:setButtonAction("lbutton", "home_title_left_press", "home_title_left_hold", "soft_reset", true)
									end,
									true)
					else
						obj.window:setButtonAction("lbutton", "home_title_left_press", "home_title_left_hold", "soft_reset", true)
					end
					return EVENT_UNUSED
				end)

	obj.window:addListener( EVENT_WINDOW_INACTIVE,
				function()
					if Framework:getActionToActionTranslation("home_title_left_press") == "power" then
						obj.window:setButtonAction("lbutton", nil)
					end
					return EVENT_UNUSED
				end)

	return obj
end

function getMenuItem(self, id)
	return self.menuTable[id]
end

function getMenuTable(self)
	return self.menuTable
end

function getNodeTable(self)
	return self.nodeTable
end

function getNodeText(self, node)
	assert(node)
	if self.nodeTable[node] and self.nodeTable[node]['item'] and self.nodeTable[node]['item']['text'] then
		return self.nodeTable[node]['item']['text']
	else
		return nil
	end
end

function getComplexWeight(self, id, item)
	if self.menuTable[id]['node'] == 'home' then
		return item.weight
	elseif self.menuTable[id]['node'] == 'hidden' then
		return self.menuTable[id].hiddenWeight and self.menuTable[id].hiddenWeight or 100
	else
		local nodeItem = self.menuTable[id]['node']
		if not self.menuTable[nodeItem] then
			log:warn('when trying to analyze ', item.text, ', its node, ', nodeItem, ', is not currently in the menuTable thus no way to establish a complex weight for sorting')
			return item.weight
		else
			return self:getComplexWeight(self.menuTable[id]['node'], self.menuTable[nodeItem]) .. '.' .. item.weight
		end
	end
end

function setRank(self, item, rank)
	log:debug('setting rank for ', item.id , ' from ', item.rank, ' to ', rank)
	item.rank = rank
end


function getWeight(self, item)
	return item.weight
end

-- goes through an established home menu node and sets the ranks from 1..N
-- assists in the ability for CustomizeHomeMenuApplet to move items up/down one in the menu
-- also needs to be run after any item is added to an already ranked menu
function rankMenuItems(self, node)
	if not self.nodeTable and not self.nodeTable[node] then
		log:error('rankMenuItems not given proper args')
                return
        end
	local menu = self:getNodeMenu(node)

        local rank = 1
        for i, v in ipairs (menu.items) do
                self:setRank(v, rank)
                rank = rank + 1
		log:debug('v.id: ', v.id, ' rank: ', rank, '--->', v)
        end

	menu:setComparator(SimpleMenu.itemComparatorRank)
end


function getNodeMenu(self, node)
	local menu = self.nodeTable and self.nodeTable[node] and self.nodeTable[node].menu
	if not menu or not menu.items then
		log:error('no menu object found for ', node)
                return false
        end
	return menu
end


function itemUpOne(self, item, node)
	if not node then
		node = 'home'
	end
	local menu = self:getNodeMenu(node)
	if not menu then
		return
	end
	
	-- first make sure we have a ranked weight menu
	self:rankMenuItems(node)

	local rank = 1
	for i, v in ipairs(menu.items) do
		if v == item then
			if rank == 1 then
				log:info('Item is already at the top')
			else
				local itemAbove = menu.items[i - 1]
				self:setRank(itemAbove, rank)
				self:setRank(v, rank - 1)
				menu:setSelectedIndex(rank - 1)
				menu:setComparator(SimpleMenu.itemComparatorRank)
				break
			end
		end
		rank = rank + 1
	end
end

function itemDownOne(self, item, node)
	if not node then
		node = 'home'
	end
	local menu = self:getNodeMenu(node)
	if not menu then
		return
	end

	-- first make sure the items are ranked in order
	self:rankMenuItems(node)
	
	local rank = 1
	for i, v in ipairs(menu.items) do
		if v == item then
			if rank == #menu.items then
				log:info('Item is already at the bottom')
			else
				local itemBelow = menu.items[i + 1]
				self:setRank(itemBelow, rank)
				self:setRank(v, rank + 1)
				menu:setComparator(SimpleMenu.itemComparatorRank)
				menu:setSelectedIndex(rank + 1)
				break
			end
		end
		rank = rank + 1
	end
end

function itemToBottom(self, item, node)
	if not node then
		node = 'home'
	end
	local menu = self:getNodeMenu(node)
	if not menu then
		return
	end
	
	-- first make sure the items are ranked in order
	self:rankMenuItems(node)

	local rank = 1
	for i, v in ipairs(menu.items) do
		if v == item then
			if rank == #menu.items then
				log:info('Item is already at the bottom')
			else
				local bottomIndex = #menu.items
				-- note: order matters here, you don't want to rankMenuItems until the menu has been resorted
				self:setRank(v, bottomIndex + 1)
				menu:setSelectedIndex(bottomIndex)
				menu:setComparator(SimpleMenu.itemComparatorRank)
				self:rankMenuItems('home')
				break
			end
		end
		rank = rank + 1
	end
end


function itemToTop(self, item, node)
	if not node then
		node = 'home'
	end
	local menu = self:getNodeMenu(node)
	if not menu then
		return
	end

	-- first make sure the items are ranked in order
	self:rankMenuItems(node)

	local rank = 1
	for i, v in ipairs(menu.items) do
		if v == item then
			if rank == 1 then
				log:info('Item is already at the top')
			else
				self:setRank(v, 1)
			end
		else
			self:setRank(v, rank + 1)

		end
		rank = rank + 1
	end
	menu:setSelectedIndex(1)

	-- sort menu before ranking it
	menu:setComparator(SimpleMenu.itemComparatorRank)
	self:rankMenuItems(node)

end


function setTitle(self, title)
	if title then
		self.window:setTitle(title)
	else
		self.window:setTitle(self.windowTitle)
	end
end

function setCustomNode(self, id, node)
	if self.menuTable[id] then
		local item = self.menuTable[id]
		-- an item from home that is set for 'hidden' should be removed from home
		if item.node == 'home' and node == 'hidden' then
			self:removeItemFromNode(item, 'home')
		end
		self:addItemToNode(item, node)
	end
	self.customNodes[id] = node
end

function setNode(self, item, node)
	assert(item)
	assert(node)

	self:removeItem(item)
	self:setCustomNode(item.id, node)
	self:addItem(item)
end

--[[

Close all windows to expose the home menu. By default alwaysOnTop windows
are not hidden. Also move to root home item.

--]]
function closeToHome(self, hideAlwaysOnTop, transition)

	--move to root item :bug #14066
	if self.nodeTable then
		self.nodeTable["home"].menu:setSelectedIndex(1)
	end

	local stack = Framework.windowStack

	local k = 1
	for i = 1, #stack do
		if stack[i].alwaysOnTop and hideAlwaysOnTop ~= false then
			k = i + 1
		end

		if stack[i] == self.window then
			for j = i - 1, k, -1 do
				stack[j]:hide(transition)
			end
		end
	end
end


function _changeNode(self, id, node)
	-- looks at the node and decides whether it needs to be removed
	-- from a different node before adding
	if self.menuTable[id] and self.menuTable[id].node ~= node then 
		-- remove menuitem from previous node
		self.nodeTable[node].items[id] = nil
		-- change menuitem's node
		self.menuTable[id].node = node
		-- add item to that node
		self:addNode(self.menuTable[id])
	end
end

function exists(self, id)
	return self.menuTable[id] ~= nil
end

function addNode(self, item)

	if not item or not item.id or not item.node then
		return
	end

	item.isANode = 1

	item.cmCallback = function()
		appletManager:callService("homeMenuItemContextMenu", item)
		return EVENT_CONSUME
	end

	if not item.weight then 
		item.weight = 100
	end

	if item.iconStyle then
		item.icon = Icon(item.iconStyle)
	else
		item.iconStyle = 'hm_advancedSettings'
	end
	-- remove/update node from previous node (if changed)
	if self.menuTable[item.id] then
		self.menuTable[item.id].text = item.text
		local newNode    = item.node
		local prevNode   = self.menuTable[item.id].node
		if newNode ~= prevNode then
			_changeNode(self, item.id, newNode)
		end

		return
	end

	local window
	if item.windowStyle then
		window = Window(item.windowStyle, item.text)
	else
		window = Window("home_menu", item.text)
	end

	local menuStyle = 'menu'
	if item.window and item.window.menuStyle then
		menuStyle = item.window.menuStyle .. 'menu'
	end
	local menu = SimpleMenu(menuStyle, item)
	menu:setComparator(SimpleMenu.itemComparatorWeightAlpha)

	window:addWidget(menu)

	self.nodeTable[item.id] = {
		menu = menu,
		item = item,
		items = {}
	}

	if not item.callback then
		item.callback = function ()
			window:setTitle(item.text)
			window:show()
		end
	end

	if not item.sound then
		item.sound = "WINDOWSHOW"
	end
end

-- add an item to a node
function addItemToNode(self, item, node)
	assert(item.id)
	self.node = node
	if node then
		self.customNodes[item.id] = node
		if item.node ~= 'home' and node == 'home' then
			local complexWeight = self:getComplexWeight(item.id, item)
			item.weights = string.split('%.', complexWeight)
		end
	else
		node = item.node
	end
	assert(node)

	if self.nodeTable[node] then
		self.nodeTable[node].items[item.id] = item
		local menuIdx = self.nodeTable[node].menu:addItem(item)
		-- items in the home menu get special handling and a new table created for them
		if node == 'home' then
			--this breaks localization code, punt for now. items moved to the home menu will not display custom text
			--[[
			local labelText = item.homeMenuText
			if not labelText then
				if item.text.str then
					-- FIXME: by grabbing the home menu text directly from item.text.str here, this creates 
					-- a bug where if the user changes languages these items do not change their language
					labelText = item.text.str
				else
					labelText = item.text
				end
			end
			-- change the menu item's text by creating a new item table with different label text
			local myItem = _uses(item, { 
				text = labelText,
			 })
			--]]

			local myItem = _uses(item)

			-- rewrite the callback for CM to use myItem instead of item
			myItem.cmCallback = function()
				appletManager:callService("homeMenuItemContextMenu", myItem)
				return EVENT_CONSUME
			end
			self.customMenuTable[myItem.id] = myItem
			self.nodeTable[node].menu:addItem(myItem)
			self.nodeTable[node].items[myItem.id] = myItem
			return myItem

		else
			return item
		end
	end

end

-- add an item to a menu. the menu is ordered by weight, then item name
function addItem(self, item)
	assert(item.id)
	assert(item.node)

	item.cmCallback = function()
		appletManager:callService("homeMenuItemContextMenu", item)
		return EVENT_CONSUME
	end
	if item.iconStyle then
		item.icon = Icon(item.iconStyle)
	end
	if not item.weight then
		item.weight = 100
	end

	if item.extras and type(item.extras) == 'table' then
		for key, val in pairs(item.extras) do
			item[key] = val
		end
		item.extras = nil
	end

	-- add or update the item from the menuTable
	self.menuTable[item.id] = item

	-- add item to its custom node
	local customNode = self.customNodes[item.id]
	if customNode then
		if customNode == 'hidden' and item.node == 'home' then
			self:addItemToNode(item, customNode)
			self:removeItemFromNode(item, 'home')
			return
		elseif customNode == 'home' then
			self:addItemToNode(item, customNode)
		end
	end

	-- add item to its default node
	self:addItemToNode(item)

	-- add parent node?
	local nodeEntry = self.nodeTable[item.node]

	-- FIXME: this looks like a bug...shouldn't we be adding a node entry also when nodeEntry is false?
	if nodeEntry and nodeEntry.item then
		local hasItem = self.menuTable[nodeEntry.item.id] ~= nil

		if not hasItem then
			-- any entries in items table?
			local hasEntry = pairs(nodeEntry.items)(nodeEntry.items)
			if  hasEntry then
				-- now add the item to the menu
				self:addItem(nodeEntry.item)
			end
		end
	end
end

-- takes an id and returns true if this item exists in either the menuTable or the nodeTable
function isMenuItem(self, id)
	if self.menuTable[id] or self.nodeTable[id] then
		return true
	else
		return false
	end
end

function _checkRemoveNode(self, node)
	local nodeEntry = self.nodeTable[node]

	if nodeEntry and nodeEntry.item then
		local hasItem = self.menuTable[nodeEntry.item.id] ~= nil

		if hasItem then
			-- any entries in items table?
			local hasEntry = pairs(nodeEntry.items)(nodeEntry.items)

			if not hasEntry  then
				self:removeItem(nodeEntry.item)
			end
		end
	end
end

-- remove an item from a node
function removeItemFromNode(self, item, node)
	assert(item)
	if not node then
		node = item.node
	end
	assert(node)
	if node == 'home' and self.customMenuTable[item.id] then
		local myIdx = self.nodeTable[node].menu:getIdIndex(item.id)
		if myIdx ~= nil then
			local myItem = self.nodeTable[node].menu:getItem(myIdx)
			self.nodeTable[node].menu:removeItem(myItem)
		end
	end

	if self.nodeTable[node] then
		self.nodeTable[node].items[item.id] = nil
		self.nodeTable[node].menu:removeItem(item)
		self:_checkRemoveNode(node)
	end


end

-- remove an item from a menu
function removeItem(self, item)
	assert(item)
	assert(item.node)

	if self.menuTable[item.id] then
		self.menuTable[item.id] = nil
	end

	self:removeItemFromNode(item)

	-- if this item is co-located in home, get rid of it there too
	self:removeItemFromNode(item, 'home')

end


function openNodeById(self, id, resetSelection)
	if self.nodeTable[id] then
		if resetSelection then
			self.nodeTable[id].menu:setSelectedIndex(1)
		end
		self.nodeTable[id].item.callback()
		return true
	else
		return false
	end
end


function enableItem(self, item)
	
end

--  disableItem differs from removeItem in that it drops the item into a removed node rather than eliminating it completely
--  this is useful for situations where you would not want GC, e.g., a meta file that needs to continue to be in memory
--  to handle jnt notification events

function disableItem(self, item)
	assert(item)
	assert(item.node)

	if self.menuTable[item.id] then
		self.menuTable[item.id] = nil
	end

	self:removeItemFromNode(item)

	item.node = 'hidden'
	self:addItem(item)

	-- if this item is co-located in home, get rid of it there too
	self:removeItemFromNode(item, 'home')

end

function disableItemById(self, id)
	if self.menuTable[id] then
		local item = self.menuTable[id]
		self:disableItem(item)
	end

end

-- remove an item from a menu by its id
function removeItemById(self, id)
	if self.menuTable[id] then
		local item = self.menuTable[id]
		self:removeItem(item)
	end
end


function getNodeItemById(self, id, node)
	return self.nodeTable and self.nodeTable[node] and self.nodeTable[node].items and self.nodeTable[node].items[id]

end

-- lock an item in the menu
function lockItem(self, item, ...)
	if self.customNodes[item.id] then
		self.nodeTable[self.customNodes[item.id]].menu:lock(...)
	elseif self.nodeTable[item.node] then
		self.nodeTable[item.node].menu:lock(...)
	end
end


-- unlock an item in the menu
function unlockItem(self, item)
	if self.customNodes[item.id] then
		self.nodeTable[self.customNodes[item.id]].menu:unlock()
	elseif self.nodeTable[item.node] then
		self.nodeTable[item.node].menu:unlock()
	end
end


-- iterator over items in menu
function iterator(self)
	return self.menu:iterator()
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

