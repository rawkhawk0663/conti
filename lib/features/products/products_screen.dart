import 'package:flutter/material.dart';

import '../../app/l10n.dart';
import '../../app/theme.dart';
import '../../core/conti_state.dart';
import '../../core/model/crm.dart';
import '../../core/model/synced.dart';
import '../../core/money.dart';
import '../../widgets/visuals.dart';

String unitLabel(PriceUnit u) => switch (u) {
  PriceUnit.flat => tr('pauschal', 'flat'),
  PriceUnit.hour => tr('pro Stunde', 'per hour'),
  PriceUnit.lesson => tr('pro Lektion', 'per lesson'),
  PriceUnit.piece => tr('pro Stück', 'per piece'),
};

/// Kurz für Positionen: „Std.“, „Lekt.“ …
String unitShort(PriceUnit u) => switch (u) {
  PriceUnit.flat => tr('pauschal', 'flat'),
  PriceUnit.hour => tr('Std.', 'hrs'),
  PriceUnit.lesson => tr('Lekt.', 'lessons'),
  PriceUnit.piece => tr('Stk.', 'pcs'),
};

/// Produkte und Leistungen mit Preis, nach Gruppe geordnet.
class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ContiScope.of(context);
    final c = context.conti;
    final q = _search.text.trim().toLowerCase();
    final list = s.products
        .where((p) => q.isEmpty || '${p.name} ${p.description} ${p.group}'.toLowerCase().contains(q))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final groups = <String, List<Product>>{};
    for (final p in list) {
      groups.putIfAbsent(p.group.trim(), () => []).add(p);
    }
    final keys = groups.keys.toList()..sort((a, b) => a.isEmpty ? 1 : (b.isEmpty ? -1 : a.compareTo(b)));
    return Scaffold(
      appBar: AppBar(title: Text(tr('Produkte', 'Products'))),
      floatingActionButton: GradientFab(label: tr('Produkt', 'Product'), icon: Icons.add, onPressed: () => editProduct(context)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
            children: [
              TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: tr('Suchen …', 'Search …'),
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  suffixIcon: _search.text.isEmpty ? null : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_search.clear)),
                ),
              ),
              const SizedBox(height: 12),
              if (list.isEmpty)
                EmptyState(
                  icon: Icons.sell_outlined,
                  title: q.isEmpty ? tr('Noch keine Produkte', 'No products yet') : tr('Nichts gefunden', 'Nothing found'),
                  text: tr(
                    'Produkte und Leistungen mit Preis, z. B. „Gig“, „Lektion 45 Minuten“ oder „Flyer-Gestaltung pro Stunde“. In Aufträgen wählst du sie dann aus.',
                    'Products and services with a price, e.g. “Gig”, “45-minute lesson” or “Flyer design per hour”. You then pick them in orders.',
                  ),
                ),
              for (final g in keys) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
                  child: CapsLabel(g.isEmpty ? tr('Ohne Gruppe', 'No group') : g),
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      children: [
                        for (final p in groups[g]!)
                          ListTile(
                            title: Text(p.name),
                            subtitle: p.description.isEmpty ? null : Text(p.description, maxLines: 1, overflow: TextOverflow.ellipsis),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  'CHF ${Money.format(p.price)}',
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()]),
                                ),
                                Text(unitLabel(p.unit), style: TextStyle(color: c.muted, fontSize: 12)),
                              ],
                            ),
                            onTap: () => editProduct(context, product: p),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Produkt anlegen oder ändern. Gibt das gespeicherte Produkt zurück.
Future<Product?> editProduct(BuildContext context, {Product? product}) async {
  final s = ContiScope.read(context);
  final x = product?.copy() ?? Product(id: newId(), name: '');
  final name = TextEditingController(text: x.name);
  final desc = TextEditingController(text: x.description);
  final group = TextEditingController(text: x.group);
  final price = TextEditingController(text: x.price == 0 ? '' : Money.forInput(x.price));
  final groups = {for (final p in s.products) p.group.trim()}..remove('');
  String? error;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(product == null ? tr('Neues Produkt', 'New product') : tr('Produkt', 'Product')),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: name, autofocus: product == null, decoration: InputDecoration(labelText: tr('Name', 'Name'), hintText: tr('z. B. Gig', 'e.g. Gig'))),
                const SizedBox(height: 14),
                TextField(
                  controller: desc,
                  decoration: InputDecoration(labelText: tr('Beschreibung (steht auf der Rechnung)', 'Description (shown on the invoice)')),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: price,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'CHF', hintText: '0.00'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<PriceUnit>(
                        initialValue: x.unit,
                        isExpanded: true,
                        decoration: InputDecoration(labelText: tr('Einheit', 'Unit')),
                        items: [for (final u in PriceUnit.values) DropdownMenuItem(value: u, child: Text(unitLabel(u)))],
                        onChanged: (v) => setState(() => x.unit = v ?? x.unit),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Autocomplete<String>(
                  initialValue: TextEditingValue(text: x.group),
                  optionsBuilder: (v) => groups.where((g) => g.toLowerCase().contains(v.text.toLowerCase())),
                  onSelected: (v) => group.text = v,
                  fieldViewBuilder: (context, ctl, focus, onSubmit) => TextField(
                    controller: ctl,
                    focusNode: focus,
                    onChanged: (v) => group.text = v,
                    decoration: InputDecoration(labelText: tr('Gruppe (optional)', 'Group (optional)'), hintText: tr('z. B. Musik, Grafik', 'e.g. Music, Design')),
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          if (product != null)
            TextButton(
              onPressed: () async {
                await s.deleteProduct(product);
                if (context.mounted) Navigator.pop(context, false);
              },
              child: Text(tr('Löschen', 'Delete')),
            ),
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Abbrechen', 'Cancel'))),
          FilledButton(
            onPressed: () {
              final p = price.text.trim().isEmpty ? 0 : Money.parse(price.text);
              if (name.text.trim().isEmpty) {
                setState(() => error = tr('Bitte einen Namen eingeben.', 'Please enter a name.'));
                return;
              }
              if (p == null || p < 0) {
                setState(() => error = tr('Der Preis ist keine Zahl.', 'The price is not a number.'));
                return;
              }
              x
                ..name = name.text.trim()
                ..description = desc.text.trim()
                ..group = group.text.trim()
                ..price = p;
              Navigator.pop(context, true);
            },
            child: Text(tr('Sichern', 'Save')),
          ),
        ],
      ),
    ),
  );
  if (ok != true) return null;
  await s.saveProduct(x);
  return x;
}

/// Produkt auswählen (für Positionen). Null = abgebrochen.
Future<Product?> pickProduct(BuildContext context) {
  final s = ContiScope.read(context);
  return showModalBottomSheet<Product>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      builder: (context, ctl) => ListView(
        controller: ctl,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(tr('Produkt wählen', 'Choose a product'), style: Theme.of(context).textTheme.titleMedium),
          ),
          for (final p in s.products..sort((a, b) => a.name.compareTo(b.name)))
            ListTile(
              title: Text(p.name),
              subtitle: p.description.isEmpty ? null : Text(p.description),
              trailing: Text('CHF ${Money.format(p.price)}'),
              onTap: () => Navigator.pop(context, p),
            ),
          ListTile(
            leading: const Icon(Icons.add),
            title: Text(tr('Neues Produkt …', 'New product …')),
            onTap: () async {
              final p = await editProduct(context);
              if (context.mounted) Navigator.pop(context, p);
            },
          ),
        ],
      ),
    ),
  );
}
