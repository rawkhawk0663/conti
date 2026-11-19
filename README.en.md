<p align="center"><img src="bilder/conti_icon.png" width="120" alt="Conti"></p>

<h1 align="center">Conti</h1>

<p align="center"><b>Bookkeeping for self-employed people in Switzerland</b><br>
For Windows and Android · Open source (GPL-3.0) · <a href="README.md">Deutsch</a></p>

---

Conti is a simple cash book for sole traders and freelancers: income, expenses, receipts and accounts in one place, on your computer and on your phone. Plus clients, orders, invoices with the Swiss QR payment part and the year-end report for your tax return.

![Conti on a Surface, dark mode](bilder/surface_dunkel.png)

![Conti on a phone](bilder/handy_dunkel.png)

## What Conti does today

- **Record entries:** income, expenses and transfers between your own accounts, with date, description, account and category. One receipt can be split across several categories.
- **Accounts** such as bank, PostFinance, cash and TWINT, with opening and current balance.
- **Categories** for self-employed people, ready to use and editable, including subcategories (e.g. Expenses → Travel).
- **Receipts** attached to any entry: take a photo on your phone, or choose a PDF or image on the computer.
- **Overview:** profit of the year, income and expenses, monthly bars, totals per category, account balances.
- **Search and filter** by year, type, account, category and text.
- **Clients** with address, contact and notes. The client card shows orders, tasks, entries and the amount due.
- **Products** with price and unit (flat, per hour, per lesson, per piece).
- **Orders** of any kind (gig, lesson pack, design job …) with items and a status from “open” to “paid”. You define the order kinds yourself.
- **Lesson packs** with any number of lessons: tick off lessons, Conti counts and reminds you when the pack is used up. One button creates the next pack.
- **Invoices as PDF with the Swiss QR payment part:** from an order with one button. Logo, sender, recipient, items, closing note with signature and payment part with receipt. Regular IBAN with a message or QR-IBAN with a QR reference. Invoices are kept and never changed, and can be opened, sent by email or WhatsApp, and saved.
- **Record payments:** the income is booked with the invoice as receipt, and the order is set to “paid”. Open and overdue invoices appear on the home page, with a reminder the day after the due date and a **payment reminder** PDF at the push of a button.
- **Year-end report for the tax return:** income and expenses, assets on 1 January and 31 December, private withdrawals and deposits, with a check that everything adds up. As a PDF to attach and as a table (CSV) for Excel or an accountant. For **Lucerne** the amounts are listed next to the fields of forms S2 and S3. Afterwards the year can be closed and its entries are locked.
- **Depreciation:** mark a larger purchase (instrument, amplifier, laptop) as an “acquisition” in the entry. Conti depreciates it every year using the tax administration’s rates.
- **Private shares** for a car (flat 0.9 % per month), phone or internet, plus business costs paid privately such as a home office. For money between business and private there are the categories “Private withdrawal” and “Private deposit”.
- **Set aside for taxes:** the home page shows roughly how much to put aside (percentage adjustable).
- **Tasks** with a deadline and colours (yellow, orange, red), on the home page and in the client card, plus **reminder notifications** on Android and Windows.
- **My business:** name, address, IBAN (validated, recognises QR-IBANs), logo, signature, canton. Everyone sets up their own business, none of it is built into the program.
- **Import** from the previous bookkeeping app (`.json` file), with a preview. Importing twice creates no duplicates.
- **Sync via Dropbox** between Windows and Android: at start-up, every two minutes and shortly after every change. What two devices record offline is merged. The data lives in your Dropbox in the “Apps” folder.
- **Backups:** automatically once a day, plus by hand as a ZIP file. Restoring never deletes anything.
- **Light and dark**, German and English. Works with finger, pen, mouse and keyboard. Right-click (or a long press) opens a menu on entries, clients, orders, products and tasks. Escape closes the open page. On the computer there is no title bar, just three round window buttons at the top right; drag the window by the logo.
- **Updates** right in the app: *Settings → About Conti → Check for updates*.

## Coming soon

- [x] **Dropbox** sync between Windows and Android
- [x] **Clients, products and orders** (gig, lesson pack, design job …) and **tasks** with deadline colours
- [x] **Invoices** as PDF with the **Swiss QR payment part**, recording payments, reminders
- [x] **Year-end report** for the tax return (all cantons, form fields for Lucerne first)
- [ ] Form fields for **more cantons**
- [ ] **VAT** in case you become liable (8.1 %, 2.6 %, 3.8 %, effective or net tax rate method)

## Install

The latest version is under [Releases](https://github.com/rawkhawk0663/conti/releases/latest).

- **Windows 10/11:** download and run `Conti-Setup.exe`. If Windows says "Windows protected your PC": *More info → Run anyway*. Without installing: unzip `Conti-Windows.zip` and run `Conti.exe`.
- **Android:** download `Conti-Android.apk` on your phone and open it. Android asks whether apps from this source may be installed.
- **Android with automatic updates:** in the [Obtainium](https://github.com/ImranR98/Obtainium) app choose “Add app” and enter `https://github.com/rawkhawk0663/conti`. Obtainium notifies you about and installs every new version.

## Your data

Conti has no account and no server. Everything stays on your devices (on Windows in `%APPDATA%\Conti\Conti\Daten`) and, if you connect it, in your own Dropbox. Deleted items are kept as a marker and can be restored, because bookkeeping records must be kept for 10 years in Switzerland.

## Licence

Conti is free software under the [GNU General Public License v3.0](LICENSE). You may use, change and share Conti. Changed versions must stay open under the GPL-3.0 as well.

Fonts: [Sora](https://fonts.google.com/specimen/Sora), [IBM Plex Sans](https://fonts.google.com/specimen/IBM+Plex+Sans) and [Arimo](https://fonts.google.com/specimen/Arimo) (SIL Open Font License), [Roboto Slab](https://fonts.google.com/specimen/Roboto+Slab) (Apache License 2.0).
