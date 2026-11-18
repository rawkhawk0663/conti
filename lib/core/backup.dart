import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import 'conti_state.dart';
import 'dates.dart';
import 'store/data_store.dart';

/// Sicherungen als ZIP-Datei mit dem ganzen Datenordner.
///
/// Einspielen löscht nie etwas: Die Sicherung wird mit dem aktuellen Stand
/// zusammengeführt (pro Eintrag gewinnt die jüngere Fassung), Belege kommen
/// dazu, wenn sie fehlen.
class Backup {
  Backup._();

  /// Wie viele automatische Sicherungen aufbewahrt werden.
  static const keepAuto = 14;

  static String autoFolder(ContiState s) => p.join(s.supportDir, 'Sicherungen');

  /// ZIP des Datenordners nach [target] schreiben.
  static Future<File> writeZip(ContiState s, String target) async {
    final root = s.store.root;
    await Isolate.run(() async {
      final enc = ZipFileEncoder();
      enc.create(target);
      final dir = Directory(root);
      if (await dir.exists()) {
        await for (final f in dir.list(recursive: true, followLinks: false)) {
          if (f is! File || f.path.endsWith('.tmp')) continue;
          await enc.addFile(f, p.relative(f.path, from: root).replaceAll('\\', '/'));
        }
      }
      await enc.close();
    });
    return File(target);
  }

  static String fileName([DateTime? t]) {
    final n = t ?? DateTime.now();
    final time = '${n.hour.toString().padLeft(2, '0')}${n.minute.toString().padLeft(2, '0')}';
    return 'Conti-Sicherung ${Day.toKey(n)} $time.zip';
  }

  /// Einmal pro Tag beim Start: Sicherung in den Ordner „Sicherungen“,
  /// ältere als die letzten [keepAuto] werden weggeräumt.
  static Future<void> autoBackup(ContiState s) async {
    final today = Day.toKey(DateTime.now());
    if (s.device.lastAutoBackup == today || !s.dataInitialized) return;
    final dir = Directory(autoFolder(s));
    await dir.create(recursive: true);
    await writeZip(s, p.join(dir.path, fileName()));
    await s.device.setLastAutoBackup(today);
    final all = await dir.list().where((f) => f is File && f.path.endsWith('.zip')).cast<File>().toList();
    all.sort((a, b) => b.path.compareTo(a.path));
    for (final old in all.skip(keepAuto)) {
      try {
        await old.delete();
      } catch (_) {}
    }
  }

  static Future<List<File>> autoBackups(ContiState s) async {
    final dir = Directory(autoFolder(s));
    if (!await dir.exists()) return [];
    final all = await dir.list().where((f) => f is File && f.path.endsWith('.zip')).cast<File>().toList();
    all.sort((a, b) => b.path.compareTo(a.path));
    return all;
  }

  /// Sicherung einspielen (zusammenführen). Gibt die Zahl der Buchungen in
  /// der Sicherung zurück. Wirft, wenn die Datei keine Conti-Sicherung ist.
  static Future<int> restore(ContiState s, String zipPath) async {
    final tmp = await Directory.systemTemp.createTemp('conti-restore-');
    try {
      final out = tmp.path;
      await Isolate.run(() => extractFileToDisk(zipPath, out));
      if (!await File(p.join(out, DataStore.marker)).exists()) {
        throw const FormatException('Das ist keine Conti-Sicherung.');
      }
      final snap = await DataStore(out).load();
      // Belege und Bilder, die fehlen, dazulegen (vorhandene nie überschreiben).
      for (final sub in ['belege', 'bilder']) {
        final dir = Directory(p.join(out, sub));
        if (!await dir.exists()) continue;
        await for (final f in dir.list(recursive: true)) {
          if (f is! File) continue;
          final rel = p.relative(f.path, from: out);
          final target = File(s.dataPath(rel));
          if (await target.exists()) continue;
          await target.parent.create(recursive: true);
          await f.copy(target.path);
        }
      }
      await s.mergeIn(
        entries: snap.entries,
        accounts: snap.accounts,
        categories: snap.categories,
        clients: snap.clients,
        products: snap.products,
        orders: snap.orders,
        tasks: snap.tasks,
        business: snap.business.isEmpty ? null : snap.business,
      );
      return snap.entries.where((e) => !e.deleted).length;
    } finally {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    }
  }
}
