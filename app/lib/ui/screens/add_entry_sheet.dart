import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runway_core/runway_core.dart';

import '../../data/api_client.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';

Future<void> showAddEntrySheet(
  BuildContext context, {
  EntryKind kind = EntryKind.expense,
  String? categoryId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) =>
        AddEntrySheet(initialKind: kind, initialCategoryId: categoryId),
  );
}

/// Open, type the amount, tap a category, save.
class AddEntrySheet extends ConsumerStatefulWidget {
  final EntryKind initialKind;
  final String? initialCategoryId;
  const AddEntrySheet({
    super.key,
    this.initialKind = EntryKind.expense,
    this.initialCategoryId,
  });

  @override
  ConsumerState<AddEntrySheet> createState() => _AddEntrySheetState();
}

class _AddEntrySheetState extends ConsumerState<AddEntrySheet> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  late EntryKind _kind = widget.initialKind;
  String? _categoryId;
  late LocalDate _date = _defaultDate();
  bool _saving = false;
  String? _error;

  LocalDate _defaultDate() {
    final today = ref.read(todayProvider);
    final viewed = ref.read(selectedMonthProvider);
    // Adding while browsing another month lands in that month.
    return viewed == today.yearMonth ? today : viewed.first;
  }

  @override
  void initState() {
    super.initState();
    _categoryId =
        widget.initialCategoryId ??
        (_kind == EntryKind.expense ? 'food' : 'allowance');
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_categoryId == null) {
      setState(() => _error = 'Pick a category');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(apiClientProvider)
          .addEntry(
            kind: _kind,
            amountSen: parseRmToSen(_amount.text)!,
            categoryId: _categoryId!,
            occurredOn: _date,
            note: _note.text,
          );
      ref.invalidate(monthProvider);
      if (!mounted) return;
      final saved =
          '${_kind == EntryKind.income ? 'Income' : 'Expense'} of '
          '${formatRm(parseRmToSen(_amount.text)!)} saved';
      Navigator.pop(context);
      showMessage(context, saved);
    } on ApiException catch (e) {
      setState(() {
        _saving = false;
        _error = e.message;
      });
    }
  }

  Future<void> _pickDate() async {
    final today = ref.read(todayProvider);
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(_date.year, _date.month, _date.day),
      firstDate: DateTime(today.year - 2),
      lastDate: DateTime(today.year + 1, 12, 31),
    );
    if (picked != null) setState(() => _date = LocalDate.fromDateTime(picked));
  }

  @override
  Widget build(BuildContext context) {
    final cats = ref.watch(categoriesProvider).value ?? const <Category>[];
    final today = ref.watch(todayProvider);
    final shown = cats.where((c) => c.kind == _kind).toList();
    final dateLabel = _date == today
        ? 'Today'
        : _date == today.addDays(-1)
        ? 'Yesterday'
        : '${_date.day} ${monthShortNames[_date.month - 1]} ${_date.year}';

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<EntryKind>(
                segments: const [
                  ButtonSegment(
                    value: EntryKind.expense,
                    label: Text('Expense'),
                    icon: Icon(Icons.remove),
                  ),
                  ButtonSegment(
                    value: EntryKind.income,
                    label: Text('Income'),
                    icon: Icon(Icons.add),
                  ),
                ],
                selected: {_kind},
                onSelectionChanged: (s) => setState(() {
                  _kind = s.first;
                  _categoryId = _kind == EntryKind.expense
                      ? 'food'
                      : 'allowance';
                }),
              ),
              const SizedBox(height: 16),
              RmField(
                controller: _amount,
                autofocus: true,
                large: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 16),
              Text('Category', style: context.text.labelLarge),
              const SizedBox(height: 8),
              if (shown.isEmpty)
                const LinearProgressIndicator()
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in shown)
                      ChoiceChip(
                        avatar: Icon(categoryIcon(c.id), size: 18),
                        label: Text(c.label),
                        selected: _categoryId == c.id,
                        onSelected: (_) => setState(() => _categoryId = c.id),
                      ),
                  ],
                ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _note,
                maxLength: 120,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Note (optional)',
                  hintText: _kind == EntryKind.expense
                      ? 'Nasi lemak at the cafe'
                      : 'PTPTN, part-time shift…',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: Text(dateLabel),
                trailing: const Text('Change'),
                onTap: _pickDate,
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _error!,
                    style: TextStyle(color: context.colors.error),
                  ),
                ),
              FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                child: _saving
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        _kind == EntryKind.expense
                            ? 'Save expense'
                            : 'Save income',
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
