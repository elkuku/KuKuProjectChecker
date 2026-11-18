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

  /// The deploy remote: the first remote other than "origin" that is not an HTTP(S) URL.
  final String? deployRemote;

  /// Commits not on the deploy remote's branch, or null if there is no such branch.
  final int? undeployed;

  const RepoStatus({
    required this.branch,
    required this.uncommitted,
    this.unpushed,
    this.deployRemote,
    this.undeployed,
  });

  /// Everything is committed, pushed and, if there is a deploy remote, deployed.
  bool get isClean =>
      uncommitted == 0 &&
      unpushed == 0 &&
      (deployRemote == null || undeployed == 0);

  static Future<RepoStatus> check(String repoPath) async {
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

    final deployRemote = await _findDeployRemote(path);
    final undeployed = deployRemote == null
        ? null
        : await _count(path, '$deployRemote/$branch..HEAD');

    return RepoStatus(
      branch: branch,
      uncommitted: uncommitted,
      unpushed: unpushed,
      deployRemote: deployRemote,
      undeployed: undeployed,
    );
  }

  static Future<String?> _findDeployRemote(String path) async {
    final remotes = (await _git(path, ['remote']) ?? '')
        .split('\n')
        .where((remote) => remote.isNotEmpty && remote != 'origin');

    for (final remote in remotes) {
      final url = await _git(path, ['remote', 'get-url', remote]) ?? '';
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        return remote;
      }
    }

    return null;
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
