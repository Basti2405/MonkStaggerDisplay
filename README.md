# Monk Stagger Display

[![CI](https://github.com/Basti2405/MonkStaggerDisplay/actions/workflows/ci.yml/badge.svg)](https://github.com/Basti2405/MonkStaggerDisplay/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Interface](https://img.shields.io/badge/WoW-12.1.0%20(Midnight)-blue.svg)](MonkStaggerDisplay/MonkStaggerDisplay.toc)

**[→ Projektseite mit Live-Demo](https://basti2405.github.io/MonkStaggerDisplay/de/)** · [English](https://basti2405.github.io/MonkStaggerDisplay/)

Stagger-Anzeige mit Empfehlungs-Engine für **Braumeister-Mönche** (Spec-ID 268) in Modern WoW (Retail).
Keine Bibliotheken, keine Abhängigkeiten – drei Lua-Dateien und eine TOC.

## Installation

**Variante A – Release-Archiv**
ZIP aus den [Releases](https://github.com/Basti2405/MonkStaggerDisplay/releases) laden und den enthaltenen
Ordner `MonkStaggerDisplay` nach `World of Warcraft/_retail_/Interface/AddOns/` entpacken.

**Variante B – aus dem Repo**

```bash
scripts/install.sh                       # nutzt WOW_ADDONS_DIR oder den voreingestellten Pfad
scripts/install.sh "/pfad/Interface/AddOns"
```

Danach im Spiel `/reload`.

Zielstruktur: `Interface/AddOns/MonkStaggerDisplay/MonkStaggerDisplay.toc`

> **Interface-Version:** Die TOC steht auf `## Interface: 120100` (Client 12.1.0, Midnight).
> Bei abweichender Client-Version den Wert anpassen oder im AddOn-Menü „Inkompatible AddOns laden" aktivieren.

## Projektstruktur

```
.
├── MonkStaggerDisplay/          das AddOn selbst (dieser Ordner kommt nach Interface/AddOns/)
│   ├── MonkStaggerDisplay.toc   Ladeliste, Metadaten, SavedVariables: MonkStaggerDB
│   ├── Config.lua               Konstanten, API-Kompatibilität, Defaults, Optionsfenster
│   ├── Display.lua              Ankerrahmen, Leiste, Gebräu-Symbole, Glow/Pulse, Fading
│   └── Core.lua                 Events, Zustand, Empfehlungs-Engine, Slash-Befehle
├── tests/                       Testlauf gegen eine WoW-API-Attrappe (ohne Spiel lauffähig)
├── scripts/                     install.sh, package.sh
└── .github/workflows/           CI (Syntax, Luacheck, Tests) und Release
```

Die Module kommunizieren ausschließlich über die private Addon-Tabelle (`local addonName, ns = ...`).

## Funktionsumfang

**Spezialisierungsprüfung** — Alle UI-Elemente werden nur angezeigt, wenn Klasse `MONK` **und** Spec-ID `268` (Braumeister) vorliegen. Bei Spec-Wechsel wird `COMBAT_LOG_EVENT_UNFILTERED` dynamisch ab- bzw. angemeldet, um außerhalb der Spec keine Last zu erzeugen.

**Stagger-Tracking** — `UnitStagger("player")` gegen `UnitHealthMax("player")`, Aktualisierung alle 50 ms plus ereignisgetrieben (`UNIT_HEALTH`, `UNIT_AURA`, `SPELL_UPDATE_COOLDOWN`, `SPELL_UPDATE_CHARGES`).

**Schwellenwerte** (konfigurierbar, in % des maximalen Lebens):

| Stufe | Standard | Farbe |
|---|---|---|
| Leicht | < 30 % | Grün |
| Mittel | 30 – 60 % | Gelb |
| Schwer | > 60 % | Rot |

**Empfehlungs-Engine** — Hebt Läuterndes bzw. Himmlisches Gebräu durch Pulsieren und/oder Leuchten hervor:

*Läuterndes Gebräu* (119582)
1. **Notfall** – Leben unter der Notfallschwelle (Standard 40 %) und Stagger aktiv.
2. **Regulär** – Stagger über der Schwelle (Standard 60 % max. Leben) **und** die Läuterung entfernt mindestens den Mindestwert (Standard 5 % max. Leben). Der zweite Teil verhindert Empfehlungen, die kaum defensiven Wert haben.
3. **Ladungsschutz** – Eine Ladung würde durch das Ladungslimit verfallen und die Läuterung wäre noch spürbar.

*Himmlisches Gebräu* (322507)
1. Genügend Stapel **Geläutertes Chi** (386963) für einen maximalen Schild (Standard 3).
2. Leben unter der Notfallschwelle (Standard 50 %).

Sämtliche Schwellen sind Heuristiken und über das Optionsfenster anpassbar – auch der Anteil, den Läuterndes Gebräu entfernt (Standard 50 %), falls sich das Balancing ändert.

**Kampfsteuerung** — Sofortiges Einblenden ohne Fade bei `PLAYER_REGEN_DISABLED` und bei eingehendem Schaden (Combat-Log-Auswertung auf die eigene GUID). Ausblenden erst, wenn Kampf beendet, Stagger auf 0 **und** die Nachlaufzeit seit dem letzten Treffer abgelaufen ist (Standard 5 s).

## Slash-Befehle

`/msd` oder `/stagger`

| Befehl | Wirkung |
|---|---|
| *(ohne Argument)* | Einstellungen öffnen |
| `lock` / `unlock` / `toggle` | Ankerrahmen sperren / freigeben / umschalten |
| `test` | Testanzeige mit simuliertem Stagger-Verlauf |
| `on` / `off` | Anzeige aktivieren / deaktivieren |
| `reset` | Position zurücksetzen |
| `resetall` | Alle Einstellungen zurücksetzen (mit Bestätigung) |
| `status` | Aktuellen Zustand im Chat ausgeben |
| `debug` | Debug-Ausgaben umschalten |

Bei entsperrtem Anker: linke Maustaste zum Ziehen, rechte Maustaste sperrt wieder.

## Einstellungen

Registriert über `Settings.RegisterCanvasLayoutCategory` (mit Rückfall auf `InterfaceOptions_AddCategory` für ältere Clients) unter *Interface → AddOns → Monk Stagger Display*.

Bereiche: Allgemein, Darstellung, Stagger-Schwellenwerte, Farben, Text, Sichtbarkeit, Empfehlungs-Engine, Aktionen.

Alle Werte liegen in `MonkStaggerDB` und überleben Sitzungen — inklusive Ankerposition (`point`, `relPoint`, `x`, `y`).

## Kompatibilität

`Config.lua` kapselt die API-Zugriffe, sodass sowohl die neuen als auch die alten Varianten funktionieren:

- `C_Spell.GetSpellCooldown` / `GetSpellCharges` / `GetSpellTexture` mit Rückfall auf die globalen Funktionen
- `C_SpecializationInfo.GetSpecialization` mit Rückfall auf `GetSpecialization`
- `ColorPickerFrame:SetupColorPickerAndShow` mit Legacy-Pfad (invertierte Opacity)
- `C_UnitAuras.GetPlayerAuraBySpellID` für Stapel von Geläutertem Chi

Schieberegler und Farbwähler sind ohne Blizzard-Templates gebaut, um Brüche bei UI-Umbauten zu vermeiden.

## Entwicklung

```bash
luacheck MonkStaggerDisplay tests     # Lint (0 Warnungen erwartet)
lua5.1 tests/run_tests.lua            # 113 Prüfungen gegen die API-Attrappe
bash scripts/package.sh               # dist/MonkStaggerDisplay-<version>.zip
```

Der Testlauf lädt die echten Addon-Dateien gegen `tests/mock_wow.lua` und prüft
Ladevorgang, Ereignisverarbeitung, Schwellenlogik an den Grenzwerten,
Empfehlungs-Engine, Slash-Befehle, Optionsfenster und Persistenz.
Er ersetzt keinen Test im Spiel – die Darstellung selbst wird nicht gerendert.

### Release

Version in der TOC erhöhen, `CHANGELOG.md` ergänzen, dann:

```bash
git tag v1.0.5 && git push origin v1.0.5
```

Der Release-Workflow prüft, dass der Tag zur TOC-Version passt, baut das Archiv
und veröffentlicht es als GitHub-Release.

## Bekannte Einschränkungen

- **Gesperrte Werte unter Midnight:** Der Client gibt `UnitHealth("player")` sowie
  Ladungsstand und Abklingzeit der Gebräue als *secret value* aus — ein getaintetes
  AddOn darf damit nicht rechnen. Ist ein Wert nicht lesbar, trifft das AddOn bewusst
  **keine** Aussage: Die beiden Notfall-Empfehlungen (Läutern bzw. Schild unterhalb
  einer Lebensschwelle) lösen dann nicht aus, und der Ladungszähler zeigt `?` statt
  einer geratenen Zahl. Stagger-Anzeige, Schwellenfarben und die Empfehlung über
  Geläutertes Chi arbeiten unverändert. `/msd status` weist aus, was gerade gesperrt
  ist. Betrifft alle Fassungen ab 1.0.1.
- **Geläutertes Chi (386963):** Die Spell-ID konnte nicht gegen den Client verifiziert
  werden. Findet das AddOn die Aura nicht, bleibt für Himmlisches Gebräu nur der
  Notfallpfad über das Leben — der wiederum ausfällt, solange dieses gesperrt ist.
  Die ID steht als Konstante in `Config.lua`.
- Die Empfehlungswerte sind Heuristiken, keine Simulation. Insbesondere „Läuterndes
  Gebräu entfernt 50 %" ist ein konfigurierbarer Startwert.
