import 'package:flutter/material.dart';

import '../support/local_versions.dart';
import '../support/repo_status.dart';
import '../support/server_health.dart' show SiteHealth;
import '../support/site_info.dart';
import 'repo_status_text.dart';
import 'site_row_action.dart'
    show SiteActionBar, SiteActionPlace, SiteRowAction;

/// A KMyServer report for one environment of a project.
class SiteServerHealth {
  final String server;
  final SiteHealth health;

  const SiteServerHealth({required this.server, required this.health});
}

/// One project row: name, server badges and the common buttons. Versions and
/// repository details are hidden until the row is expanded.
class SiteCard extends StatefulWidget {
  final SiteInfo site;

  /// Allowlisted actions; only [SiteActionPlace.header] ones are shown collapsed.
  final List<SiteRowAction> actions;

  /// Overflow menu, reserved for the Open in… actions.
  final Widget? openInMenu;

  /// Shown on the left, to drag the site to another place in the list.
  final Widget? dragHandle;

  /// Opens the changes of the local repository; null if there is none.
  final VoidCallback? onTap;

  /// Deploys the site; null if it has no local repository.
  final void Function(RepoStatus status)? onDeploy;

  /// What each KMyServer reports about this project's environments there.
  final List<SiteServerHealth> serverHealths;

  const SiteCard({
    super.key,
    required this.site,
    this.actions = const [],
    this.openInMenu,
    this.dragHandle,
    this.onTap,
    this.onDeploy,
    this.serverHealths = const [],
  });

  @override
  State<SiteCard> createState() => _SiteCardState();
}

class _SiteCardState extends State<SiteCard> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) {
    final header = widget.actions
        .where((action) => action.place == SiteActionPlace.header)
        .toList();

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 3, 12, 3),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                  widget.dragHandle == null ? 10 : 2, 5, 4, 5),
              child: Row(
                children: [
                  if (widget.dragHandle != null) ...[
                    widget.dragHandle!,
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _title(context),
                        if (widget.serverHealths.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          _serverStatuses(context, compact: true),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  SiteActionBar(actions: header, compact: true),
                  if (widget.site.repoStatus != null) ...[
                    const SizedBox(width: 4),
                    _Actions(
                      status: widget.site.repoStatus!,
                      onShowChanges: widget.onTap,
                      onDeploy: widget.onDeploy,
                      compact: true,
                    ),
                  ],
                  const SizedBox(width: 2),
                  IconButton(
                    tooltip: expanded ? 'Hide details' : 'Show details',
                    icon:
                        Icon(expanded ? Icons.expand_less : Icons.expand_more),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => expanded = !expanded),
                  ),
                  if (widget.openInMenu != null) widget.openInMenu!,
                ],
              ),
            ),
            if (expanded) ...[
              const Divider(height: 1),
              _details(context),
            ],
          ],
        ),
      ),
    );
  }

  Widget _title(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.site.name,
          style:
              theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          widget.site.url,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _status(BuildContext context) => DefaultTextStyle.merge(
        style: Theme.of(context).textTheme.bodyMedium,
        child: RepoStatusText(status: widget.site.repoStatus!),
      );

  /// On a collapsed row the server name is a small label in front of its badges,
  /// so the same site on two servers can be told apart.
  Widget _serverStatuses(BuildContext context, {required bool compact}) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in widget.serverHealths) ...[
          if (widget.serverHealths.length > 1)
            Text(
              entry.server,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ServerSiteStatus(health: entry.health, compact: compact),
        ],
      ],
    );
  }

  Widget _details(BuildContext context) {
    final actions = widget.actions
        .where((action) => action.place == SiteActionPlace.details)
        .toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.serverHealths.isNotEmpty)
            _serverStatuses(context, compact: false),
          const SizedBox(height: 8),
          _Versions(site: widget.site),
          if (widget.site.repoStatus != null) ...[
            const SizedBox(height: 8),
            _status(context),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 8),
            SiteActionBar(actions: actions),
          ],
        ],
      ),
    );
  }
}

