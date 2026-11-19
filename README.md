<p align="center"><img src="bilder/conti_icon.png" width="120" alt="Conti"></p>

<h1 align="center">Conti</h1>

<p align="center"><b>Buchhaltung für Selbständige in der Schweiz</b><br>
Für Windows und Android · Open Source (GPL-3.0) · <a href="README.en.md">English</a></p>

---

Conti ist ein Kassenbuch („Milchbüechli“) für Einzelfirmen und Selbständige: Einnahmen, Ausgaben, Belege und Konten an einem Ort, auf dem Computer und auf dem Handy. Später kommen Kundinnen und Kunden, Aufträge, Rechnungen mit Schweizer QR-Zahlteil und der Jahresabschluss für die Steuererklärung dazu.

![Conti auf dem Surface, dunkel](bilder/surface_dunkel.png)

![Conti auf dem Handy](bilder/handy_dunkel.png)

## Was Conti heute kann

- **Buchungen erfassen:** Einnahmen, Ausgaben und Umbuchungen zwischen eigenen Konten, mit Datum, Text, Konto und Kategorie. Eine Quittung lässt sich auf mehrere Kategorien aufteilen.
- **Konten** wie Bank, PostFinance, Bargeld und TWINT, mit Anfangsbestand und aktuellem Saldo.
- **Kategorien** für Selbständige, fertig eingerichtet und änderbar, auch mit Unterkategorien (z. B. Spesen → Fahrspesen).
- **Belege** an jede Buchung hängen: auf dem Handy direkt fotografieren, am Computer PDF oder Bild wählen.
- **Übersicht:** Gewinn des Jahres, Einnahmen und Ausgaben, Monatsbalken, Summen pro Kategorie, Kontostände.
- **Suchen und filtern** nach Jahr, Art, Konto, Kategorie und Text.
- **Kunden** mit Adresse, Kontakt und Notizen. Die Kundenkarte zeigt Aufträge, Aufgaben, Buchungen und den offenen Betrag.
- **Produkte** mit Preis und Einheit (pauschal, pro Stunde, pro Lektion, pro Stück).
- **Aufträge** jeder Art (Gig, Lektionen-Abo, Grafik …) mit Positionen und Stand von „offen“ bis „bezahlt“. Auftragsarten legst du selbst an.
- **Abos** mit frei wählbarer Anzahl Lektionen: Lektionen abhaken, Conti zählt mit und erinnert, wenn das Abo aufgebraucht ist. Mit einem Knopf entsteht das nächste Abo.
- **Aufgaben** mit Frist und Farb-Ampel (gelb, orange, rot), auf der Startseite und in der Kundenkarte, dazu **Erinnerungen als Mitteilung** auf Android und Windows.
- **Mein Geschäft:** Name, Adresse, IBAN (mit Prüfung, erkennt QR-IBAN), Logo, Unterschrift, Kanton. Jede Person richtet ihr eigenes Geschäft ein, nichts davon steht im Programm.
- **Import** aus der früheren Buchhaltungs-App (Datei `.json`), mit Vorschau. Ein zweiter Import erzeugt nichts doppelt.
- **Abgleich über Dropbox** zwischen Windows und Android: beim Start, alle zwei Minuten und kurz nach jeder Änderung. Was zwei Geräte ohne Netz erfassen, wird zusammengeführt. Die Daten liegen in deiner Dropbox im Ordner „Apps“.
- **Sicherungen:** automatisch einmal am Tag, dazu von Hand als ZIP-Datei. Einspielen löscht nie etwas.
- **Hell und dunkel**, Deutsch und Englisch. Bedienbar mit Finger, Stift, Maus und Tastatur.
- **Updates** direkt in der App: *Einstellungen → Über Conti → Nach Updates suchen*.

## Kommt bald

- [x] Abgleich über **Dropbox** zwischen Windows und Android
- [x] **Kunden, Produkte und Aufträge** (Gig, Lektionen-Abo, Grafik-Auftrag …) und **Aufgaben** mit Fristen-Ampel
- [ ] **Rechnungen** als PDF mit **Schweizer QR-Zahlteil**, Zahlungen verbuchen, Mahnungen
- [ ] **Jahresabschluss** für die Steuererklärung (für alle Kantone, zuerst Luzern)
- [ ] **MWST**, falls man pflichtig wird (8,1 %, 2,6 %, 3,8 %, effektiv oder Saldosteuersatz)

## Installieren

Unter [Releases](https://github.com/rawkhawk0663/conti/releases/latest) liegt die neueste Version.

- **Windows 10/11:** `Conti-Setup.exe` herunterladen und starten. Meldet Windows „Der Computer wurde durch Windows geschützt“: *Weitere Informationen → Trotzdem ausführen*. Ohne Installation: `Conti-Windows.zip` entpacken und `Conti.exe` starten.
- **Android:** `Conti-Android.apk` auf dem Handy herunterladen und öffnen. Android fragt, ob Apps aus dieser Quelle installiert werden dürfen.

## Deine Daten

Conti hat kein Konto und keinen Server. Alles liegt auf deinen Geräten (unter Windows in `%APPDATA%\Conti\Conti\Daten`) und, wenn du es verbindest, in deiner eigenen Dropbox. Gelöschtes bleibt als Vermerk erhalten und lässt sich zurückholen, weil Buchhaltungsunterlagen 10 Jahre aufbewahrt werden müssen.

## Lizenz

Conti ist freie Software unter der [GNU General Public License v3.0](LICENSE). Du darfst Conti nutzen, verändern und weitergeben. Veränderte Fassungen müssen ebenfalls unter der GPL-3.0 offen bleiben.

Schriften: [Sora](https://fonts.google.com/specimen/Sora) und [IBM Plex Sans](https://fonts.google.com/specimen/IBM+Plex+Sans), beide unter der SIL Open Font License.
