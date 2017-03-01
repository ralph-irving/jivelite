local ipairs, pairs, tonumber, setmetatable, type, tostring = ipairs, pairs, tonumber, setmetatable, type, tostring

local math             = require("math")
local table            = require("table")
local os           = require("os")  
local string           = require("jive.utils.string")
local debug        = require("jive.utils.debug")

local oo               = require("loop.simple")

local Applet           = require("jive.Applet")
local Font             = require("jive.ui.Font")
local Framework        = require("jive.ui.Framework")
local Group            = require("jive.ui.Group")
local Icon             = require("jive.ui.Icon")
local Canvas           = require("jive.ui.Canvas")
local Choice           = require("jive.ui.Choice")
local Label            = require("jive.ui.Label")
local RadioButton      = require("jive.ui.RadioButton")
local RadioGroup       = require("jive.ui.RadioGroup")
local SimpleMenu       = require("jive.ui.SimpleMenu")
local Surface          = require("jive.ui.Surface")
local Tile             = require("jive.ui.Tile")
local Window           = require("jive.ui.Window")
local SnapshotWindow   = require("jive.ui.SnapshotWindow")

local Player           = require("jive.slim.Player")
                       
local datetime         = require("jive.utils.datetime")

local appletManager = appletManager
local jiveMain          = jiveMain
local jnt               = jnt

local LAYER_FRAME            = jive.ui.LAYER_FRAME
local LAYER_CONTENT_ON_STAGE = jive.ui.LAYER_CONTENT_ON_STAGE

local LAYOUT_NORTH           = jive.ui.LAYOUT_NORTH
local LAYOUT_EAST            = jive.ui.LAYOUT_EAST
local LAYOUT_SOUTH           = jive.ui.LAYOUT_SOUTH
local LAYOUT_WEST            = jive.ui.LAYOUT_WEST
local LAYOUT_CENTER          = jive.ui.LAYOUT_CENTER
local LAYOUT_NONE            = jive.ui.LAYOUT_NONE

local WH_FILL                = jive.ui.WH_FILL

module(..., Framework.constants)
oo.class(_M, Applet)

local jogglerSkinAlarmX = 748
local jogglerSkinAlarmY = 11

-- Define useful variables for this skin
local fontpath = "fonts/"
local FONT_NAME = "FreeSans"
local BOLD_PREFIX = "Bold"

local function _isJogglerSkin(skinName)
	if string.match(skinName, 'PiGridSkin') or string.match(skinName, 'JogglerSkin') then
		return true
	end
end

local function _isWQVGASkin(skinName)
    if skinName == 'WQVGAsmallSkin' or skinName == 'WQVGAlargeSkin' then
    	return true
    end
end

local function _isHDSkin(skinName)
    if string.match(skinName, "HDSkin") or string.match(skinName, "HDGridSkin") then
    	return true
    end
end


local function _imgpath(self)
	local skinName = self.skinName
	
	if _isJogglerSkin(skinName) then
		skinName = 'JogglerSkin'
		
	elseif _isWQVGASkin(skinName) then
		skinName = "WQVGAsmallSkin"
	
	elseif _isHDSkin(skinName) then
		skinName = "HDSkin"
	
	end
	
    return "applets/" .. skinName .. "/images/"
end

function _loadImage(self, file)
    return Surface:loadImage(self.imgpath .. file)
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

function displayName(self)
    return "Clock (NEW)"
end

Clock  = oo.class()

function Clock:notify_playerAlarmState(player, alarmSet)
    if not player:isLocal() then
        return
    end
    self.alarmSet = player:getAlarmState()
    log:debug('Setting self.alarmSet to ', self.alarmSet)

    self:Draw()
end

function Clock:__init(skin, windowStyle)
    log:debug("Init Clock")

    local obj = oo.rawnew(self)
    obj.screen_width, obj.screen_height = Framework:getScreenSize()

    -- the player object needs adding here for the alarm icon support
    obj.player = Player:getLocalPlayer()
    if obj.player then
        jnt:subscribe(obj)
        obj.alarmSet = obj.player:getAlarmState()
    else
        obj.alarmSet = nil
    end

    -- create window and icon
    if not windowStyle then
        windowStyle = 'Clock'
    end
    obj.window = Window(windowStyle)
    obj.window:setSkin(skin)
    obj.window:reSkin()
    obj.window:setShowFrameworkWidgets(false)

    obj.window:addListener(EVENT_MOTION,
        function()
            obj.window:hide(Window.transitionNone)
            return EVENT_CONSUME
        end)

    -- register window as a screensaver
    local manager = appletManager:getAppletInstance("ScreenSavers")
    manager:screensaverWindow(obj.window, _, _, _, 'Clock')

    return obj
end

function Clock:_getHour(time)
    local theHour = time.hour
    if self.clock_format_hour == "%I" then
        theHour = time.hour % 12
        if theHour == 0 then
            theHour = 12
        end
    end
    return self:_padString(theHour)

end

function Clock:_padString(number)
    if number < 10 then
        return "0" .. tostring(number)
    else
        return tostring(number)
    end
end

function Clock:_getMinute(time)
    return self:_padString(time.min)
end


function Clock:_getDate(time)
    local theDate
    if self.clock_format_date == "%d%m%Y" then
        theDate = self:_padString(time.day) .. self:_padString(time.month) .. tostring(time.year)
        
    else
        theDate = self:_padString(time.month) .. self:_padString(time.day) .. tostring(time.year)
    end
    return theDate
end

DotMatrix = oo.class({}, Clock)

function DotMatrix:__init(ampm, shortDateFormat)
    log:debug("Init Dot Matrix Clock")

    local skinName = jiveMain:getSelectedSkin()
    
    if not self.skin or skinName ~= self.oldSkinName then
        log:debug("Fetching Dot Matrix clock skin")
        self.oldSkinName = skinName
        self.skin = DotMatrix:getDotMatrixClockSkin(skinName)
    end
    obj = oo.rawnew(self, Clock(self.skin))

    obj.ampm = ampm

    obj.h1   = Group('h1', {
        digit = Icon('icon_dotMatrixDigit0'),
    })
    obj.h2   = Group('h2', {
        digit = Icon('icon_dotMatrixDigit0'),
    })
    local clockDots = Group('dots', { 
        dots = Icon('icon_dotMatrixDots'),
    })
    obj.m1   = Group('m1', {
        digit = Icon('icon_dotMatrixDigit0'),
    })
    obj.m2   = Group('m2', {
        digit = Icon('icon_dotMatrixDigit0')
    })
    local alarmStyle = 'icon_alarm_off'
    if obj.alarmSet then
        alarmStyle = 'icon_alarm_on'
    end
    obj.alarm = Group('alarm', {
        alarm = Icon(alarmStyle)
    })
    obj.M1    = Group('M1', {
        digit    = Icon('icon_dotMatrixDate0'),
    })
    obj.M2    = Group('M2', {
        digit    = Icon('icon_dotMatrixDate0'),
    })
    local dot1  = Group('dot1', {
        dot  = Icon('icon_dotMatrixDateDot'),
    })
    obj.D1    = Group('D1', {
        digit    = Icon('icon_dotMatrixDate0'),
    })
    obj.D2    = Group('D2', {
        digit    = Icon('icon_dotMatrixDate0'),
    })
    local dot2  = Group('dot2', {
        dot  = Icon('icon_dotMatrixDateDot'),
    })
    obj.Y1    = Group('Y1', {
        digit    = Icon('icon_dotMatrixDate0'),
    })
    obj.Y2    = Group('Y2', {
        digit    = Icon('icon_dotMatrixDate0'),
    })
    obj.Y3    = Group('Y3', {
        digit    = Icon('icon_dotMatrixDate0'),
    })
    obj.Y4    = Group('Y4', {
        digit    = Icon('icon_dotMatrixDate0'),
    })

    obj.window:addWidget(obj.h1)
    obj.window:addWidget(obj.h2)
    obj.window:addWidget(clockDots)
    obj.window:addWidget(obj.m1)
    obj.window:addWidget(obj.m2)

    obj.window:addWidget(obj.alarm)
    obj.window:addWidget(obj.M1)
    obj.window:addWidget(obj.M2)
    obj.window:addWidget(dot1)
    obj.window:addWidget(obj.D1)
    obj.window:addWidget(obj.D2)
    obj.window:addWidget(dot2)
    obj.window:addWidget(obj.Y1)
    obj.window:addWidget(obj.Y2)
    obj.window:addWidget(obj.Y3)
    obj.window:addWidget(obj.Y4)

    obj.show_ampm = ampm

    if ampm then
        obj.clock_format_hour = "%I"
    else
        obj.clock_format_hour = "%H"
    end

    obj.clock_format_minute = "%M"
    obj.clock_format_month  = "%m"
    obj.clock_format_day    = "%d"
    obj.clock_format_year   = "%Y"
    
    -- do not allow any format for date here, but instead decide 
    -- based on the position of %m and %d in shortDateFormat 
    -- if the format should end up on this clock as MM.DD.YYYY or DD.MM.YYYY
    local monthSpot = string.find(shortDateFormat, "m")
    local daySpot   = string.find(shortDateFormat, "d")
    if daySpot < monthSpot then
        obj.clock_format_date   = "%d%m%Y"
    else
        obj.clock_format_date   = "%m%d%Y"
    end
    
    obj.clock_format = obj.clock_format_hour .. ":" .. obj.clock_format_minute

    return obj
end


function DotMatrix:Draw()

    local time = os.date("*t")

    local theHour   = self:_getHour(time)
    local theMinute = self:_getMinute(time)
    local theDate   = self:_getDate(time)

--[[
    FOR TESTING PURPOSES 

    -- MIN test
    local theHour   = '01'
    local theMinute = '01'
    local theDate   = '01012009'

    -- MAX test
    local theHour   = '12'
    local theMinute = '59'
    local theDate   = '12312009'
--]]
    -- draw hour digits
    self:DrawClock(string.sub(theHour, 1, 1), 'h1')
    self:DrawClock(string.sub(theHour, 2, 2), 'h2')

    -- draw minute digits
    self:DrawClock(string.sub(theMinute, 1, 1), 'm1')
    self:DrawClock(string.sub(theMinute, 2, 2), 'm2')

    -- draw month digits
    self:DrawDate(string.sub(theDate, 1, 1), 'M1')
    self:DrawDate(string.sub(theDate, 2, 2), 'M2')

    -- draw day digits
    self:DrawDate(string.sub(theDate, 3, 3), 'D1')
    self:DrawDate(string.sub(theDate, 4, 4), 'D2')

    -- draw year digits
    self:DrawDate(string.sub(theDate, 5, 5), 'Y1')
    self:DrawDate(string.sub(theDate, 6, 6), 'Y2')
    self:DrawDate(string.sub(theDate, 7, 7), 'Y3')
    self:DrawDate(string.sub(theDate, 8, 8), 'Y4')
    --self:DrawMinTest()

    local alarmIcon = self.alarm:getWidget('alarm')
    if self.alarmSet then
        alarmIcon:setStyle('icon_alarm_on')
    else
        alarmIcon:setStyle('icon_alarm_off')
    end
end


function DotMatrix:DrawClock(digit, groupKey)
    local style = 'icon_dotMatrixDigit' .. digit
    if digit == '0' and groupKey == 'h1' and self.ampm then
        style = 'icon_dotMatrixDigitNone'
    end
    local widget = self[groupKey]:getWidget('digit')
    widget:setStyle(style)
end


function DotMatrix:DrawDate(digit, groupKey)
    local style = 'icon_dotMatrixDate' .. digit
    local widget = self[groupKey]:getWidget('digit')
    widget:setStyle(style)
end

-----------------------------------------------------------------------------------------

WordClock = oo.class({}, Clock)

