import 'package:flutter/material.dart';

import '../../app/l10n.dart';
import '../../widgets/visuals.dart';
import '../clients/clients_screen.dart';
import '../entries/entries_screen.dart';
import '../orders/orders_screen.dart';
import '../overview/overview_screen.dart';
import '../products/products_screen.dart';
import '../settings/settings_screen.dart';

/// Breite, ab der links eine Leiste statt unten eine Navigation erscheint.
const wideLayout = 840.0;

/// Rahmen der App: Navigation unten (Handy) oder links (Surface).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  void _go(int i) => setState(() => _index = i);

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
    final page = IndexedStack(index: _index, children: pages);
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth >= wideLayout) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: _index,
                  onDestinationSelected: _go,
                  leading: const Padding(padding: EdgeInsets.only(top: 12, bottom: 20), child: ContiMark(size: 40)),
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
            // Sechs Punkte: Beschriftung nur beim gewählten, sonst wird es eng.
            labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
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
