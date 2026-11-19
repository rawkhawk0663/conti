import 'package:flutter/material.dart';

import '../../app/l10n.dart';
import '../../app/theme.dart';
import '../../app/version.dart';
import '../../core/conti_state.dart';
import '../../core/sync/sync_controller.dart';
import '../sync/sync_page.dart';
import 'about_page.dart';
import 'accounts_page.dart';
import 'business_page.dart';
import 'categories_page.dart';
import 'data_page.dart';

/// Einstellungen: eine Liste von Bereichen, jeder öffnet eine eigene Seite.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = ContiScope.of(context);
    final c = context.conti;
    void open(Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

    Widget tile(IconData icon, List<Color> colors, String title, String sub, Widget page) => ListTile(
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(gradient: LinearGradient(colors: colors), borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
      title: Text(title),
      subtitle: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => open(page),
    );

    final b = s.business;
    final sync = SyncScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Einstellungen', 'Settings'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
            children: [
              Card(
                child: Column(
                  children: [
                    tile(
                      Icons.storefront_outlined,
                      c.pink,
                      tr('Mein Geschäft', 'My business'),
                      b.isEmpty ? tr('Name, Adresse, Logo, IBAN', 'Name, address, logo, IBAN') : b.displayName,
                      const BusinessPage(),
                    ),
                    tile(
                      Icons.account_balance_wallet_outlined,
                      c.mint,
                      tr('Konten', 'Accounts'),
                      s.accounts.map((a) => a.name).join(', '),
                      const AccountsPage(),
                    ),
                    tile(
                      Icons.category_outlined,
                      c.sun,
                      tr('Kategorien', 'Categories'),
                      tr('${s.categories.length} Kategorien', '${s.categories.length} categories'),
                      const CategoriesPage(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Card(child: _Appearance()),
              const SizedBox(height: 14),
              Card(
                child: Column(
                  children: [
                    tile(
                      Icons.cloud_sync_outlined,
                      c.sky,
                      tr('Abgleich mit Dropbox', 'Sync with Dropbox'),
                      !sync.available
                          ? tr('In dieser Version nicht eingerichtet', 'Not set up in this version')
                          : sync.connected
                          ? (sync.account ?? tr('Verbunden', 'Connected'))
                          : tr('Nicht verbunden', 'Not connected'),
                      const SyncPage(),
                    ),
                    tile(
                      Icons.inventory_2_outlined,
                      c.sky,
                      tr('Daten & Sicherung', 'Data & backup'),
                      tr('Import, Sicherungen, Datenordner', 'Import, backups, data folder'),
                      const DataPage(),
                    ),
                    tile(
                      Icons.info_outline,
                      c.pink,
                      tr('Über Conti', 'About Conti'),
                      tr('Version $contiVersion · Updates · Fehlerprotokoll', 'Version $contiVersion · Updates · Error log'),
                      const AboutPage(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Appearance extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final s = ContiScope.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('Darstellung', 'Appearance'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          SegmentedButton<ThemeMode>(
            segments: [
              ButtonSegment(value: ThemeMode.system, label: Text(tr('Wie Gerät', 'System'))),
              ButtonSegment(value: ThemeMode.light, label: Text(tr('Hell', 'Light'))),
              ButtonSegment(value: ThemeMode.dark, label: Text(tr('Dunkel', 'Dark'))),
            ],
            selected: {s.device.themeMode},
            showSelectedIcon: false,
            onSelectionChanged: (v) => s.setThemeMode(v.first),
          ),
          const SizedBox(height: 20),
          // Absichtlich zweisprachig beschriftet, damit man die Sprache immer findet.
          Text('Sprache · Language', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          SegmentedButton<AppLanguage?>(
            segments: [
              ButtonSegment(value: null, label: Text(tr('Wie Gerät', 'System'))),
              for (final l in AppLanguage.values) ButtonSegment(value: l, label: Text(l.label)),
            ],
            selected: {s.device.language},
            showSelectedIcon: false,
            onSelectionChanged: (v) => s.setLanguage(v.first),
          ),
        ],
      ),
    );
  }
}
