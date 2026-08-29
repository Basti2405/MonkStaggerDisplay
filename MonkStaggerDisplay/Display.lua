--[[--------------------------------------------------------------------------
    Monk Stagger Display -- Display.lua

    Verantwortlich fuer saemtliche Rahmen und Texturen:
      * beweglicher Ankerrahmen mit persistenter Position
      * Stagger-Leiste inkl. Schwellenmarkierungen und Text
      * Gebraeu-Symbole (Laeuterndes / Himmlisches Gebraeu) mit Abklingzeit
      * Hervorhebung (Pulsieren / Leuchten) der Empfehlungs-Engine
      * weiches Ein- und Ausblenden
----------------------------------------------------------------------------]]

local _, ns = ...

local Display = {}
ns.Display = Display

local FALLBACK_FONT = "Fonts\\FRIZQT__.TTF"
local GLOW_TEXTURE  = "Interface\\SpellActivationOverlay\\IconAlert"
local GLOW_COORDS   = { 0.00781250, 0.50781250, 0.27734375, 0.53515625 }

--==========================================================================
-- Hilfsfunktionen
--==========================================================================

local function GetFontPath()
    local base = _G.STANDARD_TEXT_FONT
    if type(base) == "string" and base ~= "" then return base end
    if GameFontNormal then
        local path = GameFontNormal:GetFont()
        if path then return path end
    end
    return FALLBACK_FONT
end

local function StyleFontString(fs)
    local text = ns.db.text
    fs:SetFont(GetFontPath(), text.fontSize, text.outline and "OUTLINE" or "")
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 0.9)
end

local function GetBarTexture()
    local entry = ns.BAR_TEXTURES[ns.db.bar.texture] or ns.BAR_TEXTURES[1]
    return entry.path
end

--- Erzeugt eine wiederverwendbare Hervorhebung ueber einem Rahmen.
local function CreateHighlight(parent, padding)
    local glow = CreateFrame("Frame", nil, parent)
    glow:SetPoint("TOPLEFT", parent, "TOPLEFT", -(padding or 6), (padding or 6))
    glow:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", (padding or 6), -(padding or 6))
    glow:SetFrameLevel(parent:GetFrameLevel() + 6)
    glow:Hide()

    -- Weiches Leuchten (Spell-Alert-Optik)
    local alert = glow:CreateTexture(nil, "OVERLAY")
    alert:SetAllPoints()
    alert:SetTexture(GLOW_TEXTURE)
    alert:SetTexCoord(unpack(GLOW_COORDS))
    alert:SetBlendMode("ADD")
    alert:SetAlpha(0.85)
    glow.alert = alert

    -- Zusaetzlicher farbiger Schleier fuer den Pulseffekt
    local flash = glow:CreateTexture(nil, "ARTWORK")
    flash:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    flash:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    flash:SetColorTexture(1, 1, 1, 1)
    flash:SetBlendMode("ADD")
    flash:SetAlpha(0.25)
    glow.flash = flash

    -- Pulsanimation (Alpha)
    local pulse = glow:CreateAnimationGroup()
    pulse:SetLooping("REPEAT")
    local fadeIn = pulse:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0.20); fadeIn:SetToAlpha(1.00); fadeIn:SetDuration(0.40); fadeIn:SetOrder(1)
    local fadeOut = pulse:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1.00); fadeOut:SetToAlpha(0.20); fadeOut:SetDuration(0.40); fadeOut:SetOrder(2)
    glow.pulse = pulse

    function glow:SetColor(r, g, b)
        self.flash:SetColorTexture(r, g, b, 1)
        self.alert:SetVertexColor(r, g, b)
    end

    function glow:Start(style)
        style = style or "BOTH"
        if style == "NONE" then self:Stop() return end

        self.alert:SetShown(style == "GLOW" or style == "BOTH")
        self.flash:SetShown(style == "PULSE" or style == "BOTH")

        if not self:IsShown() then self:Show() end

        -- "Leuchten" bleibt statisch, "Pulsieren" animiert die Deckkraft
        if style == "PULSE" or style == "BOTH" then
            if not self.pulse:IsPlaying() then
                self:SetAlpha(1)
                self.pulse:Play()
            end
        else
            if self.pulse:IsPlaying() then self.pulse:Stop() end
            self:SetAlpha(1)
        end
    end

    function glow:Stop()
        if self.pulse:IsPlaying() then self.pulse:Stop() end
        self:SetAlpha(1)
        if self:IsShown() then self:Hide() end
    end

    return glow
