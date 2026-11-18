import 'package:flutter/material.dart';

import '../../app/l10n.dart';
import '../../app/theme.dart';
import '../../core/conti_state.dart';
import '../../core/dates.dart';
import '../../core/model/entry.dart';
import '../../core/money.dart';
import '../../widgets/visuals.dart';
import '../entries/entry_editor.dart';
import '../entries/entry_tile.dart';

/// Startseite: Gewinn des Jahres, Konten, Monate, letzte Buchungen.
class OverviewScreen extends StatefulWidget {
  const OverviewScreen({super.key, required this.onShowEntries});
  final VoidCallback onShowEntries;

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  int? _year;

  @override
  Widget build(BuildContext context) {
    final s = ContiScope.of(context);
    final years = s.years;
    final year = _year != null && years.contains(_year) ? _year! : years.first;
    final income = s.incomeOf(year);
    final expenses = s.expensesOf(year);
    final profit = income - expenses;
    final name = s.business.displayName;

    final cards = <Widget>[
      _ProfitCard(year: year, income: income, expenses: expenses, profit: profit),
      _AccountsCard(),
      _MonthsCard(year: year),
      _CategoriesCard(year: year),
      _RecentCard(onShowAll: widget.onShowEntries),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(name.isEmpty ? 'Conti' : name),
        actions: [
          if (years.length > 1)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: year,
                  borderRadius: BorderRadius.circular(14),
                  items: [for (final y in years) DropdownMenuItem(value: y, child: Text('$y'))],
                  onChanged: (y) => setState(() => _year = y),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: GradientFab(
        label: tr('Buchung', 'Entry'),
        icon: Icons.add,
        onPressed: () => openEntryEditor(context),
      ),
      body: LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= 900;
          final pad = EdgeInsets.fromLTRB(16, 8, 16, 110);
          if (!wide) {
            return ListView.separated(
              padding: pad,
              itemCount: cards.length,
              separatorBuilder: (_, _) => const SizedBox(height: 14),
              itemBuilder: (_, i) => cards[i],
            );
          }
          // Zwei Spalten: links die Zahlen, rechts Konten und Letzte Buchungen.
          return SingleChildScrollView(
            padding: pad,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: Column(children: [cards[0], const SizedBox(height: 14), cards[2], const SizedBox(height: 14), cards[3]]),
                ),
                const SizedBox(width: 14),
                Expanded(flex: 2, child: Column(children: [cards[1], const SizedBox(height: 14), cards[4]])),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ProfitCard extends StatelessWidget {
  const _ProfitCard({required this.year, required this.income, required this.expenses, required this.profit});
  final int year, income, expenses, profit;

  @override
  Widget build(BuildContext context) {
    final c = context.conti;
    final ratio = income <= 0 ? 0.0 : (profit / income).clamp(0.0, 1.0);
    final maxV = income > expenses ? income : expenses;
    return SectionCard(
      title: tr('Jahr $year', 'Year $year'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GradientRing(value: ratio, colors: c.pink, label: income <= 0 ? '–' : '${(ratio * 100).round()}%'),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BigNumber(Money.format(profit)),
                    const SizedBox(height: 6),
                    Text(
                      profit >= 0 ? tr('Gewinn in CHF', 'Profit in CHF') : tr('Verlust in CHF', 'Loss in CHF'),
                      style: TextStyle(color: c.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          _BarRow(label: tr('Einnahmen', 'Income'), value: income, max: maxV, colors: c.mint),
          const SizedBox(height: 14),
          _BarRow(label: tr('Ausgaben', 'Expenses'), value: expenses, max: maxV, colors: c.sun),
        ],
      ),
    );
  }
}

class _BarRow extends StatelessWidget {
  const _BarRow({required this.label, required this.value, required this.max, required this.colors});
  final String label;
  final int value, max;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: CapsLabel(label)),
            Text(
              Money.format(value),
              style: TextStyle(color: context.conti.muted, fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ],
        ),
        const SizedBox(height: 7),
        GradientBar(value: max <= 0 ? 0 : value / max, colors: colors),
      ],
    );
  }
}

class _AccountsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final s = ContiScope.of(context);
    final accounts = s.activeAccounts;
    return SectionCard(
      title: tr('Konten', 'Accounts'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BigNumber(Money.format(s.totalBalance), size: 30),
          const SizedBox(height: 4),
          Text(tr('Total heute', 'Total today'), style: TextStyle(color: context.conti.muted)),
          const SizedBox(height: 14),
          for (final a in accounts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(child: Text(a.name)),
                  AmountText(s.balance(a.id), colored: false, sign: false),
                ],
              ),
            ),
          if (accounts.isEmpty) Text(tr('Noch keine Konten.', 'No accounts yet.')),
        ],
      ),
    );
  }
}

