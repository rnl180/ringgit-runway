import 'package:runway_core/runway_core.dart';

import 'http_util.dart';

/// Largest amount we accept anywhere: RM 1,000,000.00.
const maxAmountSen = 100000000;

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);

bool isUuid(String? s) => s != null && _uuid.hasMatch(s);

Never _bad(String message) => throw ApiError.badRequest(message);

/// Typed reads from a decoded JSON body, throwing messages a student can act on.
class Fields {
  final Map<String, Object?> _m;
  Fields(this._m);

  bool has(String key) => _m.containsKey(key);

  /// Amount in sen: a whole number, more than zero (or zero if [allowZero]).
  int amountSen(String key, {String label = 'Amount', bool allowZero = false}) {
    final v = _m[key];
    if (v == null) _bad('$label is required.');
    if (v is! int) {
      _bad(
        v is num
            ? '$label must be sent in whole sen (RM 12.50 = 1250).'
            : '$label must be a number.',
      );
    }
    if (allowZero ? v < 0 : v <= 0) {
      _bad(
        allowZero
            ? "$label can't be negative."
            : '$label must be more than RM 0.',
      );
    }
    if (v > maxAmountSen) {
      _bad('$label must be at most ${formatRm(maxAmountSen)}.');
    }
    return v;
  }

  String requiredString(
    String key, {
    required String label,
    int maxLength = 200,
  }) {
    final v = optionalString(key, label: label, maxLength: maxLength);
    if (v == null) _bad('$label is required.');
    return v;
  }

  /// Trimmed string; empty becomes null.
  String? optionalString(
    String key, {
    required String label,
    int maxLength = 200,
  }) {
    final v = _m[key];
    if (v == null) return null;
    if (v is! String) _bad('$label must be text.');
    final t = v.trim();
    if (t.isEmpty) return null;
    if (t.length > maxLength) {
      _bad('$label must be at most $maxLength characters.');
    }
    return t;
  }

  LocalDate? optionalDate(String key, {String label = 'Date'}) {
    final v = _m[key];
    if (v == null) return null;
    final d = v is String ? LocalDate.tryParse(v) : null;
    if (d == null) _bad('$label must be a real date like 2026-09-28.');
    if (d.year < 2000 || d.year > 2100) {
      _bad('$label must be between 2000 and 2100.');
    }
    return d;
  }

  LocalDate requiredDate(String key, {String label = 'Date'}) =>
      optionalDate(key, label: label) ?? _bad('$label is required.');

  int intInRange(
    String key, {
    required String label,
    required int min,
    required int max,
  }) {
    final v = _m[key];
    if (v is! int || v < min || v > max) {
      _bad('$label must be a whole number from $min to $max.');
    }
    return v;
  }

  EntryKind kind(String key) =>
      EntryKind.tryParse(_m[key] is String ? _m[key] as String : null) ??
      _bad('Choose whether this is income or an expense.');

  String? optionalUuid(String key, {required String label}) {
    final v = _m[key];
    if (v == null) return null;
    if (v is! String || !isUuid(v)) _bad('$label is not valid.');
    return v.toLowerCase();
  }
}
