import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuku_project_checker/main.dart';
import 'package:kuku_project_checker/support/app_services.dart';
import 'package:kuku_project_checker/support/local_versions.dart';
import 'package:kuku_project_checker/support/repo_status.dart';
import 'package:kuku_project_checker/support/server.dart';
import 'package:kuku_project_checker/support/settings.dart';
import 'package:kuku_project_checker/support/site.dart';
import 'package:kuku_project_checker/support/site_info.dart';

import 'helpers.dart';

class _MemorySettings extends Settings {
  List<Site> sites;

  _MemorySettings(this.sites);

  @override
  Future<List<Site>> readSettings() async => [...sites];

  @override
  Future<File> writeSettings(List<Site> s) async {
    sites = [...s];
    return File('/dev/null');
  }
}

/// The dev badge is only read in server mode, so a server must be active.
TestPreferences get _preferences => TestPreferences(
      servers: const [
        Server(
            name: 'Plesk', remote: 'elkuku.dev', baseUrl: 'https://example.com')
      ],
      active: 'Plesk',
    );

final _shop = legacySite(
  name: 'Shop',
  url: 'https://shop.example.com',
  repoPath: '/repos/shop',
  devUrl: 'https://dev.shop.example.com',
  server: 'Plesk',
);

final _deployedAt = DateTime.utc(2026, 11, 24, 18, 0);

SystemInfo _info({String status = 'ok', DateTime? at}) => SystemInfo(
      sfVersion: '8.1.11',
      phpVersion: '8.5.13',
      lastDeploy: LastDeploy(at: at ?? _deployedAt, status: status),
    );

