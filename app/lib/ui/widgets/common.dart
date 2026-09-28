import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runway_core/runway_core.dart';

import '../../data/api_client.dart';
import '../../state/providers.dart';
import '../theme.dart';

/// Pill that names the budget status in words, with an icon, never color alone.
class StatusPill extends StatelessWidget {
  final BudgetStatus status;
  const StatusPill(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.runway;
    final (bg, fg, icon) = switch (status) {
      BudgetStatus.onTrack => (c.good, c.onGood, Icons.check_circle),
      BudgetStatus.spendingFast => (c.warning, c.onWarning, Icons.speed),
      BudgetStatus.overBudget => (c.critical, c.onCritical, Icons.error),
      BudgetStatus.noIncome => (
        context.colors.secondaryContainer,
        context.colors.onSecondaryContainer,
        Icons.info,
      ),
    };
    return Semantics(
      label: 'Status: ${status.label}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 6),
            Text(
              status.label,
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "‹ September 2026 ›" in the app bar; shared by every tab.
class MonthSwitcher extends ConsumerWidget {
  const MonthSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedMonthProvider);
    final today = ref.watch(todayProvider);
    final ctl = ref.read(selectedMonthProvider.notifier);
    final isCurrent = month == today.yearMonth;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'Previous month',
          icon: const Icon(Icons.chevron_left),
          onPressed: ctl.previous,
        ),
        Flexible(
          child: GestureDetector(
            onTap: isCurrent ? null : () => ctl.set(today.yearMonth),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${monthLongNames[month.month - 1]} ${month.year}',
                    style: context.text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (!isCurrent)
                    Text(
                      'Tap for this month',
                      style: context.text.labelSmall?.copyWith(
                        color: context.colors.primary,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'Next month',
          icon: const Icon(Icons.chevron_right),
          onPressed: ctl.next,
        ),
      ],
    );
  }
}

/// Loading spinner, friendly error with retry, or the data.
class AsyncView<T> extends StatelessWidget {
  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback onRetry;

  const AsyncView({
    super.key,
    required this.value,
    required this.builder,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (value.hasValue) return builder(value.requireValue);
    if (value.hasError) {
      final e = value.error;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 40, color: context.colors.outline),
              const SizedBox(height: 12),
              Text(
                e is ApiException ? e.message : 'Something went wrong.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: onRetry,
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }
    return const Center(child: CircularProgressIndicator());
  }
}

IconData categoryIcon(String id) => switch (id) {
  'food' => Icons.restaurant,
  'groceries' => Icons.shopping_basket,
  'transport' => Icons.directions_bus,
  'housing' => Icons.home,
  'phone' => Icons.smartphone,
  'study' => Icons.menu_book,
  'fun' => Icons.celebration,
  'shopping' => Icons.shopping_bag,
  'health' => Icons.healing,
  'allowance' => Icons.account_balance_wallet,
  'job' => Icons.work,
  'scholarship' => Icons.school,
  'gift' => Icons.card_giftcard,
  'carry_over' => Icons.redo,
  _ => Icons.more_horiz,
};

/// Amount input with an `RM` prefix that only accepts money-shaped text.
class RmField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool autofocus;
  final bool large;
  final String? Function(String?)? validator;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  const RmField({
    super.key,
    required this.controller,
    this.label = 'Amount',
    this.autofocus = false,
    this.large = false,
    this.validator,
    this.textInputAction,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final style = large
        ? context.text.headlineMedium?.copyWith(fontWeight: FontWeight.w700)
        : null;
    return TextFormField(
      controller: controller,
      autofocus: autofocus,
      style: style,
      textInputAction: textInputAction,
      onFieldSubmitted: onSubmitted,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
        LengthLimitingTextInputFormatter(12),
      ],
      decoration: InputDecoration(
        labelText: label,
        prefixText: 'RM ',
        prefixStyle: style,
        hintText: '0.00',
      ),
      validator: validator ?? (v) => validateAmount(v),
    );
  }
}

String? validateAmount(String? v, {bool allowZero = false}) {
  final sen = parseRmToSen(v ?? '');
  if (sen == null) return 'Enter an amount like 12.50';
  if (!allowZero && sen <= 0) return 'Amount must be more than RM 0';
  if (sen > 100000000) return 'Amount must be at most RM 1,000,000';
  return null;
}

/// Plain amount string for pre-filling an [RmField] ("12.50").
String senToInput(int sen) =>
    '${sen ~/ 100}.${(sen % 100).toString().padLeft(2, '0')}';

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String action = 'Delete',
  bool destructive = true,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: ctx.runway.critical,
                  foregroundColor: ctx.runway.onCritical,
                )
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return ok ?? false;
}

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Runs an API call, showing its error message if it fails.
Future<bool> runApi(
  BuildContext context,
  Future<void> Function() call, {
  String? success,
}) async {
  try {
    await call();
    if (success != null && context.mounted) showMessage(context, success);
    return true;
  } on ApiException catch (e) {
    if (context.mounted) showMessage(context, e.message);
    return false;
  }
}

/// Centers content and caps its width so it reads well on tablets and web.
class PageWidth extends StatelessWidget {
  final Widget child;
  const PageWidth({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: child,
    ),
  );
}