function WordClock:__init(applet)
    log:debug("Init Word Clock")

    local skinName = jiveMain:getSelectedSkin()
    
    log:debug("self.skin: ", self.skin)
    log:debug("self.skinName: ", self.skinName)
    log:debug("skinName: ", skinName)
    log:debug("self.oldSkinName: ", self.oldSkinName)

    if not self.skin or skinName ~= self.oldSkinName then
        log:debug("Fetching WordClock clock skin")
        self.oldSkinName = skinName
        self.skin = WordClock:getWordClockSkin(skinName)
    end
    obj = oo.rawnew(self, Clock(self.skin))

    obj.textdate = Label('textdate')
    obj.skinParams = WordClock:getSkinParams(skinName)

    if _isJogglerSkin(skinName) or skinName == "WQVGAsmallSkin" or skinName == "WQVGAlargeSkin" then
        obj.pointer_textIt         = Surface:loadImage(obj.skinParams.textIt)  
        obj.pointer_textIs         = Surface:loadImage(obj.skinParams.textIs)  
        obj.pointer_textHas        = Surface:loadImage(obj.skinParams.textHas)  
        obj.pointer_textNearly     = Surface:loadImage(obj.skinParams.textNearly)  
        obj.pointer_textJustgone   = Surface:loadImage(obj.skinParams.textJustgone)  

        obj.pointer_textHalf       = Surface:loadImage(obj.skinParams.textHalf)  
        obj.pointer_textTen        = Surface:loadImage(obj.skinParams.textTen)  
        obj.pointer_textAquarter   = Surface:loadImage(obj.skinParams.textAQuarter)  
        obj.pointer_textTwenty     = Surface:loadImage(obj.skinParams.textTwenty)  

        obj.pointer_textFive       = Surface:loadImage(obj.skinParams.textFive)  
        obj.pointer_textMinutes    = Surface:loadImage(obj.skinParams.textMinutes)  
        obj.pointer_textTo         = Surface:loadImage(obj.skinParams.textTo)  
        obj.pointer_textPast       = Surface:loadImage(obj.skinParams.textPast)  

        obj.pointer_textHourOne    = Surface:loadImage(obj.skinParams.textHourOne)  
        obj.pointer_textHourTwo    = Surface:loadImage(obj.skinParams.textHourTwo)  
        obj.pointer_textHourThree  = Surface:loadImage(obj.skinParams.textHourThree)  
        obj.pointer_textHourFour   = Surface:loadImage(obj.skinParams.textHourFour)  
        obj.pointer_textHourFive   = Surface:loadImage(obj.skinParams.textHourFive)  
        obj.pointer_textHourSix    = Surface:loadImage(obj.skinParams.textHourSix)  
        obj.pointer_textHourSeven  = Surface:loadImage(obj.skinParams.textHourSeven)  
        obj.pointer_textHourEight  = Surface:loadImage(obj.skinParams.textHourEight)  
        obj.pointer_textHourNine   = Surface:loadImage(obj.skinParams.textHourNine)  
        obj.pointer_textHourTen    = Surface:loadImage(obj.skinParams.textHourTen)  
        obj.pointer_textHourEleven = Surface:loadImage(obj.skinParams.textHourEleven)  
        obj.pointer_textHourTwelve = Surface:loadImage(obj.skinParams.textHourTwelve)  

        obj.pointer_textOClock     = Surface:loadImage(obj.skinParams.textOClock)  
        obj.pointer_textAM         = Surface:loadImage(obj.skinParams.textAM)  
        obj.pointer_textPM         = Surface:loadImage(obj.skinParams.textPM)  
    elseif skinName == "QVGAlandscapeSkin" or skinName == "QVGAportraitSkin" then
        obj.pointer_hour           = Surface:loadImage(obj.skinParams.hourHand)
        obj.pointer_minute         = Surface:loadImage(obj.skinParams.minuteHand)
    end
    
    obj.alarmIcon = Surface:loadImage(obj.skinParams.alarmIcon)

    -- bring in applet's self so strings are available
    obj.applet    = applet

    obj.canvas   = Canvas('debug_canvas', function(screen)
        obj:_reDraw(screen)
    end)
    obj.window:addWidget(obj.canvas)
    obj.window:addWidget(obj.textdate)

    obj.clock_format = "%H:%M"
    return obj
end

function WordClock:Draw()
    log:debug("WordClock:Draw")
    self.canvas:reDraw()
end

function WordClock:_reDraw(screen)
    log:debug("WordClock:_reDraw")
    log:debug("WordClock:_reDraw self.skinName = " .. self.skinName)

    if _isJogglerSkin(self.skinName) or _isWQVGASkin(self.skinName) then
        local timenow = os.date("*t",os.time())

        local flags = WordClock:getwordflags(timenow)

        local all = false  -- Just for debugging screen position
        
        -- ratio by which we have to multiply coordinates relative to the Joggler skin
        local r = self.skin.Clock.ratio
        
        -- zoom factor by which we have to resize the artwork
        local z = r
        
        -- resizing is not necessary for the WQVGA skins - we have native sizes
        if _isWQVGASkin(self.skinName) then
        	z = 1
        end

        local x = self.skin.Clock.offsetX
      
    -- Row 1
        self.pointer_textIt:zoom(z, z, 1):blit(screen, x + 20*r, 50*r)
        if all or flags.is         then self.pointer_textIs:zoom(z, z, 1):blit(screen, x + 86*r, 50*r) end
        if all or flags.has        then self.pointer_textHas:zoom(z, z, 1):blit(screen, x + 156*r, 50*r) end
        if all or flags.nearly     then self.pointer_textNearly:zoom(z, z, 1):blit(screen, x + 280*r, 50*r) end
        if all or flags.justgone   then self.pointer_textJustgone:zoom(z, z, 1):blit(screen, x + 496*r, 50*r) end

    -- Row 2
        if all or flags.half       then self.pointer_textHalf:zoom(z, z, 1):blit(screen, x + 20*r, 108*r) end
        if all or flags.ten        then self.pointer_textTen:zoom(z, z, 1):blit(screen, x + 163*r, 108*r) end
        if all or flags.aquarter   then self.pointer_textAquarter:zoom(z, z, 1):blit(screen, x + 274*r, 108*r) end
        if all or flags.twenty     then self.pointer_textTwenty:zoom(z, z, 1):blit(screen, x + 579*r, 108*r) end

    -- Row 3
        if all or flags.five       then self.pointer_textFive:zoom(z, z, 1):blit(screen, x + 20*r, 165*r) end
        if all or flags.minutes    then self.pointer_textMinutes:zoom(z, z, 1):blit(screen, x + 169*r, 165*r) end
        if all or flags.to         then self.pointer_textTo:zoom(z, z, 1):blit(screen, x + 425*r, 165*r) end
        if all or flags.past       then self.pointer_textPast:zoom(z, z, 1):blit(screen, x + 537*r, 165*r) end
        if all or flags.hsix       then self.pointer_textHourSix:zoom(z, z, 1):blit(screen, x + 707*r, 165*r) end

    -- Row 4
        if all or flags.hseven     then self.pointer_textHourSeven:zoom(z, z, 1):blit(screen, x + 20*r, 222*r) end
        if all or flags.hone       then self.pointer_textHourOne:zoom(z, z, 1):blit(screen, x + 222*r, 222*r) end
        if all or flags.htwo       then self.pointer_textHourTwo:zoom(z, z, 1):blit(screen, x + 363*r, 222*r) end
        if all or flags.hten       then self.pointer_textHourTen:zoom(z, z, 1):blit(screen, x + 513*r, 222*r) end
        if all or flags.hfour      then self.pointer_textHourFour:zoom(z, z, 1):blit(screen, x + 650*r, 222*r) end

    -- Row 5
        if all or flags.hfive      then self.pointer_textHourFive:zoom(z, z, 1):blit(screen, x + 20*r, 280*r) end
        if all or flags.hnine      then self.pointer_textHourNine:zoom(z, z, 1):blit(screen, x + 193*r, 280*r) end
        if all or flags.htwelve    then self.pointer_textHourTwelve:zoom(z, z, 1):blit(screen, x + 371*r, 280*r) end
        if all or flags.height     then self.pointer_textHourEight:zoom(z, z, 1):blit(screen, x + 639*r, 280*r) end

    -- Row 6
        if all or flags.heleven    then self.pointer_textHourEleven:zoom(z, z, 1):blit(screen, x + 20*r, 338*r) end
        if all or flags.hthree     then self.pointer_textHourThree:zoom(z, z, 1):blit(screen, x + 222*r, 338*r) end
        if all or flags.oclock     then self.pointer_textOClock:zoom(z, z, 1):blit(screen, x + 398*r, 338*r) end
        if all or flags.am         then self.pointer_textAM:zoom(z, z, 1):blit(screen, x + 627*r, 338*r) end
        if all or flags.pm         then self.pointer_textPM:zoom(z, z, 1):blit(screen, x + 716*r, 338*r) end

        self.textdate:setValue("ON " .. string.upper(WordClock:getDateAsWords(tonumber(os.date("%d")))))

    elseif self.skinName == "QVGAlandscapeSkin" or self.skinName == "QVGAportraitSkin" then
        local x, y

        -- Setup Time Objects
        local time = os.date("*t")
        local m = time.min
        local h = time.hour % 12

        -- Hour Pointer
        local angle = (360 / 12) * (h + (m/60))

        local tmp = self.pointer_hour:rotozoom(-angle, 1, 5)
        local facew, faceh = tmp:getSize()
        x = math.floor((self.screen_width/2) - (facew/2))
        y = math.floor((self.screen_height/2) - (faceh/2))
        tmp:blit(screen, x, y)
        tmp:release()

        -- Minute Pointer
        local angle = (360 / 60) * m 

        local tmp = self.pointer_minute:rotozoom(-angle, 1, 5)
        local facew, faceh = tmp:getSize()
        x = math.floor((self.screen_width/2) - (facew/2))
        y = math.floor((self.screen_height/2) - (faceh/2))
        tmp:blit(screen, x, y)
        tmp:release()   

        self.textdate:setValue(string.upper(WordClock:getDateAsWords(tonumber(os.date("%d")))))
    end
    
    if self.alarmSet then
        local tmp = self.alarmIcon
        tmp:blit(screen, self.skinParams.alarmX, self.skinParams.alarmY)
    end
  
end

-----------------------------------------------------------------------------------------

Analog = oo.class({}, Clock)

function Analog:__init(applet)
    log:info("Init Analog Clock")

    local skinName = jiveMain:getSelectedSkin()
    
    if not self.skin or skinName ~= self.oldSkinName then
        log:debug("Fetching Analog clock skin")
        self.oldSkinName = skinName
        self.skin = Analog:getAnalogClockSkin(skinName)
    end
    obj = oo.rawnew(self, Clock(self.skin))

    obj.skinParams = Analog:getSkinParams(skinName)
    obj.pointer_hour = Surface:loadImage(obj.skinParams.hourHand)
    obj.pointer_minute = Surface:loadImage(obj.skinParams.minuteHand)
    obj.alarmIcon = Surface:loadImage(obj.skinParams.alarmIcon)

    -- bring in applet's self so strings are available
    obj.applet    = applet

    obj.canvas   = Canvas('debug_canvas', function(screen)
        obj:_reDraw(screen)
    end)
    obj.window:addWidget(obj.canvas)

    obj.clock_format = "%H:%M"
    return obj
end


function Analog:Draw()
    self.canvas:reDraw()
end


function Analog:_reDraw(screen)

    local x, y

    -- Setup Time Objects
    local time = os.date("*t")
    local m = time.min
    local h = time.hour % 12

    -- Hour Pointer
    local angle = (360 / 12) * (h + (m/60))

    local tmp = self.pointer_hour:rotozoom(-angle, self.skinParams.ratio, 5)
    local facew, faceh = tmp:getSize()
    x = math.floor((self.screen_width/2) - (facew/2))
    y = math.floor((self.screen_height/2) - (faceh/2))
    tmp:blit(screen, x, y)
    tmp:release()

    -- Minute Pointer
    local angle = (360 / 60) * m 

    local tmp = self.pointer_minute:rotozoom(-angle, self.skinParams.ratio, 5)
    local facew, faceh = tmp:getSize()
    x = math.floor((self.screen_width/2) - (facew/2))
    y = math.floor((self.screen_height/2) - (faceh/2))
    tmp:blit(screen, x, y)
    tmp:release()

    if self.alarmSet then
        local tmp = self.alarmIcon
        tmp:blit(screen, self.skinParams.alarmX, self.skinParams.alarmY)
    end
