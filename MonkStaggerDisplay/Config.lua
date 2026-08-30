--[[--------------------------------------------------------------------------
    Monk Stagger Display -- Config.lua

    Verantwortlich fuer:
      * Addon-weite Konstanten (Spec-ID, Spell-IDs, Stagger-Fenster)
      * API-Kompatibilitaets-Wrapper (C_Spell / C_UnitAuras / Spezialisierung)
      * SavedVariables: Defaults, Migration, Zugriff
      * Das Optionsfenster (Settings.RegisterCanvasLayoutCategory)
----------------------------------------------------------------------------]]

local addonName, ns = ...

--==========================================================================
-- 1. Metadaten & Konstanten
--==========================================================================

local GetAddOnMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata

ns.ADDON_NAME  = addonName
ns.ADDON_TITLE = "Monk Stagger Display"
ns.VERSION     = (GetAddOnMetadata and GetAddOnMetadata(addonName, "Version")) or "1.0.0"
ns.CHAT_PREFIX = "|cff00ff96[MSD]|r "

-- Braumeister-Spezialisierung
ns.SPEC_ID_BREWMASTER = 268

-- Stagger tickt ueber 10 Sekunden ab (alle 0.5s ein Tick)
ns.STAGGER_WINDOW = 10

ns.SPELL = {
    PURIFYING_BREW   = 119582,  -- Laeuterndes Gebraeu
    CELESTIAL_BREW   = 322507,  -- Himmlisches Gebraeu
    STAGGER_LIGHT    = 124275,  -- Leichter Stagger (Aura)
    STAGGER_MODERATE = 124274,  -- Mittlerer Stagger (Aura)
    STAGGER_HEAVY    = 124273,  -- Schwerer Stagger (Aura)
    PURIFIED_CHI     = 386963,  -- Gelaeutertes Chi (verstaerkt Himmlisches Gebraeu)
}

ns.LEVEL = { LIGHT = 1, MEDIUM = 2, HEAVY = 3 }

ns.LEVEL_NAME = {
    [ns.LEVEL.LIGHT]  = "Leicht",
    [ns.LEVEL.MEDIUM] = "Mittel",
    [ns.LEVEL.HEAVY]  = "Schwer",
}

ns.GLOW_STYLES = { "PULSE", "GLOW", "BOTH", "NONE" }
ns.GLOW_STYLE_NAME = {
    PULSE = "Pulsieren",
    GLOW  = "Leuchten",
    BOTH  = "Pulsieren + Leuchten",
    NONE  = "Aus",
}

