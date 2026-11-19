import 'package:flutter/material.dart';

import '../../app/l10n.dart';
import '../../app/theme.dart';
import '../../core/conti_state.dart';
import '../../core/model/account.dart';
import '../../core/model/category.dart';
import '../../core/model/synced.dart';
import '../../widgets/visuals.dart';
import '../import/import_screen.dart';
import '../settings/business_page.dart';
import '../sync/sync_page.dart';

/// Einrichtung beim ersten Start: Geschäft, Konten, Kanton. Oder gleich die
/// Daten aus der früheren App übernehmen.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

enum _Step { welcome, address, payment, taxes }

class _SetupScreenState extends State<SetupScreen> {
  _Step _step = _Step.welcome;
  final _form = GlobalKey<BusinessFormState>();
  bool _imported = false;

  /// Vorgeschlagene Konten (Art, an/aus).
  final Map<AccountType, bool> _accounts = {
    AccountType.bank: true,
    AccountType.cash: true,
    AccountType.twint: false,
    AccountType.post: false,
  };

  Future<void> _ensureCategories() async {
    final s = ContiScope.read(context);
    if (s.categories.isEmpty) {
      await s.mergeIn(categories: DefaultCategories.build(english: L10n.isEnglish));
    }
  }

  Future<void> _next() async {
    await _form.currentState?.save();
    if (!mounted) return;
    switch (_step) {
      case _Step.welcome:
        await _ensureCategories();
        setState(() => _step = _Step.address);
      case _Step.address:
        setState(() => _step = _Step.payment);
      case _Step.payment:
        setState(() => _step = _Step.taxes);
      case _Step.taxes:
        await _finish();
    }
  }

  void _back() => setState(() {
    _step = switch (_step) {
      _Step.welcome || _Step.address => _Step.welcome,
      _Step.payment => _Step.address,
      _Step.taxes => _imported ? _Step.welcome : _Step.payment,
    };
  });

