-- Luacheck-Konfiguration für World-of-Warcraft-Addons (Lua 5.1)
std = "lua51"
max_line_length = 120
exclude_files = { "tests/mock_wow.lua" }
codes = true

-- Die Addon-Tabelle wird über varargs übergeben
ignore = {
    "212/self",   -- ungenutzter self-Parameter in Methoden
    "212/_.*",    -- absichtlich ignorierte Parameter
    "542",        -- leerer if-Zweig
}

read_globals = {
    -- Basis-API
    "CreateFrame", "UIParent", "GameTooltip", "GetTime", "InCombatLockdown",
    "UnitClass", "UnitGUID", "UnitHealth", "UnitHealthMax", "UnitStagger",
    "UnitAffectingCombat", "UnitInVehicle", "UnitHasVehicleUI",
    "CombatLogGetCurrentEventInfo", "IsPlayerSpell", "PlaySound",
    "issecretvalue",
    "GetSpecialization", "GetSpecializationInfo", "GetSpellCooldown",
    "GetSpellCharges", "GetSpellTexture",

    -- Namespaces
    "C_AddOns", "C_Spell", "C_UnitAuras", "C_SpecializationInfo", "C_SpellBook",
    "Settings",

    -- UI-Bausteine
    "OpacitySliderFrame", "BackdropTemplateMixin",
    "StaticPopup_Show", "InterfaceOptions_AddCategory",
    "InterfaceOptionsFrame_OpenToCategory", "GameFontNormal",
    "STANDARD_TEXT_FONT", "YES", "NO",

    -- Lua-Erweiterungen von Blizzard
    "wipe", "strtrim", "strjoin", "strsplit", "tostringall", "unpack",
    "table", "string", "math",
}

globals = {
    -- Legacy-ColorPicker-Pfad setzt Felder auf dem Frame
    "ColorPickerFrame",

    -- Von diesem Addon absichtlich global gesetzt
    "MonkStaggerDB",
    "SlashCmdList",
    "SLASH_MONKSTAGGERDISPLAY1",
    "SLASH_MONKSTAGGERDISPLAY2",
    "StaticPopupDialogs",
    "MonkStaggerDisplay_OnAddonCompartmentClick",
    "MonkStaggerDisplay_OnAddonCompartmentEnter",
    "MonkStaggerDisplay_OnAddonCompartmentLeave",
}

-- Der Testlauf ersetzt absichtlich API-Funktionen, um Szenarien zu erzeugen.
files["tests/run_tests.lua"] = {
    globals = { "UnitStagger", "UnitHealth", "UnitHealthMax", "UnitAffectingCombat" },
    read_globals = { "MarkSecret", "issecretvalue" },
}
