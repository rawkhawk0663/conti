import '../model/closing.dart';
import '../model/entry.dart';

/// Eine Anlage, die abgeschrieben wird: entweder aus einer Buchung
/// (Anschaffung in Conti) oder eine Anlage ohne Buchung ([Asset]).
class FixedAsset {
  FixedAsset({
    required this.id,
    required this.info,
    required this.acquired,
    required this.cost,
    required this.startYear,
    required this.startValue,
    this.entryId,
    this.assetId,
  });

  /// Aus einer Buchung mit Anschaffung.
  factory FixedAsset.fromEntry(Entry e, AssetInfo info) => FixedAsset(
    id: 'entry-${e.id}',
    info: info,
    acquired: e.date,
    cost: e.amount,
    startYear: e.date.year,
    startValue: e.amount,
    entryId: e.id,
  );

  /// Aus einer Anlage ohne Buchung.
  factory FixedAsset.fromAsset(Asset a) => FixedAsset(
    id: 'asset-${a.id}',
    info: a.info,
    acquired: a.acquired,
    cost: a.cost,
    startYear: a.openingYear,
    startValue: a.openingYear <= a.acquired.year ? a.cost : a.openingValue,
    assetId: a.id,
  );

  final String id;
  final AssetInfo info;
  final DateTime acquired;
  final int cost;

  /// Ab diesem Jahr wird gerechnet, mit dem Wert [startValue] am Jahresanfang.
  final int startYear;
  final int startValue;
  final String? entryId;
  final String? assetId;

  String get name => info.name;

  /// Im Jahr [year] gekauft (in Conti gebucht): am 1. Januar noch nicht da.
  bool boughtIn(int year) => entryId != null && acquired.year == year;

  /// Werte im Jahr [year]: Restwert am Anfang, Abschreibung, Restwert am Ende.
  /// Vor dem ersten Jahr oder nach dem Verkauf: alles 0.
  DepYear yearOf(int year) {
    if (year < startYear) return const DepYear(0, 0, 0);
    var value = startValue;
    for (var y = startYear; y <= year; y++) {
      final sold = info.soldYear;
      if (sold != null && y > sold) return const DepYear(0, 0, 0);
      final dep = sold == y ? value : Depreciation.amount(info, cost: cost, value: value);
      if (y == year) return DepYear(value, dep, value - dep);
      value -= dep;
    }
    return const DepYear(0, 0, 0);
  }
}

/// Werte einer Anlage in einem Jahr (Rappen).
class DepYear {
  const DepYear(this.start, this.depreciation, this.end);

  final int start;
  final int depreciation;
  final int end;
}

class Depreciation {
  Depreciation._();

  /// Erinnerungsfranken: eine Anlage bleibt mit CHF 1 stehen, solange man sie hat.
  static const memo = 100;

  /// Unter diesem Restwert wird der Rest auf einmal abgeschrieben.
  static const smallRest = 1000;

  /// Abschreibung eines Jahres bei Restwert [value].
  static int amount(AssetInfo info, {required int cost, required int value}) {
    if (value <= memo) return 0;
    final room = value - memo;
    int dep;
    switch (info.method) {
      case DepMethod.immediate:
        dep = room;
      case DepMethod.linear:
        dep = (cost * info.rate / 100).round();
      case DepMethod.degressive:
        dep = (value * info.rate / 100).round();
    }
    if (dep >= room || value - dep < smallRest) return room;
    return dep < 0 ? 0 : dep;
  }
}
