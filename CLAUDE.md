# Conti – Hinweise für die Entwicklung

Conti ist eine Buchhaltungs-App für Selbständige in der Schweiz („Milchbüechli“: Einnahmen, Ausgaben, Vermögen), Open Source unter GPL-3.0. Hauptgeräte des Besitzers: Microsoft Surface (Windows) und ein Samsung-Handy (Android). Der Besitzer programmiert nicht selbst. Erkläre Änderungen deshalb in einfacher Sprache und ohne Fachjargon.

Der Bauplan liegt als Artifact „Conti Bauplan“ beim Besitzer. Pakete:
1. **Kassenbuch** (fertig): Buchungen, Konten, Kategorien mit Unterkategorien, Aufteilen, Belege, Übersicht, Ersteinrichtung, Import aus der früheren App, Sicherungen.
2. **Dropbox-Sync** auf Windows **und** Android (Android braucht eine Rückleitung in die App nach der Anmeldung, nicht den Empfänger auf localhost).
3. **Kunden, Produkte, Aufträge** (Auftragsarten frei: Gig, Abo, Grafik …), Abos mit Zähler, **Aufgaben** mit Fristen-Ampel (`Business.deadlineRules`). Die Daten kommen schon jetzt mit dem Import.
4. **Rechnungen** als PDF mit Schweizer QR-Zahlteil, Aufbau wie die bisherige Rechnung des Besitzers (Logo oben links, Absender rechts, grosser Titel, Tabelle Beschreibung/Tarif/Anzahl/Preis, Dankeszeile, Unterschrift, Zahlteil). Alles einstellbar (`InvoiceSettings`, Platzhalter `{rechnungsnummer}`, `{name}`, `{firma}`, `{datum}`). Normale IBAN → Mitteilung, QR-IBAN → QR-Referenz (`Iban.isQrIban`). Seit November 2025 nur strukturierte Adressen.
5. **Jahresabschluss** für alle Kantone (Aufstellung Einnahmen, Ausgaben, Vermögen, Privatbezüge/-einlagen), zuerst Feld-Zuordnung für Luzern.
6. **MWST** (optional, ausgeschaltet): Feld `vat` an Buchungen, Produkten und Positionen ist schon da (Standard „none“).

## Grundsätze (nie brechen)
- **Keine persönlichen Daten im Programm.** Name, Adresse, IBAN, Logo, Unterschrift stehen nur in „Mein Geschäft“ (`geschaeft.json`). Das Projekt ist öffentlich: Nie echte Daten des Besitzers (seine JSON-Datei, seine Rechnungen) einchecken. Tests nutzen erfundene Daten (`test/fixtures/legacy_sample.json`).
- **Kein Konto, kein Server.** Internet nur für „Nach Updates suchen“ (auf Knopfdruck) und später Dropbox.
- **Beträge immer in ganzen Rappen** (`int`, `Money`). Nie `double` für Geld.
- **Nichts geht verloren:** Gelöschtes bleibt als Grabstein (`deleted: true`). Belege werden nie verändert oder gelöscht (10 Jahre Aufbewahrung). Sicherung einspielen und Import führen nur zusammen.
- **Sync-taugliches Datenmodell:** Jeder Eintrag hat ID und `updatedAt` (UTC). Beim Speichern wird mit der Festplatte zusammengeführt (`mergeById`, jüngere Fassung gewinnt). Feste IDs für Standard-Kategorien (`DefaultCategories`), Import-Kategorien bekommen eine ID aus dem Namen (`imp-<sha1>`), damit nichts doppelt entsteht.
- **Keine Hinweise auf andere Apps** in Kommentaren, Tests und Doku (Wunsch des Besitzers). Die frühere App heisst nur „frühere Buchhaltungs-App“. Dienste, mit denen Conti arbeitet (Dropbox), dürfen genannt werden.

## Sprache
- Oberfläche Deutsch (Grundsprache, Schweizer Schreibweise: „ss“ statt „ß“) und Englisch (britisch). **Jeder sichtbare Text** als `tr('Deutsch', 'English')` (`lib/app/l10n.dart`). Kein `const` um Widgets mit `tr(...)`.
- Code-Kommentare deutsch, Bezeichner englisch. Datei- und Ordnernamen im Datenordner und JSON-Schlüssel nie übersetzen.
- Beträge Schweizer Schreibweise: `1'234.50`, negativ mit echtem Minus `−`. Datum `18.11.2026`.
- Beschreibung im Projekt: `README.md` (Deutsch) und `README.en.md` (Englisch), Bilder in `bilder/`. **Bei jeder sichtbaren Änderung nachführen** (neue Funktionen, „Kommt bald“ abhaken). Bildschirmfotos nur mit erfundenen Daten.