ns.BAR_TEXTURES = {
    { name = "Blizzard",  path = "Interface\\TargetingFrame\\UI-StatusBar" },
    { name = "Glatt",     path = "Interface\\Buttons\\WHITE8X8" },
    { name = "Raid",      path = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
}

--==========================================================================
-- 2. API-Kompatibilitaet
--==========================================================================

-- Spezialisierung
local _GetSpecialization     = _G.GetSpecialization
    or (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization)
local _GetSpecializationInfo = _G.GetSpecializationInfo
    or (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo)

--- Liefert die aktuelle Spezialisierungs-ID des Spielers (oder nil).
function ns.GetPlayerSpecID()
    if not (_GetSpecialization and _GetSpecializationInfo) then return nil end
    local index = _GetSpecialization()
    if not index then return nil end
    local id = _GetSpecializationInfo(index)
    return id
end

--- Zauber-Abklingzeit. Rueckgabe: start, duration, enabled, modRate
function ns.GetSpellCooldownInfo(spellID)
    if C_Spell and C_Spell.GetSpellCooldown then
        local info = C_Spell.GetSpellCooldown(spellID)
        if info then
            return info.startTime or 0, info.duration or 0, info.isEnabled ~= false, info.modRate or 1
        end
        return 0, 0, true, 1
    end
    if _G.GetSpellCooldown then
        local start, duration, enabled, modRate = _G.GetSpellCooldown(spellID)
        return start or 0, duration or 0, enabled ~= 0 and enabled ~= false, modRate or 1
    end
    return 0, 0, true, 1
end

--- Ladungen eines Zaubers. Rueckgabe: charges, maxCharges, start, duration, modRate (oder nil)
function ns.GetSpellChargeInfo(spellID)
    if C_Spell and C_Spell.GetSpellCharges then
        local info = C_Spell.GetSpellCharges(spellID)
        if info then
            return info.currentCharges, info.maxCharges, info.cooldownStartTime,
                   info.cooldownDuration, info.chargeModRate or 1
        end
        return nil
    end
    if _G.GetSpellCharges then
        return _G.GetSpellCharges(spellID)
    end
    return nil
end

--- Zaubersymbol.
function ns.GetSpellIcon(spellID)
    if C_Spell and C_Spell.GetSpellTexture then
        return C_Spell.GetSpellTexture(spellID)
    end
    return _G.GetSpellTexture and _G.GetSpellTexture(spellID) or "Interface\\Icons\\INV_Misc_QuestionMark"
end

--- Kennt der Spieler den Zauber?
function ns.IsSpellAvailable(spellID)
    if _G.IsPlayerSpell then
        return IsPlayerSpell(spellID) and true or false
    end
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        return C_SpellBook.IsSpellKnown(spellID) and true or false
    end
    return true
end

--- Stapel einer eigenen Aura (0 wenn nicht vorhanden).
function ns.GetPlayerAuraStacks(spellID)
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
        if aura then
            return math.max(aura.applications or aura.charges or 1, 1), aura
        end
    end
    return 0, nil
end

--- Meldet ein Ereignis an, sofern dieser Client es kennt.
--- ------------------------------------------------------------------------
--- Blizzard entfernt und benennt Ereignisse um; LEARNED_SPELL_IN_TAB etwa
--- existiert in Midnight nicht mehr. RegisterEvent wirft bei einem
--- unbekannten Namen, und der Fehler reisst alles mit, was danach kommt.
--- C_EventUtils.IsEventValid ist der dafuer vorgesehene Weg; das pcall
--- daneben faengt auch den Fall ab, dass es die Pruefung selbst nicht gibt.
function ns.RegisterEventSafely(frame, event, unit)
    if C_EventUtils and C_EventUtils.IsEventValid
       and not C_EventUtils.IsEventValid(event) then
        ns.Debug("Ereignis in diesem Client unbekannt, übersprungen:", event)
        return false
    end
    local ok = pcall(function()
        if unit then
            frame:RegisterUnitEvent(event, unit)
        else
            frame:RegisterEvent(event)
        end
    end)
    if not ok then
        ns.Debug("Ereignis konnte nicht angemeldet werden:", event)
    end
    return ok
end

--- Gesperrte Werte ("secret values", ab Midnight/12.0)
--- ------------------------------------------------------------------------
--- Blizzard versieht seit 12.0 bestimmte Unit-Werte mit einem Sperrvermerk.
--- Ein getaintetes Addon darf sie weder in die Oberflaeche schreiben noch
--- damit rechnen - jeder Rechenversuch wirft einen Lua-Fehler. Betroffen ist
--- unter anderem UnitHealth("player"), waehrend UnitHealthMax weiterhin eine
--- normale Zahl liefert. Die Prueffunktion existiert in aelteren Clients
--- nicht, deshalb der Zugriff ueber _G.
local issecretvalue = _G.issecretvalue

function ns.IsSecret(value)
    if not issecretvalue then return false end
    local ok, result = pcall(issecretvalue, value)
    return ok and result or false
end

--- Liefert den Wert als Zahl, oder nil wenn er gesperrt bzw. keine Zahl ist.
--- Damit laesst sich an der Aufrufstelle sauber zwischen "null" und
--- "nicht lesbar" unterscheiden, statt blind mit 0 weiterzurechnen.
function ns.SafeNumber(value)
    if type(value) ~= "number" then return nil end
    if ns.IsSecret(value) then return nil end
    return value
end

--- Zahlen kompakt formatieren (1.2k / 3.4M).
function ns.FormatNumber(value)
    value = value or 0
    if value >= 1000000 then
        return string.format("%.2fM", value / 1000000)
    elseif value >= 1000 then
        return string.format("%.1fk", value / 1000)
    end
    return string.format("%d", value)
end

function ns.Print(...)
    print(ns.CHAT_PREFIX .. string.join(" ", tostringall(...)))
end

function ns.Debug(...)
    if ns.db and ns.db.debug then
        print("|cffff8800[MSD-Debug]|r " .. string.join(" ", tostringall(...)))
    end
end

--==========================================================================
-- 3. Standardeinstellungen
--==========================================================================

ns.defaults = {
    dbVersion = 1,
    enabled   = true,
    locked    = true,
    debug     = false,

    position = { point = "CENTER", relPoint = "CENTER", x = 0, y = -180 },

    bar = {
        width       = 260,
        height      = 24,
        scale       = 1.0,
        maxPct      = 100,   -- Skalenende der Leiste in % max. Leben
        texture     = 1,
        showTicks   = true,
        showSpark   = true,
        showBrews   = true,
        brewSize    = 30,
    },

    -- Schwellenwerte in % des maximalen Lebens
    thresholds = {
        light  = 30,   -- < 30 %  -> Leicht
        medium = 60,   -- 30-60 % -> Mittel, > 60 % -> Schwer
    },

    colors = {
        light      = { 0.20, 0.85, 0.30, 1.00 },
        medium     = { 0.95, 0.82, 0.15, 1.00 },
        heavy      = { 0.90, 0.18, 0.18, 1.00 },
        background = { 0.05, 0.05, 0.05, 0.75 },
        border     = { 0.00, 0.00, 0.00, 1.00 },
    },

    text = {
        showPercent  = true,
        showAbsolute = true,
        showDTPS     = true,
        showLevel    = true,
        fontSize     = 12,
        outline      = true,
    },

    visibility = {
        hideOutOfCombat  = true,
        showWhenStaggered= true,
        damageGrace      = 5.0,   -- Sekunden nach letztem eingehenden Schaden
        fadeDuration     = 0.45,
        alphaInCombat    = 1.0,
        alphaIdle        = 0.35,
        hideInVehicle    = true,
    },

    recommend = {
        enabled                  = true,
        purifyRemovalPct         = 50,   -- Anteil des Staggers, den Laeuterndes Gebraeu entfernt
        purifyThresholdPct       = 60,   -- ab welchem Stagger-% empfohlen wird
        purifyMinGainPct         = 5,    -- Mindestwert der Entfernung in % max. Leben
        capProtection            = true, -- vor ueberlaufenden Ladungen warnen
        capProtectionWindow      = 3,    -- Sekunden Vorlauf
        emergencyHealthPct       = 40,   -- Notfall-Purify unterhalb dieses Lebens-%
        celestialEnabled         = true,
        celestialMinStacks       = 3,    -- Gelaeutertes Chi Stapel fuer optimalen Schild
        celestialEmergencyHealthPct = 50,
        glowStyle                = "BOTH",
        sound                    = false,
        soundKit                 = 8959, -- Raid-Warnung
        soundThrottle            = 3.0,
    },
}

--==========================================================================
-- 4. SavedVariables
--==========================================================================

local Config = {}
ns.Config = Config

local function applyDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then target[key] = {} end
            applyDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
    return target
end

local function deepCopy(source)
    local copy = {}
    for key, value in pairs(source) do
        copy[key] = (type(value) == "table") and deepCopy(value) or value
    end
    return copy
end

ns.deepCopy = deepCopy

--- Laedt bzw. erstellt die SavedVariables. Wird aus Core bei ADDON_LOADED gerufen.
function Config:Initialize()
    if type(MonkStaggerDB) ~= "table" then MonkStaggerDB = {} end
    ns.db = applyDefaults(MonkStaggerDB, ns.defaults)

    -- Konsistenz: mittlere Schwelle muss ueber der leichten liegen
    if ns.db.thresholds.medium <= ns.db.thresholds.light then
        ns.db.thresholds.medium = math.min(100, ns.db.thresholds.light + 5)
    end

    ns.db.dbVersion = ns.defaults.dbVersion
    return ns.db
end

--- Alle Module ueber geaenderte Einstellungen informieren.
function Config:Notify()
    if ns.Display and ns.Display.ApplySettings then
        ns.Display:ApplySettings()
    end
    if ns.Core and ns.Core.ForceUpdate then
        ns.Core:ForceUpdate()
    end
    if self.panel and self.panel.Refresh then
        self.panel:Refresh()
    end
end

function Config:ResetPosition()
    ns.db.position = deepCopy(ns.defaults.position)
    if ns.Display and ns.Display.ApplyPosition then
        ns.Display:ApplyPosition()
    end
    ns.Print("Position zurückgesetzt.")
end

function Config:ResetAll()
    wipe(MonkStaggerDB)
    ns.db = applyDefaults(MonkStaggerDB, ns.defaults)
    if ns.Display and ns.Display.ApplyPosition then ns.Display:ApplyPosition() end
    self:Notify()
    ns.Print("Alle Einstellungen wurden auf Standardwerte zurückgesetzt.")
end

--- Anker sperren / entsperren.
function Config:SetLocked(locked)
    ns.db.locked = locked and true or false
    if ns.Display and ns.Display.ApplyLockState then
        ns.Display:ApplyLockState()
    end
    if ns.Core and ns.Core.ForceUpdate then ns.Core:ForceUpdate() end
    if self.panel and self.panel.Refresh then self.panel:Refresh() end
    ns.Print(ns.db.locked and "Ankerrahmen |cffff5555gesperrt|r."
                           or "Ankerrahmen |cff55ff55entsperrt|r – zum Verschieben ziehen.")
end

function Config:ToggleLock()
    self:SetLocked(not ns.db.locked)
end

--==========================================================================
-- 5. Widget-Helfer fuer das Optionsfenster
--==========================================================================

local WIDGET_WIDTH = 380

local function CreateHeader(parent, text)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    fs:SetText(text)
    fs:SetJustifyH("LEFT")

    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(0.35, 0.35, 0.35, 0.8)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -3)
    line:SetPoint("RIGHT", parent, "RIGHT", -20, 0)

    fs.__height = 26
    fs.__widget = fs
    return fs
