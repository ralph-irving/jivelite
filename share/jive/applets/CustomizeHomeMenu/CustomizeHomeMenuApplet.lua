
--[[
=head1 NAME

applets.CustomizeHomeMenu.CustomizeHomeMenuApplet - Customize Home Menu Applet

=head1 DESCRIPTION

This applet is to allow for a user to customize what items are displayed/hidden from the home menu

=head1 FUNCTIONS

Applet related methods are described in L<jive.Applet>. 

=cut
--]]


-- stuff we use
local tostring, tonumber, pairs, ipairs, table = tostring, tonumber, pairs, ipairs, table
local oo                     = require("loop.simple")
local string                 = require("string")
local string                = require("jive.utils.string")
local table                  = require("jive.utils.table")

local Applet                 = require("jive.Applet")
local Checkbox               = require("jive.ui.Checkbox")
local Window                 = require("jive.ui.Window")
local ContextMenuWindow      = require("jive.ui.ContextMenuWindow")
local Textarea               = require('jive.ui.Textarea')
local Framework              = require('jive.ui.Framework')
local Timer                  = require('jive.ui.Timer')

local SimpleMenu             = require("jive.ui.SimpleMenu")

local debug                  = require("jive.utils.debug")
local jiveMain               = jiveMain
local appletManager          = appletManager
local jnt                    = jnt

module(..., Framework.constants)
oo.class(_M, Applet)

-- FIXME: this method should be farmed out to SimpleMenu as a function called from _itemRenderer()
-- _indent
-- returns a string of <size> spaces
local function _indent(indentSize)
	local indent = ''
	if not indentSize then
		return indent
	end
	for i = 1, tonumber(indentSize) do
		indent = tostring(indent) .. ' '
	end
	return indent
end

-- method to give menu of hidden items that can be restored individually back to home menu
-- this feature is currently disabled in the Meta file.
function restoreHiddenItemMenu(self, menuItem)
	local settings = self:getSettings()

	local window = Window('home_menu', self:string("RESTORE_HIDDEN_ITEMS"))
	local menu   = SimpleMenu("menu")
	local menuTable = jiveMain:getMenuTable()
	local atLeastOneItem = false
	for id, item in pairs(menuTable) do
		if settings[id] == 'hidden' then
			atLeastOneItem = true
			menu:addItem({
				text = item.text,
				iconStyle = item.iconStyle,
				callback = function()
					appletManager:callService("goHome")
					self:_timedExec( function()
						self:getSettings()[item.id] = 'home'
						jiveMain:addItemToNode(item, 'home')
						self:_storeSettings('home')

						-- immediately jump to the item that's been restored
						local menu = jiveMain:getNodeMenu('home')
						local restoredItemIdx = menu:getIdIndex(item.id)
						menu:setSelectedIndex(restoredItemIdx)

						local somethingHidden = false
						for id, item in pairs(menuTable) do
							if self:getSettings()[id] == 'hidden' then
								somethingHidden = true
							end
						end
					end, 500)
					return EVENT_CONSUME
				end,
			})
		end
	end

	local helpText = Textarea( 'help_text', self:string('RESTORE_HIDDEN_ITEMS_HELP') )

	if not atLeastOneItem then
		window = Window('text_list', self:string("RESTORE_HIDDEN_ITEMS"))
		helpText    = Textarea('help_text', self:string('NO_HIDDEN_ITEMS') )
		menu:addItem({
			text = self:string('CUSTOMIZE_CANCEL'),
			callback = function()
				window:hide(Window.transitionPushRight)
				return EVENT_CONSUME
			end
		})
	end

	menu:setHeaderWidget(helpText)
	window:addWidget(menu)
	window:show()
end

