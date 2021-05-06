-- input to action mappings

local Framework        = require("jive.ui.Framework")
module(..., Framework.constants)


charActionMappings = {}
charActionMappings.press = {
--BEGIN temp shortcuts to test action framework
	["["]  = "go_now_playing",
	["]"]  = "go_playlist",
	["{"]  = "go_current_track_info",
	["`"]  = "go_playlists",
	[";"]  = "go_music_library",
	[":"]  = "go_favorites",
	["'"]  = "go_brightness",
	[","]  = "shuffle_toggle",
	["."]  = "repeat_toggle",
	["|"]  = "sleep",
	["Q"]  = "power",
--END temp shortcuts to test action framework

--alternatives for common control buttons avoiding keyboard modifiers
	["f"]  = "go_favorites",
	["s"]  = "sleep",
	["q"]  = "power",
	["k"]  = "power_on",
	["i"]  = "power_off",
	["t"]  = "go_current_track_info",
	["n"]  = "go_home_or_now_playing",
	["m"]  = "create_mix",
	["g"]  = "stop",
	["d"]  = "add_end",
	["y"]  = "play_next",
	["e"]  = "scanner_rew",
	["r"]  = "scanner_fwd",
	["u"]  = "mute",
	["o"]  = "quit",

-- original
	["/"]   = "go_search",
	["h"]   = "go_home",
	["J"]   = "go_home_or_now_playing",
	["D"]   = "soft_reset",
	["x"]   = "play",
	["p"]   = "play",
	["P"]   = "create_mix",
	[" "]   = "pause",
	["c"]   = "pause",
	["C"]   = "stop",
	["a"]   = "add",
	["A"]   = "add_end",
	["W"]   = "play_next",
	["M"]   = "mute",
	["\b"]  = "back", -- BACKSPACE
	["\27"] = "back", -- ESC
	["j"]   = "back",
	["l"]   = "go",
	["S"]   = "take_screenshot",
	["z"]  = "jump_rew",
	["<"]  = "jump_rew",
	["Z"]  = "scanner_rew",
	["b"]  = "jump_fwd",
	[">"]  = "jump_fwd",
	["B"]  = "scanner_fwd",
	["+"]  = "volume_up",
	["="]  = "volume_up",
	["-"]  = "volume_down",
	["0"]  = "play_preset_0",
	["1"]  = "play_preset_1",
	["2"]  = "play_preset_2",
	["3"]  = "play_preset_3",
	["4"]  = "play_preset_4",
	["5"]  = "play_preset_5",
	["6"]  = "play_preset_6",
	["7"]  = "play_preset_7",
	["8"]  = "play_preset_8",
	["9"]  = "play_preset_9",
	[")"]  = "set_preset_0",
	["!"]  = "set_preset_1",
	["@"]  = "set_preset_2",
	["#"]  = "set_preset_3",
	["$"]  = "set_preset_4",
	["%"]  = "set_preset_5",
	["^"]  = "set_preset_6",
	["&"]  = "set_preset_7",
	["*"]  = "set_preset_8",
	["("]  = "set_preset_9",
	["?"]  = "help",

	--development tools -- Later when modifier keys are supported, these could be obscured from everyday users
	["R"]  = "reload_skin",
	["}"]  = "debug_skin",
	["~"]  = "debug_touch",

}


keyActionMappings = {}
keyActionMappings.press = {
	[KEY_HOME] = "go_home_or_now_playing",
	[KEY_PLAY] = "play",
	[KEY_ADD] = "add",
	[KEY_BACK] = "back",
	--[KEY_LEFT] = "back",
	[KEY_GO] = "go",
	--[KEY_RIGHT] = "go",
	[KEY_PAUSE] = "pause",
	[KEY_STOP] = "stop",
	[KEY_PRESET_0] = "play_preset_0",
	[KEY_PRESET_1] = "play_preset_1",
	[KEY_PRESET_2] = "play_preset_2",
	[KEY_PRESET_3] = "play_preset_3",
	[KEY_PRESET_4] = "play_preset_4",
	[KEY_PRESET_5] = "play_preset_5",
	[KEY_PRESET_6] = "play_preset_6",
	[KEY_PRESET_7] = "play_preset_7",
	[KEY_PRESET_8] = "play_preset_8",
	[KEY_PRESET_9] = "play_preset_9",
	[KEY_MUTE] = "mute",
	[KEY_PAGE_UP] = "page_up",
	[KEY_PAGE_DOWN] = "page_down",
	[KEY_FWD] = "jump_fwd",
	[KEY_REW] = "jump_rew",
	[KEY_FWD_SCAN] = "scanner_fwd",
	[KEY_REW_SCAN] = "scanner_rew",
	[KEY_VOLUME_UP] = "volume_up",
	[KEY_VOLUME_DOWN] = "volume_down",
	[KEY_PRINT] = "take_screenshot",
	[KEY_POWER] = "power",
	[KEY_ALARM] = "go_alarms",
}

--Hmm, this won't work yet since we still look for KEY_PRESS in a lot of places, and would get double responses
--keyActionMappings = {}
--keyActionMappings.down = {
--	[KEY_LEFT] = "back",
--	[KEY_BACK] = "back",
--}

gestureActionMappings = {
	[GESTURE_L_R] = "go_home", --will be reset by ShortcutsMeta defaults
	[GESTURE_R_L] = "go_now_playing_or_playlist", --will be reset by ShortcutsMeta defaults
}