end

Digital = oo.class({}, Clock)

function Digital:__init(applet, ampm)
    log:debug("Init Digital Clock")
    
    local windowStyle = applet.windowStyle or 'Clock'

    local skinName = jiveMain:getSelectedSkin()

    if not self.skin or skinName ~= self.oldSkinName then
        log:debug("Fetching Digital clock skin")
        self.oldSkinName = skinName
        self.skin = Digital:getDigitalClockSkin(skinName)
    end

    obj = oo.rawnew(self, Clock(self.skin, windowStyle))

    -- store the applet's self so we can call self.applet:string() for localizations
    obj.applet = applet

    obj.h1   = Label('h1', '1')
    obj.h2   = Label('h2', '2')
    local dots = Group('dots', { 
        dots = Icon("icon_digitalDots") 
        }
    )
    obj.m1   = Label('m1', '0')
    obj.m2   = Label('m2', '0')
    obj.ampm = Label('ampm', '')

    local alarmStyle = 'icon_alarm_off'
    if obj.alarmSet then
        alarmStyle = 'icon_alarm_on'
    end
    obj.alarm = Group('alarm', {
        alarm = Icon(alarmStyle),
    })

    obj.today = Label('today', '')
    obj.dateGroup = Group('date', {
        dayofweek  = Label('dayofweek', ''),
        vdivider1  = Icon('icon_digitalClockVDivider'),
        dayofmonth = Label('dayofmonth'),
        vdivider2  = Icon('icon_digitalClockVDivider'),
        month      = Label('month'),
    })

    obj.ampm = Label('ampm')

    local hdivider = Group('horizDivider', {
        horizDivider = Icon('icon_digitalClockHDivider'),
    })
    local hdivider2 = Group('horizDivider2', {
        horizDivider = Icon('icon_digitalClockHDivider'),
    })

    obj.h1Shadow   = Group('h1Shadow', { 
        h1Shadow = Icon('icon_digitalClockDropShadow'), 
    })
    obj.h2Shadow   = Group('h2Shadow', {
        h2Shadow = Icon('icon_digitalClockDropShadow'),
    })
    obj.m1Shadow   = Group('m1Shadow', {
        m1Shadow = Icon('icon_digitalClockDropShadow'),
    })
    obj.m2Shadow   = Group('m2Shadow', {
        m2Shadow = Icon('icon_digitalClockDropShadow'),
    })

    obj.window:addWidget(obj.today)
    obj.window:addWidget(obj.alarm)
    -- clock widgets
    obj.window:addWidget(obj.h1)
    obj.window:addWidget(obj.h1Shadow)
    obj.window:addWidget(obj.h2)
    obj.window:addWidget(obj.h2Shadow)
    obj.window:addWidget(dots)
    obj.window:addWidget(obj.m1)
    obj.window:addWidget(obj.m1Shadow)
    obj.window:addWidget(obj.m2)
    obj.window:addWidget(obj.m2Shadow)
    obj.window:addWidget(obj.ampm)

    obj.window:addWidget(hdivider)
    obj.window:addWidget(hdivider2)

    -- date widgets
    obj.window:addWidget(obj.dateGroup)

    obj.show_ampm = ampm

    if ampm then
        obj.clock_format_hour = "%I"
        obj.useAmPm = true
    else
        obj.clock_format_hour = "%H"
        obj.useAmPm = false
    end
    obj.clock_format_minute = "%M"

    obj.clock_format = obj.clock_format_hour .. ":" .. obj.clock_format_minute

    return obj
end

    
function Digital:Draw()

    local time = os.date("*t")

    -- string day of week
    local dayOfWeek   = tostring(time.wday - 1)

    local token = "SCREENSAVER_CLOCK_DAY_" .. dayOfWeek
    local dayOfWeekString = self.applet:string(token)
    self.today:setValue(dayOfWeekString)
    local widget = self.dateGroup:getWidget('dayofweek')
    widget:setValue(dayOfWeekString)

    -- numerical day of month
    local dayOfMonth = tostring(time.day)
    widget = self.dateGroup:getWidget('dayofmonth')
    widget:setValue(dayOfMonth)

    -- string month of year
    token = "SCREENSAVER_CLOCK_MONTH_" .. self:_padString(time.month)
    local monthString = self.applet:string(token)
    widget = self.dateGroup:getWidget('month')
    widget:setValue(monthString)

    local alarmIcon = self.alarm:getWidget('alarm')
    if self.alarmSet then
        alarmIcon:setStyle('icon_alarm_on')
    else
        alarmIcon:setStyle('icon_alarm_off')
    end

    -- what time is it? it's time to get ill!
    self:DrawTime(time)
    
    --FOR DEBUG
    --[[
    self:DrawMinTest()
    self:DrawMaxTest()
    --]]
end
    
-- this method is around for testing the rendering of different elements
-- it is not called in practice
function Digital:DrawMinTest()

    self.h1:setValue('')
    local widget = self.h1Shadow:getWidget('h1Shadow')
    widget:setStyle('icon_digitalClockNoShadow')
    self.h2:setValue('1')
    self.m1:setValue('0')
    self.m2:setValue('1')
    
    self.ampm:setValue('AM')

    widget = self.dateGroup:getWidget('dayofweek')
    widget:setValue('Monday')
    widget = self.dateGroup:getWidget('dayofmonth')
    widget:setValue('01')
    widget = self.dateGroup:getWidget('month')
    widget:setValue('July')

end

-- this method is around for testing the rendering of different elements
-- it is not called in practice
function Digital:DrawMaxTest()

    self.h1:setValue('2')
    self.h2:setValue('4')
    self.m1:setValue('5')
    self.m2:setValue('9')
    
    self.ampm:setValue('PM')

    widget = self.dateGroup:getWidget('dayofweek')
    widget:setValue('Wednesday')
    widget = self.dateGroup:getWidget('dayofmonth')
    widget:setValue('31')
    widget = self.dateGroup:getWidget('month')
    widget:setValue('September')
end

function Digital:DrawTime(time)

    if not time then
        time = os.date("*t")
    end

    --local theMinute = tostring(time.min)
    local theMinute = self:_getMinute(time)
    local theHour   = self:_getHour(time)

    if string.sub(theHour, 1, 1) == '0' then
        self.h1:setValue('')
        widget = self.h1Shadow:getWidget('h1Shadow')
        widget:setStyle('icon_digitalClockNoShadow')
    else
        self.h1:setValue(string.sub(theHour, 1, 1))
        widget = self.h1Shadow:getWidget('h1Shadow')
        widget:setStyle('icon_digitalClockDropShadow')
    end
    self.h2:setValue(string.sub(theHour, 2, 2))

    self.m1:setValue(string.sub(theMinute, 1, 1))
    self.m2:setValue(string.sub(theMinute, 2, 2))
    
    -- Draw AM PM
    if self.useAmPm then
        -- localized ampm rendering requires an os.date() call
        local ampm = os.date("%p")
        self.ampm:setValue(ampm)
    end

end

-- keep these methods with their legacy names
-- to ensure backwards compatibility with old settings.lua files
function openDetailedClock(self, force)
    return self:_openScreensaver("Digital", 'Clock', force)
end

function openDetailedClockBlack(self, force)
    return self:_openScreensaver("Digital", 'ClockBlack', force)
end

function openDetailedClockTransparent(self, force)
    return self:_openScreensaver("Digital", 'ClockTransparent', force)
end

function openAnalogClock(self, force)
    return self:_openScreensaver("Analog", _, force)
end

function openStyledClock(self, force)
    return self:_openScreensaver("DotMatrix", _, force)
end

-----------------------------------------------------------------------------------------
function openWordClock(self, force)
    return self:_openScreensaver("WordClock", _, force)
end
-----------------------------------------------------------------------------------------

function _tick(self)
    local theTime = os.date(self.clock.clock_format)
    if theTime == self.oldTime then
        -- nothing to do yet
        return
    end

    self.oldTime = theTime

    if not self.snapshot then
        self.snapshot = SnapshotWindow()
        local manager = appletManager:getAppletInstance("ScreenSavers")
        manager:screensaverWindow(self.snapshot, _, _, _, 'Clock')
    else
        self.snapshot:refresh()
    end
    self.snapshot:replace(self.clock.window)
    self.clock:Draw()
    self.clock.window:replace(self.snapshot, Window.transitionFadeIn)

end


function _openScreensaver(self, type, windowStyle, force)
    log:debug("Type: " .. type)

    local year = os.date("%Y")
    if tonumber(year) < 2009 and not force then
        local time = os.date()
        log:warn('This device does not seem to have the right time: ', time)
        return
    end
    -- Global Date/Time Settings
    local weekstart       = datetime:getWeekstart() 
    local hours           = datetime:getHours() 
    local shortDateFormat = datetime:getShortDateFormat() 

    hours = (hours == "12")

    -- Create two clock instances, so that we can do use a fade in transition

    if type == "DotMatrix" then
        self.clock = DotMatrix(hours, shortDateFormat)
    elseif type == "Digital" then
        self.windowStyle = windowStyle
        self.clock = Digital(self, hours)
    elseif type == "Analog" then
        self.clock = Analog(self)
-----------------------------------------------------------------------------------------
    elseif type == "WordClock" then
        self.clock = WordClock(self)
-----------------------------------------------------------------------------------------
    else
        log:error("Unknown clock type")
        return
    end

    self.clock.window:addTimer(1000, function() self:_tick() end)

    self.clock:Draw()
    self.clock.window:show(Window.transitionFadeIn)

    return true
end


