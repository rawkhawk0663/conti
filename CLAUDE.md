# Conti – Hinweise für die Entwicklung

Conti ist eine Buchhaltungs-App für Selbständige in der Schweiz („Milchbüechli“: Einnahmen, Ausgaben, Vermögen), Open Source unter GPL-3.0. Hauptgeräte des Besitzers: Microsoft Surface (Windows) und ein Samsung-Handy (Android). Der Besitzer programmiert nicht selbst. Erkläre Änderungen deshalb in einfacher Sprache und ohne Fachjargon.

Der Bauplan liegt als Artifact „Conti Bauplan“ beim Besitzer. Pakete:
1. **Kassenbuch** (fertig): Buchungen, Konten, Kategorien mit Unterkategorien, Aufteilen, Belege, Übersicht, Ersteinrichtung, Import aus der früheren App, Sicherungen.
2. **Dropbox-Sync** (fertig) auf Windows und Android, siehe „Abgleich“.
3. **Kunden, Produkte, Aufträge, Aufgaben** (fertig), siehe „Kunden und Aufträge“.
4. **Rechnungen** (fertig), siehe „Rechnungen“.
5. **Jahresabschluss** (fertig), siehe „Jahresabschluss“. Feld-Zuordnung bisher nur Luzern.
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
- „Neu“/„Hinzufügen“ immer als schwebender Knopf unten rechts (`GradientFab`), Listen darunter brauchen unten ~110 Punkte Platz. Hinweise (`Tooltip`) nur mit der Maus.
- **Kontextmenüs** (Wunsch des Besitzers): Rechtsklick *und* langes Drücken, über `ContextMenuArea` und `showContextMenu` (`lib/widgets/context_menu.dart`). Auf dem Computer erscheint das Menü an der Stelle des Zeigers bzw. Fingers, auf dem Handy als Blatt von unten. Neue Listen bekommen das auch. Löschen aus dem Menü mit „Rückgängig“ (`showUndo`).
- Navigation: ab 840 Punkten Breite Leiste links (`NavigationRail`), sonst unten (`NavigationBar`), `lib/features/shell/home_shell.dart`. Die Leiste bleibt immer sichtbar (Wunsch des Besitzers): Jeder Bereich hat einen eigenen `Navigator` (`ShellNav.keys`), Seiten wie Buchung oder Auftrag öffnen sich darin und bleiben offen, wenn man den Bereich wechselt. Nochmals auf den gewählten Bereich tippen führt zu seiner ersten Seite. Zurück-Taste (Android) und Escape schliessen zuerst die Seite im sichtbaren Bereich. Fenster (`showDialog`) liegen weiter über allem.
- **Fenster am Computer** (Wunsch des Besitzers): ohne Windows-Titelleiste (`prepareWindow`, `TitleBarStyle.hidden`). Oben rechts drei runde Knöpfe gelb/grün/rot für Minimieren/Maximieren/Schliessen (`WindowButtonsOverlay` in `lib/app/window_buttons.dart`, über allen Seiten). Die AppBar lässt rechts `windowButtonsWidth` frei (`actionsPadding` im Theme). Verschieben am Logo oben in der Leiste (`WindowDragArea`, doppelt klicken maximiert).
- **Escape** schliesst die oberste Seite (Buchung, Auftrag …) wie das Kreuz, ein offenes Menü oder Fenster zuerst (`_onEscape` in `lib/main.dart`). Auch mit dem Cursor in einem Textfeld.
- App-Symbol: `tool/make_icon.py` (Verlauf Pink → Violett, weisses „C“ mit Punkt). Schriften: feste Schnitte aus `tool/make_fonts.py`.

