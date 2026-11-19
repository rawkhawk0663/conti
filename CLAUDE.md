# Conti – Hinweise für die Entwicklung

Conti ist eine Buchhaltungs-App für Selbständige in der Schweiz („Milchbüechli“: Einnahmen, Ausgaben, Vermögen), Open Source unter GPL-3.0. Hauptgeräte des Besitzers: Microsoft Surface (Windows) und ein Samsung-Handy (Android). Der Besitzer programmiert nicht selbst. Erkläre Änderungen deshalb in einfacher Sprache und ohne Fachjargon.

Der Bauplan liegt als Artifact „Conti Bauplan“ beim Besitzer. Pakete:
1. **Kassenbuch** (fertig): Buchungen, Konten, Kategorien mit Unterkategorien, Aufteilen, Belege, Übersicht, Ersteinrichtung, Import aus der früheren App, Sicherungen.
2. **Dropbox-Sync** (fertig) auf Windows und Android, siehe „Abgleich“.
3. **Kunden, Produkte, Aufträge** (Auftragsarten frei: Gig, Abo, Grafik …), Abos mit Zähler, **Aufgaben** mit Fristen-Ampel (`Business.deadlineRules`). Die Daten kommen schon jetzt mit dem Import.
4. **Rechnungen** als PDF mit Schweizer QR-Zahlteil, Aufbau wie die bisherige Rechnung des Besitzers (Logo oben links, Absender rechts, grosser Titel, Tabelle Beschreibung/Tarif/Anzahl/Preis, Dankeszeile, Unterschrift, Zahlteil). Alles einstellbar (`InvoiceSettings`, Platzhalter `{rechnungsnummer}`, `{name}`, `{firma}`, `{datum}`). Normale IBAN → Mitteilung, QR-IBAN → QR-Referenz (`Iban.isQrIban`). Seit November 2025 nur strukturierte Adressen.
5. **Jahresabschluss** für alle Kantone (Aufstellung Einnahmen, Ausgaben, Vermögen, Privatbezüge/-einlagen), zuerst Feld-Zuordnung für Luzern.
6. **MWST** (optional, ausgeschaltet): Feld `vat` an Buchungen, Produkten und Positionen ist schon da (Standard „none“).

## Grundsätze (nie brechen)
- **Keine persönlichen Daten im Programm.** Name, Adresse, IBAN, Logo, Unterschrift stehen nur in „Mein Geschäft“ (`geschaeft.json`). Das Projekt ist öffentlich: Nie echte Daten des Besitzers (seine JSON-Datei, seine Rechnungen) einchecken. Tests nutzen erfundene Daten (`test/fixtures/legacy_sample.json`).
- **Kein Konto, kein Server.** Internet nur für „Nach Updates suchen“ (auf Knopfdruck) und den Abgleich mit der eigenen Dropbox.
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

## Abgleich (Paket 2)
- `lib/core/sync/`: `cloud_auth.dart` (OAuth mit PKCE), `dropbox_api.dart` (`CloudApi`, `DropboxApi`), `sync_engine.dart`, `sync_controller.dart` (`SyncScope`). Seite `features/sync/sync_page.dart`, Zustand oben in Übersicht und Buchungen (`SyncStatusButton`).
- **Anmeldung:** Dropbox erlaubt als Rückleitung nur `https` oder `localhost`, keine eigenen App-Adressen. Windows/Linux: Browser meldet sich bei `http://localhost:53682/` zurück (`signIn`, muss in der Dropbox-App als Redirect-URI stehen). Android: ohne Rückleitung, Dropbox zeigt einen Code, den man in Conti einfügt (`codeSignInUrl`/`finishCodeSignIn`). Auf dem Computer gibt es den Code-Weg als Ersatz.
- Schlüssel: Geheimnis `DROPBOX_APP_KEY` im GitHub-Projekt, beim Bauen per `--dart-define`. Fehlt er, ist der Abgleich ausgegraut. Dropbox-App: „Scoped access“, „App folder“ (`Apps/<Name>`), Rechte `files.metadata.read`, `files.content.read`, `files.content.write`, „Allow public clients (PKCE)“ an.
- Der dauerhafte Zugang (`dropboxToken`) und das Konto (`dropboxAccount`) liegen in den Geräteeinstellungen. Stand pro Datei (`rev` beim Dienst, Prüfsumme des eigenen Inhalts) in `<ApplicationSupport>/abgleich_dropbox.json`, beim Verbinden vergessen.
- **Regeln (`SyncEngine`):** Weil nie etwas gelöscht wird, braucht es keine Basis wie bei einem Ordner-Abgleich. JSON-Dateien werden immer zusammengeführt (`mergeJson`: Einträge pro ID, jüngeres `updatedAt` gewinnt; `geschaeft.json` als Ganzes; sonst die eigene Fassung), das Ergebnis geht auf beide Seiten. Belege und Bilder ändern sich nie: was fehlt, wird kopiert, gelöscht wird nichts. Die Markierung `conti.json` kommt zuletzt. Lesen, Zusammenführen und Schreiben einer Datei laufen unter der Sperre des Datenordners (`DataStore.withLock`), damit Speichern und Abgleich sich nie überschreiben. Nach Änderungen liest `ContiState.reload` neu ein.
- **Wann:** beim Start, alle 2 Minuten, 4 Sekunden nach jeder eigenen Änderung (`ContiState.onLocalChange`), wenn die App wieder in den Vordergrund kommt, auf Knopfdruck.
- **Zweites Gerät:** In der Einrichtung „Schon auf einem anderen Gerät eingerichtet“ → Dropbox verbinden → Abgleich → fertig (keine Standard-Konten, sonst gäbe es sie doppelt).
- Tests: `test/sync_test.dart` mit zwei Geräten und einer Dropbox im Arbeitsspeicher.

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
    sync/     cloud_auth, dropbox_api, sync_engine, sync_controller
  features/   shell, overview, entries (Liste, Zeile, Editor), settings (Geschäft, Konten, Kategorien, Daten, Über), import, setup, sync
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
