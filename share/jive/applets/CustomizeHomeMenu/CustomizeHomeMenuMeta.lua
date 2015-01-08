local pairs, ipairs = pairs, ipairs
local oo            = require("loop.simple")
local AppletMeta    = require("jive.AppletMeta")
local debug         = require("jive.utils.debug")
local SimpleMenu     = require("jive.ui.SimpleMenu")

local appletManager = appletManager
local jnt           = jnt
local jiveMain      = jiveMain


module(...)
oo.class(_M, AppletMeta)


function jiveVersion(self)
	return 1, 1
end

function defaultSettings(self)
        return {
		nodes = {},
        }
end

function configureApplet(self)
	jnt:subscribe(self)
	self:registerService("homeMenuItemContextMenu")

end


function registerApplet(self)
	-- register custom nodes for ids stored in settings.lua in a HomeMenu table customNodes
	local currentSettings = self:getSettings()
	for id, node in pairs(currentSettings) do
		jiveMain:setCustomNode(id, node)
	end

	jiveMain:addItem(self:menuItem('appletCustomizeHome', 'settings', "CUSTOMIZE_HOME", function(applet, ...) applet:menu(...) end, 55, nil, "hm_appletCustomizeHome"))

end

function notify_playerLoaded(self, player)
	log:debug('notify_playerLoaded(): ', player)

	-- now that the menu is loaded, retrieve the home menu items from jive.ui.HomeMenu
	local homeMenuItems    = jiveMain:getNodeTable()
	for node, data in pairs (homeMenuItems) do
		jiveMain:rankMenuItems(node)
		local menu = jiveMain:getNodeMenu(node)
		menu:setComparator(SimpleMenu.itemComparatorRank)
	end
	-- FIXME: pull in stored settings and resort as needed here?
	local settings = self:getSettings()
	if settings and settings._nodes then
		for node, table in pairs(settings._nodes) do
			for i, v in ipairs(table) do
				local item = jiveMain:getNodeItemById(v, node)
				if item then
					jiveMain:setRank(item, i)
				end
			end
			local menu = jiveMain:getNodeMenu(node)
			menu:setComparator(SimpleMenu.itemComparatorRank)
			jiveMain:rankMenuItems(node)
		end
	else
		-- create the _nodes table if it isn't there
		self:getSettings()._nodes = {}
		self:storeSettings()
	end

end
