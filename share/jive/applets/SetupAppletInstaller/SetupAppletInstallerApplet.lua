
--[[
=head1 NAME

applets.SetupAppletInstaller.SetupAppletInsallerApplet

=head1 DESCRIPTION

Allows applets to be downloaded from SqueezeCenter to jive

SC responds to a query for 'jiveapplets' with a list of applets including name, version and a url for a zipfile
containing the applet.  Users may select which applets to download, they will then be downloaded and extracted
into the applet directory.

Assumptions:
- applet name returned by SC is used as the foldername for the applet
- the name of the applet returned by SC should match the files contained in the zip file, i.e. <name>Applet.lua and <name>Meta.lua

=cut
--]]

local next, pairs, type, package, string, tostring, tonumber, pcall, bit = next, pairs, type, package, string, tostring, tonumber, pcall, bit

local oo               = require("loop.simple")
local debug            = require("jive.utils.debug")

local os               = require("os")
local io               = require("io")
local zip              = require("zipfilter")
local ltn12            = require("ltn12")
local lfs              = require("lfs")
local sha1             = require("sha1")

local Applet           = require("jive.Applet")
local SlimServer       = require("jive.slim.SlimServer")

local System           = require("jive.System")

local RequestHttp      = require("jive.net.RequestHttp")
local SocketHttp       = require("jive.net.SocketHttp")

local Window           = require("jive.ui.Window")
local SimpleMenu       = require("jive.ui.SimpleMenu")
local Label            = require("jive.ui.Label")
local Popup            = require("jive.ui.Popup")
local Icon             = require("jive.ui.Icon")
local Textarea         = require("jive.ui.Textarea")
local Framework        = require("jive.ui.Framework")
local Task             = require("jive.ui.Task")
local Timer            = require("jive.ui.Timer")
local Checkbox         = require("jive.ui.Checkbox")

local appletManager    = appletManager
local jiveMain         = jiveMain
local jnt              = jnt

local JIVE_VERSION     = jive.JIVE_VERSION


module(..., Framework.constants)
oo.class(_M, Applet)


function appletInstallerMenu(self, menuItem, action)

	self.title = self.title or menuItem.text
	self.window = self.window or Window("text_list", self.title)
	self.auto = action and action == 'auto'

	local v1, v2, v3 = string.match(JIVE_VERSION, "(%d+)%.(%d+)%.(%d+)")
	self.version = v1 .. "." .. v2 .. "." .. v3
	log:info("requesting applets for version: ", self.version)

	-- find the applet directory
	self.appletdir = System.getUserDir() .. "/applets"

	log:info("User Applets Path: ", self.appletdir)

	-- query all non Squeezenetwork servers (will try SN later if no useful response from these)
	self.waitingfor = 0
	self.best = {}
	self.sn = nil
	for id, server in appletManager:callService("iterateSqueezeCenters") do
		if server:isSqueezeNetwork() then
			self.sn = server
		else
			self:sendRequest(server)
			self.waitingfor = self.waitingfor + 1
		end
	end

	-- start a timer which will fire if one or more servers does not respond
	-- needs to be long enough for async fetch of repo by the server before it responds
	self.timer = Timer(10000,
					   function()
						   menuSink(self, nil)
					   end,
					   true)
	self.timer:start()

	-- create animiation to show while we get data from the servers
	self.popup = Popup("waiting_popup")
	self.popup:addWidget(Icon("icon_connecting"))
	self.popup:addWidget(Label("text", self:string("APPLET_FETCHING")))
	self:tieAndShowWindow(self.popup)
end


function sendRequest(self, server)
	log:info("sending query to ", tostring(server))
	server:userRequest(
		function(chunk, err)
			if err then
				log:debug(err)
			elseif chunk then
				self:menuSink(server, chunk.data)
			end
		end,
		nil,
		{ 
			"jiveapplets",
			"target:" .. System:getMachine(), 
			"version:" .. self.version,
		}
	)
