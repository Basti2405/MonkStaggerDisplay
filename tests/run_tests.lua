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

print("")
if failed == 0 then
    print("ERGEBNIS: alle Prüfungen bestanden")
    os.exit(0)
else
    print(string.format("ERGEBNIS: %d Prüfung(en) fehlgeschlagen", failed))
    os.exit(1)
end
