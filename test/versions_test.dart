import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuku_project_checker/main.dart';
import 'package:kuku_project_checker/support/app_services.dart';
import 'package:kuku_project_checker/support/local_versions.dart';
import 'package:kuku_project_checker/support/preferences.dart';
import 'package:kuku_project_checker/support/repo_status.dart';
import 'package:kuku_project_checker/support/settings.dart';
import 'package:kuku_project_checker/support/site.dart';
import 'package:kuku_project_checker/support/site_info.dart';

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

const _clean = RepoStatus(
    branch: 'master',
    uncommitted: 0,
    unpushed: 0,
    deployRemote: 'production',
    undeployed: 0);

void main() {
  group('SystemInfo.fromJson', () {
    test('reads the versions only, as older sites send them', () {
      final info = SystemInfo.fromJson(
          {'sf_version': '8.1.11', 'php_version': '8.5.12'});

      expect(info.sfVersion, '8.1.11');
      expect(info.dbVersion, isNull);
      expect(info.lastDeploy, isNull);
    });

    test('reads the database and the last deploy', () {
      final info = SystemInfo.fromJson(jsonDecode('''{
        "sf_version": "8.1.11", "php_version": "8.5.12",
        "db_platform": "mariadb", "db_version": "12.3.4-MariaDB-deb12",
        "last_deploy": {"at": "2026-11-23T15:45:02+00:00", "status": "errors"}
      }'''));

      expect(info.dbPlatform, 'mariadb');
      expect(info.dbVersion, '12.3.4-MariaDB-deb12');
      expect(info.lastDeploy!.status, 'errors');
      expect(info.lastDeploy!.at, DateTime.utc(2026, 11, 23, 15, 45, 2));
    });

    test('takes unknown values as missing', () {
      final info = SystemInfo.fromJson({
        'sf_version': '8.1.11',
        'php_version': '8.5.12',
        'db_platform': null,
        'db_version': null,
        'last_deploy': {'at': null, 'status': 'unfinished'},
      });

      expect(info.dbVersion, isNull);
      expect(info.lastDeploy!.at, isNull);
      expect(info.lastDeploy!.ok, isFalse);
    });
  });

  group('LocalVersions', () {
    test('reads Symfony from composer.lock', () {
      expect(
          LocalVersions.symfonyFromLock(jsonEncode({
            'packages': [
              {'name': 'symfony/console', 'version': 'v8.1.9'},
              {'name': 'symfony/http-kernel', 'version': 'v8.1.11'},
            ]
          })),
          '8.1.11');
      expect(LocalVersions.symfonyFromLock('{"packages": []}'), isNull);
      expect(LocalVersions.symfonyFromLock('not json'), isNull);
    });

    test('reads the database from the compose image', () {
      expect(LocalVersions.databaseFromCompose(['''
services:
  database:
    # Matches the production server
    image: mariadb:12.3
  pma:
    image: phpmyadmin
''']), ('mariadb', '12.3'));

      expect(LocalVersions.databaseFromCompose(['''
services:
  database:
    image: postgres:\${POSTGRES_VERSION:-16}-alpine
''']), ('postgresql', '16'));

      expect(
          LocalVersions.databaseFromCompose(["    image: 'mysql:8.0.32'"]),
          ('mysql', '8.0.32'));
      expect(
          LocalVersions.databaseFromCompose(['image: postgis/postgis:16-3.4']),
          ('postgresql', '16'));
      expect(LocalVersions.databaseFromCompose(['image: mariadb:latest']),
          isNull);
      expect(LocalVersions.databaseFromCompose(['image: adminer:4']), isNull);
    });

    test('an override file wins', () {
      expect(
          LocalVersions.databaseFromCompose(
              ['image: postgres:16-alpine', 'image: postgres:15-alpine']),
          ('postgresql', '15'));
    });

    test('compares as far as the local version goes', () {
      expect(LocalVersions.matches('16', '16.4 (Debian 16.4-1.pgdg120+1)'),
          isTrue);
      expect(LocalVersions.matches('16', '13.23'), isFalse);
      expect(LocalVersions.matches('12.3', '12.3.4-MariaDB-deb12'), isTrue);
      expect(LocalVersions.matches('8.1.11', '8.1.11'), isTrue);
      expect(LocalVersions.matches('8.1.11', '8.1.10'), isFalse);
      expect(LocalVersions.matches('8.5.13', '8.5.12', maxParts: 2), isTrue);
      expect(LocalVersions.matches('8.4', '5.5.5-8.4.3'), isTrue);
      expect(LocalVersions.matches('16', 'N/A'), isFalse);
    });

    test('reads a repository', () async {
      final dir = await Directory.systemTemp.createTemp('local_versions');
      addTearDown(() => dir.delete(recursive: true));
      await File('${dir.path}/composer.lock').writeAsString(jsonEncode({
        'packages': [
          {'name': 'symfony/http-kernel', 'version': 'v8.1.11'}
        ]
      }));
      await File('${dir.path}/docker-compose.yaml')
          .writeAsString('services:\n  database:\n    image: mariadb:12.3\n');

      final local =
          await LocalVersions.read(dir.path, phpVersion: () async => '8.5.13');

      expect(local.symfony, '8.1.11');
      expect(local.php, '8.5.13');
      expect(local.dbPlatform, 'mariadb');
      expect(local.dbVersion, '12.3');
    });
  });

  group('version badges', () {
    Future<void> showSite(WidgetTester tester, SystemInfo info,
        LocalVersions? local) async {
      tester.view.physicalSize = const Size(800, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MyApp(
        preferences: _Light(),
        services: AppServices(
          settings: _OneSite(),
          fetchInfo: (_) async => info,
          checkRepo: (_) async => _clean,
          readLocal: (_) async => local ?? const LocalVersions(),
          openInTargets: const [],
          push: (a, b, c, d) async => 0,
        ),
      ));
      await tester.pumpAndSettle();
    }

    String tooltipOf(WidgetTester tester, String text) => tester
        .widget<Tooltip>(
            find.ancestor(of: find.text(text), matching: find.byType(Tooltip)))
        .message!;

    testWidgets('show the database and the last deploy', (tester) async {
      await showSite(
        tester,
        SystemInfo(
          sfVersion: '8.1.11',
          phpVersion: '8.5.12',
          dbPlatform: 'mariadb',
          dbVersion: '12.3.4-MariaDB-deb12',
          lastDeploy: LastDeploy(
              at: DateTime.now().subtract(const Duration(hours: 3)),
              status: 'ok'),
        ),
        const LocalVersions(
            symfony: '8.1.11',
            php: '8.5.13',
            dbPlatform: 'mariadb',
            dbVersion: '12.3'),
      );

      expect(find.text('PHP 8.5.12'), findsOneWidget);
      expect(find.text('Symfony 8.1.11'), findsOneWidget);
      expect(find.text('MariaDB 12.3.4'), findsOneWidget);
      expect(find.text('3h ago'), findsOneWidget);
      // Everything matches: no orange badge.
      expect(find.byIcon(Icons.compare_arrows), findsNothing);
      expect(tooltipOf(tester, 'MariaDB 12.3.4'),
          'MariaDB 12.3.4-MariaDB-deb12 on the site\nMariaDB 12.3 locally');
      expect(tooltipOf(tester, '3h ago'), startsWith('Last deploy: deployed\n'));
    });

    testWidgets('mark versions that differ from the local project',
        (tester) async {
      await showSite(
        tester,
        const SystemInfo(
          sfVersion: '8.1.10',
          phpVersion: '8.5.12',
          dbPlatform: 'postgresql',
          dbVersion: '13.23',
          lastDeploy: LastDeploy(status: 'errors'),
        ),
        const LocalVersions(
            symfony: '8.1.11',
            php: '8.5.13',
            dbPlatform: 'postgresql',
            dbVersion: '16'),
      );

      // Symfony and the database differ; PHP only in the patch version.
      expect(find.byIcon(Icons.compare_arrows), findsNWidgets(2));
      expect(tooltipOf(tester, 'Symfony 8.1.10'),
          contains('Symfony 8.1.11 locally'));
      expect(tooltipOf(tester, 'PostgreSQL 13.23'),
          contains('The site runs a different version'));
      expect(tooltipOf(tester, 'unknown'),
          'Last deploy: finished with errors');
    });

    testWidgets('show only the versions for an older site', (tester) async {
      await showSite(tester,
          const SystemInfo(sfVersion: 'N/A', phpVersion: '8.5.12'), null);

      expect(find.text('Symfony N/A'), findsOneWidget);
      expect(find.byIcon(Icons.storage), findsNothing);
      expect(find.byIcon(Icons.rocket_launch_outlined), findsNothing);
      expect(find.byIcon(Icons.compare_arrows), findsNothing);
    });
  });
}
