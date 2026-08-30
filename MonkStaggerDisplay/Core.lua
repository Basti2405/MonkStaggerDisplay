--[[--------------------------------------------------------------------------
    Monk Stagger Display -- Core.lua

    Herzstueck des Addons:
      * Ereignisverarbeitung und Spezialisierungspruefung (Braumeister, 268)
      * Zustandsermittlung (Stagger, Leben, Gebraeu-Abklingzeiten, Auren)
      * Empfehlungs-Engine fuer Laeuterndes Gebraeu / Himmlische Infusion
      * Sichtbarkeitssteuerung (Kampf, eingehender Schaden, Ruhezustand)
      * Slash-Befehle /msd und /stagger
----------------------------------------------------------------------------]]

local addonName, ns = ...

local Core = {}
ns.Core = Core

local UPDATE_INTERVAL = 0.05   -- Aktualisierungstakt der Anzeige
local GCD_THRESHOLD   = 1.5    -- Abklingzeiten bis hierher sind die globale Abklingzeit

Core.state = {
    stagger    = 0,
    staggerPct = 0,
    dtps       = 0,
    health     = 0,
    healthPct  = 100,
    maxHealth  = 0,
    level      = 1,
    inCombat   = false,
    purifiedChi= 0,
    purify     = {},
    celestial  = {},
    rec        = {},
}

Core.isBrewmaster  = false
Core.lastDamageTime= 0
Core.lastStagger   = 0
Core.lastSoundTime = 0
Core.testMode      = false
Core.elapsedAccum  = 0

--==========================================================================
-- 1. Zustandsermittlung
--==========================================================================

--- Fuellt eine Tabelle mit Abklingzeit- und Ladungsinformationen eines Zaubers.
local function FillSpellInfo(info, spellID)
    wipe(info)
    info.spellID = spellID
    info.known   = ns.IsSpellAvailable(spellID)
    if not info.known then return info end

    local now = GetTime()

    -- Seit Midnight (12.0) sperrt Blizzard Abklingzeit- und Ladungswerte,
    -- sobald Addon-Code die Ausfuehrung taintet. Die Wrapper liefern dafuer
    -- nil; die raw*-Felder tragen die Originalwerte und gehen ungelesen an
    -- Blizzards Cooldown-Anzeige weiter. Ist ein Wert nicht lesbar, wird das
    -- ueber info.unknown gemeldet -- geraten wird nicht.
    local start, duration, enabled, _, rawStart, rawDuration =
        ns.GetSpellCooldownInfo(spellID)
    info.start, info.duration, info.enabled = start, duration, enabled
    info.rawStart, info.rawDuration = rawStart, rawDuration

    local hasCharges, charges, maxCharges, chargeStart, chargeDuration,
          rawChargeStart, rawChargeDuration = ns.GetSpellChargeInfo(spellID)
    info.rawChargeStart, info.rawChargeDuration = rawChargeStart, rawChargeDuration

    if hasCharges then
        info.charges        = charges
        info.maxCharges     = maxCharges
        info.chargeStart    = chargeStart
        info.chargeDuration = chargeDuration

        if charges == nil or maxCharges == nil then
            info.unknown = true
        elseif charges < maxCharges and chargeStart
               and chargeDuration and chargeDuration > 0 then
            info.timeToNextCharge = math.max((chargeStart + chargeDuration) - now, 0)
        else
            info.timeToNextCharge = 0
        end
    else
        -- Zauber ohne Ladungssystem als 0/1 Ladungen abbilden
        info.maxCharges = 1
        if start == nil or duration == nil then
            info.unknown = true
        else
            local remaining = 0
            if start > 0 and duration > GCD_THRESHOLD then
                remaining = math.max((start + duration) - now, 0)
            end
            info.charges          = (remaining > 0) and 0 or 1
            info.timeToNextCharge = remaining
        end
    end

    -- Bei unbekanntem Ladungsstand gilt der Zauber nicht als bereit. Das
    -- unterdrueckt jede Empfehlung, statt eine auf geratenen Werten zu geben.
    info.ready = (not info.unknown) and (info.charges or 0) >= 1
    return info
