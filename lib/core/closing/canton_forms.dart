import '../../app/l10n.dart';
import '../model/account.dart';
import '../model/closing.dart';
import 'year_report.dart';

/// Ein Feld in einem Steuerformular mit dem Betrag aus dem Abschluss.
class TaxField {
  TaxField(this.code, this.label, this.amount, {this.note = '', this.total = false});

  /// Feldnummer im Formular (z. B. „S200“), leer wenn es keine eigene gibt.
  final String code;
  final String label;
  final int amount;
  final String note;

  /// Summen- oder Übertragszeile.
  final bool total;
}

class TaxSection {
  TaxSection(this.title, this.fields, {this.note = ''});

  final String title;
  final List<TaxField> fields;
  final String note;
}

/// Zuordnung der Beträge zu den Feldern der kantonalen Formulare. Bisher für
/// Luzern; andere Kantone bekommen die allgemeine Aufstellung im PDF.
class CantonForms {
  CantonForms._();

  static const supported = {'LU'};

  static bool has(String canton) => supported.contains(canton.toUpperCase());

  static List<TaxSection> of(String canton, YearReport r, {required bool mainOccupation}) => switch (canton.toUpperCase()) {
    'LU' => luzern(r, mainOccupation: mainOccupation),
    _ => const [],
  };

