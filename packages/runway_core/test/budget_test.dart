import 'package:runway_core/runway_core.dart';
import 'package:test/test.dart';

LocalDate sep(int day) => LocalDate(2026, 9, day);
final september = YearMonth(2026, 9);

BudgetEntry income(int sen, LocalDate on, {String cat = 'allowance'}) =>
    BudgetEntry(
      kind: EntryKind.income,
      amountSen: sen,
      occurredOn: on,
      categoryId: cat,
    );

BudgetEntry expense(
  int sen,
  LocalDate on, {
  String cat = 'food',
  String? billId,
}) => BudgetEntry(
  kind: EntryKind.expense,
  amountSen: sen,
  occurredOn: on,
  categoryId: cat,
  billId: billId,
);

const rent = BudgetBill(id: 'rent', amountSen: 60000);
const phone = BudgetBill(id: 'phone', amountSen: 3000);

/// RM 1,500 allowance, rent RM 600 paid on the 1st, phone RM 30 unpaid,
/// RM 100 savings goal, and some food.
List<BudgetEntry> baseEntries({int todaySpend = 1500}) => [
  income(150000, sep(1)),
  expense(60000, sep(1), cat: 'housing', billId: 'rent'),
  expense(2000, sep(1)),
  expense(3000, sep(5)),
  if (todaySpend > 0) expense(todaySpend, sep(10)),
];

MonthSummary summarize(
  List<BudgetEntry> entries, {
  LocalDate? today,
  YearMonth? month,
  List<BudgetBill> bills = const [rent, phone],
  int savings = 10000,
}) => summarizeMonth(
  month: month ?? september,
  today: today ?? sep(10),
  entries: entries,
  bills: bills,
  savingsGoalSen: savings,
);

