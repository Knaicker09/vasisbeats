import 'package:flutter/material.dart';

const List<int> _presetMinutes = [5, 10, 15, 30];

/// Practice timer picker: 5/10/15/30-minute chips plus a custom length.
/// Stateless — the caller owns the selected value.
class PracticeTimerPicker extends StatelessWidget {
  final int? selectedMinutes;
  final ValueChanged<int> onSelected;
  final VoidCallback onCancel;

  const PracticeTimerPicker({
    super.key,
    required this.selectedMinutes,
    required this.onSelected,
    required this.onCancel,
  });

  Future<void> _pickCustom(BuildContext context) async {
    final controller = TextEditingController();
    final minutes = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Custom timer'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(suffixText: 'minutes'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, int.tryParse(controller.text)),
            child: const Text('Set'),
          ),
        ],
      ),
    );
    if (minutes != null && minutes > 0) onSelected(minutes);
  }

  @override
  Widget build(BuildContext context) {
    final customSelected =
        selectedMinutes != null && !_presetMinutes.contains(selectedMinutes);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final minutes in _presetMinutes)
          ChoiceChip(
            label: Text('$minutes min'),
            selected: selectedMinutes == minutes,
            onSelected: (_) => onSelected(minutes),
          ),
        ChoiceChip(
          avatar: const Icon(Icons.edit, size: 16),
          label: Text(customSelected ? '$selectedMinutes min' : 'Custom'),
          selected: customSelected,
          onSelected: (_) => _pickCustom(context),
        ),
        if (selectedMinutes != null)
          TextButton.icon(
            onPressed: onCancel,
            icon: const Icon(Icons.close, size: 16),
            label: const Text('No timer'),
          ),
      ],
    );
  }
}
