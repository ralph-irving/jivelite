--[[
=head1 NAME

applets.HDGridSkin.HDGridSkinApplet

=cut
--]]


-- stuff we use
local ipairs, pairs, setmetatable, type, tostring = ipairs, pairs, setmetatable, type, tostring

local oo                     = require("loop.simple")

local Applet                 = require("jive.Applet")
local Audio                  = require("jive.ui.Audio")
local Font                   = require("jive.ui.Font")
local Framework              = require("jive.ui.Framework")
local Icon                   = require("jive.ui.Icon")
local Label                  = require("jive.ui.Label")
local RadioButton            = require("jive.ui.RadioButton")
local RadioGroup             = require("jive.ui.RadioGroup")
local SimpleMenu             = require("jive.ui.SimpleMenu")
local Surface                = require("jive.ui.Surface")
local Textarea               = require("jive.ui.Textarea")
local Tile                   = require("jive.ui.Tile")
local Window                 = require("jive.ui.Window")

local table                  = require("jive.utils.table")
local debug                  = require("jive.utils.debug")
local autotable              = require("jive.utils.autotable")

local log                    = require("jive.utils.log").logger("applet.HDGridSkin")

local EVENT_ACTION           = jive.ui.EVENT_ACTION
local EVENT_CONSUME          = jive.ui.EVENT_CONSUME
local EVENT_WINDOW_POP       = jive.ui.EVENT_WINDOW_POP
local LAYER_FRAME            = jive.ui.LAYER_FRAME
local LAYER_CONTENT_ON_STAGE = jive.ui.LAYER_CONTENT_ON_STAGE
local LAYER_TITLE            = jive.ui.LAYER_TITLE

local LAYOUT_NORTH           = jive.ui.LAYOUT_NORTH
local LAYOUT_EAST            = jive.ui.LAYOUT_EAST
local LAYOUT_SOUTH           = jive.ui.LAYOUT_SOUTH
local LAYOUT_WEST            = jive.ui.LAYOUT_WEST
local LAYOUT_CENTER          = jive.ui.LAYOUT_CENTER
local LAYOUT_NONE            = jive.ui.LAYOUT_NONE

local WH_FILL                = jive.ui.WH_FILL

local jiveMain               = jiveMain
local appletManager          = appletManager
local math                   = math

module(..., Framework.constants)
oo.class(_M, Applet)


-- Define useful variables for this skin
local imgpath = "applets/HDGridSkin/images/"
local fontpath = "fonts/"
local FONT_NAME = "FreeSans"
local BOLD_PREFIX = "Bold"


function init(self)
	self.images = {}

	self.imageTiles = {}
	self.hTiles = {}
	self.vTiles = {}
	self.tiles = {}
end

local coverSize = 900 -- default value, change by calling skin

function param(self)
	return {
		THUMB_SIZE = 250,
		THUMB_SIZE_MENU = 250,
		THUMB_SIZE_LINEAR = 72,
		THUMB_SIZE_PLAYLIST = 72,
		NOWPLAYING_MENU = true,
		-- NOWPLAYING_TRACKINFO_LINES used in assisting scroll behavior animation on NP
		-- 3 is for a three line track, artist, and album (e.g., SBtouch)
		-- 2 is for a two line track, artist+album (e.g., SBradio, SBcontroller)
		NOWPLAYING_TRACKINFO_LINES = 3,
		POPUP_THUMB_SIZE = 100,
		nowPlayingScreenStyles = { 
			-- every skin needs to start off with a nowplaying style
			{
				style = 'nowplaying', 
				artworkSize = coverSize .. "x" .. coverSize,
				text = self:string("ART_AND_TEXT"),
			},
			{
				style = 'nowplaying_spectrum_text',
				artworkSize = coverSize .. "x" .. coverSize,
				localPlayerOnly = 1,
				text = self:string("SPECTRUM_ANALYZER"),
			},
		},
		disableTimeInput = true,
	}
end

local function _loadImage(self, file)
	return Surface:loadImage(imgpath .. file)
end


local function _buildTileKey(tileTable)
	local key = ""
	for i = 1, #tileTable do
		local element = tileTable[i] or "NIL"
		key = key .. element .. "&"
	end

	return key
end

local function _loadTile(self, tileTable)
	if not tileTable then
		return nil
	end

	local key = _buildTileKey(tileTable)


	if not self.tiles[key] then
		self.tiles[key] = Tile:loadTiles(tileTable)
	end

	return self.tiles[key]
end


local function _loadHTile(self, tileTable)
	if not tileTable then
		return nil
	end

	local key = _buildTileKey(tileTable)

	if not self.hTiles[key] then
		self.hTiles[key] = Tile:loadHTiles(tileTable)
	end

	return self.hTiles[key]
end


local function _loadVTile(self, tileTable)
	if not tileTable then
		return nil
	end

	local key = _buildTileKey(tileTable)

	if not self.vTiles[key] then
		self.vTiles[key] = Tile:loadVTiles(tileTable)
	end

	return self.vTiles[key]
end


local function _loadImageTile(self, file)
	if not file then
		return nil
	end

	return Tile:loadImage(file)
end


-- define a local function to make it easier to create icons.
local function _icon(x, y, img)
	local var = {}
	var.x = x
	var.y = y
	var.img = _loadImage(self, img)
	var.layer = LAYER_FRAME
	var.position = LAYOUT_SOUTH

	return var
end

-- define a local function that makes it easier to set fonts
local function _font(fontSize)
	return Font:load(fontpath .. FONT_NAME .. ".ttf", fontSize)
end

-- define a local function that makes it easier to set bold fonts
local function _boldfont(fontSize)
	return Font:load(fontpath .. FONT_NAME .. BOLD_PREFIX .. ".ttf", fontSize)
end

-- defines a new style that inherrits from an existing style
local function _uses(parent, value)
	if parent == nil then
		log:warn("nil parent in _uses at:\n", debug.traceback())
	end
	local style = {}
	setmetatable(style, { __index = parent })
	for k,v in pairs(value or {}) do
		if type(v) == "table" and type(parent[k]) == "table" then
			-- recursively inherrit from parent style
			style[k] = _uses(parent[k], v)
		else
			style[k] = v
		end
	end

	return style
end


-- skin
-- The meta arranges for this to be called to skin the interface.
function skin_1080p(self, s)
	Framework:setVideoMode(1920, 1080, 0, false)
	self:skin(s)
end


