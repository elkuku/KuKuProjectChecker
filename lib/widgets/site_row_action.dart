import 'package:flutter/material.dart';

/// Where an action is shown on a project/server row.
enum SiteActionPlace {
  /// Small icon button in the collapsed row.
  header,

  /// Labelled button in the expanded details.
  details,
}

/// One allowlisted action on a project or server-only row.
class SiteRowAction {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final SiteActionPlace place;

  /// Uses a filled style for the main action of a group.
  final bool filled;

  /// Uses the error colour for destructive actions.
  final bool danger;

  const SiteRowAction(
    this.icon,
    this.label,
    this.onPressed, {
    this.place = SiteActionPlace.header,
    this.filled = false,
    this.danger = false,
  });

  String get tooltip => label;
}

/// The buttons of a row. [compact] shows only icons, for the collapsed header.
class SiteActionBar extends StatelessWidget {
  final List<SiteRowAction> actions;
  final bool compact;

  const SiteActionBar({
    super.key,
    required this.actions,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: compact ? 2 : 6,
      runSpacing: compact ? 2 : 6,
      children: [for (final action in actions) _button(context, action)],
    );
  }

  Widget _button(BuildContext context, SiteRowAction action) {
    final colors = Theme.of(context).colorScheme;
    final foreground = action.danger
        ? colors.error
        : action.filled
            ? colors.primary
            : null;

    if (compact) {
      return Tooltip(
        message: action.tooltip,
        child: IconButton(
          icon: Icon(action.icon, size: 19, color: foreground),
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.all(6),
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          onPressed: action.onPressed,
        ),
      );
    }

    final label = Text(action.label);
    final style = ButtonStyle(
      visualDensity: VisualDensity.compact,
      padding: WidgetStatePropertyAll(
          const EdgeInsets.symmetric(horizontal: 10, vertical: 2)),
    );

    final button = switch ((action.danger, action.filled)) {
      (true, _) => OutlinedButton.icon(
          style: style,
          icon: Icon(action.icon, size: 17, color: colors.error),
          label: label,
          onPressed: action.onPressed,
        ),
      (_, true) => FilledButton.tonalIcon(
          style: style,
          icon: Icon(action.icon, size: 17),
          label: label,
          onPressed: action.onPressed,
        ),
      _ => OutlinedButton.icon(
          style: style,
          icon: Icon(action.icon, size: 17),
          label: label,
          onPressed: action.onPressed,
        ),
    };
    return Tooltip(message: action.tooltip, child: button);
  }
}
