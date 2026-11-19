import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;

import '../../app/error_log.dart';
import '../../app/l10n.dart';
import '../../app/theme.dart';
import '../../core/conti_state.dart';
import '../../core/dates.dart';
import '../../core/model/category.dart';
import '../../core/model/closing.dart';
import '../../core/model/entry.dart';
import '../../core/model/synced.dart';
import '../../core/money.dart';
import '../../widgets/visuals.dart';

/// Buchung erfassen oder ändern (eigene Seite, auf dem Handy bildschirmfüllend).
Future<void> openEntryEditor(BuildContext context, {Entry? entry, EntryKind? kind, bool isNew = false}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => EntryEditor(entry: entry, kind: kind, isNew: isNew || entry == null),
    ),
  );
}

class EntryEditor extends StatefulWidget {
  const EntryEditor({super.key, this.entry, this.kind, required this.isNew});

  final Entry? entry;
  final EntryKind? kind;
  final bool isNew;

  @override
  State<EntryEditor> createState() => _EntryEditorState();
}

class _SplitRow {
  _SplitRow({this.categoryId, String amount = '', String text = ''})
    : amount = TextEditingController(text: amount),
      text = TextEditingController(text: text);
  String? categoryId;
  final TextEditingController amount;
  final TextEditingController text;
}

class _EntryEditorState extends State<EntryEditor> {
  late Entry _e;
  late int? _originalYear;
  final _amount = TextEditingController();
  final _text = TextEditingController();
  final _number = TextEditingController();
  final _notes = TextEditingController();
  final _assetName = TextEditingController();
  final _assetRate = TextEditingController();

  /// Anschaffung, die über mehrere Jahre abgeschrieben wird (null = normale Ausgabe).
  AssetInfo? _asset;
  final List<_SplitRow> _splits = [];
  bool _split = false;
  bool _saving = false;
  bool _showMore = false;

