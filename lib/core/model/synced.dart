import 'package:uuid/uuid.dart';

import '../dates.dart';

const _uuid = Uuid();

/// Neue, weltweit eindeutige ID (damit zwei Geräte nie dieselbe vergeben).
String newId() => _uuid.v4();

/// Alles, was zwischen Geräten abgeglichen wird, hat eine ID, den Zeitpunkt
/// der letzten Änderung und kann gelöscht sein. Gelöschtes bleibt als
/// „Grabstein“ (`deleted: true`) erhalten, sonst würde es beim nächsten
/// Abgleich von einem anderen Gerät wieder auftauchen.
abstract class Synced {
  String get id;
  DateTime get updatedAt;
  bool get deleted;
  Map<String, dynamic> toJson();
}

/// Zwei Fassungen derselben Liste zusammenführen: pro ID gewinnt die jüngere
/// Änderung. Bei gleicher Zeit gewinnt [mine] (die eigene Fassung).
List<T> mergeById<T extends Synced>(Iterable<T> mine, Iterable<T> theirs) {
  final out = <String, T>{for (final x in mine) x.id: x};
  for (final t in theirs) {
    final m = out[t.id];
    if (m == null || t.updatedAt.isAfter(m.updatedAt)) out[t.id] = t;
  }
  return out.values.toList();
}

/// Hilfen zum Lesen von JSON, die bei fehlenden oder falschen Werten nicht
/// abstürzen, sondern einen Standardwert nehmen.
extension JsonRead on Map<String, dynamic> {
  String str(String k, [String fallback = '']) {
    final v = this[k];
    return v is String ? v : (v == null ? fallback : v.toString());
  }

  String? strOrNull(String k) {
    final v = this[k];
    if (v is String && v.isNotEmpty) return v;
    return null;
  }

  int integer(String k, [int fallback = 0]) {
    final v = this[k];
    if (v is int) return v;
    if (v is num) return v.round();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  double dbl(String k, [double fallback = 0]) {
    final v = this[k];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? fallback;
    return fallback;
  }

  bool flag(String k, [bool fallback = false]) {
    final v = this[k];
    return v is bool ? v : fallback;
  }

  DateTime stamp(String k) => Day.parseStamp(this[k] as String?);

  List<Map<String, dynamic>> maps(String k) {
    final v = this[k];
    if (v is! List) return const [];
    return [for (final e in v) if (e is Map) Map<String, dynamic>.from(e)];
  }
}
