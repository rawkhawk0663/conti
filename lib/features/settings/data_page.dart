import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../../app/error_log.dart';
import '../../app/l10n.dart';
import '../../app/theme.dart';
import '../../core/backup.dart';
import '../../core/conti_state.dart';
import '../../widgets/visuals.dart';
import '../import/import_screen.dart';

/// Daten & Sicherung: Import, Sicherungen, Datenordner.
class DataPage extends StatefulWidget {
  const DataPage({super.key});

  @override
  State<DataPage> createState() => _DataPageState();
}

class _DataPageState extends State<DataPage> {
  bool _busy = false;
  List<File> _auto = [];

  @override
  void initState() {
    super.initState();
    _loadAuto();
  }

  Future<void> _loadAuto() async {
    final list = await Backup.autoBackups(ContiScope.read(context));
    if (mounted) setState(() => _auto = list);
  }

  void _say(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), persist: false));

  Future<void> _run(Future<void> Function() job) async {
    setState(() => _busy = true);
    try {
      await job();
    } catch (e, st) {
      ErrorLog.record(e, st, where: 'Daten & Sicherung');
      if (mounted) _say(tr('Das ging nicht: $e', 'That didn’t work: $e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() => _run(() async {
    final s = ContiScope.read(context);
    final name = Backup.fileName();
    if (Platform.isAndroid || Platform.isIOS) {
      // Auf dem Handy: in den Ordner der automatischen Sicherungen.
      final dir = Backup.autoFolder(s);
      await Directory(dir).create(recursive: true);
      await Backup.writeZip(s, p.join(dir, name));
      await _loadAuto();
      _say(tr('Sicherung erstellt.', 'Backup created.'));
      return;
    }
    final loc = await getSaveLocation(
      suggestedName: name,
      acceptedTypeGroups: const [XTypeGroup(label: 'ZIP', extensions: ['zip'])],
    );
    if (loc == null) return;
    await Backup.writeZip(s, loc.path.endsWith('.zip') ? loc.path : '${loc.path}.zip');
    _say(tr('Sicherung gespeichert.', 'Backup saved.'));
  });

  Future<void> _restore(String? path) => _run(() async {
    final s = ContiScope.read(context);
    var file = path;
    if (file == null) {
      final f = await openFile(acceptedTypeGroups: const [XTypeGroup(label: 'ZIP', extensions: ['zip'], mimeTypes: ['application/zip'])]);
      if (f == null) return;
      file = f.path;
    }
    final n = await Backup.restore(s, file);
    _say(tr('Sicherung eingespielt ($n Buchungen darin).', 'Backup restored ($n entries in it).'));
  });

  Future<void> _openFolder() async {
    final s = ContiScope.read(context);
    final dir = s.store.root;
    await Directory(dir).create(recursive: true);
    try {
      if (Platform.isWindows) {
        await Process.run('explorer.exe', [dir]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [dir]);
      } else {
        await launchUrl(Uri.directory(dir));
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final s = ContiScope.of(context);
    final c = context.conti;
    final desktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Daten & Sicherung', 'Data & backup'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
            children: [
              if (_busy) const Padding(padding: EdgeInsets.only(bottom: 12), child: LinearProgressIndicator()),
              SectionCard(
                title: tr('Aus der alten Buchhaltung übernehmen', 'Bring over from your old bookkeeping app'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(
                        'Wähle die Datendatei (.json) der früheren App. Vor dem Übernehmen siehst du, was hinzukommt. Ein zweiter Import erzeugt nichts doppelt.',
                        'Choose the data file (.json) of your previous app. Before anything is added you see a preview. Importing twice creates no duplicates.',
                      ),
                      style: TextStyle(color: c.muted),
                    ),
                    const SizedBox(height: 12),
                    GradientButton(
                      label: tr('Datei wählen …', 'Choose file …'),
                      icon: Icons.file_open_outlined,
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ImportScreen())),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SectionCard(
                title: tr('Sicherung', 'Backup'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(
                        'Eine Sicherung enthält alle Buchungen, Belege und Einstellungen als ZIP-Datei. Einspielen löscht nie etwas, es kommt nur dazu.',
                        'A backup holds all entries, receipts and settings as a ZIP file. Restoring never deletes anything, it only adds.',
                      ),
                      style: TextStyle(color: c.muted),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _export,
                          icon: const Icon(Icons.save_alt),
                          label: Text(desktop ? tr('Sicherung speichern …', 'Save backup …') : tr('Sicherung erstellen', 'Create backup')),
                        ),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : () => _restore(null),
                          icon: const Icon(Icons.restore),
                          label: Text(tr('Sicherung einspielen …', 'Restore backup …')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SectionCard(
                title: tr('Automatische Sicherungen', 'Automatic backups'),
                padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        tr(
                          'Einmal am Tag beim Start, die letzten ${Backup.keepAuto} bleiben.',
                          'Once a day at start-up, the last ${Backup.keepAuto} are kept.',
                        ),
                        style: TextStyle(color: c.muted),
                      ),
                    ),
                    for (final f in _auto.take(6))
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.history),
                        title: Text(p.basenameWithoutExtension(f.path).replaceFirst('Conti-Sicherung ', '')),
                        trailing: TextButton(
                          onPressed: _busy ? null : () => _restore(f.path),
                          child: Text(tr('Einspielen', 'Restore')),
                        ),
                      ),
                    if (_auto.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(tr('Noch keine.', 'None yet.')),
                      ),
                  ],
                ),
              ),
              if (desktop) ...[
                const SizedBox(height: 14),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.folder_open_outlined),
                    title: Text(tr('Datenordner öffnen', 'Open data folder')),
                    subtitle: Text(s.store.root, maxLines: 2, overflow: TextOverflow.ellipsis),
                    onTap: _openFolder,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
