import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../../app/error_log.dart';
import '../../app/l10n.dart';
import '../conti_state.dart';
import '../store/json_file.dart';
import 'cloud_auth.dart';
import 'dropbox_api.dart';
import 'sync_engine.dart';

enum SyncStatus { off, idle, syncing, error }

/// Steuert den Abgleich mit Dropbox: wann er läuft und was angezeigt wird.
///
/// Abgeglichen wird beim Start, alle zwei Minuten, ein paar Sekunden nach
/// jeder Änderung, wenn die App wieder in den Vordergrund kommt, und auf
/// Knopfdruck.
class SyncController extends ChangeNotifier with WidgetsBindingObserver {
  SyncController(this.state, {CloudApi Function(OAuthClient auth)? apiFactory})
    : _apiFactory = apiFactory ?? DropboxApi.new;

  final ContiState state;
  final CloudApi Function(OAuthClient auth) _apiFactory;

  SyncStatus _status = SyncStatus.off;
  SyncStatus get status => _status;
  String? error;
  SyncReport? lastReport;
  Timer? _timer;
  Timer? _soon;
  Future<void>? _running;
  bool _again = false;
  OAuthClient? _pending;

  /// Ist Dropbox in dieser Version eingerichtet (Schlüssel beim Bauen gesetzt)?
  bool get available => dropboxAppKey.isNotEmpty;

  bool get connected => state.device.dropboxToken != null;

  String? get account => state.device.dropboxAccount;

  DateTime? get lastSync => DateTime.tryParse(state.device.lastSync ?? '')?.toLocal();

  /// Unter Android geht die Rückmeldung an das Gerät nicht, dort mit Code.
  static bool get prefersCode => Platform.isAndroid || Platform.isIOS;

  JsonFile get _stateFile => JsonFile(p.join(state.supportDir, 'abgleich_dropbox.json'));

  OAuthClient _auth() => OAuthClient(
    refreshToken: state.device.dropboxToken,
    onRefreshToken: (t) => state.device.setDropbox(token: t, account: account),
  );

  void start() {
    WidgetsBinding.instance.addObserver(this);
    state.onLocalChange = _changedSoon;
    if (connected) _schedule();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _soon?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && connected) syncNow();
  }

  void _schedule() {
    _status = SyncStatus.idle;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 2), (_) => syncNow());
    Future<void>.delayed(const Duration(seconds: 2), syncNow);
    notifyListeners();
  }

  void _changedSoon() {
    if (!connected) return;
    _soon?.cancel();
    _soon = Timer(const Duration(seconds: 4), syncNow);
  }

  /// Jetzt abgleichen. Läuft schon einer, kommt danach noch einer.
  Future<void> syncNow() {
    if (!connected) return Future.value();
    if (_running != null) {
      _again = true;
      return _running!;
    }
    final f = _run();
    _running = f;
    return f.whenComplete(() {
      _running = null;
      if (_again) {
        _again = false;
        syncNow();
      }
    });
  }

  Future<void> _run() async {
    _status = SyncStatus.syncing;
    notifyListeners();
    try {
      final engine = SyncEngine(api: _apiFactory(_auth()), store: state.store, stateFile: _stateFile);
      final r = await engine.run();
      lastReport = r;
      if (r.changedLocal) await state.reload();
      if (r.failed.isEmpty) {
        error = null;
        _status = SyncStatus.idle;
        await state.device.setLastSync(DateTime.now().toUtc().toIso8601String());
      } else {
        _status = SyncStatus.error;
        error = tr(
          '${r.failed.length} Dateien gingen nicht: ${r.firstError}',
          '${r.failed.length} files failed: ${r.firstError}',
        );
      }
    } catch (e, st) {
      ErrorLog.record(e, st, where: 'Abgleich');
      _status = SyncStatus.error;
      error = e is SocketException || e is TimeoutException || e is HandshakeException
          ? tr('Keine Verbindung zu Dropbox. Bist du online?', 'No connection to Dropbox. Are you online?')
          : '$e';
    }
    notifyListeners();
  }

  // ---------- Verbinden ----------

  /// Windows/Linux: Anmeldung im Browser, Conti bekommt die Antwort selbst.
  Future<void> connectWithBrowser(Future<void> Function(Uri url) openBrowser) async {
    final auth = OAuthClient();
    await auth.signIn(openBrowser);
    await _connected(auth);
  }

  /// Anmeldung mit Code, Schritt 1: Adresse zum Öffnen im Browser.
  Uri beginCodeSignIn() {
    final auth = OAuthClient();
    _pending = auth;
    return auth.codeSignInUrl();
  }

  /// Schritt 2: den von Dropbox gezeigten Code einlösen.
  Future<void> finishCodeSignIn(String code) async {
    final auth = _pending;
    if (auth == null) {
      throw CloudAuthException(tr('Bitte zuerst „Bei Dropbox anmelden“ tippen.', 'Please tap “Sign in to Dropbox” first.'));
    }
    await auth.finishCodeSignIn(code);
    _pending = null;
    await _connected(auth);
  }

  Future<void> _connected(OAuthClient auth) async {
    String? name;
    try {
      final api = _apiFactory(auth);
      if (api is DropboxApi) name = await api.accountName();
    } catch (_) {}
    // Neues Ziel: Stand vom letzten Mal vergessen (es wird nur zusammengeführt,
    // also geht dabei nie etwas verloren).
    try {
      await File(_stateFile.path).delete();
    } catch (_) {}
    await state.device.setDropbox(token: auth.refreshToken, account: name);
    error = null;
    _schedule();
    await syncNow();
  }

  Future<void> disconnect() async {
    _timer?.cancel();
    _soon?.cancel();
    await state.device.setDropbox(token: null);
    try {
      await File(_stateFile.path).delete();
    } catch (_) {}
    _status = SyncStatus.off;
    error = null;
    notifyListeners();
  }
}

/// Macht den [SyncController] überall verfügbar.
class SyncScope extends InheritedNotifier<SyncController> {
  const SyncScope({super.key, required SyncController sync, required super.child}) : super(notifier: sync);

  static SyncController of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<SyncScope>()!.notifier!;
}