function skin(self, s)
	local screenWidth, screenHeight = Framework:getScreenSize()

	--init lastInputType so selected item style is not shown on skin load
	Framework.mostRecentInputType = "mouse"

	-- skin
	local thisSkin = 'remote'
	local skinSuffix = "_" .. thisSkin .. ".png"

	-- Images and Tiles
	local inputTitleBox           = _loadImageTile(self,  imgpath .. "Titlebar/titlebar.png" )
	local backButton              = _loadImageTile(self,  imgpath .. "Icons/icon_back_button_tb.png")
	local cancelButton            = _loadImageTile(self,  imgpath .. "Icons/icon_close_button_tb.png")
	local homeButton              = _loadImageTile(self,  imgpath .. "Icons/icon_home_button_tb.png")
	local helpButton              = _loadImageTile(self,  imgpath .. "Icons/icon_help_button_tb.png")
	local powerButton             = _loadImageTile(self,  imgpath .. "Icons/icon_power_button_tb.png")
	local nowPlayingButton        = _loadImageTile(self,  imgpath .. "Icons/icon_nplay_button_tb.png")
	local playlistButton          = _loadImageTile(self,  imgpath .. "Icons/icon_nplay_list_tb.png")
	local moreButton              = _loadImageTile(self,  imgpath .. "Icons/icon_more_tb.png")
	local touchToolbarBackground  = _loadImageTile(self,  imgpath .. "Touch_Toolbar/toolbar_tch_bkgrd.png")
	local sliderBackground        = _loadImageTile(self,  imgpath .. "Touch_Toolbar/toolbar_lrg.png")
	local touchToolbarKeyDivider  = _loadImageTile(self,  imgpath .. "Touch_Toolbar/toolbar_divider.png")
	local deleteKeyBackground     = _loadImageTile(self,  imgpath .. "Buttons/button_delete_text_entry.png")
	local deleteKeyPressedBackground = _loadImageTile(self,  imgpath .. "Buttons/button_delete_text_entry_press.png")
	local helpTextBackground      = _loadImageTile(self,  imgpath .. "Titlebar/tbar_dropdwn_bkrgd.png")


	local nocturneWallpaper = _loadImageTile(self, "applets/SetupWallpaper/wallpaper/fab4_nocturne.png")

	--FIXME, _r asset here doesn't work...it's supposed to have a fadeout effect and it doesn't appear on screen
	local fiveItemBox             = _loadHTile(self, {
		 imgpath .. "5_line_lists/tch_5line_divider_l.png",
		 imgpath .. "5_line_lists/tch_5line_divider.png",
		 imgpath .. "5_line_lists/tch_5line_divider_r.png",
	})
	local fiveItemSelectionBox    = _loadHTile(self, {
		 nil,
		 imgpath .. "5_line_lists/menu_sel_box_5line.png",
		 imgpath .. "5_line_lists/menu_sel_box_5line_r.png",
	})
	local fiveItemPressedBox      = _loadHTile(self, {
		 nil,
		 imgpath .. "5_line_lists/menu_sel_box_5line_press.png",
		 imgpath .. "5_line_lists/menu_sel_box_5line_press_r.png",
	})

	local gridItemSelectionBox    = _loadTile(self, {
		imgpath .. "grid_list/button_titlebar.png",
		imgpath .. "grid_list/button_titlebar_tl.png",
		imgpath .. "grid_list/button_titlebar_t.png",
		imgpath .. "grid_list/button_titlebar_tr.png",
		imgpath .. "grid_list/button_titlebar_r.png",
		imgpath .. "grid_list/button_titlebar_br.png",
		imgpath .. "grid_list/button_titlebar_b.png",
		imgpath .. "grid_list/button_titlebar_bl.png",
		imgpath .. "grid_list/button_titlebar_l.png",
	})

	local threeItemSelectionBox            = _loadHTile(self, {
		 imgpath .. "3_line_lists/menu_sel_box_3line_l.png",
		 imgpath .. "3_line_lists/menu_sel_box_3line.png",
		 imgpath .. "3_line_lists/menu_sel_box_3line_r.png",
	})
	local threeItemPressedBox = _loadImageTile(self, imgpath .. "3_line_lists/menu_sel_box_3item_press.png")
	
	local contextMenuPressedBox    = _loadTile(self, {
		imgpath .. "Popup_Menu/button_cm_press.png",
		imgpath .. "Popup_Menu/button_cm_tl_press.png",
		imgpath .. "Popup_Menu/button_cm_t_press.png",
		imgpath .. "Popup_Menu/button_cm_tr_press.png",
		imgpath .. "Popup_Menu/button_cm_r_press.png",
		imgpath .. "Popup_Menu/button_cm_br_press.png",
		imgpath .. "Popup_Menu/button_cm_b_press.png",
		imgpath .. "Popup_Menu/button_cm_bl_press.png",
		imgpath .. "Popup_Menu/button_cm_l_press.png",
	})
	
	local keyTopLeft = _loadTile(self, {
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_bkgrd.png",
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_bkgrd_tl.png",
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_bkgrd_t.png",
		nil,
		nil,
		nil,
		nil,
		nil,
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_bkgrd_l.png",
	})

	local keyTopLeftPressed = _loadTile(self, {
		imgpath .. "Buttons/keybrd_n_button_press.png",
		imgpath .. "Buttons/keybrd_nw_button_press_tl.png",
		imgpath .. "Buttons/keybrd_n_button_press_t.png",
		nil,
		nil,
		nil,
		nil,
		nil,
		imgpath .. "Buttons/keybrd_nw_button_press_l.png",
	})

	local keyTop = _loadTile(self, {
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_bkgrd.png",
		nil,
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_bkgrd_t_wvert.png",
		nil,
		nil,
		nil,
		nil,
		nil,
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_divider_vert.png",
	})

	local keyTopPressed = _loadTile(self, {
		imgpath .. "Buttons/keybrd_n_button_press.png",
		nil,
		imgpath .. "Buttons/keybrd_n_button_press_t.png",
		nil,
		nil,
		nil,
		nil,
		nil,
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_divider_vert.png",
	})

	local keyTopRight = _loadTile(self, {
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_bkgrd.png",
		nil,
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_bkgrd_t_wvert.png",
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_bkgrd_tr.png",
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_bkgrd_r.png",
		nil,
		nil,
		nil,
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_divider_vert.png",
	})

	local keyTopRightPressed = _loadTile(self, {
		imgpath .. "Buttons/keybrd_n_button_press.png",
		nil,
		imgpath .. "Buttons/keybrd_n_button_press_t.png",
		imgpath .. "Buttons/keybrd_ne_button_press_tr.png",
		imgpath .. "Buttons/keybrd_ne_button_press_r.png",
		nil,
		nil,
		nil,
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_divider_vert.png",
	})

	local keyLeft = _loadTile(self, {
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_bkgrd.png",
		imgpath .. "Text_Entry/Keyboard_Touch/keyboardLeftEdge.png",
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_divider_hort.png",
		nil,
		nil,
		nil,
		nil,
		nil,
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_bkgrd_l.png",
	})

	local keyLeftPressed = _loadTile(self, {
		imgpath .. "Buttons/keyboard_button_press.png",
		nil,
		nil,
		nil,
		nil,
		nil,
		nil,
		nil,
		imgpath .. "Buttons/keyboard_button_press.png",
	})

	local keyMiddle = _loadTile(self, {
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_bkgrd.png",
		nil,
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_divider_hort.png",
		nil,
		nil,
		nil,
		nil,
		nil,
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_divider_vert.png",
	})

	local keyMiddlePressed = _loadTile(self, {
		imgpath .. "Buttons/keyboard_button_press.png",
		nil,
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_divider_hort.png",
		nil,
		nil,
		nil,
		nil,
		nil,
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_divider_vert.png",
	})

	local sliderButtonPressed = _loadTile(self, {
		imgpath .. "Buttons/keyboard_button_press.png",
		nil,
		nil,
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_divider_hort.png",
		nil,
		nil,
		nil,
		nil,
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_divider_vert.png",
	})

	local keyRight = _loadTile(self, {
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_bkgrd.png",
		nil,
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_divider_hort.png",
		imgpath .. "Text_Entry/Keyboard_Touch/keyboardRightEdge.png",
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_bkgrd_r.png",
		nil,
		nil,
		nil,
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_divider_vert.png",
	})

	local keyRightPressed = _loadTile(self, {
		imgpath .. "Buttons/keyboard_button_press.png",
		nil,
		nil,
		nil,
		imgpath .. "Buttons/keyboard_button_press.png",
		nil,
		nil,
		nil,
		nil,
	})

	local keyBottomLeft = _loadTile(self, {
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_bkgrd.png",
		imgpath .. "Text_Entry/Keyboard_Touch/keyboardLeftEdge.png",
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_divider_hort.png",
		nil,
		nil,
		nil,
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_bkgrd_b.png",
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_bkgrd_bl.png",
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_bkgrd_l.png",
	})

	local keyBottomLeftPressed = _loadTile(self, {
		imgpath .. "Buttons/keybrd_s_button_press.png",
		imgpath .. "Text_Entry/Keyboard_Touch/keyboardLeftEdge.png",
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_divider_hort.png",
		nil,
		nil,
		nil,
		imgpath .. "Buttons/keybrd_s_button_press_b.png",
		imgpath .. "Buttons/keybrd_sw_button_press_bl.png",
		imgpath .. "Buttons/keybrd_sw_button_press_l.png",
	})

	local keyBottom = _loadTile(self, {
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_bkgrd.png",
		nil,
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_divider_hort.png",
		nil,
		nil,
		nil,
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_bkgrd_b_wvert.png",
		nil,
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_divider_vert.png",
	})

	local keyBottomPressed = _loadTile(self, {
		imgpath .. "Buttons/keybrd_s_button_press.png",
		nil,
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_divider_hort.png",
		nil,
		nil,
		nil,
		imgpath .. "Buttons/keybrd_s_button_press_b.png",
		nil,
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_divider_vert.png",
	})

	local keyBottomRight = _loadTile(self, {
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_bkgrd.png",
		nil,
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_divider_hort.png",
		imgpath .. "Text_Entry/Keyboard_Touch/keyboardRightEdge.png",
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_bkgrd_r.png",
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_bkgrd_br.png",
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_bkgrd_b_wvert.png",
		nil,
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_divider_vert.png",
	})

	local keyBottomRightPressed = _loadTile(self, {
		imgpath .. "Buttons/keybrd_s_button_press.png",
		nil,
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_divider_hort.png",
		imgpath .. "Text_Entry/Keyboard_Touch/keyboardRightEdge.png",
		imgpath .. "Buttons/keybrd_se_button_press_r.png",
		imgpath .. "Buttons/keybrd_se_button_press_br.png",
		imgpath .. "Buttons/keybrd_s_button_press_b.png",
		nil,
		imgpath .. "Text_Entry/Keyboard_Touch/keyboard_divider_vert.png",
	})

	local titleBox = _loadTile(self, {
		imgpath .. "Titlebar/titlebar.png",
		nil,
		nil,
		nil,
		nil,
		nil,
		imgpath .. "Titlebar/titlebar_shadow.png",
		nil,
		nil,
	})

	local textinputBackground = _loadTile(self, {
		imgpath .. "Text_Entry/Keyboard_Touch/titlebar_box.png",
		imgpath .. "Text_Entry/Keyboard_Touch/text_entry_titlebar_box_tl.png",
		imgpath .. "Text_Entry/Keyboard_Touch/text_entry_titlebar_box_t.png",
		imgpath .. "Text_Entry/Keyboard_Touch/text_entry_titlebar_box_tr.png",
		imgpath .. "Text_Entry/Keyboard_Touch/text_entry_titlebar_box_r.png",
		imgpath .. "Text_Entry/Keyboard_Touch/text_entry_titlebar_box_br.png",
		imgpath .. "Text_Entry/Keyboard_Touch/text_entry_titlebar_box_b.png",
		imgpath .. "Text_Entry/Keyboard_Touch/text_entry_titlebar_box_bl.png",
		imgpath .. "Text_Entry/Keyboard_Touch/text_entry_titlebar_box_l.png",
	})

	local pressedTitlebarButtonBox = _loadTile(self, {
		imgpath .. "Buttons/button_titlebar_press.png",
		imgpath .. "Buttons/button_titlebar_tl_press.png",
		imgpath .. "Buttons/button_titlebar_t_press.png",
		imgpath .. "Buttons/button_titlebar_tr_press.png",
		imgpath .. "Buttons/button_titlebar_r_press.png",
		imgpath .. "Buttons/button_titlebar_br_press.png",
		imgpath .. "Buttons/button_titlebar_b_press.png",
		imgpath .. "Buttons/button_titlebar_bl_press.png",
		imgpath .. "Buttons/button_titlebar_l_press.png",
	})

	local titlebarButtonBox =_loadTile(self, {
		imgpath .. "Buttons/button_titlebar.png",
		imgpath .. "Buttons/button_titlebar_tl.png",
		imgpath .. "Buttons/button_titlebar_t.png",
		imgpath .. "Buttons/button_titlebar_tr.png",
		imgpath .. "Buttons/button_titlebar_r.png",
		imgpath .. "Buttons/button_titlebar_br.png",
		imgpath .. "Buttons/button_titlebar_b.png",
		imgpath .. "Buttons/button_titlebar_bl.png",
		imgpath .. "Buttons/button_titlebar_l.png",
	})

	local popupBox = _loadTile(self, {
       imgpath .. "Popup_Menu/popup_box.png",
       imgpath .. "Popup_Menu/popup_box_tl.png",
       imgpath .. "Popup_Menu/popup_box_t.png",
       imgpath .. "Popup_Menu/popup_box_tr.png",
       imgpath .. "Popup_Menu/popup_box_r.png",
       imgpath .. "Popup_Menu/popup_box_br.png",
       imgpath .. "Popup_Menu/popup_box_b.png",
       imgpath .. "Popup_Menu/popup_box_bl.png",
       imgpath .. "Popup_Menu/popup_box_l.png",
	})

	local contextMenuBox = _loadTile(self, {
		imgpath .. "Popup_Menu/cm_popup_box.png",
		imgpath .. "Popup_Menu/cm_popup_box_tl.png",
		imgpath .. "Popup_Menu/cm_popup_box_t.png",
		imgpath .. "Popup_Menu/cm_popup_box_tr.png",
		imgpath .. "Popup_Menu/cm_popup_box_r.png",
		imgpath .. "Popup_Menu/cm_popup_box_br.png",
		imgpath .. "Popup_Menu/cm_popup_box_b.png",
		imgpath .. "Popup_Menu/cm_popup_box_bl.png",
		imgpath .. "Popup_Menu/cm_popup_box_l.png",
	})

	local scrollBackground = _loadVTile(self, {
		imgpath .. "Scroll_Bar/scrollbar_bkgrd_t.png",
		imgpath .. "Scroll_Bar/scrollbar_bkgrd.png",
		imgpath .. "Scroll_Bar/scrollbar_bkgrd_b.png",
	})

	local scrollBar = _loadVTile(self, {
		imgpath .. "Scroll_Bar/scrollbar_body_t.png",
		imgpath .. "Scroll_Bar/scrollbar_body.png",
		imgpath .. "Scroll_Bar/scrollbar_body_b.png",
	})

	local popupBackground = Tile:fillColor(0x000000ff)

	local textinputCursor = _loadImageTile(self, imgpath .. "Text_Entry/Keyboard_Touch/tch_cursor.png")

	local THUMB_SIZE_G = self:param().THUMB_SIZE
	local THUMB_SIZE_L = self:param().THUMB_SIZE_LINEAR
	
	local TITLE_PADDING  = { 0, 15, 0, 15 }
	local CHECK_PADDING  = { 2, 0, 6, 0 }
	local CHECKBOX_RADIO_PADDING  = { 2, 0, 0, 0 }

	local MENU_ITEM_ICON_PADDING = { 0, 0, 24, 0 }
	local MENU_PLAYLISTITEM_TEXT_PADDING = { 16, 1, 9, 1 }

	local MENU_CURRENTALBUM_TEXT_PADDING = { 6, 20, 0, 10 }
	local TEXTAREA_PADDING = { 13, 8, 8, 0 }

	local TEXT_COLOR = { 0xE7, 0xE7, 0xE7 }
	local TEXT_COLOR_BLACK = { 0x00, 0x00, 0x00 }
	local TEXT_SH_COLOR = { 0x37, 0x37, 0x37 }
	local TEXT_COLOR_TEAL = { 0, 0xbe, 0xbe }

	local SELECT_COLOR = { 0xE7, 0xE7, 0xE7 }
	local SELECT_SH_COLOR = { }

	local TITLE_HEIGHT = 65
	local TITLE_FONT_SIZE = math.floor(30 * screenHeight / 720)
	local ALBUMMENU_FONT_SIZE = 32
	local ALBUMMENU_SMALL_FONT_SIZE = 24
	local TEXTMENU_FONT_SIZE = 40
	local POPUP_TEXT_SIZE_1 = 34
	local POPUP_TEXT_SIZE_2 = 26
	local TRACK_FONT_SIZE = 18
	local TEXTAREA_FONT_SIZE = 18
	local CENTERED_TEXTAREA_FONT_SIZE = 28

	local CM_MENU_HEIGHT = 45

	local TEXTINPUT_FONT_SIZE = 40
	local TEXTINPUT_SELECTED_FONT_SIZE = 24
	
	local HELP_FONT_SIZE = 36
	local UPDATE_SUBTEXT_SIZE = 20

	local ITEM_ICON_ALIGN   = 'center'
	local ITEM_LEFT_PADDING = 24
	local THREE_ITEM_HEIGHT = 72
	local FIVE_ITEM_HEIGHT = 76
	local TITLE_BUTTON_WIDTH = 76

	-- alternatives for grid view
	local ALBUMMENU_FONT_SIZE_G = 26
	local ALBUMMENU_SMALL_FONT_SIZE_G = 24
	local MENU_ITEM_ICON_PADDING_G = { 0, 0, 0, 0 }

	local smallSpinny = {
		img = _loadImage(self, "Alerts/wifi_connecting_med.png"),
		frameRate = 8,
		frameWidth = 26,
		padding = 0,
		h = WH_FILL,
	}
	--[[
	local largeSpinny = {
		img = _loadImage(self, "Alerts/wifi_connecting.png"),
		position = LAYOUT_CENTER,
		w = WH_FILL,
		align = "center",
		frameRate = 8,
		frameWidth = 120,
		padding = { 0, 0, 0, 10 }
	}
	--]]
	-- convenience method for removing a button from the window
	local noButton = { 
		img = false, 
		bgImg = false, 
		w = 0 
	}

	local playArrow = { 
		img = _loadImage(self, "Icons/selection_play_3line_on.png"),
	}
	local addArrow  = { 
		img = _loadImage(self, "Icons/selection_add_3line_off.png"),
	}
	local favItem  = { 
		img = _loadImage(self, "Icons/icon_toolbar_fav.png"),
	}


	---- REVIEWED BELOW THIS LINE ----

