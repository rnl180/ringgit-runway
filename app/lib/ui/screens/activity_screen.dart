import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runway_core/runway_core.dart';

import '../../data/models.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String dayHeading(LocalDate d, LocalDate today) {
  if (d == today) return 'Today';
  if (d == today.addDays(-1)) return 'Yesterday';
  final wd = DateTime.utc(d.year, d.month, d.day).weekday;
  return '${_weekdays[wd - 1]}, ${d.day} ${monthShortNames[d.month - 1]}';
}

class ActivityScreen extends ConsumerWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedMonthProvider);
    final today = ref.watch(todayProvider);
    final cats = {
      for (final c in ref.watch(categoriesProvider).value ?? const <Category>[])
        c.id: c,
    };

    return AsyncView<MonthData>(
      value: ref.watch(monthProvider(month)),
      onRetry: () => ref.invalidate(monthProvider(month)),
      builder: (d) {
        if (d.entries.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'Nothing recorded in ${monthLongNames[month.month - 1]} yet.\n'
                'Tap Add to log what you spend or receive.',
                textAlign: TextAlign.center,
                style: context.text.bodyLarge,
              ),
            ),
          );
        }
        final byDay = <LocalDate, List<Entry>>{};
        for (final e in d.entries) {
          (byDay[e.occurredOn] ??= []).add(e);
        }
        final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));

        return RefreshIndicator(
          onRefresh: () => ref.refresh(monthProvider(month).future),
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 96),
            itemCount: days.length,
            itemBuilder: (context, i) {
              final day = days[i];
              final items = byDay[day]!;
              final spent = items
                  .where((e) => !e.isIncome)
                  .fold<int>(0, (s, e) => s + e.amountSen);
              return PageWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              dayHeading(day, today),
                              style: context.text.titleSmall,
                            ),
                          ),
                          if (spent > 0)
                            Text(
                              'Spent ${formatRm(spent)}',
                              style: context.text.labelMedium?.copyWith(
                                color: context.runway.muted,
                              ),
                            ),
                        ],
                      ),
                    ),
                    for (final e in items)
                      _EntryTile(entry: e, category: cats[e.categoryId]),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _EntryTile extends ConsumerWidget {
  final Entry entry;
  final Category? category;
  const _EntryTile({required this.entry, required this.category});

  Future<bool> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await confirm(
      context,
      title: 'Delete this entry?',
      message:
          '${category?.label ?? 'Entry'} · ${formatRm(entry.amountSen)}'
          '${entry.note != null ? '\n"${entry.note}"' : ''}'
          '${entry.billId != null ? '\n\nThe bill will show as unpaid again.' : ''}',
    );
    if (!ok || !context.mounted) return false;
    final done = await runApi(
      context,
      () => ref.read(apiClientProvider).deleteEntry(entry.id),
      success: 'Entry deleted',
    );
    if (done) ref.invalidate(monthProvider);
    return done;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final income = entry.isIncome;
    final amount = income
        ? formatRmSigned(entry.amountSen)
        : formatRm(entry.amountSen);
    final title = entry.note ?? category?.label ?? entry.categoryId;
    final subtitle = [
      if (entry.note != null) category?.label ?? entry.categoryId,
      if (entry.billId != null) 'Bill payment',
    ].join(' · ');

    return Dismissible(
      key: ValueKey(entry.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _delete(context, ref),
      background: Container(
        color: context.runway.critical,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Delete', style: TextStyle(color: context.runway.onCritical)),
            const SizedBox(width: 8),
            Icon(Icons.delete, color: context.runway.onCritical),
          ],
        ),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: income
              ? context.runway.incomeText.withValues(alpha: 0.15)
              : context.colors.surfaceContainerHighest,
          child: Icon(
            categoryIcon(entry.categoryId),
            size: 20,
            color: income
                ? context.runway.incomeText
                : context.colors.onSurfaceVariant,
          ),
        ),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: subtitle.isEmpty ? null : Text(subtitle),
        trailing: Text(
          amount,
          style: context.text.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: income ? context.runway.incomeText : null,
          ),
        ),
        onTap: () => _showActions(context, ref),
      ),
    );
  }

  void _showActions(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(categoryIcon(entry.categoryId)),
              title: Text(category?.label ?? entry.categoryId),
              subtitle: Text(
                [
                  '${entry.occurredOn.day} ${monthLongNames[entry.occurredOn.month - 1]} ${entry.occurredOn.year}',
                  if (entry.note != null) entry.note!,
                ].join('\n'),
              ),
              trailing: Text(
                formatRm(entry.amountSen),
                style: context.text.titleMedium,
              ),
            ),
            ListTile(
              leading: Icon(Icons.delete, color: context.colors.error),
              title: Text(
                'Delete entry',
                style: TextStyle(color: context.colors.error),
              ),
              onTap: () async {
                Navigator.pop(sheet);
                await _delete(context, ref);
              },
            ),
          ],
        ),
      ),
    );
  }
}
