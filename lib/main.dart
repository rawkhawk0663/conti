import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';

import 'app/error_log.dart';
import 'app/l10n.dart';
import 'app/reminders.dart';
import 'app/theme.dart';
import 'app/updater.dart';
import 'app/window_buttons.dart';
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
  // Windows: maximiert, ohne Titelleiste (eigene Fensterknöpfe oben rechts).
  await prepareWindow();
  final state = ContiState(support);
  await state.load();
  final sync = SyncController(state)..start();
  // Erinnerungen: einrichten, einmal um Erlaubnis fragen, bei jeder Änderung neu planen.
  await Reminders.init();
  if (state.device.remindersOn && !state.needsSetup) unawaited(Reminders.askPermission());
  Timer? plan;
  void replan() {
    plan?.cancel();
    plan = Timer(const Duration(seconds: 2), () => Reminders.reschedule(state));
  }

  state.addListener(replan);
  replan();
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

void _registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final (name, file) in const [
      ('Sora', 'OFL-Sora.txt'),
      ('IBM Plex Sans', 'OFL-IBMPlexSans.txt'),
      ('Arimo', 'OFL-Arimo.txt'),
      ('Roboto Slab', 'LICENSE-RobotoSlab.txt'),
    ]) {
      yield LicenseEntryWithLineBreaks([
        name,
      ], await rootBundle.loadString('assets/fonts/$file'));
    }
  });
}

/// Für die Escape-Taste: die oberste Seite schliessen.
final _navigator = GlobalKey<NavigatorState>();

/// Escape schliesst die oberste Seite (Buchung, Auftrag …), wie das Kreuz
/// oben links (Wunsch des Besitzers). Ist ein Menü oder Fenster offen, das
/// sich selbst schliessen kann, geht zuerst dieses zu.
KeyEventResult _onEscape(FocusNode node, KeyEvent event) {
  if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.escape) return KeyEventResult.ignored;
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx != null) {
    // Ein Textfeld hält Escape nicht zurück, sonst ginge die Seite mit dem Cursor im Feld nie zu.
    final inText = ctx.findAncestorStateOfType<EditableTextState>() != null;
    final action = inText ? null : Actions.maybeFind<DismissIntent>(ctx);
    if (action != null && action.isEnabled(const DismissIntent())) {
      Actions.invoke(ctx, const DismissIntent());
      return KeyEventResult.handled;
    }
  }
  // Zuerst, was über allem liegt (z. B. eine Seite vor der Einrichtung),
  // dann die offene Seite im sichtbaren Bereich der Leiste.
  for (final nav in [_navigator.currentState, ShellNav.current]) {
    if (nav != null && nav.canPop()) {
      nav.maybePop();
      return KeyEventResult.handled;
    }
  }
  return KeyEventResult.ignored;
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
              navigatorKey: _navigator,
              builder: (context, child) => Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onKeyEvent: _onEscape,
                child: WindowButtonsOverlay(child: child ?? const SizedBox.shrink()),
              ),
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
