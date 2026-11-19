import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

import '../../app/l10n.dart';

/// Schlüssel der Dropbox-App. Er wird beim Bauen eingesetzt (Geheimnis
/// `DROPBOX_APP_KEY` im GitHub-Projekt) und steckt dann in der App. Bei Apps
/// auf dem Gerät ist das so vorgesehen, ein Passwort ist er nicht.
const dropboxAppKey = String.fromEnvironment('DROPBOX_APP_KEY');

/// Fester Anschluss für die Rückmeldung nach der Anmeldung im Browser
/// (`http://localhost:53682/` muss in der Dropbox-App eingetragen sein).
const oauthPort = 53682;

class CloudAuthException implements Exception {
  CloudAuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Anmeldung bei Dropbox (OAuth mit PKCE) und Verwaltung der Zugangsschlüssel.
/// Der langlebige Schlüssel ([refreshToken]) wird auf dem Gerät gespeichert,
/// der kurzlebige nur im Speicher gehalten.
///
/// Zwei Wege:
/// - [signIn]: Der Browser meldet sich nach der Anmeldung bei einem kleinen
///   Empfänger auf diesem Gerät zurück (Windows, Linux).
/// - [codeSignInUrl] + [finishCodeSignIn]: Dropbox zeigt nach der Anmeldung
///   einen Code, den man in Conti einfügt (Android, und als Ersatz überall).
class OAuthClient {
  OAuthClient({this.refreshToken, this.onRefreshToken});

  static const authorizeUrl = 'https://www.dropbox.com/oauth2/authorize';
  static const tokenUrl = 'https://api.dropboxapi.com/oauth2/token';
  static const redirectUri = 'http://localhost:$oauthPort/';

  String get clientId => dropboxAppKey;

  String? refreshToken;

  /// Wird aufgerufen, wenn Dropbox einen neuen langlebigen Schlüssel gibt.
  final Future<void> Function(String token)? onRefreshToken;

  String? _access;
  DateTime _accessUntil = DateTime(2000);
  String? _codeVerifier;

  static String _randomUrlSafe(int bytes) {
    final r = math.Random.secure();
    return base64Url.encode(List<int>.generate(bytes, (_) => r.nextInt(256))).replaceAll('=', '');
  }

  static String _challenge(String verifier) =>
      base64Url.encode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');

  Uri _authorize({required String challenge, String? state, String? redirect}) => Uri.parse(authorizeUrl).replace(
    queryParameters: {
      'client_id': clientId,
      'response_type': 'code',
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      'token_access_type': 'offline',
      'redirect_uri': ?redirect,
      'state': ?state,
    },
  );

  /// Anmeldung im Browser mit Rückmeldung an dieses Gerät. [openBrowser]
  /// öffnet die Adresse. [cancel] bricht ab.
  Future<void> signIn(Future<void> Function(Uri url) openBrowser, {Future<void>? cancel}) async {
    final verifier = _randomUrlSafe(48);
    final state = _randomUrlSafe(16);
    final url = _authorize(challenge: _challenge(verifier), state: state, redirect: redirectUri);

    final servers = <HttpServer>[];
    for (final address in [InternetAddress.loopbackIPv4, InternetAddress.loopbackIPv6]) {
      try {
        servers.add(await HttpServer.bind(address, oauthPort));
      } catch (_) {}
    }
    if (servers.isEmpty) {
      throw CloudAuthException(
        tr(
          'Der Anschluss $oauthPort ist belegt. Bitte Conti neu starten oder „Mit Code verbinden“ wählen.',
          'Port $oauthPort is in use. Please restart Conti or choose “Connect with a code”.',
        ),
      );
    }
    final done = Completer<String>();
    for (final server in servers) {
      server.listen((req) async {
        final q = req.uri.queryParameters;
        final ok = q['code'] != null && q['state'] == state;
        req.response.headers.contentType = ContentType.html;
        req.response.write(_page(ok));
        await req.response.close();
        if (done.isCompleted) return;
        if (ok) {
          done.complete(q['code']);
        } else if (q.containsKey('error') || q.containsKey('code')) {
          done.completeError(
            CloudAuthException(
              tr(
                'Die Anmeldung wurde abgebrochen (${q['error'] ?? 'falsche Antwort'}).',
                'Sign-in was cancelled (${q['error'] ?? 'wrong answer'}).',
              ),
            ),
          );
        }
      });
    }
    try {
      await openBrowser(url);
      final code =
          await Future.any([
            done.future,
            if (cancel != null) cancel.then<String>((_) => throw CloudAuthException(tr('Abgebrochen.', 'Cancelled.'))),
          ]).timeout(
            const Duration(minutes: 10),
            onTimeout: () => throw CloudAuthException(tr('Zeit abgelaufen.', 'Timed out.')),
          );
      await _token({
        'grant_type': 'authorization_code',
        'code': code,
        'code_verifier': verifier,
        'redirect_uri': redirectUri,
      });
    } finally {
      for (final s in servers) {
        await s.close(force: true);
      }
    }
    _requireRefresh();
  }

