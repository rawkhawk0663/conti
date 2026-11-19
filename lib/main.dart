import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app/error_log.dart';
import 'app/l10n.dart';
import 'app/theme.dart';
import 'app/updater.dart';
import 'core/backup.dart';
import 'core/conti_state.dart';
import 'core/sync/sync_controller.dart';
import 'features/setup/setup_screen.dart';
import 'features/shell/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final support = (await getApplicationSupportDirectory()).path;
  ErrorLog.install(support);
  _registerFontLicenses();
  await _prepareWindow();
  final state = ContiState(support);
  await state.load();
  final sync = SyncController(state)..start();
  // Einmal pro Tag eine Sicherung, nach einem Update alte Programmdateien wegräumen.
  Future<void>.delayed(const Duration(seconds: 8), () async {
    try {
      await Backup.autoBackup(state);
    } catch (e, st) {
      ErrorLog.record(e, st, where: 'Automatische Sicherung');
    }
  });
  Future<void>.delayed(const Duration(seconds: 5), Updater.cleanUp);
  runApp(ContiApp(state: state, sync: sync));
}

/// Windows: maximiert öffnen, mit dem Namen der App im Titel.
Future<void> _prepareWindow() async {
  if (kIsWeb || !Platform.isWindows) return;
  try {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(title: 'Conti', minimumSize: Size(420, 560)),
      () async {
        await windowManager.maximize();
        await windowManager.show();
        await windowManager.focus();
      },
    );
  } catch (e, st) {
    ErrorLog.record(e, st, where: 'Fenster vorbereiten');
  }
}

void _registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final (name, file) in const [
      ('Sora', 'OFL-Sora.txt'),
      ('IBM Plex Sans', 'OFL-IBMPlexSans.txt'),
    ]) {
      yield LicenseEntryWithLineBreaks([
        name,
      ], await rootBundle.loadString('assets/fonts/$file'));
    }
  });
}

class ContiApp extends StatelessWidget {
  const ContiApp({super.key, required this.state, this.sync});
  final ContiState state;

  /// Abgleich (in Tests ohne).
  final SyncController? sync;

  @override
  Widget build(BuildContext context) {
    return ContiScope(
      state: state,
      child: SyncScope(
        sync: sync ?? SyncController(state),
        child: ValueListenableBuilder(
          valueListenable: L10n.language,
          builder: (context, language, _) => ListenableBuilder(
            listenable: state,
            builder: (context, _) => MaterialApp(
              title: 'Conti',
              debugShowCheckedModeBanner: false,
              theme: buildContiTheme(Brightness.light),
              darkTheme: buildContiTheme(Brightness.dark),
              themeMode: state.device.themeMode,
              locale: language.locale,
              supportedLocales: const [
                Locale('de', 'CH'),
                Locale('de'),
                Locale('en'),
              ],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: state.needsSetup ? const SetupScreen() : const HomeShell(),
            ),
          ),
        ),
      ),
    );
  }
}
