--[[--------------------------------------------------------------------------
    Testlauf ausserhalb von World of Warcraft.

    Laedt die Addon-Module gegen eine WoW-API-Attrappe und prueft Ladevorgang,
    Ereignisverarbeitung, Schwellenlogik, Slash-Befehle und Optionsfenster.

    Aufruf aus dem Projektstammverzeichnis:
        lua5.1 tests/run_tests.lua
----------------------------------------------------------------------------]]

local TEST_DIR  = (arg and arg[0] or "tests/run_tests.lua"):match("^(.*)[/\\][^/\\]*$") or "tests"
local ADDON_DIR = os.getenv("ADDON_DIR") or (TEST_DIR .. "/../MonkStaggerDisplay")

dofile(TEST_DIR .. "/mock_wow.lua")

local ADDON  = "MonkStaggerDisplay"
local ns     = {}
local failed = 0

local function check(label, ok, detail)
    if ok then
        print(string.format("  [ok]   %s%s", label, detail and ("  " .. detail) or ""))
    else
        failed = failed + 1
        print(string.format("  [FAIL] %s%s", label, detail and ("  " .. detail) or ""))
    end
end

local function loadModule(file)
    local chunk, err = loadfile(ADDON_DIR .. "/" .. file)
    if not chunk then
        failed = failed + 1
        print("  [FAIL] Ladefehler in " .. file .. ": " .. tostring(err))
        os.exit(1)
    end
    chunk(ADDON, ns)
    check("geladen: " .. file, true)
end

print("== Module laden ==")
loadModule("Config.lua")
loadModule("Display.lua")
loadModule("Core.lua")

local core = _G.MonkStaggerDisplayCore
check("Core-Ereignisrahmen erzeugt", core ~= nil)

print("\n== Ereignisse ==")
core:Fire("ADDON_LOADED", ADDON)
check("ADDON_LOADED legt SavedVariables an", MonkStaggerDB ~= nil)
core:Fire("PLAYER_LOGIN")
check("PLAYER_LOGIN erkennt Braumeister", ns.Core.isBrewmaster == true)
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "UNIT_HEALTH",
                         "UNIT_AURA", "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES",
                         "COMBAT_LOG_EVENT_UNFILTERED", "PLAYER_REGEN_ENABLED" }) do
    local ok, err = pcall(core.Fire, core, event, "player")
    check("Ereignis " .. event, ok, ok and "" or tostring(err))
end

print("\n== Aktualisierungsschleife ==")
for _ = 1, 20 do core:Tick(0.06) end
local s = ns.Core.state
check("Stagger berechnet", s.stagger > 0,
      string.format("%.0f (%.1f%%)", s.stagger, s.staggerPct))
check("DTPS = Stagger / 10s", math.abs(s.dtps - s.stagger / 10) < 0.01,
      string.format("%.0f/s", s.dtps))
check("Ladungen gelesen", s.purify.maxCharges == 2,
      string.format("%s/%s", tostring(s.purify.charges), tostring(s.purify.maxCharges)))
check("Geläutertes Chi gelesen", s.purifiedChi == 4, tostring(s.purifiedChi))

print("\n== Schwellenlogik ==")
local EXPECTED = {
    [0]    = "Leicht", [15]   = "Leicht", [29.9] = "Leicht",
    [30]   = "Mittel", [45]   = "Mittel", [59.9] = "Mittel",
    [60]   = "Schwer", [85]   = "Schwer",
}
for _, pct in ipairs({ 0, 15, 29.9, 30, 45, 59.9, 60, 85 }) do
    UnitStagger = function() return 1000000 * pct / 100 end
    ns.Core:BuildState()
    local got = ns.LEVEL_NAME[ns.Core.state.level]
    check(string.format("%5.1f%% -> %s", pct, got), got == EXPECTED[pct])
end
UnitStagger = function() return 450000 end

print("\n== Empfehlungs-Engine ==")
-- Kein Stagger -> keine Läuterungsempfehlung
UnitStagger = function() return 0 end
ns.Core:BuildState()
check("kein Stagger -> keine Läuterung", ns.Core.state.rec.purify ~= true)
-- Hoher Stagger -> Läuterung empfohlen
UnitStagger = function() return 800000 end
ns.Core:BuildState()
check("80% Stagger -> Läuterung empfohlen", ns.Core.state.rec.purify == true,
      tostring(ns.Core.state.rec.purifyReason))
-- Engine deaktiviert -> keine Empfehlung
ns.db.recommend.enabled = false
ns.Core:BuildState()
check("Engine aus -> keine Empfehlung", ns.Core.state.rec.purify ~= true)
ns.db.recommend.enabled = true
UnitStagger = function() return 450000 end

