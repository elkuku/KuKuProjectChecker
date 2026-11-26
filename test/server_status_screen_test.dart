import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuku_project_checker/main.dart';
import 'package:kuku_project_checker/screens/server_status_screen.dart';
import 'package:kuku_project_checker/support/app_services.dart';
import 'package:kuku_project_checker/support/deployer.dart' show RunFunction;
import 'package:kuku_project_checker/support/preferences.dart';
import 'package:kuku_project_checker/support/repo_status.dart';
import 'package:kuku_project_checker/support/server.dart';
import 'package:kuku_project_checker/support/server_api.dart';
import 'package:kuku_project_checker/support/server_health.dart';
import 'package:kuku_project_checker/support/settings.dart';
import 'package:kuku_project_checker/support/site.dart';
import 'package:kuku_project_checker/support/site_info.dart';

import 'helpers.dart';

const vm = Server(
    name: 'Test VM',
    remote: 'vm',
    sshHost: 'localhost',
    sshPort: 2222,
    sitePort: 8443,
    domainSuffix: 'example.com');

Map<String, dynamic> _json({bool healthy = false}) => {
      'schema': 1,
      'generatedAt': '2026-11-26T09:00:00Z',
      'host': 'test-vm',
      'problems': healthy ? 0 : 5,
      'system': {
        'os': 'Debian 13.8, kernel 6.12',
        'kernel': '6.12',
        'uptime': ' 09:00:00 up  1:42',
        'rebootRequired': false,
        'rebootPackages': [],
      },
      'services': [
        {
          'name': 'caddy',
          'state': healthy ? 'active' : 'inactive',
          'ok': healthy
        },
      ],
      'failedUnits': [],
      'disk': [
        {
          'mount': '/',
          'size': '80G',
          'used': healthy ? '12G' : '70G',
          'available': healthy ? '68G' : '10G',
          'percent': healthy ? 15 : 88,
        },
      ],
      'memory': {'total': '2.0Gi', 'used': '380Mi'},
      'updates': {'pending': 0, 'lastUnattended': '2026-11-26 06:12'},
      'security': {
        'bannedNow': 0,
        'bannedTotal': 7,
        'listening': [22, 80, 443],
        'firewall': [22, 80, 443],
      },
      'backup': {
        'ok': healthy,
        'lastOk': '2026-11-26 02:30',
        'ageHours': 7,
        'sets': 14,
      },
      'mail': {
        'configured': true,
        'ok': healthy,
        'last': healthy ? '2026-11-26 06:00' : '',
      },
      'sites': [
        {
          'name': 'starter',
          'domain': 'starter.localhost',
          'http': healthy ? 200 : 0,
          'certificate': {'days': 0, 'issuer': 'Caddy Local Authority'},
          'release': '20261125-1412',
          'revision': '33abb4d',
          'deploy': {
            'state': healthy ? 'ok' : 'failed',
            'when': '2026-11-26 08:45',
          },
          'critical24h': healthy ? 0 : 2,
          'lastCritical': healthy ? null : 'Database connection failed',
          'problems': healthy ? [] : ['http 000', 'last deploy failed'],
        },
      ],
    };

Future<void> showScreen(WidgetTester tester,
    {required FetchServerHealth fetch,
    RunFunction? run,
    NewSiteFromServer? onNewSite}) async {
  // The report is a lazy ListView; a tall test window keeps every section mounted.
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    home: ServerStatusScreen(
      server: vm,
      fetch: fetch,
      run: run ?? (_, __, ___, {workingDirectory}) async => 0,
      onNewSite: onNewSite,
    ),
  ));
  await tester.pumpAndSettle();
}

class _Preferences extends Preferences {
  @override
  Future<ThemeMode> readThemeMode() async => ThemeMode.light;

  @override
  Future<void> writeThemeMode(ThemeMode mode) async {}

  @override
  Future<(List<Server>, String)> readServers() async => ([vm], 'Test VM');
}

class _NoSites extends Settings {
  @override
  Future<List<Site>> readSettings() async => [];
}

class _OneSite extends Settings {
  @override
  Future<List<Site>> readSettings() async => [
        const Site(url: 'https://starter.localhost:8443'),
      ];
}

class _OneRepo extends Settings {
  @override
  Future<List<Site>> readSettings() async => [
        const Site(
            name: 'Shop',
            url: 'https://shop.example.com',
            repoPath: '~/repos/shop'),
      ];
}

class _NoSitesNoWrite extends Settings {
  int writes = 0;

  @override
  Future<List<Site>> readSettings() async => [];