end


function menuSink(self, server, data)

	if server ~= nil then
		-- stash response if best so far (most entries)
		data.count = tonumber(data.count)
		log:info("reponse received from ", tostring(server), " with ", data.count, " entries");
		if self.best.count == nil or self.best.count < data.count then
			self.best = { server = server, count = data.count, data = data }
		end
		self.waitingfor = self.waitingfor - 1
	else
		-- timer called sink, give up waiting for more
		log:info("timeout waiting for response")
		self.waitingfor = 0
	end
		
	if self.waitingfor ~= 0 then
		return
	end

	-- if we got no entries in all responses, try squeezenetwork if not already tried
	if (self.best.count == nil or self.best.count == 0) and self.sn then
		log:info("no entries - sending query to squeezenetwork");
		sendRequest(self, self.sn)
		self.sn = nil
		self.waitingfor = 1
		self.timer:restart()
		return
	end

	-- at this point have the best response we are going to get...
	data, server = self.best.data, self.best.server
	log:info("best received from ", tostring(server), " with ", data and data.count or 0, " entries");

	-- kill the timer 
	self.timer:stop()

	if self.menu then
		self.window:removeWidget(self.menu)
	end
	self.menu = SimpleMenu("menu")
	self.menu:setComparator(SimpleMenu.itemComparatorWeightAlpha)
	self.menu:setHeaderWidget(Textarea("help_text", self:string("APPLET_WARN")))
	self.window:addWidget(self.menu)

	self.toremove = {}
	self.todownload = {}
	self.inrepos = {}

	local installed = self:getSettings()

	if data and data.item_loop then

		for _,entry in pairs(data.item_loop) do

			if entry.relurl then
				local ip, port = server:getIpPort()
				entry.url = 'http://' .. ip .. ':' .. port .. entry.relurl
			end

			self.inrepos[entry.name] = 1
			
			local status
			if installed[entry.name] then
				if not appletManager:hasApplet(entry.name) then
					self.reinstall = self.reinstall or {}
					self.reinstall[entry.name] = { url = entry.url, ver = entry.version, sha = entry.sha }
					status = "REINSTALL"
				else
					status = entry.version == installed[entry.name] and "INSTALLED" or "UPDATES"
					if status == "UPDATES" then
						self.updateall = self.updateall or {}
						self.updateall[entry.name] = { url = entry.url, ver = entry.version, sha = entry.sha }
					end
				end
			end

			self.menu:addItem({
				text = entry.title .. (status and (" (" .. tostring(self:string(status)) .. ")") or ""),
				sound = "WINDOWSHOW",
				callback = function(event, menuItem)
					self.appletwindow = self:_repoEntry(menuItem, entry, status or "INSTALL")
				end,
				weight = 2
			})				  
		end

	end

	-- if called from meta at restart then reinstall or quit
	if self.auto then
		if self.reinstall then
			self.toremove = self.reinstall 
			self.todownload = self.reinstall
			self:action()
		end
		self.popup:hide()
		return
	end

	self:tieAndShowWindow(self.window)
	self.popup:hide()

	if self.reinstall then
		self.menu:addItem({
			text = self:string("REINSTALL_ALL"),
			sound = "WINDOWSHOW",
			callback = function(event, menuItem)
				self.toremove = self.reinstall 
				self.todownload = self.reinstall
				self:action()
			end,
			weight = 1
		})
	end

	if self.updateall then
		local count = 0
		for _, _ in pairs(self.updateall) do count = count + 1 end
		self.menu:addItem({
			text = tostring(self:string("UPDATE_ALL")) .. " (" .. count .. ")",
			sound = "WINDOWSHOW",
			callback = function(event, menuItem)
				self.toremove = self.updateall 
				self.todownload = self.updateall
				self:action()
			end,
			weight = 1
		})
	end

	for name, ver in pairs(installed) do
		if appletManager:hasApplet(name) and not self.inrepos[name] then
			self.menu:addItem({
				text = name,
				sound = "WINDOWSHOW",
				callback = function(event, menuItem)
					self.appletwindow = self:_nonRepoEntry(menuItem, name, ver)
				end,
				weight = 2
			})
		end
	end

	if self.menu:numItems() == 0 then
		self.menu:addItem( {
			text = self:string("NONE_FOUND"), 
			iconStyle = 'item_no_arrow',
			weight = 2
		})
	end

	-- FIXME - make this happen all the time rather than an option?
	self.menu:addItem({
		text = self:string("APPLET_AUTOUP"),
		style = 'item_choice',
		check = Checkbox("checkbox",
			function(object, isSelected)
				self:getSettings()["_AUTOUP"] = isSelected
				self:storeSettings()
			end,
			self:getSettings()["_AUTOUP"]
		),
		weight = 4
	})
	  
