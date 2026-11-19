import 'package:flutter/material.dart';

import '../../app/l10n.dart';
import '../../app/theme.dart';
import '../../core/conti_state.dart';
import '../../core/dates.dart';
import '../../core/model/crm.dart';
import '../../core/model/synced.dart';
import '../../core/money.dart';
import '../../widgets/context_menu.dart';
import '../../widgets/visuals.dart';
import 'order_editor.dart';

String statusLabel(OrderStatus s) => switch (s) {
  OrderStatus.open => tr('Offen', 'Open'),
  OrderStatus.inProgress => tr('In Arbeit', 'In progress'),
  OrderStatus.done => tr('Erledigt', 'Done'),
  OrderStatus.invoiced => tr('Verrechnet', 'Invoiced'),
  OrderStatus.paid => tr('Bezahlt', 'Paid'),
  OrderStatus.cancelled => tr('Abgesagt', 'Cancelled'),
};

/// Farben des Stands, nach der festen Bedeutung der Verläufe.
List<Color> statusColors(BuildContext context, OrderStatus s) {
  final c = context.conti;
  return switch (s) {
    OrderStatus.open => c.sky,
    OrderStatus.inProgress => c.pink,
    OrderStatus.done => c.pink,
    OrderStatus.invoiced => c.sun,
    OrderStatus.paid => c.mint,
    OrderStatus.cancelled => [c.muted, c.muted],
  };
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.status, {super.key});
  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = statusColors(context, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.last.withValues(alpha: 0.8)),
        color: colors.last.withValues(alpha: 0.14),
      ),
      child: Text(
        statusLabel(status),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: colors.last,
        ),
      ),
    );
  }
}

/// Abo-Fortschritt als Punkte: ● ● ● ○ ○  3/5
class SubscriptionDots extends StatelessWidget {
  const SubscriptionDots({super.key, required this.order, this.size = 10});
  final Order order;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.conti;
    final total = order.lessonsTotal ?? 0;
    final used = order.lessonsUsed;
    final many = total > 12;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (many)
          SizedBox(
            width: 90,
            child: GradientBar(
              value: total == 0 ? 0 : used / total,
              colors: c.pink,
              height: 6,
            ),
          )
        else
          for (var i = 0; i < total; i++)
            Container(
              width: size,
              height: size,
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: i < used ? LinearGradient(colors: c.pink) : null,
                color: i < used ? null : c.track,
              ),
            ),
        const SizedBox(width: 6),
        Text(
          '$used/$total',
          style: TextStyle(
            color: c.muted,
            fontSize: 12,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// Eine Zeile in Auftragslisten.
class OrderTile extends StatelessWidget {
  const OrderTile({super.key, required this.order, this.showClient = true});
  final Order order;
  final bool showClient;

  @override
  Widget build(BuildContext context) {
    final s = ContiScope.of(context);
    final c = context.conti;
    final o = order;
    final who = showClient ? s.client(o.clientId)?.displayName : null;
    final sub = [
      o.number,
      s.kindLabel(o),
      ?who,
      if (o.date != null) Day.short(o.date!),
    ].where((x) => x.isNotEmpty).join(' · ');
    return ContextMenuArea(
      onMenu: (at) => showOrderMenu(context, o, at: at),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => openOrderEditor(context, order: o),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      o.title.isEmpty ? tr('Ohne Titel', 'Untitled') : o.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.muted, fontSize: 13),
                    ),
                    if (o.isSubscription) ...[
                      const SizedBox(height: 6),
                      SubscriptionDots(order: o),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    Money.format(o.total),
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 4),
                  StatusPill(o.status),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Menü eines Auftrags: Bearbeiten, kopieren, löschen.
Future<void> showOrderMenu(BuildContext context, Order o, {Offset? at}) async {
  final s = ContiScope.read(context);
  final choice = await showContextMenu<String>(
    context,
    at: at,
    actions: [
      MenuAction('edit', Icons.edit_outlined, tr('Bearbeiten', 'Edit')),
      MenuAction(
        'copy',
        Icons.copy_outlined,
        tr('Als neuen Auftrag kopieren', 'Copy as new order'),
      ),
      MenuAction(
        'delete',
        Icons.delete_outline,
        tr('Löschen', 'Delete'),
        danger: true,
      ),
    ],
  );
  if (!context.mounted) return;
  switch (choice) {
    case 'edit':
      await openOrderEditor(context, order: o);
    case 'copy':
      final c = Order(
        id: newId(),
        number: s.nextOrderNumber(),
        title: o.title,
        kind: o.kind,
        clientId: o.clientId,
        lessonsTotal: o.lessonsTotal,
        notes: o.notes,
        items: [
          for (final i in o.items)
            OrderItem.fromJson({...i.toJson(), 'id': newId()}),
        ],
      );
      await s.saveOrder(c);
      if (context.mounted) await openOrderEditor(context, order: c);
    case 'delete':
      await s.deleteOrder(o);
      if (context.mounted) {
        showUndo(
          context,
          tr('Auftrag gelöscht', 'Order deleted'),
          () => s.saveOrder(o.copy()..deleted = false),
          undoLabel: tr('Rückgängig', 'Undo'),
        );
      }
  }
}