end

--- Erzeugt ein Gebraeu-Symbol mit Abklingzeit und Ladungsanzeige.
local function CreateBrewIcon(parent, spellID)
    local button = CreateFrame("Frame", nil, parent)
    button.spellID = spellID

    local border = button:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetColorTexture(0, 0, 0, 1)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", -1, 1)
    icon:SetTexture(ns.GetSpellIcon(spellID))
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.icon = icon

    local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cooldown:SetAllPoints(icon)
    cooldown:SetDrawEdge(false)
    cooldown:SetHideCountdownNumbers(false)
    button.cooldown = cooldown

    local count = button:CreateFontString(nil, "OVERLAY")
    count:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 1)
    button.count = count

    button.glow = CreateHighlight(button, 7)

    -- Tooltip beim Ueberfahren
    button:SetScript("OnEnter", function(self)
        if not self:IsMouseEnabled() then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        if GameTooltip.SetSpellByID then
            GameTooltip:SetSpellByID(self.spellID)
        end
        if self.reason then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cff00ff96Empfehlung:|r " .. self.reason, 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return button
end

--==========================================================================
-- Aufbau
--==========================================================================

function Display:Initialize()
    if self.initialized then return end

    local backdropTemplate = BackdropTemplateMixin and "BackdropTemplate" or nil

    ------------------------------------------------------------------
    -- Ankerrahmen
    ------------------------------------------------------------------
    local frame = CreateFrame("Frame", "MonkStaggerDisplayFrame", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetAlpha(0)
    frame:Hide()
    self.frame = frame

    frame:SetScript("OnDragStart", function(anchor)
        if not ns.db.locked then anchor:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(anchor)
        anchor:StopMovingOrSizing()
        Display:SavePosition()
    end)
    frame:SetScript("OnMouseUp", function(_, mouseButton)
        if mouseButton == "RightButton" and not ns.db.locked then
            ns.Config:SetLocked(true)
        end
    end)

    ------------------------------------------------------------------
    -- Leiste
    ------------------------------------------------------------------
    local holder = CreateFrame("Frame", nil, frame, backdropTemplate)
    holder:SetPoint("TOPLEFT")
    holder:SetPoint("TOPRIGHT")
    if holder.SetBackdrop then
        holder:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
            insets   = { left = 1, right = 1, top = 1, bottom = 1 },
        })
    end
    self.holder = holder

    local bar = CreateFrame("StatusBar", nil, holder)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("BOTTOMRIGHT", -1, 1)
    bar:SetMinMaxValues(0, 100)
    bar:SetValue(0)
    self.bar = bar

    local barBG = bar:CreateTexture(nil, "BACKGROUND")
    barBG:SetAllPoints()
    barBG:SetColorTexture(0, 0, 0, 0.35)
    self.barBG = barBG

    local spark = bar:CreateTexture(nil, "OVERLAY")
    spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    spark:SetBlendMode("ADD")
    spark:SetWidth(16)
    self.spark = spark

    -- Schwellenmarkierungen
    self.tickLight  = bar:CreateTexture(nil, "OVERLAY")
    self.tickMedium = bar:CreateTexture(nil, "OVERLAY")
    for _, tick in ipairs({ self.tickLight, self.tickMedium }) do
        tick:SetColorTexture(1, 1, 1, 0.55)
        tick:SetWidth(1)
    end

    ------------------------------------------------------------------
    -- Textebene
    ------------------------------------------------------------------
    local textLayer = CreateFrame("Frame", nil, bar)
    textLayer:SetAllPoints()
    textLayer:SetFrameLevel(bar:GetFrameLevel() + 3)
    self.textLayer = textLayer

    self.textLeft = textLayer:CreateFontString(nil, "OVERLAY")
    self.textLeft:SetPoint("LEFT", 4, 0)
    self.textLeft:SetJustifyH("LEFT")

    self.textCenter = textLayer:CreateFontString(nil, "OVERLAY")
    self.textCenter:SetPoint("CENTER", 0, 0)
    self.textCenter:SetJustifyH("CENTER")

    self.textRight = textLayer:CreateFontString(nil, "OVERLAY")
    self.textRight:SetPoint("RIGHT", -4, 0)
    self.textRight:SetJustifyH("RIGHT")

    ------------------------------------------------------------------
    -- Hervorhebung der Leiste
    ------------------------------------------------------------------
    self.barGlow = CreateHighlight(holder, 5)

    ------------------------------------------------------------------
    -- Gebraeu-Symbole
    ------------------------------------------------------------------
    local brews = CreateFrame("Frame", nil, frame)
    brews:SetPoint("TOPLEFT", holder, "BOTTOMLEFT", 0, -4)
    brews:SetPoint("TOPRIGHT", holder, "BOTTOMRIGHT", 0, -4)
    self.brewContainer = brews

    self.purifyIcon   = CreateBrewIcon(brews, ns.SPELL.PURIFYING_BREW)
    self.celestialIcon= CreateBrewIcon(brews, ns.SPELL.CELESTIAL_BREW)
    self.purifyIcon:SetPoint("TOPLEFT", brews, "TOPLEFT", 0, 0)
    self.celestialIcon:SetPoint("TOPLEFT", self.purifyIcon, "TOPRIGHT", 6, 0)

    -- Empfehlungstext neben den Symbolen
    self.hintText = brews:CreateFontString(nil, "OVERLAY")
    self.hintText:SetPoint("LEFT", self.celestialIcon, "RIGHT", 8, 0)
    self.hintText:SetPoint("RIGHT", brews, "RIGHT", 0, 0)
    self.hintText:SetJustifyH("LEFT")

    ------------------------------------------------------------------
    -- Overlay im entsperrten Zustand
    ------------------------------------------------------------------
    local unlock = CreateFrame("Frame", nil, frame)
    unlock:SetAllPoints()
    unlock:SetFrameLevel(frame:GetFrameLevel() + 20)
    unlock:Hide()
    self.unlockOverlay = unlock

    local unlockBG = unlock:CreateTexture(nil, "BACKGROUND")
    unlockBG:SetAllPoints()
    unlockBG:SetColorTexture(0.1, 0.7, 0.4, 0.25)

    local unlockText = unlock:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    unlockText:SetPoint("CENTER")
    unlockText:SetText("|cff00ff96Ziehen zum Verschieben|r\nRechtsklick sperrt")
    unlockText:SetJustifyH("CENTER")

    ------------------------------------------------------------------
    self.initialized  = true
    self.currentAlpha = 0
    self.targetAlpha  = 0

    self:ApplySettings()
    self:ApplyPosition()
    self:ApplyLockState()

    return frame
