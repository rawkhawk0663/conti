import 'package:flutter/material.dart';

import '../../app/l10n.dart';
import '../../app/theme.dart';
import '../../core/conti_state.dart';
import '../../core/dates.dart';
import '../../core/model/account.dart';
import '../../core/model/synced.dart';
import '../../core/money.dart';
import '../../widgets/visuals.dart';

class AccountsPage extends StatelessWidget {
  const AccountsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = ContiScope.of(context);
    final c = context.conti;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Konten', 'Accounts'))),
      floatingActionButton: GradientFab(
        label: tr('Konto', 'Account'),
        icon: Icons.add,
        onPressed: () => editAccount(context, null),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                child: Text(
                  tr(
                    'Wo dein Geld liegt: Bank, PostFinance, Bargeld, TWINT … Jede Buchung gehört zu einem Konto. Der Anfangsbestand ist der Kontostand am Anfangsdatum.',
                    'Where your money is: bank, PostFinance, cash, TWINT … Every entry belongs to an account. The opening balance is the balance on the start date.',
                  ),
                  style: TextStyle(color: c.muted),
                ),
              ),
              Card(
                child: Column(
                  children: [
                    for (final a in s.accounts)
                      ListTile(
                        leading: Icon(_icon(a.type)),
                        title: Text(a.name),
                        subtitle: Text(
                          [a.type.label, if (a.archived) tr('archiviert', 'archived'), if (a.iban.isNotEmpty) a.iban].join(' · '),
                        ),
                        trailing: AmountText(s.balance(a.id), colored: false, sign: false),
                        onTap: () => editAccount(context, a),
                      ),
                    if (s.accounts.isEmpty)
                      Padding(padding: const EdgeInsets.all(20), child: Text(tr('Noch keine Konten.', 'No accounts yet.'))),
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

IconData _icon(AccountType t) => switch (t) {
  AccountType.bank => Icons.account_balance_outlined,
  AccountType.post => Icons.local_post_office_outlined,
  AccountType.cash => Icons.payments_outlined,
  AccountType.twint => Icons.phone_iphone,
  AccountType.card => Icons.credit_card,
  AccountType.other => Icons.wallet_outlined,
};

/// Konto anlegen ([a] == null) oder ändern.
Future<void> editAccount(BuildContext context, Account? a) async {
  final s = ContiScope.read(context);
  final acc = a?.copy() ?? Account(id: newId(), name: '', order: s.accounts.length);
  final name = TextEditingController(text: acc.name);
  final opening = TextEditingController(text: acc.opening == 0 ? '' : Money.forInput(acc.opening));
  final iban = TextEditingController(text: acc.iban);
  String? error;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(a == null ? tr('Neues Konto', 'New account') : tr('Konto', 'Account')),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  autofocus: a == null,
                  decoration: InputDecoration(labelText: tr('Name', 'Name'), hintText: tr('z. B. UBS Privatkonto', 'e.g. Main bank account')),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<AccountType>(
                  initialValue: acc.type,
                  decoration: InputDecoration(labelText: tr('Art', 'Type')),
                  items: [for (final t in AccountType.values) DropdownMenuItem(value: t, child: Text(t.label))],
                  onChanged: (v) => setState(() => acc.type = v ?? acc.type),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: opening,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                        decoration: InputDecoration(labelText: tr('Anfangsbestand CHF', 'Opening balance CHF'), hintText: '0.00'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: acc.openingDate,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(Day.today().year + 1, 12, 31),
                          );
                          if (d != null) setState(() => acc.openingDate = d);
                        },
                        child: InputDecorator(
                          decoration: InputDecoration(labelText: tr('am', 'on')),
                          child: Text(Day.short(acc.openingDate)),
                        ),
                      ),
                    ),
                  ],
                ),
                if (acc.type == AccountType.bank || acc.type == AccountType.post) ...[
                  const SizedBox(height: 14),
                  TextField(controller: iban, decoration: const InputDecoration(labelText: 'IBAN (optional)')),
                ],
                if (a != null)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr('Archiviert', 'Archived')),
                    subtitle: Text(tr('Erscheint nicht mehr bei neuen Buchungen.', 'No longer offered for new entries.')),
                    value: acc.archived,
                    onChanged: (v) => setState(() => acc.archived = v),
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
          if (a != null)
            TextButton(
              onPressed: () async {
                if (s.accountInUse(a.id)) {
                  setState(
                    () => error = tr(
                      'Dieses Konto hat Buchungen und kann nicht gelöscht werden. Du kannst es archivieren.',
                      'This account has entries and cannot be deleted. You can archive it.',
                    ),
                  );
                  return;
                }
                await s.deleteAccount(a.copy());
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
              final o = opening.text.trim().isEmpty ? 0 : Money.parse(opening.text);
              if (o == null) {
                setState(() => error = tr('Der Anfangsbestand ist keine Zahl.', 'The opening balance is not a number.'));
                return;
              }
              acc
                ..name = name.text.trim()
                ..opening = o
                ..iban = iban.text.trim();
              Navigator.pop(context, true);
            },
            child: Text(tr('Sichern', 'Save')),
          ),
        ],
      ),
    ),
  );
  if (ok == true) await s.saveAccount(acc);
}
