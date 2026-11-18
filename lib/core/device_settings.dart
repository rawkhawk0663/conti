import 'package:flutter/material.dart';

import '../app/l10n.dart';
import 'store/json_file.dart';

/// Einstellungen nur für dieses Gerät (werden nicht abgeglichen):
/// Darstellung, Sprache, ob die Einrichtung fertig ist.
class DeviceSettings {
  DeviceSettings(this._file);

  final JsonFile _file;
  Map<String, dynamic> _data = {};

  Future<void> load() async => _data = await _file.read();

  Future<void> _save() => _file.write(_data);

  ThemeMode get themeMode => switch (_data['themeMode']) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  Future<void> setThemeMode(ThemeMode m) {
    _data['themeMode'] = switch (m) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    return _save();
  }

  /// Gewählte Sprache (null = wie das System).
  AppLanguage? get language => AppLanguage.fromCode(_data['language'] as String?);

  Future<void> setLanguage(AppLanguage? l) {
    if (l == null) {
      _data.remove('language');
    } else {
      _data['language'] = l.name;
    }
    return _save();
  }

  bool get setupDone => _data['setupDone'] == true;

  Future<void> setSetupDone() {
    _data['setupDone'] = true;
    return _save();
  }

  /// Datum der letzten automatischen Sicherung („2026-11-18“).
  String? get lastAutoBackup => _data['lastAutoBackup'] as String?;

  Future<void> setLastAutoBackup(String day) {
    _data['lastAutoBackup'] = day;
    return _save();
  }

  /// Zuletzt gewähltes Konto für neue Buchungen.
  String? get lastAccountId => _data['lastAccountId'] as String?;

  Future<void> setLastAccountId(String id) {
    _data['lastAccountId'] = id;
    return _save();
  }
}
