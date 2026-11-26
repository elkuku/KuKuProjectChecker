import 'package:flutter/material.dart';

import '../support/deployer.dart' show RunFunction;
import '../support/server.dart';
import '../support/server_actions.dart';
import '../support/server_api.dart';
import '../support/server_health.dart';
import '../widgets/server_action_dialog.dart';
import 'changes_screen.dart' show monoTextStyle;

typedef RunServerAction = Future<bool> Function(ServerAction action);
typedef NewSiteFromServer = Future<void> Function();

/// One KMyServer server: a read-only report plus the allowlisted actions in [ServerAction].
///
/// The [report] and its [onReload] are owned by the parent so the main screen can share the
/// site statuses with the site list. The standalone screen uses [_ServerStatusLoader] below.
class ServerStatusPanel extends StatelessWidget {
  final Server server;
  final Future<ServerHealth> report;
  final VoidCallback onReload;
  final RunFunction run;

  /// The existing new-site wizard, linked here so site creation stays in one place.
  final NewSiteFromServer? onNewSite;

  const ServerStatusPanel({
    super.key,
    required this.server,
    required this.report,
    required this.onReload,
    required this.run,
    this.onNewSite,
  });

  Future<bool> _runAction(BuildContext context, ServerAction action) async {
    final done = await showServerActionDialog(
      context,
      action: action,
      server: server,
      siteName: '',
      run: run,
    );
    // Reading a log does not change the report; don't run a second health check for it.
    if (done && action.risk != ServerActionRisk.read) onReload();
    return done;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Server: ${server.name}',
                  style: theme.textTheme.titleMedium),
            ),
            IconButton(
              onPressed: onReload,
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        FutureBuilder<ServerHealth>(
          future: report,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_off_outlined,
                        size: 32, color: colors.error),
                    const SizedBox(height: 8),
                    const Text('Could not read the server'),
                    const SizedBox(height: 6),
                    Text('${snapshot.error}',
                        style: monoTextStyle.copyWith(fontSize: 12),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: onReload,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try again'),
                    ),
                  ],
                ),
              );
            }
            if (!snapshot.hasData) {
              return const SizedBox(
                  height: 160,
                  child: Center(child: CircularProgressIndicator()));
            }
            return ServerStatusReport(
              report: snapshot.data!,
              onAction: (action) => _runAction(context, action),
              onNewSite: onNewSite,
            );
          },
        ),
      ],
    );
  }
}

/// Owns the report for the standalone screen and reloads it after a write action.
class _ServerStatusLoader extends StatefulWidget {
  final Server server;
  final FetchServerHealth fetch;
  final RunFunction run;
  final NewSiteFromServer? onNewSite;

  const _ServerStatusLoader({
    required this.server,
    required this.fetch,
    required this.run,
    this.onNewSite,
  });

  @override
  State<_ServerStatusLoader> createState() => _ServerStatusLoaderState();
}

class _ServerStatusLoaderState extends State<_ServerStatusLoader> {
  late Future<ServerHealth> report = widget.fetch(widget.server);

  @override
  void didUpdateWidget(covariant _ServerStatusLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.server != widget.server) {
      final next = widget.fetch(widget.server);
      setState(() {
        report = next;
      });
    }
  }

  void _reload() {
    final next = widget.fetch(widget.server);
    setState(() {
      report = next;
    });
  }

  @override
  Widget build(BuildContext context) => ServerStatusPanel(
        server: widget.server,
        report: report,
        onReload: _reload,
        run: widget.run,
        onNewSite: widget.onNewSite,
      );
}

/// Standalone screen: the panel above, in a scrollable page.
class ServerStatusScreen extends StatelessWidget {
  final Server server;
  final FetchServerHealth fetch;
  final RunFunction run;
  final NewSiteFromServer? onNewSite;

  const ServerStatusScreen({
    super.key,
    required this.server,
    required this.fetch,
    required this.run,
    this.onNewSite,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: colors.inversePrimary,
        title: const Text('Server status'),
      ),
      body: SingleChildScrollView(
        child: _ServerStatusLoader(
          server: server,
          fetch: fetch,
          run: run,
          onNewSite: onNewSite,
        ),
      ),
    );
  }
}

class ServerStatusReport extends StatelessWidget {
  final ServerHealth report;
  final RunServerAction onAction;
  final NewSiteFromServer? onNewSite;

  const ServerStatusReport({
    super.key,
    required this.report,
    required this.onAction,
    this.onNewSite,
  });