--------- CONSTANTS ---------

	local _progressBackground = _loadImageTile(self, imgpath .. "Alerts/alert_progress_bar_bkgrd.png")

	local _progressBar = _loadHTile(self, {
		nil,
		imgpath .. "Alerts/alert_progress_bar_body.png",
	})

	local _songProgressBackground = _loadHTile(self, {
		imgpath .. "NowPlaying/np_progressbar_bkgrd_l.png",
		imgpath .. "NowPlaying/np_progressbar_bkgrd.png",
		imgpath .. "NowPlaying/np_progressbar_bkgrd_r.png",
	})

	local _songProgressBar = _loadHTile(self, {
		nil,
		nil,
		imgpath .. "NowPlaying/np_progressbar_slider_10ft.png"
	})

	local _songProgressBarDisabled = _loadHTile(self, {
		nil,
		nil,
		imgpath .. "NowPlaying/np_progressbar_slider_10ft.png"
	})

	local _vizProgressBar = _loadHTile(self, {
		imgpath .. "UNOFFICIAL/viz_progress_fill_l.png",
		imgpath .. "UNOFFICIAL/viz_progress_fill.png",
		imgpath .. "UNOFFICIAL/viz_progress_fill_r.png",
	})
	local _vizProgressBarPill = _loadImageTile(self, imgpath .. "UNOFFICIAL/viz_progress_slider.png")

	local _volumeSliderBackground = _loadHTile(self, {
		imgpath .. "Touch_Toolbar/tch_volumebar_bkgrd_l.png",
		imgpath .. "Touch_Toolbar/tch_volumebar_bkgrd.png",
		imgpath .. "Touch_Toolbar/tch_volumebar_bkgrd_r.png",
	})

	local _volumeSliderBar = _loadHTile(self, {
		imgpath .. "UNOFFICIAL/tch_volumebar_fill_l.png",
		imgpath .. "UNOFFICIAL/tch_volumebar_fill.png",
		imgpath .. "UNOFFICIAL/tch_volumebar_fill_r.png",
	})
	
	local _volumeSliderPill = _loadImageTile(self, imgpath .. "Touch_Toolbar/tch_volume_slider.png")

	local _popupSliderBar = _loadHTile(self, {
		imgpath .. "Touch_Toolbar/tch_volumebar_fill_l.png",
		imgpath .. "Touch_Toolbar/tch_volumebar_fill.png",
		imgpath .. "Touch_Toolbar/tch_volumebar_fill_r.png",
	})

--------- DEFAULT WIDGET STYLES ---------
	--
	-- These are the default styles for the widgets 

	s.window = {
		w = screenWidth,
		h = screenHeight,
	}

	-- window with absolute positioning
	s.absolute = _uses(s.window, {
		layout = Window.noLayout,
	})

	s.popup = _uses(s.window, {
		border = { 0, 0, 0, 0 },
		bgImg = popupBackground,
	})

	s.title = {
		h = TITLE_HEIGHT,
		border = 0,
		position = LAYOUT_NORTH,
		--bgImg = titleBox,
		padding = { 0, 5, 0, 5 },
		order = { "text" }, -- { "lbutton", "text", "rbutton" },
		lbutton = {
			border = { 8, 0, 8, 0 },
			h = WH_FILL,
		},
		rbutton = {
			border = { 8, 0, 8, 0 },
			h = WH_FILL,
		},
		text = {
			w = WH_FILL,
			padding = TITLE_PADDING,
			align = "center",
			font = _boldfont(TITLE_FONT_SIZE),
			fg = TEXT_COLOR,
		}
	}

	s.title.textButton = _uses(s.title.text, {
		--bgImg = titlebarButtonBox,
		padding = { 4, 15, 4, 15 },
	})

	s.title.pressed = {}
	s.title.pressed.textButton = _uses(s.title.textButton, {
		bgImg = pressedTitlebarButtonBox,
	})

	s.text_block_black = {
		bgImg = Tile:fillColor(0x000000ff),
		position = LAYOUT_NORTH,
		h = 100,
		order = { 'text' },
		text = {
			w = WH_FILL,
			h = 100,
			padding = { 10, 160, 10, 0 },
			align = "center",
			font = _font(100),
			fg = TEXT_COLOR,
			sh = TEXT_SH_COLOR,
		},
	}

	local menu_height = math.floor((screenHeight - TITLE_HEIGHT) / FIVE_ITEM_HEIGHT) * FIVE_ITEM_HEIGHT
	local grid_height = math.floor((screenHeight - TITLE_HEIGHT - 16) / 3) * 3

	s.menu = {
		h = menu_height,
		position = LAYOUT_CENTER,
		padding = { 0, 0, 0, 0 },
		itemHeight = FIVE_ITEM_HEIGHT,
		fg = {0xbb, 0xbb, 0xbb },
		font = _boldfont(120),
	}

	s.menu_hidden = _uses(s.menu, {
		hidden = 1,
	})
	
	s.item = {
		order = { "icon", "text", "arrow" },
		padding = { ITEM_LEFT_PADDING, 0, 8, 0 },
		text = {
			padding = { 0, 0, 2, 0 },
			align = "left",
			w = WH_FILL,
			h = WH_FILL,
			font = _boldfont(TEXTMENU_FONT_SIZE),
			fg = TEXT_COLOR,
			sh = TEXT_SH_COLOR,
		},
		icon = {
			padding = MENU_ITEM_ICON_PADDING,
			align = 'center',
		},
		arrow = {
			align = ITEM_ICON_ALIGN,
			img = _loadImage(self, "Icons/selection_right_5line.png"),
			padding = { 0, 0, 0, 0 },
		},
		bgImg = fiveItemBox,
	}

	s.itemG = {
		order = { "icon", "text" },
		orientation = 1,
		padding = { 8, 4, 8, 0 },
		text = {
			padding = { 0, 2, 0, 4 },
			align = "center",
			w = WH_FILL,
			h = WH_FILL,
			font = _boldfont(28),
			fg = TEXT_COLOR,
			sh = TEXT_SH_COLOR,
		},
		icon = {
			padding = MENU_ITEM_ICON_PADDING_G,
			align = 'center',
		},
		bgImg = false,
	}

	s.item_play = _uses(s.item, { 
		arrow = { img = false },
	})
	s.item_add = _uses(s.item, { 
		arrow = addArrow 
	})

	-- Checkbox
	s.checkbox = {}
	s.checkbox.align = 'center'
	s.checkbox.padding = CHECKBOX_RADIO_PADDING
	s.checkbox.h = WH_FILL
	s.checkbox.img_on = _loadImage(self, "Icons/checkbox_on.png")
	s.checkbox.img_off = _loadImage(self, "Icons/checkbox_off.png")
	

	-- Radio button
	s.radio = {}
	s.radio.align = 'center'
	s.radio.padding = CHECKBOX_RADIO_PADDING
	s.radio.h = WH_FILL
	s.radio.img_on = _loadImage(self, "Icons/radiobutton_on.png")
	s.radio.img_off = _loadImage(self, "Icons/radiobutton_off.png")

	s.item_choice = _uses(s.item, {
		order  = { 'icon', 'text', 'check' },
		choice = {
			h = WH_FILL,
			padding = CHECKBOX_RADIO_PADDING,
			align = 'right',
			font = _boldfont(TEXTMENU_FONT_SIZE),
			fg = TEXT_COLOR,
			sh = TEXT_SH_COLOR,
		},
	})
	s.item_checked = _uses(s.item, {
		order = { "icon", "text", "check", "arrow" },
		check = {
			align = ITEM_ICON_ALIGN,
			padding = CHECK_PADDING,
			img = _loadImage(self, "Icons/icon_check_5line.png")
		}
	})

	s.item_info = _uses(s.item, {
		order = { 'text' },
		padding = { ITEM_LEFT_PADDING, 0, 0, 0 },
		text = {
			align = "top-left",
			w = WH_FILL,
			h = WH_FILL,
			padding = { 0, 6, 0, 6 },
			font = _font(14),
			line = {
				{
					font = _font(14),
					height = 14,
				},
				{
					font = _boldfont(18),
					height = 18,
				},
			},
		},
	})

	s.item_no_arrow = _uses(s.item, {
		order = { 'icon', 'text' },
	})
	s.item_checked_no_arrow = _uses(s.item, {
		order = { 'icon', 'text', 'check' },
	})

	s.selected = {
		item = _uses(s.item, {
			bgImg = fiveItemSelectionBox
		}),
		item_play = _uses(s.item_play, {
			bgImg = fiveItemSelectionBox
		}),
		item_add = _uses(s.item_add, {
			bgImg = fiveItemSelectionBox
		}),
		item_checked = _uses(s.item_checked, {
			bgImg = fiveItemSelectionBox
		}),
		item_no_arrow = _uses(s.item_no_arrow, {
			bgImg = fiveItemSelectionBox
		}),
		item_checked_no_arrow = _uses(s.item_checked_no_arrow, {
			bgImg = fiveItemSelectionBox
		}),
		item_choice = _uses(s.item_choice, {
			bgImg = fiveItemSelectionBox
		}),
		item_info = _uses(s.item_info, {
			bgImg = fiveItemSelectionBox
		}),
	}

	s.pressed = {
		item = _uses(s.item, {
			bgImg = fiveItemPressedBox,
		}),
		item_checked = _uses(s.item_checked, {
			bgImg = fiveItemPressedBox,
		}),
		item_play = _uses(s.item_play, {
			bgImg = fiveItemPressedBox,
		}),
		item_add = _uses(s.item_add, {
			bgImg = fiveItemPressedBox,
		}),
		item_no_arrow = _uses(s.item_no_arrow, {
			bgImg = fiveItemPressedBox,
		}),
		item_checked_no_arrow = _uses(s.item_checked_no_arrow, {
			bgImg = fiveItemPressedBox,
		}),
		item_choice = _uses(s.item_choice, {
			bgImg = fiveItemPressedBox,
		}),
		item_info = _uses(s.item_info, {
			bgImg = fiveItemPressedBox,
		}),
	}

	s.locked = {
		item = _uses(s.pressed.item, {
			arrow = smallSpinny
		}),
		item_checked = _uses(s.pressed.item_checked, {
			arrow = smallSpinny
		}),
		item_play = _uses(s.pressed.item_play, {
			arrow = smallSpinny
		}),
		item_add = _uses(s.pressed.item_add, {
			arrow = smallSpinny
		}),
		item_no_arrow = _uses(s.item_no_arrow, {
			arrow = smallSpinny
		}),
		item_checked_no_arrow = _uses(s.item_checked_no_arrow, {
			arrow = smallSpinny
		}),
		item_info = _uses(s.item_info, {
			arrow = smallSpinny,
		}),
	}

	s.item_blank = {
		padding = {  },
		text = {},
		bgImg = helpTextBackground,
	}

	s.pressed.item_blank = _uses(s.item_blank)
	s.selected.item_blank = _uses(s.item_blank)

	s.help_text = {
		w = screenWidth - 30,
		padding = { 18, 18, 12, 0},
		font = _font(HELP_FONT_SIZE),
		lineHeight = 38,
		fg = TEXT_COLOR,
		sh = TEXT_SH_COLOR,
		align = "top-left",
	}

	s.scrollbar = {
		w = 46,
		border = 0,
		padding = { 0, 0, 0, 0 },
		horizontal = 0,
		bgImg = scrollBackground,
		img = scrollBar,
		layer = LAYER_CONTENT_ON_STAGE,
	}

	s.text = {
		w = screenWidth,
		h = WH_FILL,
		padding = TEXTAREA_PADDING,
		font = _boldfont(TEXTAREA_FONT_SIZE),
		fg = TEXT_COLOR,
		sh = TEXT_SH_COLOR,
		align = "left",
	}

	s.multiline_text = {
		w = WH_FILL,
		padding = { 10, 0, 2, 10 },
		font = _font(18),
		height = 21,
		fg = { 0xe6, 0xe6, 0xe6 },
		sh = { },
		align = "left",
	}
	s.multiline_popup_text = _uses(s.multiline_text, {
		padding = { 14, 18, 14, 18 },
		border = { 0, 0, 10, 0 },
	})

	s.slider = {
		border = 10,
		position = LAYOUT_SOUTH,
		horizontal = 1,
		bgImg = _progressBackground,
		img = _progressBar,
	}

	s.slider_group = {
		w = WH_FILL,
		border = { 0, 5, 0, 10 },
		order = { "min", "slider", "max" },
	}


