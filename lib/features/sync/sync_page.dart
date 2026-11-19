import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/l10n.dart';
import '../../app/window_buttons.dart';
import '../../app/theme.dart';
import '../../core/conti_state.dart';
import '../../core/dates.dart';
import '../../core/sync/sync_controller.dart';
import '../../widgets/visuals.dart';

Future<void> _openBrowser(Uri url) async {
  await launchUrl(url, mode: LaunchMode.externalApplication);
}

/// Abgleich mit Dropbox: verbinden, Stand ansehen, jetzt abgleichen, trennen.
///
/// [join]: aus der Einrichtung geöffnet („schon auf einem anderen Gerät
/// eingerichtet“). Nach dem ersten Abgleich ist die Einrichtung dann fertig.
class SyncPage extends StatefulWidget {
  const SyncPage({super.key, this.join = false});
  final bool join;

  @override
  State<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends State<SyncPage> {
  final _code = TextEditingController();
  bool _busy = false;
  bool _codeMode = SyncController.prefersCode;
  bool _codeStarted = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _guard(Future<void> Function() job) async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await job();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _afterConnect() async {
    if (!widget.join || !mounted) return;
    final s = ContiScope.read(context);
    final sync = SyncScope.of(context);
    await sync.syncNow();
    await s.reload();
    if (s.dataInitialized) {
      await s.finishSetup();
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } else {
      setState(
        () => _info = tr(
          'Verbunden, aber in deiner Dropbox liegen noch keine Conti-Daten. Richte Conti zuerst auf dem anderen Gerät ein und verbinde es dort mit Dropbox. Danach hier „Jetzt abgleichen“ tippen.',
          'Connected, but there is no Conti data in your Dropbox yet. Set up Conti on your other device first and connect it to Dropbox there. Then tap “Sync now” here.',
        ),
      );
    }
  }

  Future<void> _connectBrowser() => _guard(() async {
    await SyncScope.of(context).connectWithBrowser(_openBrowser);
    // Nach der Anmeldung im Browser Conti wieder nach vorne holen.
    await bringWindowToFront();
    await _afterConnect();
  });

  Future<void> _startCode() => _guard(() async {
    final url = SyncScope.of(context).beginCodeSignIn();
    await _openBrowser(url);
    setState(() => _codeStarted = true);
  });

  Future<void> _finishCode() => _guard(() async {
    await SyncScope.of(context).finishCodeSignIn(_code.text);
    _code.clear();
    await _afterConnect();
  });

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    final t = d?.text?.trim();
    if (t != null && t.isNotEmpty) setState(() => _code.text = t);
  }

