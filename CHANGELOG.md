# Changelog

Alle nennenswerten Änderungen an diesem Projekt werden hier dokumentiert.
Das Format orientiert sich an [Keep a Changelog](https://keepachangelog.com/de/1.1.0/),
die Versionierung an [Semantic Versioning](https://semver.org/lang/de/).

## [Unveröffentlicht]

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

[Unveröffentlicht]: https://github.com/Basti2405/MonkStaggerDisplay/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/Basti2405/MonkStaggerDisplay/releases/tag/v1.0.0
