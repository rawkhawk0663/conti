import 'package:flutter/material.dart';

import '../../app/l10n.dart';
import '../../core/conti_state.dart';
import '../../core/model/crm.dart';
import '../../core/model/synced.dart';
import '../../widgets/visuals.dart';

/// Kunde anlegen oder ändern (eigene Seite). Gibt den gespeicherten Kunden zurück.
Future<Client?> editClient(BuildContext context, {Client? client}) {
  return Navigator.of(context).push<Client>(
    MaterialPageRoute(fullscreenDialog: true, builder: (_) => ClientEditor(client: client)),
  );
}

class ClientEditor extends StatefulWidget {
  const ClientEditor({super.key, this.client});
  final Client? client;

  @override
  State<ClientEditor> createState() => _ClientEditorState();
}

class _ClientEditorState extends State<ClientEditor> {
  late Client _c;
  final _f = <String, TextEditingController>{};
  String? _error;

  TextEditingController _ctl(String k, String v) => _f.putIfAbsent(k, () => TextEditingController(text: v));

  @override
  void initState() {
    super.initState();
    _c = widget.client?.copy() ?? Client(id: newId());
  }

  @override
  void dispose() {
    for (final c in _f.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    String v(String k) => _f[k]?.text.trim() ?? '';
    if (v('first').isEmpty && v('last').isEmpty && v('company').isEmpty) {
      setState(() => _error = tr('Bitte einen Namen oder eine Firma eingeben.', 'Please enter a name or a company.'));
      return;
    }
    _c
      ..firstName = v('first')
      ..lastName = v('last')
      ..company = v('company')
      ..street = v('street')
      ..houseNumber = v('no')
      ..zip = v('zip')
      ..city = v('city')
      ..country = v('country').isEmpty ? 'CH' : v('country').toUpperCase()
      ..email = v('email')
      ..phone = v('phone')
      ..notes = v('notes');
    await ContiScope.read(context).saveClient(_c);
    if (mounted) Navigator.pop(context, _c);
  }

  Future<void> _delete() async {
    final s = ContiScope.read(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Kunde löschen?', 'Delete client?')),
        content: Text(
          tr(
            'Der Kunde verschwindet aus der Liste. Aufträge und Buchungen bleiben erhalten.',
            'The client disappears from the list. Orders and entries are kept.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Abbrechen', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Löschen', 'Delete'))),
        ],
      ),
    );
    if (ok != true) return;
    await s.deleteClient(_c);
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    Widget field(String key, String label, String value, {TextInputType? type, int flex = 1, int lines = 1}) => Expanded(
      flex: flex,
      child: TextField(
        controller: _ctl(key, value),
        keyboardType: type,
        minLines: lines,
        maxLines: lines == 1 ? 1 : 8,
        textCapitalization: type == null ? TextCapitalization.words : TextCapitalization.none,
        decoration: InputDecoration(labelText: label),
      ),
    );
    Widget row(List<Widget> ws) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(children: [for (final (i, w) in ws.indexed) ...[if (i > 0) const SizedBox(width: 12), w]]),
    );
    final c = _c;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.client == null ? tr('Neuer Kunde', 'New client') : tr('Kunde bearbeiten', 'Edit client')),
        actions: [
          if (widget.client != null) IconButton(tooltip: tr('Löschen', 'Delete'), icon: const Icon(Icons.delete_outline), onPressed: _delete),
          IconButton(tooltip: tr('Sichern', 'Save'), icon: const Icon(Icons.check), onPressed: _save),
          const SizedBox(width: 4),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              SectionCard(
                title: tr('Name', 'Name'),
                child: Column(
                  children: [
                    row([field('first', tr('Vorname', 'First name'), c.firstName), field('last', tr('Nachname', 'Last name'), c.lastName)]),
                    row([field('company', tr('Firma (optional)', 'Company (optional)'), c.company)]),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SectionCard(
                title: tr('Adresse', 'Address'),
                child: Column(
                  children: [
                    row([field('street', tr('Strasse', 'Street'), c.street, flex: 3), field('no', tr('Nr.', 'No.'), c.houseNumber)]),
                    row([
                      field('zip', tr('PLZ', 'Postcode'), c.zip, type: TextInputType.number),
                      field('city', tr('Ort', 'Town'), c.city, flex: 3),
                    ]),
                    row([field('country', tr('Land (z. B. CH)', 'Country (e.g. CH)'), c.country)]),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SectionCard(
                title: tr('Kontakt', 'Contact'),
                child: Column(
                  children: [
                    row([field('email', tr('E-Mail', 'Email'), c.email, type: TextInputType.emailAddress)]),
                    row([field('phone', tr('Telefon', 'Phone'), c.phone, type: TextInputType.phone)]),
                    row([field('notes', tr('Notizen', 'Notes'), c.notes, type: TextInputType.multiline, lines: 3)]),
                  ],
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              const SizedBox(height: 20),
              Align(alignment: Alignment.centerRight, child: GradientButton(label: tr('Sichern', 'Save'), icon: Icons.check, onPressed: _save)),
            ],
          ),
        ),
      ),
    );
  }
}