end

--==========================================================================
-- Position
--==========================================================================

function Display:ApplyPosition()
    if not self.frame then return end
    local pos = ns.db.position
    self.frame:ClearAllPoints()
    self.frame:SetPoint(pos.point or "CENTER", UIParent, pos.relPoint or "CENTER", pos.x or 0, pos.y or 0)
end

function Display:SavePosition()
    if not self.frame then return end
    local point, _, relPoint, x, y = self.frame:GetPoint(1)
    ns.db.position = {
        point    = point    or "CENTER",
        relPoint = relPoint or "CENTER",
        x        = math.floor((x or 0) + 0.5),
        y        = math.floor((y or 0) + 0.5),
    }
    ns.Debug("Position gespeichert:", ns.db.position.point, ns.db.position.x, ns.db.position.y)
end

function Display:ApplyLockState()
    if not self.frame then return end
    local locked = ns.db.locked
    self.frame:EnableMouse(not locked)
    self.purifyIcon:EnableMouse(locked)
    self.celestialIcon:EnableMouse(locked)
    self.unlockOverlay:SetShown(not locked)
    if not locked then
        self.currentAlpha = 1
        self.targetAlpha  = 1
        self.frame:SetAlpha(1)
        self.frame:Show()
    end
end

--==========================================================================
-- Einstellungen anwenden
--==========================================================================