end

--- Ordnet einen Stagger-Prozentwert einer der drei Stufen zu.
local function LevelForPercent(percent)
    local thresholds = ns.db.thresholds
    if percent >= thresholds.medium then return ns.LEVEL.HEAVY end
    if percent >= thresholds.light  then return ns.LEVEL.MEDIUM end
    return ns.LEVEL.LIGHT
end

--- Werte fuer die Testanzeige erzeugen (sinusfoermiger Stagger-Verlauf).
function Core:BuildTestState(state)
    local maxHealth = math.max(UnitHealthMax("player") or 0, 1000000)
    local cycle     = (GetTime() % 12) / 12
    local wave      = (1 - math.cos(cycle * 2 * math.pi)) / 2   -- 0 .. 1 .. 0

    state.maxHealth  = maxHealth
    state.health     = maxHealth * (1 - wave * 0.55)
    state.stagger    = maxHealth * wave * (ns.db.bar.maxPct / 100)
    state.healthPct  = state.health / maxHealth * 100
    state.staggerPct = state.stagger / maxHealth * 100
    state.dtps       = state.stagger / ns.STAGGER_WINDOW
    state.level      = LevelForPercent(state.staggerPct)
    state.inCombat   = true
    state.purifiedChi= math.floor(wave * 6)

    local now = GetTime()
    wipe(state.purify)
    state.purify.known      = true
    state.purify.charges    = (wave > 0.5) and 2 or 1
    state.purify.maxCharges = 2
    state.purify.chargeStart    = now - (cycle * 15)
    state.purify.chargeDuration = 15
    state.purify.timeToNextCharge = 15 - (cycle * 15)
    state.purify.ready      = true

    wipe(state.celestial)
    state.celestial.known      = true
    state.celestial.charges    = 1
    state.celestial.maxCharges = 1
    state.celestial.ready      = true
    state.celestial.start      = 0
    state.celestial.duration   = 0

    wipe(state.rec)
    if state.staggerPct >= ns.db.thresholds.medium then
        state.rec.purify       = true
        state.rec.purifyReason = "Testmodus: Läutern empfohlen"
    end
    if state.purifiedChi >= ns.db.recommend.celestialMinStacks then
        state.rec.celestial       = true
        state.rec.celestialReason = "Testmodus: Schild optimal"
    end
end

--- Sammelt alle relevanten Werte im wiederverwendeten Zustandsobjekt.
function Core:BuildState()
    local state = self.state

    if self.testMode then
        self:BuildTestState(state)
        return state
    end

    -- Ab Midnight (12.0) kann UnitHealth einen gesperrten Wert liefern, mit
    -- dem nicht gerechnet werden darf. SafeNumber gibt dann nil zurueck, und
    -- healthPct bleibt nil - also ausdruecklich "unbekannt" statt "null".
    local maxHealth = ns.SafeNumber(UnitHealthMax("player")) or 0
    local health    = ns.SafeNumber(UnitHealth("player"))

    -- Ist der Stagger gesperrt, waere 0 eine Behauptung. Der Unterschied
    -- zaehlt fuer die Sichtbarkeit: "kein Stagger" blendet aus,
    -- "nicht lesbar" darf es nicht.
    local staggerRaw = UnitStagger and UnitStagger("player") or nil
    local staggerVal = ns.SafeNumber(staggerRaw)
    local stagger    = staggerVal or 0
    state.staggerUnknown = (staggerRaw ~= nil) and (staggerVal == nil)

    state.maxHealth  = maxHealth
    state.health     = health
    state.stagger    = stagger
    state.healthPct  = (health and maxHealth > 0) and (health / maxHealth * 100) or nil
    state.staggerPct = (maxHealth > 0) and (stagger / maxHealth * 100) or 0

    -- Steigt der Stagger, ist gerade Schaden eingegangen. Das ersetzt die
    -- Auswertung des Kampflogs: Fuer einen Braumeister ist der Stagger das
    -- unmittelbarere Signal, und es kostet kein einziges Ereignis.
    if stagger > (self.lastStagger or 0) then
        self.lastDamageTime = GetTime()
    end
    self.lastStagger = stagger
    state.dtps       = stagger / ns.STAGGER_WINDOW
    state.level      = LevelForPercent(state.staggerPct)
    state.inCombat   = InCombatLockdown() or (UnitAffectingCombat("player") and true or false)
    state.purifiedChi= ns.GetPlayerAuraStacks(ns.SPELL.PURIFIED_CHI)

    FillSpellInfo(state.purify,    ns.SPELL.PURIFYING_BREW)
    -- Welcher der beiden Schild-Zauber getalentet ist, kann sich jederzeit
    -- aendern. IsPlayerSpell ist ein einfacher Lookup; ihn hier zu stellen
    -- ist billiger als ihn ueber Talent-Ereignisse aktuell zu halten.
    local celestialID = ns.GetCelestialSpellID()
    state.celestialSpellID = celestialID
    if celestialID then
        FillSpellInfo(state.celestial, celestialID)
        ns.Display:SetCelestialSpell(celestialID)
    else
        wipe(state.celestial)
        state.celestial.known = false
    end

    self:EvaluateRecommendations(state)
    return state
