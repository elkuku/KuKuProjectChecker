import 'package:flutter_test/flutter_test.dart';
import 'package:kuku_project_checker/support/github_repos.dart';

void main() {
  const repos = [
    GitHubRepo(
        nameWithOwner: 'elkuku/shop', url: 'https://github.com/elkuku/shop'),
    GitHubRepo(
        nameWithOwner: 'elkuku/shop-app',
        url: 'https://github.com/elkuku/shop-app'),
    GitHubRepo(
        nameWithOwner: 'elkuku/my-blog',
        url: 'https://github.com/elkuku/my-blog'),
    GitHubRepo(
        nameWithOwner: 'elkuku/web-atacames',
        url: 'https://github.com/elkuku/web-atacames'),
  ];

  test('an exact name wins over a prefixed one', () {
    expect(similarGitHubRepo(repos, 'shop')?.nameWithOwner, 'elkuku/shop');
  });

  test('a prefixed or token name counts as an existing repo', () {
    expect(similarGitHubRepo(repos, 'blog')?.nameWithOwner, 'elkuku/my-blog');
    expect(similarGitHubRepo(repos, 'web-atacames')?.nameWithOwner,
        'elkuku/web-atacames');
  });

  test('a small spelling difference counts, an unrelated name does not', () {
    expect(similarGitHubRepo(repos, 'shope')?.nameWithOwner, 'elkuku/shop');
    expect(similarGitHubRepo(repos, 'totally-other'), isNull);
    expect(similarGitHubRepo(repos, ''), isNull);
  });

  test('fuzzy candidates share a meaningful word, not a generic one', () {
    final candidates = [
      const GitHubRepo(
          nameWithOwner: '4e-ecuador/website-bot',
          url: 'https://github.com/4e-ecuador/website-bot'),
      const GitHubRepo(
          nameWithOwner: '4e-ecuador/website-red',
          url: 'https://github.com/4e-ecuador/website-red'),
      const GitHubRepo(
          nameWithOwner: '4e-ecuador/4e-events',
          url: 'https://github.com/4e-ecuador/4e-events'),
    ];

    expect(similarGitHubRepos(candidates, '4e-website').map((r) => r.name),
        ['website-bot', 'website-red']);
    expect(
        similarGitHubRepos(
          const [
            GitHubRepo(
                nameWithOwner: 'elkuku/test-app',
                url: 'https://github.com/elkuku/test-app')
          ],
          'test-opensite'),
        isEmpty);
  });

  test('matching is case insensitive, including organisation owners', () {
    const orgRepos = [
      GitHubRepo(
          nameWithOwner: '4e-ecuador/4E-Manager',
          url: 'https://github.com/4e-ecuador/4E-Manager'),
      GitHubRepo(
          nameWithOwner: 'elkuku/AgentTools',
          url: 'https://github.com/elkuku/AgentTools'),
    ];

    expect(similarGitHubRepo(orgRepos, 'agenttools')?.nameWithOwner,
        'elkuku/AgentTools');
    expect(similarGitHubRepo(orgRepos, '4e-manager')?.nameWithOwner,
        '4e-ecuador/4E-Manager');
  });
}
