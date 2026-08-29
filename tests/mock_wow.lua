-- Minimale WoW-API-Attrappe, um die Addon-Dateien lokal zu laden und zu testen.

local NUMERIC = {
    GetFrameLevel = 5, GetWidth = 260, GetHeight = 24, GetAlpha = 1,
    GetValue = 0, GetScale = 1, GetEffectiveScale = 1, GetID = 1,
    GetNumPoints = 1, GetTop = 0, GetLeft = 0,
}
local BOOLEAN = {
    IsShown = true, IsVisible = true, IsPlaying = false, IsMouseEnabled = true,
    GetChecked = false, IsForbidden = false, IsObjectType = false, IsDragging = false,
}

local newObject

local function makeMethod(self, key)
    if NUMERIC[key] ~= nil then return function() return NUMERIC[key] end end
    if BOOLEAN[key] ~= nil then return function() return BOOLEAN[key] end end
    if key == "GetPoint"        then return function() return "CENTER", nil, "CENTER", 0, 0 end end
    if key == "GetFont"         then return function() return "Fonts\\FRIZQT__.TTF", 12, "" end end
    if key == "GetThumbTexture" or key == "GetStatusBarTexture"
       or key == "GetNormalTexture" or key == "GetRegions" then
        return function() return newObject("Texture") end
    end
    if key == "CreateTexture" or key == "CreateFontString" or key == "CreateAnimationGroup"
       or key == "CreateAnimation" or key == "CreateMaskTexture" then
        return function() return newObject(key) end
    end
    if key == "GetMinMaxValues" then return function() return 0, 100 end end
    if key == "GetText"         then return function() return "" end end
    if key == "GetName"         then return function(s) return s.__name end end
    if key == "GetParent"       then return function(s) return s.__parent end end
    return function() return nil end
end

local FrameMethods = {}

function FrameMethods:SetScript(handler, fn) self.__scripts[handler] = fn end
function FrameMethods:GetScript(handler)     return self.__scripts[handler] end
function FrameMethods:HookScript(handler, fn)
    local old = self.__scripts[handler]
    self.__scripts[handler] = function(...) if old then old(...) end fn(...) end
end
-- Ereignisse, die dieser Client nicht kennt. Wie im Spiel wirft der Versuch,
-- sie anzumelden - sonst koennte kein Test den gemeldeten Fehler nachstellen.
UNBEKANNTE_EREIGNISSE = { LEARNED_SPELL_IN_TAB = true }

C_EventUtils = {
    IsEventValid = function(event) return not UNBEKANNTE_EREIGNISSE[event] end,
}

function FrameMethods:RegisterEvent(event)
    if UNBEKANNTE_EREIGNISSE[event] then
        error(('Attempt to register unknown event "%s"'):format(event), 2)
    end
    self.__events[event] = true
end
function FrameMethods:RegisterUnitEvent(event)
    if UNBEKANNTE_EREIGNISSE[event] then
        error(('Attempt to register unknown event "%s"'):format(event), 2)
    end
    self.__events[event] = true
end
function FrameMethods:UnregisterEvent(event)     self.__events[event] = nil end
function FrameMethods:IsEventRegistered(event)   return self.__events[event] == true end
function FrameMethods:Fire(event, ...)
    local fn = self.__scripts.OnEvent
    if fn and self.__events[event] then fn(self, event, ...) end
end
function FrameMethods:Tick(elapsed)
    local fn = self.__scripts.OnUpdate
    if fn then fn(self, elapsed) end
end

local objectMT = {
    __index = function(tbl, key)
        local method = FrameMethods[key] or makeMethod(tbl, key)
        rawset(tbl, key, method)
        return method
    end,
}

newObject = function(objectType, name, parent)
    local obj = {
        __type = objectType, __name = name, __parent = parent,
        __scripts = {}, __events = {},
    }
    return setmetatable(obj, objectMT)
end

-- Globale Attrappen -------------------------------------------------------
function CreateFrame(frameType, name, parent, template)
    local f = newObject(frameType, name, parent)
    if name then _G[name] = f end
    return f