print("\n== Slash-Befehle ==")
local slash = SlashCmdList["MONKSTAGGERDISPLAY"]
check("Slash-Handler registriert", slash ~= nil)
check("/msd registriert", SLASH_MONKSTAGGERDISPLAY1 == "/msd")
check("/stagger registriert", SLASH_MONKSTAGGERDISPLAY2 == "/stagger")
for _, cmd in ipairs({ "", "unlock", "lock", "toggle", "test", "test", "status",
                       "off", "on", "reset", "debug", "debug", "unbekannt" }) do
    local ok, err = pcall(slash, cmd)
    check("/msd " .. (cmd == "" and "(leer)" or cmd), ok, ok and "" or tostring(err))
end

print("\n== Optionsfenster ==")
local panel = ns.Config.panel
check("Panel gebaut", panel ~= nil)
check("Bedienelemente vorhanden", panel and #panel.refreshers > 30,
      panel and (#panel.refreshers .. " Refresher") or "")
check("Refresh fehlerfrei", pcall(panel.Refresh, panel))
check("OnRefresh-Hook vorhanden", type(panel.OnRefresh) == "function")
check("OnDefault-Hook vorhanden", type(panel.OnDefault) == "function")

-- Gemeldet aus dem Spiel: bad argument #1 to 'OpenSettingsPanel'. Die
-- Kategorie-ID wurde nach der Registrierung mit dem Anzeigenamen ueber-
-- schrieben; C_SettingsUtil.OpenSettingsPanel erwartet aber eine Zahl.
check("Kategorie behaelt Blizzards numerische ID",
      type(ns.Config.category and ns.Config.category:GetID()) == "number",
      "ID = " .. tostring(ns.Config.category and ns.Config.category:GetID()))
Settings.__openedID = nil
local okOpen, errOpen = pcall(ns.Config.OpenSettings, ns.Config)
check("OpenSettings wirft nicht", okOpen, okOpen and "" or tostring(errOpen))
check("OpenToCategory bekam die numerische ID",
      Settings.__openedID == (ns.Config.category and ns.Config.category:GetID()))

print("\n== Persistenz ==")
ns.db.position.x, ns.db.position.y = 123, -456
check("Position wird in SavedVariables gehalten",
      MonkStaggerDB.position.x == 123 and MonkStaggerDB.position.y == -456)
ns.Config:ResetPosition()
check("ResetPosition stellt Standard her", ns.db.position.x == 0 and ns.db.position.y == -180)
ns.Config:ResetAll()
check("ResetAll stellt Standardwerte her", ns.db.thresholds.light == 30 and ns.db.thresholds.medium == 60)

print("\n== Testmodus ==")
ns.Core.testMode = true
local ok = pcall(function() for _ = 1, 10 do core:Tick(0.06) end end)
check("Testmodus läuft fehlerfrei", ok,
      string.format("%.1f%%", ns.Core.state.staggerPct))
ns.Core.testMode = false

print("\n== Addon-Kompartiment ==")
check("Click-Handler vorhanden", type(MonkStaggerDisplay_OnAddonCompartmentClick) == "function")
check("Enter-Handler vorhanden", type(MonkStaggerDisplay_OnAddonCompartmentEnter) == "function")
check("Leave-Handler vorhanden", type(MonkStaggerDisplay_OnAddonCompartmentLeave) == "function")
check("Handler aufrufbar", pcall(function()
    MonkStaggerDisplay_OnAddonCompartmentClick(nil, "LeftButton")
    MonkStaggerDisplay_OnAddonCompartmentClick(nil, "RightButton")
    MonkStaggerDisplay_OnAddonCompartmentEnter(nil, nil)
    MonkStaggerDisplay_OnAddonCompartmentLeave()
end))

print("\n== Gesperrte Werte (Midnight 12.0) ==")
-- Nachstellung des gemeldeten Fehlers: UnitHealth liefert einen gesperrten
-- Wert, UnitHealthMax bleibt eine normale Zahl.
local geheim = MarkSecret(420000)
UnitHealth = function() return geheim end
check("issecretvalue erkennt den Wert", issecretvalue(geheim) == true)
-- Nachweis, dass die Attrappe den Fehler wirklich nachstellt: ohne Schutz
-- muss die Rechnung aus der alten Fassung scheitern.
local wirft = not pcall(function() return geheim / 566900 * 100 end)
check("Rechnen auf dem gesperrten Wert wirft (wie im Spiel)", wirft)
check("SafeNumber liefert dafür nil", ns.SafeNumber(geheim) == nil)
check("SafeNumber lässt normale Zahlen durch", ns.SafeNumber(566900) == 566900)

local okBuild, errBuild = pcall(function() ns.Core:BuildState() end)
check("BuildState wirft keinen Fehler mehr", okBuild, okBuild and "" or tostring(errBuild))
check("healthPct ist unbekannt statt geraten", ns.Core.state.healthPct == nil)
check("Stagger wird weiter berechnet", ns.Core.state.staggerPct > 0,
      string.format("%.1f%%", ns.Core.state.staggerPct))

-- Notfallpfade dürfen bei unbekanntem Leben nicht auslösen
ns.db.recommend.emergencyHealthPct = 100
ns.db.recommend.celestialEmergencyHealthPct = 100
UnitStagger = function() return 50000 end          -- niedrig: nur Notfall käme infrage
ns.Core:BuildState()
check("kein Notfall-Läutern bei unbekanntem Leben",
      not string.find(tostring(ns.Core.state.rec.purifyReason or ""), "Notfall"))
check("kein Notfall-Schild bei unbekanntem Leben",
      not string.find(tostring(ns.Core.state.rec.celestialReason or ""), "Notfall"))

-- Mit lesbarem Leben muss der Notfall wieder greifen
UnitHealth = function() return 100000 end
UnitStagger = function() return 350000 end
ns.Core:BuildState()
check("mit lesbarem Leben greift der Notfall wieder",
      ns.Core.state.rec.purify == true, tostring(ns.Core.state.rec.purifyReason))
ns.db.recommend.emergencyHealthPct = 40

print("\n== Gesperrte Zauberwerte (Ladungen & Abklingzeit) ==")
-- Gemeldet aus dem Spiel: attempt to compare local 'charges' (a secret number
-- value) in FillSpellInfo. currentCharges/cooldownStartTime/cooldownDuration
-- sind gesperrt, maxCharges bleibt lesbar.
ns.db.recommend.celestialEmergencyHealthPct = 40
C_Spell.__secret = true

local geheimeLadung = C_Spell.GetSpellCharges(119582).currentCharges
check("Attrappe liefert die Ladungen gesperrt", issecretvalue(geheimeLadung) == true)
check("Vergleich darauf wirft (wie im Spiel)",
      not pcall(function() return geheimeLadung < 2 end))

local okFill, errFill = pcall(function() return ns.Core:BuildState() end)
check("BuildState wirft nicht mehr", okFill, okFill and "" or tostring(errFill))

local purify = ns.Core.state.purify
check("Gebräu gilt weiter als bekannt", purify.known == true)
check("Ladungssystem wird erkannt", purify.maxCharges == 2)
check("Ladungsstand als unbekannt markiert", purify.unknown == true)
check("charges bleibt nil statt geraten", purify.charges == nil)
check("nicht als bereit ausgegeben", purify.ready == false)
check("Rohwert für die Cooldown-Anzeige erhalten",
      issecretvalue(purify.rawChargeStart) == true)

-- Keine Empfehlung auf unbekannter Grundlage, obwohl der Stagger hoch ist.
UnitStagger = function() return 350000 end
ns.Core:BuildState()
check("Stagger wird weiter berechnet", ns.Core.state.staggerPct > 0,
      string.format("%.1f%%", ns.Core.state.staggerPct))
check("keine Läutern-Empfehlung bei unbekannten Ladungen",
      not ns.Core.state.rec.purify, tostring(ns.Core.state.rec.purifyReason))
check("keine Schild-Empfehlung bei unbekannter Abklingzeit",
      not ns.Core.state.rec.celestial, tostring(ns.Core.state.rec.celestialReason))

-- Die Anzeige muss trotzdem durchlaufen und ehrlich beschriften.
local okDisp, errDisp = pcall(function() ns.Display:Update(ns.Core.state) end)
check("Display:Update wirft nicht", okDisp, okDisp and "" or tostring(errDisp))
check("Ladungszähler zeigt ? statt 0",
      ns.Display.purifyIcon.count.__text == "?",
      tostring(ns.Display.purifyIcon.count.__text))
check("Cooldown-Anzeige bekommt den Rohwert",
      ns.Display.purifyIcon.cooldown.__cooldown ~= nil
      and issecretvalue(ns.Display.purifyIcon.cooldown.__cooldown[1]) == true)

-- /msd status muss den Zustand benennen statt ihn zu verschweigen.
local statusZeilen = {}
local echtesPrint = print
print = function(...) statusZeilen[#statusZeilen + 1] = table.concat({ tostringall(...) }, " ") end
local okStatus = pcall(function() ns.Core:PrintStatus() end)
print = echtesPrint
check("PrintStatus wirft nicht", okStatus)
check("Status weist die gesperrten Werte aus",
      string.find(table.concat(statusZeilen, "\n"), "Gesperrt:") ~= nil)

-- Zurueck auf lesbare Werte: alles muss wieder normal arbeiten.
C_Spell.__secret = false
ns.Core:BuildState()
check("mit lesbaren Werten wieder normale Ladungen",
      ns.Core.state.purify.charges == 1 and ns.Core.state.purify.unknown == nil)
check("und wieder als bereit gemeldet", ns.Core.state.purify.ready == true)
ns.Display:Update(ns.Core.state)
check("Zähler zeigt wieder die Zahl", ns.Display.purifyIcon.count.__text == 1,
      tostring(ns.Display.purifyIcon.count.__text))
ns.db.recommend.celestialEmergencyHealthPct = 20
ns.db.recommend.celestialEmergencyHealthPct = 50
UnitHealth = function() return 620000 end
UnitStagger = function() return 450000 end

print("\n== Refresh außerhalb der Spezialisierung ==")
local vorher = ns.Core.isBrewmaster
ns.Core.isBrewmaster = false
local ok2, err2 = pcall(function() ns.Core:Refresh(true) end)
check("Refresh ohne Braumeister bleibt fehlerfrei", ok2, ok2 and "" or tostring(err2))
ns.Core.isBrewmaster = vorher

print("\n== Geschützte Aufrufe (ADDON_ACTION_FORBIDDEN) ==")
-- Gemeldet aus dem Spiel: RegisterEvent aus UpdateSpecialization heraus ist
-- verboten, weil PLAYER_SPECIALIZATION_CHANGED aus geschütztem Kontext feuert.
-- Alle Registrierungen müssen deshalb beim Laden erfolgen, nicht später.
local function ereignismenge()
    local liste = {}
    for e in pairs(core.__events) do liste[#liste+1] = e end
    table.sort(liste)
    return table.concat(liste, ",")
end

check("COMBAT_LOG_EVENT_UNFILTERED wird nicht registriert",
      core.__events["COMBAT_LOG_EVENT_UNFILTERED"] == nil)

local ereignisseVorher = ereignismenge()
ns.Core.isBrewmaster = false
ns.Core:UpdateSpecialization()          -- Wechsel nach Braumeister
ns.Core.isBrewmaster = true
ns.Core:UpdateSpecialization()          -- und wieder zurück
check("UpdateSpecialization registriert keine Ereignisse nach",
      ereignismenge() == ereignisseVorher, "")

print("\n== Schadenserkennung ohne Kampflog ==")
ns.Core.lastStagger = 0
ns.Core.lastDamageTime = 0
UnitStagger = function() return 0 end
ns.Core:BuildState()
check("kein Stagger -> kein Schadenszeitpunkt", ns.Core.lastDamageTime == 0)

UnitStagger = function() return 120000 end
ns.Core:BuildState()
local nachAnstieg = ns.Core.lastDamageTime
check("Stagger-Anstieg setzt den Schadenszeitpunkt", nachAnstieg > 0)

UnitStagger = function() return 90000 end     -- faellt ab: kein neuer Schaden
ns.Core:BuildState()
check("fallender Stagger setzt ihn nicht erneut",
      ns.Core.lastDamageTime == nachAnstieg)

UnitStagger = function() return 200000 end    -- steigt wieder
ns.Core:BuildState()
check("erneuter Anstieg setzt ihn wieder", ns.Core.lastDamageTime > nachAnstieg)
UnitStagger = function() return 450000 end

print("\n== Ereignisanmeldung (unbekannte Ereignisse) ==")
-- Gemeldet aus dem Spiel: Attempt to register unknown event
-- "LEARNED_SPELL_IN_TAB". Der Fehler warf in Initialize und riss alle
-- Anmeldungen danach mit - UNIT_HEALTH und die Kampfereignisse fehlten.
check("Attrappe wirft bei unbekanntem Ereignis (wie im Spiel)",
      not pcall(function() core:RegisterEvent("LEARNED_SPELL_IN_TAB") end))
check("C_EventUtils.IsEventValid erkennt es",
      C_EventUtils.IsEventValid("LEARNED_SPELL_IN_TAB") == false)
check("RegisterEventSafely wirft nicht, meldet false",
      select(2, pcall(ns.RegisterEventSafely, core, "LEARNED_SPELL_IN_TAB")) == false)

-- Alles, was nach der frueher fehlerhaften Zeile kam, muss angemeldet sein.
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD",
                     "PLAYER_SPECIALIZATION_CHANGED", "PLAYER_REGEN_DISABLED",
                     "PLAYER_REGEN_ENABLED", "SPELL_UPDATE_COOLDOWN",
                     "SPELL_UPDATE_CHARGES", "UNIT_HEALTH", "UNIT_MAXHEALTH",
                     "UNIT_AURA" }) do
    check("angemeldet: " .. e, core.__events[e] == true)
end
check("LEARNED_SPELL_IN_TAB wird nicht mehr angemeldet",
      core.__events["LEARNED_SPELL_IN_TAB"] == nil)

print("")
if failed == 0 then
    print("ERGEBNIS: alle Prüfungen bestanden")
    os.exit(0)
else
    print(string.format("ERGEBNIS: %d Prüfung(en) fehlgeschlagen", failed))
    os.exit(1)
end
