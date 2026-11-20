import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/l10n.dart';
import '../../app/window_buttons.dart';
import '../../widgets/visuals.dart';
import '../clients/clients_screen.dart';
import '../entries/entries_screen.dart';
import '../orders/orders_screen.dart';
import '../overview/overview_screen.dart';
import '../products/products_screen.dart';
import '../settings/settings_screen.dart';

/// Breite, ab der links eine Leiste statt unten eine Navigation erscheint.
const wideLayout = 840.0;

/// Jeder Bereich (Übersicht, Buchungen …) hat einen eigenen Navigator. So
/// bleibt die Leiste sichtbar, wenn eine Buchung oder ein Auftrag offen ist
/// (Wunsch des Besitzers), und jeder Bereich behält seine offene Seite, wenn
/// man hin- und herwechselt.
class ShellNav {
  ShellNav._();

  static final keys = List.generate(6, (_) => GlobalKey<NavigatorState>());
  static int index = 0;

  /// Navigator des sichtbaren Bereichs.
  static NavigatorState? get current => keys[index].currentState;
}

/// Rahmen der App: Navigation unten (Handy) oder links (Surface).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    ShellNav.index = 0;
  }

  void _go(int i) {
    // Nochmals auf den gewählten Bereich: zurück zu seiner ersten Seite.
    if (i == _index) {
      ShellNav.keys[i].currentState?.popUntil((r) => r.isFirst);
      return;
    }
    setState(() => _index = ShellNav.index = i);
  }

  /// Zurück-Taste (Android): zuerst die offene Seite im Bereich schliessen,
  /// dann zur Übersicht, erst dann die App verlassen.
  void _back() {
    final nav = ShellNav.current;
    if (nav != null && nav.canPop()) {
      nav.maybePop();
    } else if (_index != 0) {
      _go(0);
    } else {
      SystemNavigator.pop();
    }
  }

  Widget _tab(int i, Widget page) => Navigator(
    key: ShellNav.keys[i],
    onGenerateRoute: (settings) => MaterialPageRoute<void>(settings: settings, builder: (_) => page),
  );

  @override
  Widget build(BuildContext context) {
    final pages = [
      OverviewScreen(onShowEntries: () => _go(1)),
      const EntriesScreen(),
      const ClientsScreen(),
      const OrdersScreen(),
      const ProductsScreen(),
      const SettingsScreen(),
    ];
    final items = [
      (Icons.space_dashboard_outlined, Icons.space_dashboard, tr('Übersicht', 'Overview')),
      (Icons.receipt_long_outlined, Icons.receipt_long, tr('Buchungen', 'Entries')),
      (Icons.people_outline, Icons.people, tr('Kunden', 'Clients')),
      (Icons.work_outline, Icons.work, tr('Aufträge', 'Orders')),
      (Icons.sell_outlined, Icons.sell, tr('Produkte', 'Products')),
      (Icons.settings_outlined, Icons.settings, tr('Einstellungen', 'Settings')),
    ];
    final page = PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: IndexedStack(index: _index, children: [for (var i = 0; i < pages.length; i++) _tab(i, pages[i])]),
    );
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth >= wideLayout) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: _index,
                  onDestinationSelected: _go,
                  // Am Logo verschiebt man das Fenster, doppelt antippen maximiert.
                  leading: const WindowDragArea(
                    child: Padding(padding: EdgeInsets.only(top: 12, bottom: 20), child: ContiMark(size: 40)),
                  ),
                  destinations: [
                    for (final (icon, sel, label) in items)
                      NavigationRailDestination(icon: Icon(icon), selectedIcon: Icon(sel), label: Text(label)),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: page),
              ],
            ),
          );
        }
        return Scaffold(
          body: page,
          bottomNavigationBar: NavigationBar(
            // Sechs Punkte: nur Symbole (Wunsch des Besitzers), der Titel oben sagt, wo man ist.
            labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
            height: 64,
            selectedIndex: _index,
            onDestinationSelected: _go,
            destinations: [
              for (final (icon, sel, label) in items) NavigationDestination(icon: Icon(icon), selectedIcon: Icon(sel), label: label),
            ],
          ),
        );
      },
    );
  }
}