end

--==========================================================================
-- 2. Empfehlungs-Engine
--==========================================================================

--[[
    Bewertet, wann der Einsatz von Laeuterndem bzw. Himmlischem Gebraeu den
    groessten defensiven Wert hat. Alle Schwellen sind konfigurierbar, damit
    die Heuristik an Spielstil und Balanceaenderungen angepasst werden kann.

    Laeuterndes Gebraeu wird empfohlen, wenn ...
      a) Notfall: Leben unter der Notfallschwelle und ueberhaupt Stagger aktiv
      b) Regulaer: Stagger ueber der Schwelle UND die Laeuterung entfernt
         mindestens den konfigurierten Mindestwert (in % max. Leben)
      c) Ladungsschutz: eine Ladung wuerde gleich verfallen und die Laeuterung
         waere trotzdem noch spuerbar

    Die Himmlische Infusion wird empfohlen, wenn ...
      a) genug Stapel "Geläutertes Chi" fuer einen maximalen Schild vorliegen
      b) das Leben unter die Notfallschwelle faellt
]]
function Core:EvaluateRecommendations(state)
    local rec = state.rec
    wipe(rec)

    local cfg = ns.db.recommend
    if not cfg.enabled then return rec end

    local maxHealth = state.maxHealth
    if maxHealth <= 0 then return rec end

    ------------------------------------------------------------------
    -- Läuterndes Gebräu
    ------------------------------------------------------------------
    local purify = state.purify
    if purify.known then
        local removed  = state.stagger * (cfg.purifyRemovalPct / 100)
        local gainPct  = removed / maxHealth * 100
        state.purifyValue    = removed
        state.purifyValuePct = gainPct

        local hasCharge = (purify.charges or 0) >= 1

        if hasCharge and state.staggerPct > 0 then
            -- Ist das Leben nicht lesbar, faellt der Notfallpfad aus. Lieber
            -- keine Empfehlung als eine auf geratenen Werten.
            if state.healthPct and state.healthPct <= cfg.emergencyHealthPct
               and state.staggerPct >= ns.db.thresholds.light then
                rec.purify       = true
                rec.purifyReason = string.format("Notfall – Läutern (%.0f%% Leben)", state.healthPct)

            elseif state.staggerPct >= cfg.purifyThresholdPct
                   and gainPct >= cfg.purifyMinGainPct then
                rec.purify       = true
                rec.purifyReason = string.format("Läutern entfernt %s (%.1f%% Leben)",
                                                 ns.FormatNumber(removed), gainPct)

            elseif cfg.capProtection and gainPct >= (cfg.purifyMinGainPct * 0.5) then
                local maxCharges = purify.maxCharges or 1
                local atCap      = (purify.charges or 0) >= maxCharges
                local nearCap    = (purify.charges or 0) >= (maxCharges - 1)
                                   and (purify.timeToNextCharge or 99) <= cfg.capProtectionWindow
                if maxCharges > 1 and (atCap or nearCap) then
                    rec.purify       = true
                    rec.purifyReason = "Ladung läuft über – jetzt läutern"
                end
            end
        end
    end

    ------------------------------------------------------------------
    -- Himmlische Infusion
    ------------------------------------------------------------------
    local celestial = state.celestial
    if cfg.celestialEnabled and celestial.known and celestial.ready then
        if state.purifiedChi >= cfg.celestialMinStacks then
            rec.celestial       = true
            rec.celestialReason = string.format("Schild maximal (%d Stapel Geläutertes Chi)",
                                                state.purifiedChi)
        elseif state.healthPct and state.healthPct <= cfg.celestialEmergencyHealthPct then
            rec.celestial       = true
            rec.celestialReason = string.format("Notfall – Schild (%.0f%% Leben)", state.healthPct)
        end
    end

    return rec
