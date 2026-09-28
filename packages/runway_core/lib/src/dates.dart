/// A calendar date with no time or time zone ("2026-09-28").
///
/// Budget math works on the user's local calendar, so it never touches
/// [DateTime] with a time component.
class LocalDate implements Comparable<LocalDate> {
  final int year;
  final int month;
  final int day;

  LocalDate(this.year, this.month, this.day) {
    if (month < 1 || month > 12) {
      throw ArgumentError.value(month, 'month', 'must be 1-12');
    }
    if (day < 1 || day > daysInMonth(year, month)) {
      throw ArgumentError.value(day, 'day', 'not in $year-$month');
    }
  }

  /// Parses `yyyy-mm-dd`. Returns null for anything else, including
  /// impossible dates like 2026-02-30.
  static LocalDate? tryParse(String? s) {
    if (s == null) return null;
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
    if (m == null) return null;
    final y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!);
    if (mo < 1 || mo > 12 || d < 1 || d > daysInMonth(y, mo)) return null;
    return LocalDate(y, mo, d);
  }

  factory LocalDate.fromDateTime(DateTime dt) =>
      LocalDate(dt.year, dt.month, dt.day);

  YearMonth get yearMonth => YearMonth(year, month);

  LocalDate addDays(int n) {
    final dt = DateTime.utc(year, month, day + n);
    return LocalDate(dt.year, dt.month, dt.day);
  }

  @override
  int compareTo(LocalDate other) =>
      (year - other.year) * 10000 +
      (month - other.month) * 100 +
      (day - other.day);

  bool isBefore(LocalDate other) => compareTo(other) < 0;
  bool isAfter(LocalDate other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) =>
      other is LocalDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() =>
      '${year.toString().padLeft(4, '0')}-${_two(month)}-${_two(day)}';
}

/// A calendar month ("2026-09").
class YearMonth implements Comparable<YearMonth> {
  final int year;
  final int month;

  YearMonth(this.year, this.month) {
    if (month < 1 || month > 12) {
      throw ArgumentError.value(month, 'month', 'must be 1-12');
    }
  }

  /// Parses `yyyy-mm`, or returns null.
  static YearMonth? tryParse(String? s) {
    if (s == null) return null;
    final m = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(s);
    if (m == null) return null;
    final y = int.parse(m[1]!), mo = int.parse(m[2]!);
    if (y < 2000 || y > 2100 || mo < 1 || mo > 12) return null;
    return YearMonth(y, mo);
  }

  int get days => daysInMonth(year, month);
  LocalDate get first => LocalDate(year, month, 1);
  LocalDate get last => LocalDate(year, month, days);

  YearMonth get previous =>
      month == 1 ? YearMonth(year - 1, 12) : YearMonth(year, month - 1);
  YearMonth get next =>
      month == 12 ? YearMonth(year + 1, 1) : YearMonth(year, month + 1);

  bool contains(LocalDate d) => d.year == year && d.month == month;

  @override
  int compareTo(YearMonth other) =>
      (year - other.year) * 100 + (month - other.month);

  @override
  bool operator ==(Object other) =>
      other is YearMonth && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);

  @override
  String toString() => '${year.toString().padLeft(4, '0')}-${_two(month)}';
}

int daysInMonth(int year, int month) => DateTime.utc(year, month + 1, 0).day;

String _two(int n) => n.toString().padLeft(2, '0');

const monthShortNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

const monthLongNames = [
  'January', 'February', 'March', 'April', 'May', 'June', //
  'July', 'August', 'September', 'October', 'November', 'December',
];
