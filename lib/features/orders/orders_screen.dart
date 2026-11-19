import 'package:flutter/material.dart';

import '../../app/l10n.dart';
import '../../app/theme.dart';
import '../../core/conti_state.dart';
import '../../core/model/crm.dart';
import '../../core/money.dart';
import '../../widgets/visuals.dart';
import '../sync/sync_page.dart';
import 'order_editor.dart';
import 'order_widgets.dart';

/// Alle Aufträge mit Filter nach Stand.
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

enum _Filter { active, open, invoiced, paid, all }

class _OrdersScreenState extends State<OrdersScreen> {
  final _search = TextEditingController();
  _Filter _filter = _Filter.active;
  String? _kind;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(ContiState s, Order o) {
    final ok = switch (_filter) {
      _Filter.active => o.status != OrderStatus.paid && o.status != OrderStatus.cancelled,
      _Filter.open => o.status == OrderStatus.open || o.status == OrderStatus.inProgress || o.status == OrderStatus.done,
      _Filter.invoiced => o.status == OrderStatus.invoiced,
      _Filter.paid => o.status == OrderStatus.paid,
      _Filter.all => true,
    };
    if (!ok) return false;
    if (_kind != null && o.kind != _kind) return false;
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    final hay = [o.title, o.number, o.invoiceNumber, s.kindLabel(o), s.client(o.clientId)?.displayName ?? '', o.notes, ...o.items.map((i) => i.name)]
        .join(' ')
        .toLowerCase();
    return q.split(RegExp(r'\s+')).every(hay.contains);
  }

  @override
  Widget build(BuildContext context) {
    final s = ContiScope.of(context);
    final c = context.conti;
    final list = s.orders.where((o) => _matches(s, o)).toList()
      ..sort((a, b) {
        final ad = a.date ?? a.createdAt, bd = b.date ?? b.createdAt;
        return bd.compareTo(ad);
      });
    final sum = list.fold(0, (a, o) => a + o.total);
    final labels = {
      _Filter.active: tr('Aktiv', 'Active'),
      _Filter.open: tr('Zu verrechnen', 'To invoice'),
      _Filter.invoiced: tr('Verrechnet', 'Invoiced'),
      _Filter.paid: tr('Bezahlt', 'Paid'),
      _Filter.all: tr('Alle', 'All'),
    };
    return Scaffold(
      appBar: AppBar(title: Text(tr('Aufträge', 'Orders')), actions: const [SyncStatusButton(), SizedBox(width: 4)]),
      floatingActionButton: GradientFab(label: tr('Auftrag', 'Order'), icon: Icons.add, onPressed: () => openOrderEditor(context)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: tr('Suchen: Titel, Kunde, Nummer …', 'Search: title, client, number …'),
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                suffixIcon: _search.text.isEmpty ? null : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_search.clear)),
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final f in _Filter.values) ...[
                  ChoiceChip(label: Text(labels[f]!), selected: _filter == f, onSelected: (_) => setState(() => _filter = f)),
                  const SizedBox(width: 8),
                ],
                MenuAnchor(
                  menuChildren: [
                    MenuItemButton(onPressed: () => setState(() => _kind = null), child: Text(tr('Alle Arten', 'All kinds'))),
                    for (final k in s.orderKinds) MenuItemButton(onPressed: () => setState(() => _kind = k.id), child: Text(k.name)),
                  ],
                  builder: (context, ctl, _) => ActionChip(
                    avatar: const Icon(Icons.expand_more, size: 18),
                    label: Text(_kind == null ? tr('Alle Arten', 'All kinds') : (s.orderKind(_kind)?.name ?? '?')),
                    onPressed: () => ctl.isOpen ? ctl.close() : ctl.open(),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
            child: Row(
              children: [
                Text(tr('${list.length} Aufträge', '${list.length} orders'), style: TextStyle(color: c.muted, fontSize: 13)),
                const Spacer(),
                Text('CHF ${Money.format(sum)}', style: TextStyle(color: c.muted, fontSize: 13)),
              ],
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? EmptyState(
                    icon: Icons.work_outline,
                    title: tr('Keine Aufträge', 'No orders'),
                    text: tr(
                      'Ein Auftrag ist z. B. ein Gig, ein Lektionen-Abo oder eine Grafik-Arbeit. Lege ihn mit dem Knopf unten rechts an.',
                      'An order is e.g. a gig, a lesson pack or a design job. Create one with the button at the bottom right.',
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 110),
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Column(
                            children: [
                              for (final (i, o) in list.indexed) ...[
                                if (i > 0) const Divider(indent: 16, endIndent: 16),
                                OrderTile(order: o),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
