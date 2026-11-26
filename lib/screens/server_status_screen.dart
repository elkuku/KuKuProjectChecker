import 'package:flutter/material.dart';

import '../support/deployer.dart' show RunFunction;
import '../support/server.dart';
import '../support/server_actions.dart';
import '../support/server_api.dart';
import '../support/server_health.dart';
import '../widgets/server_action_dialog.dart';
import 'changes_screen.dart' show monoTextStyle;

typedef RunServerAction = Future<bool> Function(
    ServerAction action, SiteHealth? site);
typedef DeploySiteFromServer = Future<bool> Function(SiteHealth site);
typedef NewSiteFromServer = Future<void> Function();

/// One KMyServer server: a read-only report plus the allowlisted actions in [ServerAction].
class ServerStatusScreen extends StatefulWidget {
  final Server server;
  final FetchServerHealth fetch;
  final RunFunction run;

  /// The existing site-card deploy, so deploys are still a git push from the local repository.
  final DeploySiteFromServer? onDeploy;

  /// The existing new-site wizard, linked here so site creation stays in one place.
  final NewSiteFromServer? onNewSite;

  const ServerStatusScreen({
    super.key,
    required this.server,
    required this.fetch,
    required this.run,
    this.onDeploy,
    this.onNewSite,
  });

  @override
  State<ServerStatusScreen> createState() => _ServerStatusScreenState();
}

class _ServerStatusScreenState extends State<ServerStatusScreen> {
  late Future<ServerHealth> report = widget.fetch(widget.server);

  void _reload() {
    setState(() {
      report = widget.fetch(widget.server);
    });
  }

  Future<bool> _runAction(ServerAction action, SiteHealth? site) async {
    final done = await showServerActionDialog(
      context,
      action: action,
      server: widget.server,
      siteName: site?.name ?? '',
      run: widget.run,
    );
    // Reading a log does not change the report; don't run a second health check for it.
    if (done && mounted && action.risk != ServerActionRisk.read) _reload();
    return done;
  }

  Future<bool> _deploy(SiteHealth site) async {
    final deploy = widget.onDeploy;
    if (deploy == null) return false;
    final done = await deploy(site);
    if (done && mounted) _reload();
    return done;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: colors.inversePrimary,
        title: Text('Server: ${widget.server.name}'),
        actions: [
          IconButton(
            onPressed: _reload,
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<ServerHealth>(
        future: report,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_off_outlined,
                        size: 48, color: colors.error),
                    const SizedBox(height: 12),
                    const Text('Could not read the server'),
                    const SizedBox(height: 8),
                    Text('${snapshot.error}',
                        style: monoTextStyle.copyWith(fontSize: 12),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return _ReportView(
            report: snapshot.data!,
            onAction: _runAction,
            onDeploy: _deploy,
            onNewSite: widget.onNewSite,
          );
        },
      ),
    );
  }
}

class _ReportView extends StatelessWidget {
  final ServerHealth report;
  final RunServerAction onAction;
  final DeploySiteFromServer onDeploy;
  final NewSiteFromServer? onNewSite;

  const _ReportView({
    required this.report,
    required this.onAction,
    required this.onDeploy,
    this.onNewSite,
  });

  @override
  Widget build(BuildContext context) {
    final generated =
        report.generatedAt?.toLocal().toString().substring(0, 19) ?? '-';
    final warnings = report.warnings;

    return ListView(
      padding: const EdgeInsets.all(12),
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
              label: report.mail.configured ? 'Send-only mail' : 'Mail is not set up',
              value: report.mail.last.isEmpty ? 'nothing sent yet' : report.mail.last,
            ),
          ],
        ),
        _Section(
          title: 'Sites (${report.sites.length})',
          children: [
            if (report.sites.isEmpty) const Text('No sites on this server.'),
            for (final site in report.sites)
              _SiteTile(site: site, onAction: onAction, onDeploy: onDeploy),
          ],
        ),
      ],
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
  final SiteHealth? site;
  final DeploySiteFromServer? onDeploy;
  final NewSiteFromServer? onNewSite;

  const _Actions({
    required this.actions,
    required this.onAction,
    this.site,
    this.onDeploy,
    this.onNewSite,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final logs = actions.where((action) =>
        ServerAction.logActions.any((log) => log.id == action.id)).toList();
    final plain = actions.where((action) => !logs.contains(action)).toList();

    return Wrap(
      spacing: 6,
      runSpacing: 2,
      children: [
        if (site != null && onDeploy != null)
          OutlinedButton.icon(
            onPressed: () => onDeploy!(site!),
            icon: const Icon(Icons.rocket_launch, size: 17),
            label: const Text('Deploy…'),
          ),
        for (final action in plain)
          OutlinedButton.icon(
            onPressed: () => onAction(action, site),
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
        if (logs.isNotEmpty)
          PopupMenuButton<ServerAction>(
            tooltip: 'View a log',
            onSelected: (action) => onAction(action, site),
            itemBuilder: (context) => [
              for (final action in logs)
                PopupMenuItem(
                  value: action,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_icon(action), size: 18),
                      const SizedBox(width: 10),
                      Text(action.label),
                    ],
                  ),
                ),
            ],
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.article_outlined, size: 17),
                  SizedBox(width: 6),
                  Text('Logs…'),
                ],
              ),
            ),
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
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
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

class _SiteTile extends StatelessWidget {
  final SiteHealth site;
  final RunServerAction onAction;
  final DeploySiteFromServer onDeploy;

  const _SiteTile({
    required this.site,
    required this.onAction,
    required this.onDeploy,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = site.certificateDays == null ? '-' : '${site.certificateDays}d';

    return Card(
      child: ExpansionTile(
        leading: Icon(
          site.problems.isEmpty ? Icons.check_circle_outline : Icons.error_outline,
          color: site.problems.isEmpty ? null : theme.colorScheme.error,
        ),
        title: Text(site.domain, style: monoTextStyle),
        subtitle: Text(
          'http=${site.http} · cert=$days (${site.issuer}) · '
          '${site.release} ${site.revision}',
          style: theme.textTheme.bodySmall,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          _Row(label: 'Last deploy', value: '${site.deploy.state} ${site.deploy.when}'),
          _Row(label: 'CRITICAL (24 h)', value: '${site.critical24h}'),
          if (site.lastCritical != null)
            _Row(label: 'Last', value: site.lastCritical!),
          if (site.problems.isEmpty)
            const _StatusLine(ok: true, label: 'No problems', value: '')
          else
            for (final problem in site.problems)
              _StatusLine(ok: false, label: problem, value: ''),
          const SizedBox(height: 8),
          _Actions(
            actions: ServerAction.siteActions,
            onAction: onAction,
            site: site,
            onDeploy: onDeploy,
          ),
        ],
      ),
    );
  }
}
