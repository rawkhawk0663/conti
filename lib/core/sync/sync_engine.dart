import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../app/error_log.dart';
import '../dates.dart';
import '../store/data_store.dart';
import '../store/json_file.dart';
import 'dropbox_api.dart';

/// Ergebnis eines Abgleichs.
class SyncReport {
  int uploaded = 0;
  int downloaded = 0;

  /// Hat sich auf diesem Gerät etwas geändert (dann neu einlesen)?
  bool changedLocal = false;

  /// Dateien, die diesmal nicht gingen (kommen beim nächsten Mal wieder dran).
  final List<String> failed = [];
  Object? firstError;
}

/// Gleicht den Datenordner mit dem Cloud-Dienst ab.
///
/// Weil in Conti nie etwas wirklich gelöscht wird (Grabsteine), ist der
/// Abgleich einfach und sicher:
/// - **JSON-Dateien** werden immer zusammengeführt: pro Eintrag (ID) gewinnt
///   die jüngere Änderung (`updatedAt`). `geschaeft.json` gewinnt als Ganzes.
///   Das Ergebnis landet auf beiden Seiten.
/// - **Belege und Bilder** ändern sich nie: Was auf einer Seite fehlt, wird
///   kopiert. Gelöscht wird nichts, weder hier noch beim Dienst.
///
/// Damit nicht jedes Mal alles geladen wird, merkt sich das Gerät pro Datei
/// das Kennzeichen beim Dienst (`rev`) und eine Prüfsumme des eigenen Inhalts
/// (`hash`) vom letzten Abgleich ([stateFile]).
class SyncEngine {
  SyncEngine({required this.api, required this.store, required this.stateFile});

  final CloudApi api;
  final DataStore store;
  final JsonFile stateFile;

  Future<SyncReport> run() async {
    final report = SyncReport();
    final state = await stateFile.read();
    final files = <String, Map<String, dynamic>>{
      for (final e in ((state['files'] as Map?) ?? const {}).entries)
        if (e.value is Map) e.key as String: Map<String, dynamic>.from(e.value as Map),
    };
    final remote = {
      for (final e in await api.listAll())
        if (isSyncedPath(e.path)) e.path: e,
    };
    final local = await _localFiles();
    // Zuerst die kleinen Daten, dann Belege. Die Markierung zuletzt, damit
    // ein anderes Gerät erst „Daten vorhanden“ sieht, wenn alles da ist.
    final all = {...remote.keys, ...local}.toList()
      ..sort((a, b) {
        int rank(String x) => x == DataStore.marker ? 2 : (x.endsWith('.json') ? 0 : 1);
        final r = rank(a).compareTo(rank(b));
        return r != 0 ? r : a.compareTo(b);
      });
    for (final rel in all) {
      try {
        if (rel.endsWith('.json')) {
          await _syncJson(rel, remote[rel], local.contains(rel), files, report);
        } else {
          await _syncFile(rel, remote[rel], local.contains(rel), files, report);
        }
      } catch (e, st) {
        report.failed.add(rel);
        report.firstError ??= e;
        ErrorLog.record(e, st, where: 'Abgleich $rel');
      }
    }
    await stateFile.write({'format': 'conti-abgleich', 'version': 1, 'files': files});
    return report;
  }

  /// Welche Dateien gehören zum Abgleich? Keine halben Zwischendateien.
  static bool isSyncedPath(String rel) {
    if (rel.endsWith('.tmp')) return false;
    final parts = rel.split('/');
    return !parts.any((x) => x.isEmpty || x.startsWith('.'));
  }

  Future<Set<String>> _localFiles() async {
    final dir = Directory(store.root);
    if (!await dir.exists()) return {};
    final out = <String>{};
    await for (final f in dir.list(recursive: true, followLinks: false)) {
      if (f is! File) continue;
      final rel = p.relative(f.path, from: store.root).replaceAll('\\', '/');
      if (isSyncedPath(rel)) out.add(rel);
    }
    return out;
  }

  static String _hash(List<int> bytes) => sha1.convert(bytes).toString();

  Future<List<int>?> _readLocal(String rel) async {
    final f = File(store.pathOf(rel));
    return await f.exists() ? await f.readAsBytes() : null;
  }