  /// In dieser Sitzung neu hinzugefügte Belege (werden beim Abbrechen wieder weggeräumt).
  final List<Attachment> _added = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    final s = ContiScope.read(context);
    final src = widget.entry;
    if (src != null) {
      _e = src.copy();
      _originalYear = widget.isNew ? null : src.year;
    } else {
      final last = s.device.lastAccountId;
      final acc = s.activeAccounts.where((a) => a.id == last).firstOrNull ?? s.activeAccounts.firstOrNull;
      _e = Entry(id: newId(), date: Day.today(), kind: widget.kind ?? EntryKind.expense, amount: 0, accountId: acc?.id ?? '');
      _originalYear = null;
    }
    if (_e.amount > 0) _amount.text = Money.forInput(_e.amount);
    _text.text = _e.text;
    _number.text = _e.number;
    _notes.text = _e.notes;
    if (_e.splits.isNotEmpty) {
      _split = true;
      for (final x in _e.splits) {
        _splits.add(_SplitRow(categoryId: x.categoryId, amount: Money.forInput(x.amount), text: x.text));
      }
    }
    _showMore = _e.number.isNotEmpty || _e.notes.isNotEmpty || _e.clientId != null || _e.excludeFromReports;
    _asset = AssetInfo.fromJson(_e.asset);
    _assetName.text = _asset?.name ?? '';
    _assetRate.text = '${_asset?.rate ?? ''}';
  }

  /// Buchung in einem abgeschlossenen Jahr: nur ansehen.
  bool get _locked => _originalYear != null && ContiScope.read(context).isYearClosed(_originalYear!);

  @override
  void dispose() {
    for (final c in [_amount, _text, _number, _notes, _assetName, _assetRate]) {
      c.dispose();
    }
    for (final r in _splits) {
      r.amount.dispose();
      r.text.dispose();
    }
    super.dispose();
  }

  int get _splitSum => _splits.fold(0, (a, r) => a + (Money.parse(r.amount.text) ?? 0));

  Future<void> _save() async {
    final s = ContiScope.read(context);
    final amount = Money.parse(_amount.text);
    String? err;
    if (amount == null || amount <= 0) {
      err = tr('Bitte einen Betrag eingeben, z. B. 36.80.', 'Please enter an amount, e.g. 36.80.');
    } else if (s.accounts.isNotEmpty && s.account(_e.accountId) == null) {
      err = tr('Bitte ein Konto wählen.', 'Please choose an account.');
    } else if (_e.kind == EntryKind.transfer && (_e.toAccountId == null || _e.toAccountId == _e.accountId)) {
      err = tr('Bitte ein anderes Zielkonto wählen.', 'Please choose a different target account.');
    } else if (_split && _e.kind != EntryKind.transfer) {
      if (_splits.any((r) => r.categoryId == null || (Money.parse(r.amount.text) ?? 0) <= 0)) {
        err = tr('Jeder Teil braucht eine Kategorie und einen Betrag.', 'Each part needs a category and an amount.');
      } else if (_splitSum != amount) {
        err = tr(
          'Die Teile ergeben ${Money.format(_splitSum)}, der Betrag ist ${Money.format(amount)}.',
          'The parts add up to ${Money.format(_splitSum)}, the amount is ${Money.format(amount)}.',
        );
      }
    }
    final asset = _e.kind == EntryKind.expense && !_split ? _asset : null;
    if (err == null && asset != null && asset.method != DepMethod.immediate) {
      final rate = int.tryParse(_assetRate.text.trim());
      if (rate == null || rate < 1 || rate > 100) {
        err = tr('Bitte einen Satz zwischen 1 und 100 % eingeben.', 'Please enter a rate between 1 and 100%.');
      } else {
        asset.rate = rate;
      }
    }
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    if (asset != null) asset.name = _assetName.text.trim().isEmpty ? _text.text.trim() : _assetName.text.trim();
    _e.asset = asset?.toJson();
    _e
      ..amount = amount!
      ..text = _text.text.trim()
      ..number = _number.text.trim()
      ..notes = _notes.text.trim();
    if (_e.kind == EntryKind.transfer) {
      _e
        ..categoryId = null
        ..splits = [];
    } else {
      _e.toAccountId = null;
      if (_split) {
        _e
          ..categoryId = null
          ..splits = [
            for (final r in _splits) EntrySplit(categoryId: r.categoryId!, amount: Money.parse(r.amount.text)!, text: r.text.text.trim()),
          ];
      } else {
        _e.splits = [];
      }
    }
    setState(() => _saving = true);
    try {
      await s.saveEntry(_e, previousYear: _originalYear);
      _added.clear();
      if (mounted) Navigator.pop(context);
    } on YearClosedException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.message;
        });
      }
    } catch (e, st) {
      ErrorLog.record(e, st, where: 'Buchung sichern');
      if (mounted) {
        setState(() {
          _saving = false;
          _error = tr('Speichern ging nicht: $e', 'Saving failed: $e');
        });
      }
    }
  }

  /// Beim Verlassen ohne Speichern neu kopierte Belege wieder löschen.
  Future<void> _discardAdded() async {
    final s = ContiScope.read(context);
    for (final a in _added) {
      try {
        await File(s.dataPath(a.file)).delete();
      } catch (_) {}
    }
    _added.clear();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _e.date,
      firstDate: DateTime(2000),
      lastDate: DateTime(Day.today().year + 5, 12, 31),
    );
    if (d != null) setState(() => _e.date = d);
  }

  Future<void> _addFiles() async {
    final s = ContiScope.read(context);
    final files = await openFiles(
      acceptedTypeGroups: [
        XTypeGroup(
          label: tr('Belege', 'Receipts'),
          extensions: const ['pdf', 'jpg', 'jpeg', 'png', 'heic', 'webp'],
          mimeTypes: const ['application/pdf', 'image/*'],
          uniformTypeIdentifiers: const ['com.adobe.pdf', 'public.image'],
        ),
      ],
    );
    for (final f in files) {
      final a = await s.addAttachmentBytes(bytes: await f.readAsBytes(), name: f.name, year: _e.date.year);
      _added.add(a);
      setState(() => _e.attachments.add(a));
    }
  }

  Future<void> _takePhoto() async {
    final s = ContiScope.read(context);
    try {
      final x = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 80, maxWidth: 2400);
      if (x == null) return;
      final name = 'Beleg ${Day.toKey(DateTime.now())}${p.extension(x.name).isEmpty ? '.jpg' : p.extension(x.name)}';
      final a = await s.addAttachmentBytes(bytes: await x.readAsBytes(), name: name, year: _e.date.year);
      _added.add(a);
      setState(() => _e.attachments.add(a));
    } catch (e, st) {
      ErrorLog.record(e, st, where: 'Foto aufnehmen');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(tr('Die Kamera liess sich nicht öffnen.', 'The camera could not be opened.'))));
      }
    }
  }

  Future<void> _open(Attachment a) async {
    final s = ContiScope.read(context);
    final r = await OpenFilex.open(s.dataPath(a.file));
    if (r.type != ResultType.done && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('Öffnen ging nicht: ${r.message}', 'Could not open: ${r.message}'))));
    }
  }

  Future<void> _delete() async {
    final s = ContiScope.read(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Buchung löschen?', 'Delete entry?')),
        content: Text(
          tr(
            'Die Buchung verschwindet aus der Liste. Die Belege bleiben im Datenordner aufbewahrt.',
            'The entry disappears from the list. Its receipts stay in the data folder.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Abbrechen', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Löschen', 'Delete'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await s.deleteEntry(_e);
    } on YearClosedException catch (e) {
      if (mounted) setState(() => _error = e.message);
      return;
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = ContiScope.of(context);
    final c = context.conti;
    final transfer = _e.kind == EntryKind.transfer;
    final cats = s.categoryTree(income: _e.kind == EntryKind.income);
    final accounts = s.accounts.where((a) => !a.archived || a.id == _e.accountId || a.id == _e.toAccountId).toList();
    final isMobile = Platform.isAndroid || Platform.isIOS;
    final kindColors = switch (_e.kind) {
      EntryKind.income => c.mint,
      EntryKind.expense => c.sun,
      EntryKind.transfer => c.sky,
    };

    final locked = _locked;
    final form = ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        if (locked) ...[_LockedNote(year: _originalYear!), const SizedBox(height: 16)],
        IgnorePointer(
          ignoring: locked,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<EntryKind>(
                segments: [
                  ButtonSegment(value: EntryKind.income, label: Text(tr('Einnahme', 'Income'))),
                  ButtonSegment(value: EntryKind.expense, label: Text(tr('Ausgabe', 'Expense'))),
                  ButtonSegment(value: EntryKind.transfer, label: Text(tr('Umbuchung', 'Transfer'))),
                ],
                selected: {_e.kind},
                showSelectedIcon: false,
                onSelectionChanged: (v) => setState(() {
                  final k = v.first;
                  // Kategorie passt nicht mehr zur neuen Art: weg damit.
                  if ((k == EntryKind.income) != (_e.kind == EntryKind.income)) {
                    _e.categoryId = null;
                    for (final r in _splits) {
                      r.categoryId = null;
                    }
                  }
                  _e.kind = k;
                }),
              ),
              const SizedBox(height: 20),
              // Betrag
              Container(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: c.line),
                  color: c.cardHigh,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CapsLabel(tr('Betrag CHF', 'Amount CHF')),
                    TextField(
                      controller: _amount,
                      autofocus: widget.entry == null,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w300, fontFeatures: [FontFeature.tabularFigures()]),
                      decoration: const InputDecoration(
                        hintText: '0.00',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        isDense: true,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 6),
                    GradientBar(value: 1, colors: kindColors, height: 4),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _text,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: tr('Text', 'Description'),
                  hintText: transfer
                      ? tr('z. B. Bargeld einbezahlt', 'e.g. Cash deposit')
                      : tr('z. B. Saiten, Musikhaus', 'e.g. Strings, music shop'),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: _pickDate,
                      child: InputDecorator(
                        decoration: InputDecoration(labelText: tr('Datum', 'Date'), suffixIcon: const Icon(Icons.event)),
                        child: Text(Day.short(_e.date)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: accounts.any((a) => a.id == _e.accountId) ? _e.accountId : null,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: transfer ? tr('Von Konto', 'From account') : tr('Konto', 'Account')),
                      items: [
                        for (final a in accounts)
                          DropdownMenuItem(
                            value: a.id,
                            child: Text(a.name, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (v) => setState(() => _e.accountId = v ?? ''),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (transfer)
                DropdownButtonFormField<String>(
                  initialValue: accounts.any((a) => a.id == _e.toAccountId) ? _e.toAccountId : null,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: tr('Auf Konto', 'To account')),
                  items: [for (final a in accounts.where((a) => a.id != _e.accountId)) DropdownMenuItem(value: a.id, child: Text(a.name))],
                  onChanged: (v) => setState(() => _e.toAccountId = v),
                )
              else if (!_split)
                DropdownButtonFormField<String?>(
                  initialValue: cats.any((x) => x.$1.id == _e.categoryId) ? _e.categoryId : null,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: tr('Kategorie', 'Category')),
                  items: [
                    DropdownMenuItem(value: null, child: Text(tr('Ohne Kategorie', 'No category'))),
                    for (final (cat, depth) in cats)
                      DropdownMenuItem(
                        value: cat.id,
                        child: Padding(
                          padding: EdgeInsets.only(left: depth * 18.0),
                          child: Text(cat.name, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => _e.categoryId = v),
                ),
              if (!transfer) ...[
                if (_split) ..._splitEditor(cats),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: Icon(_split ? Icons.call_merge : Icons.call_split),
                    label: Text(
                      _split ? tr('Nicht aufteilen', 'Don’t split') : tr('Auf mehrere Kategorien aufteilen', 'Split across categories'),
                    ),
                    onPressed: () => setState(() {
                      _split = !_split;
                      if (_split && _splits.isEmpty) {
                        _splits.add(_SplitRow(categoryId: _e.categoryId, amount: _amount.text));
                        _splits.add(_SplitRow());
                      }
                    }),
                  ),
                ),
                if (_e.kind == EntryKind.expense && !_split) _assetEditor(),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Belege
        SectionCard(
          title: tr('Belege', 'Receipts'),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final a in _e.attachments)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    a.isPdf ? Icons.picture_as_pdf_outlined : (a.isImage ? Icons.image_outlined : Icons.insert_drive_file_outlined),
                  ),
                  title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(a.kind == 'invoice' ? tr('Rechnung', 'Invoice') : tr('Quittung', 'Receipt')),
                  onTap: () => _open(a),
                  trailing: locked
                      ? null
                      : IconButton(
                          tooltip: tr('Vom Beleg lösen', 'Remove'),
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() => _e.attachments.remove(a)),
                        ),
                ),
              if (_e.attachments.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    tr(
                      'Noch kein Beleg. Fotografiere die Quittung oder wähle eine Datei.',
                      'No receipt yet. Take a photo or choose a file.',
                    ),
                    style: TextStyle(color: c.muted),
                  ),
                ),
              if (!locked)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (isMobile)
                      OutlinedButton.icon(
                        onPressed: _takePhoto,
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: Text(tr('Foto', 'Photo')),
                      ),
                    OutlinedButton.icon(onPressed: _addFiles, icon: const Icon(Icons.attach_file), label: Text(tr('Datei', 'File'))),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (locked)
          const SizedBox.shrink()
        else if (!_showMore)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.expand_more),
              label: Text(tr('Mehr: Kunde, Belegnummer, Notiz', 'More: client, number, note')),
              onPressed: () => setState(() => _showMore = true),
            ),
          )
        else ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<String?>(
            initialValue: s.clients.any((x) => x.id == _e.clientId) ? _e.clientId : null,
            isExpanded: true,
            decoration: InputDecoration(labelText: tr('Kunde', 'Client')),
            items: [
              DropdownMenuItem(value: null, child: Text(tr('Kein Kunde', 'No client'))),
              for (final cl in s.clients)
                DropdownMenuItem(
                  value: cl.id,
                  child: Text(cl.displayName, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) => setState(() => _e.clientId = v),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _number,
            decoration: InputDecoration(labelText: tr('Belegnummer', 'Receipt number')),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _notes,
            minLines: 2,
            maxLines: 5,
            decoration: InputDecoration(labelText: tr('Notiz', 'Note')),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Nicht in Auswertungen zählen', 'Leave out of reports')),
            subtitle: Text(tr('z. B. für Privates, das nur zur Übersicht erfasst ist', 'e.g. private items kept for reference')),
            value: _e.excludeFromReports,
            onChanged: (v) => setState(() => _e.excludeFromReports = v),
          ),
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        const SizedBox(height: 20),
        if (!locked)
          Align(
            alignment: Alignment.centerRight,
            child: GradientButton(label: tr('Sichern', 'Save'), icon: Icons.check, onPressed: _saving ? null : _save),
          ),
      ],
    );

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _discardAdded();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.isNew ? tr('Neue Buchung', 'New entry') : tr('Buchung', 'Entry')),
          actions: [
            if (!widget.isNew && !locked)
              IconButton(tooltip: tr('Löschen', 'Delete'), icon: const Icon(Icons.delete_outline), onPressed: _delete),
            if (!locked) IconButton(tooltip: tr('Sichern', 'Save'), icon: const Icon(Icons.check), onPressed: _saving ? null : _save),
            const SizedBox(width: 4),
          ],
        ),
        body: Center(
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 680), child: form),
        ),
      ),
    );
  }

  /// Schalter und Angaben für eine Anschaffung, die abgeschrieben wird.
  Widget _assetEditor() {
    final c = context.conti;
    final a = _asset;
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      padding: EdgeInsets.fromLTRB(14, 4, 14, a == null ? 4 : 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Anschaffung: über mehrere Jahre abschreiben', 'Acquisition: depreciate over several years')),
            subtitle: Text(
              tr(
                'Für grössere Anschaffungen wie Instrumente, Verstärker oder Laptop. Sie zählen dann nicht als Ausgabe, sondern jedes Jahr mit einem Teil (Abschreibung).',
                'For larger purchases such as instruments, amplifiers or a laptop. They then count not as an expense but with a share every year (depreciation).',
              ),
            ),
            value: a != null,
            onChanged: (v) => setState(() {
              _asset = v ? AssetInfo(type: AssetType.machine) : null;
              _assetRate.text = '${_asset?.rate ?? ''}';
              if (v && _assetName.text.isEmpty) _assetName.text = _text.text;
            }),
          ),
          if (a != null) ...[
            const SizedBox(height: 6),
            TextField(
              controller: _assetName,
              decoration: InputDecoration(
                labelText: tr('Name der Anlage', 'Name of the asset'),
                hintText: tr('z. B. Verstärker', 'e.g. Amplifier'),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<AssetType>(
              initialValue: a.type,
              isExpanded: true,
              decoration: InputDecoration(labelText: tr('Art', 'Type')),
              items: [
                for (final t in AssetType.values)
                  DropdownMenuItem(
                    value: t,
                    child: Text(t.label, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (t) => setState(() {
                if (t == null) return;
                a.type = t;
                a.rate = a.method == DepMethod.linear ? t.rate ~/ 2 : t.rate;
                _assetRate.text = '${a.rate}';
              }),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<DepMethod>(
                    initialValue: a.method,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: tr('Abschreibung', 'Depreciation')),
                    items: [
                      for (final m in DepMethod.values)
                        DropdownMenuItem(
                          value: m,
                          child: Text(m.label, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (m) => setState(() {
                      if (m == null) return;
                      a.method = m;
                      a.rate = m == DepMethod.linear ? a.type.rate ~/ 2 : a.type.rate;
                      _assetRate.text = '${a.rate}';
                    }),
                  ),
                ),
                if (a.method != DepMethod.immediate) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _assetRate,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: tr('Satz pro Jahr', 'Rate per year'), suffixText: '%'),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text(
              a.method == DepMethod.immediate
                  ? tr(
                      'Alles im Jahr der Anschaffung abschreiben (bis auf CHF 1). Erlaubt für Geräte, Computer, Mobiliar und Fahrzeuge.',
                      'Write everything off in the year of purchase (down to CHF 1). Allowed for devices, computers, furniture and vehicles.',
                    )
                  : tr(
                      'Vorschlag nach den Normalsätzen der Steuerverwaltung. Linear ist es die Hälfte.',
                      'Suggested by the standard rates of the tax administration. Straight-line is half of it.',
                    ),
              style: TextStyle(color: c.muted, fontSize: 12.5),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _splitEditor(List<(Category, int)> cats) {
    final c = context.conti;
    final amount = Money.parse(_amount.text) ?? 0;
    final rest = amount - _splitSum;
    return [
      for (final r in _splits)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<String>(
                  initialValue: cats.any((x) => x.$1.id == r.categoryId) ? r.categoryId : null,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: tr('Kategorie', 'Category'), isDense: true),
                  items: [
                    for (final (cat, depth) in cats)
                      DropdownMenuItem<String>(
                        value: cat.id,
                        child: Padding(
                          padding: EdgeInsets.only(left: depth * 14.0),
                          child: Text(cat.name, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => r.categoryId = v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: r.amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: 'CHF', isDense: true),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: _splits.length <= 1 ? null : () => setState(() => _splits.remove(r)),
              ),
            ],
          ),
        ),
      Row(
        children: [
          TextButton.icon(
            icon: const Icon(Icons.add),
            label: Text(tr('Teil hinzufügen', 'Add part')),
            onPressed: () => setState(() => _splits.add(_SplitRow(amount: rest > 0 ? Money.forInput(rest) : ''))),
          ),
          const Spacer(),
          Text(
            rest == 0 ? tr('Geht auf', 'Balanced') : tr('Rest ${Money.format(rest)}', 'Remaining ${Money.format(rest)}'),
            style: TextStyle(color: rest == 0 ? c.plus : c.minus),
          ),
        ],
      ),
    ];
  }
}

/// Hinweis: Diese Buchung liegt in einem abgeschlossenen Jahr.
class _LockedNote extends StatelessWidget {
  const _LockedNote({required this.year});
  final int year;

  @override
  Widget build(BuildContext context) {
    final c = context.conti;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(colors: [c.sky[0].withValues(alpha: 0.16), c.sky[1].withValues(alpha: 0.16)]),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_outline),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              tr(
                'Das Jahr $year ist abgeschlossen. Diese Buchung lässt sich nicht mehr ändern. Ist etwas falsch, erfasse eine Korrektur im laufenden Jahr.',
                'The year $year is closed. This entry can no longer be changed. If something is wrong, record a correction in the current year.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