  Future<void> _startImport() async {
    await _ensureCategories();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) => ImportScreen(
          onDone: () {
            Navigator.of(ctx).pop();
            setState(() {
              _imported = true;
              _step = _Step.taxes;
            });
          },
        ),
      ),
    );
  }

  Future<void> _finish() async {
    final s = ContiScope.read(context);
    if (s.accounts.isEmpty) {
      var order = 0;
      final now = DateTime.now();
      for (final e in _accounts.entries.where((e) => e.value)) {
        final t = e.key;
        await s.saveAccount(
          Account(
            id: newId(),
            name: t == AccountType.bank && s.business.bankName.isNotEmpty ? s.business.bankName : t.label,
            type: t,
            iban: t == AccountType.bank ? s.business.iban : '',
            openingDate: DateTime(now.year, 1, 1),
            order: order++,
          ),
        );
      }
    }
    await s.finishSetup();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.conti;
    final steps = _imported ? 1 : 3;
    final index = switch (_step) {
      _Step.welcome => 0,
      _Step.address => 1,
      _Step.payment => 2,
      _Step.taxes => _imported ? 1 : 3,
    };

    final Widget body = switch (_step) {
      _Step.welcome => _welcome(context),
      _Step.address => BusinessForm(key: _form, sections: BusinessSections.address),
      _Step.payment => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BusinessForm(key: _form, sections: BusinessSections.payment),
          const SizedBox(height: 14),
          SectionCard(
            title: tr('Welche Konten brauchst du?', 'Which accounts do you need?'),
            child: Column(
              children: [
                for (final t in _accounts.keys)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(t.label),
                    value: _accounts[t],
                    onChanged: (v) => setState(() => _accounts[t] = v ?? false),
                  ),
                Text(
                  tr('Weitere Konten und Anfangsbestände kannst du später unter Einstellungen → Konten eintragen.', 'You can add more accounts and opening balances later under Settings → Accounts.'),
                  style: TextStyle(color: c.muted, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
      _Step.taxes => BusinessForm(key: _form, sections: BusinessSections.taxes),
    };

    final title = switch (_step) {
      _Step.welcome => '',
      _Step.address => tr('Wer bist du?', 'Who are you?'),
      _Step.payment => tr('Wohin wird bezahlt?', 'Where do payments go?'),
      _Step.taxes => _imported ? tr('Fast fertig', 'Almost done') : tr('Steuern', 'Taxes'),
    };
    final hint = switch (_step) {
      _Step.welcome => '',
      _Step.address => tr(
        'Diese Angaben stehen später auf deinen Rechnungen. Du kannst alles jederzeit unter Einstellungen → Mein Geschäft ändern.',
        'These details will appear on your invoices. You can change everything anytime under Settings → My business.',
      ),
      _Step.payment => tr(
        'Auf diese IBAN zahlen deine Kundinnen und Kunden über den QR-Zahlteil.',
        'Your clients pay to this IBAN through the QR payment part.',
      ),
      _Step.taxes => tr(
        'Der Kanton bestimmt, wie der Jahresabschluss für die Steuererklärung aussieht.',
        'The canton decides how the year-end report for the tax return looks.',
      ),
    };

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
              children: [
                if (_step != _Step.welcome) ...[
                  Row(
                    children: [
                      IconButton(onPressed: _back, icon: const Icon(Icons.arrow_back)),
                      const SizedBox(width: 4),
                      Expanded(child: GradientBar(value: index / steps, colors: c.pink, height: 6)),
                      const SizedBox(width: 12),
                      Text('$index / $steps', style: TextStyle(color: c.muted)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(title, style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 8),
                  Text(hint, style: TextStyle(color: c.muted)),
                  const SizedBox(height: 20),
                ],
                body,
                if (_step != _Step.welcome) ...[
                  const SizedBox(height: 24),
                  Align(
                    alignment: Alignment.centerRight,
                    child: GradientButton(
                      label: _step == _Step.taxes ? tr('Los geht’s', 'Let’s go') : tr('Weiter', 'Next'),
                      icon: _step == _Step.taxes ? Icons.check : Icons.arrow_forward,
                      onPressed: _next,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _welcome(BuildContext context) {
    final s = ContiScope.of(context);
    final c = context.conti;
    Widget choice(IconData icon, List<Color> colors, String title, String text, VoidCallback onTap) => Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(gradient: LinearGradient(colors: colors), borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, color: Colors.white),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(text, style: TextStyle(color: c.muted)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        const Center(child: ContiMark(size: 88)),
        const SizedBox(height: 24),
        Text(
          tr('Willkommen bei Conti', 'Welcome to Conti'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text(
          tr(
            'Deine Buchhaltung: Einnahmen, Ausgaben, Belege und später Rechnungen mit QR-Zahlteil.',
            'Your bookkeeping: income, expenses, receipts and later invoices with a QR payment part.',
          ),
          textAlign: TextAlign.center,
          style: TextStyle(color: c.muted),
        ),
        const SizedBox(height: 20),
        Center(
          child: SegmentedButton<AppLanguage>(
            segments: [for (final l in AppLanguage.values) ButtonSegment(value: l, label: Text(l.label))],
            selected: {L10n.language.value},
            showSelectedIcon: false,
            onSelectionChanged: (v) => s.setLanguage(v.first),
          ),
        ),
        const SizedBox(height: 28),
        choice(
          Icons.auto_awesome,
          c.pink,
          tr('Neu einrichten', 'Set up from scratch'),
          tr('Name, Adresse, Konto und Kanton in drei kurzen Schritten.', 'Name, address, account and canton in three short steps.'),
          _next,
        ),
        const SizedBox(height: 12),
        choice(
          Icons.move_down,
          c.mint,
          tr('Aus der alten Buchhaltung übernehmen', 'Bring over from your old bookkeeping app'),
          tr('Buchungen, Kunden, Belege und Geschäftsangaben aus der .json-Datei.', 'Entries, clients, receipts and business details from the .json file.'),
          _startImport,
        ),
        const SizedBox(height: 12),
        choice(
          Icons.cloud_sync_outlined,
          c.sky,
          tr('Schon auf einem anderen Gerät eingerichtet', 'Already set up on another device'),
          tr('Mit Dropbox verbinden und alle Daten holen.', 'Connect to Dropbox and fetch all your data.'),
          () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SyncPage(join: true))),
        ),
        const SizedBox(height: 18),
        Text(
          tr(
            'Alles bleibt auf deinen Geräten und in deiner eigenen Dropbox. Conti hat kein Konto und keinen Server.',
            'Everything stays on your devices and in your own Dropbox. Conti has no account and no server.',
          ),
          textAlign: TextAlign.center,
          style: TextStyle(color: c.muted, fontSize: 13),
        ),
      ],
    );
  }
}
