import 'dates.dart';
import 'money.dart';

enum EntryKind {
  income,
  expense;

  static EntryKind? tryParse(String? s) => switch (s) {
    'income' => EntryKind.income,
    'expense' => EntryKind.expense,
    _ => null,
  };
}

/// One income or expense line, as far as the budget math cares.
class BudgetEntry {
  final EntryKind kind;
  final int amountSen;
  final LocalDate occurredOn;
  final String categoryId;

  /// Set when this expense is the payment of a fixed bill.
  final String? billId;

  const BudgetEntry({
    required this.kind,
    required this.amountSen,
    required this.occurredOn,
    required this.categoryId,
    this.billId,
  });

  bool get isBillPayment => kind == EntryKind.expense && billId != null;
}

/// A fixed monthly bill (rent, phone plan).
class BudgetBill {
  final String id;
  final int amountSen;
  final bool active;

  const BudgetBill({
    required this.id,
    required this.amountSen,
    this.active = true,
  });
}

enum BudgetStatus {
  noIncome('No income yet'),
  overBudget('Over budget'),
  spendingFast('Spending fast'),
  onTrack('On track');

  final String label;
  const BudgetStatus(this.label);
}

/// Where the viewed month sits relative to today.
enum MonthPhase { past, current, future }

/// Everything the Home and Insights screens show for one month.
/// All money fields are integer sen.
class MonthSummary {
  final YearMonth month;
  final MonthPhase phase;
  final int daysInMonth;

  final int incomeSen;
  final int spentSen;
  final int paidBillsSen;
  final int unpaidBillsSen;
  final int totalBillsSen;
  final int savingsGoalSen;

  /// income − spent − unpaidBills − savingsGoal.
  final int leftSen;

  /// income − totalBills − savingsGoal: money for day-to-day spending.
  final int poolSen;

  /// spent − paid bill amounts.
  final int discretionarySpentSen;

  /// Days from today to month end including today. 0 for past months.
  final int daysLeft;

  /// Days of the month that have started, including today.
  final int daysElapsed;

  /// Expenses dated today, excluding bill payments.
  final int spentTodaySen;

  /// Today's budget as it stood this morning. Null for past months.
  final int? dailyBudgetSen;

  /// dailyBudget − spentToday: the hero number. Null for past months.
  final int? safeTodaySen;

  /// When [safeTodaySen] is negative: the daily budget from tomorrow,
  /// left / (daysLeft − 1). Null otherwise or on the last day.
  final int? tomorrowDailyBudgetSen;

  /// Day the pool empties at the current pace, if before the last day.
  final LocalDate? runOutDay;

  /// income − spent. What past months show instead of daily numbers.
  final int leftOverSen;

  final BudgetStatus status;

  /// Discretionary spending (bill payments excluded) per day, index 0 = day 1.
  final List<int> dailySpendingSen;

  /// pool / daysInMonth: the dashed line on the daily chart.
  final int dailyLineSen;

  /// Every expense (bills included) summed by category id.
  final Map<String, int> spentByCategorySen;

  const MonthSummary({
    required this.month,
    required this.phase,
    required this.daysInMonth,
    required this.incomeSen,
    required this.spentSen,
    required this.paidBillsSen,
    required this.unpaidBillsSen,
    required this.totalBillsSen,
    required this.savingsGoalSen,
    required this.leftSen,
    required this.poolSen,
    required this.discretionarySpentSen,
    required this.daysLeft,
    required this.daysElapsed,
    required this.spentTodaySen,
    required this.dailyBudgetSen,
    required this.safeTodaySen,
    required this.tomorrowDailyBudgetSen,
    required this.runOutDay,
    required this.leftOverSen,
    required this.status,
    required this.dailySpendingSen,
    required this.dailyLineSen,
    required this.spentByCategorySen,
  });

  /// Share of the month gone (0..1), for the runway bar.
  double get monthElapsedFraction => daysElapsed / daysInMonth;

  /// Share of the spending pool used (can exceed 1), for the runway bar.
  double get poolUsedFraction {
    if (poolSen > 0) return discretionarySpentSen / poolSen;
    return discretionarySpentSen > 0 ? 1 : 0;
  }

  /// How far over today's budget, when [safeTodaySen] is negative.
  int get overTodaySen =>
      (safeTodaySen != null && safeTodaySen! < 0) ? -safeTodaySen! : 0;

  Map<String, Object?> toJson() => {
    'month': month.toString(),
    'phase': phase.name,
    'daysInMonth': daysInMonth,
    'incomeSen': incomeSen,
    'spentSen': spentSen,
    'paidBillsSen': paidBillsSen,
    'unpaidBillsSen': unpaidBillsSen,
    'totalBillsSen': totalBillsSen,
    'savingsGoalSen': savingsGoalSen,
    'leftSen': leftSen,
    'poolSen': poolSen,
    'discretionarySpentSen': discretionarySpentSen,
    'daysLeft': daysLeft,
    'daysElapsed': daysElapsed,
    'spentTodaySen': spentTodaySen,
    'dailyBudgetSen': dailyBudgetSen,
    'safeTodaySen': safeTodaySen,
    'overTodaySen': overTodaySen,
    'tomorrowDailyBudgetSen': tomorrowDailyBudgetSen,
    'runOutDay': runOutDay?.toString(),
    'leftOverSen': leftOverSen,
    'status': status.name,
    'statusLabel': status.label,
    'dailySpendingSen': dailySpendingSen,
    'dailyLineSen': dailyLineSen,
    'spentByCategorySen': spentByCategorySen,
  };
}

