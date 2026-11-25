import 'dart:io';

/// What a local git repository has that is not committed, pushed or deployed.
///
/// Only local data is used, nothing is fetched: "unpushed" and "undeployed" compare
/// with the remote-tracking branches as of the last fetch or push from this machine.
class RepoStatus {
  final String branch;

  /// Modified, added, deleted and untracked files.
  final int uncommitted;

  /// Commits not on the upstream branch, or null if the branch has no upstream.
  final int? unpushed;

  /// The deploy remote, see [findDeployRemote].
  final String? deployRemote;

  /// The URL of [deployRemote]; null without one.
  final String? deployUrl;

  /// Commits not on the deploy remote's branch, or null if there is no such branch.
  final int? undeployed;

  const RepoStatus({
    required this.branch,
    required this.uncommitted,
    this.unpushed,
    this.deployRemote,
    this.deployUrl,
    this.undeployed,
  });

  /// Everything is committed, pushed and, if there is a deploy remote, deployed.
  bool get isClean =>
      uncommitted == 0 &&
      unpushed == 0 &&
      (deployRemote == null || undeployed == 0);

  /// Checks the repository at [repoPath]. [deployRemote] is the site's choice:
  /// Site.autoDeploy (''), Site.noDeploy ('-') or the name of a remote.
  static Future<RepoStatus> check(String repoPath,
      {String deployRemote = ''}) async {
    final path = expandHome(repoPath);

    if (!await Directory(path).exists()) {
      throw RepoStatusException('Folder not found: $repoPath');
    }

    final branch = await _git(path, ['rev-parse', '--abbrev-ref', 'HEAD']);
    if (branch == null) {
      throw RepoStatusException('Not a git repository: $repoPath');
    }

    final status = await _git(path, ['status', '--porcelain']) ?? '';
    final uncommitted =
        status.split('\n').where((line) => line.trim().isNotEmpty).length;

    final unpushed = await _count(path, '@{upstream}..HEAD');

    final remoteList = await remotes(path);
    final names = [for (final (name, _) in remoteList) name];
    final chosen = switch (deployRemote) {
      '' => pickDeployRemote(remoteList),
      '-' => null,
      // A chosen remote that no longer exists (renamed, removed) means no deploys.
      _ => names.contains(deployRemote) ? deployRemote : null,
    };
    final undeployed =
        chosen == null ? null : await _count(path, '$chosen/$branch..HEAD');

    return RepoStatus(
      branch: branch,
      uncommitted: uncommitted,
      unpushed: unpushed,
      deployRemote: chosen,
      deployUrl: chosen == null
          ? null
          : remoteList.firstWhere((remote) => remote.$1 == chosen).$2,
      undeployed: undeployed,
    );
  }

  /// The remotes of the repository at [repoPath] as (name, URL), in git's order;
  /// empty if it isn't a repository.
  static Future<List<(String, String)>> remotes(String repoPath) async {
    final path = expandHome(repoPath);
    if (!await Directory(path).exists()) return const [];

    final list = <(String, String)>[];
    for (final name in (await _git(path, ['remote']) ?? '').split('\n')) {
      if (name.isEmpty) continue;
      list.add((name, await _git(path, ['remote', 'get-url', name]) ?? ''));
    }

    return list;
  }

  /// Hosts where code is kept, never deployed to.
  static const codeHosts = {
    'github.com',
    'gitlab.com',
    'bitbucket.org',
    'codeberg.org',
  };

  /// The remote the app picks when a site's deploy remote is automatic: the first that is
  /// not "origin", not an HTTP(S) URL and not on a code host like GitHub ([codeHosts]).
  /// Null if there is none.
  static String? pickDeployRemote(List<(String, String)> remotes) {
    for (final (name, url) in remotes) {
      if (name == 'origin') continue;
      if (url.startsWith('http://') || url.startsWith('https://')) continue;
      if (codeHosts.contains(hostOf(url))) continue;

      return name;
    }

    return null;
  }

  /// The host of a git URL: "ssh://user@host:22/path", "user@host:path" or "host:path";
  /// null for a local path.
  static String? hostOf(String url) {
    if (url.contains('://')) {
      final host = Uri.tryParse(url)?.host;
      return host == null || host.isEmpty ? null : host.toLowerCase();
    }

    // scp-like syntax: [user@]host:path, where the host has no slash.
    final match = RegExp(r'^(?:[^@/]+@)?([^:/]+):').firstMatch(url);
    return match?.group(1)?.toLowerCase();
  }

  /// When the newest commit of the branch's upstream (e.g. origin/master) was committed,
  /// as of the last fetch or push from this machine; null without an upstream.
  static Future<DateTime?> upstreamCommitTime(String repoPath) async {
    final path = expandHome(repoPath);
    if (!await Directory(path).exists()) return null;

    final output =
        await _git(path, ['log', '-1', '--format=%cI', '@{upstream}']);
    return output == null ? null : DateTime.tryParse(output);
  }

  static Future<int?> _count(String path, String range) async {
    final output = await _git(path, ['rev-list', '--count', range]);

    return output == null ? null : int.tryParse(output);
  }

  /// Runs git in the repository; returns the trimmed output, or null if git failed.
  static Future<String?> _git(String path, List<String> args) async {
    try {
      final result = await Process.run('git', ['-C', path, ...args]);

      return result.exitCode == 0 ? (result.stdout as String).trim() : null;
    } on ProcessException {
      throw RepoStatusException('git is not installed');
    }
  }

  static String expandHome(String path) {
    final home = Platform.environment['HOME'];
    if (home != null && (path == '~' || path.startsWith('~/'))) {
      return home + path.substring(1);
    }

    return path;
  }
}

class RepoStatusException implements Exception {
  final String message;

  const RepoStatusException(this.message);

  @override
  String toString() => message;
}
