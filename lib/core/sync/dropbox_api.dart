import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../app/l10n.dart';
import 'cloud_auth.dart';

/// Eine Datei beim Cloud-Dienst.
class RemoteEntry {
  const RemoteEntry({required this.path, required this.rev});

  /// Relativer Pfad ('/' als Trenner), z. B. `buchungen/2026.json`.
  final String path;

  /// Kennzeichen des Inhalts: ändert sich bei jeder Änderung der Datei.
  final String rev;
}

/// Was ein Cloud-Dienst können muss (Dropbox, in Tests ein Speicher im
/// Arbeitsspeicher).
abstract class CloudApi {
  Future<List<RemoteEntry>> listAll();
  Future<List<int>> download(RemoteEntry e);
  Future<RemoteEntry> upload(String path, List<int> bytes);
}

class CloudHttpException implements Exception {
  CloudHttpException(this.status, this.body);
  final int status;
  final String body;
  @override
  String toString() => tr('Fehler bei Dropbox ($status): $body', 'Dropbox error ($status): $body');
}

/// Gemeinsame Anfragen: Zugangsschlüssel, nochmals versuchen bei
/// „zu viele Anfragen“ und Serverfehlern, neuer Schlüssel bei 401.
class _Http {
  _Http(this.auth);
  final OAuthClient auth;
  final _client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  bool _lastWas401 = false;

  Future<(int, List<int>)> send(String method, Uri url, {Map<String, String> headers = const {}, List<int>? body}) async {
    for (var attempt = 0; ; attempt++) {
      final token = await auth.accessToken(force: attempt > 0 && _lastWas401);
      final req = await _client.openUrl(method, url);
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      headers.forEach(req.headers.set);
      if (body != null) {
        req.contentLength = body.length;
        req.add(body);
      }
      final res = await req.close().timeout(const Duration(minutes: 5));
      final bytes = <int>[];
      await for (final c in res) {
        bytes.addAll(c);
      }
      _lastWas401 = res.statusCode == 401;
      final retry = res.statusCode == 401 || res.statusCode == 429 || res.statusCode >= 500;
      if (retry && attempt < 3) {
        final after = int.tryParse(res.headers.value('retry-after') ?? '');
        await Future<void>.delayed(Duration(seconds: after ?? (1 << attempt)));
        continue;
      }
      return (res.statusCode, bytes);
    }
  }

  Future<dynamic> json(String method, Uri url, {Object? body}) async {
    final (status, bytes) = await send(
      method,
      url,
      headers: {if (body != null) 'Content-Type': 'application/json; charset=utf-8'},
      body: body == null ? null : utf8.encode(jsonEncode(body)),
    );
    final text = utf8.decode(bytes, allowMalformed: true);
    if (status < 200 || status >= 300) throw CloudHttpException(status, text);
    return text.isEmpty ? null : jsonDecode(text);
  }
}

/// Dropbox: Conti hat einen eigenen Ordner (`Apps/<Name der App>`) und sieht
/// nur diesen.
class DropboxApi implements CloudApi {
  DropboxApi(OAuthClient auth) : _http = _Http(auth);
  final _Http _http;

  static const _api = 'https://api.dropboxapi.com/2';
  static const _content = 'https://content.dropboxapi.com/2';

  /// Dropbox erwartet die Angaben im Kopf der Anfrage; dort sind nur
  /// ASCII-Zeichen erlaubt (Umlaute als \uXXXX).
  static String headerJson(Object value) {
    final s = jsonEncode(value);
    final b = StringBuffer();
    for (final c in s.codeUnits) {
      b.write(c < 0x80 ? String.fromCharCode(c) : '\\u${c.toRadixString(16).padLeft(4, '0')}');
    }
    return b.toString();
  }

  @override
  Future<List<RemoteEntry>> listAll() async {
    final out = <RemoteEntry>[];
    dynamic page;
    try {
      page = await _http.json(
        'POST',
        Uri.parse('$_api/files/list_folder'),
        body: {'path': '', 'recursive': true, 'include_deleted': false, 'limit': 2000},
      );
    } on CloudHttpException catch (e) {
      if (e.status == 409 && e.body.contains('not_found')) return out; // noch leer
      rethrow;
    }
    while (true) {
      for (final e in (page['entries'] as List).cast<Map<String, dynamic>>()) {
        if (e['.tag'] != 'file') continue;
        final display = (e['path_display'] as String).replaceFirst(RegExp('^/'), '');
        out.add(RemoteEntry(path: display, rev: e['rev'] as String? ?? e['content_hash'] as String? ?? ''));
      }
      if (page['has_more'] != true) break;
      page = await _http.json('POST', Uri.parse('$_api/files/list_folder/continue'), body: {'cursor': page['cursor']});
    }
    return out;
  }

  @override
  Future<List<int>> download(RemoteEntry e) async {
    final (status, bytes) = await _http.send(
      'POST',
      Uri.parse('$_content/files/download'),
      headers: {'Dropbox-API-Arg': headerJson({'path': '/${e.path}'})},
    );
    if (status != 200) throw CloudHttpException(status, utf8.decode(bytes, allowMalformed: true));
    return bytes;
  }

  @override
  Future<RemoteEntry> upload(String path, List<int> bytes) async {
    final (status, body) = await _http.send(
      'POST',
      Uri.parse('$_content/files/upload'),
      headers: {
        'Content-Type': 'application/octet-stream',
        'Dropbox-API-Arg': headerJson({'path': '/$path', 'mode': 'overwrite', 'mute': true}),
      },
      body: bytes,
    );
    final text = utf8.decode(body, allowMalformed: true);
    if (status != 200) throw CloudHttpException(status, text);
    final j = jsonDecode(text) as Map<String, dynamic>;
    return RemoteEntry(path: path, rev: j['rev'] as String? ?? '');
  }

  /// Name des Kontos (für die Anzeige).
  Future<String> accountName() async {
    // Ohne Angaben erwartet Dropbox den Text „null“.
    final (status, bytes) = await _http.send(
      'POST',
      Uri.parse('$_api/users/get_current_account'),
      headers: {'Content-Type': 'application/json'},
      body: utf8.encode('null'),
    );
    final text = utf8.decode(bytes, allowMalformed: true);
    if (status != 200) throw CloudHttpException(status, text);
    final j = jsonDecode(text) as Map<String, dynamic>;
    final name = (j['name'] as Map?)?['display_name'] as String?;
    final email = j['email'] as String?;
    return [?name, if (email != null) '($email)'].join(' ');
  }
}
