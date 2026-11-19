import 'package:flutter/material.dart';

import '../../app/l10n.dart';
import '../../app/theme.dart';
import '../../core/conti_state.dart';
import '../../core/dates.dart';
import '../../core/model/entry.dart';
import '../../core/model/synced.dart';
import '../../core/money.dart';
import '../../widgets/visuals.dart';
import '../sync/sync_page.dart';
import 'entry_editor.dart';
import 'entry_tile.dart';

/// Alle Buchungen, nach Monat gruppiert, mit Suche und Filtern.
class EntriesScreen extends StatefulWidget {
  const EntriesScreen({super.key});

  @override
  State<EntriesScreen> createState() => _EntriesScreenState();
}

class _EntriesScreenState extends State<EntriesScreen> {
  final _search = TextEditingController();

  /// null = alle Jahre
  int? _year = Day.today().year;
  EntryKind? _kind;
  String? _accountId;
  String? _categoryId;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(ContiState s, Entry e) {
    if (_year != null && e.year != _year) return false;
    if (_kind != null && e.kind != _kind) return false;
    if (_accountId != null && e.accountId != _accountId && e.toAccountId != _accountId) return false;
    if (_categoryId != null) {
      final ids = {e.categoryId, ...e.splits.map((x) => x.categoryId)};
      final hit = ids.any((id) => id == _categoryId || s.category(id)?.parentId == _categoryId);
      if (!hit) return false;
    }
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    final hay = [
      e.text,
      e.notes,
      e.number,
      s.categoryLabel(e.categoryId),
      s.account(e.accountId)?.name ?? '',
      s.client(e.clientId)?.displayName ?? '',
      Money.format(e.amount),
      Day.short(e.date),
    ].join(' ').toLowerCase();
    return q.split(RegExp(r'\s+')).every(hay.contains);
  }

