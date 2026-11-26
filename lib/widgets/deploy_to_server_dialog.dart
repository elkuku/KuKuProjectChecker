import 'package:flutter/material.dart';

import '../screens/changes_screen.dart' show monoTextStyle;
import '../support/db_backup.dart' show DbDumpChoice, ServerDbBackups;
import '../support/deployer.dart' show PushFunction, RunFunction;
import '../support/repo_status.dart';
import '../support/server.dart';
import '../support/site_creator.dart' show NewSite;
import '../support/site_info.dart';
import 'deploy_dialog.dart' show showDeployDialog;
import 'push_log_view.dart';

/// What the dialog created, so the caller can record the target in the project settings.
typedef DeployToServerResult = ({
  String siteName,
  String domain,
  bool pushed,
  String? error,
});

/// Creates a site for a local project on a KMyServer, then pushes the project to it.
/// Returns null when no site was created, otherwise the name/domain to record.
Future<DeployToServerResult?> showDeployToServerDialog(
  BuildContext context, {
  required Server server,
  required SiteInfo site,
  required String domain,
  required String repoPath,
  required RepoStatus status,
  required List<(String, String)> remotes,
  bool dbDetected = false,
  required RunFunction run,
  required PushFunction push,
}) =>
    showDialog<DeployToServerResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DeployToServerDialog(
        server: server,
        site: site,
        domain: domain,
        repoPath: repoPath,
        status: status,
        remotes: remotes,
        dbDetected: dbDetected,
        run: run,
        push: push,
      ),
    );

/// A site name is lowercase letters, digits and dashes, so the project's name is
/// normalised as a suggestion; the user can still edit it.
String suggestedSiteName(String text) {
  final cleaned = text
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return cleaned.length >= 2 ? cleaned : '';
}

enum _Stage { form, running, deploying, done, failed }

class DeployToServerDialog extends StatefulWidget {
  final Server server;
  final SiteInfo site;
  final String domain;
  final String repoPath;
  final RepoStatus status;
  final List<(String, String)> remotes;
  final bool dbDetected;
  final RunFunction run;
  final PushFunction push;

  const DeployToServerDialog({
    super.key,
    required this.server,
    required this.site,
    required this.domain,
    required this.repoPath,
    required this.status,
    required this.remotes,
    this.dbDetected = false,
    required this.run,
    required this.push,
  });

  @override
  State<DeployToServerDialog> createState() => _DeployToServerDialogState();
}

class _DeployToServerDialogState extends State<DeployToServerDialog> {
  final form = GlobalKey<FormState>();
  final ScrollController scroll = ScrollController();

  late final name =
      TextEditingController(text: suggestedSiteName(widget.site.name));
  late final domain = TextEditingController(text: widget.domain);
  late final template =
      TextEditingController(text: suggestedTemplate(widget.remotes) ?? '');

  /// Prefilled from the project's local configuration, but overridable here.
  late bool createDb = widget.dbDetected;
  List<DbDumpChoice> dumps = const [];
  String selectedDump = '';
  bool loadingDumps = false;
  String? dumpsError;

  _Stage stage = _Stage.form;
  final List<String> output = [];
  int exitCode = 0;
  String? error;
  bool raw = false;
  DeployToServerResult? result;

