import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runway_core/runway_core.dart';

import '../../data/api_client.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// First run: allowance, rent, phone plan and a savings goal, so Home opens
/// with real numbers instead of an empty shell.
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _form = GlobalKey<FormState>();
  final _allowance = TextEditingController();
  final _rent = TextEditingController();
  final _rentDay = TextEditingController(text: '1');
  final _phone = TextEditingController();
  final _phoneDay = TextEditingController(text: '15');
  final _savings = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [
      _allowance,
      _rent,
      _rentDay,
      _phone,
      _phoneDay,
      _savings,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _optionalAmount(String? v) =>
      (v ?? '').trim().isEmpty ? null : validateAmount(v);

  String? _day(String? v) {
    final n = int.tryParse(v ?? '');
    return (n == null || n < 1 || n > 31) ? '1-31' : null;
  }

  Future<void> _finish() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final api = ref.read(apiClientProvider);
    final today = ref.read(todayProvider);
    int? sen(TextEditingController c) =>
        c.text.trim().isEmpty ? null : parseRmToSen(c.text);
    try {
      final allowance = sen(_allowance)!;
      await api.addEntry(
        kind: EntryKind.income,
        amountSen: allowance,
        categoryId: 'allowance',
        occurredOn: today,
        note: 'Monthly allowance',
      );
      final rent = sen(_rent);
      if (rent != null) {
        await api.createBill(
          name: 'Rent',
          amountSen: rent,
          dueDay: int.parse(_rentDay.text),
          categoryId: 'housing',
        );
      }
      final phone = sen(_phone);
      if (phone != null) {
        await api.createBill(
          name: 'Phone plan',
          amountSen: phone,
          dueDay: int.parse(_phoneDay.text),
          categoryId: 'phone',
        );
      }
      final savings = sen(_savings);
      if (savings != null) {
        final user = await api.updateMe(monthlySavingsGoalSen: savings);
        ref.read(sessionProvider.notifier).updateUser(user);
      }
      ref.invalidate(monthProvider);
      ref.read(sessionProvider.notifier).finishSetup();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final month = monthLongNames[ref.watch(todayProvider).month - 1];
    return Scaffold(
      appBar: AppBar(
        title: const Text("Let's set up your month"),
        actions: [
          TextButton(
            onPressed: _busy
                ? null
                : () => ref.read(sessionProvider.notifier).finishSetup(),
            child: const Text('Skip'),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: PageWidth(
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Three quick numbers and Ringgit Runway can tell you how much '
                    'you can spend each day in $month.',
                    style: context.text.bodyLarge,
                  ),
                  const SizedBox(height: 24),
                  Text('Money coming in', style: context.text.titleSmall),
                  const SizedBox(height: 8),
                  RmField(
                    controller: _allowance,
                    label: 'Monthly allowance',
                    autofocus: true,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Fixed bills (leave blank if none)',
                    style: context.text.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  _BillRow(
                    amount: _rent,
                    day: _rentDay,
                    label: 'Rent',
                    amountValidator: _optionalAmount,
                    dayValidator: _day,
                  ),
                  const SizedBox(height: 12),
                  _BillRow(
                    amount: _phone,
                    day: _phoneDay,
                    label: 'Phone plan',
                    amountValidator: _optionalAmount,
                    dayValidator: _day,
                  ),
                  const SizedBox(height: 24),
                  Text('Savings (optional)', style: context.text.titleSmall),
                  const SizedBox(height: 8),
                  RmField(
                    controller: _savings,
                    label: 'Save each month',
                    validator: (v) => (v ?? '').trim().isEmpty
                        ? null
                        : validateAmount(v, allowZero: true),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: TextStyle(color: context.colors.error),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _finish,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    child: _busy
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Show my daily budget'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BillRow extends StatelessWidget {
  final TextEditingController amount;
  final TextEditingController day;
  final String label;
  final String? Function(String?) amountValidator;
  final String? Function(String?) dayValidator;

  const _BillRow({
    required this.amount,
    required this.day,
    required this.label,
    required this.amountValidator,
    required this.dayValidator,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: RmField(
            controller: amount,
            label: label,
            validator: amountValidator,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: TextFormField(
            controller: day,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Due day'),
            validator: dayValidator,
          ),
        ),
      ],
    );
  }
}
