import 'package:flutter/material.dart';

import '../../app/error_log.dart';
import '../../app/l10n.dart';
import '../../app/reminders.dart';
import '../../app/theme.dart';
import '../../core/conti_state.dart';
import '../../core/dates.dart';
import '../../core/model/crm.dart';
import '../../core/model/synced.dart';
import '../../core/money.dart';
import '../../widgets/visuals.dart';
import '../clients/client_editor.dart';
import '../products/products_screen.dart';
import 'order_widgets.dart';

/// Auftrag anlegen oder ändern. [clientId]: vorgewählter Kunde.
Future<void> openOrderEditor(BuildContext context, {Order? order, String? clientId}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => OrderEditor(order: order, clientId: clientId)),
  );
}

class OrderEditor extends StatefulWidget {
  const OrderEditor({super.key, this.order, this.clientId});
  final Order? order;
  final String? clientId;

  @override
  State<OrderEditor> createState() => _OrderEditorState();
}

class _ItemFields {
  _ItemFields(OrderItem i)
    : item = i,
      name = TextEditingController(text: i.name),
      description = TextEditingController(text: i.description),
      quantity = TextEditingController(text: _qty(i.quantity)),
      price = TextEditingController(text: i.unitPrice == 0 ? '' : Money.forInput(i.unitPrice));
  final OrderItem item;
  final TextEditingController name, description, quantity, price;

  static String _qty(double q) => q == q.roundToDouble() ? q.toInt().toString() : q.toString();

  void dispose() {
    for (final c in [name, description, quantity, price]) {
      c.dispose();
    }
  }
}