end

local function CreateDescription(parent, text)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    fs:SetText(text)
    fs:SetJustifyH("LEFT")
    fs:SetWidth(WIDGET_WIDTH + 120)
    fs.__height = 16
    return fs
end

--- Checkbox ohne Template-Abhaengigkeit fuer den Text.
local function CreateCheckbox(panel, label, tooltip, getter, setter)
    local check = CreateFrame("CheckButton", nil, panel.content, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    -- Der Template-Text wird durch eine eigene Beschriftung ersetzt
    if type(check.Text) == "table" and check.Text.SetText then check.Text:SetText("") end

    local text = check:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("LEFT", check, "RIGHT", 4, 0)
    text:SetText(label)
    check.__label = text

    check:SetScript("OnClick", function(self)
        setter(self:GetChecked() and true or false)
        ns.Config:Notify()
    end)

    if tooltip then
        check:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label, 1, 1, 1)
            GameTooltip:AddLine(tooltip, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        check:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    check.__height = 26
    panel:AddRefresher(function() check:SetChecked(getter() and true or false) end)
    return check
end

--- Schieberegler, komplett selbst gebaut (keine Template-Abhaengigkeit).
local function CreateSlider(panel, label, minValue, maxValue, step, getter, setter, formatter)
    local container = CreateFrame("Frame", nil, panel.content)
    container:SetSize(WIDGET_WIDTH, 46)

    local title = container:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("TOPLEFT", 0, 0)
    title:SetText(label)

    local valueText = container:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    valueText:SetPoint("TOPRIGHT", 0, 0)

    local slider = CreateFrame("Slider", nil, container)
    slider:SetPoint("TOPLEFT", 0, -20)
    slider:SetSize(WIDGET_WIDTH, 16)
    slider:SetOrientation("HORIZONTAL")
    slider:SetHitRectInsets(0, 0, -8, -8)
    slider:SetMinMaxValues(minValue, maxValue)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")

    local thumb = slider:GetThumbTexture()
    thumb:SetSize(18, 26)

    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetColorTexture(0.16, 0.16, 0.16, 0.95)
    track:SetHeight(6)
    track:SetPoint("LEFT", slider, "LEFT", 0, 0)
    track:SetPoint("RIGHT", slider, "RIGHT", 0, 0)

    local trackBorder = slider:CreateTexture(nil, "BORDER")
    trackBorder:SetColorTexture(0.45, 0.45, 0.45, 0.6)
    trackBorder:SetHeight(8)
    trackBorder:SetPoint("LEFT", slider, "LEFT", -1, 0)
    trackBorder:SetPoint("RIGHT", slider, "RIGHT", 1, 0)

    local lowText = container:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    lowText:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, -1)
    lowText:SetText(tostring(minValue))

    local highText = container:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    highText:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", 0, -1)
    highText:SetText(tostring(maxValue))

    formatter = formatter or function(v) return tostring(v) end

    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value / step + 0.5) * step
        -- Rundungsfehler bei Nachkommaschritten glaetten
        value = tonumber(string.format("%.4f", value))
        valueText:SetText(formatter(value))
        if self.__refreshing then return end
        setter(value)
        ns.Config:Notify()
    end)

    container.__height = 62
    panel:AddRefresher(function()
        slider.__refreshing = true
        local v = getter()
        slider:SetValue(v)
        valueText:SetText(formatter(v))
        slider.__refreshing = false
    end)

    container.slider = slider
    return container