end

UIParent          = newObject("Frame", "UIParent")
GameTooltip       = newObject("GameTooltip", "GameTooltip")
GameFontNormal    = newObject("Font", "GameFontNormal")
ColorPickerFrame  = newObject("Frame", "ColorPickerFrame")
StaticPopupDialogs = {}
SlashCmdList      = {}
BackdropTemplateMixin = {}
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
YES, NO = "Ja", "Nein"

Settings = {
    RegisterCanvasLayoutCategory = function(frame, title)
        return { ID = title, GetID = function(self) return self.ID end }
    end,
    RegisterAddOnCategory = function() end,
    OpenToCategory = function(id) print("   [Settings] geöffnet: " .. tostring(id)) end,
}

function StaticPopup_Show(which) print("   [Popup] " .. tostring(which)) end
function PlaySound() end

C_AddOns   = { GetAddOnMetadata = function(_, key) return key == "Version" and "1.0.0" or nil end }
C_Spell    = {
    GetSpellCooldown = function() return { startTime = 0, duration = 0, isEnabled = true, modRate = 1 } end,
    GetSpellCharges  = function(id)
        if id == 119582 then
            return { currentCharges = 1, maxCharges = 2, cooldownStartTime = 100,
                     cooldownDuration = 15, chargeModRate = 1 }
        end
        return nil
    end,
    GetSpellTexture  = function() return "Interface\\Icons\\ability_monk_brewmaster_spec" end,
}
C_UnitAuras = {
    GetPlayerAuraBySpellID = function(id)
        if id == 386963 then return { applications = 4 } end
        return nil
    end,
}
C_SpecializationInfo = {}

local _time = 1000
function GetTime() _time = _time + 0.05 return _time end
function UnitClass()        return "Mönch", "MONK" end
function GetSpecialization() return 1 end
function GetSpecializationInfo() return 268 end
function UnitHealthMax()    return 1000000 end
function UnitHealth()       return 620000 end
function UnitStagger()      return 450000 end
function UnitGUID()         return "Player-1234-ABCDEF" end
function UnitAffectingCombat() return true end
function InCombatLockdown() return false end
function UnitInVehicle()    return false end
function UnitHasVehicleUI() return false end
function IsPlayerSpell()    return true end
function CombatLogGetCurrentEventInfo()
    return 0, "SPELL_DAMAGE", false, "Creature-1", "Boss", 0, 0, "Player-1234-ABCDEF"
end

-- Gesperrte Werte ab Midnight (12.0).
--
-- Wichtig fuer die Aussagekraft des Tests: Ein gesperrter Wert wird hier NICHT
-- als normale Zahl nachgebildet, sondern als Objekt, dessen Rechenoperationen
-- denselben Fehler werfen wie im Spiel. Sonst wuerde der Test den gemeldeten
-- Fehler gar nicht reproduzieren koennen.
local gesperrt = {}
local function sperrfehler()
    error("attempt to perform arithmetic on a secret number value, "
       .. "while execution tainted by 'MonkStaggerDisplay'", 2)
end
gesperrt.__index    = gesperrt
gesperrt.__add      = sperrfehler
gesperrt.__sub      = sperrfehler
gesperrt.__mul      = sperrfehler
gesperrt.__div      = sperrfehler
gesperrt.__unm      = sperrfehler
gesperrt.__lt       = sperrfehler
gesperrt.__le       = sperrfehler
gesperrt.__tostring = function() return "<secret number>" end

function issecretvalue(v)
    return type(v) == "table" and getmetatable(v) == gesperrt
end

function MarkSecret(zahl)
    return setmetatable({ wert = zahl }, gesperrt)
end

function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function strtrim(s) return (string.gsub(s, "^%s*(.-)%s*$", "%1")) end
function tostringall(...)
    local n = select("#", ...)
    local out = {}
    for i = 1, n do out[i] = tostring((select(i, ...))) end
    return unpack(out, 1, n)
end
string.join = function(sep, ...) return table.concat({ tostringall(...) }, sep) end
string.trim = strtrim
