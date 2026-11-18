import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kuku_project_checker/support/repo_status.dart';
import 'package:kuku_project_checker/support/site.dart';
import 'package:kuku_project_checker/widgets/repo_status_text.dart';

Future<void> git(String dir, List<String> args) async {
  final result = await Process.run('git', [
    '-C',
    dir,
    '-c',
    'user.name=Test',
    '-c',
    'user.email=test@example.com',
    '-c',
    'commit.gpgsign=false',
    ...args,
  ]);
  if (result.exitCode != 0) {
    throw Exception('git ${args.join(' ')} failed: ${result.stderr}');
  }
}

Future<void> commit(String dir, String file) async {
  await File('$dir/$file').writeAsString(file);
  await git(dir, ['add', file]);
  await git(dir, ['commit', '-q', '-m', file]);
}

void main() {
  late Directory tmp;
  late String repo;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('repo_status_test');
    repo = '${tmp.path}/repo';

    // A repository with a GitHub-like "origin" and a Plesk-like deploy remote, both bare.
    for (final remote in ['origin', 'deploy']) {
      await Directory('${tmp.path}/$remote.git').create();
      await git('${tmp.path}/$remote.git', ['init', '-q', '--bare', '-b', 'master']);
    }
    await Directory(repo).create();
    await git(repo, ['init', '-q', '-b', 'master']);
    await git(repo, ['remote', 'add', 'origin', '${tmp.path}/origin.git']);
    await git(repo, ['remote', 'add', 'elkuku.dev', '${tmp.path}/deploy.git']);
    await git(repo, ['remote', 'add', 'elkuku.dev-https', 'https://example.com/repo.git']);
    await commit(repo, 'one');
    await git(repo, ['push', '-q', '-u', 'origin', 'master']);
    await git(repo, ['push', '-q', 'elkuku.dev', 'master']);
  });

  tearDown(() => tmp.delete(recursive: true));

  test('a pushed and deployed repository is clean', () async {
    final status = await RepoStatus.check(repo);

    expect(status.branch, 'master');
    expect(status.uncommitted, 0);
    expect(status.unpushed, 0);
    expect(status.deployRemote, 'elkuku.dev');
    expect(status.undeployed, 0);
    expect(status.isClean, isTrue);
    expect(describeRepoStatus(status), 'master · clean, deployed');
  });

  test('counts uncommitted files, unpushed and undeployed commits', () async {
    await commit(repo, 'two');
    await git(repo, ['push', '-q', 'origin', 'master']);
    await commit(repo, 'three');
    await File('$repo/one').writeAsString('changed');
    await File('$repo/new').writeAsString('untracked');

    final status = await RepoStatus.check(repo);

    expect(status.uncommitted, 2);
    expect(status.unpushed, 1);
    expect(status.undeployed, 2);
    expect(status.isClean, isFalse);
    expect(describeRepoStatus(status),
        'master · 2 uncommitted · 1 unpushed · 2 not deployed (elkuku.dev)');
  });

  test('a branch without upstream or deploy remote', () async {
    await git(repo, ['checkout', '-q', '-b', 'feature']);

    final status = await RepoStatus.check(repo);

    expect(status.unpushed, isNull);
    expect(status.undeployed, isNull);
    expect(describeRepoStatus(status),
        'feature · no upstream · not on elkuku.dev');
  });

  test('reports a missing folder and a folder that is not a repository', () async {
    await expectLater(RepoStatus.check('${tmp.path}/missing'),
        throwsA(isA<RepoStatusException>()));
    await expectLater(
        RepoStatus.check(tmp.path), throwsA(isA<RepoStatusException>()));
  });

  test('expands ~ to the home folder', () {
    final home = Platform.environment['HOME'];

    expect(RepoStatus.expandHome('~/repos/x'), '$home/repos/x');
    expect(RepoStatus.expandHome('/abs/path'), '/abs/path');
  });

  test('a site is called by its name, or else by its host', () {
    final named = Site.fromJson(
        {'name': 'Shop', 'url': 'https://shop.example.com', 'repoPath': ''});

    expect(named.displayName, 'Shop');
    expect(named.toJson()['name'], 'Shop');
    expect(const Site(url: 'https://shop.example.com/').displayName,
        'shop.example.com');
  });

  test('reads the old and the new settings format', () {
    final old = Site.fromJson('https://a.example');
    final current =
        Site.fromJson({'url': 'https://b.example', 'repoPath': '~/repos/b'});

    expect(old.url, 'https://a.example');
    expect(old.repoPath, '');
    expect(current.repoPath, '~/repos/b');
    expect(current.toJson(),
        {'name': '', 'url': 'https://b.example', 'repoPath': '~/repos/b'});
  });
}
