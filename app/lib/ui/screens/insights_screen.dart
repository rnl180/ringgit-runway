import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runway_core/runway_core.dart';

import '../../data/models.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';

class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedMonthProvider);
    final today = ref.watch(todayProvider);
    final cats = ref.watch(categoriesProvider).value ?? const <Category>[];

    return AsyncView<MonthData>(
      value: ref.watch(monthProvider(month)),
      onRetry: () => ref.invalidate(monthProvider(month)),
      builder: (d) {
        final s = d.summary(today);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            PageWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DailySpendingCard(summary: s),
                  const SizedBox(height: 12),
                  CategoryCard(summary: s, limits: d.limits, categories: cats),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class DailySpendingCard extends StatefulWidget {
  final MonthSummary summary;
  const DailySpendingCard({super.key, required this.summary});

  @override
  State<DailySpendingCard> createState() => _DailySpendingCardState();
}

class _DailySpendingCardState extends State<DailySpendingCard> {
  bool _asList = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.summary;
    final c = context.runway;
    final line = s.dailyLineSen;
    final mon = monthShortNames[s.month.month - 1];
    final overDays = [
      for (var i = 0; i < s.daysInMonth; i++)
        if (line > 0 && s.dailySpendingSen[i] > line) i + 1,
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Daily spending', style: context.text.titleSmall),
                ),
                TextButton.icon(
                  onPressed: () => setState(() => _asList = !_asList),
                  icon: Icon(_asList ? Icons.bar_chart : Icons.list, size: 18),
                  label: Text(_asList ? 'Chart' : 'List'),
                ),
              ],
            ),
            Text(
              line > 0
                  ? 'Bills not included. Dashed line: ${formatRm(line)} a day '
                        '(your spending money spread over the month).'
                  : 'Bills not included. Add income to see your daily line.',
              style: context.text.bodySmall?.copyWith(color: c.muted),
            ),
            const SizedBox(height: 16),
            if (_asList)
              _DayList(summary: s)
            else ...[
              SizedBox(height: 200, child: _chart(context, s)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  _LegendSwatch(color: c.series, label: 'At or under the line'),
                  _LegendSwatch(color: c.warning, label: 'Above the line'),
                ],
              ),
            ],
            if (overDays.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.warning_amber, size: 16, color: c.muted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${overDays.length} ${overDays.length == 1 ? 'day' : 'days'} above the line: '
                      '${overDays.take(6).map((d) => '$d $mon').join(', ')}'
                      '${overDays.length > 6 ? '…' : ''}',
                      style: context.text.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chart(BuildContext context, MonthSummary s) {
    final c = context.runway;
    final line = s.dailyLineSen;
    final maxSen = math.max(line, s.dailySpendingSen.fold<int>(0, math.max));
    final maxY = maxSen == 0 ? 10.0 : (maxSen / 100) * 1.15;
    final step = _niceStep(maxY / 4);
    final mon = monthShortNames[s.month.month - 1];

    return LayoutBuilder(
      builder: (context, box) {
        final plotWidth = box.maxWidth - 44;
        final barWidth = math.max(
          2.0,
          plotWidth / s.daysInMonth - 2,
        ); // 2px gap between bars
        return BarChart(
          BarChartData(
            maxY: maxY,
            minY: 0,
            alignment: BarChartAlignment.spaceBetween,
            barGroups: [
              for (var i = 0; i < s.daysInMonth; i++)
                BarChartGroupData(
                  x: i + 1,
                  barRods: [
                    BarChartRodData(
                      toY: s.dailySpendingSen[i] / 100,
                      width: barWidth,
                      color: line > 0 && s.dailySpendingSen[i] > line
                          ? c.warning
                          : c.series,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(4),
                      ),
                    ),
                  ],
                ),
            ],
            extraLinesData: ExtraLinesData(
              horizontalLines: [
                if (line > 0)
                  HorizontalLine(
                    y: line / 100,
                    color: context.colors.onSurface.withValues(alpha: 0.7),
                    strokeWidth: 1.5,
                    dashArray: [6, 4],
                  ),
              ],
            ),
            gridData: FlGridData(
              drawVerticalLine: false,
              horizontalInterval: step,
              getDrawingHorizontalLine: (_) =>
                  FlLine(color: c.grid, strokeWidth: 1),
            ),
            borderData: FlBorderData(
              show: true,
              border: Border(bottom: BorderSide(color: c.axis)),
            ),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 44,
                  interval: step,
                  getTitlesWidget: (v, meta) => v == meta.max
                      ? const SizedBox.shrink()
                      : Text(
                          v == 0 ? '0' : 'RM${v.toStringAsFixed(0)}',
                          style: TextStyle(fontSize: 10, color: c.muted),
                        ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 22,
                  interval: 1,
                  getTitlesWidget: (v, meta) {
                    final day = v.toInt();
                    if (day != 1 && day % 5 != 0) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '$day',
                        style: TextStyle(fontSize: 10, color: c.muted),
                      ),
                    );
                  },
                ),
              ),
            ),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => context.colors.inverseSurface,
                getTooltipItem: (group, _, rod, _) {
                  final sen = s.dailySpendingSen[group.x - 1];
                  final over = line > 0 && sen > line;
                  return BarTooltipItem(
                    '${group.x} $mon\n${formatRm(sen)}${over ? '\nAbove the line' : ''}',
                    TextStyle(
                      color: context.colors.onInverseSurface,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  static double _niceStep(double raw) {
    if (raw <= 0) return 1;
    final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    for (final m in [1, 2, 5, 10]) {
      if (raw <= m * mag) return m * mag;
    }
    return 10 * mag;
  }
}

class _DayList extends StatelessWidget {
  final MonthSummary summary;
  const _DayList({required this.summary});

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final mon = monthShortNames[s.month.month - 1];
    final rows = [
      for (var i = 0; i < s.daysInMonth; i++)
        if (s.dailySpendingSen[i] > 0) i + 1,
    ];
    if (rows.isEmpty) return const Text('No spending yet.');
    return Column(
      children: [
        for (final day in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Expanded(child: Text('$day $mon')),
                if (s.dailyLineSen > 0 &&
                    s.dailySpendingSen[day - 1] > s.dailyLineSen)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      'above line',
                      style: context.text.labelSmall?.copyWith(
                        color: context.runway.muted,
                      ),
                    ),
                  ),
                Text(
                  formatRm(s.dailySpendingSen[day - 1]),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _LegendSwatch extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendSwatch({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      const SizedBox(width: 6),
      Text(label, style: context.text.labelSmall),
    ],
  );
}

class CategoryCard extends StatelessWidget {
  final MonthSummary summary;
  final Map<String, int> limits;
  final List<Category> categories;

  const CategoryCard({
    super.key,
    required this.summary,
    required this.limits,
    required this.categories,
  });

  @override
  Widget build(BuildContext context) {
    final spent = summary.spentByCategorySen;
    final rows = [
      for (final c in categories.where((c) => c.kind == EntryKind.expense))
        if ((spent[c.id] ?? 0) > 0 || limits.containsKey(c.id))
          (cat: c, spent: spent[c.id] ?? 0, limit: limits[c.id]),
    ]..sort((a, b) => b.spent.compareTo(a.spent));
    final maxSpent = rows.fold<int>(1, (m, r) => math.max(m, r.spent));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Spending by category', style: context.text.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Includes bills. Set limits in Plan.',
              style: context.text.bodySmall?.copyWith(
                color: context.runway.muted,
              ),
            ),
            const SizedBox(height: 12),
            if (rows.isEmpty) const Text('No spending yet.'),
            for (final r in rows) ...[
              _CategoryBar(
                category: r.cat,
                spent: r.spent,
                limit: r.limit,
                scale: maxSpent,
              ),
              const SizedBox(height: 14),
            ],
          ],
        ),
      ),
    );
  }
}

class _CategoryBar extends StatelessWidget {
  final Category category;
  final int spent;
  final int? limit;
  final int scale;

  const _CategoryBar({
    required this.category,
    required this.spent,
    required this.limit,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.runway;
    final over = limit != null && spent > limit!;
    final near = limit != null && !over && spent >= limit! * 0.8;
    final fraction = limit != null ? spent / limit! : spent / scale;
    final color = over
        ? c.critical
        : near
        ? c.warning
        : c.series;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(categoryIcon(category.id), size: 18, color: c.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(category.label, style: context.text.bodyMedium),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                limit != null
                    ? '${formatRm(spent)} of ${formatRm(limit!, showSen: false)}'
                    : formatRm(spent),
                textAlign: TextAlign.end,
                style: context.text.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fraction.clamp(0, 1).toDouble(),
            minHeight: 8,
            color: color,
            backgroundColor: c.grid,
          ),
        ),
        if (over || near)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Icon(
                  over ? Icons.error : Icons.warning_amber,
                  size: 14,
                  color: over ? c.critical : c.muted,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    over
                        ? 'Over limit by ${formatRm(spent - limit!)}'
                        : '${formatRm(limit! - spent)} left in this limit',
                    style: context.text.labelSmall,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
