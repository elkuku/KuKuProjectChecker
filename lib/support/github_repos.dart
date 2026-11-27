import 'dart:io';

/// A repository the authenticated GitHub user can access, including org repos.
class GitHubRepo {
  final String nameWithOwner;
  final String url;

  const GitHubRepo({required this.nameWithOwner, required this.url});

  String get name => nameWithOwner.split('/').last;
}

/// Lists every repository the authenticated GitHub user can access. The real
/// implementation uses the `gh` CLI, so the app never stores a GitHub token. Tests
/// pass their own.
typedef GitHubRepoLookup = Future<List<GitHubRepo>> Function();

/// Reads all accessible repositories with `gh`, including organisation repos that
/// `gh repo list <owner>` would miss. The CLI is a requirement: a missing CLI,
/// failed command or unexpected output is reported instead of being replaced by a
/// guessed URL.
Future<List<GitHubRepo>> lookupGitHubRepos() async {
  final ProcessResult result;
  try {
    result = await Process.run('gh', [
      'api',
      'user/repos',
      '--paginate',
      '--jq',
      '.[] | [.full_name, .html_url] | @tsv',
    ]);
  } on ProcessException catch (error) {
    throw StateError('gh is required for GitHub lookup: ${error.message}');
  }

  if (result.exitCode != 0) {
    throw StateError('gh api user/repos failed (exit ${result.exitCode})');
  }

  final repos = <GitHubRepo>[];
  for (final line in (result.stdout as String).split(RegExp(r'\r?\n'))) {
    final parts = line.split('\t');
    if (parts.length == 2 &&
        parts[0].trim().isNotEmpty &&
        parts[1].trim().isNotEmpty) {
      repos.add(GitHubRepo(
        nameWithOwner: parts[0].trim(),
        url: parts[1].trim(),
      ));
    }
  }
  return repos;
}

/// Repos in [repos] whose name is similar to [label], best first. Exact names win,
/// then prefixed names, whole-token matches, shared fuzzy tokens and small spelling
/// differences. The dialog uses the list to offer a choice when more than one fits.
List<GitHubRepo> similarGitHubRepos(
  Iterable<GitHubRepo> repos,
  String label, {
  int limit = 6,
}) {
  final query = _normalize(label);
  if (query.isEmpty) return const [];

  final queryTokens = _tokens(label);
  final scored = <({GitHubRepo repo, int score})>[];

  for (final repo in repos) {
    final name = _normalize(repo.name);
    if (name.isEmpty) continue;

    final score = _score(query, queryTokens, name, repo.name);
    if (score != null) scored.add((repo: repo, score: score));
  }

  scored.sort((a, b) {
    final byScore = a.score.compareTo(b.score);
    return byScore != 0
        ? byScore
        : a.repo.nameWithOwner.toLowerCase().compareTo(
            b.repo.nameWithOwner.toLowerCase());
  });

  final seen = <String>{};
  final matches = <GitHubRepo>[];
  for (final candidate in scored) {
    if (!seen.add(candidate.repo.url)) continue;
    matches.add(candidate.repo);
    if (matches.length == limit) break;
  }
  return matches;
}

/// The single closest repo, for callers that do not offer a choice.
GitHubRepo? similarGitHubRepo(Iterable<GitHubRepo> repos, String label) {
  final matches = similarGitHubRepos(repos, label, limit: 1);
  return matches.isEmpty ? null : matches.first;
}

int? _score(
  String query,
  Set<String> queryTokens,
  String name,
  String originalName,
) {
  if (query == name) return 0;
  if (query.length > 2 && name.startsWith(query)) return 1;
  if (query.length > 2 && query.startsWith(name)) return 2;

  final nameTokens = _tokens(originalName);
  if (query.length > 2 && nameTokens.contains(query)) return 3;

  // Fuzzy: a shared word such as `website` in `4e-website` and `website-red`.
  // Generic words like `test` or `web` are too common to be useful candidates.
  final meaningfulName = nameTokens.where(_isFuzzyToken).toSet();
  final meaningfulQuery = queryTokens.where(_isFuzzyToken).toSet();
  if (meaningfulName.any(meaningfulQuery.contains) ||
      meaningfulQuery.any(meaningfulName.contains)) {
    return 4;
  }

  if (query.length >= 4 && name.length >= 4) {
    final distance = _editDistance(query, name);
    if (distance <= 2) return 10 + distance;
  }

  return null;
}

const _genericTokens = {
  'app',
  'apps',
  'demo',
  'dev',
  'local',
  'new',
  'old',
  'prod',
  'site',
  'staging',
  'temp',
  'test',
  'tests',
  'web',
  'www',
};

bool _isFuzzyToken(String token) =>
    token.length >= 3 && !_genericTokens.contains(token);

Set<String> _tokens(String text) => text
    .toLowerCase()
    .split(RegExp(r'[^a-z0-9]+'))
    .where((part) => part.length >= 2)
    .toSet();

String _normalize(String text) =>
    text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

int _editDistance(String a, String b) {
  var previous = List<int>.generate(b.length + 1, (index) => index);

  for (var i = 1; i <= a.length; i++) {
    final current = List<int>.filled(b.length + 1, i);
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      current[j] = [
        current[j - 1] + 1,
        previous[j] + 1,
        previous[j - 1] + cost,
      ].reduce((x, y) => x < y ? x : y);
    }
    previous = current;
  }

  return previous[b.length];
}
