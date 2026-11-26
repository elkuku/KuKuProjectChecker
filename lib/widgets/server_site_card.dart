import 'package:flutter/material.dart';

import '../support/server_health.dart' show SiteHealth;
import 'site_card.dart' show ServerSiteStatus;
import 'site_row_action.dart'
    show SiteActionBar, SiteActionPlace, SiteRowAction;

/// A site the server reports but that has no local project. It is only in the list
/// while that server is selected; nothing about it is written to the settings.
class ServerSiteCard extends StatefulWidget {
  final SiteHealth health;
  final String serverName;

  /// Allowlisted server actions for this site.
  final List<SiteRowAction> actions;

  /// Overflow menu, reserved for the Open in… actions.
  final Widget? openInMenu;

  const ServerSiteCard({
    super.key,
    required this.health,
    required this.serverName,
    this.actions = const [],
    this.openInMenu,
  });

  @override
  State<ServerSiteCard> createState() => _ServerSiteCardState();
}

class _ServerSiteCardState extends State<ServerSiteCard> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final header = widget.actions
        .where((action) => action.place == SiteActionPlace.header)
        .toList();
    final details = widget.actions
        .where((action) => action.place == SiteActionPlace.details)
        .toList();

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 3, 12, 3),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // Clicking the row shows its details.
        onTap: () => setState(() => expanded = !expanded),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 5, 4, 5),
              child: Row(
                children: [
                  Icon(
                    widget.health.problems.isEmpty
                        ? Icons.dns_outlined
                        : Icons.error_outline,
                    color: widget.health.problems.isEmpty ? null : colors.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.health.name,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          widget.health.domain,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                        const SizedBox(height: 4),
                        ServerSiteStatus(health: widget.health, compact: true),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  SiteActionBar(actions: header, compact: true),
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
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 8, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ServerSiteStatus(health: widget.health),
                    const SizedBox(height: 8),
                    Text(
                      'On ${widget.serverName} · not in the projects (temporary)',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: colors.onSurfaceVariant),
                    ),
                    if (details.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      SiteActionBar(actions: details),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
