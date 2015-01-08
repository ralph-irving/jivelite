
--[[
=head1 NAME

applets.SlimDiscovery.SlimDiscoveryMeta - SlimDiscovery meta-info

=head1 DESCRIPTION

See L<applets.SlimDiscovery.SlimDiscoveryApplet>.

=head1 FUNCTIONS

See L<jive.AppletMeta> for a description of standard applet meta functions.

=cut
--]]

local oo            = require("loop.simple")

local AppletMeta    = require("jive.AppletMeta")

local Player        = require("jive.slim.Player")
local SlimServer    = require("jive.slim.SlimServer")

local debug         = require("jive.utils.debug")

local appletManager = appletManager
local jnt = jnt


module(...)
oo.class(_M, AppletMeta)


function jiveVersion(meta)
	return 1, 1
end


function defaultSettings(meta)
	return {
		currentPlayer = false
	}
end


function registerApplet(meta)
	meta:registerService("getCurrentPlayer")
	meta:registerService("setCurrentPlayer")

	meta:registerService("discoverPlayers")
	meta:registerService("discoverServers")

	meta:registerService("connectPlayer")
	meta:registerService("disconnectPlayer")

	meta:registerService("iteratePlayers")
	meta:registerService("iterateSqueezeCenters")
	meta:registerService("countPlayers")

	meta:registerService("getPollList")
	meta:registerService("setPollList")
	meta:registerService("getInitialSlimServer")
end


function configureApplet(meta)
	local settings = meta:getSettings()
	local player, server

	local slimDiscovery = appletManager:loadApplet("SlimDiscovery")

	-- Current server
	if settings.squeezeNetwork then
		server = SlimServer(jnt, "mysqueezebox.com", "mysqueezebox.com")
		server:updateInit({ip=jnt:getSNHostname()}, 9000)
		SlimServer:addLocallyRequestedServer(server)

	elseif settings.serverName then
--	elseif settings.serverName then
		if not settings.serverUuid then
			settings.serverUuid = settings.serverName
		end
		server = SlimServer(jnt, settings.serverUuid, settings.serverName)
		server:updateInit(settings.serverInit)
		SlimServer:addLocallyRequestedServer(server)
	end

	-- Current player
	if settings.playerId then
		player = Player(jnt, settings.playerId)

		if settings.squeezeNetwork then
			player:updateInit(nil, settings.playerInit)
		else
			player:updateInit(nil, settings.playerInit)
		end

	elseif settings.currentPlayer then
		-- legacy setting
		player = Player(jnt, settings.currentPlayer)
	end

	if not player then
		for i, candidatePlayer in Player:iterate() do
		        if candidatePlayer:isLocal() then
				log:info("Setting local player as current player since no saved player found and a local player exists")
		                player = candidatePlayer
		                break
		        end
		end
	end

	if player then
		slimDiscovery:setCurrentPlayer(player)
	end


	-- With the MP firmware when SqueezeNetwork is selected a dummy player with an ff mac
	-- address is selected, and then a firmware update starts. When this mac address is seen 
	-- after the upgrade we need to push the choose player and squeezenetwork pin menus
	if settings.currentPlayer == "ff:ff:ff:ff:ff:ff" then
		log:info("SqueezeNetwork dummy player found")

		-- change to a non-existant player to prevent browser connecting
		settings.currentPlayer = "ff:ff:ff:ff:ff:fe"

		-- wait until SN is connected so we know the PIN
		jnt:subscribe(meta)
	end
end


function notify_playerNew(meta, player)
	if player:getId() ~= "ff:ff:ff:ff:ff:ff" then
		return
	end

	-- unsubscribe monitor from future events
	jnt:unsubscribe(meta)

	appletManager:callService("setupShowSelectPlayer", function() end)

	appletManager:callService("forcePin", player)

end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

