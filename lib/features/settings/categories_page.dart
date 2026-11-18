import 'package:flutter/material.dart';

import '../../app/l10n.dart';
import '../../app/theme.dart';
import '../../core/conti_state.dart';
import '../../core/model/category.dart';
import '../../core/model/synced.dart';
import '../../widgets/visuals.dart';

class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key});

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  bool _income = false;

  @override
  Widget build(BuildContext context) {
    final s = ContiScope.of(context);
    final tree = s.categoryTree(income: _income);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Kategorien', 'Categories'))),
      floatingActionButton: GradientFab(
        label: tr('Kategorie', 'Category'),
        icon: Icons.add,
        onPressed: () => _edit(context, null),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
            children: [
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: false, label: Text(tr('Ausgaben', 'Expenses'))),
                  ButtonSegment(value: true, label: Text(tr('Einnahmen', 'Income'))),
                ],
                selected: {_income},
                showSelectedIcon: false,
                onSelectionChanged: (v) => setState(() => _income = v.first),
              ),
              const SizedBox(height: 14),
              Card(
                child: Column(
                  children: [
                    for (final (cat, depth) in tree)
                      ListTile(
                        contentPadding: EdgeInsets.only(left: 16 + depth * 28.0, right: 8),
                        leading: depth == 0
                            ? Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(colors: _income ? context.conti.mint : context.conti.sun),
                                ),
                              )
                            : Icon(Icons.subdirectory_arrow_right, size: 18, color: context.conti.muted),
                        title: Text(cat.name),
                        onTap: () => _edit(context, cat),
                        trailing: depth == 0
                            ? IconButton(
                                tooltip: tr('Unterkategorie', 'Subcategory'),
                                icon: const Icon(Icons.add),
                                onPressed: () => _edit(context, null, parent: cat),
                              )
                            : null,
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

  Future<void> _edit(BuildContext context, Category? cat, {Category? parent}) async {
    final s = ContiScope.read(context);
    final c = cat?.copy() ??
        Category(id: newId(), name: '', income: parent?.income ?? _income, parentId: parent?.id, order: s.categories.length + 1);
    final name = TextEditingController(text: c.name);
    final tops = s.categories.where((x) => x.parentId == null && x.income == c.income && x.id != c.id).toList();
    String? error;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(cat == null ? tr('Neue Kategorie', 'New category') : tr('Kategorie', 'Category')),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: name, autofocus: true, decoration: InputDecoration(labelText: tr('Name', 'Name'))),
                const SizedBox(height: 14),
                DropdownButtonFormField<String?>(
                  initialValue: c.parentId,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: tr('Gehört zu', 'Belongs to')),
                  items: [
                    DropdownMenuItem(value: null, child: Text(tr('– (Hauptkategorie)', '– (main category)'))),
                    for (final t in tops) DropdownMenuItem(value: t.id, child: Text(t.name)),
                  ],
                  onChanged: s.categories.any((x) => x.parentId == c.id) ? null : (v) => setState(() => c.parentId = v),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
              ],
            ),
          ),
          actions: [
            if (cat != null)
              TextButton(
                onPressed: () async {
                  if (s.categoryInUse(cat.id)) {
                    setState(
                      () => error = tr(
                        'Diese Kategorie wird noch gebraucht (Buchungen oder Unterkategorien).',
                        'This category is still in use (entries or subcategories).',
                      ),
                    );
                    return;
                  }
                  await s.deleteCategory(cat.copy());
                  if (context.mounted) Navigator.pop(context, false);
                },
                child: Text(tr('Löschen', 'Delete')),
              ),
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Abbrechen', 'Cancel'))),
            FilledButton(
              onPressed: () {
                if (name.text.trim().isEmpty) {
                  setState(() => error = tr('Bitte einen Namen eingeben.', 'Please enter a name.'));
                  return;
                }
                c.name = name.text.trim();
                Navigator.pop(context, true);
              },
              child: Text(tr('Sichern', 'Save')),
            ),
          ],
        ),
      ),
    );
    if (ok == true) await s.saveCategory(c);
  }
}
