import 'package:flutter/material.dart';

import '../../app/l10n.dart';
import '../../app/theme.dart';
import '../../core/conti_state.dart';
import '../../core/dates.dart';
import '../../core/model/entry.dart';
import '../../widgets/visuals.dart';

/// Eine Zeile in der Buchungsliste.
class EntryTile extends StatelessWidget {
  const EntryTile({super.key, required this.entry, required this.onTap, this.onLongPress});

  final Entry entry;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final s = ContiScope.of(context);
    final c = context.conti;
    final e = entry;
    final colors = switch (e.kind) {
      EntryKind.income => c.mint,
      EntryKind.expense => c.sun,
      EntryKind.transfer => c.sky,
    };
    final icon = switch (e.kind) {
      EntryKind.income => Icons.south_west,
      EntryKind.expense => Icons.north_east,
      EntryKind.transfer => Icons.swap_horiz,
    };
    final String sub;
    if (e.kind == EntryKind.transfer) {
      sub = '${s.account(e.accountId)?.name ?? '?'} → ${s.account(e.toAccountId)?.name ?? '?'}';
    } else {
      final cat = e.splits.isNotEmpty
          ? tr('Aufgeteilt (${e.splits.length})', 'Split (${e.splits.length})')
          : s.categoryLabel(e.categoryId);
      final acc = s.account(e.accountId)?.name;
      sub = acc == null ? cat : '$cat · $acc';
    }
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: Colors.white),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.text.isEmpty ? tr('Ohne Text', 'No description') : e.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${Day.short(e.date)} · $sub',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.muted, fontSize: 13),
                  ),
                ],
              ),
            ),
            if (e.attachments.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(Icons.attach_file, size: 18, color: c.muted),
              ),
            const SizedBox(width: 8),
            e.kind == EntryKind.transfer
                ? AmountText(e.amount, colored: false, sign: false)
                : AmountText(e.signedAmount),
          ],
        ),
      ),
    );
  }
}
