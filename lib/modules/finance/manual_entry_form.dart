import 'package:flutter/material.dart';
import '../../shared/trackable_entry.dart';

/// The Finance categories -- the single source of truth for keys and
/// display names. The same list is enforced in firestore.rules
/// (isCategory) and produced by functions/src/categorize.ts
/// (AnchorCategory). Add a category in all three places or not at all.
const List<String> manualEntryCategories = [
  'groceries',
  'eating_out',
  'subscriptions',
  'entertainment',
  'miscellaneous',
];

String manualCategoryDisplayName(String category) {
  switch (category) {
    case 'groceries':
      return 'Groceries';
    case 'eating_out':
      return 'Eating Out';
    case 'subscriptions':
      return 'Subscriptions';
    case 'entertainment':
      return 'Entertainment';
    case 'miscellaneous':
      return 'Miscellaneous';
    default:
      return category;
  }
}

/// A simple bottom-sheet form for manually logging a Finance entry.
/// Calls [onSubmit] with a new TrackableEntry (source: 'manual') and
/// closes itself. Does not persist anything on its own -- the caller
/// decides what to do with it (FinanceScreen saves it to Firestore
/// through FinanceRepository.addManualExpense).
class ManualEntryForm extends StatefulWidget {
  const ManualEntryForm({super.key, required this.onSubmit});

  final void Function(TrackableEntry entry) onSubmit;

  @override
  State<ManualEntryForm> createState() => _ManualEntryFormState();
}

class _ManualEntryFormState extends State<ManualEntryForm> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  String _selectedCategory = manualEntryCategories.first;
  String? _errorText;

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _handleSave() {
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      setState(() => _errorText = 'Enter a valid amount greater than \$0');
      return;
    }

    widget.onSubmit(
      TrackableEntry(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        moduleType: 'finance',
        category: _selectedCategory,
        value: amount,
        timestamp: DateTime.now(),
        note: _noteController.text.isEmpty ? null : _noteController.text,
        source: 'manual',
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Add Expense',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('manual_entry_amount_field'),
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Amount',
              prefixText: '\$',
              errorText: _errorText,
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: const Key('manual_entry_category_dropdown'),
            initialValue: _selectedCategory,
            decoration: const InputDecoration(labelText: 'Category'),
            items: manualEntryCategories
                .map((c) => DropdownMenuItem(
                      value: c,
                      child: Text(manualCategoryDisplayName(c)),
                    ))
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => _selectedCategory = value);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('manual_entry_note_field'),
            controller: _noteController,
            decoration: const InputDecoration(labelText: 'Note (optional)'),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              key: const Key('manual_entry_save_button'),
              onPressed: _handleSave,
              child: const Text('Save'),
            ),
          ),
        ],
      ),
    );
  }
}