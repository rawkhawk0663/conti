import 'package:flutter/material.dart';

import '../../app/files.dart';
import '../../app/l10n.dart';
import '../../app/theme.dart';
import '../../core/closing/canton_forms.dart';
import '../../core/closing/year_report.dart';
import '../../core/conti_state.dart';
import '../../core/dates.dart';
import '../../core/model/closing.dart';
import '../../core/model/synced.dart';
import '../../core/money.dart';
import '../../core/swiss.dart';
import '../../widgets/visuals.dart';
import '../entries/entry_editor.dart';
import '../settings/business_page.dart';
import '../settings/categories_page.dart';
import 'closing_actions.dart';

/// Welches Jahr zuerst zeigen: in der ersten Jahreshälfte das Vorjahr,
/// solange es noch nicht abgeschlossen ist.
int defaultClosingYear(ContiState s) {
  final today = Day.today();
  final prev = today.year - 1;
  if (today.month <= 6 && s.years.contains(prev) && !s.isYearClosed(prev)) return prev;
  return today.year;
}

void openClosingScreen(BuildContext context, {int? year}) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ClosingScreen(year: year)));
}

/// Jahresabschluss: Zahlen des Jahres, was noch zu tun ist, PDF und Tabelle,
/// Jahr abschliessen.
class ClosingScreen extends StatefulWidget {
  const ClosingScreen({super.key, this.year});
  final int? year;

  @override
  State<ClosingScreen> createState() => _ClosingScreenState();
}

