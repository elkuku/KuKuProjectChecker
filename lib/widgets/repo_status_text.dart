import 'package:flutter/material.dart';

import '../support/repo_status.dart';

/// One line about the local repository, e.g. "master · 2 uncommitted · 1 not deployed (elkuku.dev)".
String describeRepoStatus(RepoStatus status) {
  final parts = <String>[status.branch];

  if (status.uncommitted > 0) {
    parts.add('${status.uncommitted} uncommitted');
  }

  if (status.unpushed == null) {
    parts.add('no upstream');
  } else if (status.unpushed! > 0) {
    parts.add('${status.unpushed} unpushed');
  }

  if (status.deployRemote != null) {
    if (status.undeployed == null) {
      parts.add('not on ${status.deployRemote}');
    } else if (status.undeployed! > 0) {
      parts.add('${status.undeployed} not deployed (${status.deployRemote})');
    }
  }

  if (status.isClean) {
    parts.add(status.deployRemote == null ? 'clean' : 'clean, deployed');
  }

  return parts.join(' · ');
}

class RepoStatusText extends StatelessWidget {
  final Future<RepoStatus> status;

  const RepoStatusText({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return FutureBuilder<RepoStatus>(
      future: status,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Text('Repo: ${snapshot.error}',
              style: TextStyle(color: colors.error));
        }
        if (!snapshot.hasData) {
          return const Text('Checking repo …');
        }

        final repoStatus = snapshot.data!;

        return Row(
          children: [
            Icon(
              repoStatus.isClean ? Icons.check_circle : Icons.warning_amber,
              size: 16,
              color: repoStatus.isClean ? Colors.green : Colors.orange,
            ),
            const SizedBox(width: 4),
            Flexible(child: Text(describeRepoStatus(repoStatus))),
          ],
        );
      },
    );
  }
}