## Daten
Datenordner `<ApplicationSupport>/Daten` (Windows `%APPDATA%\Conti\Conti\Daten`). Dieser Ordner wird in Paket 2 mit Dropbox abgeglichen.
```
conti.json                Markierung (Format conti-daten v1)
geschaeft.json            Mein Geschäft (Format conti-geschaeft v1, jüngste Fassung gewinnt als Ganzes)
konten.json, kategorien.json, kunden.json, produkte.json, auftraege.json, aufgaben.json, auftragsarten.json, anlagen.json, abschluesse.json   ({format, version, items})
buchungen/<jahr>.json     Buchungen eines Jahres (conti-buchungen v1). Beim Verschieben in ein anderes Jahr beide Jahre speichern (`saveEntry(previousYear:)`), beim Laden gewinnt die jüngere Fassung.
belege/<jahr>/<id>.<endung>   Belege
rechnungen/<jahr>/<nummer>.pdf   gestellte Rechnungen und Zahlungserinnerungen (nie verändert)
abschluesse/<jahr>/abschluss-<jahr>.pdf   Jahresabschlüsse (nie überschrieben)
bilder/                   Logo, Unterschrift
```
Gerätespezifisch (nicht abgeglichen): `<ApplicationSupport>/einstellungen.json` (Darstellung, Sprache, `setupDone`, letzte Sicherung, zuletzt gewähltes Konto, Dropbox, Erinnerungen an/aus und Uhrzeit), `Sicherungen/` (automatisch, 14 Stück), `fehler.log`, `update.log`.
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

## Kunden und Aufträge (Paket 3)
- Navigation (Wunsch des Besitzers): Übersicht, Buchungen, Kunden, Aufträge, **Produkte als eigener Punkt**, Einstellungen. Auf dem Handy zeigt die untere Leiste nur Symbole, ohne Beschriftung (Wunsch des Besitzers, sonst zu eng).
- **Auftragsarten** (`OrderKind`, `auftragsarten.json`): frei anlegbar unter Einstellungen → Aufträge & Erinnerungen. Vorschläge mit festen IDs (`kind-gig`, `kind-abo`, …), angelegt bei der Einrichtung bzw. beim Laden, falls es noch nie `kind-…` gab (Grabsteine zählen, Gelöschtes kommt nicht zurück). `Order.kind` ist die ID; ältere Daten mit Namen stellt `_migrateOrderKinds` um (ID aus dem Namen `imp-kind-…`).
- **Abos** (Wunsch des Besitzers): Art mit `subscription`, Grösse frei (`lessons` als Vorschlag, pro Auftrag `Order.lessonsTotal`, 1–200). Lektionen abhaken (`Order.sessions`, mit Datum) speichert sofort. Ist das Abo aufgebraucht: Mitteilung (`Reminders.subscriptionUsedUp`), Hinweis auf der Startseite (`usedUpSubscriptions`) und Knopf „Nächstes Abo anlegen“ (kopiert Kunde, Art, Positionen, Grösse; `followUpId` beendet die Erinnerung).
- Auftragsnummern `<orderPrefix><Jahr>-<4 Ziffern>` (`nextOrderNumber`), änderbar.
- **Aufgaben** mit Fristen-Ampel (`Urgency.of` in `core/deadlines.dart`, Regeln `Business.deadlineRules`, Tage einstellbar). Auf der Startseite (`_TasksCard`), in der Kundenkarte und unter „Alle“ (`TasksScreen`).
- **Mitteilungen** (Wunsch des Besitzers: in der App *und* als Mitteilung): `lib/app/reminders.dart`, `flutter_local_notifications` **22.3.3** (23 verlangt AGP 9.1.1 und compileSdk 37, das passt nicht zu Flutter 3.47), `timezone`, `flutter_timezone`. Android und Windows. Geplant wird bei jeder Änderung alles neu (`Reminders.plan`, höchstens 60 in 90 Tagen): an jedem Ampel-Tag und am Fälligkeitstag zur gewählten Stunde (`reminderHour`, Standard 8). Android: Desugaring in `build.gradle.kts`, Empfänger im Manifest, Erlaubnis wird beim Start gefragt, ungenaue Planung (`inexactAllowWhileIdle`, keine Sonder-Erlaubnis). Windows: `WindowsInitializationSettings` mit fester GUID.
- Seiten: `features/clients/` (Liste, Karte, Formular), `features/orders/` (Liste, Editor, Zeile, Stand-Farben), `features/products/`, `features/tasks/`, `features/settings/work_settings_page.dart`.