end

--==========================================================================
-- 3. Sichtbarkeit
--==========================================================================

function Core:UpdateVisibility(state, instant)
    local db = ns.db

    -- Nicht Braumeister oder Addon deaktiviert -> komplett aus
    if not self.isBrewmaster or not db.enabled then
        ns.Display:SetTargetAlpha(0, instant)
        return
    end

    -- Entsperrter Anker oder Testmodus -> immer sichtbar
    if not db.locked or self.testMode then
        ns.Display:SetTargetAlpha(1, true)
        return
    end

    local visibility = db.visibility

    if visibility.hideInVehicle and (UnitInVehicle("player") or UnitHasVehicleUI("player")) then
        ns.Display:SetTargetAlpha(0, instant)
        return
    end

    local recentDamage = (GetTime() - (self.lastDamageTime or 0)) <= (visibility.damageGrace or 0)

    -- Ist der Stagger nicht lesbar, faellt sonst beides gleichzeitig aus:
    -- "Stagger > 0" ist nie wahr, und lastDamageTime wird nie gesetzt, weil
    -- es am Stagger-Anstieg haengt. Uebrig bliebe allein das Kampfflag --
    -- faellt das zwischen zwei Pulls ab, verschwindet die Leiste.
    local staggered = state.stagger > 0 or state.staggerUnknown

    local active = state.inCombat
                   or (visibility.showWhenStaggered and staggered)
                   or recentDamage

    if active then
        ns.Display:SetTargetAlpha(visibility.alphaInCombat, instant)
    else
        -- "Außerhalb des Kampfes ausblenden" erzwingt volle Transparenz
        local idle = visibility.hideOutOfCombat and 0 or (visibility.alphaIdle or 0)
        ns.Display:SetTargetAlpha(idle, instant)
    end
end

--==========================================================================
-- 4. Aktualisierungsschleife
--==========================================================================

function Core:Refresh(instant)
    if not ns.Display or not ns.Display.initialized then return end

    -- Ausserhalb der Braumeister-Spezialisierung gibt es nichts zu berechnen.
    -- Die Unit-Abfragen bleiben deshalb ganz aus (siehe 1.0.1).
    --
    -- Ausnahme: Bei entsperrtem Anker muss die Leiste sichtbar bleiben, sonst
    -- laesst sie sich auf einer anderen Spezialisierung nicht positionieren.
    -- ApplyLockState setzt dafuer Alpha 1 -- ohne diese Zeile hat der direkt
    -- danach laufende ForceUpdate es sofort wieder auf 0 gezogen.
    if not self.isBrewmaster and not self.testMode then
        ns.Display:SetTargetAlpha(ns.db.locked and 0 or 1, instant)
        return
    end

    local state = self:BuildState()
    ns.Display:Update(state)
    self:UpdateVisibility(state, instant)
    self:PlayRecommendationSound(state)
end

function Core:ForceUpdate()
    self:Refresh(false)
end