  Future<void> _disconnect() async {
    final sync = SyncScope.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Von Dropbox trennen?', 'Disconnect from Dropbox?')),
        content: Text(
          tr(
            'Dieses Gerät gleicht dann nicht mehr ab. Die Daten bleiben hier und in deiner Dropbox erhalten.',
            'This device stops syncing. The data stays here and in your Dropbox.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Abbrechen', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Trennen', 'Disconnect'))),
        ],
      ),
    );
    if (ok == true) await sync.disconnect();
  }

  @override
  Widget build(BuildContext context) {
    final sync = SyncScope.of(context);
    final c = context.conti;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Abgleich mit Dropbox', 'Sync with Dropbox'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
            children: [
              if (_busy) const Padding(padding: EdgeInsets.only(bottom: 12), child: LinearProgressIndicator()),
              if (!sync.available)
                SectionCard(
                  child: Text(
                    tr(
                      'In dieser Version ist Dropbox noch nicht eingerichtet (der App-Schlüssel fehlt beim Bauen).',
                      'Dropbox is not set up in this version yet (the app key was missing when it was built).',
                    ),
                  ),
                )
              else if (sync.connected)
                _connectedView(context, sync)
              else
                ..._connectView(context),
              if (_info != null)
                Padding(padding: const EdgeInsets.only(top: 14), child: Text(_info!, style: TextStyle(color: c.muted))),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              const SizedBox(height: 18),
              Text(
                tr(
                  'Conti legt seine Daten in deiner Dropbox im Ordner „Apps“ ab und sieht nur diesen Ordner. Abgeglichen wird beim Start, alle zwei Minuten und kurz nach jeder Änderung. Ohne Netz arbeitest du normal weiter.',
                  'Conti keeps its data in your Dropbox in the “Apps” folder and only sees that folder. It syncs at start-up, every two minutes and shortly after every change. Without a connection you keep working as usual.',
                ),
                style: TextStyle(color: c.muted, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _connectedView(BuildContext context, SyncController sync) {
    final c = context.conti;
    final last = sync.lastSync;
    final syncing = sync.status == SyncStatus.syncing;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _DropboxBadge(colors: sync.status == SyncStatus.error ? c.sun : c.sky),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('Verbunden', 'Connected'), style: Theme.of(context).textTheme.titleMedium),
                    if (sync.account != null) Text(sync.account!, style: TextStyle(color: c.muted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            syncing
                ? tr('Gleicht gerade ab …', 'Syncing …')
                : last == null
                ? tr('Noch nicht abgeglichen.', 'Not synced yet.')
                : tr(
                    'Zuletzt abgeglichen: ${Day.short(last)}, ${last.hour.toString().padLeft(2, '0')}:${last.minute.toString().padLeft(2, '0')}',
                    'Last synced: ${Day.short(last)}, ${last.hour.toString().padLeft(2, '0')}:${last.minute.toString().padLeft(2, '0')}',
                  ),
          ),
          if (sync.lastReport != null && !syncing)
            Text(
              tr(
                '${sync.lastReport!.uploaded} hochgeladen, ${sync.lastReport!.downloaded} geholt',
                '${sync.lastReport!.uploaded} uploaded, ${sync.lastReport!.downloaded} fetched',
              ),
              style: TextStyle(color: c.muted, fontSize: 13),
            ),
          if (sync.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(sync.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              TextButton(onPressed: _busy ? null : _disconnect, child: Text(tr('Trennen', 'Disconnect'))),
              GradientButton(
                label: tr('Jetzt abgleichen', 'Sync now'),
                icon: Icons.sync,
                colors: c.sky,
                onPressed: syncing || _busy ? null : () => _guard(() async {
                  await sync.syncNow();
                  await _afterConnect();
                }),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _connectView(BuildContext context) {
    final c = context.conti;
    Widget step(int n, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(gradient: LinearGradient(colors: c.sky), shape: BoxShape.circle),
            child: Text('$n', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Padding(padding: const EdgeInsets.only(top: 3), child: Text(text))),
        ],
      ),
    );
    return [
      SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _DropboxBadge(colors: c.sky),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    widget.join
                        ? tr('Mit deinen Daten verbinden', 'Connect to your data')
                        : tr('Mit Dropbox verbinden', 'Connect to Dropbox'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (!_codeMode) ...[
              Text(
                tr(
                  'Der Browser öffnet sich. Melde dich bei Dropbox an und erlaube Conti den Zugriff. Danach verbindet sich Conti von selbst.',
                  'Your browser opens. Sign in to Dropbox and allow Conti access. Conti then connects by itself.',
                ),
                style: TextStyle(color: c.muted),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: GradientButton(
                  label: tr('Mit Dropbox verbinden', 'Connect to Dropbox'),
                  icon: Icons.link,
                  colors: c.sky,
                  onPressed: _busy ? null : _connectBrowser,
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => setState(() => _codeMode = true),
                  child: Text(tr('Geht nicht? Mit Code verbinden', 'Not working? Connect with a code')),
                ),
              ),
            ] else ...[
              step(1, tr('„Bei Dropbox anmelden“ tippen. Der Browser öffnet sich.', 'Tap “Sign in to Dropbox”. Your browser opens.')),
              step(
                2,
                tr(
                  'Anmelden und Conti den Zugriff erlauben. Dropbox zeigt danach einen Code: auf „Kopieren“ tippen.',
                  'Sign in and allow Conti access. Dropbox then shows a code: tap “Copy”.',
                ),
              ),
              step(3, tr('Zurück zu Conti wechseln, „Einfügen“ und dann „Verbinden“ tippen.', 'Switch back to Conti, tap “Paste”, then “Connect”.')),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _startCode,
                  icon: const Icon(Icons.open_in_new),
                  label: Text(tr('Bei Dropbox anmelden', 'Sign in to Dropbox')),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _code,
                enabled: _codeStarted,
                decoration: InputDecoration(
                  labelText: tr('Code von Dropbox', 'Code from Dropbox'),
                  suffixIcon: IconButton(
                    tooltip: tr('Einfügen', 'Paste'),
                    icon: const Icon(Icons.content_paste),
                    onPressed: _codeStarted ? _paste : null,
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: GradientButton(
                  label: tr('Verbinden', 'Connect'),
                  icon: Icons.link,
                  colors: c.sky,
                  onPressed: _busy || !_codeStarted || _code.text.trim().isEmpty ? null : _finishCode,
                ),
              ),
              if (!SyncController.prefersCode)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => setState(() => _codeMode = false),
                    child: Text(tr('Lieber automatisch verbinden', 'Connect automatically instead')),
                  ),
                ),
            ],
          ],
        ),
      ),
    ];
  }
}

class _DropboxBadge extends StatelessWidget {
  const _DropboxBadge({required this.colors});
  final List<Color> colors;

  @override
  Widget build(BuildContext context) => Container(
    width: 44,
    height: 44,
    decoration: BoxDecoration(gradient: LinearGradient(colors: colors), borderRadius: BorderRadius.circular(14)),
    child: const Icon(Icons.cloud_sync_outlined, color: Colors.white),
  );
}

/// Kleines Zeichen für den Zustand des Abgleichs (für Kopfzeilen).
/// Antippen öffnet die Abgleich-Seite.
class SyncStatusButton extends StatelessWidget {
  const SyncStatusButton({super.key});

  @override
  Widget build(BuildContext context) {
    final sync = SyncScope.of(context);
    final c = context.conti;
    if (!sync.available) return const SizedBox.shrink();
    final (IconData icon, Color color, String tip) = switch (sync.status) {
      SyncStatus.off => (Icons.cloud_off_outlined, c.muted, tr('Nicht mit Dropbox verbunden', 'Not connected to Dropbox')),
      SyncStatus.idle => (Icons.cloud_done_outlined, c.sky.last, tr('Abgeglichen', 'Synced')),
      SyncStatus.syncing => (Icons.cloud_sync_outlined, c.sky.first, tr('Gleicht ab …', 'Syncing …')),
      SyncStatus.error => (Icons.cloud_off, c.sun.last, sync.error ?? tr('Abgleich ging nicht', 'Sync failed')),
    };
    return IconButton(
      tooltip: tip,
      icon: Icon(icon, color: color),
      onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SyncPage())),
    );
  }
}