/// What the selected KMyServer reports about a site: HTTP, last deploy and recent CRITICALs.
/// The site's own /system/info/ stays in [_Versions]; this is the server-side view of it.
class ServerSiteStatus extends StatelessWidget {
  final SiteHealth health;

  /// Less padding, for the row layout.
  final bool compact;

  const ServerSiteStatus(
      {super.key, required this.health, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final error = (colors.errorContainer, colors.onErrorContainer);
    final warning = _warningColors(context);

    final httpOk = health.http >= 200 && health.http < 400;
    final deploy = health.deploy;
    final deployColors = switch (deploy.state) {
      'ok' => null,
      'failed' => error,
      'running' => warning,
      _ => warning,
    };

    return Wrap(
      spacing: compact ? 4 : 6,
      runSpacing: compact ? 4 : 6,
      children: [
        InfoBadge(
          icon: Icons.public,
          text: health.http == 0 ? 'offline' : 'HTTP ${health.http}',
          tooltip: [
            '${health.domain}: ${httpOk ? 'HTTP ${health.http}' : 'not reachable (HTTP ${health.http})'}',
            if (health.certificateDays != null)
              'Certificate: ${health.certificateDays}d (${health.issuer})',
            if (health.problems.isNotEmpty)
              'Problems: ${health.problems.join('; ')}',
          ].join('\n'),
          background: httpOk ? null : error.$1,
          foreground: httpOk ? null : error.$2,
          dense: compact,
        ),
        InfoBadge(
          icon: Icons.rocket_launch_outlined,
          text: compact ? deploy.state : 'deploy ${deploy.state}',
          tooltip: [
            'Last deploy on the server: ${deploy.state}',
            if (deploy.when.isNotEmpty) 'When: ${deploy.when}',
            if (health.release.isNotEmpty)
              'Release ${health.release}${health.revision.isEmpty ? '' : ' (${health.revision})'}',
          ].join('\n'),
          background: deployColors?.$1,
          foreground: deployColors?.$2,
          dense: compact,
        ),
        if (health.critical24h > 0)
          InfoBadge(
            icon: Icons.error_outline,
            text: '${health.critical24h} CRITICAL',
            tooltip: [
              '${health.critical24h} CRITICAL errors in the last 24 h',
              if (health.lastCritical != null) 'Last: ${health.lastCritical}',
            ].join('\n'),
            background: error.$1,
            foreground: error.$2,
            dense: compact,
          ),
      ],
    );
  }
}

/// Buttons for what is pending in the repository: its changes, and a deploy.
class _Actions extends StatelessWidget {
  final Future<RepoStatus> status;
  final VoidCallback? onShowChanges;
  final void Function(RepoStatus status)? onDeploy;

  /// Smaller buttons, in one row with the rest (wide layout).
  final bool compact;

