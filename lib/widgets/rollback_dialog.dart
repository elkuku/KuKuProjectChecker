import 'package:flutter/material.dart';

import '../screens/changes_screen.dart' show monoTextStyle;
import '../support/deployer.dart' show RollbackFunction;
import '../support/kmyserver.dart';
import 'push_log_view.dart';

/// Asks before rolling a KMyServer site back to its previous release, then shows the
/// server's answer. Returns true if the rollback succeeded.
Future<bool> showRollbackDialog(
  BuildContext context, {
  required String siteName,
  required KMyServerSite site,
  required RollbackFunction rollback,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        RollbackDialog(siteName: siteName, site: site, rollback: rollback),
  );

  return result ?? false;
}

enum _Stage { confirm, running, done, failed }

class RollbackDialog extends StatefulWidget {
  final String siteName;
  final KMyServerSite site;
  final RollbackFunction rollback;

  const RollbackDialog({
    super.key,
    required this.siteName,
    required this.site,
    required this.rollback,
  });

  @override
  State<RollbackDialog> createState() => _RollbackDialogState();
}

class _RollbackDialogState extends State<RollbackDialog> {
  _Stage stage = _Stage.confirm;
  final List<String> output = [];

  Future<void> _rollback() async {
    setState(() => stage = _Stage.running);

    int exitCode;
    try {
      exitCode = await widget.rollback(widget.site, (line) {
        if (mounted) setState(() => output.add(line));
      });
    } catch (e) {
      output.add('$e');
      exitCode = -1;
    }

    if (mounted) {
      setState(() => stage = exitCode == 0 ? _Stage.done : _Stage.failed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      scrollable: true,
      icon: Icon(switch (stage) {
        _Stage.done => Icons.check_circle,
        _Stage.failed => Icons.error,
        _ => Icons.history,
      }),
      iconColor: switch (stage) {
        _Stage.done => Colors.green,
        _Stage.failed => theme.colorScheme.error,
        _ => null,
      },
      title: Text(switch (stage) {
        _Stage.confirm => 'Roll back ${widget.siteName}?',
        _Stage.running => 'Rolling back ${widget.siteName} …',
        _Stage.done => 'Rolled back',
        _Stage.failed => 'The rollback failed',
      }),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (stage == _Stage.confirm) ...[
              Text.rich(TextSpan(children: [
                const TextSpan(
                    text:
                        'Switches the live site back to its previous release on '),
                TextSpan(text: widget.site.host, style: monoTextStyle),
                const TextSpan(text: '.'),
              ])),
              const SizedBox(height: 8),
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber, size: 18, color: Colors.orange),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                        'Only the code goes back. The database stays as it is: '
                        'migrations of the newer release are not undone.'),
                  ),
                ],
              ),
            ] else ...[
              if (stage == _Stage.running) const LinearProgressIndicator(),
              const SizedBox(height: 8),
              PushLogView(output: output, running: stage == _Stage.running),
            ],
          ],
        ),
      ),
      actions: switch (stage) {
        _Stage.confirm => [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: _rollback,
              icon: const Icon(Icons.history),
              label: const Text('Roll back'),
            ),
          ],
        _Stage.running => const [],
        _ => [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(stage == _Stage.done),
              child: const Text('Close'),
            ),
          ],
      },
    );
  }
}
