
--[[
=head1 NAME

jive.slim.ArtworkCache - Size bounded LRU cache for artwork

--]]

local pairs, setmetatable = pairs, setmetatable

local os          = require("os")
local oo          = require("loop.base")

local debug       = require("jive.utils.debug")
local log         = require("jive.utils.log").logger("squeezebox.server.cache")


-- ArtworkCache is a base class
module(..., oo.class)


-- Limit artwork cache to 8 Mbytes
local ARTWORK_LIMIT = 24 * 1024 * 1024


function __init(self)
	local obj = oo.rawnew(self, {})

	-- initialise state
	obj:free()

	return obj
end


function free(self)
	-- artwork cache
	self.cache = {}

	-- most and least recently used links
	self.mru = nil
	self.lru = nil

	-- total size in bytes
	self.total = 0
end


function dump(self)
	local citems = 0
	for k, v in pairs(self.cache) do
		citems = citems + 1
	end

	local items = 0
	local v = self.lru
	while v do
		items = items + 1
		--log:debug("\t", v.key, " next=", v.next and v.next.key)
		v = v.prev
	end

	log:debug("artworkThumbCache items=", items, " citems=", citems, " bytes=", self.total, " fullness=", (self.total / ARTWORK_LIMIT) * 100)
end


function set(self, key, value)
	-- clear entry
	if value == nil then
		self.cache[key] = nil
		return
	end

	-- mark as loading
	if value == true then
		self.cache[key] = {
			value = true
		}
		return
	end

	-- loaded artwork
	local bytes = #value

	self.total = self.total + bytes

	local entry = {
		key = key,
		value = value,
		bytes = bytes,
	}

	self.cache[key] = entry

	-- link into mru list
	entry.prev = nil
	entry.next = self.mru

	if self.mru then
		self.mru.prev = entry
	end
	self.mru = entry

	if not self.lru or entry.next == nil then
		self.lru = entry
	end

	-- keep cache under artwork limit
	while self.total > ARTWORK_LIMIT do
		local entry = self.lru
		log:debug("Free artwork entry=", entry.key, " total=", self.total)

		self.cache[entry.key] = nil

		if entry.prev then
			entry.prev.next = nil
		end
		self.lru = entry.prev

		self.total = self.total - #entry.value
	end

	if log:isDebug() then
		self:dump()
	end
end


function get(self, key)
	local entry = self.cache[key]

	if not entry then
		return nil
	end

	-- loading or already most recently used entry?
	if entry.value == true or self.mru == entry then
		return entry.value
	end

	-- unlink from list
	if entry.prev then
		entry.prev.next = entry.next 
	end
	if entry.next then
		entry.next.prev = entry.prev
	end

	-- link to head
	entry.prev = nil
	entry.next = self.mru

	if self.mru then
		self.mru.prev = entry
	end
	self.mru = entry

	if entry.next == nil then
		self.lru = entry
	end

	if log:isDebug() then
		self:dump()
	end

	return entry.value
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]