  const _Actions({
    required this.status,
    this.onShowChanges,
    this.onDeploy,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<RepoStatus>(
      future: status,
      builder: (context, snapshot) {
        final status = snapshot.data;
        if (status == null) return const SizedBox.shrink();

        // Both buttons are always there, so they stay in place; they are off when
        // there is nothing to do.
        final changes = status.uncommitted > 0 && onShowChanges != null;
        final deploy = status.deployRemote != null &&
            (status.undeployed ?? 1) > 0 &&
            onDeploy != null;

        final changesTooltip = switch (status.uncommitted) {
          0 => 'No uncommitted files',
          1 => 'Show the uncommitted file',
          final n => 'Show the $n uncommitted files',
        };
        final deployTooltip = status.deployRemote == null
            ? 'No deploy remote: add a git remote other than origin, e.g. a Plesk repository'
            : switch (status.undeployed) {
                null => 'Deploy to ${status.deployRemote}',
                0 => 'Nothing to deploy',
                1 => 'Deploy 1 commit to ${status.deployRemote}',
                final n => 'Deploy $n commits to ${status.deployRemote}',
              };
        final onChanges = changes ? onShowChanges : null;
        final onDeployPressed = deploy ? () => onDeploy!(status) : null;

        if (compact) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _CountButton(
                icon: Icons.difference_outlined,
                count: status.uncommitted == 0 ? null : status.uncommitted,
                tooltip: changesTooltip,
                onPressed: onChanges,
              ),
              const SizedBox(width: 6),
              _CountButton(
                icon: Icons.rocket_launch,
                count: status.undeployed == 0 ? null : status.undeployed,
                tooltip: deployTooltip,
                filled: true,
                onPressed: onDeployPressed,
              ),
            ],
          );
        }

        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Tooltip(
                message: changesTooltip,
                child: OutlinedButton.icon(
                  onPressed: onChanges,
                  icon: const Icon(Icons.difference_outlined, size: 18),
                  label: Text(status.uncommitted == 0
                      ? 'Changes'
                      : 'Changes (${status.uncommitted})'),
                ),
              ),
              Tooltip(
                message: deployTooltip,
                child: FilledButton.tonalIcon(
                  onPressed: onDeployPressed,
                  icon: const Icon(Icons.rocket_launch, size: 18),
                  label: Text(switch (status.undeployed) {
                    null || 0 => 'Deploy',
                    final n => 'Deploy ($n)',
                  }),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A small button with an icon and a number; [tooltip] says what it does.
class _CountButton extends StatelessWidget {
  final IconData icon;
  final int? count;
  final String tooltip;
  final bool filled;
  final VoidCallback? onPressed;

  const _CountButton({
    required this.icon,
    required this.count,
    required this.tooltip,
    required this.onPressed,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    const style = ButtonStyle(
      visualDensity: VisualDensity.compact,
      padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10)),
      minimumSize: WidgetStatePropertyAll(Size(0, 34)),
    );
    final icon = Icon(this.icon, size: 17);

    return Tooltip(
      message: tooltip,
      // Without a number, only the icon.
      child: switch ((filled, count)) {
        (true, null) =>
          FilledButton.tonal(style: style, onPressed: onPressed, child: icon),
        (true, final n?) => FilledButton.tonalIcon(
            style: style, onPressed: onPressed, icon: icon, label: Text('$n')),
        (false, null) =>
          OutlinedButton(style: style, onPressed: onPressed, child: icon),
        (false, final n?) => OutlinedButton.icon(
            style: style, onPressed: onPressed, icon: icon, label: Text('$n')),
      },
    );
  }
}

/// The versions of a site as badges: PHP, Symfony and, if the site exposes them, its
/// database and last deploy. A version that differs from the local repository is orange.
class _Versions extends StatelessWidget {
  final SiteInfo site;

  const _Versions({required this.site});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return FutureBuilder<SystemInfo>(
      future: site.systemInfo,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return InfoBadge(
            icon: Icons.cloud_off,
            text: 'Not reachable',
            background: colors.errorContainer,
            foreground: colors.onErrorContainer,
          );
        }
        if (!snapshot.hasData) {
          return const SizedBox(
            height: 22,
            width: 22,
            child: Padding(
              padding: EdgeInsets.all(3),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        final info = snapshot.data!;

        // The local versions come later or not at all; the badges show without them.
        return FutureBuilder<LocalVersions>(
          future: site.localVersions,
          builder: (context, local) => Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _badges(context, info, local.data),
          ),
        );
      },
    );
  }

  List<Widget> _badges(
      BuildContext context, SystemInfo info, LocalVersions? local) {
    String nameOf(String? platform) => switch (platform) {
          'mariadb' => 'MariaDB',
          'mysql' => 'MySQL',
          'postgresql' => 'PostgreSQL',
          'sqlite' => 'SQLite',
          final other => other ?? 'DB',
        };
    final dbName = nameOf(info.dbPlatform);

    return [
      _VersionBadge(
        icon: Icons.code,
        label: 'PHP',
        live: info.phpVersion,
        local: local?.php,
        // Patch releases differ all the time between machines.
        maxParts: 2,
      ),
      _VersionBadge(
        icon: Icons.layers_outlined,
        label: 'Symfony',
        live: info.sfVersion,
        local: local?.symfony,
      ),
      if (info.dbVersion != null)
        _VersionBadge(
          icon: Icons.storage,
          label: dbName,
          live: info.dbVersion!,
          local: local?.dbVersion == null
              ? null
              : local!.dbPlatform == info.dbPlatform
                  ? local.dbVersion
                  : '${nameOf(local.dbPlatform)} ${local.dbVersion}',
          // A different database (e.g. MySQL locally, MariaDB live) never matches.
          matches: local?.dbVersion == null
              ? null
              : local!.dbPlatform == info.dbPlatform &&
                  LocalVersions.matches(local.dbVersion!, info.dbVersion!),
        ),
      if (info.lastDeploy != null) _DeployBadge(deploy: info.lastDeploy!),
      if (site.devInfo != null)
        DevBadge(
          url: site.devUrl!,
          info: site.devInfo!,
          upstreamTime: site.upstreamTime,
        ),
    ];
  }
}

/// The dev site of a site: whether its last deploy (from the upstream branch, e.g. by a
/// webhook) went well and includes the newest upstream commit.
class DevBadge extends StatelessWidget {
  final String url;
  final Future<SystemInfo> info;

  /// The time of the newest upstream commit; null without a local repository.
  final Future<DateTime?>? upstreamTime;

  const DevBadge({
    super.key,
    required this.url,
    required this.info,
    this.upstreamTime,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SystemInfo>(
      future: info,
      builder: (context, snapshot) {
        final colors = Theme.of(context).colorScheme;
        final error = (colors.errorContainer, colors.onErrorContainer);

        if (snapshot.hasError) {
          return InfoBadge(
            icon: Icons.science_outlined,
            text: 'dev offline',
            tooltip: 'Dev site $url\nNot reachable',
            background: error.$1,
            foreground: error.$2,
          );
        }
        if (!snapshot.hasData) return const SizedBox.shrink();

        final dev = snapshot.data!;
        return FutureBuilder<DateTime?>(
          future: upstreamTime,
          builder: (context, upstream) {
            final deploy = dev.lastDeploy;
            final at = deploy?.at?.toLocal();
            final state = DevState.of(deploy, upstream.data);
            final ago =
                at == null ? null : _DeployBadge.ago(at, DateTime.now());

            final (text, colorsOf, meaning) = switch (state) {
              DevState.upToDate => (
                  'dev ${ago?.replaceFirst(' ago', '') ?? ''}'.trim(),
                  null,
                  'Up to date with the upstream branch'
                ),
              DevState.behind => (
                  'dev behind',
                  _warningColors(context),
                  'The upstream branch has newer commits than the last deploy: '
                      'the deploy didn\'t run or is still running'
                ),
              DevState.errors => (
                  'dev errors',
                  _warningColors(context),
                  'The last deploy finished with errors'
                ),
              DevState.unfinished => (
                  'dev unfinished',
                  error,
                  'The last deploy did not finish'
                ),
              DevState.unknown => (
                  'dev',
                  null,
                  'The dev site doesn\'t report its deploys'
                ),
            };

            return InfoBadge(
              icon: Icons.science_outlined,
              text: text,
              tooltip: [
                'Dev site $url',
                meaning,
                'Symfony ${dev.sfVersion} · PHP ${dev.phpVersion}'
                    '${dev.dbVersion == null ? '' : ' · ${dev.dbPlatform ?? 'DB'} ${dev.dbVersion}'}',
                if (at != null) 'Last deploy: ${_DeployBadge._dateTime(at)}',
                if (upstream.data != null)
                  'Newest upstream commit: ${_DeployBadge._dateTime(upstream.data!.toLocal())}',
              ].join('\n'),
              background: colorsOf?.$1,
              foreground: colorsOf?.$2,
            );
          },
        );
      },
    );
  }
}

/// A version badge; orange when the [local] version differs from the [live] one.
class _VersionBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final String live;
  final String? local;

  /// Compare at most this many parts of the version (major, minor, patch).
  final int maxParts;

  /// Overrides the comparison of [local] and [live].
  final bool? matches;

  const _VersionBadge({
    required this.icon,
    required this.label,
    required this.live,
    this.local,
    this.maxParts = 3,
    this.matches,
  });

  @override
  Widget build(BuildContext context) {
    // The numbers only, e.g. "12.3.4" for "12.3.4-MariaDB-deb12".
    final short = RegExp(r'^\d+(\.\d+)*').stringMatch(live) ?? live;
    final hidden = live == 'N/A';
    final same = hidden || local == null
        ? true
        : matches ?? LocalVersions.matches(local!, live, maxParts: maxParts);
    final tooltip = [
      '$label $live on the site',
      // A local value with its own name (another database) needs no label.
      if (local != null)
        RegExp('^[A-Za-z]').hasMatch(local!)
            ? '$local locally'
            : '$label $local locally',
      if (!same) 'The site runs a different version than your local project.',
    ].join('\n');

    final warning = _warningColors(context);

    return InfoBadge(
      icon: same ? icon : Icons.compare_arrows,
      text: '$label $short',
      tooltip: tooltip,
      background: same ? null : warning.$1,
      foreground: same ? null : warning.$2,
    );
  }
}

/// When the site was last deployed, from its deploy log: orange if the run had errors,
/// red if it didn't finish.
class _DeployBadge extends StatelessWidget {
  final LastDeploy deploy;

  const _DeployBadge({required this.deploy});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final at = deploy.at?.toLocal();
    final ago = at == null ? 'unknown' : _DeployBadge.ago(at, DateTime.now());

    final (background, foreground, state) = switch (deploy.status) {
      'ok' => (null, null, 'deployed'),
      'errors' => (
          _warningColors(context).$1,
          _warningColors(context).$2,
          'finished with errors'
        ),
      _ => (colors.errorContainer, colors.onErrorContainer, 'did not finish'),
    };

    return InfoBadge(
      icon: Icons.rocket_launch_outlined,
      text: ago,
      tooltip: [
        'Last deploy: $state',
        if (at != null) _dateTime(at),
      ].join('\n'),
      background: background,
      foreground: foreground,
    );
  }

  static String _dateTime(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  /// "just now", "5m ago", "3h ago", "2d ago", "4mo ago" or "1y ago".
  static String ago(DateTime at, DateTime now) {
    final d = now.difference(at);
    return switch (d) {
      _ when d.inMinutes < 1 => 'just now',
      _ when d.inHours < 1 => '${d.inMinutes}m ago',
      _ when d.inDays < 1 => '${d.inHours}h ago',
      _ when d.inDays < 30 => '${d.inDays}d ago',
      _ when d.inDays < 365 => '${d.inDays ~/ 30}mo ago',
      _ => '${d.inDays ~/ 365}y ago',
    };
  }
}

/// Orange background and text for a badge, readable in light and dark mode.
(Color, Color) _warningColors(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? (const Color(0xFF5C3B00), const Color(0xFFFFDDB3))
        : (const Color(0xFFFFE0B2), const Color(0xFF6B3A00));

/// A small rounded label with an icon, and an optional [tooltip].
class InfoBadge extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? background;
  final Color? foreground;
  final String? tooltip;

  /// Less padding, for the row layout.
  final bool dense;

  const InfoBadge({
    super.key,
    required this.icon,
    required this.text,
    this.background,
    this.foreground,
    this.tooltip,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final badge = _badge(context);
    return tooltip == null ? badge : Tooltip(message: tooltip!, child: badge);
  }

  Widget _badge(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fg = foreground ?? colors.onSecondaryContainer;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 8, vertical: 3),
      decoration: BoxDecoration(
        color: background ?? colors.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          SizedBox(width: dense ? 3 : 4),
          Text(
            text,
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: fg, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
