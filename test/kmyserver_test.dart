import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuku_project_checker/main.dart';
import 'package:kuku_project_checker/support/app_services.dart';
import 'package:kuku_project_checker/support/kmyserver.dart';
import 'package:kuku_project_checker/support/preferences.dart';
import 'package:kuku_project_checker/support/repo_status.dart';
import 'package:kuku_project_checker/support/settings.dart';
import 'package:kuku_project_checker/support/site.dart';
import 'package:kuku_project_checker/support/site_info.dart';

import 'helpers.dart';

class _OneSite extends Settings {
  @override
  Future<List<Site>> readSettings() async => [
        legacySite(
            name: 'Shop', url: 'https://shop.example.com', repoPath: '/repo')
      ];
}

class _Light extends Preferences {
  @override
  Future<ThemeMode> readThemeMode() async => ThemeMode.light;

  @override
  Future<void> writeThemeMode(ThemeMode mode) async {}
}

RepoStatus _status(String url) => RepoStatus(
    branch: 'master',
    uncommitted: 0,
    unpushed: 0,
    deployRemote: 'server',
    deployUrl: url,
    undeployed: 0);

void main() {
  group('KMyServerSite', () {
    test('recognizes the site repositories of KMyServer', () {
      expect(
          KMyServerSite.fromRemoteUrl(
              'shop@new.example.com:/srv/sites/shop/repo.git'),
          const KMyServerSite(name: 'shop', host: 'new.example.com'));
      expect(
          KMyServerSite.fromRemoteUrl(
              'ssh://test2@localhost:2222/srv/sites/test2/repo.git'),
          const KMyServerSite(name: 'test2', host: 'localhost', port: 2222));
      expect(
          KMyServerSite.fromRemoteUrl(
              'ssh://shop@host/srv/sites/shop/repo.git/'),
          const KMyServerSite(name: 'shop', host: 'host'));
    });

    test('ignores other remotes', () {
      for (final url in [
        'git@github.com:elkuku/shop.git',
        'https://github.com/elkuku/shop.git',
        'shop_x1@shop.example.com:~/git/shop.git', // Plesk
        'other@host:/srv/sites/shop/repo.git', // not the site's own user
        '/srv/sites/shop/repo.git', // local path
      ]) {
        expect(KMyServerSite.fromRemoteUrl(url), isNull, reason: url);
      }
    });

    test('runs site-deploy as the site user with its full path', () {
      expect(
          const KMyServerSite(name: 'shop', host: 'h', port: 2222)
              .siteDeployArgs(['--rollback']),
          [
            '-p',
            '2222',
            'shop@h',
            '/usr/local/sbin/site-deploy',
            'shop',
            '--rollback'
          ]);
    });
  });

  group('rollback', () {
    Future<List<KMyServerSite>> showSite(WidgetTester tester, String deployUrl,
        {int exitCode = 0}) async {
      final calls = <KMyServerSite>[];
      await tester.pumpWidget(MyApp(
        preferences: _Light(),
        services: AppServices(
          settings: _OneSite(),
          fetchInfo: (_) async =>
              const SystemInfo(sfVersion: '8.1.11', phpVersion: '8.5.13'),
          checkRepo: (_, __) async => _status(deployUrl),
          readLocal: (_) async => throw Exception('none'),
          openInTargets: const [],
          rollback: (site, onOutput) async {
            calls.add(site);
            onOutput(exitCode == 0
                ? 'rolled back: releases/b → releases/a'
                : 'no older release to go back to');
            return exitCode;
          },
        ),
      ));
      await tester.pumpAndSettle();
      await expandRow(tester, 'Shop');

      return calls;
    }

    testWidgets('asks, rolls back and shows the answer', (tester) async {
      final calls = await showSite(
          tester, 'shop@new.example.com:/srv/sites/shop/repo.git');

      await tester.tap(find.byTooltip('Roll back…'));
      await tester.pumpAndSettle();
      expect(find.text('Roll back Shop?'), findsOneWidget);
      expect(find.textContaining('Only the code goes back'), findsOneWidget);
      expect(calls, isEmpty);

      await tester.tap(find.widgetWithText(FilledButton, 'Roll back'));
      await tester.pumpAndSettle();
      expect(
          calls, [const KMyServerSite(name: 'shop', host: 'new.example.com')]);
      expect(find.text('Rolled back'), findsOneWidget);
      expect(find.text('rolled back: releases/b → releases/a'), findsOneWidget);
    });

    testWidgets('shows when there is nothing to go back to', (tester) async {
      await showSite(tester, 'shop@h:/srv/sites/shop/repo.git', exitCode: 1);

      await tester.tap(find.byTooltip('Roll back…'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Roll back'));
      await tester.pumpAndSettle();
      expect(find.text('The rollback failed'), findsOneWidget);
      expect(find.text('no older release to go back to'), findsOneWidget);
    });

    testWidgets('is not offered for other servers', (tester) async {
      await showSite(tester, 'shop_x1@shop.example.com:~/git/shop.git');

      await openOpenInMenu(tester, 'Shop');
      expect(find.text('Open in browser'), findsOneWidget);
      expect(find.text('Roll back…'), findsNothing);
    });
  });
}