  @override
  void dispose() {
    for (final controller in [name, domain, template, scroll]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (createDb) _loadDumps();
  }

  /// Reads the dated backup sets already on this server. This is read-only; the
  /// dump is only imported after the user confirms and the site has been created.
  Future<void> _loadDumps() async {
    setState(() {
      loadingDumps = true;
      dumpsError = null;
    });
    try {
      final found = await ServerDbBackups.fetch(widget.server, widget.run);
      if (!mounted) return;
      setState(() {
        dumps = found;
        selectedDump = found.isEmpty ? '' : found.first.path;
        loadingDumps = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        selectedDump = '';
        dumpsError = '$e';
        loadingDumps = false;
      });
    }
  }

  /// Use the project's origin (or any other https remote) as site-add's template.
  static String? suggestedTemplate(List<(String, String)> remotes) {
    for (final (remote, url) in remotes) {
      if (remote == 'origin' && NewSite.templateError(url) == null) return url;
    }
    for (final (_, url) in remotes) {
      if (NewSite.templateError(url) == null) return url;
    }
    return null;
  }

  List<String> get siteArgs => widget.server.sshArgs('root', [
        '/usr/local/sbin/site-add',
        name.text.trim(),
        '--domain',
        domain.text.trim(),
        '--template',
        template.text.trim(),
        if (createDb) ...['--db', 'postgresql'],
      ]);

  /// Null when no backup dump is selected: site-add leaves the new database empty.
  List<String>? get importArgs {
    if (!createDb || selectedDump.isEmpty) return null;
    return widget.server.sshArgs('root', [
      '/usr/local/sbin/site-db-import',
      name.text.trim(),
      selectedDump,
    ]);
  }

  /// git needs the new site's remote in the local repository before the push.
  ({String executable, List<String> arguments})? get remoteCommand {
    final existing = widget.remotes
        .where((remote) => remote.$1 == widget.server.remote)
        .firstOrNull;
    final url = widget.server.siteRepoUrl(name.text.trim());
    if (existing == null) {
      return (
        executable: 'git',
        arguments: [
          '-C',
          widget.repoPath,
          'remote',
          'add',
          widget.server.remote,
          url,
        ]
      );
    }
    if (existing.$2 == url) return null;
    return (
      executable: 'git',
      arguments: [
        '-C',
        widget.repoPath,
        'remote',
        'set-url',
        widget.server.remote,
        url,
      ]
    );
  }

  void _log(String line) {
    if (!mounted) return;
    setState(() => output.add(line));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scroll.hasClients) scroll.jumpTo(scroll.position.maxScrollExtent);
    });
  }

  Future<void> _create() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      stage = _Stage.running;
      output.clear();
      error = null;
    });

    final siteName = name.text.trim();
    try {
      exitCode = await widget.run('ssh', siteArgs, _log);
      if (exitCode != 0) {
        if (mounted) {
          setState(() {
            error = 'Creating $siteName on ${widget.server.name} failed';
            stage = _Stage.failed;
          });
        }
        return;
      }
      final remote = remoteCommand;
      if (remote != null) {
        exitCode = await widget.run(remote.executable, remote.arguments, _log);
        if (exitCode != 0) {
          if (mounted) {
            setState(() {
              error = 'Setting the deploy remote failed';
              stage = _Stage.failed;
            });
          }
          return;
        }
      }

      // The database is still empty here. Import the chosen dump before the push,
      // so a failed restore stops the flow instead of deploying onto a wrong DB.
      final import = importArgs;
      if (import != null) {
        exitCode = await widget.run('ssh', import, _log);
        if (exitCode != 0) {
          if (mounted) {
            // The site and its database were created; record them, but never
            // claim that the deploy finished.
            result = (
              siteName: siteName,
              domain: domain.text.trim(),
              pushed: false,
              error: 'Importing the database backup failed (exit $exitCode): '
                  'the site and its database were created, but nothing was deployed',
            );
            setState(() {
              error = result!.error;
              stage = _Stage.failed;
            });
          }
          return;
        }
      }

      // The site exists now, so the usual deploy dialog can push to its repository.
      // That dialog has its own progress indicator, so this one stops animating.
      if (!mounted) return;
      setState(() => stage = _Stage.deploying);
      final pushed = await showDeployDialog(
        context,
        siteName: siteName,
        repoPath: widget.repoPath,
        status: RepoStatus(
          branch: widget.status.branch,
          uncommitted: widget.status.uncommitted,
          unpushed: widget.status.unpushed,
          deployRemote: widget.server.remote,
          deployUrl: widget.server.siteRepoUrl(siteName),
          undeployed: null,
        ),
        push: widget.push,
      );
      if (!mounted) return;
      // Record the target even when the push/deploy did not finish: the site now exists.
      result = (
        siteName: siteName,
        domain: domain.text.trim(),
        pushed: pushed,
        error: null,
      );
      setState(() {
        stage = pushed ? _Stage.done : _Stage.failed;
        error = pushed
            ? null
            : 'The site was created, but the deploy did not finish. '
                'Check the output above.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        output.add('$e');
        error = 'Something went wrong';
        stage = _Stage.failed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final running = stage == _Stage.running;

    return AlertDialog(
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
        _Stage.form => 'Deploy ${widget.site.name} to ${widget.server.name}?',
        _Stage.running => 'Creating ${name.text.trim()} …',
        _Stage.deploying => 'Deploying ${name.text.trim()} …',
        _Stage.done => '${name.text.trim()} is live on ${widget.server.name}',
        _Stage.failed => 'Could not deploy ${name.text.trim()}',
      }),
      content: SizedBox(
        width: 620,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (stage == _Stage.form) ...[
              const Text(
                'Creates the site on the server from the project’s git remote, '
                'then pushes the local branch to it.',
              ),
              const SizedBox(height: 12),
              Form(
                key: form,
                child: Column(
                  children: [
                    TextFormField(
                      controller: name,
                      validator: (value) => NewSite.nameError(value ?? ''),
                      decoration: const InputDecoration(
                        labelText: 'Site name on the server',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: domain,
                      validator: (value) => NewSite.domainError(value ?? ''),
                      decoration: const InputDecoration(
                        labelText: 'Domain',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: template,
                      validator: (value) => NewSite.templateError(value ?? ''),
                      decoration: const InputDecoration(
                        labelText: 'Template (public https git URL)',
                        border: OutlineInputBorder(),
                        helperText: 'site-add deploys this repository first',
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.remotes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final (remote, url) in widget.remotes)
                      ActionChip(
                        label: Text(remote,
                            style: monoTextStyle.copyWith(fontSize: 11)),
                        tooltip: url,
                        onPressed: () => setState(() => template.text = url),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 4),
              CheckboxListTile(
                value: createDb,
                dense: true,
                contentPadding: EdgeInsets.zero,
                onChanged: running
                    ? null
                    : (value) {
                        setState(() => createDb = value ?? false);
                        if (createDb && dumps.isEmpty && dumpsError == null) {
                          _loadDumps();
                        }
                      },
                title: const Text('Create PostgreSQL database'),
                subtitle: Text(widget.dbDetected
                    ? 'Detected in this project’s local configuration.'
                    : 'This project does not seem to use a database.'),
              ),
              if (createDb) ...[
                if (loadingDumps)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: LinearProgressIndicator(),
                  ),
                if (dumpsError != null)
                  Text(dumpsError!,
                      style: TextStyle(color: theme.colorScheme.error)),
                DropdownButtonFormField<String>(
                  // A new key when the list arrives makes initialValue follow the
                  // newest dump; later user choices keep the same form field.
                  key: ValueKey(dumps.isEmpty ? 'empty' : dumps.first.path),
                  initialValue: selectedDump,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Import a backup',
                    helperText:
                        'Restored into the new database before the deploy',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('No backup (empty database)'),
                    ),
                    for (final dump in dumps)
                      DropdownMenuItem(
                        value: dump.path,
                        child: Text(dump.label),
                      ),
                  ],
                  onChanged: loadingDumps
                      ? null
                      : (value) => setState(() => selectedDump = value ?? ''),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                [
                  'ssh ${siteArgs.join(' ')}',
                  if (remoteCommand case final command?)
                    '${command.executable} ${command.arguments.join(' ')}',
                  if (importArgs case final command?)
                    'ssh ${command.join(' ')}',
                  'git push ${widget.server.remote} ${widget.status.branch}',
                ].join('\n'),
                style: monoTextStyle.copyWith(
                    fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
              ),
            ] else ...[
              if (running) const LinearProgressIndicator(),
              if (stage == _Stage.failed && error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '$error (exit $exitCode)',
                    style: TextStyle(
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              if (stage == _Stage.done)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text('The project is deployed to the new site.'),
                ),
              PushLogView(
                output: output,
                raw: raw,
                running: running,
                controller: scroll,
              ),
              if (!running)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => setState(() => raw = !raw),
                    icon:
                        Icon(raw ? Icons.summarize : Icons.terminal, size: 18),
                    label: Text(raw ? 'Summary' : 'Show full output'),
                  ),
                ),
            ],
          ],
        ),
      ),
      actions: switch (stage) {
        _Stage.form => [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: _create,
              icon: const Icon(Icons.rocket_launch),
              label: const Text('Create and deploy'),
            ),
          ],
        _Stage.running || _Stage.deploying => const [],
        _ => [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(result),
              child: const Text('Close'),
            ),
          ],
      },
    );
  }
}