function Display:ApplySettings()
    if not self.initialized then return end

    local db      = ns.db
    local barCfg  = db.bar
    local colors  = db.colors

    local brewRow = (barCfg.showBrews and (barCfg.brewSize + 4)) or 0

    self.frame:SetScale(barCfg.scale)
    self.frame:SetSize(barCfg.width, barCfg.height + brewRow)

    self.holder:SetHeight(barCfg.height)
    if self.holder.SetBackdropColor then
        self.holder:SetBackdropColor(unpack(colors.background))
        self.holder:SetBackdropBorderColor(unpack(colors.border))
    end

    self.bar:SetStatusBarTexture(GetBarTexture())
    self.bar:SetMinMaxValues(0, barCfg.maxPct)

    self.spark:SetShown(barCfg.showSpark)
    self.spark:SetHeight(barCfg.height * 2)

    -- Schwellenmarkierungen positionieren
    local usableWidth = barCfg.width - 2
    for key, tick in pairs({ light = self.tickLight, medium = self.tickMedium }) do
        if barCfg.showTicks and db.thresholds[key] < barCfg.maxPct then
            local offset = usableWidth * (db.thresholds[key] / barCfg.maxPct)
            tick:ClearAllPoints()
            tick:SetPoint("TOPLEFT", self.bar, "TOPLEFT", offset, 0)
            tick:SetPoint("BOTTOMLEFT", self.bar, "BOTTOMLEFT", offset, 0)
            tick:Show()
        else
            tick:Hide()
        end
    end

    -- Text
    for _, fs in ipairs({ self.textLeft, self.textCenter, self.textRight, self.hintText }) do
        StyleFontString(fs)
    end

    -- Gebraeu-Symbole
    self.brewContainer:SetShown(barCfg.showBrews)
    self.brewContainer:SetHeight(math.max(barCfg.brewSize, 1))
    for _, icon in ipairs({ self.purifyIcon, self.celestialIcon }) do
        icon:SetSize(barCfg.brewSize, barCfg.brewSize)
        icon.count:SetFont(GetFontPath(), math.max(barCfg.brewSize * 0.4, 8), "OUTLINE")
    end

    self:ApplyLockState()
end

--==========================================================================
-- Laufende Aktualisierung
--==========================================================================

local function ColorForLevel(level)
    local colors = ns.db.colors
    if level == ns.LEVEL.HEAVY  then return colors.heavy  end
    if level == ns.LEVEL.MEDIUM then return colors.medium end
    return colors.light
end