-- DOT MATRIX CLOCK SKIN
function DotMatrix:getDotMatrixClockSkin(skinName)

    -- 10' and 3'UIs send the same clock
    if skinName == 'WQVGAlargeSkin' then
        skinName = 'WQVGAsmallSkin'
    end

    self.skinName = skinName
    self.imgpath = _imgpath(self)

    local s = {}

    if skinName == 'WQVGAsmallSkin' then

        local dotMatrixBackground = Tile:loadImage(self.imgpath .. "Clocks/Dot_Matrix/wallpaper_clock_dotmatrix.png")

        local _dotMatrixDigit = function(self, digit)
            local fileName = "Clocks/Dot_Matrix/dotmatrix_clock_" .. tostring(digit) .. ".png"
            return {
                w = 61,
                h = 134,
                img = _loadImage(self, fileName),
                border = { 6, 0, 6, 0 },
                align = 'bottom',
            }
        end
    
        local _dotMatrixDate = function(self, digit)
            local fileName = "Clocks/Dot_Matrix/dotmatrix_date_" .. tostring(digit) .. ".png"
            return {
                w = 27,
                h = 43,
                img = _loadImage(self, fileName),
                align = 'bottom',
                border = { 1, 0, 1, 0 },
            }
        end
    
        s.icon_dotMatrixDigit0 = _dotMatrixDigit(self, 0)
        s.icon_dotMatrixDigit1 = _dotMatrixDigit(self, 1)
        s.icon_dotMatrixDigit2 = _dotMatrixDigit(self, 2)
        s.icon_dotMatrixDigit3 = _dotMatrixDigit(self, 3)
        s.icon_dotMatrixDigit4 = _dotMatrixDigit(self, 4)
        s.icon_dotMatrixDigit5 = _dotMatrixDigit(self, 5)
        s.icon_dotMatrixDigit6 = _dotMatrixDigit(self, 6)
        s.icon_dotMatrixDigit7 = _dotMatrixDigit(self, 7)
        s.icon_dotMatrixDigit8 = _dotMatrixDigit(self, 8)
        s.icon_dotMatrixDigit9 = _dotMatrixDigit(self, 9)
        s.icon_dotMatrixDigitNone = _uses(s.icon_dotMatrixDigit9, {
            img = false,
        })
    
        s.icon_dotMatrixDate0 = _dotMatrixDate(self, 0)
        s.icon_dotMatrixDate1 = _dotMatrixDate(self, 1)
        s.icon_dotMatrixDate2 = _dotMatrixDate(self, 2)
        s.icon_dotMatrixDate3 = _dotMatrixDate(self, 3)
        s.icon_dotMatrixDate4 = _dotMatrixDate(self, 4)
        s.icon_dotMatrixDate5 = _dotMatrixDate(self, 5)
        s.icon_dotMatrixDate6 = _dotMatrixDate(self, 6)
        s.icon_dotMatrixDate7 = _dotMatrixDate(self, 7)
        s.icon_dotMatrixDate8 = _dotMatrixDate(self, 8)
        s.icon_dotMatrixDate9 = _dotMatrixDate(self, 9)
    
        s.icon_dotMatrixDateDot = {
            align = 'bottom',
            img = _loadImage(self, "Clocks/Dot_Matrix/dotmatrix_dot_sm.png")
        }
    
        s.icon_dotMatrixDots = {
            align = 'center',
            border = { 4, 0, 3, 0 },
            img = _loadImage(self, "Clocks/Dot_Matrix/dotmatrix_clock_dots.png"),
        }
    
        s.icon_alarm_on = {
            align = 'bottom',
            img = _loadImage(self, "Clocks/Dot_Matrix/dotmatrix_alarm_on.png"),
            w   = 36,
            border = { 0, 0, 13, 0 },
        }
    
        s.icon_alarm_off = _uses(s.icon_alarm_on, {
            img = false,
        })
    
        local _clockDigit = {
            position = LAYOUT_NONE,
            w = 68,
            y = 38,
        }
        local _dateDigit = {
            position = LAYOUT_NONE,
            w = 27,
            y = 192,
        }

        local x = {}
        x.h1 = 68
        x.h2 = x.h1 + 72
        x.dots = x.h2 + 75
        x.m1 = x.dots + 27
        x.m2 = x.m1 + 72
        x.alarm = 73
        x.M1 = x.alarm + 36 + 13
        x.M2 = x.M1 + 30
        x.dot1 = x.M2 + 26 + 6
        x.D1 = x.dot1 + 10
        x.D2 = x.D1 + 30
        x.dot2 = x.D2 + 26 + 6
        x.Y1 = x.dot2 + 10
        x.Y2 = x.Y1 + 30
        x.Y3 = x.Y2 + 30
        x.Y4 = x.Y3 + 29

        s.Clock = {
            w = 480,
            h = 272,
            bgImg = dotMatrixBackground,
            h1 = _uses(_clockDigit, {
                x = x.h1,
            }),
            h2 = _uses(_clockDigit, {
                x = x.h2,
            }),
            dots = {
                position = LAYOUT_NONE,
                x = x.dots,
                w = 38,
                y = 75,
            },
            m1 = _uses(_clockDigit, {
                x = x.m1,
            }),
            m2 = _uses(_clockDigit, {
                x = x.m2,
            }),

            alarm = _uses(_dateDigit, {
                w = 45,
                y = 191,
                x = x.alarm,
            }),
            M1 = _uses(_dateDigit, {
                x = x.M1,
            }),
            M2 = _uses(_dateDigit, {
                x = x.M2,
            }),
            dot1 = _uses(_dateDigit, {
                x = x.dot1,
                w = 13,
                y = 222,
            }),
            D1 = _uses(_dateDigit, {
                x = x.D1,
            }),
            D2 = _uses(_dateDigit, {
                x = x.D2,
            }),
            dot2 = _uses(_dateDigit, {
                x = x.dot2,
                w = 13,
                y = 222,
            }),
            Y1 = _uses(_dateDigit, {
                x = x.Y1,
            }),
            Y2 = _uses(_dateDigit, {
                x = x.Y2,
            }),
            Y3 = _uses(_dateDigit, {
                x = x.Y3,
            }),
            Y4 = _uses(_dateDigit, {
                x = x.Y4,
            }),

        }

    elseif _isJogglerSkin(skinName) or _isHDSkin(skinName) then

        local dotMatrixBackground = Tile:loadImage(self.imgpath .. "Clocks/Dot_Matrix/wallpaper_clock_dotmatrix.png")

        local _dotMatrixDigit = function(self, digit)
            local fileName = "Clocks/Dot_Matrix/dotmatrix_clock_" .. tostring(digit) .. ".png"
            return {
                w = 61,
                h = 134,
                img = _loadImage(self, fileName),
                border = { 6, 0, 6, 0 },
                align = 'bottom',
            }
        end
    
        local _dotMatrixDate = function(self, digit)
            local fileName = "Clocks/Dot_Matrix/dotmatrix_date_" .. tostring(digit) .. ".png"
            return {
                w = 27,
                h = 43,
                img = _loadImage(self, fileName),
                align = 'bottom',
                border = { 1, 0, 1, 0 },
            }
        end
    
        s.icon_dotMatrixDigit0 = _dotMatrixDigit(self, 0)
        s.icon_dotMatrixDigit1 = _dotMatrixDigit(self, 1)
        s.icon_dotMatrixDigit2 = _dotMatrixDigit(self, 2)
        s.icon_dotMatrixDigit3 = _dotMatrixDigit(self, 3)
        s.icon_dotMatrixDigit4 = _dotMatrixDigit(self, 4)
        s.icon_dotMatrixDigit5 = _dotMatrixDigit(self, 5)
        s.icon_dotMatrixDigit6 = _dotMatrixDigit(self, 6)
        s.icon_dotMatrixDigit7 = _dotMatrixDigit(self, 7)
        s.icon_dotMatrixDigit8 = _dotMatrixDigit(self, 8)
        s.icon_dotMatrixDigit9 = _dotMatrixDigit(self, 9)
        s.icon_dotMatrixDigitNone = _uses(s.icon_dotMatrixDigit9, {
            img = false,
        })
    
        s.icon_dotMatrixDate0 = _dotMatrixDate(self, 0)
        s.icon_dotMatrixDate1 = _dotMatrixDate(self, 1)
        s.icon_dotMatrixDate2 = _dotMatrixDate(self, 2)
        s.icon_dotMatrixDate3 = _dotMatrixDate(self, 3)
        s.icon_dotMatrixDate4 = _dotMatrixDate(self, 4)
        s.icon_dotMatrixDate5 = _dotMatrixDate(self, 5)
        s.icon_dotMatrixDate6 = _dotMatrixDate(self, 6)
        s.icon_dotMatrixDate7 = _dotMatrixDate(self, 7)
        s.icon_dotMatrixDate8 = _dotMatrixDate(self, 8)
        s.icon_dotMatrixDate9 = _dotMatrixDate(self, 9)
    
        s.icon_dotMatrixDateDot = {
            align = 'bottom',
            img = _loadImage(self, "Clocks/Dot_Matrix/dotmatrix_dot_sm.png")
        }
    
        s.icon_dotMatrixDots = {
            align = 'center',
            border = { 4, 0, 3, 0 },
            img = _loadImage(self, "Clocks/Dot_Matrix/dotmatrix_clock_dots.png"),
        }
    
        s.icon_alarm_on = {
            align = 'bottom',
            img = _loadImage(self, "Clocks/Dot_Matrix/dotmatrix_alarm_on.png"),
            w   = 36,
            border = { 0, 0, 13, 0 },
        }
    
        s.icon_alarm_off = _uses(s.icon_alarm_on, {
            img = false,
        })

        local jogglerSkinAlignWithBackgroundXOffset = 2
        local jogglerSkinAlignWithBackgroundYOffset = 1
        local jogglerSkinXOffset = 160 + jogglerSkinAlignWithBackgroundXOffset + 9
        local jogglerSkinYOffset = 104 + jogglerSkinAlignWithBackgroundYOffset
        
        local _clockDigit = {
            position = LAYOUT_NONE,
            w = 68 + 4,
            y = 38 + jogglerSkinYOffset,
        }
        local _dateDigit = {
            position = LAYOUT_NONE,
            w = 27,
            y = 192 + jogglerSkinYOffset,
        }
        
        local x = {}
        x.h1 = 68 + jogglerSkinXOffset
        x.h2 = x.h1 + 72
        x.dots = x.h2 + 75 - 1
        x.m1 = x.dots + 27 + 1
        x.m2 = x.m1 + 72
        -- x.alarm = 73 + jogglerSkinXOffset
        x.alarm = jogglerSkinAlarmX
        -- x.M1 = x.alarm + 36 + 13 + 1 - 3
        x.M1 = 73 + jogglerSkinXOffset + 36 + 13 + 1 - 3
        x.M2 = x.M1 + 30
        x.dot1 = x.M2 + 26 + 6
        x.D1 = x.dot1 + 10
        x.D2 = x.D1 + 30
        x.dot2 = x.D2 + 26 + 6
        x.Y1 = x.dot2 + 10
        x.Y2 = x.Y1 + 30
        x.Y3 = x.Y2 + 30
        x.Y4 = x.Y3 + 29 + 1

        s.Clock = {
            w = 800, --480,
            h = 480, --272,
            bgImg = dotMatrixBackground,
            h1 = _uses(_clockDigit, {
                x = x.h1,
            }),
            h2 = _uses(_clockDigit, {
                x = x.h2,
            }),
            dots = {
                position = LAYOUT_NONE,
                x = x.dots,
                w = 38,
                y = 75 + jogglerSkinYOffset,
            },
            m1 = _uses(_clockDigit, {
                x = x.m1,
            }),
            m2 = _uses(_clockDigit, {
                x = x.m2,
            }),

            alarm = _uses(_dateDigit, {
                w = 45,
                -- y = 191 + jogglerSkinYOffset,
                y = jogglerSkinAlarmY,
                x = x.alarm,
            }),
            M1 = _uses(_dateDigit, {
                x = x.M1,
            }),
            M2 = _uses(_dateDigit, {
                x = x.M2,
            }),
            dot1 = _uses(_dateDigit, {
                x = x.dot1,
                w = 13,
                y = 222 + jogglerSkinYOffset,
            }),
            D1 = _uses(_dateDigit, {
                x = x.D1,
            }),
            D2 = _uses(_dateDigit, {
                x = x.D2,
            }),
            dot2 = _uses(_dateDigit, {
                x = x.dot2,
                w = 13,
                y = 222 + jogglerSkinYOffset,
            }),
            Y1 = _uses(_dateDigit, {
                x = x.Y1,
            }),
            Y2 = _uses(_dateDigit, {
                x = x.Y2,
            }),
            Y3 = _uses(_dateDigit, {
                x = x.Y3,
            }),
            Y4 = _uses(_dateDigit, {
                x = x.Y4,
            }),

        }

    -- dot matrix for landscape QVGA
    elseif skinName == 'QVGAlandscapeSkin' then

        local dotMatrixBackground = Tile:loadImage(self.imgpath .. "Clocks/Dot_Matrix/wallpaper_clock_dotmatrix.png")

        local _dotMatrixDigit = function(self, digit)
            local fileName = "Clocks/Dot_Matrix/dotmatrix_clock_" .. tostring(digit) .. ".png"
            return {
                w = 61,
                h = 134,
                img = _loadImage(self, fileName),
                align = 'bottom',
            }
        end
    
        local _dotMatrixDate = function(self, digit)
            local fileName = "Clocks/Dot_Matrix/dotmatrix_date_" .. tostring(digit) .. ".png"
            return {
                w = 27,
                h = 43,
                img = _loadImage(self, fileName),
                align = 'bottom',
            }
        end
    
        s.icon_dotMatrixDigit0 = _dotMatrixDigit(self, 0)
        s.icon_dotMatrixDigit1 = _dotMatrixDigit(self, 1)
        s.icon_dotMatrixDigit2 = _dotMatrixDigit(self, 2)
        s.icon_dotMatrixDigit3 = _dotMatrixDigit(self, 3)
        s.icon_dotMatrixDigit4 = _dotMatrixDigit(self, 4)
        s.icon_dotMatrixDigit5 = _dotMatrixDigit(self, 5)
        s.icon_dotMatrixDigit6 = _dotMatrixDigit(self, 6)
        s.icon_dotMatrixDigit7 = _dotMatrixDigit(self, 7)
        s.icon_dotMatrixDigit8 = _dotMatrixDigit(self, 8)
        s.icon_dotMatrixDigit9 = _dotMatrixDigit(self, 9)
        s.icon_dotMatrixDigitNone = _uses(s.icon_dotMatrixDigit9, {
            img = false,
        })
    
        s.icon_dotMatrixDate0 = _dotMatrixDate(self, 0)
        s.icon_dotMatrixDate1 = _dotMatrixDate(self, 1)
        s.icon_dotMatrixDate2 = _dotMatrixDate(self, 2)
        s.icon_dotMatrixDate3 = _dotMatrixDate(self, 3)
        s.icon_dotMatrixDate4 = _dotMatrixDate(self, 4)
        s.icon_dotMatrixDate5 = _dotMatrixDate(self, 5)
        s.icon_dotMatrixDate6 = _dotMatrixDate(self, 6)
        s.icon_dotMatrixDate7 = _dotMatrixDate(self, 7)
        s.icon_dotMatrixDate8 = _dotMatrixDate(self, 8)
        s.icon_dotMatrixDate9 = _dotMatrixDate(self, 9)
    
        s.icon_dotMatrixDateDot = {
            align = 'bottom',
            img = _loadImage(self, "Clocks/Dot_Matrix/dotmatrix_dot_sm.png")
        }
    
        s.icon_dotMatrixDots = {
            align = 'center',
            border = { 4, 0, 3, 0 },
            img = _loadImage(self, "Clocks/Dot_Matrix/dotmatrix_clock_dots.png"),
        }
    
        s.icon_alarm_on = {
            align = 'bottom',
            img = _loadImage(self, "Clocks/Dot_Matrix/dotmatrix_alarm_on.png"),
            w   = 36,
        }
    
        s.icon_alarm_off = _uses(s.icon_alarm_on, {
            img = false,
        })
    
        local _clockDigit = {
            position = LAYOUT_NONE,
            w = 61,
            y = 20,
        }
        local _dateDigit = {
            position = LAYOUT_NONE,
            w = 27,
            y = 183,
        }

        local x = {}
        x.h1 = 0
        x.h2 = x.h1 + 72
        x.dots = x.h2 + 74
        x.m1 = x.dots + 28
        x.m2 = x.m1 + 72
        x.alarm = 10
        x.M1 = x.alarm + 35
        x.M2 = x.M1 + 30
        x.dot1 = x.M2 + 27 + 5
        x.D1 = x.dot1 + 10
        x.D2 = x.D1 + 30
        x.dot2 = x.D2 + 27 + 5
        x.Y1 = x.dot2 + 10
        x.Y2 = x.Y1 + 30
        x.Y3 = x.Y2 + 30
        x.Y4 = x.Y3 + 30

        s.Clock = {
            w = 320,
            h = 240,
            bgImg = dotMatrixBackground,
            h1 = _uses(_clockDigit, {
                x = x.h1,
            }),
            h2 = _uses(_clockDigit, {
                x = x.h2,
            }),
            dots = {
                position = LAYOUT_NONE,
                x = x.dots,
                w = 38,
                y = 57,
            },
            m1 = _uses(_clockDigit, {
                x = x.m1,
            }),
            m2 = _uses(_clockDigit, {
                x = x.m2,
            }),
            alarm = _uses(_dateDigit, {
                w = 36,
                x = x.alarm,
            }),
            M1 = _uses(_dateDigit, {
                x = x.M1,
            }),
            M2 = _uses(_dateDigit, {
                x = x.M2,
            }),
            dot1 = _uses(_dateDigit, {
                x = x.dot1,
                w = 13,
                y = 213,
            }),
            D1 = _uses(_dateDigit, {
                x = x.D1,
            }),
            D2 = _uses(_dateDigit, {
                x = x.D2,
            }),
            dot2 = _uses(_dateDigit, {
                x = x.dot2,
                w = 13,
                y = 213,
            }),
            Y1 = _uses(_dateDigit, {
                x = x.Y1,
            }),
            Y2 = _uses(_dateDigit, {
                x = x.Y2,
            }),
            Y3 = _uses(_dateDigit, {
                x = x.Y3,
            }),
            Y4 = _uses(_dateDigit, {
                x = x.Y4,
            }),

        }


    -- dot matrix for Controller
    elseif skinName == 'QVGAportraitSkin' then
        local dotMatrixBackground = Tile:loadImage(self.imgpath .. "Clocks/Dot_Matrix/jive_wallpaper_clock_dotmatrix.png")

        local _dotMatrixDigit = function(self, digit)
            local fileName = "Clocks/Dot_Matrix/dotmatrix_clock_" .. tostring(digit) .. ".png"
            return {
                w = 61,
                h = 134,
                img = _loadImage(self, fileName),
                align = 'bottom',
            }
        end
    
        s.icon_dotMatrixDigit0 = _dotMatrixDigit(self, 0)
        s.icon_dotMatrixDigit1 = _dotMatrixDigit(self, 1)
        s.icon_dotMatrixDigit2 = _dotMatrixDigit(self, 2)
        s.icon_dotMatrixDigit3 = _dotMatrixDigit(self, 3)
        s.icon_dotMatrixDigit4 = _dotMatrixDigit(self, 4)
        s.icon_dotMatrixDigit5 = _dotMatrixDigit(self, 5)
        s.icon_dotMatrixDigit6 = _dotMatrixDigit(self, 6)
        s.icon_dotMatrixDigit7 = _dotMatrixDigit(self, 7)
        s.icon_dotMatrixDigit8 = _dotMatrixDigit(self, 8)
        s.icon_dotMatrixDigit9 = _dotMatrixDigit(self, 9)
        s.icon_dotMatrixDigitNone = _uses(s.icon_dotMatrixDigit9, {
            img = false,
        })
    
        s.icon_dotMatrixDate0 = { img = false }
        s.icon_dotMatrixDate1 = { img = false }
        s.icon_dotMatrixDate2 = { img = false }
        s.icon_dotMatrixDate3 = { img = false }
        s.icon_dotMatrixDate4 = { img = false }
        s.icon_dotMatrixDate5 = { img = false }
        s.icon_dotMatrixDate6 = { img = false }
        s.icon_dotMatrixDate7 = { img = false }
        s.icon_dotMatrixDate8 = { img = false }
        s.icon_dotMatrixDate9 = { img = false }
    
        s.icon_dotMatrixDateDot = {
            img = false,
        }
    
        s.icon_dotMatrixDots = {
            img = false,
        }
    
        s.icon_alarm_on = {
            img = _loadImage(self, "Clocks/DotMatrix/dot_matrix_alarm_on.png"),
        }
        s.icon_alarm_off = _uses(s.icon_alarm_on, {
            img = false,
        })
    
        s.icon_dotMatrixPowerOn = {
            img = false,
        }
        s.icon_dotMatrixPowerButtonOff = _uses(s.icon_dotMatrixPowerOn, {
            img = false,
        })
    
        local _clockDigit = {
            position = LAYOUT_NONE,
            w = 61,
        }

        local leftDigit = 59
        local rightDigit = 132
        local topDigit = 22
        local bottomDigit = 160

        s.Clock = {
            w = 240,
            h = 320,
            bgImg = dotMatrixBackground,
            h1 = _uses(_clockDigit, {
                x = leftDigit,
                y = topDigit,
            }),
            h2 = _uses(_clockDigit, {
                x = rightDigit,
                y = topDigit,
            }),
            m1 = _uses(_clockDigit, {
                x = leftDigit,
                y = bottomDigit,
            }),
            m2 = _uses(_clockDigit, {
                x = rightDigit,
                y = bottomDigit,
            }),

            dots = { hidden = 1 },
            alarm = { hidden = 1 },
            M1 = { hidden = 1 },
            M2 = { hidden = 1 },
            dot1 = { hidden = 1 },
            D1 = { hidden = 1 },
            D2 = { hidden = 1 },
            dot2 = { hidden = 1 },
            Y1 = { hidden = 1 },
            Y2 = { hidden = 1 },
            Y3 = { hidden = 1 },
            Y4 = { hidden = 1 },
        }


    end

    return s
