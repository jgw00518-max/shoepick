import 'package:flutter/material.dart';

class ListOrderDropdown extends StatelessWidget {
  const ListOrderDropdown({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final String value;
  final ValueChanged<String>? onChanged;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 160,
    child: DropdownButtonFormField<String>(
      key: ValueKey('list-order-$value'),
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: '정렬',
        border: OutlineInputBorder(),
      ),
      items: const [
        DropdownMenuItem(value: 'desc', child: Text('최신순')),
        DropdownMenuItem(value: 'asc', child: Text('오래된순')),
      ],
      onChanged: onChanged == null
          ? null
          : (value) {
              if (value != null) {
                onChanged!(value);
              }
            },
    ),
  );
}