end

--- Farbwaehler (kompatibel mit alter und neuer ColorPicker-API).
local function OpenColorPicker(r, g, b, a, hasOpacity, onChange)
    local function readColor()
        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
        local na = 1
        if hasOpacity then
            if ColorPickerFrame.GetColorAlpha then
                na = ColorPickerFrame:GetColorAlpha()
            elseif _G.OpacitySliderFrame then
                na = 1 - _G.OpacitySliderFrame:GetValue()
            end
        end
        return nr, ng, nb, na
    end

    local info = {
        r = r, g = g, b = b,
        hasOpacity = hasOpacity,
        opacity    = a,
        swatchFunc  = function() onChange(readColor()) end,
        opacityFunc = function() onChange(readColor()) end,
        cancelFunc  = function() onChange(r, g, b, a) end,
    }

    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow(info)
    else
        -- Legacy-Pfad (vor 10.2.5): Opacity war invertiert
        info.opacity = 1 - a
        ColorPickerFrame.func         = info.swatchFunc
        ColorPickerFrame.opacityFunc  = info.opacityFunc
        ColorPickerFrame.cancelFunc   = info.cancelFunc
        ColorPickerFrame.hasOpacity   = hasOpacity
        ColorPickerFrame.opacity      = info.opacity
        ColorPickerFrame.previousValues = { r = r, g = g, b = b, opacity = info.opacity }
        ColorPickerFrame:SetColorRGB(r, g, b)
        ColorPickerFrame:Hide()
        ColorPickerFrame:Show()
    end
end

