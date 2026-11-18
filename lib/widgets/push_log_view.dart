import 'package:flutter/material.dart';

import '../screens/changes_screen.dart' show monoTextStyle;
import '../support/push_log.dart';

/// The output of a push: the result lines stand out, noise is hidden unless [raw].
class PushLogView extends StatelessWidget {
  final List<String> output;
  final bool raw;
  final bool running;
  final ScrollController? controller;

  const PushLogView({
    super.key,
    required this.output,
    this.raw = false,
    this.running = false,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final lines = raw
        ? [for (final line in output) PushLine(PushLineKind.progress, line)]
        : [
            for (final line in parsePushOutput(output))
              if (line.kind != PushLineKind.noise) line
          ];

    return Container(
      height: 240,
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectionArea(
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            for (final line in lines) _LogLine(line: line, raw: raw),
            if (lines.isEmpty && running)
              const _LogLine(
                  line: PushLine(PushLineKind.progress, 'Connecting …')),
          ],
        ),
      ),
    );
  }
}

class _LogLine extends StatelessWidget {
  final PushLine line;
  final bool raw;

  const _LogLine({required this.line, this.raw = false});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final green = dark ? Colors.green.shade300 : Colors.green.shade800;
    final orange = dark ? Colors.orange.shade300 : Colors.orange.shade900;

    final (IconData? icon, Color color, FontWeight weight, Color? background) =
        switch (line.kind) {
      PushLineKind.updated => (
          Icons.check_circle,
          green,
          FontWeight.w600,
          Colors.green.withValues(alpha: dark ? 0.16 : 0.10)
        ),
      PushLineKind.error => (
          Icons.error,
          colors.error,
          FontWeight.w600,
          colors.error.withValues(alpha: 0.10)
        ),
      PushLineKind.warning => (
          Icons.warning_amber,
          orange,
          FontWeight.normal,
          null
        ),
      PushLineKind.target => (
          Icons.dns_outlined,
          colors.primary,
          FontWeight.w500,
          null
        ),
      PushLineKind.server => (
          Icons.chevron_right,
          colors.onSurfaceVariant,
          FontWeight.normal,
          null
        ),
      _ => (null, colors.onSurfaceVariant, FontWeight.normal, null),
    };

    return Container(
      color: background,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!raw)
            SizedBox(
              width: 22,
              child: icon == null
                  ? null
                  : Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Icon(icon, size: 15, color: color),
                    ),
            ),
          Expanded(
            child: Text(
              line.text,
              style: monoTextStyle.copyWith(
                  fontSize: 12.5,
                  color: color,
                  fontWeight: weight,
                  height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}