function menu(self, menuItem)

	log:info("menu")

	local menu = SimpleMenu("menu")
	-- add an entry for help
	menu:addItem(
		{
			text = self:string('GLOBAL_HELP'),
			callback = function()
				self:helpWindow()
			end
		}
	)
	-- add an entry for returning everything to defaults
	menu:addItem(
		{
			text = self:string('CUSTOMIZE_RESTORE_DEFAULTS'),
			callback = function()
				self:restoreDefaultsMenu()
				return EVENT_CONSUME
			end
		}
	)
	-- add an entry for restoring hidden items
	menu:addItem(
		{
			text = self:string("RESTORE_HIDDEN_ITEMS"),
			callback = function()
				self:restoreHiddenItemMenu()
				return EVENT_CONSUME
			end
		}
	)
	local helpText = Textarea( 'help_text', self:string('CUSTOMIZE_HOME_HELP') )
	menu:setHeaderWidget(helpText)
	local window = Window("text_list", self:string("CUSTOMIZE_HOME"))
	window:addWidget(menu)
	window:show()
end

function helpWindow(self)
	local help_text = Textarea('help_text', self:string("CUSTOMIZE_HOME_MORE_HELP"))
	local window = Window("information", self:string("CUSTOMIZE_HOME"))
	window:addWidget(help_text)
	window:show()

end

function homeMenuItemContextMenu(self, item)

	local window = ContextMenuWindow(item.text)
	local menu   = SimpleMenu("menu")

	menu:addItem({
		text = self:string("CUSTOMIZE_CANCEL"),
		sound = "WINDOWHIDE",
		callback = function()
			window:hide()
			return EVENT_CONSUME
		end
	})

	local settings = self:getSettings()

	-- theItem is either the special custom home item for an app
	-- use theItem instead of item for the add/remove to home actions
	-- use item for the reordering actions
	local theItem = item
	local customHomeItem = nil
	local hiddenCustomHomeItem = nil
	if item.node ~= 'home' then
		local id = 'hm_' .. item.id
		customHomeItem = jiveMain:getNodeItemById(id, 'home')
		if not customHomeItem then
			customHomeItem = jiveMain:getNodeItemById(id, 'hidden')
			if customHomeItem then
				hiddenCustomHomeItem = true
			end
		end
	end
	if customHomeItem then
		theItem = customHomeItem
	end

	if item.noCustom and item.node == 'home' then
		menu:addItem({
			text = self:string('ITEM_CANNOT_BE_HIDDEN'),
			callback = function()
				window:hide()
				return EVENT_CONSUME
			end
		})
	elseif item.node == 'home' or settings[item.id] == 'home' or (customHomeItem and not hiddenCustomHomeItem) then
			menu:addItem({
				text = self:string('REMOVE_FROM_HOME'),
				callback = function()
					if theItem.node == 'home' then

						self:_timedExec(
							function()
								jiveMain:setNode(theItem, 'hidden')
								self:getSettings()[theItem.id] = 'hidden'
								self:_storeSettings('home')
							end
						)
				
					else
						self:_timedExec(
							function()
								self:getSettings()[theItem.id] = nil
								jiveMain:removeItemFromNode(theItem, 'home')
								self:_storeSettings('home')
							end
						)

					end
					window:hide()
					return EVENT_CONSUME
				end
			})
	else
		menu:addItem({
			text = self:string('ADD_TO_HOME'),
			callback = function()
				self:getSettings()[theItem.id] = 'home'
				theItem.node = 'home'
				local homeItem = jiveMain:addItemToNode(theItem, 'home')
				jiveMain:itemToBottom(homeItem, 'home')
				window:hide()
				self:_storeSettings('home')

				self:_timedExec(
					function()
						appletManager:callService("goHome")
						local menu = jiveMain:getNodeMenu('home')
						local restoredItemIdx = menu:getIdIndex(theItem.id)
						menu:setSelectedIndex(restoredItemIdx)
					end
				)
				
				return EVENT_CONSUME
			end
		})
	end

	local node = 'home'
	if #Framework.windowStack > 1 then
		node = item.node
	end

	-- this is for suppressing actions that don't make sense in context, 
	-- e.g. move to top when already at top
	local nodeMenu = jiveMain:getNodeMenu(node)
	local itemIdx  = nodeMenu:getIdIndex(item.id)
	if itemIdx > 1 then
		menu:addItem({
			text = self:string("MOVE_UP_ONE"),
			callback = function()
				window:hide()
				self:_timedExec(
					function()
						jiveMain:itemUpOne(item, node)
						self:_storeSettings(node)
					end
				)
				return EVENT_CONSUME
			end
		})
	end

	if itemIdx < #nodeMenu.items then
		menu:addItem({
			text = self:string("MOVE_DOWN_ONE"),
			callback = function()
				window:hide()
				self:_timedExec(
					function()
						jiveMain:itemDownOne(item, node)
						self:_storeSettings(node)
					end
				)
				return EVENT_CONSUME
			end
		})
	end


	if itemIdx > 1 then
		menu:addItem({
			text = self:string("MOVE_TO_TOP"),
			callback = function()
				window:hide()
				self:_timedExec(
					function()
						jiveMain:itemToTop(item, node)
						self:_storeSettings(node)
					end
				)
				return EVENT_CONSUME
			end
		})
	end

	if itemIdx < #nodeMenu.items then
		menu:addItem({
			text = self:string("MOVE_TO_BOTTOM"),
			callback = function()
				window:hide()
				self:_timedExec(
					function()
						jiveMain:itemToBottom(item, node)
						self:_storeSettings(node)
					end
				)
				return EVENT_CONSUME
			end
		})
	end

	window:addWidget(menu)
	window:show(Window.transitionFadeIn)
	return