--------- SPECIAL WIDGETS ---------


	-- text input
	s.textinput = {
		h = 72,
		padding = { 12, 0, 12, 0 },
		font = _boldfont(TEXTINPUT_FONT_SIZE),
		cursorFont = _boldfont(TEXTINPUT_FONT_SIZE),
		wheelFont = _boldfont(TEXTINPUT_FONT_SIZE),
		charHeight = TEXTINPUT_SELECTED_FONT_SIZE,
		fg = TEXT_COLOR_BLACK,
		charOffsetY = 8,
		wh = { 0x55, 0x55, 0x55 },
		cursorImg = textinputCursor,
	}

	-- keyboard
	s.keyboard = { hidden = 1 }

	s.keyboard_textinput = {
		bgImg = textinputBackground,
		w = WH_FILL,
		order = { "textinput", "backspace" },
		border = 0,
		textinput = {
			padding = { 16, 0, 0, 4 },
		},
	}


	local _timeFirstColumnX12h = 123
	local _timeFirstColumnX24h = 164

	s.time_input_background_12h = {
		w = WH_FILL,
		h = screenHeight - TITLE_HEIGHT,
		position = LAYOUT_NONE,
		img = _loadImage(self, "Multi_Character_Entry/tch_multi_char_bkgrd_3c.png"),
		x = 0,
		y = TITLE_HEIGHT,
	}

	s.time_input_background_24h = {
		w = WH_FILL,
		h = screenHeight - TITLE_HEIGHT,
		position = LAYOUT_NONE,
		img = _loadImage(self, "Multi_Character_Entry/tch_multi_char_bkgrd_2c.png"),
		x = 0,
		y = TITLE_HEIGHT,
	}

	s.time_input_menu_box_12h = {
		position = LAYOUT_NONE,
		img = _loadImage(self, "Multi_Character_Entry/menu_box_fixed.png"),
		w = 220,
		h = 40,
		x = 130,
		y = 140,
	}
	s.time_input_menu_box_24h = _uses(s.time_input_menu_box_12h, {
		img = _loadImage(self, "UNOFFICIAL/menu_box_fixed_2c.png"),
		w = 180,
		x = 167,
	
	})

	-- time input window
	s.input_time_12h = _uses(s.window)
	s.input_time_12h.hour = _uses(s.menu, {
		w = 75,
		--h = screenHeight - TITLE_HEIGHT,
		h = screenHeight,
		itemHeight = 45,
		position = LAYOUT_WEST,
		padding = 0,
		border = { _timeFirstColumnX12h, TITLE_HEIGHT, 0, 0 },
		item = {
			bgImg = false,
			order = { 'text' },
			text = {
				align = 'right',
				font = _boldfont(30),
				padding = { 2, 4, 8, 0 },
				fg = { 0xb3, 0xb3, 0xb3 },
				sh = { },
			},
		},
		selected = {
			item = {
				order = { 'text' },
				bgImg = false,
				text = {
					font = _boldfont(30),
					fg = { 0xe6, 0xe6, 0xe6 },
					sh = { },
					align = 'right',
					padding = { 2, 4, 8, 0 },
				},
			},
		},
		pressed = {
			item = {
				order = { 'text' },
				bgImg = false,
				text = {
					font = _boldfont(30),
					fg = { 0xe6, 0xe6, 0xe6 },
					sh = { },
					align = 'right',
					padding = { 2, 4, 8, 0 },
				},
			},
		},
	})
	s.input_time_12h.minute = _uses(s.input_time_12h.hour, {
		border = { _timeFirstColumnX12h + 75, TITLE_HEIGHT, 0, 0 },
	})
	s.input_time_12h.ampm = _uses(s.input_time_12h.hour, {
		border = { _timeFirstColumnX12h + 75 + 75, TITLE_HEIGHT, 0, 0 },
		item = {
			text = {
				padding = { 0, 2, 8, 0 },
				font = _boldfont(26),
			},
		},
		selected = {
			item = {
				text = {
					padding = { 0, 4, 8, 0 },
					font = _boldfont(26),
				},
			},
		},
		pressed = {
			item = {
				text = {
					padding = { 0, 4, 8, 0 },
					font = _boldfont(26),
				},
			},
		},
	})
	s.input_time_12h.hourUnselected   = s.input_time_12h.hour
	s.input_time_12h.minuteUnselected = s.input_time_12h.minute
	s.input_time_12h.ampmUnselected   = s.input_time_12h.ampm

	s.input_time_24h = _uses(s.input_time_12h, {
		hour = {
			border = { _timeFirstColumnX24h, TITLE_HEIGHT, 0, 0 },
		},
		minute = {
			border = { _timeFirstColumnX24h + 75, TITLE_HEIGHT, 0, 0 },
		},
		hourUnselected = {
			border = { _timeFirstColumnX24h, TITLE_HEIGHT, 0, 0 },
		},
		minuteUnselected = {
			border = { _timeFirstColumnX24h + 75, TITLE_HEIGHT, 0, 0 },
		},
	})

	-- one set for buttons, one for spacers

--------- WINDOW STYLES ---------
	--
	-- These styles override the default styles for a specific window

	-- typical text list window
	s.text_list = _uses(s.window)

	-- text_only removes icons
	s.text_only = _uses(s.text_list, {
		menu = {
			item = {
				order = { 'text', 'arrow', },
			},
			selected = {
				item = {
					order = { 'text', 'arrow', },
				}
			},
			pressed = {
				item = {
					order = { 'text', 'arrow', },
				}
			},
		},
	})

	s.text_list.title = _uses(s.title, {
		text = {
			line = {
				{
					font = _boldfont(TITLE_FONT_SIZE),
					height = 32,
				},
				{
					font = _font(14),
					fg   = { 0xB3, 0xB3, 0xB3 },
				},
			},
		},
	})

	s.text_list.title.textButton = _uses(s.text_list.title.text, {
		--bgImg = titlebarButtonBox,
		padding = { 4, 15, 4, 15 },
	})
	s.text_list.title.pressed = {}
	s.text_list.title.pressed.textButton = _uses(s.text_list.title.text, {
		bgImg = pressedTitlebarButtonBox,
		padding = { 4, 15, 4, 15 },
	})

	-- choose player window is exactly the same as text_list on all windows except WQVGAlarge
	s.choose_player = s.text_list

	s.multiline_text_list = _uses(s.text_list)

	s.multiline_text_list.menu = _uses(s.menu, {
		itemHeight = THREE_ITEM_HEIGHT,
		item = {
			padding = { 10, 8, 0, 8 },
			bgImg = false,
			icon = {
				align = 'top',
			},
		},
	})

	s.multiline_text_list.menu.item_no_arrow = _uses(s.multiline_text_list.menu.item)

	s.multiline_text_list.menu.selected = {}
	s.multiline_text_list.menu.selected.item = _uses(s.multiline_text_list.menu.item, {
		bgImg = threeItemSelectionBox,
	})
	s.multiline_text_list.menu.selected.item_no_arrow = _uses(s.multiline_text_list.menu.selected.item)

	s.multiline_text_list.menu.pressed = {}
	s.multiline_text_list.menu.pressed.item = _uses(s.multiline_text_list.menu.item, {
		bgImg = threeItemPressedBox,
	})
	s.multiline_text_list.menu.pressed.item_no_arrow = _uses(s.multiline_text_list.menu.pressed.item)
 
	-- popup "spinny" window
	s.waiting_popup = _uses(s.popup, {
		text = {
			w = WH_FILL,
			h = (POPUP_TEXT_SIZE_1 + 8 ),
			position = LAYOUT_NORTH,
			border = { 0, 34, 0, 14 },
			padding = { 15, 0, 15, 0 },
			align = "center",
			font = _font(POPUP_TEXT_SIZE_1),
			lineHeight = POPUP_TEXT_SIZE_1 + 8,
			fg = TEXT_COLOR,
			sh = TEXT_SH_COLOR,
		},
		subtext = {
			w = WH_FILL,
			h = 47,
			position = LAYOUT_SOUTH,
			border = 0,
			padding = { 15, 0, 15, 0 },
			--padding = { 0, 0, 0, 26 },
			align = "top",
			font = _boldfont(POPUP_TEXT_SIZE_2),
			fg = TEXT_COLOR,
			sh = TEXT_SH_COLOR,
		},
	})

	s.waiting_popup.subtext_connected = _uses(s.waiting_popup.subtext, {
		fg = TEXT_COLOR_TEAL,
	})

	s.black_popup = _uses(s.waiting_popup)
	s.black_popup.title = _uses(s.title, {
		bgImg = false,
		order = { },
	})

	-- input window (including keyboard)
	s.input = _uses(s.window)
	s.input.title = _uses(s.title, {
		-- remove 3px from the height and 3px from the bottom padding
		h = 44,
		padding = { 0, 5, 0, 2 },
		bgImg = inputTitleBox,
	})

	local clearMask = Tile:fillColor(0x00000000)

	s.power_on_window =  _uses(s.window)
	s.power_on_window.maskImg = clearMask
	s.power_on_window.title = _uses(s.title, {
		bgImg = false,
	})

	-- update window
	s.update_popup = _uses(s.popup, {
		text = {
			w = WH_FILL,
			h = (POPUP_TEXT_SIZE_1 + 8 ),
			position = LAYOUT_NORTH,
			border = { 0, 34, 0, 2 },
			padding = { 10, 0, 10, 0 },
			align = "center",
			font = _font(POPUP_TEXT_SIZE_1),
			lineHeight = POPUP_TEXT_SIZE_1 + 8,
			fg = TEXT_COLOR,
			sh = TEXT_SH_COLOR,		
		},
		subtext = {
			w = WH_FILL,
			-- note this is a hack as the height and padding push
			-- the content out of the widget bounding box.
			h = 30,
			padding = { 0, 0, 0, 28 },
			font = _boldfont(UPDATE_SUBTEXT_SIZE),
			fg = TEXT_COLOR,
			sh = TEXT_SH_COLOR,
			align = "bottom",
			position = LAYOUT_SOUTH,
		},

		progress = {
			border = { 15, 7, 15, 17 },
			position = LAYOUT_SOUTH,
			horizontal = 1,
			bgImg = _progressBackground,
			img = _progressBar,
		},
	})

	s.home_menu = _uses(s.text_list, {
		menu = {
			itemHeight = grid_height / 3,
			itemsPerLine = 6,
			item = _uses(s.itemG, {
				icon = {
					img = _loadImage(self, "IconsResized/icon_loading" .. skinSuffix)
				},
			}),
			item_play = _uses(s.itemG, {
				icon = {
					img = _loadImage(self, "IconsResized/icon_loading" .. skinSuffix)
				},
			}),
			item_add = _uses(s.itemG, {
				icon = {
					img = _loadImage(self, "IconsResized/icon_loading" .. skinSuffix)
				},
			}),
			item_choice = _uses(s.itemG, {
				order  = { 'icon', 'text', 'check' },
				text = {
					padding = { 0, 0, 0, 0 },
				},
				choice = {
					padding = { 0, 0, 0, 0 },
					align = 'center',
					font = _boldfont(32),
					fg = TEXT_COLOR,
					sh = TEXT_SH_COLOR,
				},
				icon = {
					img = _loadImage(self, "IconsResized/icon_loading" .. skinSuffix),
				},
			}),
			pressed = {
				item = _uses(s.itemG, {
					icon = {
						img = _loadImage(self, "IconsResized/icon_loading" .. skinSuffix),
					},
				}),
			},
			selected = {
				item = _uses(s.itemG, {
					icon = {
						img = _loadImage(self, "IconsResized/icon_loading" .. skinSuffix),
					},
					bgImg = gridItemSelectionBox,
				}),
			},
			locked = {
				item = _uses(s.itemG, {
					icon = {
						img = _loadImage(self, "IconsResized/icon_loading" .. skinSuffix),
					},
				}),
			},
		},
	})

	s.home_menu.menu.selected = {
		item = _uses(s.home_menu.menu.item, {
			bgImg = gridItemSelectionBox,
		}),
		item_choice = _uses(s.home_menu.menu.item_choice, {
			bgImg = gridItemSelectionBox,
		}),
		item_play = _uses(s.home_menu.menu.item_play, {
			bgImg = gridItemSelectionBox,
		}),
		item_add = _uses(s.home_menu.menu.item_add, {
			bgImg = gridItemSelectionBox,
		}),
	}

	-- icon_list window
	-- icon_list Grid
	s.icon_listG = _uses(s.window, {
		menu = {
			itemsPerLine = 6,
			itemHeight = grid_height / 3,
			item = _uses(s.itemG, {
				text = {
					font = _font(ALBUMMENU_SMALL_FONT_SIZE_G),
					line = {
						{
							font = _boldfont(ALBUMMENU_FONT_SIZE_G),
							height = 30,
						},
						{
							font = _font(ALBUMMENU_SMALL_FONT_SIZE_G),
						},
					},
				},
			})
		},
	})

	s.icon_listG.menu.item_checked = _uses(s.icon_listG.menu.item, {
		order = { 'icon', 'text', 'check', 'arrow' },
		check = {
			align = ITEM_ICON_ALIGN,
			padding = CHECK_PADDING,
			--img = _loadImage(self, "Icons/icon_check_5line.png")
		},
	})
	s.icon_listG.menu.item_play = _uses(s.icon_listG.menu.item, { 
		arrow = { img = false },
	})
	s.icon_listG.menu.albumcurrent = _uses(s.icon_listG.menu.item_play, {
		arrow = { img = false }, --_loadImage(self, "Icons/icon_nplay_3line_off.png"),
		--},
		--text = { padding = 0, },
		-- Bug 11482c#13, don't know why the bgImg has to be redefined again here, but this fixes the issue
		--bgImg = fiveItemBox,
	})
	s.icon_listG.menu.item_add  = _uses(s.icon_listG.menu.item, { 
		arrow = addArrow,
	})
	s.icon_listG.menu.item_no_arrow = _uses(s.icon_listG.menu.item, {
		order = { 'icon', 'text' },
	})
	s.icon_listG.menu.item_checked_no_arrow = _uses(s.icon_listG.menu.item_checked, {
		order = { 'icon', 'text', 'check' },
	})

	s.icon_listG.menu.selected = {
		item = _uses(s.icon_listG.menu.item, {
			bgImg = gridItemSelectionBox,
		}),
		albumcurrent = _uses(s.icon_listG.menu.albumcurrent, {
			--arrow = { 
			--	img = _loadImage(self, "Icons/icon_nplay_3line_sel.png"),
			--},
			bgImg = gridItemSelectionBox,
		}),
		item_checked = _uses(s.icon_listG.menu.item_checked, {
			bgImg = gridItemSelectionBox,
		}),
		item_play = _uses(s.icon_listG.menu.item_play, {
			bgImg = gridItemSelectionBox,
		}),
		item_add = _uses(s.icon_listG.menu.item_add, {
			bgImg = gridItemSelectionBox,
		}),
		item_no_arrow = _uses(s.icon_listG.menu.item_no_arrow, {
			bgImg = gridItemSelectionBox,
		}),
		item_checked_no_arrow = _uses(s.icon_listG.menu.item_checked_no_arrow, {
			bgImg = gridItemSelectionBox,
		}),
	}
	s.icon_listG.menu.pressed = {
		item = _uses(s.icon_listG.menu.item, { 
			bgImg = gridItemSelectionBox,
		}),
		albumcurrent = _uses(s.icon_listG.menu.albumcurrent, {
			bgImg = gridItemSelectionBox,
		}),
		item_checked = _uses(s.icon_listG.menu.item_checked, { 
			bgImg = gridItemSelectionBox,
		}),
		item_play = _uses(s.icon_listG.menu.item_play, { 
			bgImg = gridItemSelectionBox,
		}),
		item_add = _uses(s.icon_listG.menu.item_add, { 
			bgImg = gridItemSelectionBox,
		}),
		item_no_arrow = _uses(s.icon_listG.menu.item_no_arrow, { 
			bgImg = gridItemSelectionBox,
		}),
		item_checked_no_arrow = _uses(s.icon_listG.menu.item_checked_no_arrow, { 
			bgImg = gridItemSelectionBox,
		}),
	}
	s.icon_listG.menu.locked = {
		item = _uses(s.icon_listG.menu.pressed.item, {
			arrow = smallSpinny
		}),
		item_checked = _uses(s.icon_listG.menu.pressed.item_checked, {
			arrow = smallSpinny
		}),
		item_play = _uses(s.icon_listG.menu.pressed.item_play, {
			arrow = smallSpinny
		}),
		item_add = _uses(s.icon_listG.menu.pressed.item_add, {
			arrow = smallSpinny
		}),
		albumcurrent = _uses(s.icon_listG.menu.pressed.albumcurrent, {
			arrow = smallSpinny
		}),
	}

	-- icon_list Linear
	s.icon_listL = _uses(s.window, {
		menu = {
			item = {
				order = { "icon", "text", "arrow" },
				padding = { ITEM_LEFT_PADDING, 0, 0, 0 },
				text = {
					w = WH_FILL,
					h = WH_FILL,
					align = 'left',
					font = _font(ALBUMMENU_SMALL_FONT_SIZE),
					line = {
						{
							font = _boldfont(ALBUMMENU_FONT_SIZE),
							height = 35,
						},
						{
							font = _font(ALBUMMENU_SMALL_FONT_SIZE),
						},
					},
					fg = TEXT_COLOR,
					sh = TEXT_SH_COLOR,
				},
				icon = {
					h = THUMB_SIZE_L,
					padding = MENU_ITEM_ICON_PADDING,
					align = 'center',
				},
				arrow = _uses(s.item.arrow),
			},
		},
	})

	s.icon_listL.menu.item_checked = _uses(s.icon_listL.menu.item, {
		order = { 'icon', 'text', 'check', 'arrow' },
		check = {
			align = ITEM_ICON_ALIGN,
			padding = CHECK_PADDING,
			img = _loadImage(self, "Icons/icon_check_5line.png")
		},
	})
	s.icon_listL.menu.item_play = _uses(s.icon_listL.menu.item, { 
		arrow = { img = false },
	})
	s.icon_listL.menu.albumcurrent = _uses(s.icon_listL.menu.item_play, {
		arrow = { 
			img = _loadImage(self, "Icons/icon_nplay_3line_off.png"),
		},
		text = { padding = 0, },
		-- Bug 11482c#13, don't know why the bgImg has to be redefined again here, but this fixes the issue
		bgImg = fiveItemBox,
	})
	s.icon_listL.menu.item_add  = _uses(s.icon_listL.menu.item, { 
		arrow = addArrow,
	})
	s.icon_listL.menu.item_no_arrow = _uses(s.icon_listL.menu.item, {
		order = { 'icon', 'text' },
	})
	s.icon_listL.menu.item_checked_no_arrow = _uses(s.icon_listL.menu.item_checked, {
		order = { 'icon', 'text', 'check' },
	})

	s.icon_listL.menu.selected = {
		item = _uses(s.icon_listL.menu.item, {
			bgImg = fiveItemSelectionBox
		}),
		albumcurrent = _uses(s.icon_listL.menu.albumcurrent, {
			arrow = { 
				img = _loadImage(self, "Icons/icon_nplay_3line_sel.png"),
			},
			bgImg = fiveItemSelectionBox,
		}),
		item_checked = _uses(s.icon_listL.menu.item_checked, {
			bgImg = fiveItemSelectionBox
		}),
		item_play = _uses(s.icon_listL.menu.item_play, {
			bgImg = fiveItemSelectionBox
		}),
		item_add = _uses(s.icon_listL.menu.item_add, {
			bgImg = fiveItemSelectionBox
		}),
		item_no_arrow = _uses(s.icon_listL.menu.item_no_arrow, {
			bgImg = fiveItemSelectionBox
		}),
		item_checked_no_arrow = _uses(s.icon_listL.menu.item_checked_no_arrow, {
			bgImg = fiveItemSelectionBox
		}),
	}
	s.icon_listL.menu.pressed = {
		item = _uses(s.icon_listL.menu.item, { 
			bgImg = fiveItemPressedBox 
		}),
		albumcurrent = _uses(s.icon_listL.menu.albumcurrent, {
			bgImg = fiveItemSelectionBox
		}),
		item_checked = _uses(s.icon_listL.menu.item_checked, { 
			bgImg = fiveItemPressedBox 
		}),
		item_play = _uses(s.icon_listL.menu.item_play, { 
			bgImg = fiveItemPressedBox 
		}),
		item_add = _uses(s.icon_listL.menu.item_add, { 
			bgImg = fiveItemPressedBox 
		}),
		item_no_arrow = _uses(s.icon_listL.menu.item_no_arrow, { 
			bgImg = fiveItemPressedBox 
		}),
		item_checked_no_arrow = _uses(s.icon_listL.menu.item_checked_no_arrow, { 
			bgImg = fiveItemPressedBox 
		}),
	}
	s.icon_listL.menu.locked = {
		item = _uses(s.icon_listL.menu.pressed.item, {
			arrow = smallSpinny
		}),
		item_checked = _uses(s.icon_listL.menu.pressed.item_checked, {
			arrow = smallSpinny
		}),
		item_play = _uses(s.icon_listL.menu.pressed.item_play, {
			arrow = smallSpinny
		}),
		item_add = _uses(s.icon_listL.menu.pressed.item_add, {
			arrow = smallSpinny
		}),
		albumcurrent = _uses(s.icon_listL.menu.pressed.albumcurrent, {
			arrow = smallSpinny
		}),
	}

	s.icon_list = _uses(s.icon_listG)
	s.play_list = _uses(s.icon_listL)

	-- list window with help text
	s.help_list = _uses(s.text_list)