class _OrderEditorState extends State<OrderEditor> {
  late Order _o;
  final _title = TextEditingController();
  final _number = TextEditingController();
  final _notes = TextEditingController();
  final _lessons = TextEditingController();
  final List<_ItemFields> _items = [];
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final s = ContiScope.read(context);
    if (widget.order != null) {
      _o = widget.order!.copy();
    } else {
      final kind = s.orderKinds.firstOrNull;
      _o = Order(
        id: newId(),
        number: s.nextOrderNumber(),
        title: '',
        kind: kind?.id ?? '',
        clientId: widget.clientId,
        lessonsTotal: kind?.subscription == true ? kind!.lessons : null,
      );
    }
    _title.text = _o.title;
    _number.text = _o.number;
    _notes.text = _o.notes;
    _lessons.text = '${_o.lessonsTotal ?? ''}';
    _items.addAll(_o.items.map(_ItemFields.new));
  }

  @override
  void dispose() {
    for (final c in [_title, _number, _notes, _lessons]) {
      c.dispose();
    }
    for (final i in _items) {
      i.dispose();
    }
    super.dispose();
  }

  /// Eingaben in den Auftrag übernehmen. Gibt eine Fehlermeldung zurück oder null.
  String? _collect() {
    final items = <OrderItem>[];
    for (final f in _items) {
      final q = double.tryParse(f.quantity.text.trim().replaceAll(',', '.'));
      final p = f.price.text.trim().isEmpty ? 0 : Money.parse(f.price.text);
      if (f.name.text.trim().isEmpty) return tr('Jede Position braucht eine Beschreibung.', 'Every item needs a name.');
      if (q == null || q <= 0) return tr('Die Anzahl bei „${f.name.text.trim()}“ stimmt nicht.', 'The quantity of “${f.name.text.trim()}” is not valid.');
      if (p == null || p < 0) return tr('Der Preis bei „${f.name.text.trim()}“ ist keine Zahl.', 'The price of “${f.name.text.trim()}” is not a number.');
      f.item
        ..name = f.name.text.trim()
        ..description = f.description.text.trim()
        ..quantity = q
        ..unitPrice = p;
      items.add(f.item);
    }
    if (_o.isSubscription) {
      final n = int.tryParse(_lessons.text.trim());
      if (n == null || n < 1 || n > 200) return tr('Bitte die Anzahl Lektionen im Abo angeben (1 bis 200).', 'Please give the number of lessons in the pack (1 to 200).');
      _o.lessonsTotal = n;
    }
    _o
      ..title = _title.text.trim()
      ..number = _number.text.trim()
      ..notes = _notes.text.trim()
      ..items = items;
    return null;
  }

  Future<bool> _persist() async {
    final err = _collect();
    if (err != null) {
      setState(() => _error = err);
      return false;
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    try {
      await ContiScope.read(context).saveOrder(_o);
      _o = _o.copy();
      return true;
    } catch (e, st) {
      ErrorLog.record(e, st, where: 'Auftrag sichern');
      setState(() => _error = tr('Speichern ging nicht: $e', 'Saving failed: $e'));
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    if (await _persist() && mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final s = ContiScope.read(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Auftrag löschen?', 'Delete order?')),
        content: Text(tr('Der Auftrag verschwindet aus den Listen.', 'The order disappears from the lists.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Abbrechen', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Löschen', 'Delete'))),
        ],
      ),
    );
    if (ok != true) return;
    await s.deleteOrder(_o);
    if (mounted) Navigator.pop(context);
  }

  void _setKind(String? id) {
    final s = ContiScope.read(context);
    final k = s.orderKind(id);
    setState(() {
      _o.kind = id ?? '';
      if (k?.subscription == true && _o.lessonsTotal == null) {
        _o.lessonsTotal = k!.lessons;
        _lessons.text = '${k.lessons}';
      } else if (k?.subscription != true && _o.sessions.isEmpty) {
        _o.lessonsTotal = null;
      }
    });
  }

  Future<void> _addFromProduct() async {
    final p = await pickProduct(context);
    if (p == null) return;
    setState(() {
      _items.add(
        _ItemFields(
          OrderItem(
            id: newId(),
            productId: p.id,
            name: p.name,
            description: p.description,
            unit: p.unit,
            quantity: p.unit == PriceUnit.lesson && _o.isSubscription ? (_o.lessonsTotal ?? 1).toDouble() : 1,
            unitPrice: p.price,
            vat: p.vat,
          ),
        ),
      );
      if (_title.text.trim().isEmpty) _title.text = p.name;
    });
  }

  void _addFree() => setState(() => _items.add(_ItemFields(OrderItem(id: newId(), name: ''))));

  Future<void> _tickLesson() async {
    final s = ContiScope.read(context);
    final d = await showDatePicker(
      context: context,
      initialDate: Day.today(),
      firstDate: DateTime(2000),
      lastDate: DateTime(Day.today().year + 2, 12, 31),
      helpText: tr('Datum der Lektion', 'Date of the lesson'),
    );
    if (d == null) return;
    final wasUsedUp = _o.subscriptionUsedUp;
    setState(() {
      _o.sessions.add(Session(id: newId(), date: d));
      _o.sessions.sort((a, b) => a.date.compareTo(b.date));
      if (_o.status == OrderStatus.open) _o.status = OrderStatus.inProgress;
    });
    // Abhaken wird gleich gesichert, damit es auch ohne „Sichern“ bleibt.
    if (await _persist() && !wasUsedUp && _o.subscriptionUsedUp) {
      await Reminders.subscriptionUsedUp(s, _o);
    }
  }

  Future<void> _removeSession(Session x) async {
    setState(() => _o.sessions.removeWhere((y) => y.id == x.id));
    await _persist();
  }

  Future<void> _nextSubscription() async {
    final s = ContiScope.read(context);
    if (!await _persist()) return;
    final next = Order(
      id: newId(),
      number: s.nextOrderNumber(),
      title: _o.title,
      kind: _o.kind,
      clientId: _o.clientId,
      lessonsTotal: _o.lessonsTotal,
      items: [for (final i in _o.items) OrderItem.fromJson({...i.toJson(), 'id': newId()})],
    );
    await s.saveOrder(next);
    _o.followUpId = next.id;
    await s.saveOrder(_o);
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => OrderEditor(order: next)),
    );
  }

  Future<void> _newClient() async {
    final c = await editClient(context);
    if (c != null) setState(() => _o.clientId = c.id);
  }

  int get _total {
    var sum = 0;
    for (final f in _items) {
      final q = double.tryParse(f.quantity.text.trim().replaceAll(',', '.')) ?? 0;
      final p = Money.parse(f.price.text) ?? 0;
      sum += (p * q).round();
    }
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    final s = ContiScope.of(context);
    final c = context.conti;
    final kinds = s.orderKinds;
    final form = ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        TextField(
          controller: _title,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: tr('Titel', 'Title'), hintText: tr('z. B. Konzert im Kulturhaus', 'e.g. Concert at the arts centre')),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String?>(
                initialValue: s.clients.any((x) => x.id == _o.clientId) ? _o.clientId : null,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr('Kunde', 'Client')),
                items: [
                  DropdownMenuItem(value: null, child: Text(tr('Kein Kunde', 'No client'))),
                  for (final x in s.clients) DropdownMenuItem(value: x.id, child: Text(x.displayName, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => _o.clientId = v),
              ),
            ),
            IconButton(tooltip: tr('Neuer Kunde', 'New client'), onPressed: _newClient, icon: const Icon(Icons.person_add_alt)),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String?>(
                initialValue: kinds.any((k) => k.id == _o.kind) ? _o.kind : null,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr('Art', 'Kind')),
                items: [
                  DropdownMenuItem(value: null, child: Text(tr('Ohne Art', 'No kind'))),
                  for (final k in kinds) DropdownMenuItem(value: k.id, child: Text(k.name, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: _setKind,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<OrderStatus>(
                initialValue: _o.status,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr('Stand', 'Status')),
                items: [for (final st in OrderStatus.values) DropdownMenuItem(value: st, child: Text(statusLabel(st)))],
                onChanged: (v) => setState(() => _o.status = v ?? _o.status),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _o.date ?? Day.today(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime(Day.today().year + 5, 12, 31),
                  );
                  if (d != null) setState(() => _o.date = d);
                },
                child: InputDecorator(
                  decoration: InputDecoration(labelText: tr('Datum', 'Date'), suffixIcon: const Icon(Icons.event)),
                  child: Text(_o.date == null ? tr('Ohne Datum', 'No date') : Day.short(_o.date!)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(controller: _number, decoration: InputDecoration(labelText: tr('Auftrags-Nr.', 'Order no.'))),
            ),
          ],
        ),
        if (_o.isSubscription) ...[const SizedBox(height: 16), _subscriptionCard(context)],
        const SizedBox(height: 16),
        SectionCard(
          title: tr('Positionen', 'Items'),
          trailing: Text('CHF ${Money.format(_total)}', style: const TextStyle(fontWeight: FontWeight.w600)),
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final f in _items) _itemRow(context, f),
              if (_items.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(tr('Noch keine Positionen.', 'No items yet.'), style: TextStyle(color: c.muted)),
                ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(onPressed: _addFromProduct, icon: const Icon(Icons.sell_outlined), label: Text(tr('Aus Produkten', 'From products'))),
                  OutlinedButton.icon(onPressed: _addFree, icon: const Icon(Icons.edit_note), label: Text(tr('Freie Position', 'Free item'))),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        TextField(controller: _notes, minLines: 2, maxLines: 6, decoration: InputDecoration(labelText: tr('Notiz', 'Note'))),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerRight,
          child: GradientButton(label: tr('Sichern', 'Save'), icon: Icons.check, onPressed: _saving ? null : _save),
        ),
      ],
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.order == null ? tr('Neuer Auftrag', 'New order') : tr('Auftrag', 'Order')),
        actions: [
          if (widget.order != null) IconButton(tooltip: tr('Löschen', 'Delete'), icon: const Icon(Icons.delete_outline), onPressed: _delete),
          IconButton(tooltip: tr('Sichern', 'Save'), icon: const Icon(Icons.check), onPressed: _saving ? null : _save),
          const SizedBox(width: 4),
        ],
      ),
      body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720), child: form)),
    );
  }

  Widget _itemRow(BuildContext context, _ItemFields f) {
    final c = context.conti;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.cardHigh, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.line)),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(controller: f.name, decoration: InputDecoration(labelText: tr('Beschreibung', 'Name'), isDense: true)),
              ),
              IconButton(
                tooltip: tr('Position entfernen', 'Remove item'),
                icon: const Icon(Icons.close),
                onPressed: () => setState(() {
                  _items.remove(f);
                  f.dispose();
                }),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(controller: f.description, decoration: InputDecoration(labelText: tr('Zusatz (optional)', 'Details (optional)'), isDense: true)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: f.quantity,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: tr('Anzahl', 'Qty'), isDense: true),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<PriceUnit>(
                  initialValue: f.item.unit,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: tr('Einheit', 'Unit'), isDense: true),
                  items: [for (final u in PriceUnit.values) DropdownMenuItem(value: u, child: Text(unitShort(u)))],
                  onChanged: (v) => setState(() => f.item.unit = v ?? f.item.unit),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: f.price,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: tr('Tarif CHF', 'Rate CHF'), isDense: true),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _subscriptionCard(BuildContext context) {
    final c = context.conti;
    final total = int.tryParse(_lessons.text.trim()) ?? (_o.lessonsTotal ?? 0);
    final used = _o.sessions.length;
    final usedUp = total > 0 && used >= total;
    return SectionCard(
      title: tr('Abo', 'Lesson pack'),
      trailing: SizedBox(
        width: 130,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: total <= 1 ? null : () => setState(() => _lessons.text = '${total - 1}'),
              icon: const Icon(Icons.remove),
            ),
            SizedBox(
              width: 36,
              child: TextField(
                controller: _lessons,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 8)),
                onChanged: (_) => setState(() {}),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: total >= 200 ? null : () => setState(() => _lessons.text = '${total + 1}'),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GradientRing(value: total == 0 ? 0 : used / total, colors: c.pink, size: 72, stroke: 7, label: '$used/$total'),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  usedUp
                      ? tr('Alle $total Lektionen bezogen. Zeit für das nächste Abo!', 'All $total lessons used. Time for the next pack!')
                      : tr('${total - used} von $total Lektionen übrig.', '${total - used} of $total lessons left.'),
                  style: TextStyle(color: usedUp ? c.minus : null, fontWeight: usedUp ? FontWeight.w600 : null),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final (i, x) in _o.sessions.indexed)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                radius: 14,
                backgroundColor: c.track,
                child: Text('${i + 1}', style: const TextStyle(fontSize: 12)),
              ),
              title: Text(Day.long(x.date)),
              trailing: IconButton(
                tooltip: tr('Lektion entfernen', 'Remove lesson'),
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => _removeSession(x),
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              if (usedUp && !_o.followedUp)
                GradientButton(label: tr('Nächstes Abo anlegen', 'Create next pack'), icon: Icons.autorenew, onPressed: _nextSubscription),
              if (!usedUp) GradientButton(label: tr('Lektion abhaken', 'Tick off a lesson'), icon: Icons.check, colors: c.mint, onPressed: _tickLesson),
              if (usedUp) OutlinedButton.icon(onPressed: _tickLesson, icon: const Icon(Icons.add), label: Text(tr('Trotzdem abhaken', 'Tick off anyway'))),
            ],
          ),
        ],
      ),
    );
  }
}
