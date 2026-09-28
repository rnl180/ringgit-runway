// Money is always an integer number of sen (RM 1.00 = 100 sen).

/// Formats sen as `RM 1,234.50`. Negative amounts get a leading minus:
/// `-RM 12.00`.
String formatRm(int sen, {bool showSen = true}) {
  final negative = sen < 0;
  final abs = sen.abs();
  final whole = abs ~/ 100;
  final cents = abs % 100;
  final grouped = _group(whole);
  final body = showSen
      ? '$grouped.${cents.toString().padLeft(2, '0')}'
      : grouped;
  return '${negative ? '-' : ''}RM $body';
}

/// Like [formatRm] but always shows a sign: `+RM 5.00` / `-RM 5.00`.
String formatRmSigned(int sen) =>
    sen >= 0 ? '+${formatRm(sen)}' : formatRm(sen);

String _group(int n) {
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

/// Parses what a person types into an amount field ("12", "12.5", "1,200.00",
/// "RM 7.90") into sen. Returns null for anything that is not a plain
/// non-negative amount with at most two decimals.
int? parseRmToSen(String input) {
  var s = input.trim().replaceAll(',', '').replaceAll(' ', '');
  if (s.toUpperCase().startsWith('RM')) s = s.substring(2);
  final m = RegExp(r'^(\d{1,9})(?:\.(\d{0,2}))?$').firstMatch(s);
  if (m == null) return null;
  final whole = int.parse(m[1]!);
  final frac = (m[2] ?? '').padRight(2, '0');
  return whole * 100 + int.parse(frac);
}

/// Floor division for integers (rounds toward negative infinity), so a
/// negative budget is never rounded up into looking smaller than it is.
int floorDiv(int a, int b) {
  if (b <= 0) throw ArgumentError.value(b, 'b', 'must be positive');
  return (a - a % b) ~/ b;
}

/// Ceiling division for a positive divisor.
int ceilDiv(int a, int b) => -floorDiv(-a, b);
