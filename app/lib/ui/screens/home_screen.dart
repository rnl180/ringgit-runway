import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runway_core/runway_core.dart';

import '../../data/models.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'add_entry_sheet.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedMonthProvider);
    final today = ref.watch(todayProvider);
    final data = ref.watch(monthProvider(month));

    return AsyncView<MonthData>(
      value: data,
      onRetry: () => ref.invalidate(monthProvider(month)),
      builder: (d) {
        final s = d.summary(today);
        return RefreshIndicator(
          onRefresh: () => ref.refresh(monthProvider(month).future),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              PageWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (d.canCarryOver(today)) ...[
                      _CarryOverCard(data: d),
                      const SizedBox(height: 12),
                    ],
                    if (s.phase == MonthPhase.past)
                      _PastHero(s: s)
                    else
                      _HeroCard(s: s),
                    const SizedBox(height: 12),
                    if (s.status == BudgetStatus.noIncome) ...[
                      _NoIncomeCard(canCarry: d.canCarryOver(today)),
                      const SizedBox(height: 12),
                    ],
                    if (s.phase != MonthPhase.past) ...[
                      _RunwayCard(s: s),
                      const SizedBox(height: 12),
                    ],
                    _StatsGrid(s: s),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HeroCard extends StatelessWidget {
  final MonthSummary s;
  const _HeroCard({required this.s});

  @override
  Widget build(BuildContext context) {
    final safe = s.safeTodaySen!;
    final over = safe < 0;
    final isFuture = s.phase == MonthPhase.future;
    return Card(
      color: context.colors.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    isFuture
                        ? 'Daily budget for this month'
                        : 'Safe to spend today',
                    style: context.text.titleSmall?.copyWith(
                      color: context.colors.onPrimaryContainer,
                    ),
                  ),
                ),
                StatusPill(s.status),
              ],
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                formatRm(safe),
                key: const Key('safeToday'),
                style: context.text.displayMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: over
                      ? context.colors.error
                      : context.colors.onPrimaryContainer,
                  letterSpacing: -1,
                ),
              ),
            ),
            if (over) ...[
              const SizedBox(height: 4),
              Text(
                "You're ${formatRm(s.overTodaySen)} over today's budget."
                '${s.tomorrowDailyBudgetSen != null ? ' From tomorrow your daily budget is ${formatRm(s.tomorrowDailyBudgetSen!)}.' : ''}',
                style: context.text.bodyMedium?.copyWith(
                  color: context.colors.onPrimaryContainer,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              statusMessage(s),
              style: context.text.bodyMedium?.copyWith(
                color: context.colors.onPrimaryContainer,
              ),
            ),
            const Divider(height: 28),
            Row(
              children: [
                _HeroFact(
                  label: 'Daily budget',
                  value: formatRm(s.dailyBudgetSen!),
                ),
                _HeroFact(
                  label: 'Days left',
                  value: '${s.daysLeft}',
                  align: CrossAxisAlignment.center,
                ),
                _HeroFact(
                  label: 'Left after bills',
                  value: formatRm(s.leftSen),
                  align: CrossAxisAlignment.end,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroFact extends StatelessWidget {
  final String label;
  final String value;
  final CrossAxisAlignment align;
  const _HeroFact({
    required this.label,
    required this.value,
    this.align = CrossAxisAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    final color = context.colors.onPrimaryContainer;
    return Expanded(
      child: Column(
        crossAxisAlignment: align,
        children: [
          Text(
            label,
            style: context.text.labelMedium?.copyWith(
              color: color.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: context.text.titleMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PastHero extends StatelessWidget {
  final MonthSummary s;
  const _PastHero({required this.s});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Left over', style: context.text.titleSmall),
                ),
                StatusPill(s.status),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              formatRm(s.leftOverSen),
              key: const Key('leftOver'),
              style: context.text.displaySmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: s.leftOverSen < 0 ? context.colors.error : null,
              ),
            ),
            const SizedBox(height: 8),
            Text(statusMessage(s), style: context.text.bodyMedium),
          ],
        ),
      ),
    );
  }
}

class _RunwayCard extends StatelessWidget {
  final MonthSummary s;
  const _RunwayCard({required this.s});

  @override
  Widget build(BuildContext context) {
    final monthPct = (s.monthElapsedFraction * 100).round();
    final poolPct = (s.poolUsedFraction * 100).round();
    final ahead = s.poolUsedFraction > s.monthElapsedFraction + 0.02;
    final c = context.runway;
    final usedColor = s.poolUsedFraction > 1
        ? c.critical
        : ahead
        ? c.warning
        : c.good;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Runway', style: context.text.titleSmall),
            const SizedBox(height: 4),
            Text(
              ahead
                  ? 'You have used more of your spending money than of the month.'
                  : 'Your spending is keeping pace with the month.',
              style: context.text.bodySmall?.copyWith(color: c.muted),
            ),
            const SizedBox(height: 12),
            _Bar(
              label: 'Month gone',
              pct: monthPct,
              fraction: s.monthElapsedFraction,
              color: c.series,
            ),
            const SizedBox(height: 10),
            _Bar(
              label: 'Spending money used',
              pct: poolPct,
              fraction: s.poolUsedFraction,
              color: usedColor,
            ),
          ],
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  final String label;
  final int pct;
  final double fraction;
  final Color color;
  const _Bar({
    required this.label,
    required this.pct,
    required this.fraction,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label $pct percent',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: context.text.labelMedium)),
              Text(
                '$pct%',
                style: context.text.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction.clamp(0, 1).toDouble(),
              minHeight: 8,
              color: color,
              backgroundColor: context.runway.grid,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  final MonthSummary s;
  const _StatsGrid({required this.s});

  @override
  Widget build(BuildContext context) {
    final tiles = [
      ('Income', formatRm(s.incomeSen), Icons.south_west),
      ('Spent', formatRm(s.spentSen), Icons.north_east),
      if (s.phase != MonthPhase.past)
        ('Bills still due', formatRm(s.unpaidBillsSen), Icons.receipt_long),
      ('Saving', formatRm(s.savingsGoalSen), Icons.savings),
    ];
    return LayoutBuilder(
      builder: (context, box) {
        final w = (box.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final (label, value, icon) in tiles)
              SizedBox(
                width: w,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Icon(icon, size: 20, color: context.colors.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                label,
                                style: context.text.labelMedium?.copyWith(
                                  color: context.runway.muted,
                                ),
                              ),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  value,
                                  style: context.text.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _NoIncomeCard extends StatelessWidget {
  final bool canCarry;
  const _NoIncomeCard({required this.canCarry});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('No income yet this month', style: context.text.titleSmall),
            const SizedBox(height: 4),
            Text(
              canCarry
                  ? 'Add your allowance, or carry over last month\'s leftover above.'
                  : 'Add your allowance so your daily budget has real numbers.',
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add allowance'),
              onPressed: () => showAddEntrySheet(
                context,
                kind: EntryKind.income,
                categoryId: 'allowance',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CarryOverCard extends ConsumerWidget {
  final MonthData data;
  const _CarryOverCard({required this.data});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prev = data.month.previous;
    return Card(
      color: context.colors.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.redo, color: context.colors.onSecondaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'You had ${formatRm(data.previousLeftOverSen)} left in '
                '${monthLongNames[prev.month - 1]}.',
                style: TextStyle(color: context.colors.onSecondaryContainer),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () async {
                final ok = await runApi(
                  context,
                  () => ref.read(apiClientProvider).carryOver(data.month),
                  success: 'Carried over ${formatRm(data.previousLeftOverSen)}',
                );
                if (ok) ref.invalidate(monthProvider);
              },
              child: const Text('Carry over'),
            ),
          ],
        ),
      ),
    );
  }
}
