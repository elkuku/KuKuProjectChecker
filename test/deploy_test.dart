import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuku_project_checker/main.dart';
import 'package:kuku_project_checker/support/app_services.dart';
import 'package:kuku_project_checker/support/deployer.dart';
import 'package:kuku_project_checker/support/preferences.dart';
import 'package:kuku_project_checker/support/repo_status.dart';
import 'package:kuku_project_checker/support/settings.dart';
import 'package:kuku_project_checker/support/site.dart';
import 'package:kuku_project_checker/support/site_info.dart';
import 'package:kuku_project_checker/widgets/deploy_dialog.dart';

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

class _OneSite extends Settings {
  @override
  Future<List<Site>> readSettings() async => [
        const Site(
            name: 'Shop', url: 'https://shop.example.com', repoPath: '/repo')
      ];
}

class _Light extends Preferences {
  @override
  Future<ThemeMode> readThemeMode() async => ThemeMode.light;

  @override
  Future<void> writeThemeMode(ThemeMode mode) async {}
}

const _pending = RepoStatus(
    branch: 'master',
    uncommitted: 3,
    unpushed: 1,
    deployRemote: 'production',
    undeployed: 2);

void main() {
  group('Deployer', () {
    late Directory tmp;

    setUp(
        () async => tmp = await Directory.systemTemp.createTemp('deploy_test'));
    tearDown(() => tmp.delete(recursive: true));

    test('pushes the branch to the deploy remote', () async {
      final repo = '${tmp.path}/repo';
      final server = '${tmp.path}/server.git';
      await Directory(repo).create();
      await Directory(server).create();
      await git(server, ['init', '-q', '--bare', '-b', 'master']);
      await git(repo, ['init', '-q', '-b', 'master']);
      await git(repo, ['remote', 'add', 'production', server]);
      await File('$repo/a.txt').writeAsString('a');
      await git(repo, ['add', '.']);
      await git(repo, ['commit', '-q', '-m', 'first']);

      final output = <String>[];
      final exitCode =
          await Deployer().push(repo, 'production', 'master', output.add);

      expect(exitCode, 0);
      expect(output.join('\n'), contains('master -> master'));
      expect((await RepoStatus.check(repo)).undeployed, 0);
    });

    test('reports a failed push', () async {
      final repo = '${tmp.path}/repo';
      await Directory(repo).create();
      await git(repo, ['init', '-q', '-b', 'master']);
      await git(
          repo, ['remote', 'add', 'production', '${tmp.path}/missing.git']);

      final output = <String>[];
      final exitCode =
          await Deployer().push(repo, 'production', 'master', output.add);

      expect(exitCode, isNot(0));
      expect(output, isNotEmpty);
    });

    test('asks for SSH passphrases with a graphical askpass program', () {
      final env = Deployer.gitEnvironment({},
          exists: (path) => path == '/usr/bin/ksshaskpass');

      expect(env, {
        'GIT_TERMINAL_PROMPT': '0',
        'SSH_ASKPASS': '/usr/bin/ksshaskpass',
        'SSH_ASKPASS_REQUIRE': 'force',
      });
      expect(
          Deployer.gitEnvironment({'SSH_ASKPASS': '/opt/askpass'},
              exists: (_) => false)['SSH_ASKPASS'],
          '/opt/askpass');
      expect(Deployer.gitEnvironment({}, exists: (_) => false),
          {'GIT_TERMINAL_PROMPT': '0'});
    });
  });

  group('deploy dialog', () {
    Future<void> openDialog(WidgetTester tester, PushFunction push,
        {RepoStatus status = _pending}) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDeployDialog(context,
                siteName: 'Shop',
                repoPath: '/repo',
                status: status,
                push: push),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('asks first, warns about what is not included, then pushes',
        (tester) async {
      final pushes = <String>[];
      await openDialog(tester, (repo, remote, branch, onOutput) async {
        pushes.add('$repo $remote $branch');
        onOutput('To server:~/git/shop.git');
        onOutput('   1a2b3c4..5d6e7f8  master -> master');
        return 0;
      });

      expect(find.text('Deploy Shop?'), findsOneWidget);
      expect(find.textContaining('2 new commits'), findsOneWidget);
      expect(
          find.text('3 uncommitted files are not included.'), findsOneWidget);
      expect(find.textContaining('1 commit is not pushed'), findsOneWidget);
      expect(pushes, isEmpty);

      await tester.tap(find.widgetWithText(FilledButton, 'Deploy'));
      await tester.pumpAndSettle();

      expect(pushes, ['/repo production master']);
      expect(find.text('Pushed to production'), findsOneWidget);
      expect(find.text('1a2b3c4..5d6e7f8  master -> master'), findsOneWidget);
    });

    testWidgets('shows a failed push', (tester) async {
      await openDialog(tester, (repo, remote, branch, onOutput) async {
        onOutput('Permission denied (publickey).');
        return 128;
      });

      await tester.tap(find.widgetWithText(FilledButton, 'Deploy'));
      await tester.pumpAndSettle();

      expect(find.text('The push failed'), findsOneWidget);
      expect(find.text('Permission denied (publickey).'), findsOneWidget);
    });

    testWidgets('cancel does not push', (tester) async {
      var pushed = false;
      await openDialog(tester, (repo, remote, branch, onOutput) async {
        pushed = true;
        return 0;
      });

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(pushed, isFalse);
      expect(find.text('Deploy Shop?'), findsNothing);
    });
  });

  group('site card buttons', () {
    Future<void> showSite(WidgetTester tester, RepoStatus status,
        {double width = 800}) async {
      tester.view.physicalSize = Size(width, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MyApp(
        preferences: _Light(),
        services: AppServices(
          settings: _OneSite(),
          fetchInfo: (_) async =>
              const SystemInfo(sfVersion: '8.1.11', phpVersion: '8.5.12'),
          checkRepo: (_, __) async => status,
          openInTargets: const [],
          push: (a, b, c, d) async => 0,
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('show the changes and the commits to deploy', (tester) async {
      await showSite(tester, _pending);

      expect(
          find.widgetWithText(OutlinedButton, 'Changes (3)'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Deploy (2)'), findsOneWidget);

      await tester.tap(find.text('Deploy (2)'));
      await tester.pumpAndSettle();
      expect(find.text('Deploy Shop?'), findsOneWidget);
    });

    testWidgets('are small count buttons in a wide window', (tester) async {
      await showSite(tester, _pending, width: 1000);

      final deploy = find.byTooltip('Deploy 2 commits to production');
      final changes = find.byTooltip('Show the 3 uncommitted files');
      expect(changes, findsOneWidget);
      expect(deploy, findsOneWidget);
      // One row: the buttons sit level with the site's name.
      expect(
          tester.getCenter(deploy).dy,
          moreOrLessEquals(tester.getCenter(find.text('Shop')).dy,
              epsilon: 12));

      await tester.tap(deploy);
      await tester.pumpAndSettle();
      expect(find.text('Deploy Shop?'), findsOneWidget);
    });

    testWidgets('are off when nothing is pending', (tester) async {
      await showSite(
          tester,
          const RepoStatus(
              branch: 'master',
              uncommitted: 0,
              unpushed: 0,
              deployRemote: 'production',
              undeployed: 0));

      expect(find.textContaining('Deploy ('), findsNothing);
      expect(
          tester
              .widget<OutlinedButton>(
                  find.widgetWithText(OutlinedButton, 'Changes'))
              .onPressed,
          isNull);
      expect(
          tester
              .widget<ButtonStyleButton>(find.ancestor(
                  of: find.text('Deploy'),
                  matching:
                      find.byWidgetPredicate((w) => w is ButtonStyleButton)))
              .onPressed,
          isNull);

      // The menu edits, removes or opens the site; it doesn't deploy.
      await tester.tap(find.byTooltip('Edit, remove or open the site'));
      await tester.pumpAndSettle();
      expect(find.text('Open in browser'), findsOneWidget);
      expect(find.text('Deploy'), findsOneWidget);
      expect(find.text('Changes'), findsOneWidget);
    });
  });
}
