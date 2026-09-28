import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runway_core/runway_core.dart';

import '../../data/models.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';

class PlanScreen extends ConsumerWidget {
  const PlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedMonthProvider);
    final today = ref.watch(todayProvider);
    final cats = ref.watch(categoriesProvider).value ?? const <Category>[];

    return AsyncView<MonthData>(
      value: ref.watch(monthProvider(month)),
      onRetry: () => ref.invalidate(monthProvider(month)),
      builder: (d) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          PageWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Section(
                  title: 'Bills',
                  subtitle:
                      'Unpaid bills are set aside before your daily budget.',
                  action: TextButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Add bill'),
                    onPressed: () => showBillDialog(context, ref, cats),
                  ),
                  children: [
                    if (d.bills.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'No bills yet. Add rent and your phone plan.',
                        ),
                      ),
                    for (final b in d.bills)
                      _BillTile(
                        bill: b,
                        month: month,
                        today: today,
                        cats: cats,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                _Section(
                  title: 'Savings goal',
                  subtitle: 'Put aside every month before daily spending.',
                  children: [
                    ListTile(
                      leading: const Icon(Icons.savings),
                      title: Text(
                        d.savingsGoalSen == 0
                            ? 'No savings goal'
                            : '${formatRm(d.savingsGoalSen)} a month',
                      ),
                      trailing: const Icon(Icons.edit),
                      onTap: () => _editSavings(context, ref, d.savingsGoalSen),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _Section(
                  title: 'Category limits',
                  subtitle: 'Optional monthly caps, e.g. Food & drinks RM 550.',
                  children: [
                    for (final c in cats.where(
                      (c) => c.kind == EntryKind.expense,
                    ))
                      ListTile(
                        dense: true,
                        leading: Icon(categoryIcon(c.id)),
                        title: Text(c.label),
                        trailing: Text(
                          d.limits[c.id] == null
                              ? 'No limit'
                              : formatRm(d.limits[c.id]!, showSen: false),
                          style: d.limits[c.id] == null
                              ? TextStyle(color: context.runway.muted)
                              : const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        onTap: () =>
                            _editLimit(context, ref, c, d.limits[c.id]),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editSavings(
    BuildContext context,
    WidgetRef ref,
    int current,
  ) async {
    final sen = await _askAmount(
      context,
      title: 'Monthly savings goal',
      initial: current,
      allowZero: true,
      help: 'Set to 0 for no goal.',
    );
    if (sen == null || !context.mounted) return;
    final ok = await runApi(context, () async {
      final user = await ref
          .read(apiClientProvider)
          .updateMe(monthlySavingsGoalSen: sen);
      ref.read(sessionProvider.notifier).updateUser(user);
    }, success: 'Savings goal updated');
    if (ok) ref.invalidate(monthProvider);
  }

  Future<void> _editLimit(
    BuildContext context,
    WidgetRef ref,
    Category c,
    int? current,
  ) async {
    final sen = await _askAmount(
      context,
      title: '${c.label} limit',
      initial: current,
      allowZero: true,
      help: 'Set to 0 to remove the limit.',
    );
    if (sen == null || !context.mounted) return;
    final api = ref.read(apiClientProvider);
    final ok = await runApi(
      context,
      () => sen == 0 ? api.removeLimit(c.id) : api.setLimit(c.id, sen),
      success: sen == 0 ? 'Limit removed' : 'Limit saved',
    );
    if (ok) ref.invalidate(monthProvider);
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? action;
  final List<Widget> children;

  const _Section({
    required this.title,
    required this.subtitle,
    required this.children,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: context.text.titleSmall),
                        Text(
                          subtitle,
                          style: context.text.bodySmall?.copyWith(
                            color: context.runway.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ?action,
                ],
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _BillTile extends ConsumerWidget {
  final Bill bill;
  final YearMonth month;
  final LocalDate today;
  final List<Category> cats;

  const _BillTile({
    required this.bill,
    required this.month,
    required this.today,
    required this.cats,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = billStatus(bill, month, today);
    final c = context.runway;
    final (color, icon) = switch (st.state) {
      BillState.paid => (c.good, Icons.check_circle),
      BillState.overdue || BillState.unpaidPast => (c.critical, Icons.error),
      BillState.dueToday => (c.warning, Icons.schedule),
      _ => (c.muted, Icons.schedule),
    };
    final canPay =
        !bill.isPaid && bill.active && month.compareTo(today.yearMonth) <= 0;

    return ListTile(
      leading: Icon(categoryIcon(bill.categoryId)),
      title: Text(bill.name),
      subtitle: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Flexible(child: Text('${formatRm(bill.amountSen)} · ${st.label}')),
        ],
      ),
      trailing: canPay
          ? FilledButton.tonal(
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              onPressed: () => _pay(context, ref),
              child: const Text('Mark paid'),
            )
          : null,
      onTap: bill.active
          ? () => showBillDialog(context, ref, cats, bill: bill)
          : null,
    );
  }

  Future<void> _pay(BuildContext context, WidgetRef ref) async {
    final on = month == today.yearMonth ? today : month.last;
    final ok = await runApi(
      context,
      () => ref.read(apiClientProvider).payBill(bill.id, on),
      success: '${bill.name} marked paid (${formatRm(bill.amountSen)})',
    );
    if (ok) ref.invalidate(monthProvider);
  }
}

Future<void> showBillDialog(
  BuildContext context,
  WidgetRef ref,
  List<Category> cats, {
  Bill? bill,
}) async {
  final result = await showDialog<_BillForm>(
    context: context,
    builder: (_) => _BillDialog(bill: bill, cats: cats),
  );
  if (result == null || !context.mounted) return;
  final api = ref.read(apiClientProvider);
  final ok = await runApi(
    context,
    () {
      if (result.delete) return api.deleteBill(bill!.id);
      if (bill == null) {
        return api.createBill(
          name: result.name,
          amountSen: result.amountSen,
          dueDay: result.dueDay,
          categoryId: result.categoryId,
        );
      }
      return api.updateBill(
        bill.id,
        name: result.name,
        amountSen: result.amountSen,
        dueDay: result.dueDay,
        categoryId: result.categoryId,
      );
    },
    success: result.delete
        ? 'Bill removed'
        : bill == null
        ? 'Bill added'
        : 'Bill updated',
  );
  if (ok) ref.invalidate(monthProvider);
}

class _BillForm {
  final String name;
  final int amountSen;
  final int dueDay;
  final String categoryId;
  final bool delete;
  const _BillForm(
    this.name,
    this.amountSen,
    this.dueDay,
    this.categoryId, {
    this.delete = false,
  });
}

class _BillDialog extends StatefulWidget {
  final Bill? bill;
  final List<Category> cats;
  const _BillDialog({this.bill, required this.cats});

  @override
  State<_BillDialog> createState() => _BillDialogState();
}

class _BillDialogState extends State<_BillDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.bill?.name);
  late final _amount = TextEditingController(
    text: widget.bill == null ? '' : senToInput(widget.bill!.amountSen),
  );
  late final _day = TextEditingController(
    text: widget.bill?.dueDay.toString() ?? '1',
  );
  late String _category = widget.bill?.categoryId ?? 'housing';

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _day.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final expenseCats = widget.cats
        .where((c) => c.kind == EntryKind.expense)
        .toList();
    return AlertDialog(
      title: Text(widget.bill == null ? 'Add a bill' : 'Edit bill'),
      content: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                autofocus: widget.bill == null,
                maxLength: 60,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'Rent',
                  counterText: '',
                ),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Give the bill a name' : null,
              ),
              const SizedBox(height: 12),
              RmField(controller: _amount),
              const SizedBox(height: 12),
              TextFormField(
                controller: _day,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Due day of the month',
                  hintText: '1-31',
                ),
                validator: (v) {
                  final n = int.tryParse(v ?? '');
                  return (n == null || n < 1 || n > 31)
                      ? 'Enter a day from 1 to 31'
                      : null;
                },
              ),
              const SizedBox(height: 12),
              if (expenseCats.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: expenseCats.any((c) => c.id == _category)
                      ? _category
                      : expenseCats.first.id,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: [
                    for (final c in expenseCats)
                      DropdownMenuItem(value: c.id, child: Text(c.label)),
                  ],
                  onChanged: (v) => setState(() => _category = v ?? _category),
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.bill != null)
          TextButton(
            onPressed: () async {
              final ok = await confirm(
                context,
                title: 'Remove ${widget.bill!.name}?',
                message: 'It will no longer be set aside each month. Past payments stay in your activity.',
                action: 'Remove',
              );
              if (ok && context.mounted) {
                Navigator.pop(
                  context,
                  const _BillForm('', 0, 0, '', delete: true),
                );
              }
            },
            child: Text(
              'Remove',
              style: TextStyle(color: context.colors.error),
            ),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            Navigator.pop(
              context,
              _BillForm(
                _name.text.trim(),
                parseRmToSen(_amount.text)!,
                int.parse(_day.text),
                _category,
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

Future<int?> _askAmount(
  BuildContext context, {
  required String title,
  int? initial,
  bool allowZero = false,
  String? help,
}) {
  final controller = TextEditingController(
    text: initial == null ? '' : senToInput(initial),
  );
  final form = GlobalKey<FormState>();
  return showDialog<int>(
    context: context,
    builder: (ctx) {
      void submit() {
        if (form.currentState!.validate()) {
          Navigator.pop(ctx, parseRmToSen(controller.text));
        }
      }

      return AlertDialog(
        title: Text(title),
        content: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RmField(
                controller: controller,
                autofocus: true,
                validator: (v) => validateAmount(v, allowZero: allowZero),
                onSubmitted: (_) => submit(),
              ),
              if (help != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(help, style: ctx.text.bodySmall),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(onPressed: submit, child: const Text('Save')),
        ],
      );
    },
  );
}