  @override
  Widget build(BuildContext context) {
    final generated =
        report.generatedAt?.toLocal().toString().substring(0, 19) ?? '-';
    final warnings = report.warnings;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Section(
            title: report.host.isEmpty ? 'Server' : report.host,
            subtitle: 'Checked $generated · ${report.problems} problem(s)',
            children: [
              if (warnings.isEmpty)
                const _StatusLine(
                    ok: true, label: 'Everything looks OK', value: ''),
              for (final warning in warnings)
                _StatusLine(ok: false, label: warning, value: ''),
              const SizedBox(height: 4),
              _Actions(
                actions: ServerAction.serverActions,
                onAction: onAction,
                onNewSite: onNewSite,
              ),
            ],
          ),
          _Section(
            title: 'System',
            children: [
              _Row(label: 'OS', value: report.system.os),
              _Row(label: 'Kernel', value: report.system.kernel),
              _Row(label: 'Uptime', value: report.system.uptime),
              _StatusLine(
                ok: !report.system.rebootRequired,
                label: report.system.rebootRequired
                    ? 'Reboot required by ${report.system.rebootPackages.join(', ')}'
                    : 'No reboot required',
                value: '',
              ),
            ],
          ),
          _Section(
            title: 'Services',
            children: [
              for (final service in report.services)
                _StatusLine(
                  ok: service.ok,
                  label: service.name,
                  value: service.state,
                ),
              if (report.failedUnits.isNotEmpty)
                _StatusLine(
                  ok: false,
                  label: 'Failed units',
                  value: report.failedUnits.join(', '),
                ),
            ],
          ),
          _Section(
            title: 'Disk, memory',
            children: [
              for (final entry in report.disk)
                _StatusLine(
                  ok: entry.percent < 85,
                  label: '${entry.mount}  ${entry.used} of ${entry.size}',
                  value: '${entry.percent}% (${entry.available} free)',
                ),
              _Row(
                  label: 'Memory',
                  value: '${report.memory.used} of ${report.memory.total}'),
            ],
          ),
          _Section(
            title: 'Updates, security',
            children: [
              _Row(
                  label: 'OS updates',
                  value: '${report.updates.pending} pending'),
              _Row(
                  label: 'Last unattended upgrade',
                  value: report.updates.lastUnattended),
              _Row(
                label: 'fail2ban sshd',
                value:
                    '${report.security.bannedNow} banned now, ${report.security.bannedTotal} total',
              ),
              _Row(
                label: 'Listening ports',
                value: report.security.listening.join(', '),
              ),
              _Row(
                label: 'Firewall',
                value: report.security.firewall.join(', '),
              ),
            ],
          ),
          _Section(
            title: 'Backup',
            children: [
              _StatusLine(
                ok: report.backup.ok,
                label: report.backup.lastOk.isEmpty
                    ? 'No backup yet'
                    : 'Last ok ${report.backup.lastOk} '
                        '(${report.backup.ageHours} h ago, ${report.backup.sets} sets)',
                value: '',
              ),
            ],
          ),
          _Section(
            title: 'Mail',
            children: [
              _StatusLine(
                ok: report.mail.configured && report.mail.ok,
                label: report.mail.configured
                    ? 'Send-only mail'
                    : 'Mail is not set up',
                value: report.mail.last.isEmpty
                    ? 'nothing sent yet'
                    : report.mail.last,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

IconData _icon(ServerAction action) => switch (action.id) {
      'backup' => Icons.backup,
      'mailTest' => Icons.mail_outline,
      'releases' => Icons.list_alt,
      'rollback' => Icons.history,
      'remove' => Icons.delete_outline,
      _ => Icons.article_outlined,
    };

class _Actions extends StatelessWidget {
  final List<ServerAction> actions;
  final RunServerAction onAction;
  final NewSiteFromServer? onNewSite;

  const _Actions({
    required this.actions,
    required this.onAction,
    this.onNewSite,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Wrap(
      spacing: 6,
      runSpacing: 2,
      children: [
        for (final action in actions)
          OutlinedButton.icon(
            onPressed: () => onAction(action),
            icon: Icon(_icon(action), size: 17),
            label: Text(action.label),
            style: action.risk == ServerActionRisk.destructive
                ? OutlinedButton.styleFrom(foregroundColor: colors.error)
                : null,
          ),
        if (onNewSite != null)
          OutlinedButton.icon(
            onPressed: () => onNewSite!(),
            icon: const Icon(Icons.add, size: 17),
            label: const Text('New site…'),
          ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;

  const _Section({required this.title, this.subtitle, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 6),
                child: Text(subtitle!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ),
            const SizedBox(height: 6),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;

  const _Row({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 150,
              child: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            Expanded(child: Text(value, style: monoTextStyle)),
          ],
        ),
      );
}

class _StatusLine extends StatelessWidget {
  final bool ok;
  final String label;
  final String value;

  const _StatusLine({required this.ok, required this.label, this.value = ''});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = ok
        ? (dark ? Colors.green.shade300 : Colors.green.shade800)
        : colors.error;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 8),
            child: Icon(
              ok ? Icons.check_circle_outline : Icons.error_outline,
              size: 17,
              color: color,
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? label : '$label  $value',
              style: TextStyle(
                color: ok ? null : color,
                fontWeight: ok ? null : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
