--[[
=head1 NAME

applets.PiGridSkin.PiGridSkinApplet

=head1 DESCRIPTION


This applet implements an 800x480 resolution skin with a grid layout.

It inherits most of its code from the JogglerSkin by 3guk, Tarkan Akdam and Justblair.

Version 1.1 (25th January 2017)
Michael Herger


=head1 FUNCTIONS

Applet related methods are described in L<jive.Applet>. 

=cut
--]]


-- stuff we use
local ipairs, pairs, setmetatable, type, tostring = ipairs, pairs, setmetatable, type, tostring

local oo                     = require("loop.simple")

local Applet                 = require("jive.Applet")
local Font                   = require("jive.ui.Font")
local Framework              = require("jive.ui.Framework")
local Surface                = require("jive.ui.Surface")
local Tile                   = require("jive.ui.Tile")

local table                  = require("jive.utils.table")
local debug                  = require("jive.utils.debug")
local autotable              = require("jive.utils.autotable")

local log                    = require("jive.utils.log").logger("applet.PiGridSkin")
local JogglerSkinApplet      = require("applets.JogglerSkin.JogglerSkinApplet")

local WH_FILL                = jive.ui.WH_FILL

local jiveMain               = jiveMain
local appletManager          = appletManager
local math                   = math


module(..., Framework.constants)
oo.class(_M, JogglerSkinApplet)


-- Define useful variables for this skin
local imgpath = "applets/PiGridSkin/images/"
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
	local params = JogglerSkinApplet.param(self)
	
	params.THUMB_SIZE = 100
	params.THUMB_SIZE_MENU = 100
	params.THUMB_SIZE_LINEAR = 40
	params.THUMB_SIZE_PLAYLIST = 40
	
	return params
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
	-- almost all styles come directly from QVGAbaseSkinApplet
	JogglerSkinApplet.skin(self, s)

	local screenWidth, screenHeight = Framework:getScreenSize()

	-- c is for constants
	local c = s.CONSTANTS

	-- skin
	local skinSuffix = c.skinSuffix

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

	local THUMB_SIZE_G = self:param().THUMB_SIZE
	local THUMB_SIZE_L = self:param().THUMB_SIZE_LINEAR

	-- alternatives for grid view
	local ALBUMMENU_FONT_SIZE_G = 18
	local ALBUMMENU_SMALL_FONT_SIZE_G = 16
	local MENU_ITEM_ICON_PADDING_G = { 0, 0, 0, 0 }

	local ITEMS_PER_LINE = 5
	local LINES_OF_ITEMS = 2.3

	local smallSpinny = c.smallSpinny


--------- DEFAULT WIDGET STYLES ---------
	--
	-- These are the default styles for the widgets 

	local menu_height = math.floor((screenHeight - c.TITLE_HEIGHT) / c.FIVE_ITEM_HEIGHT) * c.FIVE_ITEM_HEIGHT
	local grid_height = math.floor((screenHeight - c.TITLE_HEIGHT - 16) / 3) * 3

	s.menu.h = menu_height

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
			fg = c.TEXT_COLOR,
			sh = c.TEXT_SH_COLOR,
		},
		icon = {
			padding = MENU_ITEM_ICON_PADDING_G,
			align = 'center',
		},
		bgImg = false,
	}


--------- WINDOW STYLES ---------
	--
	-- These styles override the default styles for a specific window

	s.home_menu = _uses(s.text_list, {
		menu = {
			itemHeight = grid_height / LINES_OF_ITEMS,
			itemsPerLine = ITEMS_PER_LINE,
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
					font = _boldfont(ALBUMMENU_SMALL_FONT_SIZE_G),
					fg = c.TEXT_COLOR,
					sh = c.TEXT_SH_COLOR,
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
	
	s.home_menu.menu.item.text.font = _boldfont(ALBUMMENU_FONT_SIZE_G)

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

	s.home_menu.menu.locked = s.home_menu.menu.selected
	s.home_menu.menu.pressed = s.home_menu.menu.selected

	s.home_menu.menu.item.icon_no_artwork = {
		img = _loadImage(self, "IconsResized/icon_loading" .. skinSuffix ),
		h   = THUMB_SIZE,
		padding = c.MENU_ITEM_ICON_PADDING,
		align = 'center',
	}
	s.home_menu.menu.selected.item.icon_no_artwork = s.home_menu.menu.item.icon_no_artwork
	s.home_menu.menu.locked.item.icon_no_artwork = s.home_menu.menu.item.icon_no_artwork

	-- icon_list window
	-- icon_list Grid
	s.icon_listG = _uses(s.window, {
		menu = {
			itemsPerLine = ITEMS_PER_LINE,
			itemHeight = grid_height / LINES_OF_ITEMS,
			item = _uses(s.itemG, {
				text = {
					font = _font(ALBUMMENU_SMALL_FONT_SIZE_G),
					line = {
						{
							font = _boldfont(ALBUMMENU_FONT_SIZE_G),
							height = ALBUMMENU_FONT_SIZE_G * 1.3,
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
			align = c.ITEM_ICON_ALIGN,
			padding = c.CHECK_PADDING,
		},
	})
	s.icon_listG.menu.item_play = _uses(s.icon_listG.menu.item, { 
		arrow = { img = false },
	})
	s.icon_listG.menu.albumcurrent = _uses(s.icon_listG.menu.item_play, {
		arrow = { img = false },
	})
	s.icon_listG.menu.item_add  = _uses(s.icon_listG.menu.item, { 
		arrow = c.addArrow,
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

	-- choose player window is exactly the same as text_list on all windows except WQVGAlarge
	s.choose_player = _uses(s.icon_list)
	
--[[ Grid view isn't great for players, as quite often the player names would be cut off before the crucial part, eg. "Squeezebox Tou..."
	s.choose_player = _uses(s.icon_listG)
	s.choose_player.menu.item_checked = _uses(s.icon_listG.menu.item_checked_no_arrow)
	s.choose_player.menu.selected.item_checked = _uses(s.icon_listG.menu.selected.item_checked_no_arrow)
	s.choose_player.menu.pressed.item_checked = _uses(s.icon_listG.menu.pressed.item_checked_no_arrow)
--]]

	s.icon_list = _uses(s.icon_listG)

	s.track_list.title.icon.w = THUMB_SIZE_L


	local _buttonicon = {
		h   = THUMB_SIZE_G,
		padding = MENU_ITEM_ICON_PADDING_G,
		align = 'center',
		img = false,
	}

	-- XXX - where are these even used?
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
		padding = c.MENU_ITEM_ICON_PADDING,
		align = 'center',
	}

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
	s.hm_settings_pcp = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_settings_pcp" .. skinSuffix),
	})
	s.hm_radio = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_tunein" .. skinSuffix),
	})
	s.hm_radios = _uses(_buttonicon, {
		img = _loadImage(self, "IconsResized/icon_tunein" .. skinSuffix),
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



	return s

end

function free(self)
	local desktop = not System:isHardware()
	if desktop then
		log:warn("reload parent")

		package.loaded["applets.JogglerSkin.JogglerSkinApplet"] = nil
		JogglerSkinApplet = require("applets.JogglerSkin.JogglerSkinApplet")
	end
        return true
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

