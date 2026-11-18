import 'package:flutter/material.dart';

import '../screens/changes_screen.dart' show monoTextStyle;
import 'push_log_view.dart';
import '../support/deployer.dart' show PushFunction;
import '../support/repo_status.dart';

/// Asks before deploying, then shows git's output while pushing to the deploy remote.
/// Returns true if the push succeeded.
Future<bool> showDeployDialog(
  BuildContext context, {
  required String siteName,
  required String repoPath,
  required RepoStatus status,
  required PushFunction push,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => DeployDialog(
      siteName: siteName,
      repoPath: repoPath,
      status: status,
      push: push,
    ),
  );

  return result ?? false;
}

enum _Stage { confirm, running, done, failed }

class DeployDialog extends StatefulWidget {
  final String siteName;
  final String repoPath;
  final RepoStatus status;
  final PushFunction push;

  const DeployDialog({
    super.key,
    required this.siteName,
    required this.repoPath,
    required this.status,
    required this.push,
  });

  @override
  State<DeployDialog> createState() => _DeployDialogState();
}

class _DeployDialogState extends State<DeployDialog> {
  _Stage stage = _Stage.confirm;
  final List<String> output = [];

  /// Shows git's output as it is, without sorting out the noise.
  bool raw = false;
  final ScrollController scroll = ScrollController();

  String get remote => widget.status.deployRemote!;
  String get branch => widget.status.branch;

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  Future<void> _deploy() async {
    setState(() => stage = _Stage.running);

    int exitCode;
    try {
      exitCode = await widget.push(widget.repoPath, remote, branch, (line) {
        if (!mounted) return;
        setState(() => output.add(line));
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (scroll.hasClients) scroll.jumpTo(scroll.position.maxScrollExtent);
        });
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
    final status = widget.status;

    return AlertDialog(
      // Scrolls instead of overflowing in a low window.
      scrollable: true,
      icon: Icon(switch (stage) {
        _Stage.done => Icons.check_circle,
        _Stage.failed => Icons.error,
        _ => Icons.rocket_launch,
      }),
      iconColor: switch (stage) {
        _Stage.done => Colors.green,
        _Stage.failed => theme.colorScheme.error,
        _ => null,
      },
      title: Text(switch (stage) {
        _Stage.confirm => 'Deploy ${widget.siteName}?',
        _Stage.running => 'Deploying ${widget.siteName} …',
        _Stage.done => 'Pushed to $remote',
        _Stage.failed => 'The push failed',
      }),
      content: SizedBox(
        width: 640,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (stage == _Stage.confirm) ...[
              Text.rich(TextSpan(children: [
                const TextSpan(text: 'Pushes '),
                TextSpan(text: branch, style: monoTextStyle),
                const TextSpan(text: ' to '),
                TextSpan(text: remote, style: monoTextStyle),
                TextSpan(
                    text: switch (status.undeployed) {
                  null => ' for the first time.',
                  0 => '. It has no new commits.',
                  1 => ': 1 new commit.',
                  final n => ': $n new commits.',
                }),
              ])),
              const SizedBox(height: 4),
              const Text('The server deploys the new version after the push.'),
              if (status.uncommitted > 0)
                _Warning(
                    '${status.uncommitted} uncommitted file${status.uncommitted == 1 ? ' is' : 's are'} not included.'),
              if ((status.unpushed ?? 0) > 0)
                _Warning(
                    '${status.unpushed} commit${status.unpushed == 1 ? ' is' : 's are'} not pushed to the upstream (e.g. GitHub) yet.'),
              if (status.unpushed == null)
                const _Warning('The branch has no upstream (e.g. GitHub).'),
            ] else ...[
              if (stage == _Stage.running) const LinearProgressIndicator(),
              if (stage == _Stage.done)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text('The server deploys the new version now.'),
                ),
              const SizedBox(height: 8),
              PushLogView(
                output: output,
                raw: raw,
                running: stage == _Stage.running,
                controller: scroll,
              ),
              if (stage != _Stage.running)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => setState(() => raw = !raw),
                    icon: Icon(raw ? Icons.notes : Icons.terminal, size: 18),
                    label: Text(raw ? 'Summary' : 'Show full output'),
                  ),
                ),
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
              onPressed: _deploy,
              icon: const Icon(Icons.rocket_launch),
              label: const Text('Deploy'),
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

class _Warning extends StatelessWidget {
  final String text;

  const _Warning(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber, size: 18, color: Colors.orange),
          const SizedBox(width: 6),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
