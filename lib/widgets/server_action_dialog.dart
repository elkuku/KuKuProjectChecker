import 'package:flutter/material.dart';

import '../screens/changes_screen.dart' show monoTextStyle;
import '../support/deployer.dart' show RunFunction;
import '../support/server.dart';
import '../support/server_actions.dart';
import 'push_log_view.dart';

/// Runs one allowlisted server action: asks first, streams the output and shows the exit code.
/// Returns true only when the command exited 0.
Future<bool> showServerActionDialog(
  BuildContext context, {
  required ServerAction action,
  required Server server,
  required String siteName,
  required RunFunction run,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ServerActionDialog(
      action: action,
      server: server,
      siteName: siteName,
      run: run,
    ),
  );
  return result ?? false;
}

enum _Stage { confirm, dryRun, running, done, failed }

class ServerActionDialog extends StatefulWidget {
  final ServerAction action;
  final Server server;
  final String siteName;
  final RunFunction run;

  const ServerActionDialog({
    super.key,
    required this.action,
    required this.server,
    required this.siteName,
    required this.run,
  });

  @override
  State<ServerActionDialog> createState() => _ServerActionDialogState();
}

class _ServerActionDialogState extends State<ServerActionDialog> {
  _Stage stage = _Stage.confirm;
  final List<String> output = [];
  final TextEditingController typed = TextEditingController();
  final ScrollController scroll = ScrollController();
  int exitCode = 0;
  bool dropDb = false;
  bool dropConfirmed = false;
  bool showRaw = true;

  @override
  void dispose() {
    typed.dispose();
    scroll.dispose();
    super.dispose();
  }

  bool get isRemove => widget.action.risk == ServerActionRisk.destructive;

  IconData get icon => switch (widget.action.id) {
        'backup' => Icons.backup,
        'mailTest' => Icons.mail_outline,
        'releases' => Icons.list_alt,
        'rollback' => Icons.history,
        'remove' => Icons.delete_outline,
        _ => Icons.article_outlined,
      };

  Future<void> _run({bool confirmed = false, bool clear = false}) async {
    setState(() {
      stage = _Stage.running;
      if (clear) output.clear();
    });

    int code;
    try {
      code = await widget.run(
        'ssh',
        widget.action.sshArgs(widget.server, widget.siteName,
            confirmed: confirmed, dropDb: dropDb),
        (line) {
          if (!mounted) return;
          setState(() => output.add(line));
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (scroll.hasClients) {
              scroll.jumpTo(scroll.position.maxScrollExtent);
            }
          });
        },
      );
    } catch (e) {
      output.add('$e');
      code = -1;
    }

    if (!mounted) return;
    setState(() {
      exitCode = code;
      output.add('== exit $code');
      stage = code == 0
          ? (widget.action.dryRun && !confirmed ? _Stage.dryRun : _Stage.done)
          : _Stage.failed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final action = widget.action;
    final warning = action.risk == ServerActionRisk.destructive ||
        action.risk == ServerActionRisk.write;

    return AlertDialog(
      scrollable: true,
      icon: Icon(switch (stage) {
        _Stage.done => Icons.check_circle,
        _Stage.failed => Icons.error,
        _ => icon,
      }),
      iconColor: switch (stage) {
        _Stage.done => Colors.green,
        _Stage.failed => theme.colorScheme.error,
        _ => null,
      },
      title: Text(switch (stage) {
        _Stage.confirm =>
          action.dryRun ? 'Dry run: ${widget.siteName}?' : action.confirmation,
        _Stage.dryRun => 'Remove ${widget.siteName}?',
        _Stage.running => '${action.label} …',
        _Stage.done => '${action.label} finished',
        _Stage.failed => '${action.label} failed',
      }),
      content: SizedBox(
        width: 600,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (stage == _Stage.confirm) ...[
              Text(action.description),
              const SizedBox(height: 10),
              Text(
                  'ssh ${action.sshArgs(widget.server, widget.siteName).join(' ')}',
                  style: monoTextStyle.copyWith(
                      fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
              if (warning)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber,
                          size: 18, color: theme.colorScheme.error),
                      const SizedBox(width: 6),
                      Expanded(child: Text(action.confirmation)),
                    ],
                  ),
                ),
            ] else ...[
              if (stage == _Stage.running) const LinearProgressIndicator(),
              if (stage == _Stage.dryRun)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Nothing was changed. Check the plan above, then type the site name.',
                  ),
                ),
              if (stage == _Stage.done || stage == _Stage.failed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    stage == _Stage.done
                        ? 'Finished with exit $exitCode.'
                        : 'Failed with exit $exitCode.',
                    style: TextStyle(
                        color: stage == _Stage.done
                            ? null
                            : theme.colorScheme.error,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              PushLogView(
                output: output,
                raw: showRaw,
                running: stage == _Stage.running,
                controller: scroll,
              ),
              if (stage != _Stage.running)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => setState(() => showRaw = !showRaw),
                    icon: Icon(showRaw ? Icons.summarize : Icons.terminal,
                        size: 18),
                    label: Text(showRaw ? 'Summary' : 'Show full output'),
                  ),
                ),
              if (stage == _Stage.dryRun) ...[
                TextField(
                  controller: typed,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Type ${widget.siteName} to confirm',
                    border: const OutlineInputBorder(),
                  ),
                ),
                CheckboxListTile(
                  value: dropDb,
                  onChanged: (value) => setState(() {
                    dropDb = value ?? false;
                    if (!dropDb) dropConfirmed = false;
                  }),
                  title: const Text('Also drop the database and its role'),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                if (dropDb)
                  CheckboxListTile(
                    value: dropConfirmed,
                    onChanged: (value) =>
                        setState(() => dropConfirmed = value ?? false),
                    title:
                        const Text('Confirm: the database cannot be restored'),
                    subtitle: const Text(
                        'The final backup stays on the server for 14 days.'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
              ],
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
              onPressed: () => _run(confirmed: false),
              icon: Icon(action.dryRun ? Icons.visibility_outlined : icon),
              label: Text(action.dryRun ? 'Show dry run' : action.label),
            ),
          ],
        _Stage.dryRun => [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed:
                  typed.text == widget.siteName && (!dropDb || dropConfirmed)
                      ? () => _run(confirmed: true, clear: true)
                      : null,
              icon: const Icon(Icons.delete_outline),
              label: Text(dropDb ? 'Remove and drop DB' : 'Remove site'),
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
