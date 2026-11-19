import '../model/account.dart';
import '../model/category.dart';
import '../model/closing.dart';
import '../model/crm.dart';
import '../model/entry.dart';
import 'depreciation.dart';

/// Eine Zeile der Erfolgsrechnung: eine Kategorie mit ihrem Jahrestotal.
class ReportLine {
  ReportLine({required this.categoryId, required this.label, required this.group, required this.amount, this.depth = 0});

  final String categoryId;
  final String label;
  final ClosingGroup group;
  int amount;

  /// 0 = Oberkategorie, 1 = Unterkategorie.
  final int depth;
}

/// Kontostand am Anfang und am Ende des Jahres.
class AccountLine {
  AccountLine(this.account, this.start, this.end, {this.openedDuringYear = 0});

  final Account account;
  final int start;
  final int end;

  /// Anfangsbestand eines Kontos, das erst in diesem Jahr dazugekommen ist
  /// (zählt als Privateinlage).
  final int openedDuringYear;
}

/// Eine Anlage mit ihren Werten im Jahr.
class AssetLine {
  AssetLine(this.asset, this.values, {required this.bought});

  final FixedAsset asset;
  final DepYear values;

  /// In diesem Jahr gekauft (am 1. Januar noch nicht da).
  final bool bought;

  int get startOfYear => bought ? 0 : values.start;
}

/// Eine offene Kundenrechnung an einem Stichtag.
class DebtorLine {
  DebtorLine(this.order, this.clientName, this.amount);

  final Order order;
  final String clientName;
  final int amount;
}

/// Ein Betrag mit Beschriftung (Privatanteile, nicht gebuchte Posten).
class LabeledAmount {
  LabeledAmount(this.label, this.amount, {this.group});

  final String label;
  final int amount;
  final ClosingGroup? group;
}

/// Der Abschluss eines Jahres, aus den Buchungen berechnet. Aufbau wie die
/// Aufstellung, die alle Kantone von Selbständigen ohne kaufmännische
/// Buchhaltung verlangen: Einnahmen und Ausgaben, Vermögen am Anfang und
/// Ende des Jahres, Privatbezüge und Privateinlagen.
///
/// Alles in Rappen. Einnahmen und Ausgaben zählen am Tag der Zahlung; die
/// offenen Rechnungen am Jahresende (Kundschaft und Lieferanten) werden
/// danach als Abgrenzung dazugerechnet.
class YearReport {
  YearReport._(this.year);

  final int year;

  final List<ReportLine> income = [];
  final List<ReportLine> expenses = [];
  final List<AssetLine> assets = [];
  final List<LabeledAmount> vehicleShares = [];
  final List<LabeledAmount> privateShares = [];
  final List<LabeledAmount> unbookedExpenses = [];
  final List<LabeledAmount> unbookedIncome = [];
  final List<DebtorLine> debtorsStart = [];
  final List<DebtorLine> debtorsEnd = [];
  final List<Creditor> creditorsStart = [];
  final List<Creditor> creditorsEnd = [];
  final List<AccountLine> accounts = [];

  /// Geld vom Geschäft zu privat (Kategorie „Privatbezug“ und Buchungen,
  /// die nicht in Auswertungen zählen).
  int cashWithdrawals = 0;

  /// Geld von privat ins Geschäft.
  int cashDeposits = 0;

  /// Buchungen, die keinem bestehenden Konto gehören (oder vor dessen
  /// Anfangsdatum liegen). Sie erklären eine Differenz in der Kontrolle.
  int entriesWithoutAccount = 0;

  int _sum(Iterable<int> xs) => xs.fold(0, (a, b) => a + b);

  int get incomeTotal => _sum(income.map((l) => l.amount));
  int get expenseTotal => _sum(expenses.map((l) => l.amount));
  int get depreciationTotal => _sum(assets.map((a) => a.values.depreciation));
  int get vehicleShareTotal => _sum(vehicleShares.map((x) => x.amount));
  int get privateShareTotal => _sum(privateShares.map((x) => x.amount));
  int get unbookedExpenseTotal => _sum(unbookedExpenses.map((x) => x.amount));
  int get unbookedIncomeTotal => _sum(unbookedIncome.map((x) => x.amount));

  /// Alle Privatanteile zusammen (Fahrzeug und andere).
  int get allPrivateShares => vehicleShareTotal + privateShareTotal;

  /// Ergebnis nach Zahlungen: Einnahmen − Ausgaben − Abschreibungen + Privatanteile.
  int get cashProfit =>
      incomeTotal + unbookedIncomeTotal - expenseTotal - unbookedExpenseTotal - depreciationTotal + allPrivateShares;

  int get debtorsStartTotal => _sum(debtorsStart.map((d) => d.amount));
  int get debtorsEndTotal => _sum(debtorsEnd.map((d) => d.amount));
  int get creditorsStartTotal => _sum(creditorsStart.map((c) => c.amount));
  int get creditorsEndTotal => _sum(creditorsEnd.map((c) => c.amount));