  @override
  Future<File> writeSettings(List<Site> sites) async {
    writes++;
    return File('/dev/null');
  }
}

void main() {
  group('server status screen', () {
    testWidgets('shows a healthy host report without a site list',
        (tester) async {
      await showScreen(
        tester,
        fetch: (_) async => ServerHealth.fromJson(_json(healthy: true)),
      );

      expect(find.text('Server: Test VM'), findsOneWidget);
      expect(find.text('test-vm'), findsOneWidget);
      expect(find.text('Everything looks OK'), findsOneWidget);
      // The server's sites now live in the projects list, not in this pane.
      expect(find.text('starter.localhost'), findsNothing);
      expect(find.text('Sites (1)'), findsNothing);
    });

    testWidgets('shows problems first and the site reasons', (tester) async {
      await showScreen(
        tester,
        fetch: (_) async => ServerHealth.fromJson(_json()),
      );

      expect(find.text('caddy is inactive'), findsOneWidget);
      expect(find.textContaining('Backup stale since'), findsOneWidget);
      expect(find.text('Last mail failed'), findsOneWidget);
      expect(find.text('starter.localhost: http 000'), findsOneWidget);
      expect(
          find.text('starter.localhost: last deploy failed'), findsOneWidget);
    });

    testWidgets('runs an allowlisted action through the injected runner',
        (tester) async {
      final calls = <List<String>>[];
      await showScreen(
        tester,
        fetch: (_) async => ServerHealth.fromJson(_json(healthy: true)),
        run: (_, arguments, onOutput, {workingDirectory}) async {
          calls.add(arguments);
          onOutput('backup ok');
          return 0;
        },
      );

      await tester.tap(find.text('Run backup'));
      await tester.pumpAndSettle();
      final confirm = find.descendant(
          of: find.byType(AlertDialog), matching: find.text('Run backup'));
      await tester.tap(confirm);
      await tester.pumpAndSettle();

      expect(calls, [
        ['-p', '2222', 'root@localhost', '/usr/local/sbin/server-backup', 'run']
      ]);
      expect(find.text('backup ok'), findsOneWidget);
      expect(find.text('Run backup finished'), findsOneWidget);
    });

    testWidgets('links to the existing new-site wizard', (tester) async {
      var opened = 0;
      await showScreen(
        tester,
        fetch: (_) async => ServerHealth.fromJson(_json(healthy: true)),
        onNewSite: () async => opened++,
      );

      await tester.tap(find.text('New site…'));
      expect(opened, 1);
    });

    testWidgets('reports an SSH error and can retry', (tester) async {
      var calls = 0;
      await showScreen(
        tester,
        fetch: (_) async {
          calls++;
          if (calls == 1) throw 'ssh: connect to host failed';
          return ServerHealth.fromJson(_json(healthy: true));
        },
      );

      expect(find.text('Could not read the server'), findsOneWidget);
      expect(find.textContaining('connect to host failed'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('Everything looks OK'), findsOneWidget);
    });
  });

  testWidgets('the selected server shows its status on the main screen',
      (tester) async {
    final fetched = <Server>[];
    await tester.pumpWidget(MyApp(
      preferences: _Preferences(),
      services: AppServices(
        settings: _NoSites(),
        fetchInfo: (_) async =>
            const SystemInfo(sfVersion: '8.1.11', phpVersion: '8.5.13'),
        checkRepo: (_, __) async =>
            const RepoStatus(branch: 'master', uncommitted: 0),
        readLocal: (_) async => throw Exception('none'),
        openInTargets: const [],
        fetchServerHealth: (server) async {
          fetched.add(server);
          return ServerHealth.fromJson(_json(healthy: true));
        },
      ),
    ));
    await tester.pumpAndSettle();

    expect(fetched, [vm]);
    expect(find.text('Server: Test VM'), findsOneWidget);
    expect(find.text('Everything looks OK'), findsOneWidget);

    await tester.tap(find.byTooltip('Switch the server the sites deploy to'));
    await tester.pumpAndSettle();
    expect(find.text('Server status…'), findsNothing);
  });

  testWidgets('a wide window shows the status beside the site list',
      (tester) async {
    tester.view.physicalSize = const Size(2000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MyApp(
      preferences: _Preferences(),
      services: AppServices(
        settings: _OneSite(),
        fetchInfo: (_) async =>
            const SystemInfo(sfVersion: '8.1.11', phpVersion: '8.5.13'),
        checkRepo: (_, __) async =>
            const RepoStatus(branch: 'master', uncommitted: 0),
        readLocal: (_) async => throw Exception('none'),
        openInTargets: const [],
        fetchServerHealth: (_) async => ServerHealth.fromJson(_json()),
      ),
    ));
    await tester.pumpAndSettle();

    // The server's site status reached the site card, not just the status pane.
    expect(find.text('offline'), findsOneWidget);
    expect(find.text('failed'), findsOneWidget);
    expect(find.text('2 CRITICAL'), findsOneWidget);

    final panel = find.byWidgetPredicate((w) => w is ServerStatusPanel);
    final row = find.ancestor(
        of: panel, matching: find.byWidgetPredicate((w) => w is Row));
    expect(find.descendant(of: row, matching: find.byType(ReorderableListView)),
        findsOneWidget);
  });

  testWidgets('server sites without a project are listed temporarily',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final settings = _NoSitesNoWrite();
    final calls = <List<String>>[];

    await tester.pumpWidget(MyApp(
      preferences: _Preferences(),
      services: AppServices(
        settings: settings,
        fetchInfo: (_) async =>
            const SystemInfo(sfVersion: '8.1.11', phpVersion: '8.5.13'),
        checkRepo: (_, __) async =>
            const RepoStatus(branch: 'master', uncommitted: 0),
        readLocal: (_) async => throw Exception('none'),
        openInTargets: const [],
        fetchServerHealth: (_) async => ServerHealth.fromJson(_json()),
        run: (_, arguments, onOutput, {workingDirectory}) async {
          calls.add(arguments);
          return 0;
        },
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('No projects yet'), findsNothing);
    expect(find.text('starter'), findsOneWidget);
    expect(find.text('starter.localhost'), findsOneWidget);
    expect(settings.writes, 0);

    await expandRow(tester, 'starter');
    expect(
        find.textContaining('not in the projects (temporary)'), findsOneWidget);
    // The dropdown only opens the site; the allowlisted actions are buttons.
    expect(find.byTooltip('Open in…'), findsOneWidget);
    await tapRowButton(tester, 'starter', 'Releases…');

    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Releases'),
    ));
    await tester.pumpAndSettle();

    expect(calls, [
      [
        '-p',
        '2222',
        'starter@localhost',
        '/usr/local/sbin/site-deploy',
        'starter',
        '--list'
      ]
    ]);
    // A read action does not change anything, so no settings write or reload.
    expect(settings.writes, 0);
  });

  testWidgets('a project not on the server can be created and deployed',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final calls = <List<String>>[];
    final pushes = <(String, String, String)>[];
    final health = _json(healthy: true)..['sites'] = [];

    await tester.pumpWidget(MyApp(
      preferences: _Preferences(),
      services: AppServices(
        settings: _OneRepo(),
        fetchInfo: (_) async =>
            const SystemInfo(sfVersion: '8.1.11', phpVersion: '8.5.13'),
        checkRepo: (_, __) async =>
            const RepoStatus(branch: 'master', uncommitted: 0),
        readLocal: (_) async => throw Exception('none'),
        openInTargets: const [],
        listRemotes: (_) async => [
          ('origin', 'https://github.com/elkuku/shop.git'),
        ],
        fetchServerHealth: (_) async => ServerHealth.fromJson(health),
        run: (_, arguments, onOutput, {workingDirectory}) async {
          calls.add(arguments);
          onOutput('remote: ok');
          return 0;
        },
        push: (repoPath, remote, branch, onOutput) async {
          pushes.add((repoPath, remote, branch));
          onOutput('remote: ok');
          return 0;
        },
      ),
    ));
    await tester.pumpAndSettle();

    await tapRowButton(tester, 'Shop', 'Deploy to Test VM…', expand: true);

    expect(find.text('shop'), findsWidgets);
    await tester.tap(find.text('Create and deploy'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Deploy'));
    await tester.pumpAndSettle();

    expect(calls[0], [
      '-p',
      '2222',
      'root@localhost',
      '/usr/local/sbin/site-add',
      'shop',
      '--domain',
      'shop.example.com',
      '--template',
      'https://github.com/elkuku/shop.git'
    ]);
    expect(calls[1], [
      '-C',
      RepoStatus.expandHome('~/repos/shop'),
      'remote',
      'add',
      'vm',
      'ssh://shop@localhost:2222/srv/sites/shop/repo.git'
    ]);
    expect(pushes, [(RepoStatus.expandHome('~/repos/shop'), 'vm', 'master')]);

    // The deploy dialog reports the push first; closing it finishes this flow.
    await tester.tap(find.widgetWithText(FilledButton, 'Close'));
    await tester.pumpAndSettle();
    expect(find.text('shop is live on Test VM'), findsOneWidget);
  });
}