## Rechnungen (Paket 4)
- Aufbau wie die bisherige Rechnung des Besitzers: Logo oben links (SVG oder Bild), Absender und Kontakt rechts, Linie, grosser Titel, Empfänger links, rechts Rechnungs-Nr./Auftrags-Nr./Datum/Zahlbar bis, Tabelle Beschreibung/Tarif/Anzahl/Preis, Dankeszeile mit Unterschrift, Gesamtbetrag, unten der QR-Zahlteil. `lib/core/invoice/invoice_pdf.dart` (`buildInvoicePdf`, `InvoiceData`). Bei mehr als etwa vier Positionen kommt der Zahlteil auf eine eigene Seite (`pw.Page` darf nicht überlaufen).
- **QR-Zahlteil** (`swiss_qr.dart`, `QrBill`): Datenformat SPC 0200, Adressen nur strukturiert (Typ „S“, seit November 2025 Pflicht). Normale IBAN → Referenz „NON“ und Mitteilung (`InvoiceSettings.qrMessage`), QR-IBAN (`Iban.isQrIban`) → QR-Referenz aus den Ziffern der Rechnungsnummer (`qrReferenceFrom`, Prüfziffer `mod10Check`). Masse nach Vorgabe: Empfangsschein 62 mm, Zahlteil 148 mm, QR-Code 46 mm mit Schweizer Kreuz 7 mm, Fehlerkorrektur M, Schrift Arimo (gleiche Formen wie Liberation Sans), gestrichelte Linien mit „Vor der Einzahlung abzutrennen“. Ohne vollständige Kundenadresse: leere Felder mit Eckmarken. Geprüft durch Auslesen des QR-Codes aus dem gerenderten PDF (OpenCV).
- Schriften fürs PDF: feste Schnitte in `assets/fonts/pdf/` (`tool/make_pdf_fonts.py`): Roboto Slab (Standard, `InvoiceSettings.font = 'roboto-slab'`) oder Arimo (`'sans'`).
- **Ablauf** (`invoicing.dart`, Knöpfe in `features/invoices/invoice_actions.dart`, Karte „Rechnung“ im Auftrag): „Rechnung stellen“ gleicht zuerst ab (damit kein anderes Gerät die Nummer schon hat), prüft (`Invoicing.problems`, sonst Hinweis mit „Mein Geschäft öffnen“ oder „Ohne QR-Zahlteil“), fragt Nummer (`nextNumber`: `<invoicePrefix><Jahr>-<4 Ziffern>`, doppelte werden abgelehnt), Datum und Frist. Das PDF liegt in `rechnungen/<jahr>/<nummer>.pdf` und wird nie verändert; „Neu erstellen“ legt eine neue Datei an (`-2`, `-3` …). „Zahlung erfassen“ bucht eine Einnahme mit der Rechnung als Beleg und setzt „bezahlt“. „Zahlungserinnerung“ erstellt ein eigenes PDF (`-erinnerung-<n>.pdf`), Daten in `Order.reminders`.
- Der offene Auftrags-Editor übernimmt Änderungen von aussen (Rechnung, Zahlung, Abgleich) über `_absorbExternal`, sonst würde „Sichern“ sie überschreiben.
- Überfällig (`Order.overdue`): rote Marke in der Liste, Karte „Offene Rechnungen“ auf der Startseite, Mitteilung am Tag nach der Frist.
- Einstellungen → Rechnungen: Kürzel, Frist, Texte mit Platzhaltern (`{rechnungsnummer}`, `{name}`, `{firma}`, `{kunde}`, `{datum}`, `{fällig}`, `{auftrag}`), Schrift, Name im Zahlteil, Vorschau.
- Import: Aufträge der früheren App mit Rechnungsnummer gelten als verrechnet; liegt das alte Rechnungs-PDF auf dem Gerät (alter Pfad oder neben dem Belegordner), wird es nach `rechnungen/` kopiert.
- Teilen über `share_plus` 13.3.1 (`lib/app/files.dart`: `openFile`, `shareFile`, `saveCopy`, `openPdfBytes`).