end

-----------------------------------------------------------------------------------------

function WordClock:getWordClockSkin(skinName)
    log:debug("WordClock:getWordClockSkin - " .. skinName)

    self.skinName = skinName
    self.imgpath = _imgpath(self)
    
    log:debug("Image path - " .. self.imgpath)
    local s = {}

    local wordClockBackground = Tile:loadImage(self.imgpath .. "Clocks/WordClock/wallpaper_clock_word.png")
        
    if _isJogglerSkin(skinName) then
        local screen_width, screen_height = Framework:getScreenSize()
        local ratio = math.min(screen_width/800, screen_height/480)

        s.Clock = {
            textdate = {
                position = LAYOUT_NONE,
                x = 0,
                y = 420 * ratio,
                w = screen_width,
                font = _font(26),
                align = 'bottom',
                fg = { 0xff, 0xff, 0xff },
            },
            ratio = ratio,
            offsetX = 0
        }

        wordClockBackground = Surface:loadImage(self.imgpath .. "Clocks/WordClock/wallpaper_clock_word.png")
        wordClockBackground = wordClockBackground:zoom(ratio, ratio, 1)

        -- if the ratio of the resized background is different, we need to shift it accordingly
        if ratio ~= (800/480) then
	        local w, h = wordClockBackground:getSize()
	        
	        if w < screen_width then
	        	s.Clock.offsetX = (screen_width - w)/2
		        local tmp = Surface:newRGB(screen_width, screen_height)
		        wordClockBackground:blit(tmp, s.Clock.offsetX, 0)
		        wordClockBackground:release()
		        wordClockBackground = tmp
		    elseif h > screen_height then
		        local tmp = Surface:newRGB(screen_width, screen_height)
		        wordClockBackground:blit(tmp, 0, (screen_height - h)/2)
		        wordClockBackground:release()
		        wordClockBackground = tmp
		    end
        end
                
        s.Clock.bgImg = wordClockBackground
        
    elseif _isWQVGASkin(skinName) then
        s.Clock = {
            bgImg = wordClockBackground,
            textdate = {
                position = LAYOUT_NONE,
                x = 0,
                y = 244, --(420 * (480/800)) - (((480 * (480/800)) - 272) / 2)
                w = 480,
                font = _font(15), --26 * (480/800)
                align = 'bottom',
                fg = { 0xff, 0xff, 0xff },
            },
            offsetX = 0,
            ratio = 480/800
        }
    elseif skinName == "QVGAlandscapeSkin" then
        s.Clock = {
            bgImg = wordClockBackground,
            textdate = {
                position = LAYOUT_NONE,
                x = 0,
                y = 222,
                w = 320,
                font = _font(10), --26 * (320/800)
                align = 'bottom',
                fg = { 0xff, 0xff, 0xff },
            },
        }
    elseif skinName == "QVGAportraitSkin" then
        s.Clock = {
            bgImg = wordClockBackground,
            textdate = {
                position = LAYOUT_NONE,
                x = 0,
                y = 300,
                w = 240,
                font = _font(8), --26 * (240/800)
                align = 'bottom',
                fg = { 0xff, 0xff, 0xff },
            },
        }
    end
    
    return s
end

