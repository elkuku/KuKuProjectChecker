import 'package:flutter/material.dart';

import '../support/site_info.dart';
import 'repo_status_text.dart';

/// One site in the list: name, URL, versions, local repository status and its menu.
class SiteCard extends StatelessWidget {
  final SiteInfo site;

  /// The "Open in" menu button.
  final Widget menu;

  /// Opens the changes of the local repository; null if there is none.
  final VoidCallback? onTap;

  const SiteCard({
    super.key,
    required this.site,
    required this.menu,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      site.name,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      site.url,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: colors.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 10),
                    _Versions(site: site),
                    if (site.repoStatus != null) ...[
                      const SizedBox(height: 10),
                      DefaultTextStyle.merge(
                        style: theme.textTheme.bodyMedium,
                        child: RepoStatusText(status: site.repoStatus!),
                      ),
                    ],
                  ],
                ),
              ),
              menu,
            ],
          ),
        ),
      ),
    );
  }
}

/// The PHP and Symfony versions of a site as badges.
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

        return Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            InfoBadge(icon: Icons.code, text: 'PHP ${info.phpVersion}'),
            InfoBadge(
                icon: Icons.layers_outlined, text: 'Symfony ${info.sfVersion}'),
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
