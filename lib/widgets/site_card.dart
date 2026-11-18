import 'package:flutter/material.dart';

import '../support/repo_status.dart';
import '../support/site_info.dart';
import 'repo_status_text.dart';

/// One site in the list: name, URL, versions, local repository status and its menu.
class SiteCard extends StatelessWidget {
  final SiteInfo site;

  /// The "Open in" menu button.
  final Widget menu;

  /// Opens the changes of the local repository; null if there is none.
  final VoidCallback? onTap;

  /// Deploys the site; null if it has no local repository.
  final void Function(RepoStatus status)? onDeploy;

  const SiteCard({
    super.key,
    required this.site,
    required this.menu,
    this.onTap,
    this.onDeploy,
  });

  /// From this width on, a site is one compact row instead of a stacked card.
  static const wideLayout = 900.0;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 3, 12, 3),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth >= wideLayout
              ? _row(context)
              : _stacked(context),
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
          site.name,
          style:
              theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          site.url,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _status(BuildContext context) => DefaultTextStyle.merge(
        style: Theme.of(context).textTheme.bodyMedium,
        child: RepoStatusText(status: site.repoStatus!),
      );

  /// Wide windows: name | versions | repository status | buttons | menu.
  Widget _row(BuildContext context) {
    // Fixed column widths, so the columns line up from row to row.
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
      child: Row(
        children: [
          Expanded(child: _title(context)),
          const SizedBox(width: 12),
          SizedBox(
            width: 214,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _Versions(site: site, compact: true),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 300,
            child: site.repoStatus == null
                ? const SizedBox.shrink()
                : _status(context),
          ),
          SizedBox(
            width: 132,
            child: site.repoStatus == null
                ? const SizedBox.shrink()
                : Align(
                    alignment: Alignment.centerRight,
                    child: _Actions(
                      status: site.repoStatus!,
                      onShowChanges: onTap,
                      onDeploy: onDeploy,
                      compact: true,
                    ),
                  ),
          ),
          menu,
        ],
      ),
    );
  }

  /// Narrow windows: everything below each other.
  Widget _stacked(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 4, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _title(context),
                const SizedBox(height: 6),
                _Versions(site: site),
                if (site.repoStatus != null) ...[
                  const SizedBox(height: 6),
                  _status(context),
                  _Actions(
                    status: site.repoStatus!,
                    onShowChanges: onTap,
                    onDeploy: onDeploy,
                  ),
                ],
              ],
            ),
          ),
          menu,
        ],
      ),
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

        final changes = status.uncommitted > 0 && onShowChanges != null;
        final deploy = status.deployRemote != null &&
            (status.undeployed ?? 1) > 0 &&
            onDeploy != null;
        if (!changes && !deploy) return const SizedBox.shrink();

        if (compact) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (changes)
                _CountButton(
                  icon: Icons.difference_outlined,
                  count: status.uncommitted,
                  tooltip:
                      'Show the ${status.uncommitted} uncommitted file${status.uncommitted == 1 ? '' : 's'}',
                  onPressed: onShowChanges!,
                ),
              if (changes && deploy) const SizedBox(width: 6),
              if (deploy)
                _CountButton(
                  icon: Icons.rocket_launch,
                  count: status.undeployed,
                  tooltip: switch (status.undeployed) {
                    null => 'Deploy to ${status.deployRemote}',
                    1 => 'Deploy 1 commit to ${status.deployRemote}',
                    final n => 'Deploy $n commits to ${status.deployRemote}',
                  },
                  filled: true,
                  onPressed: () => onDeploy!(status),
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
              if (changes)
                OutlinedButton.icon(
                  onPressed: onShowChanges,
                  icon: const Icon(Icons.difference_outlined, size: 18),
                  label: Text('Changes (${status.uncommitted})'),
                ),
              if (deploy)
                FilledButton.tonalIcon(
                  onPressed: () => onDeploy!(status),
                  icon: const Icon(Icons.rocket_launch, size: 18),
                  label: Text(status.undeployed == null
                      ? 'Deploy'
                      : 'Deploy (${status.undeployed})'),
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
  final VoidCallback onPressed;

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
    final label = Text(count?.toString() ?? '');

    return Tooltip(
      message: tooltip,
      child: filled
          ? FilledButton.tonalIcon(
              style: style, onPressed: onPressed, icon: icon, label: label)
          : OutlinedButton.icon(
              style: style, onPressed: onPressed, icon: icon, label: label),
    );
  }
}

/// The PHP and Symfony versions of a site as badges.
class _Versions extends StatelessWidget {
  final SiteInfo site;

  /// "SF" instead of "Symfony", for the row layout.
  final bool compact;

  const _Versions({required this.site, this.compact = false});

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

        return Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            InfoBadge(icon: Icons.code, text: 'PHP ${info.phpVersion}'),
            InfoBadge(
                icon: Icons.layers_outlined,
                text: '${compact ? 'SF' : 'Symfony'} ${info.sfVersion}'),
          ],
        );
      },
    );
  }
}

/// A small rounded label with an icon.
class InfoBadge extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? background;
  final Color? foreground;

  const InfoBadge({
    super.key,
    required this.icon,
    required this.text,
    this.background,
    this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fg = foreground ?? colors.onSecondaryContainer;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background ?? colors.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
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