end


function _repoEntry(self, menuItem, entry, status)
	local window = Window("text_list", menuItem.text)
	local menu = SimpleMenu("menu")
	window:addWidget(menu)

	local items = {}

	local desc = entry.desc or entry.title

	if entry.creator or entry.email then
		if entry.creator and entry.email then
			desc = desc .. "\n" .. entry.creator .. " (" .. entry.email .. ")"
		else
			desc = desc .. "\n" .. (entry.creator or entry.email)
		end
	end

	menu:setHeaderWidget(Textarea("help_text", desc))

	-- status may be INSTALL, INSTALLED, REINSTALL, UPDATES
	if status == "UPDATES" then
		items[#items+1] = {
			text  = tostring(self:string("UPDATE")) .. " : " .. entry.version,
			sound = "WINDOWSHOW",
			callback = function(event, menuItem)
						   self.toremove[entry.name] = 1
						   self.todownload[entry.name] = { url = entry.url, ver = entry.version, sha = entry.sha }
						   self:action()
					   end,
			
		}
	end
	if status == "INSTALLED" or status == "UPDATES" then
		local current = self:getSettings()[entry.name]
		items[#items+1] = {
			text  = tostring(self:string("REMOVE")) .. " : " .. current,
			sound = "WINDOWSHOW",
			callback = function(event, menuItem)
						   self.toremove[entry.name] = 1
						   self:action()
					   end,
		}
	end
	if status == "INSTALL" or status == "REINSTALL" then
		items[#items+1] = {
			text  = tostring(self:string(status)) .. " : " .. entry.version,
			sound = "WINDOWSHOW",
			callback = function(event, menuItem)
						   self.toremove[entry.name] = 1
						   self.todownload[entry.name] = { url = entry.url, ver = entry.version, sha = entry.sha }
						   self:action()
					   end,
		}
	end

	menu:setItems(items)
	self:tieAndShowWindow(window)
	return window
end


function _nonRepoEntry(self, menuItem, name, ver)
	local window = Window("text_list", menuItem.text)
	local menu = SimpleMenu("menu")
	window:addWidget(menu)

	menu:addItem({
		text = tostring(self:string("REMOVE")) .. " : " .. ver, 
		sound = "WINDOWSHOW",
		callback = function(event, menuItem)
					   self.toremove[name] = 1
					   self:action()
				   end,
	})

	self:tieAndShowWindow(window)
	return window
end


-- action changes
function action(self)
	-- generate animated downloading screen
	local icon = Icon("icon_connecting")
	self.animatelabel = Label("text", self:string("DOWNLOADING"))
	self.animatewindow = Popup("waiting_popup")
	self.animatewindow:addWidget(icon)
	self.animatewindow:addWidget(self.animatelabel)
	self.animatewindow:show()

	self.task = Task("applet download", self, function()
												  self:_remove()
												  self:_download()
												  self:_finished(label)
											  end)

	self.task:addTask()
end


-- remove applets
function _remove(self)
	for applet, _ in pairs(self.toremove) do
		local dir = self.appletdir .. "/" .. applet
		_removedir(dir)
	end
