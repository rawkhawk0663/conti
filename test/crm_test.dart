import 'dart:convert';
import 'dart:io';

import 'package:conti/app/l10n.dart';
import 'package:conti/app/reminders.dart';
import 'package:conti/core/conti_state.dart';
import 'package:conti/core/deadlines.dart';
import 'package:conti/core/import/legacy_import.dart';
import 'package:conti/core/model/account.dart';
import 'package:conti/core/model/business.dart';
import 'package:conti/core/model/category.dart';
import 'package:conti/core/model/crm.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late ContiState s;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('conti-crm-');
    s = ContiState(dir.path);
    await s.load();
    L10n.language.value = AppLanguage.de;
    await s.finishSetup();
  });
  tearDown(() => dir.delete(recursive: true));

  test('Einrichtung legt die vorgeschlagenen Auftragsarten an, einmal', () async {
    expect(s.orderKinds.map((k) => k.id), containsAll(['kind-gig', 'kind-abo']));
    expect(s.orderKind('kind-abo')!.subscription, isTrue);
    expect(s.orderKind('kind-abo')!.lessons, 5);
    // Gelöscht bleibt gelöscht, auch nach dem Neuladen.
    await s.saveOrderKind(s.orderKind('kind-gig')!.copy()..deleted = true);
    await s.reload();
    expect(s.orderKinds.any((k) => k.id == 'kind-gig'), isFalse);
  });

  test('Auftragsnummern zählen pro Jahr weiter', () async {
    expect(s.nextOrderNumber(DateTime(2026, 3, 1)), 'A-2026-0001');
    await s.saveOrder(Order(id: 'a', number: 'A-2026-0007', title: 'x'));
    await s.saveOrder(Order(id: 'b', number: 'A-2025-0012', title: 'y'));
    expect(s.nextOrderNumber(DateTime(2026, 3, 1)), 'A-2026-0008');
    expect(s.nextOrderNumber(DateTime(2025, 3, 1)), 'A-2025-0013');
  });

  test('Abo zählt Lektionen und meldet, wenn es aufgebraucht ist', () async {
    final o = Order(id: 'abo', number: 'A-2026-0001', title: '5er-Abo', kind: 'kind-abo', lessonsTotal: 3, clientId: 'c');
    await s.saveOrder(o);
    expect(s.usedUpSubscriptions, isEmpty);
    for (var i = 1; i <= 3; i++) {
      final x = s.order('abo')!.copy()..sessions.add(Session(id: 's$i', date: DateTime(2026, 1, i)));
      await s.saveOrder(x);
    }
    final x = s.order('abo')!;
    expect(x.lessonsUsed, 3);
    expect(x.lessonsLeft, 0);
    expect(x.subscriptionUsedUp, isTrue);
    expect(s.usedUpSubscriptions.single.id, 'abo');
    // Nach dem nächsten Abo keine Erinnerung mehr.
    await s.saveOrder(x.copy()..followUpId = 'next');
    expect(s.usedUpSubscriptions, isEmpty);
    // Abo-Angaben überleben das Speichern.
    final again = ContiState(dir.path);
    await again.load();
    expect(again.order('abo')!.lessonsTotal, 3);
    expect(again.order('abo')!.sessions.map((e) => e.id), ['s1', 's2', 's3']);
  });

  test('Fristen-Ampel', () {
    final rules = DeadlineRule.defaults(); // gelb 7, orange 4, rot 2
    final today = DateTime(2026, 11, 20);
    Urgency u(int days) => Urgency.of(Task(id: 't', title: 'x', due: today.add(Duration(days: days))), rules, today: today);
    expect(u(10).color, isNull);
    expect(u(7).color, parseHex('#FFC83D'));
    expect(u(3).color, parseHex('#FF8A4C'));
    expect(u(1).color, parseHex('#FF5A6E'));
    expect(u(0).label, 'Heute fällig');
    expect(u(-2).overdue, isTrue);
    expect(u(-2).label, '2 Tage überfällig');
    expect(Urgency.of(Task(id: 't', title: 'x', done: true, due: today), rules, today: today).color, isNull);
  });

  test('Erinnerungen werden für jede Ampel-Stufe und den Fälligkeitstag geplant', () async {
    await s.saveClient(Client(id: 'c', firstName: 'Erika', lastName: 'Muster'));
    await s.saveTask(Task(id: 't1', title: 'Offerte schicken', clientId: 'c', due: DateTime(2026, 12, 10)));
    await s.saveTask(Task(id: 't2', title: 'Erledigt', due: DateTime(2026, 12, 10), done: true));
    await s.saveTask(Task(id: 't3', title: 'Ohne Frist'));
    final plan = Reminders.plan(s, now: DateTime(2026, 11, 20, 12));
    expect(plan.map((r) => r.at).toList(), [
      DateTime(2026, 12, 3, 8),
      DateTime(2026, 12, 6, 8),
      DateTime(2026, 12, 8, 8),
      DateTime(2026, 12, 10, 8),
    ]);
    expect(plan.first.title, 'Frist in 7 Tagen');
    expect(plan.first.body, 'Offerte schicken · Erika Muster');
    expect(plan.last.title, 'Heute fällig');
    // Was schon vorbei ist, wird nicht geplant.
    expect(Reminders.plan(s, now: DateTime(2026, 12, 7, 9)).length, 2);
  });

  test('Importierte Aufträge bekommen eine Auftragsart', () async {
    final json = jsonDecode(File('test/fixtures/legacy_sample.json').readAsStringSync()) as Map<String, dynamic>;
    await s.mergeIn(categories: DefaultCategories.build(english: false));
    await s.saveAccount(Account(id: 'bank', name: 'Bank'));
    await LegacyImport.apply(s, LegacyImport.parse(json, existing: s.categories), accountId: 'bank');
    final o = s.order('o-1')!;
    expect(s.orderKind(o.kind)?.name, 'Musik');
    expect(s.kindLabel(o), 'Musik');
    expect(s.openAmountOf('c-1'), 0); // bezahlt
    expect(s.ordersOf('c-1').single.id, 'o-1');
    expect(s.tasksOf('c-1').single.done, isTrue);
    // Zweimal importieren: die Art gibt es nur einmal.
    await LegacyImport.apply(s, LegacyImport.parse(json, existing: s.categories), accountId: 'bank');
    await s.reload();
    expect(s.orderKinds.where((k) => k.name == 'Musik').length, 1);
  });

  test('Auftrag rechnet Positionen in Rappen', () {
    final o = Order(
      id: 'x',
      number: '1',
      title: 'Flyer',
      items: [
        OrderItem(id: 'a', name: 'Gestaltung', unit: PriceUnit.hour, quantity: 2.5, unitPrice: 7500),
        OrderItem(id: 'b', name: 'Druck', quantity: 1, unitPrice: 4990),
      ],
    );
    expect(o.total, 18750 + 4990);
  });

  test('Geschäft: Ampel-Regeln werden gespeichert', () async {
    final b = s.business.copy();
    b.deadlineRules.firstWhere((r) => r.id == 'yellow').days = 10;
    await s.saveBusiness(b);
    final again = ContiState(dir.path);
    await again.load();
    expect(again.business.deadlineRules.firstWhere((r) => r.id == 'yellow').days, 10);
    expect(Business().deadlineRules.length, 3);
  });
}
