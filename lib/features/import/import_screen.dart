import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../app/error_log.dart';
import '../../app/l10n.dart';
import '../../app/theme.dart';
import '../../core/conti_state.dart';
import '../../core/import/legacy_import.dart';
import '../../core/model/account.dart';
import '../../core/model/synced.dart';
import '../../core/money.dart';
import '../../core/swiss.dart';
import '../../widgets/visuals.dart';

/// Import aus der früheren Buchhaltungs-App: Datei wählen, Vorschau, übernehmen.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key, this.onDone});

  /// Nach dem Übernehmen (z. B. in der Einrichtung). Ohne: Seite schliessen.
  final VoidCallback? onDone;

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  LegacyData? _data;
  String? _fileName;
  String? _error;
  bool _busy = false;

  /// Konto für alle Buchungen. „new“ = neues Konto anlegen.
  String _accountId = 'new';
  String? _receipts;
  bool _takeBusiness = true;
  LegacyImportResult? _result;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _pick());
  }

  Future<void> _pick() async {
    final s = ContiScope.read(context);
    final f = await openFile(
      acceptedTypeGroups: const [XTypeGroup(label: 'JSON', extensions: ['json'], mimeTypes: ['application/json'])],
    );
    if (f == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final j = jsonDecode(utf8.decode(await f.readAsBytes(), allowMalformed: true));
      if (j is! Map<String, dynamic> || !LegacyImport.looksLike(j)) {
        throw FormatException(
          tr('Diese Datei kommt nicht aus der früheren Buchhaltungs-App.', 'This file is not from the previous bookkeeping app.'),
        );
      }
      final data = LegacyImport.parse(j, existing: s.categories);
      // Liegt die Datei im Ordner der alten App, liegen die Belege meist daneben.
      String? guess;
      if (f.path.isNotEmpty && !Platform.isAndroid) {
        final dir = File(f.path).parent;
        for (final name in ['Belege', 'belege', 'Receipts', 'receipts', 'attachments', 'Anhaenge', 'Anhänge']) {
          if (Directory('${dir.path}${Platform.pathSeparator}$name').existsSync()) {
            guess = '${dir.path}${Platform.pathSeparator}$name';
            break;
          }
        }
      }
      setState(() {
        _data = data;
        _fileName = f.name;
        _receipts = guess;
        _takeBusiness = true;
        _accountId = s.activeAccounts.isEmpty ? 'new' : s.activeAccounts.first.id;
      });
    } catch (e, st) {
      ErrorLog.record(e, st, where: 'Import lesen');
      setState(() => _error = e is FormatException ? e.message : tr('Die Datei liess sich nicht lesen: $e', 'Could not read the file: $e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickReceipts() async {
    final d = await getDirectoryPath(confirmButtonText: tr('Diesen Ordner nehmen', 'Use this folder'));
    if (d != null) setState(() => _receipts = d);
  }

  Future<void> _apply() async {
    final s = ContiScope.read(context);
    final data = _data!;
    setState(() => _busy = true);
    try {
      var accountId = _accountId;
      if (accountId == 'new') {
        final first = data.entries.isEmpty ? DateTime(DateTime.now().year, 1, 1) : data.entries.map((e) => e.date).reduce((a, b) => a.isBefore(b) ? a : b);
        final acc = Account(
          id: newId(),
          name: data.bankName.isEmpty ? tr('Bankkonto', 'Bank account') : data.bankName,
          type: AccountType.bank,
          iban: data.business.iban,
          openingDate: DateTime(first.year, 1, 1),
          order: s.accounts.length,
        );
        await s.saveAccount(acc);
        accountId = acc.id;
      }
      final r = await LegacyImport.apply(s, data, accountId: accountId, receiptsFolder: _receipts, takeBusiness: _takeBusiness);
      setState(() => _result = r);
    } catch (e, st) {
      ErrorLog.record(e, st, where: 'Import übernehmen');
      setState(() => _error = tr('Übernehmen ging nicht: $e', 'Import failed: $e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _finish() {
    if (widget.onDone != null) {
      widget.onDone!();
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Import', 'Import'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
            children: [
              if (_busy) const Padding(padding: EdgeInsets.only(bottom: 12), child: LinearProgressIndicator()),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              if (_result != null)
                _ResultView(result: _result!, onDone: _finish)
              else if (_data == null)
                EmptyState(
                  icon: Icons.file_open_outlined,
                  title: tr('Datendatei wählen', 'Choose data file'),
                  text: tr(
                    'Die frühere App speichert alles in einer .json-Datei. Wähle sie aus, dann zeigt Conti, was übernommen wird.',
                    'The previous app keeps everything in a .json file. Choose it and Conti shows what will be imported.',
                  ),
                  action: GradientButton(label: tr('Datei wählen …', 'Choose file …'), icon: Icons.folder_open, onPressed: _busy ? null : _pick),
                )
              else
                ..._preview(context, _data!),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _preview(BuildContext context, LegacyData d) {
    final s = ContiScope.of(context);
    final c = context.conti;
    final years = d.yearSummary.entries.toList()..sort((a, b) => b.key.compareTo(a.key));
    Widget count(String label, int n) => Chip(label: Text('$label: $n'));
    return [
      SectionCard(
        title: tr('Das kommt dazu', 'What will be added'),
        trailing: Text(_fileName ?? '', style: TextStyle(color: c.muted, fontSize: 13)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final y in years)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    SizedBox(width: 56, child: Text('${y.key}', style: const TextStyle(fontWeight: FontWeight.w600))),
                    Expanded(child: Text(tr('${y.value.$3} Buchungen', '${y.value.$3} entries'))),
                    Text('+${Money.format(y.value.$1)}', style: TextStyle(color: c.plus)),
                    const SizedBox(width: 14),
                    Text('−${Money.format(y.value.$2)}', style: TextStyle(color: c.minus)),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                count(tr('Kunden', 'Clients'), d.clients.length),
                count(tr('Produkte', 'Products'), d.products.length),
                count(tr('Aufträge', 'Orders'), d.orders.length),
                count(tr('Aufgaben', 'Tasks'), d.tasks.length),
                count(tr('Belege', 'Receipts'), d.attachments.length),
              ],
            ),
            if (d.newCategories.isNotEmpty) ...[
              const SizedBox(height: 14),
              CapsLabel(tr('Neue Kategorien', 'New categories')),
              const SizedBox(height: 8),
              Text(d.newCategories.map((x) => x.name).join(' · ')),
            ],
            const SizedBox(height: 10),
            Text(
              tr(
                'Kunden, Produkte, Aufträge und Aufgaben werden jetzt schon übernommen. Ansehen und bearbeiten kannst du sie ab dem nächsten Paket.',
                'Clients, products, orders and tasks are imported now. You can view and edit them from the next package on.',
              ),
              style: TextStyle(color: c.muted, fontSize: 13),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      SectionCard(
        title: tr('Konto', 'Account'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr(
                'Die frühere App kannte keine Konten. Auf welches Konto sollen die Buchungen? Später kannst du einzelne Buchungen umstellen.',
                'The previous app had no accounts. Which account should the entries go to? You can change single entries later.',
              ),
              style: TextStyle(color: c.muted),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _accountId,
              isExpanded: true,
              items: [
                DropdownMenuItem(
                  value: 'new',
                  child: Text(tr('Neues Konto „${d.bankName.isEmpty ? 'Bankkonto' : d.bankName}“', 'New account “${d.bankName.isEmpty ? 'Bank account' : d.bankName}”')),
                ),
                for (final a in s.activeAccounts) DropdownMenuItem(value: a.id, child: Text(a.name)),
              ],
              onChanged: (v) => setState(() => _accountId = v ?? 'new'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      SectionCard(
        title: tr('Belege', 'Receipts'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              Platform.isAndroid
                  ? tr(
                      'Die Belege liegen in einem Ordner der alten App. Übernimm sie am besten am Computer, dort kannst du den Ordner wählen.',
                      'The receipts are in a folder of the old app. Best import them on the computer, where you can choose the folder.',
                    )
                  : tr(
                      'Die Datei enthält nur die Namen der Belege. Wähle den Ordner, in dem die alte App sie abgelegt hat (meist mit Unterordnern wie 2025 und 2026).',
                      'The file only holds the names of the receipts. Choose the folder where the old app stored them (usually with subfolders like 2025 and 2026).',
                    ),
              style: TextStyle(color: c.muted),
            ),
            if (!Platform.isAndroid) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(_receipts ?? tr('Kein Ordner gewählt', 'No folder chosen'), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(onPressed: _pickReceipts, child: Text(tr('Ordner wählen …', 'Choose folder …'))),
                ],
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 14),
      Card(
        child: SwitchListTile(
          title: Text(tr('Mein Geschäft übernehmen', 'Take over my business details')),
          subtitle: Text(
            [
              d.business.displayName,
              [d.business.street, d.business.houseNumber].where((x) => x.isNotEmpty).join(' '),
              if (d.business.iban.isNotEmpty) Iban.pretty(d.business.iban),
              if (d.logo != null) tr('Logo', 'logo'),
              if (d.signature != null) tr('Unterschrift', 'signature'),
            ].where((x) => x.isNotEmpty).join(' · '),
          ),
          value: _takeBusiness,
          onChanged: (v) => setState(() => _takeBusiness = v),
        ),
      ),
      const SizedBox(height: 20),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(onPressed: _busy ? null : _pick, child: Text(tr('Andere Datei', 'Other file'))),
          const SizedBox(width: 8),
          GradientButton(label: tr('Übernehmen', 'Import'), icon: Icons.download_done, onPressed: _busy ? null : _apply),
        ],
      ),
    ];
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView({required this.result, required this.onDone});
  final LegacyImportResult result;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final c = context.conti;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EmptyState(
          icon: Icons.check_circle_outline,
          title: tr('Übernommen', 'Imported'),
          text: tr(
            '${result.entries} Buchungen und ${result.attachmentsFound} Belege sind jetzt in Conti.',
            '${result.entries} entries and ${result.attachmentsFound} receipts are now in Conti.',
          ),
        ),
        if (result.attachmentsMissing.isNotEmpty)
          SectionCard(
            title: tr('Nicht gefundene Belege (${result.attachmentsMissing.length})', 'Receipts not found (${result.attachmentsMissing.length})'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(
                    'Diese Dateien lagen nicht im gewählten Ordner. Du kannst den Import mit dem richtigen Ordner wiederholen, es entsteht nichts doppelt.',
                    'These files were not in the chosen folder. You can repeat the import with the right folder, nothing gets duplicated.',
                  ),
                  style: TextStyle(color: c.muted),
                ),
                const SizedBox(height: 8),
                for (final m in result.attachmentsMissing.take(30)) Text('· $m', style: const TextStyle(fontSize: 13)),
                if (result.attachmentsMissing.length > 30) Text('…'),
              ],
            ),
          ),
        const SizedBox(height: 20),
        Align(alignment: Alignment.centerRight, child: GradientButton(label: tr('Fertig', 'Done'), icon: Icons.check, onPressed: onDone)),
      ],
    );
  }
}
