import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kuku_project_checker/screens/changes_screen.dart';
import 'package:kuku_project_checker/support/repo_changes.dart';

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

void main() {
  late Directory tmp;
  late String repo;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('repo_changes_test');
    repo = tmp.path;
    await git(repo, ['init', '-q', '-b', 'master']);
    await File('$repo/kept.txt').writeAsString('one\ntwo\nthree\n');
    await File('$repo/gone.txt').writeAsString('bye\n');
    await File('$repo/old name.txt').writeAsString('moving\n');
    await git(repo, ['add', '.']);
    await git(repo, ['commit', '-q', '-m', 'start']);
  });

  tearDown(() => tmp.delete(recursive: true));

  test('lists modified, deleted, renamed, staged and untracked files',
      () async {
    await File('$repo/kept.txt').writeAsString('one\nTWO\nthree\n');
    await File('$repo/gone.txt').delete();
    await git(repo, ['mv', 'old name.txt', 'new näme.txt']);
    await File('$repo/staged.txt').writeAsString('staged\n');
    await git(repo, ['add', 'staged.txt']);
    await File('$repo/untracked file.txt').writeAsString('hello\n');

    final files = await RepoChanges(repo).files();

    expect(
      {for (final file in files) file.path: file.state},
      {
        'kept.txt': 'modified',
        'gone.txt': 'deleted',
        'new näme.txt': 'renamed',
        'staged.txt': 'added',
        'untracked file.txt': 'new',
      },
    );
    expect(files.firstWhere((file) => file.state == 'renamed').fromPath,
        'old name.txt');
  });

  test('diffs a modified file against the last commit', () async {
    await File('$repo/kept.txt').writeAsString('one\nTWO\nthree\n');

    final diff =
        await RepoChanges(repo).diff(const ChangedFile(' M', 'kept.txt'));

    expect(diff, contains('-two\n+TWO'));
  });

  test('shows an untracked file as completely added', () async {
    await File('$repo/untracked file.txt').writeAsString('hello\nworld\n');

    final diff = await RepoChanges(repo)
        .diff(const ChangedFile('??', 'untracked file.txt'));

    expect(diff, contains('+hello\n+world'));
  });

  test('lists the files of an untracked folder', () async {
    await Directory('$repo/newdir').create();
    await File('$repo/newdir/a.txt').writeAsString('a\n');
    final files = await RepoChanges(repo).files();

    expect(files, [const ChangedFile('??', 'newdir/')]);
    expect(
        await RepoChanges(repo).diff(files.single), contains('newdir/a.txt'));
  });

  test('shows a deleted file as removed', () async {
    await File('$repo/gone.txt').delete();

    final diff =
        await RepoChanges(repo).diff(const ChangedFile(' D', 'gone.txt'));

    expect(diff, contains('-bye'));
  });

  test('a clean repository has no changes', () async {
    expect(await RepoChanges(repo).files(), isEmpty);
  });

  test('parses rename entries of git status -z', () {
    expect(
      RepoChanges.parseStatus(
          'R  new.txt\x00old.txt\x00 M a b.txt\x00?? c\x00'),
      [
        const ChangedFile('R ', 'new.txt', fromPath: 'old.txt'),
        const ChangedFile(' M', 'a b.txt'),
        const ChangedFile('??', 'c'),
      ],
    );
  });

  test('colors diff lines by their kind', () {
    expect(DiffLine.kind('+added'), 'added');
    expect(DiffLine.kind('-removed'), 'removed');
    expect(DiffLine.kind('--- a/file'), 'header');
    expect(DiffLine.kind('+++ b/file'), 'header');
    expect(DiffLine.kind('@@ -1,3 +1,3 @@'), 'hunk');
    expect(DiffLine.kind('diff --git a/x b/x'), 'header');
    expect(DiffLine.kind(' context'), 'context');
  });
}
