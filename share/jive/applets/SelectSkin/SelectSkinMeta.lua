
--[[
=head1 NAME

applets.SelectSkin.SelectSkinMeta - Select SqueezePlay skin

=head1 DESCRIPTION

See L<applets.SelectSkin.SelectSkinApplet>.

=head1 FUNCTIONS

See L<jive.AppletMeta> for a description of standard applet meta functions.

=cut
--]]


local oo            = require("loop.simple")

local AppletMeta    = require("jive.AppletMeta")
local SlimServer    = require("jive.slim.SlimServer")

local appletManager = appletManager
local jiveMain      = jiveMain
local jnt           = jnt
local arg           = arg

module(...)
oo.class(_M, AppletMeta)

local THUMB_SIZE_MENU = 40

function jiveVersion(meta)
	return 1, 1
end


function defaultSettings(meta)
	return {}
end


function registerApplet(meta)
	jiveMain:addItem(meta:menuItem('appletSelectSkin', 'screenSettings', 'SELECT_SKIN', function(applet, ...) applet:selectSkinEntryPoint(...) end))
	meta:registerService("getSelectedSkinNameForType")
	meta:registerService("selectSkinStartup")

	jnt:subscribe(meta)
end


function configureApplet(meta)
	if (not meta:getSettings().skin) then
		meta:getSettings().skin = jiveMain:getDefaultSkin()
	end

	local skin

	if arg[1] and arg[1] == "--smallskin" then
		skin = "WQVGAsmallSkin"
	else
		skin = meta:getSettings().skin
	end

	jiveMain:setSelectedSkin(skin)

	local skins = 0
	for s in jiveMain:skinIterator() do
		skins = skins + 1
	end

	if skins <= 1 then
		jiveMain:removeItemById('appletSelectSkin')
	end
end


function notify_skinSelected(meta)
	local server = SlimServer:getCurrentServer()
	if server then
		_artworkspec(meta, server)
	end
end


function notify_serverConnected(meta, server)
	_artworkspec(meta, server)
end


function _artworkspec(meta, server)
	local size = jiveMain:getSkinParam('THUMB_SIZE_MENU',true) or THUMB_SIZE_MENU
	local spec = size .. 'x' .. size .. '_m'
	server:request(nil, nil, { 'artworkspec', 'add', spec, 'jiveliteskin' })
end

--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

