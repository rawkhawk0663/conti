import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/l10n.dart';
import '../../app/theme.dart';
import '../../core/conti_state.dart';
import '../../core/money.dart';
import '../../widgets/visuals.dart';
import '../entries/entry_editor.dart';
import '../entries/entry_tile.dart';
import '../orders/order_editor.dart';
import '../orders/order_widgets.dart';
import '../tasks/tasks.dart';
import 'client_editor.dart';
import 'clients_screen.dart';

/// Kundenkarte: Kontakt, Aufträge, Aufgaben, Buchungen, Notizen.
class ClientPage extends StatelessWidget {
  const ClientPage({super.key, required this.clientId});
  final String clientId;

  @override
  Widget build(BuildContext context) {
    final s = ContiScope.of(context);
    final c = context.conti;
    final client = s.client(clientId);
    if (client == null || client.deleted) {
      return Scaffold(appBar: AppBar(), body: Center(child: Text(tr('Diesen Kunden gibt es nicht mehr.', 'This client no longer exists.'))));
    }
    final orders = s.ordersOf(client.id);
    final tasks = s.tasksOf(client.id)..sort((a, b) => a.done == b.done ? 0 : (a.done ? 1 : -1));
    final entries = s.entriesOf(client.id);
    final paid = entries.fold(0, (a, e) => a + e.signedAmount);
    final open = s.openAmountOf(client.id);

    Future<void> copy(String text) async {
      await Clipboard.setData(ClipboardData(text: text));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Kopiert', 'Copied')), persist: false));
      }
    }

    Widget contact(IconData icon, String text, Uri? uri) => ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(icon, color: c.muted),
      title: Text(text),
      onTap: uri == null ? () => copy(text) : () => launchUrl(uri),
      onLongPress: () => copy(text),
    );

    final header = SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ClientAvatar(client, size: 56),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(client.displayName, style: Theme.of(context).textTheme.titleLarge),
                    if (client.company.isNotEmpty && client.personName.isNotEmpty) Text(client.personName, style: TextStyle(color: c.muted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [CapsLabel(tr('Eingenommen', 'Received')), const SizedBox(height: 4), BigNumber(Money.format(paid), size: 26)],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CapsLabel(tr('Offen', 'Due')),
                    const SizedBox(height: 4),
                    Text(
                      Money.format(open),
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.w300, color: open > 0 ? c.minus : null),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (client.addressLine.isNotEmpty) contact(Icons.place_outlined, client.addressLine, null),
          if (client.email.isNotEmpty) contact(Icons.mail_outline, client.email, Uri(scheme: 'mailto', path: client.email)),
          if (client.phone.isNotEmpty) contact(Icons.call_outlined, client.phone, Uri(scheme: 'tel', path: client.phone.replaceAll(' ', ''))),
          if (client.notes.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 6), child: Text(client.notes, style: TextStyle(color: c.muted))),
        ],
      ),
    );

    final ordersCard = SectionCard(
      title: tr('Aufträge', 'Orders'),
      trailing: TextButton.icon(
        onPressed: () => openOrderEditor(context, clientId: client.id),
        icon: const Icon(Icons.add),
        label: Text(tr('Auftrag', 'Order')),
      ),
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: orders.isEmpty
          ? Padding(padding: const EdgeInsets.all(16), child: Text(tr('Noch keine Aufträge.', 'No orders yet.'), style: TextStyle(color: c.muted)))
          : Column(children: [for (final o in orders) OrderTile(order: o, showClient: false)]),
    );

    final tasksCard = SectionCard(
      title: tr('Aufgaben', 'Tasks'),
      trailing: TextButton.icon(
        onPressed: () => editTask(context, clientId: client.id),
        icon: const Icon(Icons.add),
        label: Text(tr('Aufgabe', 'Task')),
      ),
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: tasks.isEmpty
          ? Padding(padding: const EdgeInsets.all(16), child: Text(tr('Keine Aufgaben.', 'No tasks.'), style: TextStyle(color: c.muted)))
          : Column(children: [for (final t in tasks) TaskTile(task: t, showClient: false)]),
    );

    final entriesCard = SectionCard(
      title: tr('Buchungen', 'Entries'),
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: entries.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Text(tr('Noch keine Buchungen mit diesem Kunden.', 'No entries with this client yet.'), style: TextStyle(color: c.muted)),
            )
          : Column(children: [for (final e in entries.take(20)) EntryTile(entry: e, onTap: () => openEntryEditor(context, entry: e))]),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Kunde', 'Client')),
        actions: [
          IconButton(tooltip: tr('Bearbeiten', 'Edit'), icon: const Icon(Icons.edit_outlined), onPressed: () => editClient(context, client: client)),
          const SizedBox(width: 4),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, box) {
          const pad = EdgeInsets.fromLTRB(16, 4, 16, 40);
          if (box.maxWidth < 900) {
            return ListView(
              padding: pad,
              children: [header, const SizedBox(height: 14), ordersCard, const SizedBox(height: 14), tasksCard, const SizedBox(height: 14), entriesCard],
            );
          }
          return SingleChildScrollView(
            padding: pad,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: Column(children: [header, const SizedBox(height: 14), tasksCard])),
                const SizedBox(width: 14),
                Expanded(flex: 3, child: Column(children: [ordersCard, const SizedBox(height: 14), entriesCard])),
              ],
            ),
          );
        },
      ),
    );
  }
}