end


function _removedir(dir)
	local attr = lfs.attributes(dir)
	if attr and attr.mode == "directory" then
		for file in lfs.dir(dir) do
			if file ~= "." and file ~= ".." then
				local path = dir .. "/" .. file
				if lfs.attributes(path).mode == "directory" then
					_removedir(path)
				else
					pcall(os.remove, path)
				end
			end
		end

		log:info("removing: ", dir)
		pcall(lfs.rmdir, dir)
	else
		log:info("ignoring non directory: ", dir)
	end
end


-- download each applet in turn
function _download(self)

	for applet, appletdata in pairs(self.todownload) do
		local dir = self.appletdir .. "/" .. applet .. "/"

		log:info("downloading: ", appletdata.url, " to: ", dir, " sha1: ", appletdata.sha or "")

		if lfs.attributes(dir) == nil then
			lfs.mkdir(dir)
		end

		-- fetch each zip twice if sha present: 
		-- 1) to verify sha1
		if appletdata.sha then

			self.fetched = false
			self.fetchedsha = nil
			
			local req = RequestHttp(self:_sha1Sink(), 'GET', appletdata.url, { stream = true })
			local uri = req:getURI()

			local http = SocketHttp(jnt, uri.host, uri.port, uri.host)
			http:fetch(req)
			
			while not self.fetched do
				self.task:yield()
			end
			
			if self.fetchedsha == nil or appletdata.sha ~= self.fetchedsha then
				log:warn("sha1 missmatch expected: ", appletdata.sha, " got: ", self.fetchedsha or "nil")
				break
			else
				log:info("sha1 verified")
			end
		end

		-- 2) to extract the file
		self.fetched = false

		local sink = ltn12.sink.chain(zip.filter(), self:_zipSink(dir))

		req = RequestHttp(sink, 'GET', appletdata.url, { stream = true })
		uri = req:getURI()

		http = SocketHttp(jnt, uri.host, uri.port, uri.host)
		http:fetch(req)

		while not self.fetched do
			self.task:yield()
		end
	end
end


-- called when download / removal is complete
function _finished(self, label)
	-- save new version numbers
	for applet, _ in pairs(self.toremove) do
		self:getSettings()[applet] = nil
	end
	for applet, appletdata in pairs(self.todownload) do
		self:getSettings()[applet] = appletdata.ver
	end
	self:storeSettings()

	self.animatewindow:hide()

	if self.appletwindow then
		self.appletwindow:hide()
	end
	self.window:removeWidget(self.menu)
	self.window:addWidget(Textarea("help_text", self:string("RESTART_APP")))
	self.window:addListener(bit.bor(EVENT_KEY_PRESS, EVENT_ACTION), function() self.window:hide() end)
end


-- sink for writing out files once they have been unziped by zipfilter
function _zipSink(self, dir)
	local fh = nil

	return function(chunk)

		if chunk == nil then
			if fh and fh ~= DIR then
				fh:close()
				fh = nil
				self.fetched = true
				return nil
			end

		elseif type(chunk) == "table" then

			if fh then
				fh:close()
				fh = nil
			end

			local filename = dir .. chunk.filename

			if string.sub(filename, -1) == "/" then
				log:info("creating directory: " .. filename)
				lfs.mkdir(filename)
				fh = 'DIR'
			else
				log:info("extracting file: " .. filename)
				fh = io.open(filename, "w")
			end

		else
			if fh == nil then
				return nil
			end

			if fh ~= 'DIR' then
				fh:write(chunk)
			end
		end

		return 1
	end
end


-- sink for calculating sha1 of downloaded file
function _sha1Sink(self)
	local sha1 = sha1:new()

	return function(chunk)
		if chunk == nil then
			self.fetched = true
			self.fetchedsha = sha1:digest()
			return nil
		end
		sha1:update(chunk)
	end
end