--[[
	-- BUG 11662, help_list used to have the top textarea fill the available space. That's been removed, but leaving this code in for now as an example of how to do that
	s.help_list = _uses(s.window)

	s.help_list.menu = _uses(s.menu, {
		position = LAYOUT_SOUTH,
		maxHeight = FIVE_ITEM_HEIGHT * 3,
		itemHeight = FIVE_ITEM_HEIGHT,
	})

	s.help_list.help_text = _uses(s.help_text, {
		h = WH_FILL,
		align = "left"
	})
--]]

	-- error window
	-- XXX: needs layout
	s.error = _uses(s.help_list)


	-- information window
	s.information = _uses(s.window)

	s.information.text = {
		font = _font(TEXTAREA_FONT_SIZE),
		fg = TEXT_COLOR,
		sh = TEXT_SH_COLOR,
		padding = { 18, 18, 10, 0},
		lineHeight = 23,
	}

	-- help window (likely the same as information)
	s.help_info = _uses(s.information)


	--track_list window
	-- XXXX todo
	-- identical to text_list but has icon in upper left of titlebar
	s.track_list = _uses(s.text_list)

	s.track_list.title = _uses(s.title, {
		order = { 'icon' }, -- { 'lbutton', 'icon', 'text', 'rbutton' },
		icon  = {
			w = THUMB_SIZE_L,
			h = WH_FILL,
			padding = { 10, 1, 8, 1 },
		},
	})


	-- toast_popup popup (is now text only)
	s.toast_popup_textarea = {
		padding = { 8, 8, 8, 8 } ,
		align = 'left',
		w = WH_FILL,
		h = WH_FILL,
		font = _boldfont(21),
		fg = TEXT_COLOR,
		sh = TEXT_SH_COLOR,
	}

	-- toast_popup popup with art and text
	s.toast_popup = {
		x = 5,
		y = screenHeight/2 - 93/2,
		w = screenWidth - 10,
		h = 93,
		bgImg = popupBox,
		group = {
			padding = 10,
			order = { 'icon', 'text' },
			text = { 
				padding = { 10, 12, 12, 12 } ,
				align = 'top-left',
				w = WH_FILL,
				h = WH_FILL,
				font = _font(HELP_FONT_SIZE),
				lineHeight = HELP_FONT_SIZE + 5,
			},
			icon = { 
				align = 'top-left', 
				border = { 12, 12, 0, 0 },
				img = _loadImage(self, "UNOFFICIAL/menu_album_noartwork_64.png"),
				h = WH_FILL,
				w = 64,
			}
		}
	}
	-- toast popup with textarea
	s.toast_popup_text = _uses(s.toast_popup, {
		group = {
			order = { 'text' },
			text = {
				w = WH_FILL,
				h = WH_FILL,
				align = 'top-left',
				padding = { 10, 12, 12, 12 },
				fg = TEXT_COLOR,
				sh = TEXT_SH_COLOR,
			},
		}
	})

	-- toast popup with icon only
	s.toast_popup_icon = _uses(s.toast_popup, {
		w = 190,
		h = 178,
		x = (screenWidth - 190) / 2,
		y = (screenHeight - 170) / 2,
		position = LAYOUT_NONE,
		group = {
			order = { 'icon' },
			border = { 22, 22, 0, 0 },
			padding = 0,
			icon = {
				w = WH_FILL,
				h = WH_FILL,
				align = 'center',
			},
		}
	})

	-- new style that incorporates text, icon, more text, and maybe a badge
	s.toast_popup_mixed = {
		x = 19,
		y = 16,
		position = LAYOUT_NONE,
		w = screenWidth - 38,
		h = 214,
		bgImg = popupBox,
		text = {
			position = LAYOUT_NORTH,
			padding = { 8, 24, 8, 0 },
			align = 'top',
			w = WH_FILL,
			h = WH_FILL,
			font = _boldfont(18),
			fg = TEXT_COLOR,
			sh = TEXT_SH_COLOR,
		},
		subtext = {
			position = LAYOUT_NORTH,
			padding = { 8, 178, 8, 0 },
			align = 'top',
			w = WH_FILL,
			h = WH_FILL,
			font = _boldfont(18),
			fg = TEXT_COLOR,
			sh = TEXT_SH_COLOR,
		},
	}

	s._badge = {
		position = LAYOUT_NONE,
		zOrder = 99,
		-- middle of the screen plus half of the icon width minus half of the badge width. gotta love LAYOUT_NONE
		x = screenWidth/2 + 21,
		w = 34,
		y = 34,
	}
	s.badge_none = _uses(s._badge, {
		img = false,
	})
	s.badge_favorite = _uses(s._badge, {
		img = _loadImage(self, "Icons/icon_badge_fav.png")
	})
	s.badge_add = _uses(s._badge, {
		img = _loadImage(self, "Icons/icon_badge_add.png")
	})

	s.context_menu = {
		x = 8,
		y = 16,
		w = screenWidth - 16,
		h = screenHeight - 32,
		bgImg = contextMenuBox,
		layer = LAYER_TITLE,

		multiline_text = {
			w = WH_FILL,
			h = WH_FILL, --172,
			padding = { 18, 2, 14, 18 },
			border = { 0, 0, 6, 15 },
			lineHeight = 22,
			font = _font(18),
			fg = { 0xe6, 0xe6, 0xe6 },
			sh = { },
			align = "top-left",
			scrollbar = {
				h = WH_FILL - 10, --164,
				border = {0, 2, 2, 10},
			},
		},

		title = {
			layer = LAYER_TITLE,
			h = 52,
			padding = {10,10,10,5},
			bgImg = false,
			button_cancel  = {
				layer = LAYER_TITLE,
				w       = 43,
				align = 'right',
			},
			pressed = {
				button_cancel  = {
					bgImg = pressedTitlebarButtonBox,
					layer = LAYER_TITLE,
					w       = 43,
				},
			},
			text = {
				layer = LAYER_TITLE,
				w = WH_FILL,
				padding = {0,0,20,0},
				align = "center",
				font = _boldfont(TITLE_FONT_SIZE),
				fg = TEXT_COLOR,
			},

		},
		menu = {
			h = screenHeight - 48, --CM_MENU_HEIGHT * 8,
			border = { 7, 0, 7, 0 },
			padding = { 0, 0, 0, 100 },
			scrollbar = { 
				h = screenHeight - 96, --CM_MENU_HEIGHT * 8,
			},
			item = {
				h = CM_MENU_HEIGHT,
				order = { "icon", "text", "arrow" },
				padding = { ITEM_LEFT_PADDING, 0, 12, 0 },
				text = {
					padding = { 0, 4, 0, 0 },
					w = WH_FILL,
					h = WH_FILL,
					align = 'left',
					font = _font(ALBUMMENU_SMALL_FONT_SIZE),
					line = {
						{
							font = _boldfont(ALBUMMENU_FONT_SIZE),
							height = 22,
						},
						{
							font = _font(ALBUMMENU_SMALL_FONT_SIZE),
						},
					},
					fg = TEXT_COLOR,
					sh = TEXT_SH_COLOR,
				},
				icon = {
					h = THUMB_SIZE_L,
					padding = MENU_ITEM_ICON_PADDING,
					align = 'center',
				},
				arrow = _uses(s.item.arrow),
			},
			selected = {
				item = {
					order = { "icon", "text", "arrow" },
					bgImg = fiveItemSelectionBox,
					padding = { ITEM_LEFT_PADDING, 0, 12, 0 },
					text = {
						padding = { 0, 4, 0, 0 },
						w = WH_FILL,
						h = WH_FILL,
						align = 'left',
						font = _font(ALBUMMENU_SMALL_FONT_SIZE),
						line = {
							{
								font = _boldfont(ALBUMMENU_FONT_SIZE),
								height = 22,
							},
							{
								font = _font(ALBUMMENU_SMALL_FONT_SIZE),
							},
						},
						fg = TEXT_COLOR,
						sh = TEXT_SH_COLOR,
					},
					icon = {
						h = THUMB_SIZE_L,
						padding = MENU_ITEM_ICON_PADDING,
						align = 'center',
					},
					arrow = _uses(s.item.arrow),
				},
			},

		},
	}
	
	-- FIXME find why the bgImg needs to be included here...
	s.context_menu.menu.item_play = _uses(s.context_menu.menu.item, {
		arrow = {img = playArrow.img},
		bgImg = fiveItemBox,
	})
	s.context_menu.menu.selected.item_play = _uses(s.context_menu.menu.selected.item, {
		arrow = {img = playArrow.img},
	})

	s.context_menu.menu.item_insert = _uses(s.context_menu.menu.item, {
		arrow = {img = addArrow.img},
		bgImg = fiveItemBox,
	})
	s.context_menu.menu.selected.item_insert = _uses(s.context_menu.menu.selected.item, {
		arrow = {img = addArrow.img},
	})

	s.context_menu.menu.item_add = _uses(s.context_menu.menu.item, {
		arrow = {img = addArrow.img},
		bgImg = fiveItemBox,
	})
	s.context_menu.menu.selected.item_add = _uses(s.context_menu.menu.selected.item, {
		arrow = {img = addArrow.img},
	})

	s.context_menu.menu.item_playall = _uses(s.context_menu.menu.item, {
		arrow = {img = playArrow.img},
		bgImg = fiveItemBox,
	})
	s.context_menu.menu.selected.item_playall = _uses(s.context_menu.menu.selected.item, {
		arrow = {img = playArrow.img},
	})

	s.context_menu.menu.item_fav = _uses(s.context_menu.menu.item, {
		arrow = {img = favItem.img},
		bgImg = fiveItemBox,
	})
	s.context_menu.menu.selected.item_fav = _uses(s.context_menu.menu.selected.item, {
		arrow = {img = favItem.img},
	})

	s.context_menu.menu.item_no_arrow = _uses(s.context_menu.menu.item, {
		order = { 'text' },
		bgImg = fiveItemBox,
	})
	s.context_menu.menu.selected.item_no_arrow = _uses(s.context_menu.menu.selected.item, {
		order = { 'text' },
	})

	s.context_menu.menu.pressed = _uses(s.context_menu.menu.selected, {
		item = {
			bgImg = contextMenuPressedBox,
		},
	})

	s.context_menu.menu.locked = _uses(s.context_menu.menu.pressed, {
		item = {
			arrow = smallSpinny,
		},
	})

	-- alarm popup
	s.alarm_header = {
		w = screenWidth,
		--padding = { 50, 0, 50, 0 },
		--order = { 'icon', 'time' },
		order = { 'time' },
	}

	s.alarm_time = {
		w = screenWidth - 20,
		fg = TEXT_COLOR,
		sh = TEXT_SH_COLOR,
		align = "center",
		font = _boldfont(62),
	}

	s.preview_text = _uses(s.alarm_time, {
		font = _boldfont(TITLE_FONT_SIZE),
	})
	
	-- alarm menu window
	s.alarm_popup = {
		x = 10,
		y = 10,
		w = screenWidth - 20,
		h = screenHeight - 17,
		border = 0,
		padding = 0,
		bgImg = contextMenuBox,
		layer = LAYER_TITLE,
		title = {
			layer = LAYER_TITLE,
			w = WH_FILL,
			h = 52,
			--padding = { 0, 10, 0, 0 },
			padding = { 10, 10, 10, 5 },
			bgImg = false,
		},

		menu = {
			h = CM_MENU_HEIGHT * 5,
			w = screenWidth - 34,
			x = 7,
			y = 65,
			border = 0,
			itemHeight = CM_MENU_HEIGHT,
			position = LAYOUT_NORTH,
			scrollbar = { 
				h = CM_MENU_HEIGHT * 5 - 8,
				border = {0,4,0,0},
			},
			item = {
				h = CM_MENU_HEIGHT,
				order = { "text", "arrow" },
				text = {
					w = WH_FILL,
					h = WH_FILL,
					align = 'left',
					font = _boldfont(TEXTMENU_FONT_SIZE),
					fg = TEXT_COLOR,
					sh = TEXT_SH_COLOR,
				},
				arrow = _uses(s.item.arrow),
			},
			selected = {
				item = {
					bgImg = fiveItemSelectionBox,
					order = { "text", "arrow" },
					text = {
						w = WH_FILL,
						h = WH_FILL,
						align = 'left',
						font = _boldfont(TEXTMENU_FONT_SIZE),
						fg = TEXT_COLOR,
						sh = TEXT_SH_COLOR,
					},
					arrow = _uses(s.item.arrow),
				},
			},

		},
	}
	-- slider popup (volume)
	s.slider_popup = {
		x = 50,
		y = screenHeight/2 - 100,
		w = screenWidth - 100,
		h = 200,
		bgImg = popupBox,
		heading = {
			w = WH_FILL,
		      border = 10,
		      fg = TEXT_COLOR,
		      font = _boldfont(32),
			padding = { 4, 16, 4, 0 },
		      align = "center",
		      bgImg = false,
		},
		slider_group = {
			w = WH_FILL,
			align = 'center',
			padding = { 10, 0, 10, 0 },
			order = { 'slider' },
		},
	}


       -- scanner popup
	s.scanner_popup = _uses(s.slider_popup, {
		h = 110,
		y = screenHeight/2 - 55,
	})

	s.image_popup = _uses(s.popup, {
		image = {
			w = screenWidth,
			position = LAYOUT_CENTER,
			align = "center",
			h = screenHeight,
			border = 0,
		},
	})