  Future<void> _entryMenu(Entry e) async {
    final s = ContiScope.read(context);
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.edit_outlined), title: Text(tr('Bearbeiten', 'Edit')), onTap: () => Navigator.pop(context, 'edit')),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: Text(tr('Als neue Buchung kopieren', 'Copy as new entry')),
              onTap: () => Navigator.pop(context, 'copy'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(tr('Löschen', 'Delete')),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'edit':
        await openEntryEditor(context, entry: e);
      case 'copy':
        final c = Entry.fromJson({...e.toJson(), 'id': newId(), 'attachments': <dynamic>[]})..date = Day.today();
        await openEntryEditor(context, entry: c, isNew: true);
      case 'delete':
        await deleteWithUndo(context, s, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ContiScope.of(context);
    final c = context.conti;
    final list = s.entries.where((e) => _matches(s, e)).toList()
      ..sort((a, b) {
        final d = b.date.compareTo(a.date);
        return d != 0 ? d : b.createdAt.compareTo(a.createdAt);
      });

    // Nach Monat gruppieren
    final groups = <(int, int), List<Entry>>{};
    for (final e in list) {
      groups.putIfAbsent((e.year, e.date.month), () => []).add(e);
    }
    final income = list.where((e) => e.kind == EntryKind.income && !e.excludeFromReports).fold(0, (a, e) => a + e.amount);
    final expenses = list.where((e) => e.kind == EntryKind.expense && !e.excludeFromReports).fold(0, (a, e) => a + e.amount);
    final filtered = _kind != null || _accountId != null || _categoryId != null || _search.text.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: Text(tr('Buchungen', 'Entries')), actions: const [SyncStatusButton(), SizedBox(width: 4)]),
      floatingActionButton: GradientFab(
        label: tr('Buchung', 'Entry'),
        icon: Icons.add,
        onPressed: () => openEntryEditor(context, kind: _kind),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: tr('Suchen: Text, Betrag, Kategorie …', 'Search: text, amount, category …'),
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(_search.clear),
                      ),
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _Menu<int?>(
                  label: _year == null ? tr('Alle Jahre', 'All years') : '$_year',
                  items: [(null, tr('Alle Jahre', 'All years')), for (final y in s.years) (y, '$y')],
                  onSelected: (y) => setState(() => _year = y),
                  active: true,
                ),
                const SizedBox(width: 8),
                for (final (k, label) in [
                  (EntryKind.income, tr('Einnahmen', 'Income')),
                  (EntryKind.expense, tr('Ausgaben', 'Expenses')),
                  (EntryKind.transfer, tr('Umbuchungen', 'Transfers')),
                ]) ...[
                  FilterChip(
                    label: Text(label),
                    selected: _kind == k,
                    onSelected: (v) => setState(() => _kind = v ? k : null),
                  ),
                  const SizedBox(width: 8),
                ],
                _Menu<String?>(
                  label: _accountId == null ? tr('Alle Konten', 'All accounts') : (s.account(_accountId)?.name ?? '?'),
                  items: [(null, tr('Alle Konten', 'All accounts')), for (final a in s.accounts) (a.id, a.name)],
                  onSelected: (v) => setState(() => _accountId = v),
                  active: _accountId != null,
                ),
                const SizedBox(width: 8),
                _Menu<String?>(
                  label: _categoryId == null ? tr('Alle Kategorien', 'All categories') : s.categoryLabel(_categoryId),
                  items: [
                    (null, tr('Alle Kategorien', 'All categories')),
                    for (final (cat, depth) in s.categoryTree()) (cat.id, '${depth > 0 ? '   ' : ''}${cat.name}'),
                  ],
                  onSelected: (v) => setState(() => _categoryId = v),
                  active: _categoryId != null,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Row(
              children: [
                Text(
                  tr('${list.length} Buchungen', '${list.length} entries'),
                  style: TextStyle(color: c.muted, fontSize: 13),
                ),
                const Spacer(),
                Text('+${Money.format(income)}', style: TextStyle(color: c.plus, fontSize: 13)),
                const SizedBox(width: 12),
                Text('−${Money.format(expenses)}', style: TextStyle(color: c.minus, fontSize: 13)),
              ],
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? EmptyState(
                    icon: Icons.receipt_long,
                    title: filtered ? tr('Nichts gefunden', 'Nothing found') : tr('Noch keine Buchungen', 'No entries yet'),
                    text: filtered
                        ? tr('Ändere die Suche oder die Filter.', 'Change the search or the filters.')
                        : tr(
                            'Erfasse deine erste Einnahme oder Ausgabe mit dem Knopf unten rechts.',
                            'Add your first income or expense with the button at the bottom right.',
                          ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 110),
                    children: [
                      for (final g in groups.entries) ...[
                        _MonthHeader(year: g.key.$1, month: g.key.$2, entries: g.value),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Column(
                              children: [
                                for (final e in g.value)
                                  EntryTile(
                                    entry: e,
                                    onTap: () => openEntryEditor(context, entry: e),
                                    onLongPress: () => _entryMenu(e),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({required this.year, required this.month, required this.entries});
  final int year, month;
  final List<Entry> entries;

  @override
  Widget build(BuildContext context) {
    final sum = entries.where((e) => !e.excludeFromReports).fold(0, (a, e) => a + e.signedAmount);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Row(
        children: [
          Expanded(child: CapsLabel('${Day.monthName(month)} $year')),
          AmountText(sum, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}

/// Aufklapp-Filter als Chip.
class _Menu<T> extends StatelessWidget {
  const _Menu({required this.label, required this.items, required this.onSelected, required this.active});
  final String label;
  final List<(T, String)> items;
  final ValueChanged<T> onSelected;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        for (final (v, text) in items) MenuItemButton(onPressed: () => onSelected(v), child: Text(text)),
      ],
      builder: (context, controller, _) => ActionChip(
        avatar: const Icon(Icons.expand_more, size: 18),
        label: Text(label),
        side: active ? BorderSide(color: Theme.of(context).colorScheme.primary) : null,
        onPressed: () => controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}

/// Löschen mit „Rückgängig“.
Future<void> deleteWithUndo(BuildContext context, ContiState s, Entry e) async {
  final messenger = ScaffoldMessenger.of(context);
  await s.deleteEntry(e);
  messenger.showSnackBar(
    SnackBar(
      content: Text(tr('Buchung gelöscht', 'Entry deleted')),
      persist: false,
      duration: const Duration(seconds: 6),
      action: SnackBarAction(label: tr('Rückgängig', 'Undo'), onPressed: () => s.restoreEntry(e)),
    ),
  );
}