class _MonthsCard extends StatelessWidget {
  const _MonthsCard({required this.year});
  final int year;

  @override
  Widget build(BuildContext context) {
    final s = ContiScope.of(context);
    final c = context.conti;
    Widget legend(List<Color> colors, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(gradient: LinearGradient(colors: colors), shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(color: c.muted, fontSize: 13)),
      ],
    );
    return SectionCard(
      title: tr('Monate', 'Months'),
      trailing: Wrap(spacing: 14, children: [legend(c.mint, tr('Einnahmen', 'Income')), legend(c.sun, tr('Ausgaben', 'Expenses'))]),
      child: MonthBars(
        income: [for (var m = 1; m <= 12; m++) s.incomeOf(year, month: m)],
        expenses: [for (var m = 1; m <= 12; m++) s.expensesOf(year, month: m)],
        labels: [for (var m = 1; m <= 12; m++) Day.monthShort(m)],
      ),
    );
  }
}

class _CategoriesCard extends StatelessWidget {
  const _CategoriesCard({required this.year});
  final int year;

  @override
  Widget build(BuildContext context) {
    final s = ContiScope.of(context);
    final c = context.conti;
    final exp = s.totalsByTopCategory(year, income: false).entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final inc = s.totalsByTopCategory(year, income: true).entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    if (exp.isEmpty && inc.isEmpty) return const SizedBox.shrink();
    Widget block(String title, List<MapEntry<String, int>> rows, List<Color> colors) {
      final max = rows.isEmpty ? 1 : rows.first.value;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CapsLabel(title),
          const SizedBox(height: 10),
          for (final r in rows.take(6))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(s.categoryLabel(r.key), overflow: TextOverflow.ellipsis)),
                      Text(Money.format(r.value), style: TextStyle(color: c.muted, fontFeatures: const [FontFeature.tabularFigures()])),
                    ],
                  ),
                  const SizedBox(height: 5),
                  GradientBar(value: r.value / max, colors: colors, height: 6),
                ],
              ),
            ),
        ],
      );
    }

    return SectionCard(
      title: tr('Nach Kategorie', 'By category'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (inc.isNotEmpty) block(tr('Einnahmen', 'Income'), inc, c.mint),
          if (inc.isNotEmpty && exp.isNotEmpty) const SizedBox(height: 10),
          if (exp.isNotEmpty) block(tr('Ausgaben', 'Expenses'), exp, c.sun),
        ],
      ),
    );
  }
}

class _RecentCard extends StatelessWidget {
  const _RecentCard({required this.onShowAll});
  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context) {
    final s = ContiScope.of(context);
    final recent = s.entries..sort((a, b) {
      final d = b.date.compareTo(a.date);
      return d != 0 ? d : b.createdAt.compareTo(a.createdAt);
    });
    return SectionCard(
      title: tr('Letzte Buchungen', 'Latest entries'),
      trailing: TextButton(onPressed: onShowAll, child: Text(tr('Alle', 'All'))),
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: recent.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                tr(
                  'Noch keine Buchungen. Tippe unten rechts auf „Buchung“.',
                  'No entries yet. Tap “Entry” at the bottom right.',
                ),
                style: TextStyle(color: context.conti.muted),
              ),
            )
          : Column(
              children: [
                for (final e in recent.take(6))
                  EntryTile(entry: e, onTap: () => openEntryEditor(context, entry: e)),
              ],
            ),
    );
  }
}

/// Neue Buchung mit voreingestellter Art (für Schnellknöpfe).
Future<void> newEntryOf(BuildContext context, EntryKind kind) => openEntryEditor(context, kind: kind);