function Core:PlayRecommendationSound(state)
    local cfg = ns.db.recommend
    if not (cfg.enabled and cfg.sound) then return end
    if not (state.rec.purify or state.rec.celestial) then
        self.recActive = false
        return
    end
    if self.recActive then return end

    local now = GetTime()
    if (now - (self.lastSoundTime or 0)) < (cfg.soundThrottle or 3) then return end

    self.recActive     = true
    self.lastSoundTime = now
    if PlaySound then
        PlaySound(cfg.soundKit or 8959, "Master")
    end
end

local function OnUpdate(_, elapsed)
    Core.elapsedAccum = Core.elapsedAccum + elapsed

    -- Weiches Ein-/Ausblenden laeuft in voller Bildrate
    if ns.Display and ns.Display.initialized then
        ns.Display:OnFadeUpdate(elapsed)
    end

    if Core.elapsedAccum < UPDATE_INTERVAL then return end
    Core.elapsedAccum = 0

    if not Core.isBrewmaster and not Core.testMode then return end
    Core:Refresh(false)
end

--==========================================================================
-- 5. Spezialisierung
--==========================================================================

function Core:UpdateSpecialization()
    local _, class = UnitClass("player")
    local specID   = ns.GetPlayerSpecID()
    local wasBrewmaster = self.isBrewmaster

    self.isBrewmaster = (class == "MONK") and (specID == ns.SPEC_ID_BREWMASTER)

    if self.isBrewmaster ~= wasBrewmaster then
        ns.Debug("Braumeister-Status:", tostring(self.isBrewmaster), "SpecID:", tostring(specID))

        if self.isBrewmaster then
            -- Symbole neu laden, falls die Zauber erst jetzt bekannt sind
            if ns.Display.initialized then
                ns.Display.purifyIcon.icon:SetTexture(ns.GetSpellIcon(ns.SPELL.PURIFYING_BREW))
                ns.Display:SetCelestialSpell(ns.GetCelestialSpellID())
            end
        else
            if not self.testMode then
                ns.Display:HideImmediately()
            end
        end
    end

    self:Refresh(true)
end

--==========================================================================
-- 6. Ereignisse
--==========================================================================

local eventHandlers = {}

function eventHandlers.ADDON_LOADED(self, loadedAddon)
    if loadedAddon ~= addonName then return end
    ns.Config:Initialize()
    ns.Debug("SavedVariables geladen.")
end

function eventHandlers.PLAYER_LOGIN(self)
    ns.Display:Initialize()
    ns.Config:RegisterSettings()
    self:UpdateSpecialization()

    ns.Print(string.format("v%s geladen. |cff00ff96/msd|r öffnet die Einstellungen.", ns.VERSION))
end

function eventHandlers.PLAYER_ENTERING_WORLD(self)
    self:UpdateSpecialization()
end

function eventHandlers.PLAYER_SPECIALIZATION_CHANGED(self, unit)
    if unit and unit ~= "player" then return end
    self:UpdateSpecialization()
end

eventHandlers.PLAYER_TALENT_UPDATE   = eventHandlers.PLAYER_SPECIALIZATION_CHANGED
eventHandlers.TRAIT_CONFIG_UPDATED   = eventHandlers.PLAYER_SPECIALIZATION_CHANGED

function eventHandlers.PLAYER_REGEN_DISABLED(self)
    -- Kampfbeginn: sofort einblenden, kein Fade
    self.lastDamageTime = GetTime()
    if self.isBrewmaster and ns.db.enabled then
        ns.Display:SetTargetAlpha(ns.db.visibility.alphaInCombat, true)
    end
    self:Refresh(true)
end

function eventHandlers.PLAYER_REGEN_ENABLED(self)
    self:Refresh(false)
end

function eventHandlers.UNIT_HEALTH(self)
    self:Refresh(false)
end

