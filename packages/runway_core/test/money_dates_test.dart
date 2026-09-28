import 'package:runway_core/runway_core.dart';
import 'package:test/test.dart';

void main() {
  group('formatRm', () {
    test('formats sen as ringgit', () {
      expect(formatRm(0), 'RM 0.00');
      expect(formatRm(5), 'RM 0.05');
      expect(formatRm(123450), 'RM 1,234.50');
      expect(formatRm(100000000), 'RM 1,000,000.00');
      expect(formatRm(-1200), '-RM 12.00');
      expect(formatRm(123450, showSen: false), 'RM 1,234');
    });

    test('signed', () {
      expect(formatRmSigned(500), '+RM 5.00');
      expect(formatRmSigned(-500), '-RM 5.00');
    });
  });

  group('parseRmToSen', () {
    test('accepts what people type', () {
      expect(parseRmToSen('12'), 1200);
      expect(parseRmToSen('12.5'), 1250);
      expect(parseRmToSen('12.50'), 1250);
      expect(parseRmToSen('0.05'), 5);
      expect(parseRmToSen(' 1,200.00 '), 120000);
      expect(parseRmToSen('RM 7.90'), 790);
      expect(parseRmToSen('7.'), 700);
    });

    test('rejects the rest', () {
      for (final bad in ['', '.', 'abc', '-5', '1.234', '1e3', '12.5.0']) {
        expect(parseRmToSen(bad), isNull, reason: bad);
      }
    });

    test('no floating point drift', () {
      expect(parseRmToSen('0.29'), 29);
      expect(parseRmToSen('1.15'), 115);
    });
  });

  group('integer division', () {
    test('floorDiv rounds toward negative infinity', () {
      expect(floorDiv(7, 2), 3);
      expect(floorDiv(-7, 2), -4);
      expect(floorDiv(-6, 2), -3);
      expect(floorDiv(0, 5), 0);
      expect(() => floorDiv(1, 0), throwsArgumentError);
    });

    test('ceilDiv', () {
      expect(ceilDiv(7, 2), 4);
      expect(ceilDiv(6, 2), 3);
      expect(ceilDiv(-7, 2), -3);
    });
  });

  group('dates', () {
    test('parse and print', () {
      expect(LocalDate.tryParse('2026-09-28').toString(), '2026-09-28');
      expect(LocalDate.tryParse('2026-02-29'), isNull);
      expect(LocalDate.tryParse('2028-02-29'), isNotNull);
      expect(LocalDate.tryParse('2026-9-28'), isNull);
      expect(LocalDate.tryParse(null), isNull);
      expect(YearMonth.tryParse('2026-09').toString(), '2026-09');
      expect(YearMonth.tryParse('2026-13'), isNull);
      expect(YearMonth.tryParse('26-09'), isNull);
    });

    test('month arithmetic', () {
      expect(YearMonth(2026, 1).previous, YearMonth(2025, 12));
      expect(YearMonth(2026, 12).next, YearMonth(2027, 1));
      expect(YearMonth(2026, 2).days, 28);
      expect(YearMonth(2026, 9).last, LocalDate(2026, 9, 30));
      expect(LocalDate(2026, 9, 30).addDays(1), LocalDate(2026, 10, 1));
    });

    test('ordering', () {
      expect(LocalDate(2026, 9, 1).isBefore(LocalDate(2026, 9, 2)), isTrue);
      expect(LocalDate(2026, 10, 1).isAfter(LocalDate(2026, 9, 30)), isTrue);
      expect(YearMonth(2026, 9).compareTo(YearMonth(2027, 1)), lessThan(0));
    });
  });
}