--------- SLIDERS ---------


	s.volume_slider = {
		w = WH_FILL,
		border = { 0, 0, 0, 10 },
		bgImg = _volumeSliderBackground,
		img = _popupSliderBar,
	}

	s.scanner_slider = _uses(s.volume_slider, {
		img = _volumeSliderBar,
	})
	
--------- BUTTONS ---------

	-- base button
	local _button = {
		bgImg = titlebarButtonBox,
		w = TITLE_BUTTON_WIDTH,
		h = WH_FILL,
		border = { 8, 0, 8, 0 },
		icon = {
			w = WH_FILL,
			h = WH_FILL,
			hidden = 1,
			align = 'center',
			img = false,
		},
		text = {
			w = WH_FILL,
			h = WH_FILL,
			hidden = 1,
			border = 0,
			padding = 0,
			align = 'center',
			font = _font(16),
			fg = { 0xdc,0xdc, 0xdc },
		},
	}
	local _pressed_button = _uses(_button, {
		bgImg = pressedTitlebarButtonBox,
	})


	-- icon button factory
	local _titleButtonIcon = function(name, icon, attr)
		s[name] = _uses(_button)
		s[name].layer = LAYER_TITLE

		s.pressed[name] = _uses(_pressed_button)

		attr = {
			hidden = 0,
			img = icon,
			layer = LAYER_TITLE,
		}

		s[name].icon = _uses(_button.icon, attr)
		s[name].w = 65
		s.pressed[name].icon = _uses(_pressed_button.icon, attr)
		s.pressed[name].w = 65
	end

	-- text button factory
	local _titleButtonText = function(name, string)
		s[name] = _uses(_button)
		s.pressed[name] = _uses(_pressed_button)

		attr = {
			hidden = 0,
			text = string,
		}

		s[name].text = _uses(_button.text, attr)
		s[name].w = 65
		s.pressed[name].text = _uses(_pressed_button.text, attr)
		s.pressed[name].w = 65
	end


	-- invisible button
	s.button_none = _uses(_button, {
		bgImg    = false,
		w = TITLE_BUTTON_WIDTH  - 12,
	})

	_titleButtonIcon("button_back", backButton)
	_titleButtonIcon("button_cancel", cancelButton)
	_titleButtonIcon("button_go_home", homeButton)
	_titleButtonIcon("button_playlist", playlistButton)
	_titleButtonIcon("button_more", moreButton)
	_titleButtonIcon("button_go_playlist", playlistButton)
	_titleButtonIcon("button_go_now_playing", nowPlayingButton)
	_titleButtonIcon("button_power", powerButton)
	_titleButtonIcon("button_nothing", nil)
	_titleButtonIcon("button_help", helpButton)
	_titleButtonText("button_more_help", self:string("MORE_HELP"))
	_titleButtonText("button_finish_operation", self:string("ENTER"))

	s.button_back.padding     = { 2, 0, 0, 2 }
	s.button_playlist.padding = { 2, 0, 0, 2 }

	s.button_volume_min = {
		img = _loadImage(self, "Icons/icon_toolbar_vol_down.png"),
		border = { 5, 0, 5, 0 },
	}

	s.button_volume_max = {
		img = _loadImage(self, "Icons/icon_toolbar_vol_up.png"),
		border = { 5, 0, 5, 0 },
	}

	s.button_keyboard_back = {
		align = 'left',
		w = 96,
		h = 66,
		padding = { 14, 0, 0, 0 },
		border = { 0, 2, 9, 5}, 
		img = _loadImage(self, "Icons/icon_delete_tch_text_entry.png"),
		bgImg = deleteKeyBackground,
	}
	s.pressed.button_keyboard_back = _uses(s.button_keyboard_back, {
                bgImg = deleteKeyPressedBackground,
	})


	local _buttonicon = {
		h   = THUMB_SIZE_G,
		padding = MENU_ITEM_ICON_PADDING_G,
		align = 'center',
		img = false,
	}

	s.region_US = _uses(_buttonicon, { 
		img = _loadImage(self, "IconsResized/icon_region_americas" .. skinSuffix),
	})
	s.region_XX = _uses(_buttonicon, { 
		img = _loadImage(self, "IconsResized/icon_region_other" .. skinSuffix),
	})
	s.icon_help = _uses(_buttonicon, { 
		img = _loadImage(self, "IconsResized/icon_help" .. skinSuffix),
	})
	s.wlan = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_wireless" .. skinSuffix),
	})
	s.wired = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_ethernet" .. skinSuffix),
	})