class _ClosingScreenState extends State<ClosingScreen> {
  int? _year;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final s = ContiScope.of(context);
    final years = {...s.years, Day.today().year}.toList()..sort((a, b) => b.compareTo(a));
    final year = _year ?? widget.year ?? defaultClosingYear(s);
    final r = s.reportOf(year);
    final closing = s.closingOf(year);
    final locked = closing.closed;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Jahresabschluss', 'Annual accounts')),
        actions: [
          DropdownButton<int>(
            value: year,
            underline: const SizedBox.shrink(),
            borderRadius: BorderRadius.circular(14),
            items: [for (final y in years) DropdownMenuItem(value: y, child: Text('$y'))],
            onChanged: (y) => setState(() => _year = y),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 48),
            children: [
              _summary(context, s, r, closing),
              const SizedBox(height: 14),
              if (!locked) ...[_prepare(context, s, r, closing), const SizedBox(height: 14)],
              _assetsCard(context, s, r, closing),
              const SizedBox(height: 14),
              _privateCard(context, s, r, closing),
              const SizedBox(height: 14),
              _openInvoicesCard(context, s, r, closing),
              const SizedBox(height: 14),
              _checkCard(context, r),
              const SizedBox(height: 14),
              _cantonCard(context, s, r),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- Zusammenfassung und Knöpfe ----------

  Widget _summary(BuildContext context, ContiState s, YearReport r, YearClosing closing) {
    final c = context.conti;
    Widget row(String label, int amount, {bool strong = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: strong ? const TextStyle(fontWeight: FontWeight.w600) : null)),
          AmountText(amount, colored: false, sign: false, style: strong ? const TextStyle(fontWeight: FontWeight.w600) : null),
        ],
      ),
    );
    final accrual = r.debtorsEndTotal - r.debtorsStartTotal - r.creditorsEndTotal + r.creditorsStartTotal;
    return SectionCard(
      title: '${tr('Jahr', 'Year')} ${r.year}',
      trailing: _StatusPill(closing: closing),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CapsLabel(tr('Einkommen aus selbständiger Erwerbstätigkeit', 'Income from self-employment')),
          const SizedBox(height: 6),
          BigNumber(Money.format(r.businessIncome), size: 38),
          const SizedBox(height: 8),
          GradientBar(value: 1, colors: r.businessIncome >= 0 ? c.pink : c.sun, height: 4),
          const SizedBox(height: 14),
          row(tr('Einnahmen', 'Income'), r.incomeTotal + r.unbookedIncomeTotal),
          row(tr('Ausgaben', 'Expenses'), -(r.expenseTotal + r.unbookedExpenseTotal)),
          if (r.depreciationTotal != 0) row(tr('Abschreibungen', 'Depreciation'), -r.depreciationTotal),
          if (r.allPrivateShares != 0) row(tr('Privatanteile', 'Private shares'), r.allPrivateShares),
          if (accrual != 0) row(tr('Offene Rechnungen (Abgrenzung)', 'Unpaid invoices (accrual)'), accrual),
          const Divider(height: 20),
          row(tr('Geschäftsvermögen am 31.12.', 'Business assets on 31 Dec'), r.netAssetsEnd, strong: true),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              GradientButton(
                label: tr('PDF erstellen', 'Create PDF'),
                icon: Icons.picture_as_pdf_outlined,
                onPressed: _busy ? null : () => _run(() => createClosingPdf(context, r.year)),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _run(() => exportClosingCsv(context, r.year)),
                icon: const Icon(Icons.table_chart_outlined),
                label: Text(tr('Tabelle (CSV)', 'Table (CSV)')),
              ),
              if (closing.closed)
                TextButton.icon(
                  onPressed: _busy ? null : () => _reopen(context, r.year),
                  icon: const Icon(Icons.lock_open_outlined),
                  label: Text(tr('Abschluss aufheben', 'Reopen year')),
                )
              else
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _close(context, s, r),
                  icon: const Icon(Icons.lock_outline),
                  label: Text(tr('Jahr abschliessen', 'Close year')),
                ),
            ],
          ),
          if (closing.pdfFile.isNotEmpty) ...[
            const SizedBox(height: 10),
            TextButton.icon(
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              onPressed: () => _openLastPdf(context, s, closing),
              icon: const Icon(Icons.description_outlined, size: 18),
              label: Text(tr('Zuletzt erstelltes PDF öffnen', 'Open last PDF')),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _run(Future<void> Function() job) async {
    setState(() => _busy = true);
    try {
      await job();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openLastPdf(BuildContext context, ContiState s, YearClosing c) async {
    final path = s.dataPath(c.pdfFile);
    await openFile(context, path);
  }

  Future<void> _close(BuildContext context, ContiState s, YearReport r) async {
    final closing = s.closingOf(r.year);
    final unchecked = r.accounts.where((a) => !closing.checkedAccounts.contains(a.account.id)).length;
    final warnings = [
      if (r.year >= Day.today().year)
        tr('Das Jahr ist noch nicht vorbei.', 'The year is not over yet.'),
      if (unchecked > 0)
        tr('$unchecked Kontostände sind noch nicht mit dem Auszug verglichen.', '$unchecked balances have not been compared with the statement.'),
      if (r.difference != 0)
        tr('Die Kontrolle geht nicht auf (Differenz ${Money.format(r.difference)}).', 'The check does not balance (difference ${Money.format(r.difference)}).'),
    ];
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Jahr ${r.year} abschliessen?', 'Close the year ${r.year}?')),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(
                  'Danach lassen sich die Buchungen von ${r.year} nicht mehr ändern. Conti erstellt dazu das Abschluss-PDF. Ist später etwas falsch, erfasst du eine Korrektur im laufenden Jahr.',
                  'Afterwards the entries of ${r.year} can no longer be changed. Conti creates the PDF of the accounts. If something turns out wrong later, you record a correction in the current year.',
                ),
              ),
              for (final w in warnings)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 20, color: context.conti.minus),
                      const SizedBox(width: 8),
                      Expanded(child: Text(w)),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Abbrechen', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Abschliessen', 'Close year'))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await _run(() async {
      await s.closeYear(r.year);
      if (context.mounted) await createClosingPdf(context, r.year);
    });
  }

  Future<void> _reopen(BuildContext context, int year) async {
    final s = ContiScope.read(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Abschluss $year aufheben?', 'Reopen $year?')),
        content: Text(
          tr(
            'Dann lassen sich die Buchungen von $year wieder ändern. Mach das nur, wenn die Steuererklärung noch nicht eingereicht ist. Das Aufheben bleibt im Verlauf gespeichert.',
            'The entries of $year can then be changed again. Only do this if the tax return has not been filed yet. Reopening stays recorded in the history.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Abbrechen', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Aufheben', 'Reopen'))),
        ],
      ),
    );
    if (ok == true) await s.reopenYear(year);
  }

  // ---------- Vorbereiten ----------

  Widget _prepare(BuildContext context, ContiState s, YearReport r, YearClosing closing) {
    final c = context.conti;
    final b = s.business;
    final allChecked = r.accounts.every((a) => closing.checkedAccounts.contains(a.account.id));
    return SectionCard(
      title: tr('Vorbereiten', 'Prepare'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Step(
            done: allChecked && r.accounts.isNotEmpty,
            title: tr('Kontostände am 31.12. mit den Auszügen vergleichen', 'Compare balances on 31 Dec with the statements'),
            text: tr(
              'Stimmt der Stand in Conti mit dem Bank- oder Postauszug (bzw. dem Bargeld) überein? Dann abhaken.',
              'Does the balance in Conti match the bank statement (or the cash)? Then tick it.',
            ),
            child: Column(
              children: [
                for (final a in r.accounts)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: closing.checkedAccounts.contains(a.account.id),
                    onChanged: (v) {
                      final x = closing.copy();
                      v == true ? x.checkedAccounts.add(a.account.id) : x.checkedAccounts.remove(a.account.id);
                      s.saveClosing(x);
                    },
                    title: Text(a.account.name),
                    secondary: AmountText(a.end, colored: false, sign: false),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
              ],
            ),
          ),
          _Step(
            done: false,
            neutral: true,
            title: tr('Kategorien zuordnen', 'Assign categories'),
            text: tr(
              'Jede Kategorie gehört zu einer Zeile im Abschluss (z. B. „Waren und Material“). Conti schlägt etwas vor, du kannst es ändern.',
              'Each category belongs to a line of the accounts (e.g. “Goods and materials”). Conti suggests one; you can change it.',
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const CategoriesPage())),
                icon: const Icon(Icons.category_outlined),
                label: Text(tr('Kategorien öffnen', 'Open categories')),
              ),
            ),
          ),
          _Step(
            done: b.canton.isNotEmpty,
            title: b.canton.isEmpty
                ? tr('Kanton wählen', 'Choose your canton')
                : '${tr('Kanton', 'Canton')}: ${cantons.where((x) => x.$1 == b.canton).map((x) => x.$2).firstOrNull ?? b.canton}',
            text: CantonForms.has(b.canton)
                ? tr('Conti ordnet die Beträge den Feldern der Formulare zu (unten).', 'Conti assigns the amounts to the fields of the forms (below).')
                : tr(
                    'Für diesen Kanton gibt es noch keine Feld-Zuordnung. Das PDF enthält die Aufstellung, die alle Kantone verlangen.',
                    'There is no field mapping for this canton yet. The PDF contains the statement all cantons require.',
                  ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (b.canton.isEmpty)
                  TextButton.icon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const BusinessPage())),
                    icon: const Icon(Icons.storefront_outlined),
                    label: Text(tr('Mein Geschäft öffnen', 'Open my business')),
                  ),
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(value: true, label: Text(tr('Haupterwerb', 'Main occupation'))),
                    ButtonSegment(value: false, label: Text(tr('Nebenerwerb', 'Side occupation'))),
                  ],
                  selected: {b.mainOccupation},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) => s.saveBusiness(s.business.copy()..mainOccupation = v.first),
                ),
              ],
            ),
          ),
          Text(
            tr(
              'Danach: Anschaffungen, Privatanteile und offene Rechnungen unten prüfen.',
              'Then check acquisitions, private shares and unpaid invoices below.',
            ),
            style: TextStyle(color: c.muted),
          ),
        ],
      ),
    );
  }

  // ---------- Anschaffungen ----------

  Widget _assetsCard(BuildContext context, ContiState s, YearReport r, YearClosing closing) {
    final c = context.conti;
    final locked = closing.closed;
    return SectionCard(
      title: tr('Anschaffungen und Abschreibungen', 'Acquisitions and depreciation'),
      trailing: locked
          ? null
          : TextButton.icon(
              onPressed: () => _editAsset(context, s, null, r.year),
              icon: const Icon(Icons.add),
              label: Text(tr('Ohne Buchung', 'Without entry')),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (r.assets.isEmpty)
            Text(
              tr(
                'Keine Anschaffungen. Eine neue Anschaffung markierst du direkt in der Buchung mit dem Schalter „Anschaffung“. Was du vor Conti gekauft hast, trägst du mit „Ohne Buchung“ ein.',
                'No acquisitions. Mark a new acquisition directly in the entry with the “Acquisition” switch. Add what you bought before Conti with “Without entry”.',
              ),
              style: TextStyle(color: c.muted),
            ),
          for (final a in r.assets)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(a.asset.info.soldYear == r.year ? Icons.sell_outlined : Icons.inventory_2_outlined, color: c.muted),
              title: Text(a.asset.name.isEmpty ? a.asset.info.type.label : a.asset.name),
              subtitle: Text(
                [
                  '${tr('gekauft', 'bought')} ${Day.short(a.asset.acquired)}',
                  '${Money.format(a.values.start)} − ${Money.format(a.values.depreciation)} = ${Money.format(a.values.end)}',
                  if (a.asset.info.soldYear == r.year) tr('verkauft/ausgeschieden', 'sold/disposed'),
                ].join(' · '),
              ),
              trailing: AmountText(-a.values.depreciation, colored: false, sign: false),
              onTap: () => _assetMenu(context, s, a, r.year, locked),
            ),
          if (r.assets.isNotEmpty) ...[
            const Divider(),
            Row(
              children: [
                Expanded(child: Text(tr('Abschreibungen ${r.year}', 'Depreciation ${r.year}'), style: const TextStyle(fontWeight: FontWeight.w600))),
                AmountText(-r.depreciationTotal, colored: false, sign: false, style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _assetMenu(BuildContext context, ContiState s, AssetLine a, int year, bool locked) async {
    final closing = s.closingOf(year);
    final disposed = closing.disposed.contains(a.asset.id);
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (a.asset.entryId != null)
              ListTile(leading: const Icon(Icons.receipt_long_outlined), title: Text(tr('Buchung öffnen', 'Open entry')), onTap: () => Navigator.pop(context, 'entry')),
            if (a.asset.assetId != null && !locked)
              ListTile(leading: const Icon(Icons.edit_outlined), title: Text(tr('Bearbeiten', 'Edit')), onTap: () => Navigator.pop(context, 'edit')),
            if (!locked)
              ListTile(
                leading: Icon(disposed ? Icons.undo : Icons.sell_outlined),
                title: Text(disposed ? tr('Doch nicht verkauft', 'Not sold after all') : tr('In $year verkauft oder ausgeschieden', 'Sold or disposed of in $year')),
                subtitle: disposed
                    ? null
                    : Text(tr('Der Restwert wird $year ganz abgeschrieben. Einen Verkaufserlös buchst du als Einnahme.', 'The remaining value is written off in $year. Book any sale proceeds as income.')),
                onTap: () => Navigator.pop(context, 'dispose'),
              ),
            if (a.asset.assetId != null && !locked)
              ListTile(leading: const Icon(Icons.delete_outline), title: Text(tr('Löschen', 'Delete')), onTap: () => Navigator.pop(context, 'delete')),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    switch (choice) {
      case 'entry':
        final e = s.entry(a.asset.entryId!);
        if (e != null) await openEntryEditor(context, entry: e);
      case 'edit':
        final x = s.assets.where((x) => x.id == a.asset.assetId).firstOrNull;
        if (x != null) await _editAsset(context, s, x, year);
      case 'dispose':
        final c = closing.copy();
        disposed ? c.disposed.remove(a.asset.id) : c.disposed.add(a.asset.id);
        await s.saveClosing(c);
      case 'delete':
        final x = s.assets.where((x) => x.id == a.asset.assetId).firstOrNull;
        if (x != null) await s.deleteAsset(x);
    }
  }

  Future<void> _editAsset(BuildContext context, ContiState s, Asset? existing, int year) async {
    final a = existing?.copy() ??
        Asset(id: newId(), info: AssetInfo(type: AssetType.machine), acquired: DateTime(year - 1, 1, 1), openingYear: year);
    final name = TextEditingController(text: a.info.name);
    final cost = TextEditingController(text: a.cost > 0 ? Money.forInput(a.cost) : '');
    final value = TextEditingController(text: a.openingValue > 0 ? Money.forInput(a.openingValue) : '');
    final rate = TextEditingController(text: '${a.info.rate}');
    String? error;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(tr('Anlage ohne Buchung', 'Asset without entry')),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    tr(
                      'Für Anschaffungen, die vor Conti gekauft wurden und noch abgeschrieben werden.',
                      'For acquisitions bought before Conti that are still being depreciated.',
                    ),
                    style: TextStyle(color: context.conti.muted),
                  ),
                  const SizedBox(height: 12),
                  TextField(controller: name, decoration: InputDecoration(labelText: tr('Name', 'Name'), hintText: tr('z. B. Flügel', 'e.g. Grand piano'))),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<AssetType>(
                    initialValue: a.info.type,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: tr('Art', 'Type')),
                    items: [for (final t in AssetType.values) DropdownMenuItem(value: t, child: Text(t.label))],
                    onChanged: (t) => setState(() {
                      if (t == null) return;
                      a.info.type = t;
                      a.info.rate = a.info.method == DepMethod.linear ? t.rate ~/ 2 : t.rate;
                      rate.text = '${a.info.rate}';
                    }),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () async {
                      final d = await showDatePicker(context: context, initialDate: a.acquired, firstDate: DateTime(1990), lastDate: DateTime(year, 12, 31));
                      if (d != null) setState(() => a.acquired = d);
                    },
                    child: InputDecorator(
                      decoration: InputDecoration(labelText: tr('Gekauft am', 'Bought on'), suffixIcon: const Icon(Icons.event)),
                      child: Text(Day.short(a.acquired)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: cost,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: tr('Kaufpreis CHF', 'Cost CHF')),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: value,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: tr('Restwert am 1.1.$year CHF', 'Book value on 1 Jan $year CHF'),
                      helperText: tr('aus dem Abschluss des Vorjahres', 'from last year’s accounts'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: DropdownButtonFormField<DepMethod>(
                          initialValue: a.info.method == DepMethod.immediate ? DepMethod.degressive : a.info.method,
                          isExpanded: true,
                          decoration: InputDecoration(labelText: tr('Abschreibung', 'Depreciation')),
                          items: [
                            for (final m in [DepMethod.degressive, DepMethod.linear]) DropdownMenuItem(value: m, child: Text(m.label, overflow: TextOverflow.ellipsis)),
                          ],
                          onChanged: (m) => setState(() {
                            if (m == null) return;
                            a.info.method = m;
                            a.info.rate = m == DepMethod.linear ? a.info.type.rate ~/ 2 : a.info.type.rate;
                            rate.text = '${a.info.rate}';
                          }),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: rate,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(labelText: tr('Satz', 'Rate'), suffixText: '%'),
                        ),
                      ),
                    ],
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Abbrechen', 'Cancel'))),
            FilledButton(
              onPressed: () {
                final c = Money.parse(cost.text);
                final v = Money.parse(value.text);
                final rt = int.tryParse(rate.text.trim());
                if (name.text.trim().isEmpty || c == null || c <= 0 || v == null || v < 0 || v > c || rt == null || rt < 1 || rt > 100) {
                  setState(
                    () => error = tr(
                      'Bitte Name, Kaufpreis, Restwert (höchstens der Kaufpreis) und einen Satz von 1 bis 100 % eingeben.',
                      'Please enter a name, the cost, the book value (at most the cost) and a rate from 1 to 100%.',
                    ),
                  );
                  return;
                }
                a
                  ..cost = c
                  ..openingValue = v
                  ..openingYear = year
                  ..info.name = name.text.trim()
                  ..info.rate = rt;
                Navigator.pop(context, true);
              },
              child: Text(tr('Sichern', 'Save')),
            ),
          ],
        ),
      ),
    );
    if (ok == true) await s.saveAsset(a);
  }

  // ---------- Privatanteile und nicht gebuchte Posten ----------

  Widget _privateCard(BuildContext context, ContiState s, YearReport r, YearClosing closing) {
    final c = context.conti;
    final locked = closing.closed;
    final shares = closing.adjustments.where((a) => a.kind == AdjustmentKind.privateShare).toList();
    final unbooked = closing.adjustments.where((a) => a.kind != AdjustmentKind.privateShare).toList();
    return SectionCard(
      title: tr('Privatanteile und private Kosten', 'Private shares and private costs'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr(
              'Brauchst du etwas geschäftlich und privat (Auto, Handy, Internet), zählt nur der geschäftliche Teil. Hast du Geschäftskosten privat bezahlt (z. B. ein Arbeitszimmer zuhause), kannst du sie hier dazunehmen.',
              'If you use something for business and privately (car, phone, internet), only the business part counts. If you paid business costs privately (e.g. a home office), you can add them here.',
            ),
            style: TextStyle(color: c.muted),
          ),
          const SizedBox(height: 8),
          for (final v in closing.vehicles)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.directions_car_outlined, color: c.muted),
              title: Text(v.name.isEmpty ? tr('Fahrzeug', 'Vehicle') : v.name),
              subtitle: Text(tr(
                'Kaufpreis ${Money.format(v.price)} · ${v.months} Monate · Privatanteil 0,9 % pro Monat, mind. CHF 150',
                'Cost ${Money.format(v.price)} · ${v.months} months · private share 0.9% per month, min. CHF 150',
              )),
              trailing: AmountText(v.privateShare, colored: false, sign: false),
              onTap: locked ? null : () => _editVehicle(context, s, r.year, v),
            ),
          for (final a in shares)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.pie_chart_outline, color: c.muted),
              title: Text(a.label),
              subtitle: Text(
                a.percent != null
                    ? tr('${_pct(a.percent!)} % von ${s.categoryLabel(a.categoryId)}', '${_pct(a.percent!)}% of ${s.categoryLabel(a.categoryId)}')
                    : tr('fester Betrag', 'fixed amount'),
              ),
              trailing: AmountText(r.privateShares.where((x) => x.label == a.label).fold(0, (s, x) => s + x.amount), colored: false, sign: false),
              onTap: locked ? null : () => _editAdjustment(context, s, r.year, a),
            ),
          for (final a in unbooked)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(a.kind == AdjustmentKind.unbookedExpense ? Icons.home_work_outlined : Icons.add_card_outlined, color: c.muted),
              title: Text(a.label),
              subtitle: Text(
                a.kind == AdjustmentKind.unbookedExpense
                    ? '${tr('Privat bezahlt', 'Paid privately')} · ${a.group.label}'
                    : tr('Nicht gebuchte Einnahme', 'Income not booked'),
              ),
              trailing: AmountText(a.kind == AdjustmentKind.unbookedExpense ? -a.amount : a.amount, colored: false, sign: false),
              onTap: locked ? null : () => _editAdjustment(context, s, r.year, a),
            ),
          if (!locked) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(onPressed: () => _editVehicle(context, s, r.year, null), icon: const Icon(Icons.directions_car_outlined), label: Text(tr('Fahrzeug', 'Vehicle'))),
                OutlinedButton.icon(
                  onPressed: () => _editAdjustment(context, s, r.year, Adjustment(id: newId(), kind: AdjustmentKind.privateShare, percent: 20), isNew: true),
                  icon: const Icon(Icons.pie_chart_outline),
                  label: Text(tr('Privatanteil', 'Private share')),
                ),
                OutlinedButton.icon(
                  onPressed: () => _editAdjustment(
                    context,
                    s,
                    r.year,
                    Adjustment(id: newId(), kind: AdjustmentKind.unbookedExpense, label: tr('Arbeitszimmer zuhause', 'Home office'), group: ClosingGroup.rent),
                    isNew: true,
                  ),
                  icon: const Icon(Icons.home_work_outlined),
                  label: Text(tr('Privat bezahlte Kosten', 'Costs paid privately')),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _pct(double p) => p == p.roundToDouble() ? p.toInt().toString() : p.toString();

  Future<void> _editVehicle(BuildContext context, ContiState s, int year, Vehicle? existing) async {
    final v = existing == null ? Vehicle(id: newId()) : Vehicle.fromJson(existing.toJson());
    final name = TextEditingController(text: v.name);
    final price = TextEditingController(text: v.price > 0 ? Money.forInput(v.price) : '');
    var months = v.months;
    String? error;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(tr('Fahrzeug, auch privat gebraucht', 'Vehicle also used privately')),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  tr(
                    'Die Steuerverwaltung rechnet den Privatanteil pauschal: 0,9 % des Kaufpreises (ohne MWST) pro Monat, mindestens CHF 150 pro Monat. Die Fahrzeugkosten buchst du ganz als Ausgabe.',
                    'The tax administration uses a flat private share: 0.9% of the purchase price (excl. VAT) per month, at least CHF 150 per month. Book the vehicle costs in full as expenses.',
                  ),
                  style: TextStyle(color: context.conti.muted),
                ),
                const SizedBox(height: 12),
                TextField(controller: name, decoration: InputDecoration(labelText: tr('Fahrzeug', 'Vehicle'), hintText: tr('z. B. VW Caddy', 'e.g. VW Caddy'))),
                const SizedBox(height: 12),
                TextField(
                  controller: price,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: tr('Kaufpreis ohne MWST, CHF', 'Purchase price excl. VAT, CHF')),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: months,
                  decoration: InputDecoration(labelText: tr('Monate im Geschäft', 'Months in the business')),
                  items: [for (var m = 1; m <= 12; m++) DropdownMenuItem(value: m, child: Text('$m'))],
                  onChanged: (m) => setState(() => months = m ?? 12),
                ),
                if (error != null)
                  Padding(padding: const EdgeInsets.only(top: 10), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
              ],
            ),
          ),
          actions: [
            if (existing != null) TextButton(onPressed: () => Navigator.pop(context, 'delete'), child: Text(tr('Löschen', 'Delete'))),
            TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Abbrechen', 'Cancel'))),
            FilledButton(
              onPressed: () {
                final p = Money.parse(price.text);
                if (p == null || p < 0) {
                  setState(() => error = tr('Bitte den Kaufpreis eingeben.', 'Please enter the purchase price.'));
                  return;
                }
                v
                  ..name = name.text.trim()
                  ..price = p
                  ..months = months;
                Navigator.pop(context, 'save');
              },
              child: Text(tr('Sichern', 'Save')),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    final c = s.closingOf(year).copy();
    c.vehicles.removeWhere((x) => x.id == v.id);
    if (result == 'save') c.vehicles.add(v);
    await s.saveClosing(c);
  }

  Future<void> _editAdjustment(BuildContext context, ContiState s, int year, Adjustment a, {bool isNew = false}) async {
    final x = Adjustment.fromJson(a.toJson());
    final label = TextEditingController(text: x.label);
    final amount = TextEditingController(text: x.amount > 0 ? Money.forInput(x.amount) : '');
    final percent = TextEditingController(text: x.percent == null ? '' : _pct(x.percent!));
    var byPercent = x.kind == AdjustmentKind.privateShare && x.percent != null;
    final expenseCats = s.categoryTree(income: false).where((e) => !s.groupOf(e.$1.id, income: false).isPrivate).toList();
    String? error;
    final title = switch (x.kind) {
      AdjustmentKind.privateShare => tr('Privatanteil', 'Private share'),
      AdjustmentKind.unbookedExpense => tr('Privat bezahlte Geschäftskosten', 'Business costs paid privately'),
      AdjustmentKind.unbookedIncome => tr('Nicht gebuchte Einnahme', 'Income not booked'),
    };
    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (x.kind == AdjustmentKind.unbookedExpense)
                    Text(
                      tr(
                        'Zum Beispiel ein Arbeitszimmer in der eigenen Wohnung: der geschäftliche Anteil der Miete und Nebenkosten. Halte fest, wie du den Betrag berechnet hast.',
                        'For example a home office: the business share of rent and utilities. Keep a note of how you calculated the amount.',
                      ),
                      style: TextStyle(color: context.conti.muted),
                    ),
                  if (x.kind == AdjustmentKind.privateShare)
                    Text(
                      tr(
                        'Zum Beispiel: Handy und Internet zu 30 % privat. Der Anteil wird von der Kategorie abgezogen.',
                        'For example: phone and internet 30% private. The share is deducted from the category.',
                      ),
                      style: TextStyle(color: context.conti.muted),
                    ),
                  const SizedBox(height: 12),
                  TextField(controller: label, decoration: InputDecoration(labelText: tr('Bezeichnung', 'Description'))),
                  const SizedBox(height: 12),
                  if (x.kind == AdjustmentKind.privateShare) ...[
                    DropdownButtonFormField<String>(
                      initialValue: expenseCats.any((e) => e.$1.id == x.categoryId) ? x.categoryId : null,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: tr('Kategorie', 'Category')),
                      items: [
                        for (final (cat, depth) in expenseCats)
                          DropdownMenuItem(
                            value: cat.id,
                            child: Padding(padding: EdgeInsets.only(left: depth * 14.0), child: Text(cat.name, overflow: TextOverflow.ellipsis)),
                          ),
                      ],
                      onChanged: (v) => setState(() {
                        x.categoryId = v;
                        if (label.text.trim().isEmpty && v != null) label.text = s.category(v)?.name ?? '';
                      }),
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<bool>(
                      segments: [
                        ButtonSegment(value: true, label: Text(tr('Prozent', 'Percent'))),
                        ButtonSegment(value: false, label: Text(tr('Betrag', 'Amount'))),
                      ],
                      selected: {byPercent},
                      showSelectedIcon: false,
                      onSelectionChanged: (v) => setState(() => byPercent = v.first),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (x.kind == AdjustmentKind.privateShare && byPercent)
                    TextField(
                      controller: percent,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: tr('Privater Anteil', 'Private share'), suffixText: '%'),
                    )
                  else
                    TextField(
                      controller: amount,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: tr('Betrag im Jahr, CHF', 'Amount for the year, CHF')),
                    ),
                  if (x.kind == AdjustmentKind.unbookedExpense) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<ClosingGroup>(
                      initialValue: x.group.income ? ClosingGroup.other : x.group,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: tr('Im Jahresabschluss', 'In the annual accounts')),
                      items: [
                        for (final g in ClosingGroup.forIncome(false).where((g) => !g.isPrivate))
                          DropdownMenuItem(value: g, child: Text(g.label, overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (g) => setState(() => x.group = g ?? ClosingGroup.other),
                    ),
                  ],
                  if (error != null)
                    Padding(padding: const EdgeInsets.only(top: 10), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
                ],
              ),
            ),
          ),
          actions: [
            if (!isNew) TextButton(onPressed: () => Navigator.pop(context, 'delete'), child: Text(tr('Löschen', 'Delete'))),
            TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Abbrechen', 'Cancel'))),
            FilledButton(
              onPressed: () {
                final pct = double.tryParse(percent.text.trim().replaceAll(',', '.'));
                final amt = Money.parse(amount.text);
                final share = x.kind == AdjustmentKind.privateShare;
                if (label.text.trim().isEmpty) {
                  setState(() => error = tr('Bitte eine Bezeichnung eingeben.', 'Please enter a description.'));
                  return;
                }
                if (share && byPercent && (x.categoryId == null || pct == null || pct <= 0 || pct > 100)) {
                  setState(() => error = tr('Bitte Kategorie und Prozent (1–100) wählen.', 'Please choose a category and a percentage (1–100).'));
                  return;
                }
                if ((!share || !byPercent) && (amt == null || amt <= 0)) {
                  setState(() => error = tr('Bitte einen Betrag eingeben.', 'Please enter an amount.'));
                  return;
                }
                x.label = label.text.trim();
                if (share && byPercent) {
                  x
                    ..percent = pct
                    ..amount = 0;
                } else {
                  x
                    ..percent = null
                    ..amount = amt!;
                }
                Navigator.pop(context, 'save');
              },
              child: Text(tr('Sichern', 'Save')),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    final c = s.closingOf(year).copy();
    c.adjustments.removeWhere((y) => y.id == x.id);
    if (result == 'save') c.adjustments.add(x);
    await s.saveClosing(c);
  }

  // ---------- Offene Rechnungen ----------

  Widget _openInvoicesCard(BuildContext context, ContiState s, YearReport r, YearClosing closing) {
    final c = context.conti;
    final locked = closing.closed;
    return SectionCard(
      title: tr('Offene Rechnungen am 31.12.${r.year}', 'Unpaid invoices on 31 Dec ${r.year}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CapsLabel(tr('Kundschaft schuldet dir', 'Customers owe you')),
          const SizedBox(height: 4),
          if (r.debtorsEnd.isEmpty)
            Text(tr('Keine. Conti nimmt sie aus den gestellten Rechnungen.', 'None. Conti takes them from issued invoices.'), style: TextStyle(color: c.muted)),
          for (final d in r.debtorsEnd)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(d.clientName),
              subtitle: Text('${d.order.invoiceNumber} · ${Day.short(d.order.invoicedAt!)}'),
              trailing: AmountText(d.amount, colored: false, sign: false),
            ),
          const SizedBox(height: 14),
          CapsLabel(tr('Du schuldest Lieferanten', 'You owe suppliers')),
          const SizedBox(height: 4),
          if (closing.creditors.isEmpty)
            Text(
              tr('Rechnungen, die du am 31.12. noch nicht bezahlt hattest. Sonst leer lassen.', 'Invoices you had not yet paid on 31 Dec. Otherwise leave empty.'),
              style: TextStyle(color: c.muted),
            ),
          for (final k in closing.creditors)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(k.name),
              subtitle: k.goods ? Text(tr('Waren und Material', 'Goods and materials')) : null,
              trailing: AmountText(-k.amount, colored: false, sign: false),
              onTap: locked ? null : () => _editCreditor(context, s, r.year, k),
            ),
          if (!locked)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _editCreditor(context, s, r.year, null),
                icon: const Icon(Icons.add),
                label: Text(tr('Lieferantenrechnung', 'Supplier invoice')),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _editCreditor(BuildContext context, ContiState s, int year, Creditor? existing) async {
    final k = existing == null ? Creditor(id: newId()) : Creditor.fromJson(existing.toJson());
    final name = TextEditingController(text: k.name);
    final amount = TextEditingController(text: k.amount > 0 ? Money.forInput(k.amount) : '');
    var goods = k.goods;
    String? error;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(tr('Offene Lieferantenrechnung', 'Unpaid supplier invoice')),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: name, decoration: InputDecoration(labelText: tr('Lieferant', 'Supplier'))),
                const SizedBox(height: 12),
                TextField(
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: tr('Betrag CHF', 'Amount CHF')),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('Für Waren und Material', 'For goods and materials')),
                  value: goods,
                  onChanged: (v) => setState(() => goods = v),
                ),
                if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ),
          ),
          actions: [
            if (existing != null) TextButton(onPressed: () => Navigator.pop(context, 'delete'), child: Text(tr('Löschen', 'Delete'))),
            TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Abbrechen', 'Cancel'))),
            FilledButton(
              onPressed: () {
                final a = Money.parse(amount.text);
                if (name.text.trim().isEmpty || a == null || a <= 0) {
                  setState(() => error = tr('Bitte Lieferant und Betrag eingeben.', 'Please enter supplier and amount.'));
                  return;
                }
                k
                  ..name = name.text.trim()
                  ..amount = a
                  ..goods = goods;
                Navigator.pop(context, 'save');
              },
              child: Text(tr('Sichern', 'Save')),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    final c = s.closingOf(year).copy();
    c.creditors.removeWhere((x) => x.id == k.id);
    if (result == 'save') c.creditors.add(k);
    await s.saveClosing(c);
  }

  // ---------- Kontrolle ----------

  Widget _checkCard(BuildContext context, YearReport r) {
    final c = context.conti;
    final ok = r.difference == 0;
    Widget row(String label, int v, {bool strong = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: strong ? const TextStyle(fontWeight: FontWeight.w600) : null)),
          AmountText(v, colored: false, sign: false, style: strong ? const TextStyle(fontWeight: FontWeight.w600) : null),
        ],
      ),
    );
    return SectionCard(
      title: tr('Kontrolle', 'Check'),
      trailing: Icon(ok ? Icons.check_circle : Icons.error_outline, color: ok ? c.plus : c.minus),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          row(tr('Geschäftsvermögen am 1.1.', 'Business assets on 1 Jan'), r.netAssetsStart),
          row(tr('+ Einkommen', '+ Income'), r.businessIncome),
          row(tr('− Privatbezüge', '− Private withdrawals'), -r.withdrawalsTotal),
          row(tr('+ Privateinlagen', '+ Private deposits'), r.depositsTotal),
          const Divider(height: 16),
          row(tr('= Geschäftsvermögen am 31.12.', '= Business assets on 31 Dec'), r.netAssetsEnd - r.difference, strong: true),
          row(tr('Laut Konten und Aufstellung', 'According to accounts and list'), r.netAssetsEnd),
          const SizedBox(height: 8),
          Text(
            ok
                ? tr('Geht auf. Die Zahlen passen zusammen.', 'Balanced. The figures fit together.')
                : r.entriesWithoutAccount > 0
                ? tr(
                    'Differenz ${Money.format(r.difference)}: ${r.entriesWithoutAccount} Buchungen gehören zu keinem Konto oder liegen vor dem Anfangsdatum ihres Kontos (z. B. importierte Buchungen). Prüfe unter Einstellungen → Konten das Anfangsdatum und den Anfangsbestand.',
                    'Difference ${Money.format(r.difference)}: ${r.entriesWithoutAccount} entries belong to no account or are dated before their account starts (e.g. imported entries). Check the opening date and balance under Settings → Accounts.',
                  )
                : tr(
                    'Differenz ${Money.format(r.difference)}. Prüfe die Anfangsbestände der Konten.',
                    'Difference ${Money.format(r.difference)}. Check the opening balances of the accounts.',
                  ),
            style: TextStyle(color: ok ? c.muted : c.minus),
          ),
        ],
      ),
    );
  }

  // ---------- Formulare des Kantons ----------

  Widget _cantonCard(BuildContext context, ContiState s, YearReport r) {
    final c = context.conti;
    final b = s.business;
    final sections = CantonForms.of(b.canton, r, mainOccupation: b.mainOccupation);
    if (sections.isEmpty) {
      return SectionCard(
        title: tr('Steuererklärung', 'Tax return'),
        child: Text(
          tr(
            'Lege das Abschluss-PDF der Steuererklärung bei. Es enthält die Aufstellung über Einnahmen, Ausgaben, Vermögen, Privatbezüge und Privateinlagen, die alle Kantone von Selbständigen ohne Buchhaltung verlangen. Die Feld-Zuordnung gibt es bisher für Luzern.',
            'Attach the PDF of the accounts to your tax return. It contains the statement of income, expenses, assets, private withdrawals and deposits that all cantons require from self-employed people without bookkeeping. Field mapping exists for Lucerne so far.',
          ),
          style: TextStyle(color: c.muted),
        ),
      );
    }
    return SectionCard(
      title: tr('Felder für die Steuererklärung', 'Fields for the tax return'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final sec in sections) ...[
            Padding(padding: const EdgeInsets.only(top: 6, bottom: 6), child: Text(sec.title, style: const TextStyle(fontWeight: FontWeight.w600))),
            for (final f in sec.fields)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 86,
                      child: Text(f.code, style: TextStyle(color: c.muted, fontWeight: f.total ? FontWeight.w600 : null)),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(f.label, style: f.total ? const TextStyle(fontWeight: FontWeight.w600) : null),
                          if (f.note.isNotEmpty) Text(f.note, style: TextStyle(color: c.muted, fontSize: 12.5)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    AmountText(f.amount, colored: false, sign: false, style: f.total ? const TextStyle(fontWeight: FontWeight.w600) : null),
                  ],
                ),
              ),
            if (sec.note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(sec.note, style: TextStyle(color: c.muted, fontSize: 12.5))),
            const SizedBox(height: 10),
          ],
          Text(
            tr(
              'Beträge in der Steuererklärung ohne Rappen eintragen. Feldnummern nach der Wegleitung 2026 des Kantons Luzern.',
              'Enter amounts in the tax return without centimes. Field numbers as in the 2026 guide of the canton of Lucerne.',
            ),
            style: TextStyle(color: c.muted, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

/// Status des Jahres: offen oder abgeschlossen.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.closing});
  final YearClosing closing;

  @override
  Widget build(BuildContext context) {
    final c = context.conti;
    final closed = closing.closed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        gradient: closed ? LinearGradient(colors: c.mint) : null,
        border: closed ? null : Border.all(color: c.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(closed ? Icons.lock : Icons.edit_note, size: 15, color: closed ? Colors.white : c.muted),
          const SizedBox(width: 5),
          Text(
            closed ? tr('abgeschlossen ${Day.short(closing.closedAt!.toLocal())}', 'closed ${Day.short(closing.closedAt!.toLocal())}') : tr('offen', 'open'),
            style: TextStyle(fontSize: 12.5, color: closed ? Colors.white : c.muted, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Ein Schritt im Vorbereiten, mit Häkchen.
class _Step extends StatelessWidget {
  const _Step({required this.done, required this.title, required this.text, required this.child, this.neutral = false});
  final bool done;
  final bool neutral;
  final String title;
  final String text;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.conti;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            neutral ? Icons.radio_button_unchecked : (done ? Icons.check_circle : Icons.radio_button_unchecked),
            color: done ? c.plus : c.muted,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(text, style: TextStyle(color: c.muted)),
                const SizedBox(height: 4),
                child,
              ],
            ),
          ),
        ],
      ),
    );
  }
}
