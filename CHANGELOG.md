# Changelog

Alle nennenswerten Änderungen an diesem Projekt werden hier dokumentiert.
Das Format orientiert sich an [Keep a Changelog](https://keepachangelog.com/de/1.1.0/),
die Versionierung an [Semantic Versioning](https://semver.org/lang/de/).

## [Unveröffentlicht]

## [1.0.5] – 2026-08-30

### Behoben
- **`attempt to compare local 'charges' (a secret number value)` in
  `Core.lua:63`.** Der Sperrvermerk aus 1.0.1 betraf nicht nur `UnitHealth`:
  `C_Spell.GetSpellCharges` liefert `currentCharges`, `cooldownStartTime` und
  `cooldownDuration` ebenfalls gesperrt aus, `maxCharges` dagegen als normale
  Zahl. Der Vergleich `charges < maxCharges` warf deshalb mitten in
  `FillSpellInfo` — und riss `BuildState`, `Refresh` und damit die gesamte
  Aktualisierung mit. Betroffen war auch `C_Spell.GetSpellCooldown`.

### Geändert
- `ns.GetSpellCooldownInfo` und `ns.GetSpellChargeInfo` filtern ihre
  Zahlenwerte jetzt an der Quelle über `ns.SafeNumber`. Keine Aufrufstelle
  kann den Fehler dadurch noch auslösen.
- `ns.GetSpellChargeInfo` meldet zusätzlich als erstes Ergebnis, **ob** der
  Zauber Ladungen besitzt. Ohne diese Trennung würde ein Gebräu mit
  gesperrtem Ladungsstand fälschlich als Zauber ohne Ladungssystem behandelt
  und über die Abklingzeit auf „bereit" geraten.
- Neues Feld `info.unknown`: Ist der Ladungsstand nicht lesbar, gilt das
  Gebräu **nicht** als bereit und es gibt keine Empfehlung — dieselbe Linie
  wie beim Leben in 1.0.1, lieber keine Aussage als eine geratene.
- Die Rohwerte bleiben in `info.raw*` erhalten und gehen ungelesen an
  Blizzards `Cooldown:SetCooldown`. Die Wischanzeige der Abklingzeit
  funktioniert damit weiter, obwohl das Addon die Zahlen nicht kennt; der
  Aufruf ist in `pcall` gekapselt.
- Der Ladungszähler zeigt bei gesperrtem Wert `?` statt einer erfundenen `0`,
  und das Symbol wird nicht mehr ausgegraut — „nicht verfügbar" wäre eine
  Behauptung, die sich gerade nicht treffen lässt.
- `/msd status` weist gesperrte Werte jetzt aus. Ohne diese Zeile wirkt ein
  Client, der Leben oder Ladungen sperrt, schlicht defekt.
- Die Test-Attrappe kann per `C_Spell.__secret` auf das Midnight-Verhalten
  umschalten; ein Testblock prüft Absturzfreiheit, ausbleibende Empfehlungen,
  die Beschriftung und die Rückkehr zum Normalbetrieb.

## [1.0.4] – 2026-08-30

### Behoben
- **`bad argument #1 to 'OpenSettingsPanel'` beim Öffnen der Einstellungen.**
  `RegisterSettings` hat die von Blizzard vergebene Kategorie-ID direkt nach
  der Registrierung mit dem Anzeigenamen überschrieben
  (`category.ID = ns.ADDON_TITLE`). In Midnight reicht
  `Settings.OpenToCategory` diesen Wert unverändert an
  `C_SettingsUtil.OpenSettingsPanel` weiter, und das akzeptiert
  ausschließlich eine Zahl im Int32-Bereich. Betroffen waren `/msd`,
  `/msd config` und der Klick im Addon-Kompartiment.

### Geändert
- Die Kategorie-ID bleibt jetzt unangetastet. `OpenSettings` liest sie über
  `category:GetID()`, prüft mit `type(id) == "number"` und fällt nur bei
  einer nicht-numerischen ID auf den Anzeigenamen zurück – für ältere
  Clients, die den Namen selbst auflösen. Beide Aufrufe sind in `pcall`
  gekapselt; erst wenn keiner greift, erscheint eine Meldung im Chat.
- Der Zweig für `InterfaceOptionsFrame_OpenToCategory` prüft zusätzlich, ob
  `self.panel` existiert, statt `nil` weiterzureichen.
- Die Test-Attrappe vergibt jetzt wie das Spiel eine numerische Kategorie-ID
  und wirft in `OpenToCategory` bei allem anderen. Drei Testfälle prüfen die
  ID, den fehlerfreien Aufruf und den tatsächlich übergebenen Wert.

## [1.0.3] – 2026-08-30

### Behoben
- **`Attempt to register unknown event "LEARNED_SPELL_IN_TAB"`.** Dieses
  Ereignis gibt es in Midnight nicht mehr. Der Fehler warf mitten in
  `Core:Initialize()` — und riss **alle Anmeldungen danach mit**:
  `PLAYER_REGEN_DISABLED`, `PLAYER_REGEN_ENABLED`, die beiden
  Cooldown-Ereignisse sowie sämtliche `UNIT_*`-Ereignisse blieben
  unregistriert. Dass die Anzeige trotzdem lief, lag allein an der
  `OnUpdate`-Schleife, die vorher gesetzt wird.

### Geändert
- Alle Ereignisse laufen jetzt über `ns.RegisterEventSafely`, das den Namen
  zuvor mit `C_EventUtils.IsEventValid` prüft und zusätzlich in `pcall`
  gekapselt ist. Ein künftig entferntes Ereignis kann die Initialisierung
  damit nicht mehr abbrechen.
- Das Ereignis wurde ersatzlos gestrichen statt durch
  `LEARNED_SPELL_IN_SKILL_LINE` ersetzt: `FillSpellInfo` prüft ohnehin bei
  jedem Durchlauf, ob die Gebräue bekannt sind.
- Die Test-Attrappe wirft bei unbekannten Ereignissen jetzt genau wie das
  Spiel; ein Testfall prüft, dass nach einem solchen Fehlversuch alle
  übrigen Ereignisse trotzdem angemeldet sind.

## [1.0.2] – 2026-08-30

### Behoben
- **`ADDON_ACTION_FORBIDDEN` beim Spezialisierungswechsel.** Das Addon meldete
  `COMBAT_LOG_EVENT_UNFILTERED` dynamisch an — aus `UpdateSpecialization`
  heraus, also aus einem Ereignis-Handler. `PLAYER_SPECIALIZATION_CHANGED`
  feuert aber aus geschütztem Kontext, und dort ist `RegisterEvent` aus
  Addon-Code verboten. Etablierte Addons (Details, WeakAuras) registrieren
  dieses Ereignis ausschließlich beim Laden.

### Geändert
- **Der Kampflog wird gar nicht mehr ausgewertet.** Eingehender Schaden wird
  jetzt am Anstieg des Staggers erkannt. Für einen Braumeister ist das das
  unmittelbarere Signal, es kostet kein einziges Ereignis, und die
  hochfrequenteste Ereignisquelle des Spiels entfällt vollständig.
- Sämtliche Ereignisanmeldungen erfolgen nur noch in `Core:Initialize()`,
  also beim Laden und außerhalb jedes geschützten Kontexts.
- `playerGUID` entfernt — es diente allein der Kampflog-Auswertung.

## [1.0.1] – 2026-08-29

### Behoben
- **Lua-Fehler bei jedem Aktualisierungslauf** (2469 Auslösungen in einer
  Sitzung gemeldet): `Core.lua:151: attempt to perform arithmetic on local
  'health' (a secret number value)`. Seit Midnight (12.0) liefert
  `UnitHealth("player")` einen gesperrten Wert, mit dem ein getaintetes Addon
  nicht rechnen darf; `UnitHealthMax` bleibt dagegen eine normale Zahl.
  Alle Unit-Werte laufen jetzt durch `ns.SafeNumber`, das gesperrte Werte
  über `issecretvalue` erkennt und `nil` zurückgibt.
- `Refresh` fragt außerhalb der Braumeister-Spezialisierung keine Unit-Werte
  mehr ab, sondern blendet nur noch aus. Der gemeldete Fehler trat auch bei
  `isBrewmaster = false` auf, weil `UpdateSpecialization` den Zustand
  trotzdem neu aufgebaut hat.

### Geändert
- Ist das Leben nicht lesbar, bleibt `healthPct` **nil** statt auf 100 zu
  raten. Die beiden Notfallpfade der Empfehlungs-Engine (Läutern und Schild
  unterhalb einer Lebensschwelle) lösen dann nicht aus. Stagger-Anzeige,
  Schwellenfarben und die übrigen Empfehlungen arbeiten unverändert weiter.
- Der Testlauf bildet gesperrte Werte jetzt als Objekte nach, deren
  Rechenoperationen denselben Fehler werfen wie im Spiel — sonst hätte der
  Test den Fehler nicht reproduzieren können.

## [1.0.0] – 2026-08-29

### Hinzugefügt
- Echtzeit-Stagger-Tracking über `UnitStagger("player")` gegen `UnitHealthMax("player")`,
  Aktualisierung im 50-ms-Takt plus ereignisgetrieben.
- Spezialisierungsprüfung: UI erscheint ausschließlich als Braumeister (Spec-ID 268).
- Konfigurierbare Schwellenwerte: leicht (< 30 %), mittel (30–60 %), schwer (> 60 %)
  des maximalen Lebens, jeweils mit eigener Farbe und Markierung auf der Leiste.
- Empfehlungs-Engine für Läuterndes Gebräu (119582) mit drei Pfaden – Notfall,
  regulärer Schwellwert mit Mindest-Absolutwert und Ladungsschutz.
- Empfehlungs-Engine für Himmlisches Gebräu (322507) auf Basis von
  Geläutertem Chi (386963) sowie einer Notfallschwelle.
- Hervorhebung wahlweise als Pulsieren, Leuchten, beides oder aus.
- Kampfsteuerung: sofortiges Einblenden bei `PLAYER_REGEN_DISABLED` und bei
  eingehendem Schaden, Ausblenden erst nach Kampfende, Stagger 0 und Nachlaufzeit.
- Beweglicher Ankerrahmen, Position persistent in `MonkStaggerDB`.
- Optionsfenster mit 44 Bedienelementen über `Settings.RegisterCanvasLayoutCategory`.
- Slash-Befehle `/msd` und `/stagger` inklusive Testanzeige.
- Eintrag im Addon-Kompartiment (Links: Optionen, Rechts: Anker sperren).
- Test-Harness mit WoW-API-Attrappe, lauffähig außerhalb des Spiels.

[Unveröffentlicht]: https://github.com/Basti2405/MonkStaggerDisplay/compare/v1.0.3...HEAD
[1.0.3]: https://github.com/Basti2405/MonkStaggerDisplay/releases/tag/v1.0.3
[1.0.2]: https://github.com/Basti2405/MonkStaggerDisplay/releases/tag/v1.0.2
[1.0.1]: https://github.com/Basti2405/MonkStaggerDisplay/releases/tag/v1.0.1
[1.0.0]: https://github.com/Basti2405/MonkStaggerDisplay/releases/tag/v1.0.0
