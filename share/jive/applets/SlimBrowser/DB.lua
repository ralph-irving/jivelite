
--[[
=head1 NAME

applets.SlimBrowser.DB - Item database.

=head1 DESCRIPTION

This object is designed to store and manage the browsing data Jive receives.

Conceptually, this data is a long list of items n1, n2, n3..., which is received by chunks. Each chunk 
is a table with many properties but of particular interest are:
- count: indicates the number of items in the long list
- offset: indicates the first index of the data in the item_obj array
- item_obj: array of consecutive elements, from offset to offset+#item_obj
- playlist_timestamp: timestamp of the data (optional)

If count is 0, then the other fields are optional (and may not even be looked at).

Fresh data always refreshes old data, except if it would be cost prohibitive to do so.

There should be one DB per long list "type". If the count or the timestamp of the long list
is different from the existing stored info, the existing info is discarded.

=head1 SYNOPSIS

TODO

=head1 FUNCTIONS

=cut
--]]

-- stuff we use
local _assert, tonumber, tostring, type, ipairs, pairs, table = _assert, tonumber, tostring, type, ipairs, pairs, table

local oo = require("loop.base")
local RadioGroup = require("jive.ui.RadioGroup")

local math = require("math")
local debug = require("jive.utils.debug")
local log = require("jive.utils.log").logger("applet.SlimBrowser.data")

-- our class
module(..., oo.class)


local BLOCK_SIZE = 200

-- init
-- creates an empty database object
function __init(self, windowSpec)
	log:debug("DB:__init()")

	return oo.rawnew(self, {
		
		-- data
		store = {},
		textIndex = {},
		last_chunk = false,  -- last_chunk received, to access other non DB fields

		-- major items extracted from data
		count = 0,           -- =last_chunk.count, the total number of items in the long list
		ts = false,          -- =last_chunk.timestamp, the timestamp of the current long list (if available)
		currentIndex = 0,    -- =last_chunk.playlist_cur_index, index of the current song (if available)

		-- cache
		last_indexed_chunk = false,
		complete = false,
		
		-- windowSpec (to create labels in renderer)
		windowSpec = windowSpec,
	})
end


function menuStyle(self)
	return self.windowSpec.menuStyle
end

function windowStyle(self)
	return self.windowSpec.windowStyle
end

function labelItemStyle(self)
	return self.windowSpec.labelItemStyle
end

function getBlockSize(self)
	return BLOCK_SIZE
end

-- getRadioGroup
-- either returns self.radioGroup or creates and returns it
function getRadioGroup(self)
	if not self.radioGroup then
		self.radioGroup = RadioGroup()
	end
	return self.radioGroup
end


-- status
-- Update the DB status from the chunk.
function updateStatus(self, chunk)
	-- sanity check on the chunk
	_assert(chunk["count"], "chunk must have count field")

	-- keep the chunk as header, in all cases
	self.last_chunk = chunk
	
	-- update currentIndex if we have it
	local currentIndex = chunk["playlist_cur_index"]
	if currentIndex then
		self.currentIndex = currentIndex + 1
	end
	
	-- detect change that invalidates data
	local ts = chunk["playlist_timestamp"] or false
	
	-- get the count
	local cCount = tonumber( chunk["count"] )

	local reset = false
	if cCount ~= self.count then
		-- count has changed, drop the data
		log:debug("..store invalid, different count")
		reset = true
		
	elseif ts and self.ts ~= ts then
		-- ts has changed, drop the data
		log:debug("..store invalid, different timestamp")
		reset = true
	end

	if reset then
		self.store = {}
		self.complete = false
		self.upCompleted = false
		self.downCompleted = false
		self.textIndex = {}
	end

	-- update the window properties
	if chunk and chunk.window then
		local window = chunk.window

		if window.menuStyle then
			self.windowSpec.menuStyle = window.menuStyle .. "menu"
			self.windowSpec.labelItemStyle = window.menuStyle .. "item"
		end
		if window.windowStyle then
			self.windowSpec.windowStyle = window.windowStyle
		end
	end


	self.ts = ts
	self.count = cCount

	return reset
end


-- menuItems
-- Stores the chunk in the DB and returns data suitable for the menu:setItems call
function menuItems(self, chunk)
	log:debug(self, " menuItems()")

	-- we may be called with no chunk, f.e. when building the window
	if not chunk then
		return self.count
	end

	-- update the status
	updateStatus(self, chunk)

	-- fix offset, CLI is 0 based and we're 1-based
	local cFrom = 0
	local cTo = 0
	if self.count > 0 then
	
		_assert(chunk["item_loop"], "chunk must have item_loop field if count>0")
		_assert(chunk["offset"], "chunk must have offset field if count>0")
		
		cFrom = chunk["offset"] + 1
		cTo = cFrom + #chunk["item_loop"] - 1
	end

	-- store chunk
	local key = math.floor(cFrom/BLOCK_SIZE)

	-- helpful debug flags to show what chunk key and range is being loaded
	log:debug('********************************* loading key number ', key)
	log:debug('********************************* cFrom: ', cFrom)
	log:debug('********************************* cTo:   ', cTo)

	self.store[key] = chunk["item_loop"]

	for i,item in ipairs(chunk["item_loop"]) do
		local index = i + tonumber(chunk["offset"])
		local textKey = item.textkey or (item.params and item.params.textkey)
		if textKey then
			local textKeyIndex = self.textIndex[textKey]
			if not textKeyIndex or textKeyIndex > index then
				--hold lowest index for the given textKey
				self.textIndex[textKey] = index
			end
			
		end
	end
	return self.count, cFrom, cTo
