import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'error_log.dart';
import 'l10n.dart';

/// Datei mit dem Standard-Programm öffnen (z. B. ein PDF).
Future<void> openFile(BuildContext context, String path) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final r = await OpenFilex.open(path);
    if (r.type != ResultType.done) throw Exception(r.message);
  } catch (e, st) {
    ErrorLog.record(e, st, where: 'Datei öffnen');
    messenger.showSnackBar(SnackBar(content: Text(tr('Öffnen ging nicht: $e', 'Could not open: $e'))));
  }
}

/// PDF-Daten in eine Zwischendatei schreiben und öffnen (Vorschau).
Future<void> openPdfBytes(BuildContext context, List<int> bytes, String fileName) async {
  final dir = Directory(p.join((await getTemporaryDirectory()).path, 'conti-pdf'));
  await dir.create(recursive: true);
  final path = p.join(dir.path, fileName);
  await File(path).writeAsBytes(bytes, flush: true);
  if (context.mounted) await openFile(context, path);
}

/// Datei teilen (E-Mail, WhatsApp …). Unter Windows das Teilen-Fenster;
/// geht das nicht, wird die Datei im Explorer gezeigt.
Future<void> shareFile(BuildContext context, String path, {String? subject, String? text}) async {
  final messenger = ScaffoldMessenger.of(context);
  final box = context.findRenderObject() as RenderBox?;
  final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
  try {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path, mimeType: 'application/pdf')],
        subject: subject,
        text: text,
        sharePositionOrigin: origin,
      ),
    );
  } catch (e, st) {
    ErrorLog.record(e, st, where: 'Teilen');
    if (Platform.isWindows) {
      await Process.run('explorer.exe', ['/select,', path]);
    } else {
      messenger.showSnackBar(SnackBar(content: Text(tr('Teilen ging nicht: $e', 'Sharing failed: $e'))));
    }
  }
}

/// Kopie der Datei an einem gewählten Ort speichern (Computer).
Future<void> saveCopy(BuildContext context, String path) async {
  final messenger = ScaffoldMessenger.of(context);
  final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
  final loc = await getSaveLocation(
    suggestedName: p.basename(path),
    acceptedTypeGroups: [XTypeGroup(label: ext.toUpperCase(), extensions: [ext])],
  );
  if (loc == null) return;
  try {
    await File(path).copy(loc.path.toLowerCase().endsWith('.$ext') ? loc.path : '${loc.path}.$ext');
    messenger.showSnackBar(SnackBar(content: Text(tr('Gespeichert', 'Saved')), persist: false));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(tr('Speichern ging nicht: $e', 'Saving failed: $e'))));
  }
}

bool get isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;
