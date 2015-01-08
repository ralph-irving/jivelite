
--[[
=head1 NAME

applets.SelectSkin.SelectSkinApplet - An applet to select different SqueezePlay skins

=head1 DESCRIPTION

This applet allows the SqueezePlay skin to be selected.

=head1 FUNCTIONS

Applet related methods are described in L<jive.Applet>. 
SelectSkinApplet overrides the following methods:

=cut
--]]


-- stuff we use
local pairs, type = pairs, type

local table           = require("table")

local oo              = require("loop.simple")

local Applet          = require("jive.Applet")
local RadioButton     = require("jive.ui.RadioButton")
local RadioGroup      = require("jive.ui.RadioGroup")
local Checkbox      = require("jive.ui.Checkbox")
local System        = require("jive.System")
local debug            = require("jive.utils.debug")

local SimpleMenu      = require("jive.ui.SimpleMenu")
local Window          = require("jive.ui.Window")
local Framework       = require("jive.ui.Framework")
local Timer            = require("jive.ui.Timer")

local appletManager   = appletManager

local JiveMain        = jiveMain


module(..., Framework.constants)
oo.class(_M, Applet)

local _defaultSkinNameForType = {
		["touch"] = "WQVGAsmallSkin",
		["remote"] = "WQVGAlargeSkin",
}


--service method
function getSelectedSkinNameForType(self, skinType)
	return self:getSettings()[skinType] or _defaultSkinNameForType[skinType]
end


function selectSkinEntryPoint(self, menuItem)
	if System:hasTouch() and System:isHardware() then
		local window = Window("text_list", menuItem.text, 'settingstitle')
		local menu = SimpleMenu("menu")
		menu:addItem({
			text = self:string("SELECT_SKIN_TOUCH_SKIN"),
			sound = "WINDOWSHOW",
			callback = function(event, menuItem)
				self:selectSkin(self:string("SELECT_SKIN_TOUCH_SKIN"), "touch", self:getSelectedSkinNameForType("touch"))
			end
			
		})
		menu:addItem({
			text = self:string("SELECT_SKIN_REMOTE_SKIN"),
			sound = "WINDOWSHOW",
			callback = function(event, menuItem)
				self:selectSkin(self:string("SELECT_SKIN_REMOTE_SKIN"), "remote", self:getSelectedSkinNameForType("remote"))
			end
			
		})

		window:addWidget(menu)
	
		self:tieAndShowWindow(window)
		return window

	else
		return selectSkin(self, menuItem.text, "skin", JiveMain:getSelectedSkin())
	end
end


function selectSkinStartup(self, setupNext)
	return selectSkin(self, self:string("SELECT_SKIN"), "skin", JiveMain:getSelectedSkin(), setupNext)
end


function selectSkin(self, title, skinType, previouslySelectedSkin, setupNext)
	local window = Window("text_list", title, 'settingstitle')
	local menu = SimpleMenu("menu")
	menu:setComparator(menu.itemComparatorAlpha)

	local group = RadioGroup()

	-- add skins
	for skinId, name in JiveMain:skinIterator() do
		menu:addItem({
			text = name,
			style = 'item_choice',
			check = RadioButton(
				"radio", 
				group, 
				function()
					local activeSkinType = appletManager:callService("getActiveSkinType") or "skin"
					local currentSkin = JiveMain:getSelectedSkin()
					if activeSkinType == skinType then
						--current type is active, so immediately switch the overall selected skin
						JiveMain:setSelectedSkin(skinId)
					end

					self:getSettings()[skinType] = skinId
					self.changed = true

					-- display dialog to confirm skin setting, reverts to previous after 10 second otherwise
					local timer
					local confirmGroup = RadioGroup()
					local window = Window("text_list", self:string("CONFIRM_SKIN"))
					local menu = SimpleMenu("menu",
						{
							{
								text = self:string("REVERT_SKIN"),
								style = 'item_choice',
								check = RadioButton("radio", confirmGroup, function()
																			   log:info("revert skin choice")
																			   JiveMain:setSelectedSkin(currentSkin)
																			   self:getSettings()[skinType] = currentSkin
																			   window:hide()
																		   end, true)
							},
							{
								text = self:string("KEEP_SKIN"),
								style = 'item_choice',
								check = RadioButton("radio", confirmGroup, function(event, menuItem)
																			   log:info("keep skin choice")
																			   timer:stop()
																			   if setupNext then
																				   setupNext()
																				   setupNext = nil
																			   else
																				   window:hide()
																			   end
																		   end, false)
							},
						}
					)

					timer = Timer(10000, function()
											 log:info("no selection - reverting skin choice")
											 JiveMain:setSelectedSkin(currentSkin)
											 self:getSettings()[skinType] = currentSkin
											 window:hide()
										 end, true)
					timer:start()

					window:addWidget(menu)
					self:tieAndShowWindow(window)
				end,
				skinId == previouslySelectedSkin
			)
		})
	end

	window:addWidget(menu)

	window:addListener(EVENT_WINDOW_POP,
		function()
			if self.changed then
				self:storeSettings()
			end
			if setupNext then
				setupNext()
			end
		end
	)

	self:tieAndShowWindow(window)
	return window
end

--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