void main() {
  group('DevState', () {
    final before = _deployedAt.subtract(const Duration(minutes: 5));
    final after = _deployedAt.add(const Duration(minutes: 5));
    LastDeploy deploy(String status) =>
        LastDeploy(at: _deployedAt, status: status);

    test('up to date when the deploy is newer than the upstream commit', () {
      expect(DevState.of(deploy('ok'), before), DevState.upToDate);
      expect(DevState.of(deploy('ok'), null), DevState.upToDate,
          reason: 'Without a local repository there is nothing to compare');
    });

    test('behind when upstream has a newer commit', () {
      expect(DevState.of(deploy('ok'), after), DevState.behind);
    });

    test('a failed deploy wins over the comparison', () {
      expect(DevState.of(deploy('errors'), after), DevState.errors);
      expect(DevState.of(deploy('unfinished'), before), DevState.unfinished);
    });

    test('unknown when the site reports no deploys', () {
      expect(DevState.of(null, after), DevState.unknown);
    });
  });

  test('saves the dev site address', () {
    expect(_shop.toJson()['devUrl'], 'https://dev.shop.example.com');
    expect(
        Site.fromJson(_shop.toJson()).devUrl, 'https://dev.shop.example.com');
    expect(legacySite(url: 'https://a.example').toJson().containsKey('devUrl'),
        isFalse);
  });

  test('reads the time of the newest upstream commit', () async {
    final tmp = await Directory.systemTemp.createTemp('upstream_time');
    addTearDown(() => tmp.delete(recursive: true));
    Future<void> git(String dir, List<String> args) async {
      final r = await Process.run('git', [
        '-C', dir, '-c', 'user.name=T', '-c', 'user.email=t@example.com', //
        '-c', 'commit.gpgsign=false', ...args,
      ], environment: {
        'GIT_COMMITTER_DATE': '2026-11-24T17:30:00+00:00'
      });
      if (r.exitCode != 0) throw Exception(r.stderr);
    }

    await git(tmp.path, ['init', '-q', '--bare', '-b', 'master', 'origin.git']);
    final repo = '${tmp.path}/repo';
    await Directory(repo).create();
    await git(repo, ['init', '-q', '-b', 'master']);
    await git(repo, ['remote', 'add', 'origin', '${tmp.path}/origin.git']);
    await File('$repo/a').writeAsString('a');
    await git(repo, ['add', 'a']);
    await git(repo, ['commit', '-q', '-m', 'a']);

    expect(await RepoStatus.upstreamCommitTime(repo), isNull,
        reason: 'No upstream yet');

    await git(repo, ['push', '-q', '-u', 'origin', 'master']);
    expect(await RepoStatus.upstreamCommitTime(repo),
        DateTime.utc(2026, 11, 24, 17, 30));
    expect(await RepoStatus.upstreamCommitTime('${tmp.path}/missing'), isNull);
  });

  group('in the app', () {
    late _MemorySettings settings;

    /// Returns the addresses read from services so the tests can tell the dev
    /// site apart from the site the versions are compared with.
    Future<List<String>> showApp(WidgetTester tester,
        {required Future<SystemInfo> Function() dev,
        DateTime? upstream}) async {
      tester.view.physicalSize = const Size(1200, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final fetched = <String>[];
      settings = _MemorySettings([_shop]);
      await tester.pumpWidget(MyApp(
        preferences: _preferences,
        services: AppServices(
          settings: settings,
          fetchInfo: (url) {
            fetched.add(url);
            return url == _shop.devUrl
                ? dev()
                : Future.value(_info(at: DateTime.utc(2026, 11, 20)));
          },
          checkRepo: (_, __) async =>
              const RepoStatus(branch: 'master', uncommitted: 0, unpushed: 0),
          listRemotes: (_) async => const [],
          readLocal: (_) async => const LocalVersions(),
          openInTargets: const [],
          upstreamTime: (_) async => upstream,
        ),
      ));
      await tester.pumpAndSettle();
      return fetched;
    }

    testWidgets('an up-to-date dev site', (tester) async {
      await showApp(tester,
          dev: () async => _info(),
          upstream: _deployedAt.subtract(const Duration(hours: 1)));

      await expandRow(tester, 'Shop');
      expect(find.textContaining('dev '), findsOneWidget);
      expect(find.text('dev behind'), findsNothing);
    });

    testWidgets('a dev site behind the upstream branch', (tester) async {
      final fetched = await showApp(tester,
          dev: () async => _info(),
          upstream: _deployedAt.add(const Duration(minutes: 10)));
      await expandRow(tester, 'Shop');

      expect(fetched, contains(_shop.devUrl),
          reason: 'The dev site is read in server mode');
      expect(find.text('dev behind'), findsOneWidget);
      final tooltip = tester.widget<Tooltip>(find.ancestor(
          of: find.text('dev behind'), matching: find.byType(Tooltip)));
      expect(
          tooltip.message, contains('Dev site https://dev.shop.example.com'));
      expect(tooltip.message, contains('newer commits than the last deploy'));
    });

    testWidgets('a dev site whose deploy failed', (tester) async {
      await showApp(tester, dev: () async => _info(status: 'errors'));
      await expandRow(tester, 'Shop');
      expect(find.text('dev errors'), findsOneWidget);
    });

    testWidgets('an unreachable dev site', (tester) async {
      await showApp(tester,
          dev: () => Future.error(const SocketException('refused')));
      await expandRow(tester, 'Shop');
      expect(find.text('dev offline'), findsOneWidget);
    });

    testWidgets('the menu opens the dev site; the dialog edits it',
        (tester) async {
      await showApp(tester, dev: () async => _info());

      await openOpenInMenu(tester, 'Shop');
      expect(find.text('Open dev site'), findsOneWidget);
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      await tapRowButton(tester, 'Shop', 'Edit…');
      final field = find.widgetWithText(TextField, 'Dev site URL');
      expect(tester.widget<TextField>(field).controller!.text,
          'https://dev.shop.example.com');

      // An invalid address is refused; an empty one removes the dev site.
      await tester.enterText(field, 'dev.shop.example.com');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.text('Use a full address, like https://shop.example.com'),
          findsOneWidget);
      expect(settings.sites.single.devUrl, 'https://dev.shop.example.com');

      await tester.enterText(field, '');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(settings.sites.single.devUrl, '');
      expect(find.textContaining('dev '), findsNothing);
    });
  });
}