void main() {
  group('a normal mid-month day', () {
    final s = summarize(baseEntries());

    test('totals', () {
      expect(s.phase, MonthPhase.current);
      expect(s.incomeSen, 150000);
      expect(s.spentSen, 66500);
      expect(s.paidBillsSen, 60000);
      expect(s.unpaidBillsSen, 3000);
      expect(s.totalBillsSen, 63000);
      expect(s.savingsGoalSen, 10000);
    });

    test('left = income - spent - unpaid bills - savings', () {
      expect(s.leftSen, 150000 - 66500 - 3000 - 10000);
    });

    test('days left includes today', () {
      expect(s.daysLeft, 21); // 10..30
      expect(s.daysElapsed, 10);
    });

    test(
      'daily budget is this morning\'s budget, safe today subtracts today',
      () {
        expect(s.spentTodaySen, 1500);
        // (70500 + 1500) / 21 = 3428.57 -> floor
        expect(s.dailyBudgetSen, 3428);
        expect(s.safeTodaySen, 3428 - 1500);
        expect(s.overTodaySen, 0);
        expect(s.tomorrowDailyBudgetSen, isNull);
      },
    );

    test('pool and discretionary spend', () {
      expect(s.poolSen, 150000 - 63000 - 10000);
      expect(s.discretionarySpentSen, 6500);
      expect(s.leftSen, s.poolSen - s.discretionarySpentSen);
    });

    test('on track, no run-out day', () {
      expect(s.runOutDay, isNull);
      expect(s.status, BudgetStatus.onTrack);
      expect(statusMessage(s), 'At this pace your money lasts the month.');
    });

    test('chart data', () {
      expect(s.dailySpendingSen.length, 30);
      expect(s.dailySpendingSen[0], 2000); // rent excluded
      expect(s.dailySpendingSen[4], 3000);
      expect(s.dailySpendingSen[9], 1500);
      expect(
        s.dailySpendingSen.reduce((a, b) => a + b),
        s.discretionarySpentSen,
      );
      expect(s.dailyLineSen, 77000 ~/ 30);
      expect(s.spentByCategorySen, {'housing': 60000, 'food': 6500});
    });

    test('runway bar fractions', () {
      expect(s.monthElapsedFraction, closeTo(10 / 30, 1e-9));
      expect(s.poolUsedFraction, closeTo(6500 / 77000, 1e-9));
    });

    test('toJson carries integers only for money', () {
      final j = s.toJson();
      expect(j['safeTodaySen'], 1928);
      expect(j['status'], 'onTrack');
      expect(j['statusLabel'], 'On track');
      expect(j['runOutDay'], isNull);
      for (final k in j.keys.where((k) => k.endsWith('Sen'))) {
        expect(
          j[k],
          anyOf(isA<int>(), isNull, isA<List<int>>(), isA<Map<String, int>>()),
          reason: k,
        );
      }
    });
  });

  group('over today\'s budget', () {
    final s = summarize(baseEntries(todaySpend: 5000));

    test('safe today goes negative and tomorrow\'s budget is re-spread', () {
      // left = 150000 - 70000 - 3000 - 10000 = 67000
      expect(s.leftSen, 67000);
      expect(s.dailyBudgetSen, (67000 + 5000) ~/ 21);
      expect(s.safeTodaySen, 3428 - 5000);
      expect(s.overTodaySen, 1572);
      expect(s.tomorrowDailyBudgetSen, 67000 ~/ 20);
    });
  });

  group('spending fast', () {
    // RM 300 of day-to-day spending in 10 days against a RM 770 pool:
    // RM 30/day empties it on day ceil(770 / 30) = 26.
    final s = summarize([
      income(150000, sep(1)),
      expense(60000, sep(1), cat: 'housing', billId: 'rent'),
      expense(25000, sep(3)),
      expense(5000, sep(10)),
    ]);

    test('run-out day and status', () {
      expect(s.leftSen, greaterThanOrEqualTo(0));
      expect(s.runOutDay, sep(26));
      expect(s.status, BudgetStatus.spendingFast);
      expect(
        statusMessage(s),
        'At this pace your money runs out around 26 Sep.',
      );
    });

    test('run-out on the last day is not "spending fast"', () {
      // pool 77000, 10 days elapsed; spending 77000*10/30 = 25666.67/10 days
      // puts the run-out day at exactly 30.
      final t = summarize([
        income(150000, sep(1)),
        expense(60000, sep(1), cat: 'housing', billId: 'rent'),
        expense(25667, sep(4)),
      ]);
      expect(t.runOutDay, isNull);
      expect(t.status, BudgetStatus.onTrack);
    });

    test('exactly empty pool today runs out today', () {
      final t = summarize([
        income(150000, sep(1)),
        expense(60000, sep(1), cat: 'housing', billId: 'rent'),
        expense(77000, sep(4)),
      ]);
      expect(t.leftSen, 0);
      expect(t.runOutDay, sep(10));
      expect(t.status, BudgetStatus.spendingFast);
    });
  });

  group('over budget', () {
    final s = summarize([
      income(80000, sep(1)),
      expense(60000, sep(1), cat: 'housing', billId: 'rent'),
      expense(15000, sep(8)),
    ]);

    test('left below zero beats spending fast', () {
      // 80000 - 75000 - 3000 - 10000
      expect(s.leftSen, -8000);
      expect(s.status, BudgetStatus.overBudget);
      expect(statusMessage(s), "You're RM 80.00 over after bills and savings.");
    });

    test('negative daily budget rounds down, not toward zero', () {
      // -8000 / 21 = -380.95 -> -381
      expect(s.dailyBudgetSen, -381);
      expect(s.safeTodaySen, -381);
      expect(s.tomorrowDailyBudgetSen, floorDiv(-8000, 20));
    });
  });

  group('zero income', () {
    test('no entries at all', () {
      final s = summarize([]);
      expect(s.incomeSen, 0);
      expect(s.status, BudgetStatus.noIncome);
      expect(s.leftSen, -73000); // bills + savings still reserved
      expect(s.poolSen, -73000);
      expect(s.runOutDay, isNull);
      expect(s.dailyLineSen, 0);
      expect(s.poolUsedFraction, 0);
      expect(statusMessage(s), contains('allowance'));
    });

    test('spending without income still says no income yet', () {
      final s = summarize([expense(1000, sep(10))], bills: [], savings: 0);
      expect(s.status, BudgetStatus.noIncome);
      expect(s.leftSen, -1000);
      expect(s.poolUsedFraction, 1);
    });
  });

  group('bills paid vs unpaid', () {
    List<BudgetEntry> entries({required bool phonePaid}) => [
      ...baseEntries(),
      if (phonePaid) expense(3000, sep(10), cat: 'phone', billId: 'phone'),
    ];

    test(
      'paying a bill moves it from unpaid to spent without changing left',
      () {
        final before = summarize(entries(phonePaid: false));
        final after = summarize(entries(phonePaid: true));
        expect(before.unpaidBillsSen, 3000);
        expect(after.unpaidBillsSen, 0);
        expect(after.spentSen, before.spentSen + 3000);
        expect(after.leftSen, before.leftSen);
        expect(after.poolSen, before.poolSen);
        expect(after.safeTodaySen, before.safeTodaySen);
        expect(
          after.spentTodaySen,
          before.spentTodaySen,
          reason: 'bill payments excluded',
        );
        expect(after.discretionarySpentSen, before.discretionarySpentSen);
      },
    );

    test('bill paid for a different amount counts what was actually paid', () {
      final s = summarize([
        income(150000, sep(1)),
        expense(3500, sep(2), cat: 'phone', billId: 'phone'),
      ]);
      expect(s.paidBillsSen, 3500);
      expect(s.unpaidBillsSen, 60000);
      expect(s.totalBillsSen, 63500);
    });

    test('inactive bills are not reserved', () {
      final s = summarize(
        [income(150000, sep(1))],
        bills: [
          rent,
          const BudgetBill(id: 'gym', amountSen: 9000, active: false),
        ],
      );
      expect(s.unpaidBillsSen, 60000);
    });

    test('a bill paid last month is still due this month', () {
      final s = summarize([
        income(150000, sep(1)),
        expense(60000, LocalDate(2026, 8, 1), cat: 'housing', billId: 'rent'),
      ]);
      expect(s.unpaidBillsSen, 63000);
      expect(s.spentSen, 0);
    });
  });

  group('month edges', () {
    test('first day of the month', () {
      final s = summarize([income(150000, sep(1))], today: sep(1));
      expect(s.daysLeft, 30);
      expect(s.daysElapsed, 1);
      expect(s.dailyBudgetSen, (150000 - 63000 - 10000) ~/ 30);
    });

    test('last day: whole remainder is today\'s budget', () {
      final s = summarize([
        income(150000, sep(1)),
        expense(60000, sep(1), cat: 'housing', billId: 'rent'),
        expense(1000, sep(30)),
      ], today: sep(30));
      expect(s.daysLeft, 1);
      expect(s.dailyBudgetSen, s.leftSen + 1000);
      expect(s.safeTodaySen, s.leftSen);
    });

    test('last day over budget has no tomorrow', () {
      final s = summarize(
        [income(1000, sep(1)), expense(20000, sep(30))],
        bills: [],
        savings: 0,
        today: sep(30),
      );
      expect(s.safeTodaySen, -19000);
      expect(s.tomorrowDailyBudgetSen, isNull);
    });

    test('31-day month and leap February', () {
      final oct = summarize(
        [income(31000, LocalDate(2026, 10, 1))],
        month: YearMonth(2026, 10),
        today: LocalDate(2026, 10, 31),
        bills: [],
        savings: 0,
      );
      expect(oct.daysInMonth, 31);
      expect(oct.daysLeft, 1);
      final feb = summarize(
        [income(29000, LocalDate(2028, 2, 1))],
        month: YearMonth(2028, 2),
        today: LocalDate(2028, 2, 1),
        bills: [],
        savings: 0,
      );
      expect(feb.daysInMonth, 29);
      expect(feb.dailyBudgetSen, 1000);
    });

    test('entries outside the month are ignored', () {
      final s = summarize([
        income(150000, sep(1)),
        income(99900, LocalDate(2026, 8, 31)),
        expense(5000, LocalDate(2026, 10, 1)),
      ]);
      expect(s.incomeSen, 150000);
      expect(s.spentSen, 0);
    });
  });

  group('past and future months', () {
    test('past month shows left over, no daily numbers', () {
      final aug = YearMonth(2026, 8);
      final s = summarize([
        income(150000, LocalDate(2026, 8, 1)),
        expense(60000, LocalDate(2026, 8, 1), cat: 'housing', billId: 'rent'),
        expense(70000, LocalDate(2026, 8, 20)),
      ], month: aug);
      expect(s.phase, MonthPhase.past);
      expect(s.leftOverSen, 20000);
      expect(s.daysLeft, 0);
      expect(s.dailyBudgetSen, isNull);
      expect(s.safeTodaySen, isNull);
      expect(s.runOutDay, isNull);
      expect(s.status, BudgetStatus.onTrack);
      expect(statusMessage(s), 'You finished with RM 200.00 left over.');
      expect(s.monthElapsedFraction, 1);
    });

    test('past month that overspent', () {
      final s = summarize(
        [
          income(10000, LocalDate(2026, 8, 1)),
          expense(12000, LocalDate(2026, 8, 3)),
        ],
        month: YearMonth(2026, 8),
        bills: [],
        savings: 0,
      );
      expect(s.status, BudgetStatus.overBudget);
      expect(statusMessage(s), 'You spent RM 20.00 more than came in.');
    });

    test('future month spreads over every day', () {
      final s = summarize([
        income(150000, LocalDate(2026, 10, 1)),
      ], month: YearMonth(2026, 10));
      expect(s.phase, MonthPhase.future);
      expect(s.daysLeft, 31);
      expect(s.daysElapsed, 0);
      expect(s.spentTodaySen, 0);
      expect(s.dailyBudgetSen, floorDiv(150000 - 63000 - 10000, 31));
      expect(s.monthElapsedFraction, 0);
    });
  });
}