--- Aktualisiert Leiste, Texte und Hervorhebungen anhand des Zustands aus Core.
function Display:Update(state)
    if not self.initialized then return end

    local db     = ns.db
    local barCfg = db.bar
    local color  = ColorForLevel(state.level)

    ------------------------------------------------------------------
    -- Leiste
    ------------------------------------------------------------------
    local shown = math.min(state.staggerPct, barCfg.maxPct)
    self.bar:SetValue(shown)
    self.bar:SetStatusBarColor(color[1], color[2], color[3], color[4] or 1)

    if barCfg.showSpark and shown > 0 and shown < barCfg.maxPct then
        local offset = (barCfg.width - 2) * (shown / barCfg.maxPct)
        self.spark:ClearAllPoints()
        self.spark:SetPoint("CENTER", self.bar, "LEFT", offset, 0)
        self.spark:Show()
    else
        self.spark:Hide()
    end

    ------------------------------------------------------------------
    -- Texte
    ------------------------------------------------------------------
    local text = db.text

    if text.showLevel then
        self.textLeft:SetText(ns.LEVEL_NAME[state.level] or "")
    else
        self.textLeft:SetText("")
    end

    local center = {}
    if text.showPercent  then center[#center + 1] = string.format("%.1f%%", state.staggerPct) end
    if text.showAbsolute then center[#center + 1] = ns.FormatNumber(state.stagger) end
    self.textCenter:SetText(table.concat(center, "  |cff888888•|r  "))

    if text.showDTPS then
        self.textRight:SetText(string.format("%s /s", ns.FormatNumber(state.dtps)))
    else
        self.textRight:SetText("")
    end

    ------------------------------------------------------------------
    -- Gebraeu-Symbole
    ------------------------------------------------------------------
    if barCfg.showBrews then
        self:UpdateBrewIcon(self.purifyIcon, state.purify, state.rec.purify, state.rec.purifyReason)
        self:UpdateBrewIcon(self.celestialIcon, state.celestial, state.rec.celestial, state.rec.celestialReason)

        local hint = state.rec.purifyReason or state.rec.celestialReason
        if hint then
            self.hintText:SetText("|cff00ff96" .. hint .. "|r")
        else
            self.hintText:SetText("")
        end
    else
        -- Symbole ausgeblendet: laufende Animationen anhalten
        self.purifyIcon.glow:Stop()
        self.celestialIcon.glow:Stop()
    end

    ------------------------------------------------------------------
    -- Hervorhebung der Leiste
    ------------------------------------------------------------------
    local style = db.recommend.glowStyle
    if db.recommend.enabled and (state.rec.purify or state.rec.celestial) and style ~= "NONE" then
        self.barGlow:SetColor(color[1], color[2], color[3])
        self.barGlow:Start(style)
    else
        self.barGlow:Stop()
    end
end

--- Aktualisiert ein einzelnes Gebraeu-Symbol.
function Display:UpdateBrewIcon(icon, info, recommended, reason)
    if not info or not info.known then
        icon:Hide()
        return
    end
    icon:Show()
    icon.reason = reason

    -- Abklingzeit / Ladungen
    if info.chargeStart and info.chargeDuration and info.chargeDuration > 0
       and info.charges and info.maxCharges and info.charges < info.maxCharges then
        icon.cooldown:SetCooldown(info.chargeStart, info.chargeDuration)
    elseif info.start and info.duration and info.duration > 1.5 and info.charges == 0 then
        icon.cooldown:SetCooldown(info.start, info.duration)
    else
        icon.cooldown:Clear()
    end

    if info.maxCharges and info.maxCharges > 1 then
        icon.count:SetText(info.charges or 0)
        icon.count:SetTextColor(1, 1, 1)
    else
        icon.count:SetText("")
    end

    -- Verfuegbarkeit visualisieren
    local usable = (info.charges or 0) >= 1
    icon.icon:SetDesaturated(not usable)
    icon.icon:SetVertexColor(usable and 1 or 0.55, usable and 1 or 0.55, usable and 1 or 0.55)

    -- Hervorhebung
    local style = ns.db.recommend.glowStyle
    if recommended and ns.db.recommend.enabled and style ~= "NONE" then
        icon.glow:SetColor(0.2, 1.0, 0.6)
        icon.glow:Start(style)
    else
        icon.glow:Stop()
    end
end

--==========================================================================
-- Ein- und Ausblenden
--==========================================================================

function Display:SetTargetAlpha(alpha, instant)
    if not self.initialized then return end
    self.targetAlpha = alpha

    if instant or (ns.db.visibility.fadeDuration or 0) <= 0 then
        self.currentAlpha = alpha
        self.frame:SetAlpha(alpha)
        self:UpdateShownState()
    elseif alpha > 0 and not self.frame:IsShown() then
        -- Beim Einblenden sofort sichtbar machen, damit die Animation greift
        self.frame:Show()
    end
end

--- Wird jeden Frame aus Core aufgerufen (der Treiberrahmen ist immer sichtbar).
function Display:OnFadeUpdate(elapsed)
    if not self.initialized then return end

    local current = self.currentAlpha or 0
    local target  = self.targetAlpha or 0

    if math.abs(current - target) < 0.005 then
        if current ~= target then
            self.currentAlpha = target
            self.frame:SetAlpha(target)
            self:UpdateShownState()
        end
        return
    end

    local duration = math.max(ns.db.visibility.fadeDuration or 0.3, 0.05)
    local step = elapsed / duration

    if current < target then
        current = math.min(target, current + step)
    else
        current = math.max(target, current - step)
    end

    self.currentAlpha = current
    self.frame:SetAlpha(current)
    self:UpdateShownState()
end

function Display:UpdateShownState()
    local alpha = self.currentAlpha or 0
    if alpha <= 0.01 then
        if self.frame:IsShown() then
            self.frame:Hide()
            self.barGlow:Stop()
            self.purifyIcon.glow:Stop()
            self.celestialIcon.glow:Stop()
        end
    elseif not self.frame:IsShown() then
        self.frame:Show()
    end
end

function Display:HideImmediately()
    if not self.initialized then return end
    self.currentAlpha = 0
    self.targetAlpha  = 0
    self.frame:SetAlpha(0)
    self:UpdateShownState()
end
