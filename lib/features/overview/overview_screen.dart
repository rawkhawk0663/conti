import 'package:flutter/material.dart';

import '../../app/l10n.dart';
import '../../app/theme.dart';
import '../../core/conti_state.dart';
import '../../core/dates.dart';
import '../../core/model/entry.dart';
import '../../core/money.dart';
import '../../widgets/visuals.dart';
import '../entries/entry_editor.dart';
import '../sync/sync_page.dart';
import '../entries/entry_tile.dart';
import '../orders/order_editor.dart';
import '../orders/order_widgets.dart';
import '../tasks/tasks.dart';

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
      const _TasksCard(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(name.isEmpty ? 'Conti' : name),
        actions: [
          const SyncStatusButton(),
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
              // Handy: Aufgaben gleich nach dem Gewinn.
              itemBuilder: (_, i) => cards[const [0, 5, 1, 2, 3, 4][i]],
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
                Expanded(
                  flex: 2,
                  child: Column(children: [cards[5], const SizedBox(height: 14), cards[1], const SizedBox(height: 14), cards[4]]),
                ),
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

/// Offene Aufgaben mit Ampel und aufgebrauchte Abos.
class _TasksCard extends StatelessWidget {
  const _TasksCard();

  @override
  Widget build(BuildContext context) {
    final s = ContiScope.of(context);
    final c = context.conti;
    final open = s.openTasks;
    final abos = s.usedUpSubscriptions;
    return SectionCard(
      title: tr('Aufgaben', 'Tasks'),
      trailing: TextButton(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TasksScreen())),
        child: Text(open.isEmpty ? tr('Öffnen', 'Open') : tr('Alle (${open.length})', 'All (${open.length})')),
      ),
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final o in abos)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => openOrderEditor(context, order: o),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(colors: [for (final x in c.sun) x.withValues(alpha: 0.16)]),
                    border: Border.all(color: c.sun.last.withValues(alpha: 0.6)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.autorenew, color: c.sun.last),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tr('Abo aufgebraucht', 'Lesson pack used up'), style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text(
                              '${s.client(o.clientId)?.displayName ?? o.title} · ${o.lessonsUsed}/${o.lessonsTotal}',
                              style: TextStyle(color: c.muted, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      SubscriptionDots(order: o, size: 8),
                    ],
                  ),
                ),
              ),
            ),
          if (open.isEmpty && abos.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(tr('Alles erledigt.', 'All done.'), style: TextStyle(color: c.muted)),
            ),
          for (final t in open.take(5)) TaskTile(task: t),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(onPressed: () => editTask(context), icon: const Icon(Icons.add), label: Text(tr('Aufgabe', 'Task'))),
          ),
        ],
      ),
    );
  }
}

/// Neue Buchung mit voreingestellter Art (für Schnellknöpfe).
Future<void> newEntryOf(BuildContext context, EntryKind kind) => openEntryEditor(context, kind: kind);