## Design (Wunsch des Besitzers, nach einem Bild)
- Dunkle Karten (`#18191D` auf `#0D0E11`), feine grosse Zahlen (IBM Plex Sans 300), Überschriften Sora. Heller Modus gleichwertig.
- Verläufe mit fester Bedeutung (`ContiColors` in `lib/app/theme.dart`): **Mint-Blau** Einnahmen/bezahlt, **Gelb-Pink** Ausgaben/fällig, **Pink-Violett** Gewinn/Hauptknöpfe/App-Symbol, **Türkis-Blau** Umbuchungen/Sync/Hinweise.
- Bausteine in `lib/widgets/visuals.dart`: `SectionCard`, `GradientRing`, `GradientBar`, `GradientButton`, `GradientFab`, `MonthBars`, `AmountText`, `BigNumber`, `CapsLabel`, `ContiMark`, `EmptyState`.
- „Neu“/„Hinzufügen“ immer als schwebender Knopf unten rechts (`GradientFab`), Listen darunter brauchen unten ~110 Punkte Platz. Langes Drücken = Rechtsklick (Menü). Hinweise (`Tooltip`) nur mit der Maus.
- Navigation: ab 840 Punkten Breite Leiste links (`NavigationRail`), sonst unten (`NavigationBar`), `lib/features/shell/home_shell.dart`.
- App-Symbol: `tool/make_icon.py` (Verlauf Pink → Violett, weisses „C“ mit Punkt). Schriften: feste Schnitte aus `tool/make_fonts.py`.

## Daten
Datenordner `<ApplicationSupport>/Daten` (Windows `%APPDATA%\Conti\Conti\Daten`). Dieser Ordner wird in Paket 2 mit Dropbox abgeglichen.
```
conti.json                Markierung (Format conti-daten v1)
geschaeft.json            Mein Geschäft (Format conti-geschaeft v1, jüngste Fassung gewinnt als Ganzes)
konten.json, kategorien.json, kunden.json, produkte.json, auftraege.json, aufgaben.json   ({format, version, items})
buchungen/<jahr>.json     Buchungen eines Jahres (conti-buchungen v1). Beim Verschieben in ein anderes Jahr beide Jahre speichern (`saveEntry(previousYear:)`), beim Laden gewinnt die jüngere Fassung.
belege/<jahr>/<id>.<endung>   Belege
bilder/                   Logo, Unterschrift
```
Gerätespezifisch (nicht abgeglichen): `<ApplicationSupport>/einstellungen.json` (Darstellung, Sprache, `setupDone`, letzte Sicherung, zuletzt gewähltes Konto), `Sicherungen/` (automatisch, 14 Stück), `fehler.log`, `update.log`.
Geschrieben wird immer über eine Zwischendatei (`JsonFile`).

## Import aus der früheren App
`lib/core/import/legacy_import.dart`. Die Datei hat `entries`, `clients`, `products`, `orders`, `tasks`, `company`, `invoiceSettings`, `taskSettings`. Beträge dort in Franken (`double`), `expenseItems` mit einem Eintrag = Unterkategorie, mit mehreren = Aufteilung. Die alte App kennt keine Konten: Beim Import wählt man eines. Belege stehen nur als `storedFileName` (z. B. `2026/…pdf`) drin, die Dateien sucht der Import im gewählten Ordner (direkt oder nach Dateiname). Logo und Unterschrift sind Daten-URLs (SVG). Platzhalter `{deinName}` → `{name}`, `{invoiceNumber}` → `{rechnungsnummer}`. Strasse und Hausnummer werden getrennt (`splitStreet`).

## Aufbau
```
lib/
  app/        l10n, Theme (ContiColors), Updater, Fehlerprotokoll, Version
  core/       money, dates, swiss (IBAN, Kantone), device_settings, backup, conti_state (ContiScope)
    model/    synced (mergeById), entry, account, category, business, crm (Client, Product, Order, Task)
    store/    json_file, data_store
    import/   legacy_import
  features/   shell, overview, entries (Liste, Zeile, Editor), settings (Geschäft, Konten, Kategorien, Daten, Über), import, setup
  widgets/    visuals
```

## Technik
- Flutter `3.47.9` (in `.github/workflows/build.yml`), Material 3. `window_manager` bleibt auf 0.5.x (0.6 braucht beim Testen GTK-Entwicklungsdateien).
- Jeder Push auf `main` baut Windows (`Conti-Windows.zip`, `Conti-Setup.exe`) und Android (`Conti-Android.apk`) und veröffentlicht sie unter Releases in diesem Projekt. „Nach Updates suchen“ holt sie von dort (`Updater.repo`). Versionsnummer `v0.1.<run_number>` über `--dart-define=CONTI_VERSION`.
- Android wird mit festem Schlüssel signiert, wenn die Geheimnisse `CONTI_KEYSTORE` (Base64 der .jks) und `CONTI_KEYSTORE_PASSWORD` gesetzt sind (Alias `conti`). Sonst Test-Schlüssel (dann geht ein Update nur nach Entfernen der App). Den Schlüssel hat der Besitzer, er liegt nie im Projekt.

## Prüfen
```bash
flutter analyze
flutter test
```
Sichtprüfung: `flutter build linux --debug` (braucht `libgtk-3-dev`), unter Xvfb starten, mit `xdotool` bedienen und die Fenstergrösse setzen (`windowsize --sync`), mit `import` Bildschirmfotos machen. Beispieldaten nur erfunden.
