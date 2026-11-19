import 'package:flutter/material.dart';

import '../../app/l10n.dart';
import '../../app/theme.dart';
import '../../core/conti_state.dart';
import '../../core/model/crm.dart';
import '../../core/money.dart';
import '../../widgets/visuals.dart';
import '../sync/sync_page.dart';
import 'client_editor.dart';
import 'client_page.dart';

/// Rundes Zeichen mit den Anfangsbuchstaben.
class ClientAvatar extends StatelessWidget {
  const ClientAvatar(this.client, {super.key, this.size = 40});
  final Client client;
  final double size;

  @override
  Widget build(BuildContext context) {
    final name = client.displayName;
    final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final initials = parts.isEmpty ? '?' : (parts.length == 1 ? parts.first.substring(0, 1) : '${parts.first[0]}${parts.last[0]}').toUpperCase();
    final colors = [context.conti.sky, context.conti.mint, context.conti.pink, context.conti.sun][name.hashCode.abs() % 4];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight)),
      child: Text(initials, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: size * 0.36)),
    );
  }
}

class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key});

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _open(Client c) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ClientPage(clientId: c.id)));

  @override
  Widget build(BuildContext context) {
    final s = ContiScope.of(context);
    final c = context.conti;
    final q = _search.text.trim().toLowerCase();
    final list = s.clients
        .where((x) => q.isEmpty || [x.displayName, x.personName, x.city, x.email, x.phone].join(' ').toLowerCase().contains(q))
        .toList();
    return Scaffold(
      appBar: AppBar(title: Text(tr('Kunden', 'Clients')), actions: const [SyncStatusButton(), SizedBox(width: 4)]),
      floatingActionButton: GradientFab(
        label: tr('Kunde', 'Client'),
        icon: Icons.add,
        onPressed: () async {
          final n = await editClient(context);
          if (n != null && context.mounted) _open(n);
        },
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: tr('Suchen: Name, Ort, E-Mail …', 'Search: name, town, email …'),
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                suffixIcon: _search.text.isEmpty ? null : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_search.clear)),
              ),
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? EmptyState(
                    icon: Icons.people_outline,
                    title: q.isEmpty ? tr('Noch keine Kunden', 'No clients yet') : tr('Nichts gefunden', 'Nothing found'),
                    text: tr(
                      'Lege Kundinnen und Kunden mit Adresse an. Die Adresse kommt später so auf die Rechnung und in den QR-Zahlteil.',
                      'Add clients with their address. It later goes onto the invoice and into the QR payment part.',
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
                              for (final x in list)
                                ListTile(
                                  leading: ClientAvatar(x),
                                  title: Text(x.displayName),
                                  subtitle: Text(
                                    [if (x.company.isNotEmpty && x.personName.isNotEmpty) x.personName, x.city].where((t) => t.isNotEmpty).join(' · '),
                                  ),
                                  trailing: Builder(
                                    builder: (context) {
                                      final open = s.openAmountOf(x.id);
                                      final active = s.ordersOf(x.id).where((o) => o.status != OrderStatus.paid && o.status != OrderStatus.cancelled).length;
                                      return Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          if (open > 0) Text('${Money.format(open)} ${tr('offen', 'due')}', style: TextStyle(color: c.minus, fontSize: 13)),
                                          if (active > 0) Text(tr('$active aktiv', '$active active'), style: TextStyle(color: c.muted, fontSize: 12)),
                                        ],
                                      );
                                    },
                                  ),
                                  onTap: () => _open(x),
                                ),
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