  /// Einkommen aus selbständiger Erwerbstätigkeit (für die Steuererklärung).
  int get businessIncome =>
      cashProfit + debtorsEndTotal - debtorsStartTotal - creditorsEndTotal + creditorsStartTotal;

  int get accountsStart => _sum(accounts.map((a) => a.start));
  int get accountsEnd => _sum(accounts.map((a) => a.end));
  int get assetsStart => _sum(assets.map((a) => a.startOfYear));
  int get assetsEnd => _sum(assets.map((a) => a.values.end));
  int get boughtThisYear => _sum(assets.where((a) => a.bought).map((a) => a.values.start));

  /// Geschäftsvermögen: Konten + offene Kundenrechnungen + Anlagen − offene Lieferantenrechnungen.
  int get netAssetsStart => accountsStart + debtorsStartTotal + assetsStart - creditorsStartTotal;
  int get netAssetsEnd => accountsEnd + debtorsEndTotal + assetsEnd - creditorsEndTotal;

  int get newAccountDeposits => _sum(accounts.map((a) => a.openedDuringYear));

  /// Privatbezüge insgesamt: Geld, Privatanteile, nicht gebuchte Einnahmen.
  int get withdrawalsTotal => cashWithdrawals + allPrivateShares + unbookedIncomeTotal;

  /// Privateinlagen insgesamt: Geld, privat bezahlte Geschäftskosten, neue Konten.
  int get depositsTotal => cashDeposits + unbookedExpenseTotal + newAccountDeposits;

  /// Kontrolle: Vermögen Ende − (Anfang + Einkommen − Bezüge + Einlagen).
  /// Sollte 0 sein.
  int get difference => netAssetsEnd - (netAssetsStart + businessIncome - withdrawalsTotal + depositsTotal);

  /// Summen der Erfolgsrechnung pro Gruppe (für die Formulare der Kantone).
  int groupTotal(ClosingGroup g) {
    var sum = 0;
    for (final l in [...income, ...expenses]) {
      if (l.group == g) sum += l.amount;
    }
    for (final x in unbookedExpenses) {
      if (x.group == g) sum += x.amount;
    }
    for (final x in unbookedIncome) {
      if (x.group == g) sum += x.amount;
    }
    return sum;
  }

  /// Privatanteile auf Kategorien einer Gruppe (z. B. Handy unter „andere Kosten“).
  int privateSharesOf(ClosingGroup g) => _sum(privateShares.where((x) => x.group == g).map((x) => x.amount));

  static DateTime endOf(int year) => DateTime(year, 12, 31);