--------- ICONS --------

	-- icons used for 'waiting' and 'update' windows
	local _icon = {
		w = WH_FILL,
		align = "center",
		position = LAYOUT_CENTER,
		padding = { 0, 0, 0, 10 }
	}

	local _popupicon = {
		padding = 0,
		border = { 22, 18, 0, 0 },
		h = WH_FILL,
		w = 166,
	}

	local no_artwork_iconG = _loadImage(self, "IconsResized/icon_album_noart" .. skinSuffix ):resize(THUMB_SIZE_G, THUMB_SIZE_G)
	local no_artwork_iconL = _loadImage(self, "IconsResized/icon_album_noart" .. skinSuffix ):resize(THUMB_SIZE_L, THUMB_SIZE_L)

	-- icon for albums with no artwork
	s.icon_no_artwork = {
		img = no_artwork_iconG,
		h   = THUMB_SIZE_G,
		padding = MENU_ITEM_ICON_PADDING_G,
		align = 'center',
	}

	-- alternative small artwork for playlists
	s.icon_no_artwork_playlist = {
		img = no_artwork_iconL,
		h   = THUMB_SIZE_L,
		padding = MENU_ITEM_ICON_PADDING,
		align = 'center',
	}

	s.icon_connecting = _uses(_icon, {
		img = _loadImage(self, "Alerts/wifi_connecting.png"),
		frameRate = 8,
		frameWidth = 120,
		h = WH_FILL,
		padding = { 0, 2, 0, 10 },
	})

	s.icon_connected = _uses(_icon, {
		img = _loadImage(self, "Alerts/connecting_success_icon.png"),
		padding = { 0, 2, 0, 10 },
	})

	s.icon_photo_loading = _uses(_icon, {
		img = _loadImage(self, "Icons/image_viewer_loading.png"),
	})

	s.icon_software_update = _uses(_icon, {
		img = _loadImage(self, "IconsResized/icon_firmware_update" .. skinSuffix),
	})

	s.icon_restart = _uses(_icon, {
		img = _loadImage(self, "IconsResized/icon_restart" .. skinSuffix),
	})

	s.icon_popup_pause = _uses(_popupicon, {
		img = _loadImage(self, "Icons/icon_popup_box_pause.png"),
	})

	s.icon_popup_play = _uses(_popupicon, {
		img = _loadImage(self, "Icons/icon_popup_box_play.png"),
	})

	s.icon_popup_fwd = _uses(_popupicon, {
		img = _loadImage(self, "Icons/icon_popup_box_fwd.png"),
	})
	s.icon_popup_rew = _uses(_popupicon, {
		img = _loadImage(self, "Icons/icon_popup_box_rew.png"),
	})

	s.icon_popup_stop = _uses(_popupicon, {
		img = _loadImage(self, "Icons/icon_popup_box_stop.png"),
	})
	s.icon_popup_lineIn = _uses(_popupicon, {
		img = _loadImage(self, "IconsResized/icon_linein_134.png"),
	})

	s.icon_popup_volume = {
		img = _loadImage(self, "Icons/icon_popup_box_volume_bar.png"),
		w = WH_FILL,
		h = 90,
		align = 'center',
		padding = { 0, 5, 0, 5 },
	}

	s.icon_popup_mute = _uses(s.icon_popup_volume, {
		img = _loadImage(self, "Icons/icon_popup_box_volume_mute.png"),
	})

	s.icon_popup_shuffle0 = _uses(_popupicon, {
		img = _loadImage(self, "Icons/icon_popup_box_shuffle_off.png"),
	})

	s.icon_popup_shuffle1 = _uses(_popupicon, {
		img = _loadImage(self, "Icons/icon_popup_box_shuffle.png"),
	})

	s.icon_popup_shuffle2 = _uses(_popupicon, {
    	img = _loadImage(self, "Icons/icon_popup_box_shuffle_album.png"),
	})

	s.icon_popup_repeat0 = _uses(_popupicon, {
		img = _loadImage(self, "Icons/icon_popup_box_repeat_off.png"),
	})

	s.icon_popup_repeat1 = _uses(_popupicon, {
		img = _loadImage(self, "Icons/icon_popup_box_repeat_song.png"),
	})

	s.icon_popup_repeat2 = _uses(_popupicon, {
		img = _loadImage(self, "Icons/icon_popup_box_repeat.png"),
	})

	s.icon_popup_sleep_15 = {
		img = _loadImage(self, "Icons/icon_popup_box_sleep_15.png"),
		h = WH_FILL,
		w = WH_FILL,
		padding = { 24, 24, 0, 0 },
	}
	s.icon_popup_sleep_30 = _uses(s.icon_popup_sleep_15, {
		img = _loadImage(self, "Icons/icon_popup_box_sleep_30.png"),
	})
	s.icon_popup_sleep_45 = _uses(s.icon_popup_sleep_15, {
		img = _loadImage(self, "Icons/icon_popup_box_sleep_45.png"),
	})
	s.icon_popup_sleep_60 = _uses(s.icon_popup_sleep_15, {
		img = _loadImage(self, "Icons/icon_popup_box_sleep_60.png"),
	})
	s.icon_popup_sleep_90 = _uses(s.icon_popup_sleep_15, {
		img = _loadImage(self, "Icons/icon_popup_box_sleep_90.png"),
	})
	s.icon_popup_sleep_cancel = _uses(s.icon_popup_sleep_15, {
		img = _loadImage(self, "Icons/icon_popup_box_sleep_off.png"),
		padding = { 24, 34, 0, 0 },
	})

	s.icon_power = _uses(_icon, {
		img = _loadImage(self, "IconsResized/icon_restart" .. skinSuffix),
	})

	s.icon_locked = _uses(_icon, {
-- FIXME no asset for this (needed?)
--		img = _loadImage(self, "Alerts/popup_locked_icon.png"),
	})

	s.icon_alarm = {
		img = _loadImage(self, "Icons/icon_alarm.png"),
	}

	s.icon_art = _uses(_icon, {
		padding = 0,
        img = false,
	})

	s.player_transporter = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_transporter" .. skinSuffix),
	})
	s.player_squeezebox = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_SB1n2" .. skinSuffix),
	})
	s.player_squeezebox2 = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_SB1n2" .. skinSuffix),
	})
	s.player_squeezebox3 = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_SB3" .. skinSuffix),
	})
	s.player_boom = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_boom" .. skinSuffix),
	})
	s.player_slimp3 = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_slimp3" .. skinSuffix),
	})
	s.player_softsqueeze = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_softsqueeze" .. skinSuffix),
	})
	s.player_controller = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_controller" .. skinSuffix),
	})
	s.player_receiver = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_receiver" .. skinSuffix),
	})
	s.player_squeezeplay = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_squeezeplay" .. skinSuffix),
	})
	s.player_http = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_tunein_url" .. skinSuffix),
	})
	s.player_baby = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_baby" .. skinSuffix),
	})
	s.player_fab4 = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_fab4" .. skinSuffix),
	})

	-- misc home menu icons
	s.hm_appletImageViewer = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_image_viewer" .. skinSuffix),
	})
	s.hm_eject = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_eject" .. skinSuffix),
	})
	s.hm_sdcard = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_device_SDcard" .. skinSuffix),
	})
	s.hm_usbdrive = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_device_USB" .. skinSuffix),
	})
	s.hm_appletNowPlaying = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_nowplaying" .. skinSuffix),
	})
	s.hm_settings = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_settings" .. skinSuffix),
	})
	s.hm_advancedSettings = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_settings_adv" .. skinSuffix),
	})
	s.hm_radio = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_internet_radio" .. skinSuffix),
	})
	s.hm_radios = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_internet_radio" .. skinSuffix),
	})
	s.hm_myApps = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_my_apps" .. skinSuffix),
	})
	s.hm_myMusic = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_mymusic" .. skinSuffix),
	})
	s.hm__myMusic = _uses(s.hm_myMusic)
   	s.hm_otherLibrary = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_ml_other_library" .. skinSuffix),
	})
	s.hm_myMusicSelector = _uses(s.hm_myMusic)

	s.hm_favorites = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_favorites" .. skinSuffix),
	})
	s.hm_settingsAlarm = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_alarm" .. skinSuffix),
	})
	s.hm_settingsPlayerNameChange = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_settings_name" .. skinSuffix),
	})
	s.hm_settingsBrightness = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_settings_brightness" .. skinSuffix),
	})
	s.hm_settingsSync = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_sync" .. skinSuffix),
	})
	s.hm_selectPlayer = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_choose_player" .. skinSuffix),
	})
	s.hm_quit = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_power_off" .. skinSuffix),
	})
	s.hm_playerpower = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_power_off" .. skinSuffix),
	})
	s.hm_settingsScreen = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_blank" .. skinSuffix),
	})
	s.hm_myMusicArtists = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_ml_artist" .. skinSuffix),
	})
	s.hm_myMusicAlbums = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_ml_albums" .. skinSuffix),
	})
	s.hm_myMusicGenres = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_ml_genres" .. skinSuffix),
	})
	s.hm_myMusicYears = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_ml_years" .. skinSuffix),
	})

	s.hm_myMusicNewMusic = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_ml_new_music" .. skinSuffix),
	})
	s.hm_myMusicPlaylists = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_ml_playlist" .. skinSuffix),
	})
	s.hm_myMusicSearch = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_ml_search" .. skinSuffix),
	})
	s.hm_myMusicSearchArtists   = _uses(s.hm_myMusicSearch)
	s.hm_myMusicSearchAlbums    = _uses(s.hm_myMusicSearch)
	s.hm_myMusicSearchSongs     = _uses(s.hm_myMusicSearch)
	s.hm_myMusicSearchPlaylists = _uses(s.hm_myMusicSearch)
	s.hm_myMusicSearchRecent    = _uses(s.hm_myMusicSearch)
	s.hm_homeSearchRecent       = _uses(s.hm_myMusicSearch)
	s.hm_globalSearch           = _uses(s.hm_myMusicSearch)

	s.hm_myMusicMusicFolder = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_ml_folder" .. skinSuffix),
	})
	s.hm_randomplay = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_ml_random" .. skinSuffix),
	})
	s.hm_skinTest = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_blank" .. skinSuffix),
	})

	s.hm_settingsRepeat = _uses(_buttonicon, {
    	img = _loadImage(self, "IconsResized/icon_settings_repeat" .. skinSuffix),
	})
	s.hm_settingsShuffle = _uses(_buttonicon, {
    	img = _loadImage(self, "IconsResized/icon_settings_shuffle" .. skinSuffix),
	})
	s.hm_settingsSleep = _uses(_buttonicon, {
    	img = _loadImage(self, "IconsResized/icon_settings_sleep" .. skinSuffix),
	})
	s.hm_settingsScreen = _uses(_buttonicon, {
    	img = _loadImage(self, "IconsResized/icon_settings_screen" .. skinSuffix),
	})
	s.hm_appletCustomizeHome = _uses(_buttonicon, {
    	img = _loadImage(self, "IconsResized/icon_settings_home" .. skinSuffix),
	})
	s.hm_settingsAudio = _uses(_buttonicon, {
    	img = _loadImage(self, "IconsResized/icon_settings_audio" .. skinSuffix),
	})
	s.hm_linein = _uses(_buttonicon, {
    	img = _loadImage(self, "IconsResized/icon_linein" .. skinSuffix),
	})

        -- ??
	s.hm_loading = _uses(_buttonicon, {
    	img = _loadImage(self, "IconsResized/icon_loading" .. skinSuffix),
	})
        -- ??
	s.hm_settingsPlugin = _uses(_buttonicon, {
    	img = _loadImage(self, "IconsResized/icon_settings_plugin" .. skinSuffix),
	})

	-- indicator icons, on right of menus
	local _indicator = {
		align = "center",
	}

	s.wirelessLevel1 = _uses(_indicator, {
		img = _loadImage(self, "Icons/icon_wireless_1.png")
	})

	s.wirelessLevel2 = _uses(_indicator, {
		img = _loadImage(self, "Icons/icon_wireless_2.png")
	})

	s.wirelessLevel3 = _uses(_indicator, {
		img = _loadImage(self, "Icons/icon_wireless_3.png")
	})

	s.wirelessLevel4 = _uses(_indicator, {
		img = _loadImage(self, "Icons/icon_wireless_4.png")
	})

	s.wirelessDisabled = _uses(_indicator, {
		img = _loadImage(self, "Icons/icon_wireless_disabled.png")
	})

	s.wirelessWaiting = _uses(_indicator, {
		img = _loadImage(self, "Icons/icon_wireless_waiting.png")
	})