## Jahresabschluss (Paket 5)
- Rechnung in `lib/core/closing/year_report.dart` (`YearReport.compute`, reine Funktion, getestet in `test/closing_test.dart`): Erfolgsrechnung nach Zahlung (Ist), danach Abgrenzung mit offenen Kundenrechnungen (aus Aufträgen: `invoicedAt` ≤ Stichtag, nicht bezahlt) und offenen Lieferantenrechnungen (von Hand). Vermögen am 1.1. und 31.12. (Konten, Debitoren, Anlagen, − Kreditoren), Privatbezüge/-einlagen und **Kontrolle** (`difference` muss 0 sein; Buchungen ohne Konto oder vor dem Anfangsdatum eines Kontos erklären eine Differenz).
- **Gruppen** (`ClosingGroup`, Feld `group` an der Kategorie, sonst von der Oberkategorie, sonst Vorschlag `ClosingGroups.suggest`): Einnahmen, andere Erträge, Waren/Material, Löhne, Miete, Fahrzeug, andere Kosten, **Privatbezug/Privateinlage**. Private Gruppen zählen nirgends als Einnahme/Ausgabe (`ContiState.businessAmount`). Feste Kategorien `cat-private-out`, `cat-private-in` (`ensurePrivateCategories`, wie die Auftragsarten). „Nicht in Auswertungen zählen“ gilt im Abschluss als Privatbezug/-einlage.
- **Anschaffungen:** Schalter in der Buchung (nur Ausgabe ohne Aufteilen) schreibt `Entry.asset` (`AssetInfo`: Art, Methode, Satz; liest auch das Format der früheren App). Solche Buchungen sind keine Ausgabe, sondern laufen über `FixedAsset`/`Depreciation` (`depreciation.dart`): degressiv vom Restwert (Normalsätze ESTV Merkblatt A 1995: Mobiliar 25, Geräte/Instrumente 30, Computer 40, Fahrzeuge 40, Werkzeuge 45 %), linear halber Satz vom Kaufpreis, oder sofort; Restwert bleibt CHF 1, unter CHF 10 geht der Rest auf einmal. Anlagen ohne Buchung (vor Conti gekauft): `anlagen.json` (`Asset`, Restwert am 1.1. eines Jahres). Verkauft/ausgeschieden: `YearClosing.disposed` im Jahr des Verkaufs (die Buchung im alten Jahr bleibt unverändert, weil das Jahr gesperrt sein kann).
- **Pro Jahr** (`abschluesse.json`, `YearClosing`, ID `year-<jahr>`): Fahrzeuge (Privatanteil 0,9 % des Kaufpreises pro Monat, mind. CHF 150), Korrekturen (`Adjustment`: Privatanteil in % einer Kategorie oder Betrag, privat bezahlte Kosten wie Arbeitszimmer, nicht gebuchte Einnahmen), Lieferantenrechnungen, abgehakte Kontostände, Abschluss (`closedAt`, Verlauf `history`), letztes PDF.
- **Abschliessen** sperrt das Jahr: `saveEntry`/`deleteEntry`/`restoreEntry` werfen `YearClosedException` (auch beim Verschieben in ein gesperrtes Jahr), der Editor zeigt die Buchung nur an. Aufheben geht mit Bestätigung und bleibt im Verlauf.
- **PDF** (`closing_pdf.dart`, Schrift wie die Rechnungen) in `abschluesse/<jahr>/abschluss-<jahr>.pdf`, nie überschrieben (`-2` …). **CSV** (`closing_csv.dart`): Strichpunkt, BOM, Beträge mit Punkt, eine Zeile pro Buchungsteil.
- **Kantone** (`canton_forms.dart`): Luzern Formular S2 (S200, S204, S206/S208, S211–S214, S219, S220, S222, S230, S236–S238, S239, S240), S3 (S300–S302, S308, S309, S312 → Ziffer 430, S341, Bank-/Postkonten „G1“ ins Wertschriftenverzeichnis), Privat (S320, S322, S323, S328, S330, S331), Einkommen → Ziffer 110 (Haupterwerb) bzw. 114 (Nebenerwerb, `Business.mainOccupation`). Nummern aus der Wegleitung 2026; die Rückseite von S2 (S221–S246) steht dort nicht vollständig, darum der Hinweis zum Prüfen. Andere Kantone: nur die allgemeine Aufstellung.
- Seite `features/closing/closing_screen.dart` (aus Einstellungen und der Karte „Steuern und Abschluss“ auf der Startseite). Die Karte zeigt die Rücklage für Steuern/AHV (`Business.taxReservePercent`, Standard 25 %) und im ersten Halbjahr den offenen Abschluss des Vorjahres.