  /// Luzern: Formulare S2 (Geschäftseinkommen ohne kaufmännische
  /// Buchhaltung) und S3 (Betriebsvermögen, Privatentnahmen und -einlagen),
  /// Feldnummern nach der Wegleitung 2026.
  static List<TaxSection> luzern(YearReport r, {required bool mainOccupation}) {
    final goodsCredEnd = r.creditorsEnd.where((c) => c.goods).fold(0, (s, c) => s + c.amount);
    final goodsCredStart = r.creditorsStart.where((c) => c.goods).fold(0, (s, c) => s + c.amount);
    final otherCredDelta =
        (r.creditorsEndTotal - goodsCredEnd) - (r.creditorsStartTotal - goodsCredStart);

    final revenue = r.groupTotal(ClosingGroup.revenue);
    final other = r.groupTotal(ClosingGroup.otherIncome);
    final turnover = revenue + other + r.debtorsEndTotal - r.debtorsStartTotal;
    final goods = r.groupTotal(ClosingGroup.goods);
    final goodsCost = goods + goodsCredEnd - goodsCredStart;
    final gross = turnover - goodsCost;
    final personnel = r.groupTotal(ClosingGroup.personnel);
    final rent = r.groupTotal(ClosingGroup.rent);
    final vehicle = r.groupTotal(ClosingGroup.vehicle);
    final otherCosts = r.groupTotal(ClosingGroup.other) + otherCredDelta;

    final cash = r.accounts.where((a) => a.account.type == AccountType.cash).fold(0, (s, a) => s + a.end);
    int assetsOf(Set<AssetType> types) =>
        r.assets.where((a) => types.contains(a.asset.info.type)).fold(0, (s, a) => s + a.values.end);
    final furniture = assetsOf({AssetType.furniture});
    final vehicles = assetsOf({AssetType.vehicle});
    final machines = assetsOf({AssetType.machine, AssetType.it, AssetType.tools, AssetType.other});
    final movable = furniture + vehicles + machines + r.debtorsEndTotal + cash;

    final s2 = TaxSection(
      tr('Formular S2: Geschäftseinkommen ohne kaufmännische Buchhaltung', 'Form S2: business income without bookkeeping'),
      [
        TaxField('S200', tr('Einnahmen aus Arbeit/Warenverkauf', 'Income from work/sales'), revenue),
        if (other != 0) TaxField('S204', tr('Andere Geschäftserträge', 'Other business income'), other),
        if (r.debtorsEndTotal != 0) TaxField('S206', tr('Debitoren am Ende des Jahres', 'Receivables at year end'), r.debtorsEndTotal),
        if (r.debtorsStartTotal != 0) TaxField('S208', tr('Debitoren am Anfang des Jahres', 'Receivables at start of year'), -r.debtorsStartTotal),
        TaxField('S211', tr('Umsatz (Erlös)', 'Turnover'), turnover, total: true),
        if (goods != 0) TaxField('S212', tr('Zahlungen für Waren und Hilfsmaterial', 'Payments for goods and materials'), goods),
        if (goodsCredEnd != 0) TaxField('S213', tr('Warenschulden am Ende des Jahres', 'Unpaid goods at year end'), goodsCredEnd),
        if (goodsCredStart != 0) TaxField('S214', tr('Warenschulden am Anfang des Jahres', 'Unpaid goods at start of year'), -goodsCredStart),
        TaxField('S219', tr('Waren- und Materialaufwand', 'Cost of goods and materials'), goodsCost),
        TaxField('S220', tr('Bruttogewinn (Übertrag auf S221)', 'Gross profit (carried to S221)'), gross, total: true),
        if (personnel != 0) TaxField('S222', tr('Löhne', 'Wages'), personnel),
        if (rent != 0)
          TaxField('S230', tr('Miete bzw. Mietwert Geschäftsräume', 'Rent or rental value of business premises'), rent),
        if (vehicle != 0 || r.vehicleShareTotal != 0) ...[
          TaxField('S236–S238', tr('Fahrzeugkosten', 'Vehicle costs'), vehicle),
          TaxField('S236–S238', tr('Privatanteil Fahrzeugkosten', 'Private share of vehicle costs'), -r.vehicleShareTotal,
              note: tr('0,9 % des Kaufpreises pro Monat, mindestens CHF 1\'800 im Jahr', '0.9% of the purchase price per month, at least CHF 1,800 a year')),
        ],
        TaxField('S239', tr('Andere Geschäftsunkosten (Aufstellung beilegen)', 'Other business costs (attach list)'), otherCosts),
        if (r.privateShareTotal != 0)
          TaxField('S240', tr('Privatanteil an den anderen Unkosten', 'Private share of other costs'), -r.privateShareTotal),
        if (r.depreciationTotal != 0)
          TaxField('', tr('Abschreibungen (laut Abschreibungstabelle, Formular S3)', 'Depreciation (as per schedule, form S3)'), -r.depreciationTotal),
        TaxField(
          mainOccupation ? 'Ziffer 110' : 'Ziffer 114',
          mainOccupation
              ? tr('Einkommen aus selbständiger Erwerbstätigkeit, Haupterwerb', 'Self-employed income, main occupation')
              : tr('Einkommen aus selbständiger Erwerbstätigkeit, Nebenerwerb', 'Self-employed income, side occupation'),
          r.businessIncome,
          total: true,
          note: tr('Übertrag in die Steuererklärung, Seite 2', 'Carry to the tax return, page 2'),
        ),
      ],
      note: tr(
        'Die Feldnummern der Kosten auf der Rückseite von S2 bitte beim Übertragen im Formular prüfen.',
        'Please check the field numbers of the costs on the back of S2 when copying.',
      ),
    );

    final s3 = TaxSection(
      tr('Formular S3: Betriebsvermögen am 31. Dezember', 'Form S3: business assets on 31 December'),
      [
        if (furniture != 0) TaxField('S300', tr('Betriebseinrichtungen', 'Business fittings'), furniture),
        if (vehicles != 0) TaxField('S301', tr('Fahrzeuge', 'Vehicles'), vehicles),
        if (machines != 0) TaxField('S302', tr('Maschinen / übriges bewegliches Vermögen', 'Machines / other movable assets'), machines),
        if (r.debtorsEndTotal != 0) TaxField('S308', tr('Debitoren (Forderungen gegenüber Kundschaft)', 'Receivables from customers'), r.debtorsEndTotal),
        if (cash != 0) TaxField('S309', tr('Kasse', 'Cash'), cash),
        TaxField('S312', tr('Total bewegliches Betriebsvermögen (Ziffer 430)', 'Total movable business assets (item 430)'), movable, total: true),
        if (r.boughtThisYear != 0)
          TaxField('S341', tr('Anschaffungen im Laufe des Jahres (Abschreibungstabelle)', 'Acquisitions during the year (depreciation schedule)'), r.boughtThisYear),
        for (final a in r.accounts.where((a) => a.account.type != AccountType.cash))
          TaxField('G1', '${a.account.name}: ${tr('ins Wertschriften- und Guthabenverzeichnis', 'into the securities and assets list')}', a.end),
        if (r.creditorsEndTotal != 0)
          TaxField('', tr('Offene Lieferantenrechnungen (Geschäftsschulden)', 'Unpaid supplier invoices (business debts)'), r.creditorsEndTotal),
      ],
      note: tr(
        'Bank- und Postkonten des Geschäfts gehören ins Wertschriften- und Guthabenverzeichnis, bezeichnet mit «G1».',
        'Business bank and postal accounts belong in the securities and assets list, marked “G1”.',
      ),
    );

    final private = TaxSection(tr('Formular S3: Privatentnahmen und Privateinlagen', 'Form S3: private withdrawals and deposits'), [
      TaxField('S320', tr('Bar- und Privatbezüge', 'Cash and private withdrawals'), r.cashWithdrawals),
      if (r.vehicleShareTotal != 0) TaxField('S322', tr('Privatanteil an den Fahrzeugkosten', 'Private share of vehicle costs'), r.vehicleShareTotal),
      if (r.privateShareTotal != 0) TaxField('S323', tr('Privatanteil an den übrigen Unkosten', 'Private share of other costs'), r.privateShareTotal),
      if (r.unbookedIncomeTotal != 0) TaxField('S328', tr('Sonstige Entnahmen', 'Other withdrawals'), r.unbookedIncomeTotal),
      TaxField('S330', tr('Privateinlagen', 'Private deposits'), r.cashDeposits + r.newAccountDeposits),
      if (r.unbookedExpenseTotal != 0)
        TaxField('S331', tr('Sonstige Gutschriften (privat bezahlte Geschäftskosten)', 'Other credits (business costs paid privately)'), r.unbookedExpenseTotal),
    ]);
    return [s2, s3, private];
  }
}