  Future<void> _syncJson(
    String rel,
    RemoteEntry? remote,
    bool hasLocal,
    Map<String, Map<String, dynamic>> files,
    SyncReport report,
  ) async {
    final last = files[rel];
    if (remote == null) {
      // Nur hier: hochladen.
      final bytes = await _readLocal(rel);
      if (bytes == null) return;
      final up = await api.upload(rel, bytes);
      files[rel] = {'rev': up.rev, 'hash': _hash(bytes)};
      report.uploaded++;
      return;
    }
    if (last != null && last['rev'] == remote.rev && hasLocal) {
      // Beim Dienst unverändert seit dem letzten Mal.
      final bytes = await _readLocal(rel);
      if (bytes == null) return;
      final h = _hash(bytes);
      if (h != last['hash']) {
        final up = await api.upload(rel, bytes);
        files[rel] = {'rev': up.rev, 'hash': h};
        report.uploaded++;
      }
      return;
    }
    // Beim Dienst geändert (oder noch nie gesehen): holen und zusammenführen.
    final remoteBytes = await api.download(remote);
    report.downloaded++;
    final remoteJson = _decode(remoteBytes);
    late List<int> merged;
    await store.withLock(() async {
      final cur = await _readLocal(rel);
      final curJson = cur == null ? null : _decode(cur);
      if (remoteJson == null) {
        // Unlesbar beim Dienst: die eigene Fassung gilt.
        merged = cur ?? remoteBytes;
        return;
      }
      final m = curJson == null ? remoteJson : mergeJson(rel, curJson, remoteJson);
      merged = _encode(m);
      if (cur == null || _canonical(curJson) != _canonical(m)) {
        await store.writeBytesUnlocked(rel, merged);
        report.changedLocal = true;
      }
    });
    var rev = remote.rev;
    if (remoteJson == null || _canonical(_decode(merged)) != _canonical(remoteJson)) {
      rev = (await api.upload(rel, merged)).rev;
      report.uploaded++;
    }
    files[rel] = {'rev': rev, 'hash': _hash(merged)};
  }

  Future<void> _syncFile(
    String rel,
    RemoteEntry? remote,
    bool hasLocal,
    Map<String, Map<String, dynamic>> files,
    SyncReport report,
  ) async {
    if (remote != null && !hasLocal) {
      await store.putFile(rel, await api.download(remote));
      report.downloaded++;
      report.changedLocal = true;
      files[rel] = {'rev': remote.rev};
    } else if (remote == null && hasLocal) {
      final bytes = await _readLocal(rel);
      if (bytes == null) return;
      final up = await api.upload(rel, bytes);
      report.uploaded++;
      files[rel] = {'rev': up.rev};
    } else if (remote != null) {
      files[rel] = {'rev': remote.rev};
    }
  }

  static Map<String, dynamic>? _decode(List<int> bytes) {
    try {
      final j = jsonDecode(utf8.decode(bytes));
      return j is Map<String, dynamic> ? j : null;
    } catch (_) {
      return null;
    }
  }

  static List<int> _encode(Map<String, dynamic> j) => utf8.encode(const JsonEncoder.withIndent(' ').convert(j));

  static String _canonical(Object? j) => jsonEncode(j);

  /// Zwei Fassungen einer Datei zusammenführen. [local] gewinnt bei Gleichstand.
  static Map<String, dynamic> mergeJson(String rel, Map<String, dynamic> local, Map<String, dynamic> remote) {
    if (rel == 'geschaeft.json') {
      final l = Day.parseStamp(local['updatedAt'] as String?);
      final r = Day.parseStamp(remote['updatedAt'] as String?);
      return r.isAfter(l) ? remote : local;
    }
    for (final key in const ['entries', 'items']) {
      if (local[key] is List || remote[key] is List) {
        final merged = _mergeRecords(local[key], remote[key]);
        if (key == 'entries') {
          merged.sort((a, b) {
            final d = '${a['date']}'.compareTo('${b['date']}');
            return d != 0 ? d : '${a['id']}'.compareTo('${b['id']}');
          });
        }
        return {...remote, ...local, key: merged};
      }
    }
    // Sonst (z. B. die Markierung): die eigene Fassung.
    return local;
  }

  static List<Map<String, dynamic>> _mergeRecords(Object? local, Object? remote) {
    final out = <String, Map<String, dynamic>>{};
    final order = <String>[];
    void add(Object? list, {required bool mine}) {
      if (list is! List) return;
      for (final x in list) {
        if (x is! Map) continue;
        final m = Map<String, dynamic>.from(x);
        final id = '${m['id']}';
        final cur = out[id];
        if (cur == null) {
          out[id] = m;
          order.add(id);
        } else if (!mine) {
          final a = Day.parseStamp(cur['updatedAt'] as String?);
          final b = Day.parseStamp(m['updatedAt'] as String?);
          if (b.isAfter(a)) out[id] = m;
        }
      }
    }

    add(local, mine: true);
    add(remote, mine: false);
    return [for (final id in order) out[id]!];
  }
}