end


-- many of the UI functions of repositioning items work better 
-- if there's a small delay before execution so the user sees them happening
function _timedExec(self, func, delay)

	if not delay then
		delay = 350
	end
	local timer = Timer(delay, func, true)
	timer:start()

end

function _storeSettings(self, node)
	if not node then
		return
	end
	local menu = jiveMain:getNodeMenu(node)
	if not menu then
		log:error('no menu found for ', node)
	end
	local menuItems = {}
	for i, v in ipairs (menu.items) do
		table.insert(menuItems, v.id)
        end

	local settings = self:getSettings()
	settings._nodes[node] = menuItems
	self:storeSettings()
end


function restoreDefaultsMenu(self, id)
	local window = Window("help_list", self:string("CUSTOMIZE_RESTORE_DEFAULTS"), 'settingstitle')
        local menu = SimpleMenu("menu", {
		{
			text = self:string("CUSTOMIZE_CANCEL"),
			sound = "WINDOWHIDE",
			callback = function()
				window:hide()
				return EVENT_CONSUME
			end
		},
		{
			text = self:string("CUSTOMIZE_CONTINUE"),
			sound = "WINDOWSHOW",
			callback = function()
				local currentSettings = self:getSettings()
				for id, customNode in pairs(currentSettings) do
					if id == '_nodes' then
						for node, itemList in pairs(customNode) do
							local menu = jiveMain:getNodeMenu(node)
							log:info('resorting ', node, ' by weight/alpha')
							menu:setComparator(SimpleMenu.itemComparatorWeightAlpha)
						end
						self:getSettings()._nodes = {}
					else
						self:getSettings()[id] = nil
						-- fetch item by id
						local item = jiveMain:getMenuItem(id)
						-- replace to original node, remove customNode
						if item then
							jiveMain:setNode(item, item.node)
						end
					end
				end
				self:storeSettings()
				appletManager:callService("goHome")
				return EVENT_CONSUME
			end
		},
	})

	menu:setHeaderWidget(Textarea("help_text", self:string("CUSTOMIZE_RESTORE_DEFAULTS_HELP")))
        window:addWidget(menu)
	window:show()
end