function WordClock:getSkinParams(skinName)
    log:debug("WordClock:getSkinParams - " .. skinName)

    self.skinName = skinName
    self.imgpath = _imgpath(self)
    
    log:debug("Image path - " .. self.imgpath)
    
    if _isJogglerSkin(skinName) or _isWQVGASkin(skinName) then
        local params = {
            textIt        = self.imgpath .. "Clocks/WordClock/" .. 'text-it.png',
            textIs        = self.imgpath .. "Clocks/WordClock/" .. 'text-is.png',
            textHas       = self.imgpath .. "Clocks/WordClock/" .. 'text-has.png',
            textNearly    = self.imgpath .. "Clocks/WordClock/" .. 'text-nearly.png',
            textJustgone  = self.imgpath .. "Clocks/WordClock/" .. 'text-justgone.png',

            textHalf      = self.imgpath .. "Clocks/WordClock/" .. 'text-half.png',
            textTen       = self.imgpath .. "Clocks/WordClock/" .. 'text-ten.png',
            textAQuarter  = self.imgpath .. "Clocks/WordClock/" .. 'text-aquarter.png',
            textTwenty    = self.imgpath .. "Clocks/WordClock/" .. 'text-twenty.png',

            textFive       = self.imgpath .. "Clocks/WordClock/" .. 'text-five.png',
            textMinutes    = self.imgpath .. "Clocks/WordClock/" .. 'text-minutes.png',
            textTo         = self.imgpath .. "Clocks/WordClock/" .. 'text-to.png',
            textPast       = self.imgpath .. "Clocks/WordClock/" .. 'text-past.png',

            textHourOne    = self.imgpath .. "Clocks/WordClock/" .. 'text-hour-one.png',
            textHourTwo    = self.imgpath .. "Clocks/WordClock/" .. 'text-hour-two.png',
            textHourThree  = self.imgpath .. "Clocks/WordClock/" .. 'text-hour-three.png',
            textHourFour   = self.imgpath .. "Clocks/WordClock/" .. 'text-hour-four.png',
            textHourFive   = self.imgpath .. "Clocks/WordClock/" .. 'text-hour-five.png',
            textHourSix    = self.imgpath .. "Clocks/WordClock/" .. 'text-hour-six.png',
            textHourSeven  = self.imgpath .. "Clocks/WordClock/" .. 'text-hour-seven.png',
            textHourEight  = self.imgpath .. "Clocks/WordClock/" .. 'text-hour-eight.png',
            textHourNine   = self.imgpath .. "Clocks/WordClock/" .. 'text-hour-nine.png',
            textHourTen    = self.imgpath .. "Clocks/WordClock/" .. 'text-hour-ten.png',
            textHourEleven = self.imgpath .. "Clocks/WordClock/" .. 'text-hour-eleven.png',
            textHourTwelve = self.imgpath .. "Clocks/WordClock/" .. 'text-hour-twelve.png',

            textOClock     = self.imgpath .. "Clocks/WordClock/" .. 'text-oclock.png',
            textAM         = self.imgpath .. "Clocks/WordClock/" .. 'text-am.png',
            textPM         = self.imgpath .. "Clocks/WordClock/" .. 'text-pm.png',

            alarmIcon  = self.imgpath .. "Clocks/WordClock/" .. 'icon_alarm_word.png',
            alarmX     = jogglerSkinAlarmX,
            alarmY     = jogglerSkinAlarmY,
        }
        
        if _isWQVGASkin(skinname) then
            params.alarmX = 445
            params.alarmY = 2
        end
        
        return params
    elseif skinName == "QVGAlandscapeSkin" then
        return {
            minuteHand = self.imgpath .. "Clocks/WordClock/" .. 'clock_word_min_hand.png',
            hourHand   = self.imgpath .. "Clocks/WordClock/" .. 'clock_word_hr_hand.png',
            alarmIcon  = self.imgpath .. "Clocks/WordClock/" .. 'icon_alarm_word.png',
            alarmX     = 280,
            alarmY     = 15,
        }
    elseif skinName == "QVGAportraitSkin" then
        return {
            minuteHand = self.imgpath .. "Clocks/WordClock/" .. 'clock_word_min_hand.png',
            hourHand   = self.imgpath .. "Clocks/WordClock/" .. 'clock_word_hr_hand.png',
            alarmIcon  = self.imgpath .. "Clocks/WordClock/" .. 'icon_alarm_word.png',
            alarmX     = 200,
            alarmY     = 15,
        }
    end
end

function WordClock:getwordflags(timenow)
    local flags = {}

    local fifths = {
        function(x) flags.zero = true end,
        function(x) flags.five = true flags.minutes = true end,
        function(x) flags.ten = true flags.minutes = true end,
        function(x) flags.aquarter = true end,
        function(x) flags.twenty = true flags.minutes = true end,
        function(x) flags.twenty = true flags.five = true flags.minutes = true end,
        function(x) flags.half = true end,
        function(x) flags.twenty = true flags.five = true flags.minutes = true end,
        function(x) flags.twenty = true flags.minutes = true end,
        function(x) flags.aquarter = true end,
        function(x) flags.ten = true flags.minutes = true end,
        function(x) flags.five = true flags.minutes = true end,
        function(x) flags.zero = true end
    }

    -- Work out IS, HAS, NEARLY and JUST GONE

    local tmp = timenow.min % 5

    if tmp == 0 then
      flags.is = true flags.exactly = true
    elseif tmp == 1 or tmp == 2 then
      flags.has = true flags.justgone = true
    elseif tmp == 3 or tmp == 4 then
      flags.is = true flags.nearly = true
    end

    -- Work out five minute divisions

    tmp = math.floor(timenow.min / 5) + 2

    if flags.exactly or flags.justgone then
      tmp = tmp - 1
    end

    fifths[tmp]()

    -- Work out TO, PAST and OCLOCK

    if (timenow.min >= 0 and timenow.min <= 2) or timenow.min == 58 or timenow.min == 59 then
      flags.oclock = true
    elseif (timenow.min >= 3 and timenow.min <= 32) then
      flags.past = true
    elseif (timenow.min >= 33 and timenow.min <= 57) then
      flags.to = true
    end

    -- Work out whether AM or PM

      if timenow.hour <= 11 then
        flags.am = true
      else
        flags.pm = true
      end

    -- Work out hour

    local hours = {
        function(x) flags.htwelve = true end,
        function(x) flags.hone = true end,
        function(x) flags.htwo = true end,
        function(x) flags.hthree = true end,
        function(x) flags.hfour = true end,
        function(x) flags.hfive = true end,
        function(x) flags.hsix = true end,
        function(x) flags.hseven = true end,
        function(x) flags.height = true end,
        function(x) flags.hnine = true end,
        function(x) flags.hten = true end,
        function(x) flags.heleven = true end,
        function(x) flags.htwelve = true end
    }

    local hour12 = (timenow.hour % 12) + 1

    if timenow.min >= 0 and timenow.min <=32 then
      hours[hour12]()
    elseif timenow.min >= 33 and timenow.min <=59 then
      hours[hour12 + 1]()
    end

    return flags
end

-- Generate output
function WordClock:timeastext(flags)

    local timestr = "IT"

    if flags.is == true then
      timestr = timestr .. " IS"
    end

    if flags.has == true then
      timestr = timestr .. " HAS"
    end

    if flags.justgone == true then
      timestr = timestr .. " JUST GONE"
    end

    if flags.nearly == true then
      timestr = timestr .. " NEARLY"
    end

    if flags.ten == true then
      timestr = timestr .. " TEN"
    elseif flags.aquarter == true then
      timestr = timestr .. " A QUARTER"
    elseif flags.twenty == true then
      timestr = timestr .. " TWENTY"
    end

    if flags.five == true then
      timestr = timestr .. " FIVE"
    end

    if flags.half == true then
      timestr = timestr .. " HALF"
    end

    if flags.past == true then
      timestr = timestr .. " PAST"
    end

    if flags.to == true then
      timestr = timestr .. " TO"
    end

    if flags.hone == true then
      timestr = timestr .. " ONE"
    elseif flags.htwo == true then
      timestr = timestr .. " TWO"
    elseif flags.hthree == true then
      timestr = timestr .. " THREE"
    elseif flags.hfour == true then
      timestr = timestr .. " FOUR"
    elseif flags.hfive == true then
      timestr = timestr .. " FIVE"
    elseif flags.hsix == true then
      timestr = timestr .. " SIX"
    elseif flags.hseven == true then
      timestr = timestr .. " SEVEN"
    elseif flags.height == true then
      timestr = timestr .. " EIGHT"
    elseif flags.hnine == true then
      timestr = timestr .. " NINE"
    elseif flags.hten == true then
      timestr = timestr .. " TEN"
    elseif flags.heleven == true then
      timestr = timestr .. " ELEVEN"
    elseif flags.htwelve == true then
      timestr = timestr .. " TWELVE"
    end

    if flags.oclock == true then
      timestr = timestr .. " O'CLOCK"
    end

    if flags.am == true then
      timestr = timestr .. " AM"
    elseif flags.pm == true then
      timestr = timestr .. " PM"
    end

    return timestr
end

function WordClock:getDateAsWords(day)
    local w = {
        "First",
        "Second",
        "Third",
        "Fourth",
        "Fifth",
        "Sixth",
        "Seventh",
        "Eighth",
        "Ninth",
        "Tenth",
        "Eleventh",
        "Twelfth",
        "Thirteenth",
        "Fourteenth",
        "Fifteenth",
        "Sixteenth",
        "Seventeenth",
        "Eighteenth",
        "Nineteenth",
        "Twentieth",
        "Twenty First",
        "Twenty Second",
        "Twenty Third",
        "Twenty Fourth",
        "Twenty Fifth",
        "Twenty Sixth",
        "Twenty Seventh",
        "Twenty Eighth",
        "Twenty Ninth",
        "Thirtieth",
        "Thirty First"
    }

    return( os.date("%A the ") .. w[day] .. " of " .. os.date("%B"))
end

-----------------------------------------------------------------------------------------


