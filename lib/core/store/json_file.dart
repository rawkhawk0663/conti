import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../app/error_log.dart';

/// Eine JSON-Datei. Geschrieben wird erst in eine Zwischendatei, die dann
/// umbenannt wird. So bleibt bei einem Absturz nie eine halbe Datei zurück.
class JsonFile {
  JsonFile(this.path);

  final String path;

  Future<Map<String, dynamic>> read() async {
    try {
      final f = File(path);
      if (!await f.exists()) return {};
      final j = jsonDecode(await f.readAsString());
      return j is Map<String, dynamic> ? j : {};
    } catch (err, st) {
      ErrorLog.record(err, st, where: 'Lesen ${p.basename(path)}');
      return {};
    }
  }

  Future<void> write(Map<String, dynamic> json) async {
    await File(path).parent.create(recursive: true);
    final tmp = File('$path.tmp');
    await tmp.writeAsString(const JsonEncoder.withIndent(' ').convert(json), flush: true);
    await tmp.rename(path);
  }
}