## Import aus der früheren App
`lib/core/import/legacy_import.dart`. Die Datei hat `entries`, `clients`, `products`, `orders`, `tasks`, `company`, `invoiceSettings`, `taskSettings`. Beträge dort in Franken (`double`), `expenseItems` mit einem Eintrag = Unterkategorie, mit mehreren = Aufteilung. Die alte App kennt keine Konten: Beim Import wählt man eines. Belege stehen nur als `storedFileName` (z. B. `2026/…pdf`) drin, die Dateien sucht der Import im gewählten Ordner (direkt oder nach Dateiname). Logo und Unterschrift sind Daten-URLs (SVG). Platzhalter `{deinName}` → `{name}`, `{invoiceNumber}` → `{rechnungsnummer}`. Strasse und Hausnummer werden getrennt (`splitStreet`).

## Aufbau
```
lib/
  app/        l10n, Theme (ContiColors), Updater, Fehlerprotokoll, Version
  core/       money, dates, swiss (IBAN, Kantone), device_settings, backup, conti_state (ContiScope)
    model/    synced (mergeById), entry, account, category, business, crm (Client, Product, Order, Task), closing (Abschluss, Anlagen)
    store/    json_file, data_store
    import/   legacy_import
    sync/     cloud_auth, dropbox_api, sync_engine, sync_controller
    invoice/  swiss_qr, invoice_pdf, invoicing
    closing/  depreciation, year_report, canton_forms, closing_pdf, closing_csv
  features/   shell, overview, entries, clients, orders, invoices, closing, products, tasks, settings, import, setup, sync
  widgets/    visuals
```

## Technik
- Flutter `3.47.9` (in `.github/workflows/build.yml`), Material 3. `window_manager` bleibt auf 0.5.x (0.6 braucht beim Testen GTK-Entwicklungsdateien).
- Jeder Push auf `main` baut Windows (`Conti-Windows.zip`, `Conti-Setup.exe`) und Android (`Conti-Android.apk`) und veröffentlicht sie unter Releases in diesem Projekt. „Nach Updates suchen“ holt sie von dort (`Updater.repo`). Versionsnummer `v0.1.<run_number>` über `--dart-define=CONTI_VERSION`.
- Android-Updates: über „Nach Updates suchen“ (öffnet die Download-Seite) oder automatisch mit Obtainium (Adresse des Projekts eintragen; die Version im Release-Tag `v0.1.n` passt zur versionName `0.1.n` der APK). Dafür muss jede APK mit demselben Schlüssel signiert sein.
- Android wird mit festem Schlüssel signiert, wenn die Geheimnisse `CONTI_KEYSTORE` (Base64 der .jks) und `CONTI_KEYSTORE_PASSWORD` gesetzt sind (Alias `conti`). Sonst Test-Schlüssel (dann geht ein Update nur nach Entfernen der App). Den Schlüssel hat der Besitzer, er liegt nie im Projekt.

## Prüfen
```bash
flutter analyze
flutter test
```
Sichtprüfung: `flutter build linux --debug` (braucht `libgtk-3-dev`), unter Xvfb starten, mit `xdotool` bedienen und die Fenstergrösse setzen (`windowsize --sync`), mit `import` Bildschirmfotos machen. Beispieldaten nur erfunden.
