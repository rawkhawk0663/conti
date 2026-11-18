import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path/path.dart' as p;

import '../../app/l10n.dart';
import '../../app/theme.dart';
import '../../core/conti_state.dart';
import '../../core/model/business.dart';
import '../../core/swiss.dart';
import '../../widgets/visuals.dart';

/// „Mein Geschäft“: Angaben für Rechnungen und Jahresabschluss.
class BusinessPage extends StatelessWidget {
  const BusinessPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Mein Geschäft', 'My business'))),
      body: const SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 4, 16, 40),
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(width: 720, child: BusinessForm(showSave: true)),
        ),
      ),
    );
  }
}

/// Formular für „Mein Geschäft“. Wird auch in der Einrichtung gebraucht,
/// dort ohne eigenen „Sichern“-Knopf (die Einrichtung sichert selbst).
class BusinessForm extends StatefulWidget {
  const BusinessForm({super.key, this.showSave = false, this.sections = BusinessSections.all});

  final bool showSave;
  final BusinessSections sections;

  @override
  State<BusinessForm> createState() => BusinessFormState();
}

enum BusinessSections { all, address, payment, taxes }

class BusinessFormState extends State<BusinessForm> {
  late Business _b;
  final _c = <String, TextEditingController>{};
  bool _saved = false;

  TextEditingController _ctl(String key, String value) => _c.putIfAbsent(key, () => TextEditingController(text: value));

  @override
  void initState() {
    super.initState();
    _b = ContiScope.read(context).business.copy();
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Eingaben übernehmen und sichern.
  Future<void> save() async {
    final s = ContiScope.read(context);
    String v(String k) => _c[k]?.text.trim() ?? '';
    if (_c.containsKey('owner')) _b.ownerName = v('owner');
    if (_c.containsKey('company')) _b.companyName = v('company');
    if (_c.containsKey('street')) _b.street = v('street');
    if (_c.containsKey('no')) _b.houseNumber = v('no');
    if (_c.containsKey('zip')) _b.zip = v('zip');
    if (_c.containsKey('city')) _b.city = v('city');
    if (_c.containsKey('email')) _b.email = v('email');
    if (_c.containsKey('phone')) _b.phone = v('phone');
    if (_c.containsKey('web')) _b.website = v('web');
    if (_c.containsKey('iban')) _b.iban = Iban.pretty(v('iban'));
    if (_c.containsKey('bank')) _b.bankName = v('bank');
    if (_c.containsKey('vat')) _b.vatNumber = v('vat');
    if (_c.containsKey('prefix')) _b.invoice.invoicePrefix = v('prefix');
    if (_c.containsKey('terms')) _b.invoice.paymentTermsDays = int.tryParse(v('terms')) ?? _b.invoice.paymentTermsDays;
    await s.saveBusiness(_b);
    _b = s.business.copy();
    if (mounted && widget.showSave) {
      setState(() => _saved = true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Gesichert', 'Saved')), persist: false));
    }
  }

  Future<void> _pickImage({required bool logo}) async {
    final s = ContiScope.read(context);
    final f = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(
          label: tr('Bilder', 'Images'),
          extensions: const ['png', 'jpg', 'jpeg', 'svg'],
          mimeTypes: const ['image/png', 'image/jpeg', 'image/svg+xml'],
        ),
      ],
    );
    if (f == null) return;
    final ext = p.extension(f.name).toLowerCase();
    final rel = 'bilder/${logo ? 'logo' : 'unterschrift'}-${DateTime.now().millisecondsSinceEpoch}$ext';
    await s.store.putFile(rel, await f.readAsBytes());
    setState(() {
      if (logo) {
        _b.logoFile = rel;
      } else {
        _b.signatureFile = rel;
      }
    });
  }