end

function getTextIndexes(self)
	local tmp = {}
	for key, index in pairs(self.textIndex) do
		table.insert(tmp, {key = key, index = index})
	end
	
	table.sort(tmp, 
			function(a,b)
				return a.index < b.index
			end
	)
	return tmp
end

function chunk(self)
	return self.last_chunk
end


function playlistIndex(self)
	if self.ts then
		return self.currentIndex
	else
		return nil
	end
end


function item(self, index)
	local current = (index == self.currentIndex)

	index = index - 1

	local key = math.modf(index / BLOCK_SIZE)
	local offset = math.fmod(index, BLOCK_SIZE) + 1

	if not self.store[key] then
		return
	end

	return self.store[key][offset], current
end


function size(self)
	return self.count
end


-- the missing method's job is to identify the next chunk to load
function missing(self, index)

	-- use our cached result
	if self.complete then
		log:debug(self, " complete (cached)")
		return
	end

	-- if index isn't defined we load first chunk, last chunk, then all middle chunks from the top down
	-- otherwise we load the chunk that contains index, then chunks on either side of it back-and-forth until top and bottom chunks are filled
	if not self.last_chunk or not self.last_chunk.count then
		return 0, BLOCK_SIZE
	end

	local count = tonumber(self.last_chunk.count)

	-- determine the key for the last chunk in the chunk list
	local lastKey = 0
	if count > BLOCK_SIZE then
		lastKey = math.modf(count / BLOCK_SIZE)
		if lastKey * BLOCK_SIZE == count then
			lastKey = lastKey - 1
		end
	end
	
	local firstChunkFrom = 0
	local firstChunkKey  = 0

	if not index then
		-- load first chunk if we don't have it
		if not self.store[0] then
			return 0, BLOCK_SIZE
		end
		-- load the last chunk if we don't have it
		if not self.store[lastKey] then
			return lastKey * BLOCK_SIZE, BLOCK_SIZE
		end
		-- up is done, so start searching downward
		self.searchDirection = 'down'
		self.upCompleted  = true
	end

	-- search for chunks to load
	-- get key for first chunk if we don't have it
	if index then
		firstChunkFrom = index - ( index % BLOCK_SIZE )
		firstChunkKey  = math.floor(firstChunkFrom/BLOCK_SIZE)
	end

	-- don't search down if the first chunk loaded is also the last chunk
	if firstChunkFrom + BLOCK_SIZE >= count then
		self.downCompleted = true
		self.searchDirection = 'up'
	end

	-- if both down and up are done, then we are done
	if self.downCompleted and self.upCompleted then
		-- if we reach here we're complete (for next time)
		log:debug(self, " scan complete (calculated)")
		self.complete = true
		return
	end

	-- go up and down around firstChunkKey until we have self.store[0] and self.store[lastKey]
	if not self.searchDirection then
		self.searchDirection = 'up'
	end
	if self.searchDirection == 'up' and not self.upCompleted then
		-- start with previous key to first chunk, go to beginning
		local fromKey, toKey, step = firstChunkKey-1, 0, -1

		if not self.downCompleted then
			self.searchDirection = 'down'
		end
		-- search for chunks to load
		for key = fromKey, toKey, step do
			if not self.store[key] then
				local thisChunkFrom = key * BLOCK_SIZE
				if key == toKey then
					self.upCompleted = true
				end
				return thisChunkFrom, BLOCK_SIZE
			end
		end
		self.upCompleted = true
	end

	if self.searchDirection == 'down' and not self.downCompleted then
		if not self.upCompleted then
			self.searchDirection = 'up'
		end
		-- start with next key from first chunk, go to end
		local fromKey, toKey, step = firstChunkKey+1, lastKey, 1
		for key = fromKey, toKey, step do
			if not self.store[key] then
				local thisChunkFrom = key * BLOCK_SIZE
				if key == toKey then
					self.downCompleted = true
				end
				return thisChunkFrom, BLOCK_SIZE
			end
		end
		self.downCompleted = true
	end

end

function __tostring(self)
	return "DB {" .. tostring(self.windowSpec.text) .. "}"
end

--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

