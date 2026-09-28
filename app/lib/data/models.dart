import 'package:runway_core/runway_core.dart';

class User {
  final String id;
  final String email;
  final String? displayName;
  final int monthlySavingsGoalSen;

  const User({
    required this.id,
    required this.email,
    this.displayName,
    this.monthlySavingsGoalSen = 0,
  });

  factory User.fromJson(Map<String, dynamic> j) => User(
    id: j['id'] as String,
    email: j['email'] as String,
    displayName: j['displayName'] as String?,
    monthlySavingsGoalSen: j['monthlySavingsGoalSen'] as int? ?? 0,
  );

  String get greetingName {
    final n = displayName?.trim();
    if (n != null && n.isNotEmpty) return n.split(' ').first;
    return email.split('@').first;
  }
}

class Category {
  final String id;
  final EntryKind kind;
  final String label;
  final int sortOrder;

  const Category({
    required this.id,
    required this.kind,
    required this.label,
    required this.sortOrder,
  });

  factory Category.fromJson(Map<String, dynamic> j) => Category(
    id: j['id'] as String,
    kind: EntryKind.tryParse(j['kind'] as String)!,
    label: j['label'] as String,
    sortOrder: j['sortOrder'] as int,
  );
}

class Entry {
  final String id;
  final EntryKind kind;
  final int amountSen;
  final String categoryId;
  final String? note;
  final LocalDate occurredOn;
  final String? billId;

  const Entry({
    required this.id,
    required this.kind,
    required this.amountSen,
    required this.categoryId,
    required this.occurredOn,
    this.note,
    this.billId,
  });

  factory Entry.fromJson(Map<String, dynamic> j) => Entry(
    id: j['id'] as String,
    kind: EntryKind.tryParse(j['kind'] as String)!,
    amountSen: j['amountSen'] as int,
    categoryId: j['categoryId'] as String,
    note: j['note'] as String?,
    occurredOn: LocalDate.tryParse(j['occurredOn'] as String)!,
    billId: j['billId'] as String?,
  );

  bool get isIncome => kind == EntryKind.income;

  BudgetEntry toBudget() => BudgetEntry(
    kind: kind,
    amountSen: amountSen,
    occurredOn: occurredOn,
    categoryId: categoryId,
    billId: billId,
  );
}

class Bill {
  final String id;
  final String name;
  final int amountSen;
  final int dueDay;
  final String categoryId;
  final bool active;
  final LocalDate? paidOn;

  const Bill({
    required this.id,
    required this.name,
    required this.amountSen,
    required this.dueDay,
    required this.categoryId,
    this.active = true,
    this.paidOn,
  });

  factory Bill.fromJson(Map<String, dynamic> j) => Bill(
    id: j['id'] as String,
    name: j['name'] as String,
    amountSen: j['amountSen'] as int,
    dueDay: j['dueDay'] as int,
    categoryId: j['categoryId'] as String,
    active: j['active'] as bool? ?? true,
    paidOn: LocalDate.tryParse(j['paidOn'] as String?),
  );

  bool get isPaid => paidOn != null;
}

enum BillState { paid, dueLater, dueToday, overdue, unpaidPast, upcoming }

/// Paid / Due in N days / Overdue, as seen on [today] while viewing [month].
({BillState state, String label}) billStatus(
  Bill bill,
  YearMonth month,
  LocalDate today,
) {
  if (bill.isPaid) {
    final p = bill.paidOn!;
    return (
      state: BillState.paid,
      label: 'Paid ${p.day} ${monthShortNames[p.month - 1]}',
    );
  }
  final dueDay = bill.dueDay.clamp(1, month.days);
  final cmp = month.compareTo(today.yearMonth);
  if (cmp < 0) return (state: BillState.unpaidPast, label: 'Not paid');
  if (cmp > 0) {
    return (
      state: BillState.upcoming,
      label: 'Due $dueDay ${monthShortNames[month.month - 1]}',
    );
  }
  final diff = dueDay - today.day;
  if (diff == 0) return (state: BillState.dueToday, label: 'Due today');
  if (diff > 0) {
    return (
      state: BillState.dueLater,
      label: diff == 1 ? 'Due tomorrow' : 'Due in $diff days',
    );
  }
  final late = -diff;
  return (
    state: BillState.overdue,
    label: late == 1 ? 'Overdue by 1 day' : 'Overdue by $late days',
  );
}

class MonthData {
  final YearMonth month;
  final int savingsGoalSen;
  final List<Entry> entries;
  final List<Bill> bills;

  /// Category id -> monthly limit in sen.
  final Map<String, int> limits;
  final int previousLeftOverSen;
  final bool alreadyCarried;

  const MonthData({
    required this.month,
    required this.savingsGoalSen,
    required this.entries,
    required this.bills,
    required this.limits,
    required this.previousLeftOverSen,
    required this.alreadyCarried,
  });

  factory MonthData.fromJson(Map<String, dynamic> j) {
    final carry = j['carryOver'] as Map<String, dynamic>;
    return MonthData(
      month: YearMonth.tryParse(j['month'] as String)!,
      savingsGoalSen: j['savingsGoalSen'] as int,
      entries: [
        for (final e in j['entries'] as List)
          Entry.fromJson(e as Map<String, dynamic>),
      ],
      bills: [
        for (final b in j['bills'] as List)
          Bill.fromJson(b as Map<String, dynamic>),
      ],
      limits: {
        for (final l in j['limits'] as List)
          (l as Map)['categoryId'] as String: l['monthlyLimitSen'] as int,
      },
      previousLeftOverSen: carry['previousLeftOverSen'] as int,
      alreadyCarried: carry['alreadyCarried'] as bool,
    );
  }

  /// The same budget math the server uses, for the device's today.
  MonthSummary summary(LocalDate today) => summarizeMonth(
    month: month,
    today: today,
    entries: [for (final e in entries) e.toBudget()],
    bills: [
      for (final b in bills)
        BudgetBill(id: b.id, amountSen: b.amountSen, active: b.active),
    ],
    savingsGoalSen: savingsGoalSen,
  );

  /// Carry-over is offered on the current or a future month when last month
  /// ended with money left and it has not been carried yet.
  bool canCarryOver(LocalDate today) =>
      previousLeftOverSen > 0 &&
      !alreadyCarried &&
      month.compareTo(today.yearMonth) >= 0;
}