  /// Adresse für die Anmeldung mit Code (ohne Rückmeldung). Danach zeigt
  /// Dropbox einen Code, der mit [finishCodeSignIn] eingelöst wird.
  Uri codeSignInUrl() {
    final verifier = _randomUrlSafe(48);
    _codeVerifier = verifier;
    return _authorize(challenge: _challenge(verifier));
  }

  Future<void> finishCodeSignIn(String code) async {
    final verifier = _codeVerifier;
    if (verifier == null) {
      throw CloudAuthException(tr('Bitte zuerst „Bei Dropbox anmelden“ tippen.', 'Please tap “Sign in to Dropbox” first.'));
    }
    final c = code.trim();
    if (c.isEmpty) throw CloudAuthException(tr('Bitte den Code einfügen.', 'Please paste the code.'));
    await _token({'grant_type': 'authorization_code', 'code': c, 'code_verifier': verifier});
    _codeVerifier = null;
    _requireRefresh();
  }

  void _requireRefresh() {
    if (refreshToken == null) {
      throw CloudAuthException(tr('Dropbox hat keinen dauerhaften Zugang erteilt.', 'Dropbox did not grant lasting access.'));
    }
  }

  static String _page(bool ok) =>
      '<!doctype html><meta charset="utf-8"><title>Conti</title>'
      '<body style="font-family:sans-serif;background:#0D0E11;color:#F3F4F6;display:grid;place-items:center;height:90vh">'
      '<div style="text-align:center"><h1 style="background:linear-gradient(90deg,#FF7AC6,#9A6BFF);-webkit-background-clip:text;color:transparent">Conti</h1><p>'
      '${ok ? 'Verbunden – du kannst dieses Fenster schliessen.<br>Connected – you can close this window.' : 'Die Anmeldung hat nicht geklappt. / Sign-in failed.'}'
      '</p></div></body>';

  Future<void> _token(Map<String, String> params) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final req = await client.postUrl(Uri.parse(tokenUrl));
      req.headers.contentType = ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
      req.write(Uri(queryParameters: {'client_id': clientId, ...params}).query);
      final res = await req.close().timeout(const Duration(seconds: 30));
      final text = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) {
        final bad = text.contains('invalid_grant');
        throw CloudAuthException(
          bad
              ? tr(
                  'Der Code stimmt nicht oder ist abgelaufen. Bitte nochmals bei Dropbox anmelden.',
                  'The code is wrong or has expired. Please sign in to Dropbox again.',
                )
              : tr('Anmeldung bei Dropbox fehlgeschlagen (${res.statusCode}): $text', 'Dropbox sign-in failed (${res.statusCode}): $text'),
        );
      }
      final j = jsonDecode(text) as Map<String, dynamic>;
      _access = j['access_token'] as String?;
      final expires = (j['expires_in'] as num?)?.toInt() ?? 3600;
      _accessUntil = DateTime.now().add(Duration(seconds: expires - 120));
      final newRefresh = j['refresh_token'] as String?;
      if (newRefresh != null && newRefresh != refreshToken) {
        refreshToken = newRefresh;
        await onRefreshToken?.call(newRefresh);
      }
    } finally {
      client.close(force: true);
    }
  }

  /// Gültiger Zugangsschlüssel (wird bei Bedarf erneuert).
  Future<String> accessToken({bool force = false}) async {
    if (!force && _access != null && DateTime.now().isBefore(_accessUntil)) return _access!;
    final r = refreshToken;
    if (r == null) throw CloudAuthException(tr('Nicht mit Dropbox verbunden.', 'Not connected to Dropbox.'));
    await _token({'grant_type': 'refresh_token', 'refresh_token': r});
    return _access!;
  }
}