--------- ICONBAR ---------

	s.iconbar_group = {
		hidden = 1,
	}

	-- time (hidden off screen)
	s.button_time = {
		hidden = 1,
	}

	-- BEGIN NowPlaying skin code

	local NP_ARTISTALBUM_FONT_SIZE = math.floor(72*screenWidth/1920)
	local NP_TRACK_FONT_SIZE = math.floor(72*screenWidth/1920)

	local controlHeight = 66
	local controlWidth = 100
	local buttonPadding = 0

	local _transportControlButton = {
		w = controlWidth,
		h = controlHeight,
		align = 'center',
		padding = buttonPadding,
	}

	local _transportControlBorder = _uses(_transportControlButton, {
		w = 2,
		padding = 0,
		img = touchToolbarKeyDivider,		
	})

	coverSize = math.floor(math.min((screenHeight - TITLE_HEIGHT - 20), screenWidth/2 - 50) / 10) * 10

	local _tracklayout = {
		border = { 10, 0, 10, 0 },
		position = LAYOUT_NONE,
		w = WH_FILL,
		align = "left",
		lineHeight = NP_TRACK_FONT_SIZE,
		fg = TEXT_COLOR,
		x = coverSize + math.floor(100 * screenWidth / 1920), 
	}

	s.nowplaying = _uses(s.window, {
		--title bar
		title = _uses(s.title, {
			zOrder = 1,
			text = {
				font = _boldfont(TITLE_FONT_SIZE),
				--bgImg   = titlebarButtonBox,
			},
			--[[
			rbutton  = {
				font    = _font(14),
				fg      = TEXT_COLOR,
				bgImg   = titlebarButtonBox,
				w       = TITLE_BUTTON_WIDTH,
				padding = { 8, 0, 8, 0},
				align   = 'center',
			}
			--]]
		}),
	
		-- Song metadata
		nptitle = {
			order = { 'nptrack' },
			position   = _tracklayout.position,
			border     = _tracklayout.border,
			x          = _tracklayout.x,
			y 	   = TITLE_HEIGHT + (screenHeight - TITLE_HEIGHT - coverSize) / 2 + coverSize * 0 / 6,
			h          = 90,
			nptrack =  {
				padding    = { 0, 20, 0, 0 },
				w          = screenWidth - _tracklayout.x - math.floor(50 * screenWidth / 1920),
				align      = _tracklayout.align,
				lineHeight = _tracklayout.lineHeight,
				fg         = _tracklayout.fg,
				font       = _boldfont(NP_TRACK_FONT_SIZE), 
				sh = TEXT_SH_COLOR,
			},
		},
		npartistgroup = {
			order = { 'npartist' },
			position   = _tracklayout.position,
			border     = _tracklayout.border,
			x          = _tracklayout.x,
			y 	   = TITLE_HEIGHT + (screenHeight - TITLE_HEIGHT - coverSize) / 2 + coverSize * 1 / 6,
			h          = 90,
			npartist = {
				padding    = { 0, 20, 0, 0 },
				w          = screenWidth - _tracklayout.x - math.floor(50 * screenWidth / 1920),
				align      = _tracklayout.align,
				lineHeight = _tracklayout.lineHeight,
				fg         = _tracklayout.fg,
				font       = _font(NP_ARTISTALBUM_FONT_SIZE),
				sh = TEXT_SH_COLOR,
			},
		},
		npalbumgroup = {
			order = {'npalbum' },
			position   = _tracklayout.position,
			border     = _tracklayout.border,
			x          = _tracklayout.x,
			y 	   = TITLE_HEIGHT + (screenHeight - TITLE_HEIGHT - coverSize) / 2 + coverSize * 2 / 6,
			h          = 90,
			npalbum = {
				w          = screenWidth - _tracklayout.x - math.floor(50 * screenWidth / 1920),
				padding    = { 0, 20, 0, 0 },
				align      = _tracklayout.align,
				lineHeight = _tracklayout.lineHeight,
				fg         = _tracklayout.fg,
				font       = _font(NP_ARTISTALBUM_FONT_SIZE),
				sh = TEXT_SH_COLOR,
			},
		},
		npartistalbum = {
			hidden = 1,
		},
	
		-- cover art
		npartwork = {
			w = coverSize,
			position = LAYOUT_NONE,
			x = math.floor(50 * screenWidth/1920),
			y = TITLE_HEIGHT + (screenHeight - TITLE_HEIGHT - coverSize) / 2,
			align = "center",
			h = coverSize,

			artwork = {
				w = coverSize,
				h = coverSize,
				align = "center",
				padding = 0,
				img = false,
			},
		},

		npvisu = { hidden = 1 },
	
		--transport controls - hidden
		npcontrols = {
			order = { 'repeatMode', 'shuffleMode' },
			position = LAYOUT_NONE,
			x = coverSize + math.floor(100 * screenWidth/1920) + (screenWidth - _tracklayout.x - math.floor(50 * screenWidth/1920) - 8)/2 - controlWidth,
			y = TITLE_HEIGHT + (screenHeight - TITLE_HEIGHT - coverSize) / 2 + coverSize * 5.5 / 6,	
			h = controlHeight,
			w = WH_FILL,
			shuffleMode = _uses(_transportControlButton, {
				img = _loadImage(self, "Icons/icon_toolbar_shuffle_off.png"),
			}),
			shuffleOff = _uses(_transportControlButton, {
				img = _loadImage(self, "Icons/icon_toolbar_shuffle_off.png"),
			}),
			shuffleSong = _uses(_transportControlButton, {
				img = _loadImage(self, "Icons/icon_toolbar_shuffle_on.png"),
			}),
			shuffleAlbum = _uses(_transportControlButton, {
				img = _loadImage(self, "Icons/icon_toolbar_shuffle_album_on.png"),
			}),
			repeatMode = _uses(_transportControlButton, {
				img = _loadImage(self, "Icons/icon_toolbar_repeat_off.png"),
			}),
			repeatOff = _uses(_transportControlButton, {
				img = _loadImage(self, "Icons/icon_toolbar_repeat_off.png"),
			}),
			repeatPlaylist = _uses(_transportControlButton, {
				img = _loadImage(self, "Icons/icon_toolbar_repeat_on.png"),
			}),
			repeatSong = _uses(_transportControlButton, {
				img = _loadImage(self, "Icons/icon_toolbar_repeat_song_on.png"),
			}),
			shuffleDisabled = _uses(_transportControlButton, {
				img = _loadImage(self, "Icons/icon_toolbar_shuffle_dis.png"),
			}),
			repeatDisabled = _uses(_transportControlButton, {
				img = _loadImage(self, "Icons/icon_toolbar_repeat_dis.png"),
			}),
		},
	
		-- Progress bar
		npprogress = {
			position = LAYOUT_NONE,
			x = coverSize + math.floor(100 * screenWidth/1920),
			y = TITLE_HEIGHT + (screenHeight - TITLE_HEIGHT - coverSize) / 2 + coverSize * 5 / 6,
			padding = { 0, 10, 0, 0 },
			order = { "elapsed", "slider", "remain" },
			elapsed = {
				w = math.floor(100 * screenWidth/1920),
				align = 'left',
				padding = { 0, 0, 4, 10 },
				font = _boldfont(math.ceil(28 * screenWidth/1920)),
				fg = { 0xe7,0xe7, 0xe7 },
				sh = { 0x37, 0x37, 0x37 },
			},
			remain = {
				w = math.floor(100 * screenWidth/1920),
				align = 'right',
				padding = { 4, 0, 0, 10 },
				font = _boldfont(math.ceil(28 * screenWidth/1920)),
				fg = { 0xe7,0xe7, 0xe7 },
				sh = { 0x37, 0x37, 0x37 },
			},
			elapsedSmall = {
				w = math.floor(100 * screenWidth/1920),
				align = 'left',
				padding = { 0, 0, 4, 20 },
				font = _boldfont(math.ceil(28 * screenWidth/1920)),
				fg = { 0xe7,0xe7, 0xe7 },
				sh = { 0x37, 0x37, 0x37 },
			},
			remainSmall = {
				w = math.floor(100 * screenWidth/1920),
				align = 'right',
				padding = { 4, 0, 0, 20 },
				font = _boldfont(math.ceil(28 * screenWidth/1920)),
				fg = { 0xe7,0xe7, 0xe7 },
				sh = { 0x37, 0x37, 0x37 },
			},
			npprogressB = {
				w = screenWidth - _tracklayout.x - math.floor(250 * screenWidth/1920),
				h = 50,
				padding     = { 0, 0, 0, 0 },
				position = LAYOUT_SOUTH,
				horizontal = 1,
				bgImg = _songProgressBackground,
				img = _songProgressBar,
			},
		},
	
		-- special style for when there shouldn't be a progress bar (e.g., internet radio streams)
		npprogressNB = {
			order = { "elapsed" },
			position = LAYOUT_NONE,
			x = coverSize + math.floor(100 * screenWidth/1920),
			y = TITLE_HEIGHT + (screenHeight - TITLE_HEIGHT - coverSize) / 2 + coverSize * 5 / 6,
			elapsed = {
				w = math.floor(100 * screenWidth/1920),
				align = "left",
				padding = { 0, 0, 4, 10 },
				font = _boldfont(math.ceil(28 * screenWidth/1920)),
				fg = { 0xe7, 0xe7, 0xe7 },
				sh = { 0x37, 0x37, 0x37 },
			},
		},

	})

	-- sliders
	s.nowplaying.npprogress.npprogressB_disabled = _uses(s.nowplaying.npprogress.npprogressB, {
		img = _songProgressBarDisabled,
	})

	-- pressed styles
	s.nowplaying.title.pressed = _uses(s.nowplaying.title, {
		text = {
			fg = { 0xB3, 0xB3, 0xB3 },
			sh = { },
			bgImg = pressedTitlebarButtonBox,
		},
		lbutton = {
			bgImg = pressedTitlebarButtonBox,
		},
		rbutton = {
			bgImg = pressedTitlebarButtonBox,
		},
	})

	s.nowplaying.pressed = s.nowplaying
	s.nowplaying.nptitle.pressed = _uses(s.nowplaying.nptitle)
	s.nowplaying.npalbumgroup.pressed = _uses(s.nowplaying.npalbumgroup)
	s.nowplaying.npartistgroup.pressed = _uses(s.nowplaying.npartistgroup)
	s.nowplaying.npartwork.pressed = s.nowplaying.npartwork

	s.nowplaying.npcontrols.pressed = {
		hidden = 1,
	}

	
	-- Visualizer: Container with titlebar, progressbar and controls.
	--  The space between title and controls is used for the visualizer.
	s.nowplaying_visualizer_common = _uses(s.nowplaying, {
		npartwork = { hidden = 1 },
	})

	s.nowplaying_visualizer_common.npprogress.npprogressB_disabled = s.nowplaying_visualizer_common.npprogress.npprogressB

	-- Visualizer: Spectrum Visualizer
	s.nowplaying_spectrum_text = _uses(s.nowplaying_visualizer_common, {
		npvisu = {
			hidden = 0,
			position = LAYOUT_NONE,
			x = math.floor(50 * screenWidth/1920),
			y = TITLE_HEIGHT + (screenHeight - TITLE_HEIGHT - coverSize) / 2 + coverSize * 6 / 6 - coverSize,
			align = "center",
			w = coverSize,
			h = coverSize,
			border = { 0, 0, 0, 0 },
			padding = { 0, 0, 0, 0 },
			bgImg = _progressBackground,

			spectrum = {
				position = LAYOUT_NONE,
				x = 0,
				y = 0,
				w = coverSize,
				h = coverSize,
				border = { 0, 0, 0, 0 },
				padding = { 0, 0, 0, 0 },

				bg = { 0x00, 0x00, 0x00, 0x00 },

				barColor = { 0x14, 0xbc, 0xbc, 0xff },
				capColor = { 0xb4, 0x56, 0xa1, 0xff },

				isMono = 0,				-- 0 / 1

				capHeight = { 4, 4 },			-- >= 0
				capSpace = { 4, 4 },			-- >= 0
				channelFlipped = { 0, 1 },		-- 0 / 1
				barsInBin = { 2, 2 },			-- > 1
				barWidth = { 1, 1 },			-- > 1
				barSpace = { 3, 3 },			-- >= 0
				binSpace = { 6, 6 },			-- >= 0
				clipSubbands = { 1, 1 },		-- 0 / 1
			}
		},
	})

	s.brightness_group = {
		order = {  'down', 'div1', 'slider', 'div2', 'up' },
		position = LAYOUT_SOUTH,
		h = 56,
		w = WH_FILL,
		bgImg = sliderBackground,

		div1 = _uses(_transportControlBorder),
		div2 = _uses(_transportControlBorder),

		down   = _uses(_transportControlButton, {
			w = 56,
			h = 56,
			img = _loadImage(self, "Icons/icon_toolbar_brightness_down.png"),
		}),
		up   = _uses(_transportControlButton, {
			w = 56,
			h = 56,
			img = _loadImage(self, "Icons/icon_toolbar_brightness_up.png"),
		}),
	}
	s.brightness_group.pressed = {
		down = _uses(s.brightness_group.down, { bgImg = sliderButtonPressed }),
		up   = _uses(s.brightness_group.up, { bgImg = sliderButtonPressed }),
	}

	s.brightness_slider = {
		w = WH_FILL,
		border = { 5, 12, 5, 0 },
		padding = { 6, 0, 6, 0 },
		position = LAYOUT_SOUTH,
		horizontal = 1,
		bgImg = _volumeSliderBackground,
		img = _volumeSliderBar,
		pillImg = _volumeSliderPill,
	}

	s.settings_slider_group = _uses(s.brightness_group, {
		down = {
			img = _loadImage(self, "Icons/icon_toolbar_minus.png"),
		},
		up = {
			img = _loadImage(self, "Icons/icon_toolbar_plus.png"),
		},
	})

	s.settings_slider = _uses(s.brightness_slider, {
	})
	s.settings_slider_group.pressed = {
		down = _uses(s.settings_slider_group.down, { 
			bgImg = sliderButtonPressed,
			img = _loadImage(self, "Icons/icon_toolbar_minus_dis.png"),
		}),
		up = _uses(s.settings_slider_group.up, { 
			bgImg = sliderButtonPressed,
			img = _loadImage(self, "Icons/icon_toolbar_plus_dis.png"),
		}),
	}

	s.settings_volume_group = _uses(s.brightness_group, {
		down = {
			img = _loadImage(self, "Icons/icon_toolbar_vol_down.png"),
		},
		up = {
			img = _loadImage(self, "Icons/icon_toolbar_vol_up.png"),
		},
	})
	s.settings_volume_group.pressed = {
		down = _uses(s.settings_volume_group.down, { 
			bgImg = sliderButtonPressed,
			img = _loadImage(self, "Icons/icon_toolbar_vol_down_dis.png"),
		}),
		up = _uses(s.settings_volume_group.up, { 
			bgImg = sliderButtonPressed,
			img = _loadImage(self, "Icons/icon_toolbar_vol_up_dis.png"),
		}),
	}

	s.debug_canvas = {
		zOrder = 9999
	}

	s.demo_text = {
		font = _boldfont(18),
		position = LAYOUT_SOUTH,
		w = screenWidth,
		h = 50,
		align = 'center',
		padding = { 6, 0, 6, 10 },
		fg = TEXT_COLOR,
		sh = TEXT_SH_COLOR,
	}


end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

