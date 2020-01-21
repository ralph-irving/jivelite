
--[[
=head1 NAME

applets.QVGA240squareSkin.QVGA240squareSkinApplet - The skin for a 240x240 display, such as the Pirate Audio boards for the Raspberry Pi

=head1 DESCRIPTION

This applet implements the skin for a 240x240 display, such as the Pirate Audio boards for the Raspberry Pi

=head1 FUNCTIONS

Applet related methods are described in L<jive.Applet>.

=cut
--]]

--created by cloning the QVGAlandscape skin, and modifying a few width-related parameters, as denoted by --240 comments

-- stuff we use
local ipairs, pairs, setmetatable, type, package, tostring = ipairs, pairs, setmetatable, type, package, tostring

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
local System                 = require("jive.System")

local table                  = require("jive.utils.table")
local debug                  = require("jive.utils.debug")
local autotable              = require("jive.utils.autotable")

local log                    = require("jive.utils.log").logger("applet.QVGA240squareSkin")

local QVGAbaseSkinApplet     = require("applets.QVGAbaseSkin.QVGAbaseSkinApplet")

local LAYER_FRAME            = jive.ui.LAYER_FRAME
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
oo.class(_M, QVGAbaseSkinApplet)


function init(self)
	self.images = {}
end


function param(self)
	return {
		THUMB_SIZE = 41,
		THUMB_SIZE_MENU = 40,
		POPUP_THUMB_SIZE = 120,
		NOWPLAYING_MENU = true,
		-- NOWPLAYING_TRACKINFO_LINES used in assisting scroll behavior animation on NP
                -- 3 is for a three line track, artist, and album (e.g., SBtouch)
                -- 2 is for a two line track, artist+album (e.g., SBradio, SBcontroller)
                NOWPLAYING_TRACKINFO_LINES = 2,
		nowPlayingScreenStyles = { 
			{ 
				style = 'nowplaying',
--240				artworkSize = '320x320',
				artworkSize = '240x240',
				text = self:string('LARGE_ART'),
			 },
			{
				style = 'nowplaying_small_art',
				artworkSize = '143x143',
				text = self:string('SMALL_ART'),
			},
		},
        }
end

-- skin
-- The meta arranges for this to be called to skin Jive.
function skin(self, s, reload, useDefaultSize)
	

	local screenWidth, screenHeight = Framework:getScreenSize()
	local imgpath = 'applets/QVGA240squareSkin/images/'
	local baseImgpath = 'applets/QVGAbaseSkin/images/'

--240
--[[	if useDefaultSize or screenWidth < 320 or screenHeight < 240 then
                screenWidth = 320
                screenHeight = 240
    end
--]]
    if useDefaultSize or screenWidth < 240 or screenHeight < 240 then
            screenWidth = 240
            screenHeight = 240
    end

        Framework:setVideoMode(screenWidth, screenHeight, 16, jiveMain:isFullscreen())

	--init lastInputType so selected item style is not shown on skin load
	Framework.mostRecentInputType = "scroll"

	-- almost all styles come directly from QVGAbaseSkinApplet
	QVGAbaseSkinApplet.skin(self, s, reload, useDefaultSize)

	-- c is for constants
	local c = s.CONSTANTS

	-- styles specific to the square QVGA skin
	s.img.scrollBackground =
                Tile:loadVTiles({
                                        imgpath .. "Scroll_Bar/scrollbar_bkgrd_t.png",
                                        imgpath .. "Scroll_Bar/scrollbar_bkgrd.png",
                                        imgpath .. "Scroll_Bar/scrollbar_bkgrd_b.png",
                                })

	s.img.scrollBar =
                Tile:loadVTiles({
                                        imgpath .. "Scroll_Bar/scrollbar_body_t.png",
                                        imgpath .. "Scroll_Bar/scrollbar_body.png",
                                        imgpath .. "Scroll_Bar/scrollbar_body_b.png",
                               })

        s.scrollbar = {
                w          = 20,
		h          = c.LANDSCAPE_LINE_ITEM_HEIGHT * 4 - 8,
                border     = { 0, 4, 0, 0},  -- bug in jive_menu, makes it so bottom and right values are ignored
                horizontal = 0,
                bgImg      = s.img.scrollBackground,
                img        = s.img.scrollBar,
                layer      = LAYER_CONTENT_ON_STAGE,
        }

	s.img.progressBackground = Tile:loadImage(imgpath .. "Alerts/alert_progress_bar_bkgrd.png")
	s.img.progressBar = Tile:loadHTiles({
                nil,
                imgpath .. "Alerts/alert_progress_bar_body.png",
        })

	s.track_list.menu.scrollbar = _uses(s.scrollbar, {
		h = 41 * 4 - 8,
	})
	-- software update window
	s.update_popup = _uses(s.popup)

	s.update_popup.text = {
                w = WH_FILL,
                h = (c.POPUP_TEXT_SIZE_1 + 8 ) * 2,
                position = LAYOUT_NORTH,
                border = { 0, 14, 0, 0 },
                padding = { 12, 0, 12, 0 },
                align = "center",
                font = _font(c.POPUP_TEXT_SIZE_1),
                lineHeight = c.POPUP_TEXT_SIZE_1 + 8,
                fg = c.TEXT_COLOR,
                sh = c.TEXT_SH_COLOR,
        }

        s.update_popup.subtext = {
                w = WH_FILL,
                -- note this is a hack as the height and padding push
                -- the content out of the widget bounding box.
                h = 30,
                padding = { 0, 0, 0, 36 },
                font = _boldfont(c.UPDATE_SUBTEXT_SIZE),
                fg = c.TEXT_COLOR,
                sh = TEXT_SH_COLOR,
                align = "bottom",
                position = LAYOUT_SOUTH,
        }
	s.update_popup.progress = {
                border = { 12, 0, 12, 12 },
                --padding = { 0, 0, 0, 24 },
                position = LAYOUT_SOUTH,
                horizontal = 1,
                bgImg = s.img.progressBackground,
                img = s.img.progressBar,
        }
    
