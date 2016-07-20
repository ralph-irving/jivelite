
--[[
=head1 NAME

applets.WQVGAlargeSkin.WQVGAlargeSkinApplet - skin for large print and 480x272 resolution

=head1 DESCRIPTION

This applet implements the large print skin for 480x272 resolution

=head1 FUNCTIONS

Applet related methods are described in L<jive.Applet>. 
SqueezeboxSkin overrides the following methods:

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

local log                    = require("jive.utils.log").logger("applet.WQVGAlargeSkin")

local EVENT_ACTION           = jive.ui.EVENT_ACTION
local EVENT_CONSUME          = jive.ui.EVENT_CONSUME
local EVENT_WINDOW_POP       = jive.ui.EVENT_WINDOW_POP
local LAYER_FRAME            = jive.ui.LAYER_FRAME
local LAYER_TITLE            = jive.ui.LAYER_TITLE
local LAYER_CONTENT_ON_STAGE = jive.ui.LAYER_CONTENT_ON_STAGE

local LAYOUT_NORTH           = jive.ui.LAYOUT_NORTH
local LAYOUT_EAST            = jive.ui.LAYOUT_EAST
local LAYOUT_SOUTH           = jive.ui.LAYOUT_SOUTH
local LAYOUT_WEST            = jive.ui.LAYOUT_WEST
local LAYOUT_CENTER          = jive.ui.LAYOUT_CENTER
local LAYOUT_NONE            = jive.ui.LAYOUT_NONE

local WH_FILL                = jive.ui.WH_FILL

local jiveMain               = jiveMain
local appletManager          = appletManager


module(..., Framework.constants)
oo.class(_M, Applet)


-- Define useful variables for this skin
local imgpath = "applets/WQVGAsmallSkin/images/"
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


function param(self)
	return {
		THUMB_SIZE = 64,
		THUMB_SIZE_MENU = 64,
		POPUP_THUMB_SIZE = 120,
		NOWPLAYING_MENU = true,
		-- NOWPLAYING_TRACKINFO_LINES used in assisting scroll behavior animation on NP
                -- 3 is for a three line track, artist, and album (e.g., SBtouch)
                -- 2 is for a two line track, artist+album (e.g., SBradio, SBcontroller)
                NOWPLAYING_TRACKINFO_LINES = 3,
		nowPlayingScreenStyles = { 
			{ 
				style = 'nowplaying' ,
				artworkSize = '190x190',
				text = self:string("ART_AND_TEXT"),
			},
			{
				style = 'nowplaying_art_only',
				artworkSize = '470x262',
				suppressTitlebar = 1,
				text = self:string("ART_ONLY"),
			},
			{
				style = 'nowplaying_text_only',
				artworkSize = '190x190',
				text = self:string("TEXT_ONLY"),
			},
			{
				style = 'nowplaying_spectrum_text',
				artworkSize = '190x190',
				localPlayerOnly = 1,
				text = self:string("SPECTRUM_ANALYZER"),
			},
			{
				style = 'nowplaying_vuanalog_text',
				artworkSize = '190x190',
				localPlayerOnly = 1,
				text = self:string("ANALOG_VU_METER"),
			},
		},
		radialClock = {
			hourTickPath     = 'applets/WQVGAsmallSkin/images/Clocks/Radial/radial_ticks_hr_on.png',
			minuteTickPath   = 'applets/WQVGAsmallSkin/images/Clocks/Radial/radial_ticks_min_on.png',
		},
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
function skin(self, s)
	Framework:setVideoMode(480, 272, 0, false)

	local screenWidth, screenHeight = Framework:getScreenSize()

	--init lastInputType so selected item style is not shown on skin load
	Framework.mostRecentInputType = "mouse"

	-- skin
	local thisSkin = 'remote'
	local skinSuffix = "_" .. thisSkin .. ".png"

	-- Images and Tiles
	local inputTitleBox           = _loadImageTile(self,  imgpath .. "Titlebar/titlebar.png" )
	local backButton              = _loadImageTile(self,  imgpath .. "Icons/icon_back_button_tb.png")
	local helpButton              = _loadImageTile(self,  imgpath .. "Icons/icon_help_button_tb.png")
	local nowPlayingButton        = _loadImageTile(self,  imgpath .. "Icons/icon_nplay_button_tb.png")
	local powerButton             = _loadImageTile(self,  imgpath .. "Icons/icon_power_button_tb.png")
	local sliderBackground        = _loadImageTile(self,  imgpath .. "Touch_Toolbar/toolbar_lrg.png")
        local touchToolbarKeyDivider  = _loadImageTile(self,  imgpath .. "Touch_Toolbar/toolbar_divider.png")

	local blackBackground   = Tile:fillColor(0x000000ff)
	local nocturneWallpaper = _loadImageTile(self, "applets/SetupWallpaper/wallpaper/fab4_nocturne.png")

	local deleteKeyBackground     = _loadImageTile(self,  imgpath .. "Buttons/button_delete_text_entry.png")
	local deleteKeyPressedBackground = _loadImageTile(self,  imgpath .. "Buttons/button_delete_text_entry_press.png")
	local helpTextBackground  = _loadImageTile(self, imgpath .. "Titlebar/tbar_dropdwn_bkrgd.png")

	local threeItemSelectionBox   = _loadHTile(self, {
		nil,
		 imgpath .. "3_line_lists/menu_sel_box_3line.png",
		 imgpath .. "3_line_lists/menu_sel_box_3line_r.png",
	})

	local threeItemCMSelectionBox   = _loadTile(self, {
		imgpath .. "Popup_Menu/button_cm.png",
		imgpath .. "Popup_Menu/button_cm_tl.png",
		imgpath .. "Popup_Menu/button_cm_t.png",
		imgpath .. "Popup_Menu/button_cm_tr.png",
		imgpath .. "Popup_Menu/button_cm_r.png",
		imgpath .. "Popup_Menu/button_cm_br.png",
		imgpath .. "Popup_Menu/button_cm_b.png",
		imgpath .. "Popup_Menu/button_cm_bl.png",
		imgpath .. "Popup_Menu/button_cm_l.png",
	})

	local threeItemCMPressedBox   = _loadTile(self, {
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

	local threeItemBox             = _loadHTile(self, {
		 imgpath .. "3_line_lists/rem_3line_divider_l.png",
		 imgpath .. "3_line_lists/rem_3line_divider.png",
		 imgpath .. "3_line_lists/rem_3line_divider_r.png",
        })

	local threeItemPressedBox     = _loadImageTile(self, imgpath .. "3_line_lists/menu_sel_box_3item_press.png" )

	local titleBox                =
		_loadTile(self, {
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

	local textinputBackground = _loadImageTile(self, imgpath .. "Text_Entry/Classic_10ft/text_entry_bkgrd_whole.png")

	local pressedTitlebarButtonBox =
		_loadTile(self, {
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

	local titlebarButtonBox =
		_loadTile(self, {
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

	local popupBox = 
		_loadTile(self, {
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

        local contextMenuBox =
		_loadTile(self, {
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


	local scrollBackground = 
		_loadVTile(self, {
					imgpath .. "Scroll_Bar/scrollbar_bkgrd_t.png",
					imgpath .. "Scroll_Bar/scrollbar_bkgrd.png",
					imgpath .. "Scroll_Bar/scrollbar_bkgrd_b.png",
			       })

	local scrollBar = 
		_loadVTile(self, {
					imgpath .. "Scroll_Bar/scrollbar_body_t.png",
					imgpath .. "Scroll_Bar/scrollbar_body.png",
					imgpath .. "Scroll_Bar/scrollbar_body_b.png",
			       })

	local _volumeSliderBackground = _loadHTile(self, {
		imgpath .. "Touch_Toolbar/tch_volumebar_bkgrd_l.png",
		imgpath .. "Touch_Toolbar/tch_volumebar_bkgrd.png",
		imgpath .. "Touch_Toolbar/tch_volumebar_bkgrd_r.png",
	})

        local _popupSliderBar = _loadHTile(self, {
                imgpath .. "Touch_Toolbar/tch_volumebar_fill_l.png",
                imgpath .. "Touch_Toolbar/tch_volumebar_fill.png",
                imgpath .. "Touch_Toolbar/tch_volumebar_fill_r.png",
        })

	local _scannerSliderBar = _loadHTile(self, {
		nil,
		nil,
		imgpath .. "Song_Progress_Bar/SP_Bar_Remote/rem_slider.png",
	})

	local _scannerSliderBackground = _loadHTile(self, {
		imgpath .. "Song_Progress_Bar/SP_Bar_Remote/rem_sliderbar_bkgrd_l.png",
		imgpath .. "Song_Progress_Bar/SP_Bar_Remote/rem_sliderbar_bkgrd.png",
		imgpath .. "Song_Progress_Bar/SP_Bar_Remote/rem_sliderbar_bkgrd_r.png",
	})

	local volumeBar        = _loadImageTile(self, imgpath .. "Touch_Toolbar/tch_volumebar_fill.png")
	local volumeBackground = _loadImageTile(self, imgpath .. "Touch_Toolbar/tch_volumebar_whole.png")

	local popupBackground  = _loadImageTile(self, imgpath .. "Alerts/popup_fullscreen_100.png")

	local textinputCursor     = _loadImageTile(self, imgpath .. "Text_Entry/Classic_10ft/text_bar_vert_fill.png")
	local textinputWheel      = _loadImageTile(self, imgpath .. "Text_Entry/Classic_10ft/text_bar_vert.png")
        local textinputRightArrow = _loadImageTile(self, imgpath .. "Icons/sel_right_textentry.png")

	local THUMB_SIZE = self:param().THUMB_SIZE
	
	local CHECK_PADDING  = { 2, 0, 6, 0 }
	local CHECKBOX_RADIO_PADDING  = { 2, 0, 0, 0 }

	local MENU_ITEM_ICON_PADDING = { 0, 0, 8, 0 }
	local MENU_PLAYLISTITEM_TEXT_PADDING = { 16, 1, 9, 1 }

	local MENU_CURRENTALBUM_TEXT_PADDING = { 6, 20, 0, 10 }
	local TEXTAREA_PADDING = { 13, 8, 8, 0 }

	local WHITE = { 0xE7, 0xE7, 0xE7 }
	local OFFWHITE = { 0xdc, 0xdc, 0xdc }
	local BLACK = { 0x00, 0x00, 0x00 }
	local TEAL = { 0, 0xbe, 0xbe }
	local NONE = { }

	local TEXT_COLOR = WHITE
	local TEXT_SH_COLOR = NONE

	local TITLE_HEIGHT = 55
	local CM_MENU_HEIGHT = 72
	local TITLE_FONT_SIZE = 30
	local ALBUMMENU_FONT_SIZE = 34
	local ALBUMMENU_SMALL_FONT_SIZE = 18
	local ALBUMMENU_SELECTED_FONT_SIZE = 40
	local ALBUMMENU_SELECTED_SMALL_FONT_SIZE = 22
	local TEXTMENU_FONT_SIZE = 30
	local TEXTMENU_SELECTED_FONT_SIZE = 40
	local POPUP_TEXT_SIZE_1 = 34
	local POPUP_TEXT_SIZE_2 = 26
	local TRACK_FONT_SIZE = 18
	local TEXTAREA_FONT_SIZE = 24
	local CENTERED_TEXTAREA_FONT_SIZE = 24

	local HELP_FONT_SIZE = 28
	local UPDATE_SUBTEXT_SIZE = 20

	local ITEM_ICON_ALIGN   = 'center'
	local ITEM_LEFT_PADDING = 12
	local THREE_ITEM_HEIGHT = 72
	local FIVE_ITEM_HEIGHT = 43
	local TITLE_BUTTON_WIDTH = 76

	local smallSpinny = {
		img = _loadImage(self, "Alerts/wifi_connecting_med.png"),
		frameRate = 8,
		frameWidth = 32,
		padding = 0,
		h = WH_FILL,
	}
	local largeSpinny = {
		img = _loadImage(self, "Alerts/wifi_connecting.png"),
		position = LAYOUT_CENTER,
		w = WH_FILL,
		align = "center",
		frameRate = 8,
		frameWidth = 120,
		padding = { 0, 0, 0, 10 }
	}
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
		img = _loadImage(self, "Icons/selection_add_3line_on.png"),
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
		imgpath .. "NowPlaying/np_progressbar_slider_10ft.png",
        })

        local _settingsSliderBackground = _loadHTile(self, {
                imgpath .. "Touch_Toolbar/tch_volumebar_bkgrd_l.png",
                imgpath .. "Touch_Toolbar/tch_volumebar_bkgrd.png",
                imgpath .. "Touch_Toolbar/tch_volumebar_bkgrd_r.png",
        })

        local _settingsSliderBar = _loadHTile(self, {
               imgpath .. "UNOFFICIAL/tch_volumebar_fill_l.png",
               imgpath .. "UNOFFICIAL/tch_volumebar_fill.png",
               imgpath .. "UNOFFICIAL/tch_volumebar_fill_r.png",
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
		bgImg = titleBox,
		order = { "text" },
		text = {
			w = WH_FILL,
			h = WH_FILL,
			align = "center",
			font = _boldfont(TITLE_FONT_SIZE),
			fg = WHITE,
			sh = NONE,
		}
	}
	s.title.textButton = s.title.text
	s.title.pressed = {}
	s.title.pressed.textButton = s.title.textButton

	s.text_block_black = {
		bgImg = Tile:fillColor(0x000000ff),
		position = LAYOUT_NORTH,
		h = 100,
		order = { 'text' },
		text = {
			w = WH_FILL,
			h = 100,
			padding = { 10, 120, 10, 0 },
			align = "center",
			font = _font(100),
			fg = WHITE,
			sh = NONE,
		},
	}

	s.menu = {
		position = LAYOUT_CENTER,
		padding = { 0, 0, 0, 0 },
		itemHeight = THREE_ITEM_HEIGHT,
		fg = {0xbb, 0xbb, 0xbb },
		font = _boldfont(160),
	}

	s.menu_hidden = _uses(s.menu, {
		hidden = 1,
	})

	s.item = {
		order = { "text", "arrow" },
		padding = { ITEM_LEFT_PADDING, 0, 5, 0 },
		bgImg = threeItemBox,
		text = {
			padding = { 0, 10, 2, 0 },
			align = "left",
			w = WH_FILL,
			h = WH_FILL,
			font = _boldfont(TEXTMENU_FONT_SIZE),
			fg = OFFWHITE,
			sh = NONE,
		},
		icon = {
			padding = MENU_ITEM_ICON_PADDING,
			align = 'center',
		},
		arrow = {
			w = 37,
	      		align = ITEM_ICON_ALIGN,
	      		img = _loadImage(self, "Icons/selection_right_3line_off.png"),
			padding = { 0, 0, 0, 0 },
		},
	}

	s.item_play = _uses(s.item, { 
		order = { 'icon', 'text' },
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
        s.checkbox.img_on = _loadImage(self, "Icons/checkbox_on_3line.png")
        s.checkbox.img_off = _loadImage(self, "Icons/checkbox_off_3line.png")


        -- Radio button
        s.radio = {}
	s.radio.align = 'center'
	s.radio.padding = CHECKBOX_RADIO_PADDING
	s.radio.h = WH_FILL
        s.radio.img_on = _loadImage(self, "Icons/radiobutton_on_3line.png")
        s.radio.img_off = _loadImage(self, "Icons/radiobutton_off_3line.png")

	s.item_choice = _uses(s.item, {
		order  = { 'text', 'check' },
		choice = {
			h = WH_FILL,
			padding = CHECKBOX_RADIO_PADDING,
			align = 'right',
			font = _boldfont(TEXTMENU_FONT_SIZE),
			fg = OFFWHITE,
			sh = NONE,
		},
	})
	s.item_checked = _uses(s.item, {
		order = { "text", "check", "arrow" },
		check = {
			align = ITEM_ICON_ALIGN,
			padding = CHECK_PADDING,
			img = _loadImage(self, "Icons/icon_check_3line.png")
	      	}
	})

	s.item_info = _uses(s.item, {
		order = { 'text' },
		padding = { ITEM_LEFT_PADDING, 0, 0, 0 },
		text = {
			align = "top-left",
			w = WH_FILL,
			h = WH_FILL,
			padding = { 0, 12, 0, 12 },
			font = _font(34),
			line = {
				{
					font = _font(18),
					height = 18,
				},
				{
					font = _boldfont(34),
					height = 34,
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

	local selectedTextBlock = {
		fg = WHITE,
		sh = NONE,
		font = _boldfont(TEXTMENU_SELECTED_FONT_SIZE),
		padding = { 0, 0, 2, 0 },
	}
	local itemInfoSelectedTextBlock = _uses(s.item_info.text, {
		font = _font(40),
		line = {
			{
				font = _font(20),
				height = 20,
			},
			{
				font = _boldfont(40),
				height = 40,
			},
		},
	})

	s.selected = {
		item               = _uses(s.item, {
			bgImg = threeItemSelectionBox,
			text = selectedTextBlock,
			arrow = {
	      			img = _loadImage(self, "Icons/selection_right_3line_on.png"),
			},
		}),
		item_play           = _uses(s.item_play, {
			text   = selectedTextBlock,
			bgImg  = threeItemSelectionBox
		}),
		item_add            = _uses(s.item_add, {
			text = selectedTextBlock,
			bgImg = threeItemSelectionBox
		}),
		item_checked        = _uses(s.item_checked, {
			text = selectedTextBlock,
			bgImg = threeItemSelectionBox,
			arrow = {
	      			img = _loadImage(self, "Icons/selection_right_3line_on.png"),
			},
		}),
		item_no_arrow        = _uses(s.item_no_arrow, {
			text = selectedTextBlock,
			bgImg = threeItemSelectionBox
		}),
		item_checked_no_arrow = _uses(s.item_checked_no_arrow, {
			text = selectedTextBlock,
			bgImg = threeItemSelectionBox
		}),
		item_choice         = _uses(s.item_choice, {
			text = selectedTextBlock,
			bgImg = threeItemSelectionBox
		}),
		item_info  = _uses(s.item_info, {
			text = itemInfoSelectedTextBlock,
			bgImg = threeItemSelectionBox,
			arrow = {
	      			img = _loadImage(self, "Icons/selection_right_3line_on.png"),
			},
		}),
	}

	s.pressed = s.selected

	s.locked = {
		item = _uses(s.pressed.item, {
			arrow = smallSpinny
		}),
		item_checked = _uses(s.pressed.item_checked, {
			arrow = smallSpinny
		}),
		item_play = _uses(s.pressed.item_play, {
			order = { 'icon', 'text', 'arrow' },
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
		padding = { ITEM_LEFT_PADDING, 4, 8, 0},
		font = _font(30),
		lineHeight = 32,
		fg = WHITE,
		sh = NONE,
		align = "top-left",
	}

	s.scrollbar = {
		w = 42,
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
		lineHeight = TEXTAREA_FONT_SIZE + 10,
		fg = WHITE,
		sh = NONE,
		align = "left",
	}

	s.multiline_text = s.text

	s.slider = {
		border = 10,
                position = LAYOUT_CENTER,
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
		h                = WH_FILL,
		border           = { 8, 0, 8, 0 },
		padding          = { 12, 0, 6, 0 },
		align            = 'center',
		font             = _boldfont(64),
		cursorFont       = _boldfont(72),
		wheelFont        = _boldfont(34),
		charHeight       = 72,
		wheelCharHeight  = 34,
		fg               = BLACK,
		wh               = { 0x55, 0x55, 0x55 },
		bgImg            = textinputBackground,
		cursorImg        = textinputCursor,
                cursorColor      = WHITE,
		enterImg         = textinputRightArrow,
		wheelImg         = textinputWheel,
		charOffsetY      = 20,
		wheelCharOffsetY = 4,
	}

	-- keyboard
	s.keyboard = {
		hidden = 1,
	}

	local _timeFirstColumnX12h = 130
	local _timeFirstColumnX24h = 168

	local TIMEINPUT_TOP_PADDING = 57
	local TIMEINPUT_ITEM_PADDING = { 0, 10, 16, 0 }
	local TIMEINPUT_AMPM_PADDING = { 0, 12, 14, 0 }

	s.time_input_background_12h = {
		w = WH_FILL,
		position = LAYOUT_NONE,
		img = _loadImage(self, "Multi_Character_Entry/rem_multi_char_bkgrd_3c_10ft.png"),
		x = 0,
		y = TITLE_HEIGHT,
		h = screenHeight,
	}

	s.time_input_background_24h = {
		w = WH_FILL,
		position = LAYOUT_NONE,
		img = _loadImage(self, "Multi_Character_Entry/rem_multi_char_bkgrd_2c_10ft.png"),
		x = 0,
		y = TITLE_HEIGHT,
		h = screenHeight,
	}

	-- time input window
	s.input_time_12h = _uses(s.window)

	s.input_time_12h.hour = _uses(s.menu, {
		w = 75,
		h = screenHeight - 47,
		itemHeight = FIVE_ITEM_HEIGHT,
		position = LAYOUT_WEST,
		padding = 0,
		border = { _timeFirstColumnX12h, TIMEINPUT_TOP_PADDING, 0, 0 },
		item = {
			bgImg = false,
			order = { 'text' },
			text = {
				align = 'right',
				font = _boldfont(30),
				padding = TIMEINPUT_ITEM_PADDING,
				fg = { 0xb3, 0xb3, 0xb3 },
				sh = { },
			},
		},
		selected = {
			item = {
				order = { 'text' },
				img = _loadImage(self, "Multi_Character_Entry/menu_box_fixed_72.png"),
				text = {
					font = _boldfont(30),
					fg = { 0xe6, 0xe6, 0xe6 },
					sh = { },
					align = 'right',
					padding = TIMEINPUT_ITEM_PADDING,
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
					padding = TIMEINPUT_ITEM_PADDING,
				},
			},
		},
	})
	s.input_time_12h.minute = _uses(s.input_time_12h.hour, {
		border = { _timeFirstColumnX12h + 75, TIMEINPUT_TOP_PADDING, 0, 0 },
	})
	s.input_time_12h.ampm = _uses(s.input_time_12h.hour, {
		border = { _timeFirstColumnX12h + 75 + 75, TIMEINPUT_TOP_PADDING, 0, 0 },
		item = {
			text = {
				padding = TIMEINPUT_AMPM_PADDING,
				font = _boldfont(26),
			},
		},
		selected = {
			item = {
				img = _loadImage(self, "Multi_Character_Entry/menu_box_fixed_72.png"),
				text = {
					padding = TIMEINPUT_AMPM_PADDING,
					font = _boldfont(26),
				},
			},
		},
		pressed = {
			item = {
				text = {
					padding = TIMEINPUT_AMPM_PADDING,
					font = _boldfont(26),
				},
			},
		},
	})

	local unselectedParamTable = {
		item = {
			text = {
				fg = { 0x66, 0x66, 0x66 },
			},
		},
		selected = {
			item = {
				bgImg = false,
				text = {
					fg = { 0x66, 0x66, 0x66 },
				},
			},
		},
	}
	s.input_time_12h.hourUnselected = _uses(s.input_time_12h.hour, unselectedParamTable)
	s.input_time_12h.minuteUnselected = _uses(s.input_time_12h.minute, unselectedParamTable)
	s.input_time_12h.ampmUnselected = _uses(s.input_time_12h.ampm, unselectedParamTable)

	s.input_time_24h = _uses(s.input_time_12h, {
		hour = {
			border = { _timeFirstColumnX24h, TIMEINPUT_TOP_PADDING, 0, 0 },
		},
		minute = {
			border = { _timeFirstColumnX24h + 75, TIMEINPUT_TOP_PADDING, 0, 0 },
		},
		hourUnselected = {
			border = { _timeFirstColumnX24h, TIMEINPUT_TOP_PADDING, 0, 0 },
		},
		minuteUnselected = {
			border = { _timeFirstColumnX24h + 75, TIMEINPUT_TOP_PADDING, 0, 0 },
		},
	})
	-- one set for buttons, one for spacers

--------- WINDOW STYLES ---------
	--
	-- These styles override the default styles for a specific window

	-- typical text list window
	s.text_list = _uses(s.window)
	s.text_only = _uses(s.text_list)

	s.text_list.title = _uses(s.title, {
		text = {
			line = {
				{
					font = _boldfont(30),
					height = 32,
				},
				{
					font = _font(18),
					fg = { 0xB3, 0xB3, 0xB3 },
				},
			},
		},
	})
	s.text_list.title.textButton = s.text_list.title.text

	s.text_list.title.pressed = {}
	s.text_list.title.pressed.textButton = s.text_list.title.textButton

	-- choose player window. identical to text_list on all windows except WQVGAlarge, which needs to show the icon
	s.choose_player = _uses(s.text_list, {
		menu = {
			item = {
				order = { 'icon', 'text', 'arrow' },
			},
			item_checked = {
				order = { 'icon', 'text', 'check', 'arrow' },
			},
			selected = {
				item = {
					order = { 'icon', 'text', 'arrow' },
				},
				item_checked = {
					order = { 'icon', 'text', 'check', 'arrow' },
				},
			},
			locked = {
				item = {
					order = { 'icon', 'text', 'arrow' },
				},
				item_checked = {
					order = { 'icon', 'text', 'check', 'arrow' },
				},
			},
			locked = {
				item = {
					order = { 'icon', 'text', 'arrow' },
				},
				item_checked = {
					order = { 'icon', 'text', 'check', 'arrow' },
				},
			},
		},
	})

	s.multiline_text_list = s.text_list

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
			fg = WHITE,
			sh = NONE,
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
			fg = WHITE,
			sh = NONE,
		},
	})

	s.waiting_popup.subtext_connected = _uses(s.waiting_popup.subtext, {
		fg = TEAL,
	})

	s.black_popup = _uses(s.waiting_popup)
	s.black_popup.title = _uses(s.title, {
		bgImg = false,
		order = { },
	})

	-- input window (including keyboard)
	s.input = _uses(s.window)

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
			fg = WHITE,
			sh = NONE,		
		},
		subtext = {
			w = WH_FILL,
			-- note this is a hack as the height and padding push
			-- the content out of the widget bounding box.
			h = 30,
			padding = { 0, 0, 0, 28 },
			font = _boldfont(UPDATE_SUBTEXT_SIZE),
			fg = WHITE,
			sh = NONE,
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

	s.home_menu = _uses(s.text_list)

	-- icon_list window
	s.icon_list = _uses(s.window, {
		menu = {
			item = {
				order = { "icon", "text", "arrow" },
				padding = { ITEM_LEFT_PADDING, 0, 0, 0 },
				text = {
					w = WH_FILL,
					h = WH_FILL,
					align = 'left',
					padding = { 0, 5, 0, 0, },
					line = {
						{
							font = _boldfont(ALBUMMENU_FONT_SIZE),
							height = 42,
						},
						{
							font = _font(ALBUMMENU_SMALL_FONT_SIZE),
						},
					},
					fg = OFFWHITE,
					sh = NONE,
				},
				icon = {
					h = THUMB_SIZE,
					padding = MENU_ITEM_ICON_PADDING,
					align = 'center',
				},
				arrow = _uses(s.item.arrow),
			},
		},
	})

	s.icon_list.menu.item_checked = _uses(s.icon_list.menu.item, {
		order = { 'icon', 'text', 'check', 'arrow' },
		check = {
			align = ITEM_ICON_ALIGN,
			padding = CHECK_PADDING,
			img = _loadImage(self, "Icons/icon_check_5line.png")
		},
	})
	s.icon_list.menu.item_play = _uses(s.icon_list.menu.item, { 
		order = { 'icon', 'text' },
		arrow = { img = false },
	})
	s.icon_list.menu.albumcurrent = _uses(s.icon_list.menu.item_play, {
		arrow = {
			img = _loadImage(self, "Icons/icon_nplay_3line_off.png"),
		},
	})
	s.icon_list.menu.item_add  = _uses(s.icon_list.menu.item, { 
		arrow = addArrow,
	})
	s.icon_list.menu.item_no_arrow = _uses(s.icon_list.menu.item, {
		order = { 'icon', 'text' },
	})
	s.icon_list.menu.item_checked_no_arrow = _uses(s.icon_list.menu.item_checked, {
		order = { 'icon', 'text', 'check' },
	})

	s.icon_list.menu.selected = {
                item               = _uses(s.icon_list.menu.item, {
			bgImg = threeItemSelectionBox
		}),
                albumcurrent       = _uses(s.icon_list.menu.albumcurrent, {
			bgImg = threeItemSelectionBox,
			arrow = {
				img = _loadImage(self, "Icons/icon_nplay_3line_sel.png"),
			},
		}),
                item_checked        = _uses(s.icon_list.menu.item_checked, {
			bgImg = threeItemSelectionBox
		}),
		item_play           = _uses(s.icon_list.menu.item_play, {
			bgImg = threeItemSelectionBox
		}),
		item_add            = _uses(s.icon_list.menu.item_add, {
			bgImg = threeItemSelectionBox
		}),
		item_no_arrow        = _uses(s.icon_list.menu.item_no_arrow, {
			bgImg = threeItemSelectionBox
		}),
		item_checked_no_arrow = _uses(s.icon_list.menu.item_checked_no_arrow, {
			bgImg = threeItemSelectionBox
		}),
        }
	s.icon_list.menu.pressed = s.icon_list.menu.selected

	s.icon_list.menu.locked = {
		item = _uses(s.icon_list.menu.pressed.item, {
			arrow = smallSpinny
		}),
		item_checked = _uses(s.icon_list.menu.pressed.item_checked, {
			arrow = smallSpinny
		}),
		item_play = _uses(s.icon_list.menu.pressed.item_play, {
			arrow = smallSpinny
		}),
		item_add = _uses(s.icon_list.menu.pressed.item_add, {
			arrow = smallSpinny
		}),
	}


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
		lineHeight = TEXTAREA_FONT_SIZE + 4,
		fg = WHITE,
		sh = NONE,
		padding = { 18, 18, 10, 0},
	}

	-- help window (likely the same as information)
	s.help_info = _uses(s.information)


	--track_list window
	-- XXXX todo
	-- identical to text_list but has icon in upper left of titlebar
	s.track_list = _uses(s.text_list)

	s.track_list.title = _uses(s.title, {
		order = { 'lbutton', 'icon', 'text', 'rbutton' },
		icon  = {
			w = THUMB_SIZE,
			h = WH_FILL,
			padding = { 10, 1, 8, 1 },
		},
	})

	--playlist window
	-- identical to icon_list but with some different formatting on the text
	s.play_list = _uses(s.icon_list, {
		menu = {
			item = {
				text = {
					padding = MENU_PLAYLISTITEM_TEXT_PADDING,
					line = {
						{
							font = _boldfont(ALBUMMENU_FONT_SIZE),
							height = ALBUMMENU_FONT_SIZE
						},
						{
							height = ALBUMMENU_SMALL_FONT_SIZE + 2
						},
						{
							height = ALBUMMENU_SMALL_FONT_SIZE + 2
						},
					},	
				},
			},
		},
	})
	s.play_list.menu.item_checked = _uses(s.play_list.menu.item, {
		order = { 'icon', 'text', 'check', 'arrow' },
		check = {
			align = ITEM_ICON_ALIGN,
			padding = CHECK_PADDING,
			img = _loadImage(self, "Icons/icon_check_5line.png")
		},
	})
	s.play_list.menu.selected = {
                item = _uses(s.play_list.menu.item, {
			bgImg = threeItemSelectionBox
		}),
                item_checked = _uses(s.play_list.menu.item_checked, {
			bgImg = threeItemSelectionBox
		}),
        }
	s.play_list.menu.pressed = s.play_list.menu.selected
	s.play_list.menu.locked = {
		item = _uses(s.play_list.menu.pressed.item, {
			arrow = smallSpinny
		}),
		item_checked = _uses(s.play_list.menu.pressed.item_checked, {
			arrow = smallSpinny
		}),
	}


	-- toast_popup popup (is now text only)
	s.toast_popup_textarea = {
		padding = { 8, 8, 8, 8 } ,
		align = 'left',
		w = WH_FILL,
		h = WH_FILL,
		font = _boldfont(30),
		fg = WHITE,
		sh = { },
        }

	-- toast_popup popup with art and text
	s.toast_popup = {
		x = 5,
		y = screenHeight/2 - 126/2,
		w = screenWidth - 10,
		h = 126,
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
			text = s.toast_popup_textarea,
		}
	})
	-- toast popup with icon only
	s.toast_popup_icon = _uses(s.toast_popup, {
                w = 190,
                h = 178,
                x = 145,
                y = 72,
                position = LAYOUT_NONE,
		group = {
			padding = 0,
			order = { 'icon' },
			border = { 22, 22, 0, 0 },
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
			padding = { 8, 16, 8, 0 },
			align = 'top',
			w = WH_FILL,
			h = WH_FILL,
			font = _boldfont(26),
			fg = WHITE,
			sh = {},
		},
		subtext = {
			position = LAYOUT_NORTH,
			padding = { 8, 168, 8, 0 },
			align = 'top',
			w = WH_FILL,
			h = WH_FILL,
			font = _boldfont(32),
			fg = WHITE,
			sh = {},
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
		y = 21,
		w = screenWidth - 16,
		h = screenHeight - 42,
		bgImg = contextMenuBox,
		layer = LAYER_TITLE,

		title = {
			hidden = 1,
		},

        multiline_text = {
            w = WH_FILL,
            h = 223,
            padding = { 18, 20, 14, 18 },
            border = { 0, 0, 6, 15 },
            fg = { 0xe6, 0xe6, 0xe6 },
            sh = { },
            align = "top-left",
            scrollbar = {
                h = 210,
                border = {0, 10, 2, 10},
            },
        },
        
		menu = {
			border = { 7, 7, 7, 0 },
			padding = { 0, 0, 0, 100 },
			scrollbar = {
				h = CM_MENU_HEIGHT * 3 - 8, 
				border = { 0, 4, 2, 4 },
			},
			item = {
				h = CM_MENU_HEIGHT,
				order = { "text", "arrow" },
				padding = { ITEM_LEFT_PADDING, 0, 12, 0 },
				bgImg = false,
				text = {
					w = WH_FILL,
					h = WH_FILL,
					padding = { 0, 8, 0, 8 },
					align = 'left',
					font = _font(ALBUMMENU_SMALL_FONT_SIZE),
					line = {
						{
							font = _boldfont(ALBUMMENU_FONT_SIZE),
							height = 42,
						},
						{
							font = _font(ALBUMMENU_SMALL_FONT_SIZE),
						},
					},
					fg = TEXT_COLOR,
					sh = TEXT_SH_COLOR,
				},
				arrow = _uses(s.item.arrow),
			},
			selected = {
				item = {
					bgImg = threeItemCMSelectionBox,
					order = { "text", "arrow" },
					padding = { ITEM_LEFT_PADDING, 0, 12, 0 },
					text = {
						w = WH_FILL,
						h = WH_FILL,
						align = 'left',
						padding = { 0, 12, 0, 12 },
						font = _font(ALBUMMENU_SELECTED_SMALL_FONT_SIZE),
						line = {
							{
								font = _boldfont(ALBUMMENU_SELECTED_FONT_SIZE),
								height = 42,
							},
							{
								font = _font(ALBUMMENU_SELECTED_SMALL_FONT_SIZE),
							},
						},
						fg = TEXT_COLOR,
						sh = TEXT_SH_COLOR,
					},
					arrow = _uses(s.item.arrow, {
			      			img = _loadImage(self, "Icons/selection_right_3line_on.png"),
					}),
				},
			},

		},
	}
	
	s.context_menu.menu.item_play = _uses(s.context_menu.menu.item, {
		arrow = {img = playArrow.img},
	})
	s.context_menu.menu.selected.item_play = _uses(s.context_menu.menu.selected.item, {
		arrow = {img = playArrow.img},
	})

	s.context_menu.menu.item_insert = _uses(s.context_menu.menu.item, {
		arrow = {img = addArrow.img},
	})
	s.context_menu.menu.selected.item_insert = _uses(s.context_menu.menu.selected.item, {
		arrow = {img = addArrow.img},
	})

	s.context_menu.menu.item_add = _uses(s.context_menu.menu.item, {
		arrow = {img = addArrow.img},
	})
	s.context_menu.menu.selected.item_add = _uses(s.context_menu.menu.selected.item, {
		arrow = {img = addArrow.img},
	})

	s.context_menu.menu.item_playall = _uses(s.context_menu.menu.item, {
		arrow = {img = playArrow.img},
	})
	s.context_menu.menu.selected.item_playall = _uses(s.context_menu.menu.selected.item, {
		arrow = {img = playArrow.img},
	})

	s.context_menu.menu.item_fav = _uses(s.context_menu.menu.item, {
		arrow = {img = favItem.img},
	})
	s.context_menu.menu.selected.item_fav = _uses(s.context_menu.menu.selected.item, {
		arrow = {img = favItem.img},
	})

	s.context_menu.menu.item_no_arrow = _uses(s.context_menu.menu.item, {
		order = { 'text' },
	})
	s.context_menu.menu.selected.item_no_arrow = _uses(s.context_menu.menu.selected.item, {
		order = { 'text' },
	})

	s.context_menu.menu.item_fav = _uses(s.context_menu.menu.item, {
		arrow = {img = favItem.img},
	})
	s.context_menu.menu.selected.item_fav = _uses(s.context_menu.menu.selected.item, {
		arrow = {img = favItem.img},
	})

	s.context_menu.menu.item_no_arrow = _uses(s.context_menu.menu.item, {
		order = { 'text' },
	})
	s.context_menu.menu.selected.item_no_arrow = _uses(s.context_menu.menu.selected.item, {
		order = { 'text' },
	})

	s.context_menu.menu.pressed = _uses(s.context_menu.menu.selected, {
	})

	-- alarm popup
	s.alarm_header = {
		border = { 0, 4, 0, 0 },
		w = screenWidth - 16,
		align = 'center',
		layer = LAYER_TITLE,
		order = { 'time' },
	}

	s.alarm_time = {
		w = WH_FILL,
		fg = TEXT_COLOR,
		sh = TEXT_SH_COLOR,
		layer = LAYER_TITLE,
		align = "center",
		font = _boldfont(82),
		border = { 0, 2, 0, 0 },
	}
	s.preview_text = _uses(s.alarm_time, {
		font = _boldfont(TITLE_FONT_SIZE),
	})

	-- alarm menu window
	s.alarm_popup = {
		x = 8,
		y = 21,
		w = screenWidth - 16,
		h = screenHeight - 36,
		bgImg = contextMenuBox,
		layer = LAYER_TITLE,

		title = {
			hidden = 1,
		},

		menu = {
			border = { 7, 12, 7, 0 },
			padding = { 0, 0, 0, 100 },
			scrollbar = {
				h = CM_MENU_HEIGHT * 3 - 8, 
				border = { 0, 4, 2, 4 },
			},
			item = {
				h = CM_MENU_HEIGHT,
				order = { "icon", "text", "arrow" },
				padding = { ITEM_LEFT_PADDING, 0, 12, 0 },
				bgImg = false,
				text = {
					w = WH_FILL,
					h = WH_FILL,
					padding = { 0, 0, 0, 8 },
					align = 'left',
					font = _font(ALBUMMENU_SMALL_FONT_SIZE),
					line = {
						{
							font = _boldfont(ALBUMMENU_FONT_SIZE),
						},
						{
							font = _font(ALBUMMENU_SMALL_FONT_SIZE),
						},
					},
					fg = TEXT_COLOR,
					sh = TEXT_SH_COLOR,
				},
				icon = {
					h = THUMB_SIZE,
					padding = MENU_ITEM_ICON_PADDING,
					align = 'center',
				},
				arrow = _uses(s.item.arrow),
			},
			selected = {
				item = {
					bgImg = threeItemCMSelectionBox,
					order = { "icon", "text", "arrow" },
					padding = { ITEM_LEFT_PADDING, 0, 12, 0 },
					text = {
						w = WH_FILL,
						h = WH_FILL,
						align = 'left',
						padding = { 0, 0, 0, 12 },
						font = _font(ALBUMMENU_SELECTED_SMALL_FONT_SIZE),
						line = {
							{
								font = _boldfont(ALBUMMENU_SELECTED_FONT_SIZE),
							},
							{
								font = _font(ALBUMMENU_SELECTED_SMALL_FONT_SIZE),
							},
						},
						fg = TEXT_COLOR,
						sh = TEXT_SH_COLOR,
					},
					icon = {
						h = THUMB_SIZE,
						padding = MENU_ITEM_ICON_PADDING,
						align = 'center',
					},
					arrow = _uses(s.item.arrow, {
			      			img = _loadImage(self, "Icons/selection_right_3line_on.png"),
					}),
				},
			},
		}
	}
	
	-- slider popup (volume)
	s.slider_popup = {
		x = 50,
                y = screenHeight/2 - 100,
                w = screenWidth - 100,
                h = 200,
		position = LAYOUT_NONE,
		bgImg = popupBox,
		heading = {
			w = WH_FILL,
			border = 10,
			fg = WHITE,
			sh = {},
			font = _boldfont(32),
			align = "center",
			bgImg = false,
			padding = { 4, 16, 4, 0 },
		},
		slider_group = {
			w = WH_FILL,
			h = WH_FILL,
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
			align = "center",
                        w = screenWidth,
                        position = LAYOUT_CENTER,
                        align = "center",
                        h = screenHeight,
                        border = 0,
		},
	})


--------- SLIDERS ---------

	s.volume_slider = _uses(s.slider, {
		img = _popupSliderBar,
		bgImg = _volumeSliderBackground,
		border = 0,
	})

	s.scanner_slider = _uses(s.volume_slider, {
		img = _scannerSliderBar,
		bgImg = _scannerSliderBackground,
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


	local clearMask = Tile:fillColor(0x00000000)

	s.power_on_window =  _uses(s.window)
	s.power_on_window.maskImg = clearMask
	s.power_on_window.title = { -- borrowed from fab4 3ft skin until we get a style of our own
		h = 47,
		border = 0,
		position = LAYOUT_NORTH,
		bgImg = false,
		padding = { 0, 5, 0, 5 },
		order = { "lbutton", "text", "rbutton" },
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


	-- invisible button
	s.button_none = _uses(_button, {
		bgImg    = false,
		w = TITLE_BUTTON_WIDTH  - 12,
	})
	-- icon button factory
	local _titleButtonIcon = function(name, icon, attr)
		s[name] = _uses(_button)
		s.pressed[name] = _uses(_pressed_button)

		attr = {
			hidden = 0,
			img = icon
		}

		s[name].icon = _uses(_button.icon, attr)
		s[name].w = 65
		s.pressed[name].icon = _uses(_pressed_button.icon, attr)
		s.pressed[name].w = 65
	end

	_titleButtonIcon("button_power", powerButton)

	s.titleButton = { hidden = 1 }
	s.button_go_now_playing = _uses(s.titleButton)
	s.button_back = _uses(s.titleButton)
	s.button_help = _uses(s.titleButton)
	s.button_more_help = _uses(s.titleButton)

	s.button_back.padding = { 2, 0, 0, 2 }

	s.button_volume_min = {
		img = _loadImage(self, "Icons/icon_toolbar_vol_down.png"),
		border = { 5, 0, 5, 0 },
	}

	s.button_volume_max = {
		img = _loadImage(self, "Icons/icon_toolbar_vol_up.png"),
		border = { 5, 0, 5, 0 },
	}

	s.button_keyboard_back = {
		hidden = 1,
	}

	local _buttonicon = {
		h   = THUMB_SIZE,
		padding = MENU_ITEM_ICON_PADDING,
		align = 'center',
		img = false,
	}

	s.region_US = _uses(_buttonicon, { 
		img = _loadImage(self, "IconsResized/icon_region_americas" .. skinSuffix),
	})
	s.region_XX = _uses(_buttonicon, { 
		img = _loadImage(self, "IconsResized/icon_region_other" .. skinSuffix),
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
		border = { 22, 22, 0, 0 },
		h = WH_FILL,
		w = 146,
	}

	-- icon for albums with no artwork
	s.icon_no_artwork = {
		img = _loadImage(self, "IconsResized/icon_album_noart" .. skinSuffix ),
		h   = THUMB_SIZE,
		padding = MENU_ITEM_ICON_PADDING,
		align = 'center',
	}

	s.icon_connecting = _uses(_icon, {
		img = _loadImage(self, "Alerts/wifi_connecting.png"),
		frameRate = 8,
		frameWidth = 120,
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
	s.icon_popup_lineIn = _uses(_popupicon, {
		img = _loadImage(self, "IconsResized/icon_linein_134.png"),
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
	})
	s.icon_power = _uses(_icon, {
		img = _loadImage(self, "IconsResized/icon_restart" .. skinSuffix),
	})

	s.icon_locked = _uses(_icon, {
-- FIXME no asset for this (needed?)
--		img = _loadImage(self, "Alerts/popup_locked_icon.png"),
	})

	s.icon_alarm = _uses(_icon, {
-- FIXME no asset for this (needed?)
--		img = _loadImage(self, "Alerts/popup_alarm_icon.png"),
	})

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
		img = _loadImage(self, "IconsResized/icon_softsqueeze" .. skinSuffix),
	})
	s.player_fab4 = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_fab4" .. skinSuffix),
	})
	s.player_baby = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_baby" .. skinSuffix),
	})


	-- indicator icons, on right of menus
	local _indicator = {
		align = "center",
	}

	s.wirelessLevel1 = _uses(_indicator, {
		img = _loadImage(self, "Icons/icon_wireless_1_3line.png")
	})

	s.wirelessLevel2 = _uses(_indicator, {
		img = _loadImage(self, "Icons/icon_wireless_2_3line.png")
	})

	s.wirelessLevel3 = _uses(_indicator, {
		img = _loadImage(self, "Icons/icon_wireless_3_3line.png")
	})

	s.wirelessLevel4 = _uses(_indicator, {
		img = _loadImage(self, "Icons/icon_wireless_4_3line.png")
	})


--------- ICONBAR ---------

	s.iconbar_group = {
		hidden = 1,
	}

	-- time (hidden off screen)
	s.button_time = {
		hidden = 1,
	}



--------- NOW PLAYING ---------

	local NP_ARTISTALBUM_FONT_SIZE = 32
	local NP_TRACK_FONT_SIZE = 40


	-- Title
	s.ssnptitle = _uses(s.title, {
		rbutton  = {
			hidden = 1,
		}
	})

	local _tracklayout = {
		border = { 4, 0, 4, 0 },
		position = LAYOUT_NONE,
		x = 210,
		w = screenWidth - (210) - 10,
		align = "left",
		lineHeight = NP_TRACK_FONT_SIZE,
		fg = WHITE,
	}

	local controlHeight = 38
        local controlWidth = 45
        local volumeBarWidth = 150
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

	s.nowplaying = _uses(s.window, {
		title = _uses(s.title, {
			h = 39,
			text = {
				padding = { 10, 18, 0, 0 },
				font = _boldfont(18),
				align = 'left',
			},
			rbutton = {
				hidden = 1,
			},
		}),
		nptitle = {
			order = { 'nptrack' },
	                position   = _tracklayout.position,
			x          = _tracklayout.x,
			y          = 39 + 30,
			nptrack = {
				w          = _tracklayout.w,
				align      = _tracklayout.align,
				fg         = _tracklayout.fg,
				font       = _boldfont(NP_TRACK_FONT_SIZE),
				h          = 50,
			},
		},
		npartistgroup = {
			order = { 'npartist' },
	                position   = _tracklayout.position,
			x          = _tracklayout.x,
			y          = 39 + 40 + 43,
			npartist = {
				w          = _tracklayout.w,
				align      = _tracklayout.align,
				fg         = _tracklayout.fg,
		                font       = _font(NP_ARTISTALBUM_FONT_SIZE),
		                h          = 45,
			},

		},
		npalbumgroup = {
			order = { 'npalbum' },
	                position   = _tracklayout.position,
			x          = _tracklayout.x,
			y          = 39 + 40 + 43 + 41,
			npalbum = {
				w          = _tracklayout.w,
				align      = _tracklayout.align,
				fg         = _tracklayout.fg,
		                font       = _font(NP_ARTISTALBUM_FONT_SIZE),
		                h          = 45,
			},
		},
		npartistalbum = {
			hidden = 1,
		},
		npartwork = {
			w          = 190,
			border     = { 8, 45, 12, 5 },
			position   = LAYOUT_WEST,
			align      = "center",
			artwork    = {
				align = "center",
				padding = 0,
				img = false,
			},
		},

		npvisu = { hidden = 1 },

		npcontrols = {
			order = { 'rew', 'div1', 'play', 'div2', 'fwd', 'div3', 'repeatMode', 'div4', 'shuffleMode', 
					'div5', 'volDown', 'div6', 'volSlider', 'div7', 'volUp' },
			hidden = 1,
			div1           = { hidden = 1 },
			div2           = { hidden = 1 },
			div3           = { hidden = 1 },
			div4           = { hidden = 1 },
			div5           = { hidden = 1 },
			div6           = { hidden = 1 },
			div7           = { hidden = 1 },
			rew            = { hidden = 1 },
			play           = { hidden = 1 },
			pause          = { hidden = 1 },
			fwd            = { hidden = 1 },
			shuffleMode    = { hidden = 1 },
			shuffleOff     = { hidden = 1 },
			shuffleSong    = { hidden = 1 },
			shuffleAlbum   = { hidden = 1 },
			repeatMode     = { hidden = 1 },
			repeatOff      = { hidden = 1 },
			repeatPlaylist = { hidden = 1 },
			repeatSong     = { hidden = 1 },
			volDown        = { hidden = 1 },
			volUp          = { hidden = 1 },
			thumbsUp       = { hidden = 1 },
			thumbsDown     = { hidden = 1 },
			love           = { hidden = 1 },
			hate           = { hidden = 1 },
			fwdDisabled    = { hidden = 1 },
			rewDisabled    = { hidden = 1 },
		},

		npprogress = {
			bgImg = titleBox,
			h = 31,
			position = LAYOUT_SOUTH,
			padding  = { 0, 8, 0, 5 },
			order    = { "elapsed", "slider", "remain" },
			elapsed  = {
				w = 60,
				align = 'right',
				padding = { 8, 8, 0, 15 },
				font = _boldfont(18),
				fg = { 0xe7,0xe7, 0xe7 },
				sh = { 0x37, 0x37, 0x37 },
			},
			remain = {
				w = 60,
				align = 'left',
				padding = { 0, 8, 8, 15 },
				font = _boldfont(18),
				fg = { 0xe7,0xe7, 0xe7 },
				sh = { 0x37, 0x37, 0x37 },
			},
			elapsedSmall  = {
				w = 60,
				align = 'right',
				padding = { 8, 8, 0, 15 },
				font = _boldfont(12),
				fg = { 0xe7,0xe7, 0xe7 },
				sh = { 0x37, 0x37, 0x37 },
			},
			remainSmall = {
				w = 60,
				align = 'left',
				padding = { 0, 8, 8, 15 },
				font = _boldfont(12),
				fg = { 0xe7,0xe7, 0xe7 },
				sh = { 0x37, 0x37, 0x37 },
			},
			text = {
				w       = 60,
				align   = 'right',
				padding = { 0, 4, 0, 15 },
				font    = _boldfont(18),
				fg      = { 0xe7, 0xe7, 0xe7 },
				sh      = { 0x37, 0x37, 0x37 },
			},
			npprogressB = {
		                w          = WH_FILL,
				h          = 31,
				padding    = { 0, 0, 0, 18 },
				position   = LAYOUT_SOUTH,
				horizontal = 1,
				bgImg      = _songProgressBackground,
				img        = _songProgressBar,
			}

		},

		npprogressNB = {
			position = LAYOUT_SOUTH,
			align = 'center',
			padding = { 0, 0, 0, 18 },
                        order = { "elapsed" },
                        elapsed = {
                                w = WH_FILL,
                                align = "center",
                                padding = { 0, 0, 0, 5 },
                                font = _boldfont(18),
                                fg = { 0xe7, 0xe7, 0xe7 },
                                sh = { 0x37, 0x37, 0x37 },
                        },
                },
	})
 
	s.nowplaying.npprogressNB.elapsedSmall = s.nowplaying.npprogressNB.elapsed

	s.nowplaying.npprogress.npprogressB_disabled = _uses(s.nowplaying.npprogress.npprogressB)

	s.nowplaying_art_only = _uses(s.nowplaying, {

                bgImg            = blackBackground,
                title            = { hidden = 1 },
                nptitle          = { hidden = 1 },
                npcontrols       = { hidden = 1 },
                npprogress       = { hidden = 1 },
                npprogressNB     = { hidden = 1 },
                npartistgroup    = { hidden = 1 },
                npalbumgroup     = { hidden = 1 },

                npvisu = { hidden = 1 },

                npartwork = {
                        w = 480,
                        position = LAYOUT_CENTER,
                        align = "center",
                        h = 272,
                        border = 0,
                        padding = 5,
                        artwork = {
                                w = 480,
                                border = 0,
                                padding = 0,
                                img = false,
                        },
                },
        })
        s.nowplaying_art_only.pressed = s.nowplaying_art_only

	s.nowplaying_text_only = _uses(s.nowplaying, {
		nptitle = {
			x = 10,
			nptrack = {
				w = screenWidth - 20,
			},
		},
		npartistgroup = {
			x = 10,
			npartist = {
				w = screenWidth - 20,
			},

		},
		npalbumgroup = {
			x = 10,
			npalbum = {
				w = screenWidth - 20,
			},

		},

		npvisu = { hidden = 1 },

		npartwork = { hidden = 1 },
	})

	s.nowplaying.pressed = s.nowplaying
	s.nowplaying_art_only.pressed = s.nowplaying_art_only
	s.nowplaying_text_only.pressed = s.nowplaying_text_only
	s.nowplaying_text_only.nptitle.pressed = s.nowplaying_text_only.nptitle
	s.nowplaying_text_only.npartistgroup.pressed = s.nowplaying_text_only.npartistgroup
	s.nowplaying_text_only.npalbumgroup.pressed = s.nowplaying_text_only.npalbumgroup

	s.nowplaying.npartistgroup.pressed = s.nowplaying.npartistgroup
	s.nowplaying.npalbumgroup.pressed = s.nowplaying.npalbumgroup
	s.nowplaying.nptitle.pressed = s.nowplaying.nptitle

	-- Visualizer: Container with titlebar, progressbar and controls.
	--  The space between title and controls is used for the visualizer.
	s.nowplaying_visualizer_common = _uses(s.nowplaying, {
		bgImg = nocturneWallpaper,

		npartistgroup = { hidden = 1 },
		npalbumgroup = { hidden = 1 },
		npartwork = { hidden = 1 },

		title = _uses(s.title, {
			zOrder = 1,
			h = TITLE_HEIGHT,
			text = {
				-- Hack: text needs to be there to fill the space, but is not visible
				padding = { screenWidth, 0, 0, 0 }
			},
		}),

		-- Drawn over regular test between buttons
		nptitle = { 
			zOrder = 2,
			position = LAYOUT_NONE,
			x = 0,
			y = 0,
			w = screenWidth,
			h = TITLE_HEIGHT,
			border = { 0, 0 ,0, 0 },
			padding = { 10, 5, 10, 7 },
			nptrack = {
				w = screenWidth - 20,
				align = "center",
			},
		},

		npartistalbum = {
			hidden = 0,
			zOrder = 2,
			position = LAYOUT_NONE,
			x = 0,
			y = TITLE_HEIGHT,
			w = screenWidth,
			h = 38,
			bgImg = titleBox,
			align = "center",
			fg = { 0xb3, 0xb3, 0xb3 },
			padding = { 10, 0, 10, 5 },
			font = _font(NP_ARTISTALBUM_FONT_SIZE),
		},
	})

	-- Visualizer: Spectrum Visualizer
	s.nowplaying_spectrum_text = _uses(s.nowplaying_visualizer_common, {
		npvisu = {
			hidden = 0,
			position = LAYOUT_NONE,
			x = 0,
			y = 2 * TITLE_HEIGHT,
			w = 480,
			h = 272 - (2 * TITLE_HEIGHT + 4 + 33),
			border = { 0, 0, 0, 0 },
			padding = { 0, 0, 0, 0 },

			spectrum = {
				position = LAYOUT_NONE,
				x = 0,
				y = 2 * TITLE_HEIGHT,
				w = 480,
				h = 272 - (2 * TITLE_HEIGHT + 4 + 33),
				border = { 0, 0, 0, 0 },
				padding = { 0, 0, 0, 0 },

				bg = { 0x00, 0x00, 0x00, 0x00 },

				barColor = { 0x14, 0xbc, 0xbc, 0xff },
				capColor = { 0x74, 0x56, 0xa1, 0xff },

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
	s.nowplaying_spectrum_text.pressed = s.nowplaying_spectrum_text

	-- Visualizer: Analog VU Meter
	s.nowplaying_vuanalog_text = _uses(s.nowplaying_visualizer_common, {
		npvisu = {
			hidden = 0,
			position = LAYOUT_NONE,
			x = 0,
			y = TITLE_HEIGHT + 38,
			w = 480,
			h = 272 - (TITLE_HEIGHT + 34 + 38),
			border = { 0, 0, 0, 0 },
			padding = { 0, 0, 0, 0 },

			vumeter_analog = {
				position = LAYOUT_NONE,
				x = 0,
				y = TITLE_HEIGHT + 38,
				w = 480,
				h = 272 - (TITLE_HEIGHT + 34 + 38),
				border = { 0, 0, 0, 0 },
				padding = { 0, 0, 0, 0 },
				bgImg = _loadImage(self, "UNOFFICIAL/VUMeter/vu_analog_25seq_b.png"),
			}
		},
	})
	s.nowplaying_vuanalog_text.pressed = s.nowplaying_vuanalog_text

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

		down   = _uses(s.brightness_group.down, { bgImg = sliderButtonPressed }),
		up   = _uses(s.brightness_group.up, { bgImg = sliderButtonPressed }),
	}

	s.brightness_slider = {
		w = WH_FILL,
		border = { 5, 10, 5, 0 },
		padding = { 6, 0, 6, 0 },
                position = LAYOUT_SOUTH,
                horizontal = 1,
		bgImg = _settingsSliderBackground,
                img = _settingsSliderBar,
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


end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