eventHandlers.UNIT_MAXHEALTH        = eventHandlers.UNIT_HEALTH
eventHandlers.UNIT_AURA             = eventHandlers.UNIT_HEALTH
eventHandlers.SPELL_UPDATE_COOLDOWN = eventHandlers.UNIT_HEALTH
eventHandlers.SPELL_UPDATE_CHARGES  = eventHandlers.UNIT_HEALTH
eventHandlers.UNIT_ENTERED_VEHICLE  = eventHandlers.UNIT_HEALTH
eventHandlers.UNIT_EXITED_VEHICLE   = eventHandlers.UNIT_HEALTH

--==========================================================================
-- 7. Slash-Befehle
--==========================================================================

function Core:ToggleTestMode()
    self.testMode = not self.testMode
    if self.testMode then
        ns.Print("Testanzeige |cff55ff55aktiv|r – erneut aufrufen zum Beenden.")
        ns.Display:SetTargetAlpha(1, true)
    else
        ns.Print("Testanzeige |cffff5555beendet|r.")
        wipe(self.state.rec)
    end
    self:Refresh(true)
end

function Core:ToggleEnabled()
    ns.db.enabled = not ns.db.enabled
    ns.Print(ns.db.enabled and "Anzeige |cff55ff55aktiviert|r." or "Anzeige |cffff5555deaktiviert|r.")
    self:Refresh(true)
end