-- DIGITAL CLOCK SKIN
function Digital:getDigitalClockSkin(skinName)
    self.skinName = skinName
    self.imgpath = _imgpath(self)

    local s = {}

    if _isWQVGASkin(skinName) then

        local digitalClockBackground = Tile:loadImage(self.imgpath .. "Clocks/Digital/wallpaper_clock_digital.png")
        local digitalClockDigit = {
            font = _font(143),
            align = 'center',
            fg = { 0xcc, 0xcc, 0xcc },
            w = 76,
        }
        local shadow = {
            w = 76,
        }

        local x = {}
                x.h1 = 48
                x.h2 = x.h1 + 75
                x.dots = x.h2 + 75
                x.m1 = x.dots + 39
                x.m2 = x.m1 + 86 
                x.alarm = x.m2 + 80
        x.ampm = x.alarm

        local _clockDigit = {
            position = LAYOUT_NONE,
            font = _font(143),
            align = 'center',
            fg = { 0xcc, 0xcc, 0xcc },
            y = 54,
            zOrder = 10,
        }
        local _digitShadow = _uses(_clockDigit, {
            y = 54 + 100,
            zOrder = 1,
        })
    
        s.icon_digitalClockDropShadow = {
            img = _loadImage(self, "Clocks/Digital/drop_shadow_digital.png"),
            align = 'center',
            padding = { 4, 0, 0, 0 },
            w = 76,
        }

        s.icon_digitalClockNoShadow = _uses(s.icon_digitalClockDropShadow, {
            img = false
        })

        s.icon_alarm_on = {
            img = _loadImage(self, "Clocks/Digital/icon_alarm_digital.png"),
        }
        s.icon_alarm_off = {
            img = false
        }

        s.icon_digitalClockHDivider = {
            w = WH_FILL,
            img = _loadImage(self, "Clocks/Digital/divider_hort_digital.png"),
        }

        s.icon_digitalClockVDivider = {
            w = 3,
            img = _loadImage(self, "Clocks/Digital/divider_vert_digital.png"),
            align = 'center',
        }

        s.icon_digitalDots = {
            img = _loadImage(self, "Clocks/Digital/clock_dots_digital.png"),
            align = 'center',
            w = 40,
            border = { 14, 0, 12, 0 },
        }

        s.icon_digitalClockBlank = {
            img = false,
            w = 40,
        }

        s.Clock = {
            bgImg = digitalClockBackground,
            h1 = _uses(_clockDigit, {
                x = x.h1,
            }),
            h1Shadow = _uses(_digitShadow, {
                x = x.h1,
            }),
            h2 = _uses(_clockDigit, {
                x = x.h2,
            }),
            h2Shadow = _uses(_digitShadow, {
                x = x.h2,
            }),
            dots = _uses(_clockDigit, {
                x = x.dots,
                y = 93,
                w = 40,
            }),
            m1 = _uses(_clockDigit, {
                x = x.m1,
            }),
            m1Shadow = _uses(_digitShadow, {
                x = x.m1,
            }),
            m2 = _uses(_clockDigit, {
                x = x.m2,
            }),
            m2Shadow = _uses(_digitShadow, {
                x = x.m2,
            }),

            ampm = {
                position = LAYOUT_NONE,
                x = x.ampm,
                y = 112,
                font = _font(11),
                align = 'bottom',
                fg = { 0xcc, 0xcc, 0xcc },
            },
            alarm = {
                position = LAYOUT_NONE,
                x = x.alarm,
                y = 56,
            },
            ampm = {
                position = LAYOUT_NONE,
                x = 403,
                y = 144,
                font = _font(20),
                align = 'bottom',
                fg = { 0xcc, 0xcc, 0xcc },
            },
            horizDivider2 = { hidden = 1 },
            today = { hidden = 1 },
            horizDivider = {
                position = LAYOUT_NONE,
                x = 0,
                y = 194,
            },
            date = {
                position = LAYOUT_SOUTH,
                order = { 'dayofweek', 'vdivider1', 'dayofmonth', 'vdivider2', 'month' },
                w = WH_FILL,
                h = 70,
                padding = { 0, 0, 0, 6 },
                dayofweek = {
                    align = 'center',
                    w = 190,
                    h = WH_FILL,
                    font = _font(20),
                    fg = { 0xcc, 0xcc, 0xcc },
                    padding  = { 1, 0, 0, 6 },
                },
                vdivider1 = {
                    align = 'center',
                    w = 3,
                },
                dayofmonth = {
                    font = _font(56),
                    w = 95,
                    h = WH_FILL,
                    align = 'center',
                    fg = { 0xcc, 0xcc, 0xcc },
                    padding = { 0, 0, 0, 4 },
                },
                vdivider2 = {
                    align = 'center',
                    w = 3,
                },
                month = {
                    font = _font(20),
                    w = WH_FILL,
                    h = WH_FILL,
                    align = 'center',
                    fg = { 0xcc, 0xcc, 0xcc },
                    padding = { 0, 0, 0, 5 },
                },
                year = {
                    font = _boldfont(20),
                    w = 50,
                    h = WH_FILL,
                    align = 'left',
                    fg = { 0xcc, 0xcc, 0xcc },
                    padding = { 3, 0, 0, 5 },
                },
            },
        }
    
        local blackMask = Tile:fillColor(0x000000ff)
        s.ClockBlack = _uses(s.Clock, {
            bgImg = blackMask,
            horizDivider = { hidden = 1 },
            horizDivider2 = { hidden = 1 },
            today = { hidden = 1 },
            date = {
                order = { 'dayofweek', 'dayofmonth', 'month', 'year' },
            },
            h1Shadow = { hidden = 1 },
            h2Shadow = { hidden = 1 },
            m1Shadow = { hidden = 1 },
            m2Shadow = { hidden = 1 },
        })
        s.ClockTransparent = _uses(s.Clock, {
            bgImg = false,
            horizDivider = { hidden = 1 },
            horizDivider2 = { hidden = 1 },
            today = { hidden = 1 },
            date = {
                order = { 'dayofweek', 'dayofmonth', 'month', 'year' },
            },
            h1Shadow = { hidden = 1 },
            h2Shadow = { hidden = 1 },
            m1Shadow = { hidden = 1 },
            m2Shadow = { hidden = 1 },
        })
    elseif _isJogglerSkin(skinName) or _isHDSkin(skinName) then

        local screen_width, screen_height = Framework:getScreenSize()
        local scale = screen_height / 480
        local scale_x = screen_width / 800
        local digitWidth = 120 * scale

        local jogglerSkinXOffset = 20
        local jogglerSkinYOffset = 104

        local digitalClockBackground = _loadImage(self, "Clocks/Digital/wallpaper_clock_digital.png")
        digitalClockBackground = digitalClockBackground:zoom(scale_x, scale, 1)

        local x = {}
        x.dots = screen_width/2 - 20
        x.h2   = x.dots - digitWidth - 20
        x.h1   = x.h2 - digitWidth
        x.m1   = x.dots + 40
        x.m2   = x.m1 + digitWidth
        x.ampm = x.m2 + digitWidth
        x.alarm = jogglerSkinAlarmX
        
        local digitalDots = _loadImage(self, "Clocks/Digital/clock_dots_digital.png")
        if scale ~= 1 then
	        digitalDots = digitalDots:zoom(scale, scale, 1)
	    end
	    
	    -- unfortunately I didn't find any reliable algorithm to calculate this value
	    local ampmY = 277
	    if screen_height == 600 then
	    	ampmY = 310
	    elseif screen_height > 600 and screen_height <= 800 then
	    	ampmY = 360
	    end

        local _clockDigit = {
            position = LAYOUT_NONE,
            font = _font(220 * scale),
            lineHeight = 220 * scale,
            fg = { 0xcc, 0xcc, 0xcc },
            y = 40 + jogglerSkinYOffset,
            zOrder = 10,
        }
        
        -- hide the drop shadows, as they're really hard to scale and position right in all possible resolutions
        local _digitShadow = _uses(_clockDigit, {
 			hidden = 1
        })
    
        s.icon_digitalClockDropShadow = {
        	hidden = 1
        }

        s.icon_digitalClockNoShadow = _uses(s.icon_digitalClockDropShadow, {
            img = false
        })

        s.icon_alarm_on = {
            img = _loadImage(self, "Clocks/Digital/icon_alarm_digital.png"),
        }
        s.icon_alarm_off = {
            img = false
        }

		local digitalClockHDivider = _loadImage(self, "Clocks/Digital/divider_hort_digital.png")
		digitalClockHDivider = digitalClockHDivider:zoom(scale_x, 1, 1)
		
        s.icon_digitalClockHDivider = {
            w = WH_FILL,
            img = digitalClockHDivider,
        }

        s.icon_digitalClockVDivider = {
            w = 3,
            img = _loadImage(self, "Clocks/Digital/divider_vert_digital.png"),
            align = 'center',
        }

        s.icon_digitalDots = {
            img = digitalDots,
            align = 'center',
            h = 160 * scale,
        }

        s.icon_digitalClockBlank = {
            img = false,
            w = 40,
        }

        s.Clock = {
            bgImg = digitalClockBackground,
            h1 = _uses(_clockDigit, {
                x = x.h1,
            }),
            h1Shadow = _uses(_digitShadow),
            h2 = _uses(_clockDigit, {
                x = x.h2,
            }),
            h2Shadow = _uses(_digitShadow),
            dots = _uses(_clockDigit, {
                x = x.dots,
            }),
            m1 = _uses(_clockDigit, {
                x = x.m1,
            }),
            m1Shadow = _uses(_digitShadow),
            m2 = _uses(_clockDigit, {
                x = x.m2,
            }),
            m2Shadow = _uses(_digitShadow),

            alarm = {
                position = LAYOUT_NONE,
                x = x.alarm,
                -- y = 56,
                y = jogglerSkinAlarmY,
            },
            ampm = {
                position = LAYOUT_NONE,
                x = x.ampm,
                y = ampmY,
                font = _boldfont(40*scale),
                fg = { 0xcc, 0xcc, 0xcc },
            },
            horizDivider2 = { hidden = 1 },
            today = { hidden = 1 },
            horizDivider = {
                position = LAYOUT_NONE,
                x = 0,
                y = screen_height - 80,
            },
            date = {
                position = LAYOUT_SOUTH,
                order = { 'dayofweek', 'vdivider1', 'dayofmonth', 'vdivider2', 'month' },
                w = math.min(screen_width, 800),
                x = screen_width/2 - math.min(screen_width, 800)/2,
                align = 'center',
                h = 70,
                padding = { 0, 0, 0, 6 },
                dayofweek = {
                    align = 'center',
                    w = 348,
                    h = WH_FILL,
                    font = _font(30),
                    fg = { 0xcc, 0xcc, 0xcc },
                    padding  = { 1, 0, 0, 6 },
                },
                vdivider1 = {
                    align = 'center',
                    w = 3,
                },
                dayofmonth = {
                    font = _font(56),
                    w = 95,
                    h = WH_FILL,
                    align = 'center',
                    fg = { 0xcc, 0xcc, 0xcc },
                    padding = { 0, 0, 0, 4 },
                },
                vdivider2 = {
                    align = 'center',
                    w = 3,
                },
                month = {
                    font = _font(30),
                    w = WH_FILL,
                    h = WH_FILL,
                    align = 'center',
                    fg = { 0xcc, 0xcc, 0xcc },
                    padding = { 0, 0, 0, 5 },
                },
                year = {
                    font = _boldfont(30),
                    w = 50,
                    h = WH_FILL,
                    align = 'left',
                    fg = { 0xcc, 0xcc, 0xcc },
                    padding = { 3, 0, 0, 5 },
                },
            },
        }
    
        local blackMask = Tile:fillColor(0x000000ff)
        s.ClockBlack = _uses(s.Clock, {
            bgImg = blackMask,
            horizDivider = { hidden = 1 },
            date = {
                order = { 'dayofweek', 'dayofmonth', 'month', 'year' },
            },
        })
        s.ClockTransparent = _uses(s.Clock, {
            bgImg = false,
            horizDivider = { hidden = 1 },
            date = {
                order = { 'dayofweek', 'dayofmonth', 'month', 'year' },
            },
        })
    elseif skinName == 'QVGAlandscapeSkin'  then

        local digitalClockBackground = Tile:loadImage(self.imgpath .. "Clocks/Digital/bb_clock_digital.png")
        local shadow = {
            w = 62,
        }
        local _clockDigit = {
            position = LAYOUT_NONE,
            font = _font(100),
            align = 'right',
            fg = { 0xcc, 0xcc, 0xcc },
            w = 62,
            y = 48,
            zOrder = 10,
        }
        local _digitShadow = _uses(_clockDigit, {
            y = 116,
            zOrder = 1,
        })
    
        local x = {}
                x.h1 = 19
                x.h2 = x.h1 + 50 
                x.dots = x.h2 + 65
                x.m1 = x.dots + 15
                x.m2 = x.m1 + 64
                x.alarm = x.m2 + 61
        x.ampm = x.alarm

        s.icon_digitalClockDropShadow = {
            img = _loadImage(self, "Clocks/Digital/drop_shadow_digital.png"),
            align = 'center',
            padding = { 4, 0, 0, 0 },
            w = 62,
        }

        s.icon_alarm_on = {
            img = _loadImage(self, "Clocks/Digital/icon_alarm_digital.png")
        }
        s.icon_alarm_off = _uses(s.icon_alarm_on, {
            img = false
        })
        s.icon_digitalClockNoShadow = _uses(s.icon_digitalClockDropShadow, {
                img = false
        })

        s.icon_digitalClockHDivider = {
            w = WH_FILL,
            img = _loadImage(self, "Clocks/Digital/divider_hort_digital.png"),
        }

        s.icon_digitalClockVDivider = {
            w = 3,
            img = _loadImage(self, "Clocks/Digital/divider_vert_digital.png"),
            padding = { 0, 0, 0, 8 },
            align = 'center',
        }

        s.icon_digitalDots = {
            img = _loadImage(self, 'Clocks/Digital/clock_dots_digital.png'),
            align = 'center',
            w = 16,
            padding = { 0, 26, 0, 0 },
        }

        s.icon_digitalClockBlank = {
            img = false,
        }


        s.Clock = {
            bgImg = digitalClockBackground,
            h1 = _uses(_clockDigit, {
                x = x.h1,
            }),
            h1Shadow = _uses(_digitShadow, {
                x = x.h1,
            }),
            h2 = _uses(_clockDigit, {
                x = x.h2,
            }),
            h2Shadow = _uses(_digitShadow, {
                x = x.h2,
            }),
            dots = _uses(_clockDigit, {
                x = x.dots,
                w = 16,
            }),
            m1 = _uses(_clockDigit, {
                x = x.m1,
            }),
            m1Shadow = _uses(_digitShadow, {
                x = x.m1,
            }),
            m2 = _uses(_clockDigit, {
                x = x.m2,
            }),
            m2Shadow = _uses(_digitShadow, {
                x = x.m2,
            }),

            ampm = {
                position = LAYOUT_NONE,
                x = x.ampm,
                y = 112,
                font = _font(11),
                align = 'bottom',
                fg = { 0xcc, 0xcc, 0xcc },
            },
            alarm = {
                position = LAYOUT_NONE,
                x = x.alarm,
                y = 50,
            },
            horizDivider2 = { hidden = 1 },
            horizDivider = {
                position = LAYOUT_NONE,
                x = 0,
                y = 173,
            },
            today = { hidden = '1' },
            date = {
                position = LAYOUT_SOUTH,
                order = { 'dayofweek', 'vdivider1', 'dayofmonth', 'vdivider2', 'month' },
                w = WH_FILL,
                h = 65,
                padding = { 0, 10, 0, 0 },
                dayofweek = {
                    align = 'center',
                    w = 115,
                    h = WH_FILL,
                    font = _font(18),
                    fg = { 0xcc, 0xcc, 0xcc },
                    padding = { 0, 0, 0, 14 },
                },
                vdivider1 = {
                    align = 'center',
                    w = 2,
                },
                dayofmonth = {
                    font = _font(48),
                    w = 86,
                    h = WH_FILL,
                    align = 'center',
                    fg = { 0xcc, 0xcc, 0xcc },
                    padding = { 0, 0, 0, 12 },
                },
                vdivider2 = {
                    align = 'center',
                    w = 2,
                },
                month = {
                    font = _font(18),
                    w = WH_FILL,
                    h = WH_FILL,
                    align = 'center',
                    fg = { 0xcc, 0xcc, 0xcc },
                    padding = { 0, 0, 0, 14 },
                },
            },
        }
    
        local blackMask = Tile:fillColor(0x000000ff)
        s.ClockBlack = _uses(s.Clock, {
            bgImg = blackMask,
            horizDivider = { hidden = 1 },
            horizDivider2 = { hidden = 1 },
            today = { hidden = 1 },
            date = {
                order = { 'dayofweek', 'dayofmonth', 'month', 'year' },
            },
            h1Shadow = { hidden = 1 },
            h2Shadow = { hidden = 1 },
            m1Shadow = { hidden = 1 },
            m2Shadow = { hidden = 1 },
        })
        s.ClockTransparent = _uses(s.Clock, {
            bgImg = false,
            horizDivider = { hidden = 1 },
            horizDivider2 = { hidden = 1 },
            today = { hidden = 1 },
            date = {
                order = { 'dayofweek', 'dayofmonth', 'month', 'year' },
            },
            h1Shadow = { hidden = 1 },
            h2Shadow = { hidden = 1 },
            m1Shadow = { hidden = 1 },
            m2Shadow = { hidden = 1 },
        })
    elseif skinName == 'QVGAportraitSkin'  then
        local digitalClockBackground = Tile:loadImage(self.imgpath .. "Clocks/Digital/jive_clock_digital.png")
        local digitalClockDigit = {
            font = _font(90),
            fg = { 0xcc, 0xcc, 0xcc },
            w = WH_FILL,
        }
        local shadow = {
            w = 62,
        }
        local _clockDigit = {
            position = LAYOUT_NONE,
            font = _font(90),
            align = 'right',
            fg = { 0xcc, 0xcc, 0xcc },
            w = 62,
            y = 123,
            zOrder = 10,
        }
        local _digitShadow = _uses(_clockDigit, {
            y = 185,
            padding = { 4, 0, 0, 0 },
            zOrder = 1,
        })
    
        local x = {}
                x.h1 = 0
                x.h2 = x.h1 + 49
                x.dots = x.h2 + 62
                x.m1 = x.dots + 4
                x.m2 = x.m1 + 49
                x.alarm = x.h1

        s.icon_digitalClockDropShadow = {
            img = _loadImage(self, "Clocks/Digital/drop_shadow_digital.png"),
            align = 'center',
            padding = { 4, 0, 0, 0 },
        }

        s.icon_alarm_on = {
            img = _loadImage(self, "Clocks/Digital/icon_alarm_digital.png")
        }
        s.icon_alarm_off = _uses(s.icon_alarm_on, {
            img = false
        })
        s.icon_digitalClockNoShadow = _uses(s.icon_digitalClockDropShadow, {
            img = false
        })

        s.icon_digitalClockHDivider = {
            w = WH_FILL,
            img = _loadImage(self, "Clocks/Digital/divider_hort_digital.png"),
        }

        s.icon_digitalClockVDivider = {
            w = 3,
            img = _loadImage(self, "Clocks/Digital/divider_vert_digital.png"),
            align = 'center',
        }

        s.icon_digitalDots = {
            img = _loadImage(self, 'Clocks/Digital/clock_dots_digital.png'),
            align = 'center',
            w = 18,
            padding = { 0, 0, 0, 0 },
        }

        s.icon_digitalClockBlank = {
            img = false,
        }

        s.Clock = {
            bgImg = digitalClockBackground,
            h1 = _uses(_clockDigit, {
                x = x.h1,
            }),
            h1Shadow = _uses(_digitShadow, {
                x = x.h1,
            }),
            h2 = _uses(_clockDigit, {
                x = x.h2,
            }),
            h2Shadow = _uses(_digitShadow, {
                x = x.h2,
            }),
            dots = _uses(_clockDigit, {
                x = x.dots,
                w = 18,
                y = 143,
            }),
            m1 = _uses(_clockDigit, {
                x = x.m1,
            }),
            m1Shadow = _uses(_digitShadow, {
                x = x.m1,
            }),
            m2 = _uses(_clockDigit, {
                x = x.m2,
            }),
            m2Shadow = _uses(_digitShadow, {
                x = x.m2,
            }),

            today = {
                position = LAYOUT_NORTH,
                h = 83,
                zOrder = 2,
                w = WH_FILL,
                align = 'center',
                fg = { 0xcc, 0xcc, 0xcc },
                font = _font(20),
            },

            ampm = {
                position = LAYOUT_NONE,
                x = 203,
                y = 208,
                font = _font(14),
                align = 'bottom',
                fg = { 0xcc, 0xcc, 0xcc },
            },
            alarm = {
                position = LAYOUT_NONE,
                x = 12,
                y = 209,
            },
            horizDivider = {
                position = LAYOUT_NONE,
                x = 0,
                y = 320 - 84,
            },
            horizDivider2 = {
                position = LAYOUT_NONE,
                x = 0,
                y = 84,
            },
            date = {
                position = LAYOUT_SOUTH,
                order = { 'month', 'vdivider1', 'dayofmonth' },
                w = WH_FILL,
                h = 83,
                padding = { 0, 10, 0, 0 },
                dayofweek = { hidden = 1 },
                vdivider1 = {
                    align = 'center',
                    w = 2,
                    h = WH_FILL,
                },
                month = {
                    font = _font(20),
                    w = WH_FILL,
                    h = WH_FILL,
                    align = 'center',
                    fg = { 0xcc, 0xcc, 0xcc },
                    padding = { 2, 0, 0, 15 },
                },
                dayofmonth = {
                    font = _font(48),
                    w = 86,
                    h = WH_FILL,
                    align = 'center',
                    fg = { 0xcc, 0xcc, 0xcc },
                    padding = { 0, 0, 0, 15 },
                },
            },
        }
    
        local blackMask = Tile:fillColor(0x000000ff)
        s.ClockBlack = _uses(s.Clock, {
            bgImg = blackMask,
            horizDivider = { hidden = 1 },
            horizDivider2 = { hidden = 1 },
            date = {
                order = { 'month', 'dayofmonth' },
            },
            h1Shadow = { hidden = 1 },
            h2Shadow = { hidden = 1 },
            m1Shadow = { hidden = 1 },
            m2Shadow = { hidden = 1 },
        })
        s.ClockTransparent = _uses(s.Clock, {
            bgImg = false,
            horizDivider = { hidden = 1 },
            horizDivider2 = { hidden = 1 },
            date = {
                order = { 'month', 'dayofmonth' },
            },
            h1Shadow = { hidden = 1 },
            h2Shadow = { hidden = 1 },
            m1Shadow = { hidden = 1 },
            m2Shadow = { hidden = 1 },
        })
    
    end

    return s