  /// Rechnet den Abschluss. Gelöschtes muss schon herausgefiltert sein.
  static YearReport compute({
    required int year,
    required List<Entry> entries,
    required List<Account> accounts,
    required List<Category> categories,
    required List<Order> orders,
    required List<Client> clients,
    required List<Asset> assets,
    YearClosing? closing,
    YearClosing? previous,
    Map<String, int> disposals = const {},
  }) {
    final r = YearReport._(year);
    final cats = {for (final c in categories) c.id: c};

    ClosingGroup groupOf(String? id, bool income) => ClosingGroups.resolve(cats, id, income: income);

    // ---- Erfolgsrechnung ----
    final byCat = <String, int>{};
    final catIncome = <String, bool>{};
    final accountIds = {for (final a in accounts) a.id: a};
    for (final e in entries) {
      if (e.year != year || e.kind == EntryKind.transfer) continue;
      final income = e.kind == EntryKind.income;
      final a = accountIds[e.accountId];
      if (a == null || e.date.isBefore(a.openingDate)) r.entriesWithoutAccount++;
      if (e.excludeFromReports) {
        if (income) {
          r.cashDeposits += e.amount;
        } else {
          r.cashWithdrawals += e.amount;
        }
        continue;
      }
      // Anschaffungen zählen nicht als Ausgabe, sondern über die Abschreibungen.
      if (!income && AssetInfo.fromJson(e.asset) != null) continue;
      e.amountsByCategory.forEach((catId, amount) {
        final g = groupOf(catId, income);
        if (g.isPrivate) {
          if (income) {
            r.cashDeposits += amount;
          } else {
            r.cashWithdrawals += amount;
          }
          return;
        }
        byCat[catId] = (byCat[catId] ?? 0) + amount;
        catIncome[catId] = income;
      });
    }

    // In Baum-Reihenfolge: Oberkategorien, darunter ihre Unterkategorien.
    final tops = categories.where((c) => c.parentId == null || cats[c.parentId] == null).toList()
      ..sort((a, b) => a.order != b.order ? a.order.compareTo(b.order) : a.name.compareTo(b.name));
    final placed = <String>{};
    void place(Category c, int depth, String label) {
      final amount = byCat[c.id];
      if (amount != null && amount != 0) {
        final income = catIncome[c.id]!;
        (income ? r.income : r.expenses).add(
          ReportLine(categoryId: c.id, label: label, group: groupOf(c.id, income), amount: amount, depth: depth),
        );
      }
      placed.add(c.id);
    }

    for (final t in tops) {
      place(t, 0, t.name);
      final subs = categories.where((c) => c.parentId == t.id).toList()
        ..sort((a, b) => a.order != b.order ? a.order.compareTo(b.order) : a.name.compareTo(b.name));
      for (final s in subs) {
        place(s, 1, '${t.name} › ${s.name}');
      }
    }
    // Buchungen ohne (bekannte) Kategorie.
    for (final id in byCat.keys.where((k) => !placed.contains(k))) {
      final income = catIncome[id]!;
      (income ? r.income : r.expenses).add(
        ReportLine(
          categoryId: id,
          label: income ? 'Ohne Kategorie (Einnahmen)' : 'Ohne Kategorie (Ausgaben)',
          group: income ? ClosingGroup.revenue : ClosingGroup.other,
          amount: byCat[id]!,
        ),
      );
    }

    // ---- Abschreibungen ----
    final fixed = <FixedAsset>[
      for (final e in entries)
        if (e.kind == EntryKind.expense && !e.excludeFromReports)
          if (AssetInfo.fromJson(e.asset) case final info?) FixedAsset.fromEntry(e, info),
      for (final a in assets) FixedAsset.fromAsset(a),
    ];
    for (final f in fixed) {
      if (disposals[f.id] case final sold?) f.info.soldYear = sold;
      final v = f.yearOf(year);
      if (v.start == 0 && v.end == 0 && v.depreciation == 0) continue;
      r.assets.add(AssetLine(f, v, bought: f.boughtIn(year)));
    }
    r.assets.sort((a, b) => a.asset.acquired.compareTo(b.asset.acquired));

    // ---- Privatanteile und nicht gebuchte Posten ----
    if (closing != null) {
      for (final v in closing.vehicles) {
        r.vehicleShares.add(LabeledAmount(v.name.isEmpty ? 'Fahrzeug' : v.name, v.privateShare, group: ClosingGroup.vehicle));
      }
      for (final a in closing.adjustments) {
        switch (a.kind) {
          case AdjustmentKind.privateShare:
            var base = 0;
            if (a.categoryId != null) {
              for (final l in r.expenses) {
                final c = cats[l.categoryId];
                if (l.categoryId == a.categoryId || c?.parentId == a.categoryId) base += l.amount;
              }
            }
            final amount = a.percent != null ? (base * a.percent! / 100).round() : a.amount;
            final g = a.categoryId != null ? groupOf(a.categoryId, false) : ClosingGroup.other;
            r.privateShares.add(LabeledAmount(a.label, amount, group: g));
          case AdjustmentKind.unbookedExpense:
            r.unbookedExpenses.add(LabeledAmount(a.label, a.amount, group: a.group.income ? ClosingGroup.other : a.group));
          case AdjustmentKind.unbookedIncome:
            r.unbookedIncome.add(LabeledAmount(a.label, a.amount, group: a.group.income ? a.group : ClosingGroup.otherIncome));
        }
      }
      r.creditorsEnd.addAll(closing.creditors);
    }
    if (previous != null) r.creditorsStart.addAll(previous.creditors);

    // ---- Offene Kundenrechnungen ----
    final names = {for (final c in clients) c.id: c.displayName};
    List<DebtorLine> openAt(DateTime day) => [
      for (final o in orders)
        if (o.status != OrderStatus.cancelled &&
            o.invoicedAt != null &&
            !o.invoicedAt!.isAfter(day) &&
            (o.paidAt == null ? o.status != OrderStatus.paid : o.paidAt!.isAfter(day)) &&
            o.total > 0)
          DebtorLine(o, names[o.clientId] ?? '–', o.total),
    ]..sort((a, b) => a.order.invoicedAt!.compareTo(b.order.invoicedAt!));
    r.debtorsStart.addAll(openAt(endOf(year - 1)));
    r.debtorsEnd.addAll(openAt(endOf(year)));

    // ---- Konten ----
    for (final a in accounts) {
      int balanceUntil(DateTime day) {
        if (a.openingDate.isAfter(day)) return 0;
        var sum = a.opening;
        for (final e in entries) {
          if (e.date.isBefore(a.openingDate) || e.date.isAfter(day)) continue;
          if (e.accountId == a.id) {
            sum += e.kind == EntryKind.income ? e.amount : -e.amount;
          }
          if (e.kind == EntryKind.transfer && e.toAccountId == a.id) sum += e.amount;
        }
        return sum;
      }

      final yearStart = DateTime(year, 1, 1);
      final start = a.openingDate.isAfter(yearStart)
          ? 0
          : a.openingDate.isAfter(endOf(year - 1))
          ? a.opening
          : balanceUntil(endOf(year - 1));
      final opened = !a.openingDate.isAfter(yearStart) || a.openingDate.isAfter(endOf(year)) ? 0 : a.opening;
      final end = balanceUntil(endOf(year));
      // Ein Konto, das es in diesem Jahr nicht gab und das nichts enthält, weglassen.
      if (start == 0 && end == 0 && opened == 0 && a.archived) continue;
      if (a.openingDate.isAfter(endOf(year))) continue;
      r.accounts.add(AccountLine(a, start, end, openedDuringYear: opened));
    }
    return r;
  }
}