keyActionMappings.hold = {
	[KEY_HOME] = "go_home",
	[KEY_PLAY] = "create_mix",
	[KEY_ADD]  = "add_end",
	[KEY_BACK] = "go_home",
	[KEY_LEFT] = "go_home",
	[KEY_GO] = "add", --has no default assignment yet
	[KEY_RIGHT] = "add",
	[KEY_PAUSE] = "stop",
	[KEY_PRESET_0] = "set_preset_0",
	[KEY_PRESET_1] = "set_preset_1",
	[KEY_PRESET_2] = "set_preset_2",
	[KEY_PRESET_3] = "set_preset_3",
	[KEY_PRESET_4] = "set_preset_4",
	[KEY_PRESET_5] = "set_preset_5",
	[KEY_PRESET_6] = "set_preset_6",
	[KEY_PRESET_7] = "set_preset_7",
	[KEY_PRESET_8] = "set_preset_8",
	[KEY_PRESET_9] = "set_preset_9",
	[KEY_FWD] = "scanner_fwd",
	[KEY_REW] = "scanner_rew",
	[KEY_VOLUME_UP] = "volume_up",
	[KEY_VOLUME_DOWN] = "volume_down",
	-- [KEY_REW + KEY_PAUSE] = "take_screenshot",  -- a stab at how to handle multi-press
	-- [KEY_BACK+ KEY_PLAY] = "start_demo", 
	[KEY_POWER] = "shutdown",
	[KEY_ALARM] = "go_alarms",
}

irActionMappings = {}
irActionMappings.press = {
	["sleep"]  = "sleep",
	["power"]  = "power",
	["power_off"]  = "power_off",
	["power_on"]  = "power_on",
	["home"]   = "go_home_or_now_playing",
	["search"]   = "go_search",
	["now_playing"]  = "go_now_playing",
	["size"]  = "go_playlist",
	["browse"]  = "go_music_library",
	["favorites"]  = "go_favorites",
	["brightness"]  = "go_brightness",
	["shuffle"]  = "shuffle_toggle",
	["repeat"]  = "repeat_toggle",

	["arrow_up"]  = "up",
	["arrow_down"]  = "down",
	["arrow_left"]  = "back",
	["arrow_right"]  = "go",
	["play"]  = "play",
	["pause"]  = "pause",
	["add"]  = "add",
	["fwd"]  = "jump_fwd",
	["rew"]  = "jump_rew",
	["volup"]  = "volume_up",
	["voldown"]  = "volume_down",
	["mute"] = "mute",
	["0"]  = "play_preset_0",
	["1"]  = "play_preset_1",
	["2"]  = "play_preset_2",
	["3"]  = "play_preset_3",
	["4"]  = "play_preset_4",
	["5"]  = "play_preset_5",
	["6"]  = "play_preset_6",
	["7"]  = "play_preset_7",
	["8"]  = "play_preset_8",
	["9"]  = "play_preset_9",

	["factory_test_mode"] = "go_factory_test_mode",
	["test_audio_routing"] = "go_test_audio_routing",

-- Harmony remote integration: Discrete IR codes to play presets 1-6
	["preset_1"]  = "play_preset_1",
	["preset_2"]  = "play_preset_2",
	["preset_3"]  = "play_preset_3",
	["preset_4"]  = "play_preset_4",
	["preset_5"]  = "play_preset_5",
	["preset_6"]  = "play_preset_6",
}

irActionMappings.hold = {
	["sleep"]  = "sleep",
	["power"]  = "power",
	["power_off"]  = "power_off",
	["power_on"]  = "power_on",
	["home"]   = "go_home",
	["search"]   = "go_search",
	["now_playing"]  = "go_now_playing",
	["size"]  = "go_playlist",
	["browse"]  = "go_music_library",
	["favorites"]  = "go_favorites",
	["brightness"]  = "go_brightness",
	["shuffle"]  = "shuffle_toggle",
	["repeat"]  = "repeat_toggle",

	["arrow_left"]  = "go_home",
	["arrow_right"]  = "add",
	["play"]  = "create_mix",
	["pause"]  = "stop",
	["add"]  = "add_end",
	["fwd"]  = "scanner_fwd",
	["rew"]  = "scanner_rew",
	["volup"]  = "volume_up",
	["voldown"]  = "volume_down",
	["0"]  = "disabled",
	["1"]  = "disabled",
	["2"]  = "disabled",
	["3"]  = "disabled",
	["4"]  = "disabled",
	["5"]  = "disabled",
	["6"]  = "disabled",
	["7"]  = "disabled",
	["8"]  = "disabled",
	["9"]  = "disabled",

}


actionActionMappings = {
	["title_left_press"]  = "back", --will be reset by ShortcutsMeta defaults
	["title_left_hold"]  = "go_home", --will be reset by ShortcutsMeta defaults
	["title_right_press"]  = "go_now_playing", --will be reset by ShortcutsMeta defaults
	["title_right_hold"]  = "go_playlist", --will be reset by ShortcutsMeta defaults
	["home_title_left_press"]  = "power", --will be reset by ShortcutsMeta defaults
	["home_title_left_hold"]  = "power", --will be reset by ShortcutsMeta defaults
}

-- enter actions here that are triggered in the app but not by any hard input mechanism. Entering them here will get them registered so they can be used
unassignedActionMappings = {
	"text_mode",
	"play_next",
	"finish_operation",
	"more_help",
	"cursor_left",
	"cursor_right",
	"clear",
	"go_settings",
	"go_rhapsody",
	"nothing",
	"disabled",
	"ignore",
	"power_off",
	"power_on",
	"cancel",
	"mute",
}