/// Computes the budget for [month] as seen on [today] (the user's local
/// date). Entries outside [month] are ignored, so callers may pass extra.
MonthSummary summarizeMonth({
  required YearMonth month,
  required LocalDate today,
  required List<BudgetEntry> entries,
  required List<BudgetBill> bills,
  required int savingsGoalSen,
}) {
  final days = month.days;
  final todayMonth = today.yearMonth;
  final phase = month.compareTo(todayMonth) < 0
      ? MonthPhase.past
      : month == todayMonth
      ? MonthPhase.current
      : MonthPhase.future;

  var income = 0, spent = 0, paidBills = 0, spentToday = 0;
  final paidBillIds = <String>{};
  final daily = List<int>.filled(days, 0);
  final byCategory = <String, int>{};

  for (final e in entries) {
    if (!month.contains(e.occurredOn)) continue;
    if (e.kind == EntryKind.income) {
      income += e.amountSen;
      continue;
    }
    spent += e.amountSen;
    byCategory[e.categoryId] = (byCategory[e.categoryId] ?? 0) + e.amountSen;
    if (e.isBillPayment) {
      paidBills += e.amountSen;
      paidBillIds.add(e.billId!);
    } else {
      daily[e.occurredOn.day - 1] += e.amountSen;
      if (phase == MonthPhase.current && e.occurredOn == today) {
        spentToday += e.amountSen;
      }
    }
  }

  final unpaidBills = bills
      .where((b) => b.active && !paidBillIds.contains(b.id))
      .fold<int>(0, (sum, b) => sum + b.amountSen);
  final totalBills = paidBills + unpaidBills;
  final left = income - spent - unpaidBills - savingsGoalSen;
  final pool = income - totalBills - savingsGoalSen;
  final discretionary = spent - paidBills;
  final leftOver = income - spent;

  final (daysLeft, daysElapsed) = switch (phase) {
    MonthPhase.past => (0, days),
    MonthPhase.current => (days - today.day + 1, today.day),
    MonthPhase.future => (days, 0),
  };

  int? dailyBudget, safeToday, tomorrowBudget;
  if (phase != MonthPhase.past) {
    dailyBudget = floorDiv(left + spentToday, daysLeft);
    safeToday = dailyBudget - spentToday;
    if (safeToday < 0 && daysLeft > 1) {
      tomorrowBudget = floorDiv(left, daysLeft - 1);
    }
  }

  // Average daily discretionary spend so far, projected until the pool is
  // gone: the pool empties on day ceil(pool / average).
  LocalDate? runOutDay;
  if (phase == MonthPhase.current && pool > 0 && discretionary > 0) {
    final day = ceilDiv(pool * daysElapsed, discretionary);
    if (day < days) runOutDay = LocalDate(month.year, month.month, day);
  }

  final BudgetStatus status;
  if (income == 0) {
    status = BudgetStatus.noIncome;
  } else if ((phase == MonthPhase.past ? leftOver : left) < 0) {
    status = BudgetStatus.overBudget;
  } else if (runOutDay != null) {
    status = BudgetStatus.spendingFast;
  } else {
    status = BudgetStatus.onTrack;
  }

  return MonthSummary(
    month: month,
    phase: phase,
    daysInMonth: days,
    incomeSen: income,
    spentSen: spent,
    paidBillsSen: paidBills,
    unpaidBillsSen: unpaidBills,
    totalBillsSen: totalBills,
    savingsGoalSen: savingsGoalSen,
    leftSen: left,
    poolSen: pool,
    discretionarySpentSen: discretionary,
    daysLeft: daysLeft,
    daysElapsed: daysElapsed,
    spentTodaySen: spentToday,
    dailyBudgetSen: dailyBudget,
    safeTodaySen: safeToday,
    tomorrowDailyBudgetSen: tomorrowBudget,
    runOutDay: runOutDay,
    leftOverSen: leftOver,
    status: status,
    dailySpendingSen: daily,
    dailyLineSen: pool > 0 ? floorDiv(pool, days) : 0,
    spentByCategorySen: byCategory,
  );
}

/// One-line explanation under the status pill, e.g.
/// "At this pace your money runs out around 24 Sep".
String statusMessage(MonthSummary s) {
  switch (s.status) {
    case BudgetStatus.noIncome:
      return "Add this month's allowance or last month's leftover to start.";
    case BudgetStatus.overBudget:
      return s.phase == MonthPhase.past
          ? 'You spent ${formatRm(-s.leftOverSen)} more than came in.'
          : "You're ${formatRm(-s.leftSen)} over after bills and savings.";
    case BudgetStatus.spendingFast:
      final d = s.runOutDay!;
      return 'At this pace your money runs out around '
          '${d.day} ${monthShortNames[d.month - 1]}.';
    case BudgetStatus.onTrack:
      return s.phase == MonthPhase.past
          ? 'You finished with ${formatRm(s.leftOverSen)} left over.'
          : 'At this pace your money lasts the month.';
  }
}