local function CreateColorSwatch(panel, label, tooltip, getter, setter, hasOpacity)
    local container = CreateFrame("Frame", nil, panel.content)
    container:SetSize(WIDGET_WIDTH, 24)

    local button = CreateFrame("Button", nil, container)
    button:SetSize(22, 22)
    button:SetPoint("LEFT", 2, 0)

    local border = button:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetColorTexture(0.6, 0.6, 0.6, 1)

    local checker = button:CreateTexture(nil, "BORDER")
    checker:SetPoint("TOPLEFT", 2, -2)
    checker:SetPoint("BOTTOMRIGHT", -2, 2)
    checker:SetColorTexture(0.25, 0.25, 0.25, 1)

    local swatch = button:CreateTexture(nil, "ARTWORK")
    swatch:SetPoint("TOPLEFT", 2, -2)
    swatch:SetPoint("BOTTOMRIGHT", -2, 2)

    local text = container:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("LEFT", button, "RIGHT", 8, 0)
    text:SetText(label)

    local function refresh()
        local r, g, b, a = getter()
        swatch:SetColorTexture(r, g, b, a or 1)
    end

    button:SetScript("OnClick", function()
        local r, g, b, a = getter()
        OpenColorPicker(r, g, b, a or 1, hasOpacity, function(nr, ng, nb, na)
            setter(nr, ng, nb, na)
            refresh()
            ns.Config:Notify()
        end)
    end)

    if tooltip then
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label, 1, 1, 1)
            GameTooltip:AddLine(tooltip, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    container.__height = 28
    panel:AddRefresher(refresh)
    return container
end

--- Durchschalt-Button (Ersatz fuer Dropdown, versionsunabhaengig).
local function CreateCycleButton(panel, label, values, displayMap, getter, setter)
    local container = CreateFrame("Frame", nil, panel.content)
    container:SetSize(WIDGET_WIDTH, 26)

    local text = container:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    text:SetPoint("LEFT", 0, 0)
    text:SetText(label)

    local button = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
    button:SetSize(190, 22)
    button:SetPoint("RIGHT", 0, 0)

    local function refresh()
        local current = getter()
        button:SetText((displayMap and displayMap[current]) or tostring(current))
    end

    button:SetScript("OnClick", function()
        local current = getter()
        local index = 1
        for i, v in ipairs(values) do
            if v == current then index = i break end
        end
        index = index % #values + 1
        setter(values[index])
        refresh()
        ns.Config:Notify()
    end)

    container.__height = 30
    panel:AddRefresher(refresh)
    return container
end

local function CreateActionButton(panel, label, tooltip, onClick, width)
    local button = CreateFrame("Button", nil, panel.content, "UIPanelButtonTemplate")
    button:SetSize(width or 150, 24)
    button:SetText(label)
    button:SetScript("OnClick", onClick)

    if tooltip then
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label, 1, 1, 1)
            GameTooltip:AddLine(tooltip, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    button.__height = 30
    return button
end

--==========================================================================
-- 6. Optionsfenster
--==========================================================================

function Config:BuildOptionsPanel()
    if self.panel then return self.panel end

    local panel = CreateFrame("Frame")
    panel.name = ns.ADDON_TITLE
    panel.refreshers = {}
    self.panel = panel

    function panel.AddRefresher(frame, fn)
        table.insert(frame.refreshers, fn)
    end

    function panel.Refresh(frame)
        for _, fn in ipairs(frame.refreshers) do
            local ok, err = pcall(fn)
            if not ok then ns.Debug("Refresher-Fehler:", err) end
        end
    end

    -- Kopfzeile
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(ns.ADDON_TITLE .. "  |cff888888v" .. ns.VERSION .. "|r")

    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    subtitle:SetPoint("RIGHT", panel, "RIGHT", -20, 0)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText("Stagger-Überwachung für Braumeister-Mönche. Befehle: |cff00ff96/msd|r oder |cff00ff96/stagger|r")

    -- Scrollbereich
    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -12)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, 16)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    panel.content = content
    panel.scroll  = scroll

    scroll:SetScript("OnSizeChanged", function(_, width)
        content:SetWidth(math.max(width or 1, 1))
    end)

    ----------------------------------------------------------------------
    -- Widgets definieren
    ----------------------------------------------------------------------
    local db = function() return ns.db end
    local rows = {}
    local function add(widget, indent, spacing)
        table.insert(rows, { widget = widget, indent = indent or 0, spacing = spacing or 4 })
        return widget
    end

    -- --- Allgemein ---
    add(CreateHeader(content, "Allgemein"), 0, 8)
    add(CreateCheckbox(panel, "Addon aktiviert",
        "Deaktiviert die komplette Anzeige, ohne die Einstellungen zu verlieren.",
        function() return db().enabled end,
        function(v) db().enabled = v end), 8)
    add(CreateCheckbox(panel, "Ankerrahmen gesperrt",
        "Entsperren, um die Leiste mit der Maus zu verschieben.",
        function() return db().locked end,
        function(v) Config:SetLocked(v) end), 8)
    add(CreateCheckbox(panel, "Debug-Ausgaben",
        "Schreibt zusätzliche Informationen in den Chat.",
        function() return db().debug end,
        function(v) db().debug = v end), 8, 10)

    -- --- Darstellung ---
    add(CreateHeader(content, "Darstellung"), 0, 8)
    add(CreateSlider(panel, "Breite", 100, 600, 5,
        function() return db().bar.width end,
        function(v) db().bar.width = v end,
        function(v) return v .. " px" end), 8)
    add(CreateSlider(panel, "Höhe", 10, 80, 1,
        function() return db().bar.height end,
        function(v) db().bar.height = v end,
        function(v) return v .. " px" end), 8)
    add(CreateSlider(panel, "Skalierung", 0.5, 2.0, 0.05,
        function() return db().bar.scale end,
        function(v) db().bar.scale = v end,
        function(v) return string.format("%.2f", v) end), 8)
    add(CreateSlider(panel, "Skalenende der Leiste", 40, 200, 5,
        function() return db().bar.maxPct end,
        function(v) db().bar.maxPct = v end,
        function(v) return v .. " % max. Leben" end), 8)
    add(CreateCycleButton(panel, "Leistentextur",
        { 1, 2, 3 },
        { [1] = ns.BAR_TEXTURES[1].name, [2] = ns.BAR_TEXTURES[2].name, [3] = ns.BAR_TEXTURES[3].name },
        function() return db().bar.texture end,
        function(v) db().bar.texture = v end), 8)
    add(CreateCheckbox(panel, "Schwellenmarkierungen anzeigen", nil,
        function() return db().bar.showTicks end,
        function(v) db().bar.showTicks = v end), 8)
    add(CreateCheckbox(panel, "Leuchtpunkt am Leistenende", nil,
        function() return db().bar.showSpark end,
        function(v) db().bar.showSpark = v end), 8)
    add(CreateCheckbox(panel, "Gebräu-Symbole anzeigen",
        "Zeigt Läuterndes Gebräu und Himmlisches Gebräu mit Abklingzeit unter der Leiste.",
        function() return db().bar.showBrews end,
        function(v) db().bar.showBrews = v end), 8)
    add(CreateSlider(panel, "Größe der Gebräu-Symbole", 16, 64, 1,
        function() return db().bar.brewSize end,
        function(v) db().bar.brewSize = v end,
        function(v) return v .. " px" end), 8, 10)

    -- --- Schwellenwerte ---
    add(CreateHeader(content, "Stagger-Schwellenwerte"), 0, 4)
    add(CreateDescription(content,
        "Prozentsatz des maximalen Lebens. Unterhalb der ersten Schwelle ist der Stagger leicht (grün), "
     .. "dazwischen mittel (gelb), darüber schwer (rot)."), 8, 8)
    add(CreateSlider(panel, "Leicht bis", 5, 95, 1,
        function() return db().thresholds.light end,
        function(v)
            db().thresholds.light = v
            if db().thresholds.medium <= v then db().thresholds.medium = math.min(100, v + 5) end
        end,
        function(v) return v .. " %" end), 8)
    add(CreateSlider(panel, "Mittel bis", 10, 150, 1,
        function() return db().thresholds.medium end,
        function(v)
            db().thresholds.medium = v
            if db().thresholds.light >= v then db().thresholds.light = math.max(1, v - 5) end
        end,
        function(v) return v .. " %" end), 8, 10)

    -- --- Farben ---
    add(CreateHeader(content, "Farben"), 0, 8)
    add(CreateColorSwatch(panel, "Leichter Stagger", nil,
        function() return unpack(db().colors.light) end,
        function(r, g, b, a) db().colors.light = { r, g, b, a } end, true), 8)
    add(CreateColorSwatch(panel, "Mittlerer Stagger", nil,
        function() return unpack(db().colors.medium) end,
        function(r, g, b, a) db().colors.medium = { r, g, b, a } end, true), 8)
    add(CreateColorSwatch(panel, "Schwerer Stagger", nil,
        function() return unpack(db().colors.heavy) end,
        function(r, g, b, a) db().colors.heavy = { r, g, b, a } end, true), 8)
    add(CreateColorSwatch(panel, "Hintergrund", nil,
        function() return unpack(db().colors.background) end,
        function(r, g, b, a) db().colors.background = { r, g, b, a } end, true), 8)
    add(CreateColorSwatch(panel, "Rahmen", nil,
        function() return unpack(db().colors.border) end,
        function(r, g, b, a) db().colors.border = { r, g, b, a } end, true), 8, 10)

    -- --- Text ---
    add(CreateHeader(content, "Text"), 0, 8)
    add(CreateCheckbox(panel, "Prozentwert anzeigen", nil,
        function() return db().text.showPercent end,
        function(v) db().text.showPercent = v end), 8)
    add(CreateCheckbox(panel, "Absoluten Staggerwert anzeigen", nil,
        function() return db().text.showAbsolute end,
        function(v) db().text.showAbsolute = v end), 8)
    add(CreateCheckbox(panel, "Schaden pro Sekunde (DTPS) anzeigen",
        "Geschätzter Schaden, den der aktuelle Stagger pro Sekunde verursacht.",
        function() return db().text.showDTPS end,
        function(v) db().text.showDTPS = v end), 8)
    add(CreateCheckbox(panel, "Stufenname anzeigen (Leicht/Mittel/Schwer)", nil,
        function() return db().text.showLevel end,
        function(v) db().text.showLevel = v end), 8)
    add(CreateCheckbox(panel, "Schrift mit Kontur", nil,
        function() return db().text.outline end,
        function(v) db().text.outline = v end), 8)
    add(CreateSlider(panel, "Schriftgröße", 8, 24, 1,
        function() return db().text.fontSize end,
        function(v) db().text.fontSize = v end,
        function(v) return v .. " pt" end), 8, 10)

    -- --- Sichtbarkeit ---
    add(CreateHeader(content, "Sichtbarkeit"), 0, 8)
    add(CreateCheckbox(panel, "Außerhalb des Kampfes ausblenden",
        "Blendet die Anzeige vollständig aus, sobald der Kampf endet und kein Stagger mehr aktiv ist. "
     .. "Ist die Option aus, gilt stattdessen die Deckkraft im Ruhezustand.",
        function() return db().visibility.hideOutOfCombat end,
        function(v) db().visibility.hideOutOfCombat = v end), 8)
    add(CreateCheckbox(panel, "Bei aktivem Stagger immer einblenden", nil,
        function() return db().visibility.showWhenStaggered end,
        function(v) db().visibility.showWhenStaggered = v end), 8)
    add(CreateCheckbox(panel, "In Fahrzeugen ausblenden", nil,
        function() return db().visibility.hideInVehicle end,
        function(v) db().visibility.hideInVehicle = v end), 8)
    add(CreateSlider(panel, "Nachlaufzeit nach Schaden", 0, 15, 0.5,
        function() return db().visibility.damageGrace end,
        function(v) db().visibility.damageGrace = v end,
        function(v) return string.format("%.1f s", v) end), 8)
    add(CreateSlider(panel, "Ausblenddauer", 0, 2, 0.05,
        function() return db().visibility.fadeDuration end,
        function(v) db().visibility.fadeDuration = v end,
        function(v) return string.format("%.2f s", v) end), 8)
    add(CreateSlider(panel, "Deckkraft im Kampf", 0.1, 1.0, 0.05,
        function() return db().visibility.alphaInCombat end,
        function(v) db().visibility.alphaInCombat = v end,
        function(v) return string.format("%d %%", v * 100) end), 8)
    add(CreateSlider(panel, "Deckkraft im Ruhezustand", 0.0, 1.0, 0.05,
        function() return db().visibility.alphaIdle end,
        function(v) db().visibility.alphaIdle = v end,
        function(v) return string.format("%d %%", v * 100) end), 8, 10)

    -- --- Empfehlungen ---
    add(CreateHeader(content, "Empfehlungs-Engine"), 0, 4)
    add(CreateDescription(content,
        "Hebt Läuterndes Gebräu bzw. Himmlisches Gebräu hervor, sobald der Einsatz den größten Wert bringt."), 8, 8)
    add(CreateCheckbox(panel, "Empfehlungen aktiviert", nil,
        function() return db().recommend.enabled end,
        function(v) db().recommend.enabled = v end), 8)
    add(CreateSlider(panel, "Läutern ab Stagger", 10, 150, 1,
        function() return db().recommend.purifyThresholdPct end,
        function(v) db().recommend.purifyThresholdPct = v end,
        function(v) return v .. " % max. Leben" end), 8)
    add(CreateSlider(panel, "Mindestwert der Läuterung", 1, 40, 0.5,
        function() return db().recommend.purifyMinGainPct end,
        function(v) db().recommend.purifyMinGainPct = v end,
        function(v) return string.format("%.1f %% max. Leben", v) end), 8)
    add(CreateSlider(panel, "Läuterndes Gebräu entfernt", 20, 80, 1,
        function() return db().recommend.purifyRemovalPct end,
        function(v) db().recommend.purifyRemovalPct = v end,
        function(v) return v .. " % des Staggers" end), 8)
    add(CreateCheckbox(panel, "Vor überlaufenden Ladungen warnen",
        "Empfiehlt Läuterndes Gebräu, bevor eine Ladung durch das Ladungslimit verfällt.",
        function() return db().recommend.capProtection end,
        function(v) db().recommend.capProtection = v end), 8)
    add(CreateSlider(panel, "Vorlauf für Ladungswarnung", 0.5, 10, 0.5,
        function() return db().recommend.capProtectionWindow end,
        function(v) db().recommend.capProtectionWindow = v end,
        function(v) return string.format("%.1f s", v) end), 8)
    add(CreateSlider(panel, "Notfall-Läuterung unter", 5, 90, 1,
        function() return db().recommend.emergencyHealthPct end,
        function(v) db().recommend.emergencyHealthPct = v end,
        function(v) return v .. " % Leben" end), 8)
    add(CreateCheckbox(panel, "Himmlisches Gebräu empfehlen", nil,
        function() return db().recommend.celestialEnabled end,
        function(v) db().recommend.celestialEnabled = v end), 8)
    add(CreateSlider(panel, "Benötigte Stapel Geläutertes Chi", 1, 10, 1,
        function() return db().recommend.celestialMinStacks end,
        function(v) db().recommend.celestialMinStacks = v end,
        function(v) return v .. " Stapel" end), 8)
    add(CreateSlider(panel, "Notfall-Schild unter", 5, 90, 1,
        function() return db().recommend.celestialEmergencyHealthPct end,
        function(v) db().recommend.celestialEmergencyHealthPct = v end,
        function(v) return v .. " % Leben" end), 8)
    add(CreateCycleButton(panel, "Hervorhebung", ns.GLOW_STYLES, ns.GLOW_STYLE_NAME,
        function() return db().recommend.glowStyle end,
        function(v) db().recommend.glowStyle = v end), 8)
    add(CreateCheckbox(panel, "Signalton bei Empfehlung", nil,
        function() return db().recommend.sound end,
        function(v) db().recommend.sound = v end), 8, 12)

    -- --- Aktionen ---
    add(CreateHeader(content, "Aktionen"), 0, 8)
    add(CreateActionButton(panel, "Testanzeige umschalten",
        "Simuliert einen Stagger-Verlauf, um Position und Farben zu prüfen.",
        function() ns.Core:ToggleTestMode() end, 190), 8)
    add(CreateActionButton(panel, "Anker entsperren / sperren",
        "Schaltet den beweglichen Ankerrahmen frei.",
        function() Config:ToggleLock() end, 190), 8)
    add(CreateActionButton(panel, "Position zurücksetzen", nil,
        function() Config:ResetPosition() end, 190), 8)
    add(CreateActionButton(panel, "Alles zurücksetzen",
        "Setzt sämtliche Einstellungen auf die Standardwerte zurück.",
        function()
            StaticPopup_Show("MONKSTAGGER_RESET_ALL")
        end, 190), 8, 20)

    ----------------------------------------------------------------------
    -- Layout: alle Zeilen untereinander anordnen
    ----------------------------------------------------------------------
    local y = -8
    for _, row in ipairs(rows) do
        local widget = row.widget
        widget:ClearAllPoints()
        widget:SetPoint("TOPLEFT", content, "TOPLEFT", 8 + row.indent, y)
        y = y - (widget.__height or 24) - row.spacing
    end
    content:SetHeight(math.abs(y) + 20)

    -- Canvas-Hooks der Settings-API
    panel.OnRefresh = function() panel:Refresh() end
    panel.OnCommit  = function() end
    panel.OnDefault = function() Config:ResetAll() end

    panel:SetScript("OnShow", function(frame) frame:Refresh() end)

    return panel