end


-- ANALOG CLOCK
function Analog:getAnalogClockSkin(skinName)
    self.skinName = skinName
    self.imgpath = _imgpath(self)

    local analogClockBackground
    
    if skinName == 'QVGAlandscapeSkin' then
        analogClockBackground = Tile:loadImage(self.imgpath .. "Clocks/Analog/bb_wallpaper_clock_analog.png")

    elseif _isWQVGASkin(skinName) then
        analogClockBackground = Tile:loadImage(self.imgpath .. "Clocks/Analog/wallpaper_clock_analog.png")

    elseif _isJogglerSkin(skinName) or _isHDSkin(skinName) then
        local screen_width, screen_height = Framework:getScreenSize()
        local ratio = math.max(screen_width/800, screen_height/480)

        analogClockBackground = Surface:loadImage(self.imgpath .. "Clocks/Analog/wallpaper_clock_analog.png")
        analogClockBackground = analogClockBackground:zoom(ratio, ratio, 1)
        
        -- if the ratio of the resized background is different, we need to shift it accordingly
        if ratio ~= (800/480) then
	        local w, h = analogClockBackground:getSize()
	        
	        if w > screen_width then
		        local tmp = Surface:newRGB(screen_width, screen_height)
		        analogClockBackground:blit(tmp, (screen_width - w)/2, 0)
		        analogClockBackground:release()
		        analogClockBackground = tmp
		    elseif h > screen_height then
		        local tmp = Surface:newRGB(screen_width, screen_height)
		        analogClockBackground:blit(tmp, 0, (screen_height - h)/2)
		        analogClockBackground:release()
		        analogClockBackground = tmp
		    end
        end

    elseif skinName == 'QVGAportraitSkin' then
        analogClockBackground = Tile:loadImage(self.imgpath .. "Clocks/Analog/jive_wallpaper_clock_analog.png")

    end

    return {
    	Clock = {
	        bgImg = analogClockBackground,
	    } 
    }

end

function Analog:getSkinParams(skin)
    local screen_width, screen_height = Framework:getScreenSize()

    local params = {
        minuteHand = self.imgpath .. 'Clocks/Analog/clock_analog_min_hand.png',
        hourHand   = self.imgpath .. 'Clocks/Analog/clock_analog_hr_hand.png',
        alarmIcon  = self.imgpath .. 'Clocks/Analog/icon_alarm_analog.png',
        alarmX     = screen_width - 40,
        alarmY     = 15,
        ratio      = 1,
    }
    
    if _isWQVGASkin(skin) then
        params.alarmY = 18
        
    elseif _isJogglerSkin(skin) or _isHDSkin(skin) then
        params.alarmX = jogglerSkinAlarmX
        params.alarmY = jogglerSkinAlarmY
        params.ratio  = math.max(screen_width/800, screen_height/480)
        
        if _isHDSkin(skin) then
        	params.ratio = params.ratio * 1.5
        end
    end
    
    return params
end


--[[

=head1 LICENSE

Copyright 2010 Logitech. All Rights Reserved.

This file is licensed under BSD. Please see the LICENSE file for details.

=cut
--]]

