
--[[
=head1 NAME

applets.QVGAportraitSkin.QVGAportraitSkinApplet - The skin for the Squeezebox Controller

=head1 DESCRIPTION

This applet implements the skin for the Squeezebox Controller

=head1 FUNCTIONS

Applet related methods are described in L<jive.Applet>.

=cut
--]]


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

local log                    = require("jive.utils.log").logger("applet.QVGAportraitSkin")

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
	-- not yet
	--QVGAbaseSkinApplet.init(self)
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
				artworkSize = '240x240',
				text = self:string('LARGE_ART'),
			 },
			{
				style = 'nowplaying_small_art',
				artworkSize = '200x200',
				text = self:string('SMALL_ART'),
			},
		},
        }
end

-- skin
-- The meta arranges for this to be called to skin Jive.
function skin(self, s, reload, useDefaultSize)
	

	local screenWidth, screenHeight = Framework:getScreenSize()
	local imgpath = 'applets/QVGAportraitSkin/images/'
	local baseImgpath = 'applets/QVGAbaseSkin/images/'

	if useDefaultSize or screenWidth < 240 or screenHeight < 320 then
                screenWidth = 240
                screenHeight = 320
        end

        Framework:setVideoMode(screenWidth, screenHeight, 16, jiveMain:isFullscreen())

	--init lastInputType so selected item style is not shown on skin load
	Framework.mostRecentInputType = "scroll"

	QVGAbaseSkinApplet.skin(self, s, reload, useDefaultSize)

	-- c is for constants
	local c = s.CONSTANTS

	-- styles specific to the landscape QVGA skin
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
                w          = 16,
		h          = c.PORTRAIT_LINE_ITEM_HEIGHT * 6 - 6,
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

	-- misc layout tweaks from base for portrait
	s.title.h = 38
	s.menu.border = { 0, 38, 0, 0 }
	s.icon_software_update.padding     = { 0, 22, 0, 0 }
	s.icon_connecting.padding          = { 0, 52, 0, 0 }
	s.icon_connected.padding           = { 0, 52, 0, 0 }
	s.icon_restart.padding             = { 0, 52, 0, 0 }
	s.icon_power.padding               = { 0, 47, 0, 0 }
	s.icon_battery_low.padding         = { 0, 42, 0, 0 }
	s.waiting_popup.text.padding       = { 0, 42, 0, 0 }
	s.waiting_popup.subtext.padding    = { 0, 0, 0, 46 }
	s.alarm_time.font = _font(72)

	s.toast_popup_mixed.text.font = _boldfont(14)
	s.toast_popup_mixed.subtext.font = _boldfont(14)

        -- slider popup (volume)
        s.slider_popup.x = 6
        s.slider_popup.y = 88
        s.slider_popup.w = screenWidth - 12
	
	-- titlebar has to be 55px to also have 80px menu items in portrait and have everything fit neatly
	s.multiline_text_list.title.h = 55
	s.multiline_text_list.menu.border = { 0, 56, 0, 24 }
	s.multiline_text_list.menu.scrollbar.h = c.MULTILINE_LINE_ITEM_HEIGHT * 3 - 8

	s.menu.itemHeight           = c.PORTRAIT_LINE_ITEM_HEIGHT
	s.icon_list.menu.itemHeight = c.PORTRAIT_LINE_ITEM_HEIGHT
	-- Bug 17104: change the padding in icon_list to 1 px top/bottom (landscape is 2 px top/bottom)
	s.icon_list.menu.item.padding = { 10, 1, 4, 1 }

	-- hide alarm icon on controller status bar, no room
	s.iconbar_group.order = { 'play', 'repeat_mode', 'shuffle', 'sleep', 'battery', 'wireless' } --'repeat' is a Lua reserved word
	s.button_sleep_ON.w = WH_FILL
	s.button_sleep_ON.align = 'right'
	s.button_sleep_OFF.w = WH_FILL
	s.button_sleep_OFF.align = 'right'

	s.track_list.menu.scrollbar = _uses(s.scrollbar, {
                h = 41 * 6 - 8,
        })

	-- track_list window needs to be mostly redefined for portrait
	s.track_list.title.h = 50
        s.track_list.title = _uses(s.title, {
                h = 50,
                order = { 'icon', 'text' },
		padding = { 10,0,0,0 },
                icon  = {
                        w = 49,
                        h = WH_FILL,
                },
                text = {
                        align = "top-left",
                        font = _font(18),
                        lineHeight = 19,
                        line = {
                                        {
                                                font = _boldfont(18),
                                                height = 20,
                                        },
                                        {
                                                font = _font(14),
                                                height = 16,
                                        }
                        },
                },
        })
        s.track_list.menu = _uses(s.menu, {
                itemHeight = 41,
                h = 6 * 41,
                border = { 0, 50, 0, 0 },
        })

	s.time_input_background_12h = {
		w = WH_FILL,
		h = screenHeight,
		position = LAYOUT_NONE,
		img = Tile:loadImage(baseImgpath .. "Multi_Character_Entry/port_multi_char_bkgrd_3c.png"),
		x = 0,
		y = c.TITLE_HEIGHT,
	}
	s.time_input_background_24h = {
		w = WH_FILL,
		h = screenHeight,
		position = LAYOUT_NONE,
		img = Tile:loadImage(baseImgpath .. "Multi_Character_Entry/port_multi_char_bkgrd_2c.png"),
		x = 0,
		y = c.TITLE_HEIGHT,
	}


	-- time input window
	s.input_time_12h = _uses(s.window, {
		bgImg = _timeInputBackground,
	})
	s.input_time_12h.hour = _uses(s.menu, {
		w = 60,
		h = screenHeight - 60,
		itemHeight = 50,
		position = LAYOUT_WEST,
		padding = 0,
		border = { 25, 36, 0, 24 },
		item = {
			bgImg = false,
			order = { 'text' },
			text = {
				align = 'right',
				font = _boldfont(21),
				padding = { 0, 0, 12, 0 },
				fg = { 0xb3, 0xb3, 0xb3 },
			},
		},
		selected = {
			item = {
				order = { 'text' },
				bgImg = Tile:loadImage(baseImgpath .. "Menu_Lists/menu_box_50.png"),
				text = {
					font = _boldfont(24),
					fg = { 0xe6, 0xe6, 0xe6 },
					align = 'right',
					padding = { 0, 0, 12, 0 },
				},
			},
		},
	})
	s.input_time_12h.minute = _uses(s.input_time_12h.hour, {
		border = { 25 + 65, 36, 0, 24 },
	})
	s.input_time_12h.ampm = _uses(s.input_time_12h.hour, {
		border = { 25 + 65 + 65, 36, 0, 24 },
		item = {
			text = {
				padding = { 0, 0, 8, 0 },
			},
		},
		selected = {
			item = {
				text = {
					padding = { 0, 0, 8, 0 },
				},
			},
		},
	})
	s.input_time_12h.hourUnselected = _uses(s.input_time_12h.hour, {
		item = {
			text = {
				fg = { 0x66, 0x66, 0x66 },
				font = _boldfont(21),
			},
		},
		selected = {
			item = {
				bgImg = false,
				text = {
					fg = { 0x66, 0x66, 0x66 },
					font = _boldfont(21),
				},
			},
		},
	})
	s.input_time_12h.minuteUnselected = _uses(s.input_time_12h.minute, {
		item = {
			text = {
				fg = { 0x66, 0x66, 0x66 },
				font = _boldfont(21),
			},
		},
		selected = {
			item = {
				bgImg = false,
				text = {
					fg = { 0x66, 0x66, 0x66 },
					font = _boldfont(21),
				},
			},
		},
	})
	s.input_time_12h.ampmUnselected = _uses(s.input_time_12h.ampm, {
		item = {
			text = {
				fg = { 0x66, 0x66, 0x66 },
				font = _boldfont(20),
			},
		},
		selected = {
			item = {
				bgImg = false,
				text = {
					fg = { 0x66, 0x66, 0x66 },
					font = _boldfont(20),
				},
			},
		},
	})

	s.input_time_24h = _uses(s.input_time_12h, {
		hour = {
			border = { 58, 36, 0, 24 },
		},
		minute = {
			border = { 58 + 65, 36 ,0, 24 },
		},
		hourUnselected = {
			border = { 58, 36, 0, 24 },
		},
		minuteUnselected = {
			border = { 58 + 65, 36 ,0, 24 },
		},
	})

	-- software update window
	s.update_popup = _uses(s.popup)

	s.update_popup.text = {
                w = WH_FILL,
                h = (c.POPUP_TEXT_SIZE_1 + 8 ) * 2,
                position = LAYOUT_NORTH,
                border = { 0, 28, 0, 0 },
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
                font = _boldfont(18),
                fg = c.TEXT_COLOR,
                sh = TEXT_SH_COLOR,
                align = "bottom",
                position = LAYOUT_SOUTH,
        }
	s.update_popup.progress = {
                border = { 12, 0, 12, 20 },
                position = LAYOUT_SOUTH,
                horizontal = 1,
                bgImg = s.img.progressBackground,
                img = s.img.progressBar,
        }

	-- toast popup with icon only
	s.toast_popup_icon.x = 54
	s.toast_popup_icon.y = 95

	-- context menu window
	s.context_menu.menu.h = c.CM_MENU_HEIGHT * 7
	s.context_menu.menu.scrollbar.h = c.CM_MENU_HEIGHT * 7 - 6
	s.context_menu.menu.scrollbar.border = { 0, 4, 0, 4 }
	s.context_menu.multiline_text.lineHeight = 21

	local NP_ARTISTALBUM_FONT_SIZE = 15
	local NP_TRACK_FONT_SIZE = 21

	local controlHeight   = 38
	local controlWidth    = 45
	local volumeBarWidth  = 150
	local buttonPadding   = 0
	local NP_TITLE_HEIGHT = 31
	local NP_TRACKINFO_RIGHT_PADDING = 8

	local _tracklayout = {
		border = 0,
		position = LAYOUT_NORTH,
		w = WH_FILL,
		align = "left",
		lineHeight = NP_TRACK_FONT_SIZE,
		fg = { 0xe7, 0xe7, 0xe7 },
	}

	local _iconbarBorder = { 3, 0, 3, 0 }

	s._button_playmode.border               = { 6, 0, 3, 0 }
	s.button_playmode_OFF.border            = s._button_playmode.border
	s.button_playmode_STOP.border           = s._button_playmode.border
	s.button_playmode_PLAY.border           = s._button_playmode.border
	s.button_playmode_PAUSE.border          = s._button_playmode.border 

	s._button_repeat.border                 = _iconbarBorder 
	s.button_repeat_OFF.border              = s._button_repeat.border
	s.button_repeat_0.border                = s._button_repeat.border
	s.button_repeat_1.border                = s._button_repeat.border
	s.button_repeat_2.border                = s._button_repeat.border

	s._button_shuffle.border                = _iconbarBorder
	s.button_shuffle_OFF.border             = s._button_shuffle.border
	s.button_shuffle_0.border               = s._button_shuffle.border
	s.button_shuffle_1.border               = s._button_shuffle.border
	s.button_shuffle_2.border               = s._button_shuffle.border

	s.button_sleep_ON.border		= { 6, 0, 3, 0 }
	s.button_sleep_OFF.border		= s.button_sleep_ON.border

	s._button_battery.border                = _iconbarBorder
	s.button_battery_AC.border              = s._button_battery.border
	s.button_battery_CHARGING.border        = s._button_battery.border
	s.button_battery_0.border               = s._button_battery.border
	s.button_battery_1.border               = s._button_battery.border
	s.button_battery_2.border               = s._button_battery.border
	s.button_battery_3.border               = s._button_battery.border
	s.button_battery_4.border               = s._button_battery.border
	s.button_battery_NONE.border            = s._button_battery.border

	s._button_wireless.border               = { 3, 0, 6, 0 }
	s.button_wireless_1.border              = s._button_wireless.border
	s.button_wireless_2.border              = s._button_wireless.border
	s.button_wireless_3.border              = s._button_wireless.border
	s.button_wireless_4.border              = s._button_wireless.border
	s.button_wireless_ERROR.border          = s._button_wireless.border
	s.button_wireless_SERVERERROR.border    = s._button_wireless.border
	s.button_wireless_NONE.border           = s._button_wireless.border

	s.nowplaying = _uses(s.window, {
		bgImg = Tile:fillColor(0x000000ff),
		title = {
			zOrder = 9,
			h = 79,
			text = {
				hidden = 1,
			},
		},
		-- Song metadata
		nptitle = {
			order = { 'nptrack', 'xofy' },
			border     = _tracklayout.border,
			position   = _tracklayout.position,
			zOrder = 10,
			nptrack =  {
				w          = _tracklayout.w,
				align      = _tracklayout.align,
				lineHeight = _tracklayout.lineHeight,
				fg         = _tracklayout.fg,
				padding    = { 10, 10, 2, 0 },
				font       = _boldfont(NP_TRACK_FONT_SIZE), 
			},
			xofy =  {
				w          = 48,
				align      = 'right',
				fg         = _tracklayout.fg,
				padding    = { 0, 10, NP_TRACKINFO_RIGHT_PADDING, 0 },
				font       = _font(14), 
			},
			xofySmall =  {
				w          = 48,
				align      = 'right',
				fg         = _tracklayout.fg,
				padding    = { 0, 10, NP_TRACKINFO_RIGHT_PADDING, 0 },
				font       = _font(10), 
			},
		},
		npartistalbum  = {
			zOrder = 10,
			border     = _tracklayout.border,
			position   = _tracklayout.position,
			w          = _tracklayout.w,
			align      = _tracklayout.align,
			lineHeight = _tracklayout.lineHeight,
			fg = { 0xb3, 0xb3, 0xb3 },
			padding    = { 10, NP_TRACK_FONT_SIZE + 18, 10, 0 },
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
			position = LAYOUT_WEST,
			zOrder = 1,
			w = WH_FILL,
			align = "center",
			artwork = {
				w = WH_FILL,
				align = "center",
				padding = { 0, 79, 0, 0 },
				img = false,
			},
		},
	
		--transport controls
		npcontrols = { hidden = 1 },
	
		-- Progress bar
		npprogress = {
			zOrder = 10,
			position = LAYOUT_NORTH,
			padding = { 10, 0, 10, 0 },
			border = { 0, 63, 0, 0 },
			w = WH_FILL,
			order = { 'elapsed', 'slider', 'remain' },
			elapsed = {
				zOrder = 10,
				font = _boldfont(12),
				fg = { 0xb3, 0xb3, 0xb3 },
			},
			remain = {
				zOrder = 10,
				font = _boldfont(12),
				fg = { 0xb3, 0xb3, 0xb3 },
			},
			elapsedSmall = {
				zOrder = 10,
				font = _boldfont(9),
				fg = { 0xb3, 0xb3, 0xb3 },
			},
			remainSmall = {
				zOrder = 10,
				font = _boldfont(9),
				fg = { 0xb3, 0xb3, 0xb3 },
			},
			npprogressB = {
				w = WH_FILL,
				align = 'center',
				border = { 10, 0, 10, 0 },
				horizontal = 1,
				bgImg = s.img.songProgressBackground,
				img = s.img.songProgressBar,
				h = 15,
			},
		},
	
		-- special style for when there shouldn't be a progress bar (e.g., internet radio streams)
		npprogressNB = {
			zOrder = 10,
			position = LAYOUT_NORTH,
			padding = { 10, 0, 0, 0 },
			border = { 0, 63, 0, 0 },
			align = 'center',
			w = WH_FILL,
			order = { 'elapsed' },
			elapsed = {
				w = WH_FILL,
				align = 'left',
				font = _boldfont(12),
				fg = { 0xb3, 0xb3, 0xb3 },
			},
			
		},
	
	})

	s.nowplaying.npprogressNB.elapsedSmall = s.nowplaying.npprogressNB.elapsed

	s.nowplaying_small_art = _uses(s.nowplaying, {
		bgImg = false,
		npartwork = {
			position = LAYOUT_NORTH,
			artwork = {
				padding = { 0, 88, 0, 0 },
			},
		},
	})

	s.nowplaying.pressed = s.nowplaying
	s.nowplaying_small_art.pressed = s.nowplaying_small_art

	-- sliders
        s.nowplaying.npprogress.npprogressB_disabled = _uses(s.nowplaying.npprogress.npprogressB)

	s.npvolumeB = { hidden = 1 }
	s.npvolumeB_disabled = { hidden = 1 }

	-- line in is the same as s.nowplaying but with transparent background
	s.linein = _uses(s.nowplaying, {
		bgImg = false,
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

