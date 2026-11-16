import 'package:flutter/material.dart';

class WorkspaceSelect<T> extends StatelessWidget {
  const WorkspaceSelect({
    super.key,
    required this.label,
    required this.choices,
    required this.onChanged,
    this.initial,
    this.icon,
    this.validator,
  });

  final String label;
  final Map<T, String> choices;
  final ValueChanged<T> onChanged;
  final T? initial;
  final IconData? icon;
  final FormFieldValidator<T>? validator;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return DropdownButtonFormField<T>(
      initialValue: choices.containsKey(initial) ? initial : null,
      isExpanded: true,
      isDense: true,
      style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurface),
      menuMaxHeight: 288,
      borderRadius: BorderRadius.circular(12),
      dropdownColor: colors.surface,
      icon: Icon(Icons.expand_more_rounded, size: 19, color: colors.primary),
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 11,
        ),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 34,
          minHeight: 22,
        ),
        prefixIcon: icon == null
            ? null
            : Icon(icon, size: 17, color: colors.primary),
      ),
      items: [
        for (final choice in choices.entries)
          DropdownMenuItem(
            value: choice.key,
            child: Text(
              choice.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
      validator: validator,
    );
  }
}