--240
    --toast popup with icon only
    s.toast_popup_icon.x = 54
    s.toast_popup_icon.y = 54

	local NP_ARTISTALBUM_FONT_SIZE = 18
	local NP_TRACK_FONT_SIZE = 21

	local controlHeight   = 38
	local controlWidth    = 45
	local volumeBarWidth  = 150
	local buttonPadding   = 0
	local NP_TITLE_HEIGHT = 31
	local NP_TRACKINFO_RIGHT_PADDING = 40

	local _tracklayout = {
		position = LAYOUT_NORTH,
		w = WH_FILL,
		align = "left",
		lineHeight = NP_TRACK_FONT_SIZE,
		fg = { 0xe7, 0xe7, 0xe7 },
	}

	s.nowplaying = _uses(s.window, {
		bgImg = Tile:fillColor(0x000000ff),
		title = {
			zOrder = 9,
			h = 60,
			text = {
				hidden = 1,
			},
		},
		-- Song metadata
		nptitle = {
			zOrder = 10,
			order = { 'nptrack', 'xofy' },
			position   = _tracklayout.position,
			nptrack =  {
				padding    = { 10, 10, 2, 0 },
				w          = WH_FILL,
				align      = _tracklayout.align,
				lineHeight = _tracklayout.lineHeight,
				fg         = _tracklayout.fg,
				font       = _boldfont(NP_TRACK_FONT_SIZE), 
			},
			xofy = {
				padding    = { 0, 10, 10, 0 },
				position   = _tracklayout.position,
				w          = 50,
				align      = 'right',
				fg         = _tracklayout.fg,
				font       = _font(14), 
			},
			xofySmall = {
				padding    = { 0, 10, 10, 0 },
				position   = _tracklayout.position,
				w          = 50,
				align      = 'right',
				fg         = _tracklayout.fg,
				font       = _font(10), 
			},
		},
		npartistalbum  = {
			zOrder = 10,
			position   = _tracklayout.position,
			w          = _tracklayout.w,
			align      = _tracklayout.align,
			lineHeight = _tracklayout.lineHeight,
			fg         = { 0xb3, 0xb3, 0xb3 },
			padding    = { 10, NP_TRACK_FONT_SIZE + 14, 10, 0 },
			font       = _font(NP_ARTISTALBUM_FONT_SIZE),
		},
		nptrack       = { hidden = 1},
		npalbumgroup  = { hidden = 1},
		npartistgroup = { hidden = 1},
		npalbum       = { hidden = 1},
		npartist      = { hidden = 1},
		npvisu        = { hidden = 1},
	
		-- cover art
		npartwork = {
			position = LAYOUT_NORTH,
			w = WH_FILL,
			align = "center",
			artwork = {
				zOrder = 1,
				w = WH_FILL,
				align = "center",
				img = false,
			},
		},
	
		--transport controls
		npcontrols = { hidden = 1 },
	
		-- Progress bar
		npprogress = {
			zOrder = 10,
			position = LAYOUT_NORTH,
			padding = { 0, 0, 0, 0 },
			border = { 0, 59, 0, 0 },
			w = WH_FILL,
			order = { "slider" },
			npprogressB = {
				w = screenWidth,
				align = 'center',
				horizontal = 1,
				bgImg = s.img.songProgressBackground,
				img = s.img.songProgressBar,
				h = 15,
				padding = { 0, 0, 0, 15 },
			}
		},
	
		-- special style for when there shouldn't be a progress bar (e.g., internet radio streams)
		npprogressNB = {
			hidden = 1,
		},
	
	})

        s.nowplaying.npprogress.npprogressB_disabled = _uses(s.nowplaying.npprogress.npprogressB)

	--FIXME: Bug 15030, need way to cycle through NP views on Baby/Controller
	s.nowplaying_small_art = _uses(s.nowplaying, {
		title = {
			h = 60,
		},
		bgImg = false,
		npartwork = {
			position = LAYOUT_NORTH,
			artwork = {
				padding = { 0, 66, 0, 0 },
			},
		},
	})
	s.nowplaying.pressed = s.nowplaying
	s.nowplaying_small_art.pressed = s.nowplaying_small_art

	-- line in window is the same as nowplaying but with transparent background
	s.linein = _uses(s.nowplaying, {
		bgImg = false,
	})

	-- sliders
	s.npvolumeB = { hidden = 1 }
	s.npvolumeB_disabled = { hidden = 1 }

	s.icon_photo_loading = _uses(s._icon, {
		img = _loadImage(self, "Icons/image_viewer_loading.png"),
		padding = { 5, 5, 0, 5 }
	})

end


function free(self)
	local desktop = not System:isHardware()
	if desktop then
		log:warn("reload parent")

		package.loaded["applets.QVGAbaseSkin.QVGAbaseSkinApplet"] = nil
		QVGAbaseSkinApplet     = require("applets.QVGAbaseSkin.QVGAbaseSkinApplet")
	end
        return true
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

