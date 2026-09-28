import 'package:flutter_test/flutter_test.dart';
import 'package:ringgit_runway/data/models.dart';
import 'package:runway_core/runway_core.dart';

void main() {
  final sep = YearMonth(2026, 9);
  Bill bill({int day = 15, LocalDate? paidOn}) => Bill(
    id: 'b',
    name: 'Phone plan',
    amountSen: 3000,
    dueDay: day,
    categoryId: 'phone',
    paidOn: paidOn,
  );

  group('billStatus', () {
    test('paid', () {
      final s = billStatus(
        bill(paidOn: LocalDate(2026, 9, 3)),
        sep,
        LocalDate(2026, 9, 10),
      );
      expect(s.state, BillState.paid);
      expect(s.label, 'Paid 3 Sep');
    });

    test('due later, tomorrow, today, overdue', () {
      expect(
        billStatus(bill(), sep, LocalDate(2026, 9, 10)).label,
        'Due in 5 days',
      );
      expect(
        billStatus(bill(), sep, LocalDate(2026, 9, 14)).label,
        'Due tomorrow',
      );
      expect(
        billStatus(bill(), sep, LocalDate(2026, 9, 15)).state,
        BillState.dueToday,
      );
      expect(
        billStatus(bill(), sep, LocalDate(2026, 9, 16)).label,
        'Overdue by 1 day',
      );
      expect(
        billStatus(bill(), sep, LocalDate(2026, 9, 20)).label,
        'Overdue by 5 days',
      );
    });

    test('due day 31 in a 30-day month is the 30th', () {
      expect(
        billStatus(bill(day: 31), sep, LocalDate(2026, 9, 30)).state,
        BillState.dueToday,
      );
    });

    test('past and future months', () {
      expect(billStatus(bill(), sep, LocalDate(2026, 10, 2)).label, 'Not paid');
      expect(
        billStatus(bill(), sep, LocalDate(2026, 8, 20)).label,
        'Due 15 Sep',
      );
    });
  });

  test('carry over only when there is something left and not yet carried', () {
    MonthData m(int left, bool carried, YearMonth month) => MonthData(
      month: month,
      savingsGoalSen: 0,
      entries: const [],
      bills: const [],
      limits: const {},
      previousLeftOverSen: left,
      alreadyCarried: carried,
    );
    final today = LocalDate(2026, 9, 10);
    expect(m(100, false, sep).canCarryOver(today), isTrue);
    expect(m(0, false, sep).canCarryOver(today), isFalse);
    expect(m(100, true, sep).canCarryOver(today), isFalse);
    expect(m(100, false, YearMonth(2026, 8)).canCarryOver(today), isFalse);
  });
}