function Core:PrintStatus()
    local state = self.state
    ns.Print("Status:")
    print("  Braumeister: " .. (self.isBrewmaster and "|cff55ff55ja|r" or "|cffff5555nein|r"))
    print("  Aktiviert:   " .. (ns.db.enabled and "ja" or "nein"))
    print("  Anker:       " .. (ns.db.locked and "gesperrt" or "entsperrt"))
    print(string.format("  Stagger:     %s (%.1f%% max. Leben, %s/s)",
        ns.FormatNumber(state.stagger), state.staggerPct, ns.FormatNumber(state.dtps)))
    print(string.format("  Schwellen:   Leicht < %d%% | Mittel < %d%% | Schwer ab %d%%",
        ns.db.thresholds.light, ns.db.thresholds.medium, ns.db.thresholds.medium))
    print(string.format("  Position:    %s  x=%d  y=%d",
        ns.db.position.point, ns.db.position.x, ns.db.position.y))

    -- Lesbarkeit der gesperrten Werte ausweisen. Ohne diese Zeile wirkt ein
    -- Client, der Leben oder Ladungen sperrt, schlicht kaputt.
    local gesperrt = {}
    if state.healthPct == nil                  then gesperrt[#gesperrt + 1] = "Leben" end
    if state.purify and state.purify.unknown   then gesperrt[#gesperrt + 1] = "Läutern-Ladungen" end
    if state.celestial and state.celestial.unknown then gesperrt[#gesperrt + 1] = "Schild-Abklingzeit" end
    if #gesperrt > 0 then
        print("  |cffffaa00Gesperrt:|r    " .. table.concat(gesperrt, ", ")
              .. " – dafür gibt es keine Empfehlung")
    end
end

local function PrintHelp()
    ns.Print("Befehle (|cff00ff96/msd|r oder |cff00ff96/stagger|r):")
    print("  |cffffff00/msd|r              – Einstellungen öffnen")
    print("  |cffffff00/msd lock|r         – Ankerrahmen sperren")
    print("  |cffffff00/msd unlock|r       – Ankerrahmen zum Verschieben freigeben")
    print("  |cffffff00/msd toggle|r       – Sperre umschalten")
    print("  |cffffff00/msd test|r         – Testanzeige ein-/ausschalten")
    print("  |cffffff00/msd on|off|r       – Anzeige aktivieren/deaktivieren")
    print("  |cffffff00/msd reset|r        – Position zurücksetzen")
    print("  |cffffff00/msd resetall|r     – Alle Einstellungen zurücksetzen")
    print("  |cffffff00/msd status|r       – Aktuellen Zustand ausgeben")
    print("  |cffffff00/msd debug|r        – Debug-Ausgaben umschalten")
end

local function HandleSlash(input)
    input = string.lower(strtrim(input or ""))
    local command = string.match(input, "^(%S*)")

    if command == "" or command == "config" or command == "options" then
        ns.Config:OpenSettings()
    elseif command == "lock" then
        ns.Config:SetLocked(true)
    elseif command == "unlock" then
        ns.Config:SetLocked(false)
    elseif command == "toggle" then
        ns.Config:ToggleLock()
    elseif command == "test" then
        Core:ToggleTestMode()
    elseif command == "on" or command == "enable" then
        ns.db.enabled = true
        ns.Print("Anzeige |cff55ff55aktiviert|r.")
        Core:Refresh(true)
    elseif command == "off" or command == "disable" then
        ns.db.enabled = false
        ns.Print("Anzeige |cffff5555deaktiviert|r.")
        Core:Refresh(true)
    elseif command == "reset" then
        ns.Config:ResetPosition()
    elseif command == "resetall" then
        ns.Config:ResetAll()
    elseif command == "status" then
        Core:PrintStatus()
    elseif command == "debug" then
        ns.db.debug = not ns.db.debug
        ns.Print("Debug-Ausgaben " .. (ns.db.debug and "an" or "aus") .. ".")
    else
        PrintHelp()
    end
end

SLASH_MONKSTAGGERDISPLAY1 = "/msd"
SLASH_MONKSTAGGERDISPLAY2 = "/stagger"
SlashCmdList["MONKSTAGGERDISPLAY"] = HandleSlash

--==========================================================================
-- 7b. Addon-Kompartiment (Menue am Minimap-Button)
--==========================================================================

--- Linksklick oeffnet die Einstellungen, Rechtsklick schaltet die Sperre um.
function MonkStaggerDisplay_OnAddonCompartmentClick(_, mouseButton)
    if mouseButton == "RightButton" then
        ns.Config:ToggleLock()
    else
        ns.Config:OpenSettings()
    end
end

function MonkStaggerDisplay_OnAddonCompartmentEnter(_, menuButtonFrame)
    GameTooltip:SetOwner(menuButtonFrame or UIParent, "ANCHOR_LEFT")
    GameTooltip:SetText(ns.ADDON_TITLE, 1, 1, 1)
    GameTooltip:AddLine("Linksklick: Einstellungen öffnen", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Rechtsklick: Anker sperren/entsperren", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end

function MonkStaggerDisplay_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end

--==========================================================================
-- 8. Start
--==========================================================================

function Core:Initialize()
    local frame = CreateFrame("Frame", "MonkStaggerDisplayCore")
    self.frame = frame

    frame:SetScript("OnEvent", function(_, event, ...)
        local handler = eventHandlers[event]
        if handler then handler(Core, ...) end
    end)
    frame:SetScript("OnUpdate", OnUpdate)

    -- Ereignisse anmelden. Blizzard entfernt und benennt Ereignisse um --
    -- LEARNED_SPELL_IN_TAB etwa gibt es in Midnight nicht mehr. Ein
    -- unbekannter Name wirft, und der Fehler riss frueher den gesamten Rest
    -- der Initialisierung mit: alles nach der betroffenen Zeile blieb
    -- unregistriert. Deshalb wird jeder Name vorher geprueft.
    for _, event in ipairs({
        "ADDON_LOADED",
        "PLAYER_LOGIN",
        "PLAYER_ENTERING_WORLD",
        "PLAYER_SPECIALIZATION_CHANGED",
        "PLAYER_TALENT_UPDATE",
        "TRAIT_CONFIG_UPDATED",
        "PLAYER_REGEN_DISABLED",
        "PLAYER_REGEN_ENABLED",
        "SPELL_UPDATE_COOLDOWN",
        "SPELL_UPDATE_CHARGES",
    }) do
        ns.RegisterEventSafely(frame, event)
    end

    -- Nur spielerbezogene Unit-Ereignisse
    for _, event in ipairs({
        "UNIT_HEALTH",
        "UNIT_MAXHEALTH",
        "UNIT_AURA",
        "UNIT_ENTERED_VEHICLE",
        "UNIT_EXITED_VEHICLE",
    }) do
        ns.RegisterEventSafely(frame, event, "player")
    end
end

Core:Initialize()