  Widget _image(String rel) {
    final s = ContiScope.read(context);
    final path = s.dataPath(rel);
    if (rel.isEmpty || !File(path).existsSync()) {
      return Icon(Icons.image_outlined, size: 40, color: context.conti.muted);
    }
    // Logos sind oft dunkel: auf hellem Grund zeigen, wie auf der Rechnung.
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(8),
      child: rel.endsWith('.svg') ? SvgPicture.file(File(path), height: 48) : Image.file(File(path), height: 48),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sec = widget.sections;
    final all = sec == BusinessSections.all;
    Widget field(String key, String label, String value, {TextInputType? type, String? hint, int flex = 1}) => Expanded(
      flex: flex,
      child: TextField(
        controller: _ctl(key, value),
        keyboardType: type,
        decoration: InputDecoration(labelText: label, hintText: hint),
        onChanged: (_) => _saved ? setState(() => _saved = false) : null,
      ),
    );
    Widget row(List<Widget> children) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final (i, w) in children.indexed) ...[if (i > 0) const SizedBox(width: 12), w]]),
    );

    final ibanText = _c['iban']?.text ?? _b.iban;
    final ibanOk = ibanText.trim().isEmpty || Iban.isValid(ibanText);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (all || sec == BusinessSections.address)
          SectionCard(
            title: tr('Name und Adresse', 'Name and address'),
            child: Column(
              children: [
                row([field('owner', tr('Vor- und Nachname', 'First and last name'), _b.ownerName)]),
                row([field('company', tr('Firma (optional)', 'Company (optional)'), _b.companyName)]),
                row([
                  field('street', tr('Strasse', 'Street'), _b.street, flex: 3),
                  field('no', tr('Nr.', 'No.'), _b.houseNumber),
                ]),
                row([
                  field('zip', tr('PLZ', 'Postcode'), _b.zip, type: TextInputType.number),
                  field('city', tr('Ort', 'Town'), _b.city, flex: 3),
                ]),
                row([field('email', tr('E-Mail', 'Email'), _b.email, type: TextInputType.emailAddress)]),
                row([
                  field('phone', tr('Telefon', 'Phone'), _b.phone, type: TextInputType.phone),
                  field('web', tr('Webseite', 'Website'), _b.website, type: TextInputType.url),
                ]),
              ],
            ),
          ),
        if (all) const SizedBox(height: 14),
        if (all || sec == BusinessSections.payment)
          SectionCard(
            title: tr('Konto für Zahlungen', 'Account for payments'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _ctl('iban', _b.iban),
                  decoration: InputDecoration(
                    labelText: 'IBAN',
                    hintText: 'CH00 0000 0000 0000 0000 0',
                    helperMaxLines: 2,
                    errorMaxLines: 2,
                    errorText: ibanOk ? null : tr('Diese IBAN stimmt nicht (Prüfziffer).', 'This IBAN is not valid (check digits).'),
                    helperText: ibanText.trim().isNotEmpty && ibanOk
                        ? (Iban.isQrIban(ibanText)
                              ? tr('QR-IBAN: Rechnungen bekommen eine QR-Referenz.', 'QR-IBAN: invoices get a QR reference.')
                              : tr('Normale IBAN: Rechnungen bekommen eine Mitteilung.', 'Regular IBAN: invoices get a message.'))
                        : null,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 14),
                row([field('bank', tr('Bank', 'Bank'), _b.bankName)]),
                if (all) ...[
                  row([
                    field('prefix', tr('Kürzel für Rechnungsnummern', 'Invoice number prefix'), _b.invoice.invoicePrefix, hint: 'RE-'),
                    field('terms', tr('Zahlungsfrist (Tage)', 'Payment terms (days)'), '${_b.invoice.paymentTermsDays}', type: TextInputType.number),
                  ]),
                ],
              ],
            ),
          ),
        if (all) const SizedBox(height: 14),
        if (all || sec == BusinessSections.taxes)
          SectionCard(
            title: tr('Steuern', 'Taxes'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: cantons.any((c) => c.$1 == _b.canton) ? _b.canton : null,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: tr('Kanton (Steuererklärung)', 'Canton (tax return)')),
                  items: [for (final (code, name) in cantons) DropdownMenuItem(value: code, child: Text('$name ($code)'))],
                  onChanged: (v) => setState(() => _b.canton = v ?? ''),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('Ich bin MWST-pflichtig', 'I am registered for VAT')),
                  subtitle: Text(
                    tr(
                      'In der Regel erst ab CHF 100\'000 Umsatz im Jahr. Die MWST-Funktionen kommen in einem späteren Paket.',
                      'Usually only from CHF 100,000 turnover a year. VAT features come in a later package.',
                    ),
                  ),
                  value: _b.vatLiable,
                  onChanged: (v) => setState(() => _b.vatLiable = v),
                ),
                if (_b.vatLiable) row([field('vat', tr('MWST-Nummer', 'VAT number'), _b.vatNumber, hint: 'CHE-123.456.789 MWST')]),
              ],
            ),
          ),
        if (all) ...[
          const SizedBox(height: 14),
          SectionCard(
            title: tr('Logo und Unterschrift', 'Logo and signature'),
            child: Wrap(
              spacing: 24,
              runSpacing: 16,
              children: [
                for (final logo in [true, false])
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CapsLabel(logo ? tr('Logo', 'Logo') : tr('Unterschrift', 'Signature')),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(height: 64, child: _image(logo ? _b.logoFile : _b.signatureFile)),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          OutlinedButton(onPressed: () => _pickImage(logo: logo), child: Text(tr('Wählen …', 'Choose …'))),
                          if ((logo ? _b.logoFile : _b.signatureFile).isNotEmpty)
                            TextButton(
                              onPressed: () => setState(() => logo ? _b.logoFile = '' : _b.signatureFile = ''),
                              child: Text(tr('Entfernen', 'Remove')),
                            ),
                        ],
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
        if (widget.showSave) ...[
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerRight,
            child: GradientButton(label: _saved ? tr('Gesichert', 'Saved') : tr('Sichern', 'Save'), icon: Icons.check, onPressed: save),
          ),
        ],
      ],
    );
  }
}