end

--==========================================================================
-- 7. Registrierung in den Blizzard-Einstellungen
--==========================================================================

function Config:RegisterSettings()
    if self.category then return self.category end

    local panel = self:BuildOptionsPanel()

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, ns.ADDON_TITLE)
        -- Wichtig: category.ID NICHT ueberschreiben. Blizzard vergibt hier eine
        -- Zahl, und genau die erwartet C_SettingsUtil.OpenSettingsPanel spaeter.
        Settings.RegisterAddOnCategory(category)
        self.category = category
    elseif InterfaceOptions_AddCategory then
        -- Fallback fuer aeltere Clients
        InterfaceOptions_AddCategory(panel)
        self.category = panel
    end

    -- Bestaetigungsdialog fuer "Alles zuruecksetzen"
    StaticPopupDialogs["MONKSTAGGER_RESET_ALL"] = {
        text = ns.ADDON_TITLE .. "\n\nAlle Einstellungen wirklich auf die Standardwerte zurücksetzen?",
        button1 = YES or "Ja",
        button2 = NO or "Nein",
        OnAccept = function() Config:ResetAll() end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }

    return self.category
end

--- Numerische ID einer Settings-Kategorie ermitteln.
--- Seit Midnight (12.0) reicht Settings.OpenToCategory den Wert unveraendert
--- an C_SettingsUtil.OpenSettingsPanel weiter, und das akzeptiert nur eine
--- Zahl im Int32-Bereich. Ein Anzeigename als ID wirft dort einen Fehler.
local function GetCategoryID(category)
    if type(category) ~= "table" then return nil end

    local id
    if category.GetID then
        local ok, value = pcall(category.GetID, category)
        if ok then id = value end
    end
    if id == nil then id = category.ID end

    return type(id) == "number" and id or nil
end

--- Optionsfenster oeffnen.
function Config:OpenSettings()
    if not self.category then self:RegisterSettings() end

    if Settings and Settings.OpenToCategory then
        local id = GetCategoryID(self.category)
        if id and pcall(Settings.OpenToCategory, id) then return end
        -- Aeltere Clients loesen den Anzeigenamen selbst auf.
        if pcall(Settings.OpenToCategory, ns.ADDON_TITLE) then return end
    elseif InterfaceOptionsFrame_OpenToCategory and self.panel then
        InterfaceOptionsFrame_OpenToCategory(self.panel)
        InterfaceOptionsFrame_OpenToCategory(self.panel) -- Blizzard-Bug: zweimal noetig
        return
    end

    ns.Print("Optionsfenster konnte nicht geöffnet werden.")
end
