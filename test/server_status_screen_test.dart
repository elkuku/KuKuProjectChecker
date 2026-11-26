import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuku_project_checker/main.dart';
import 'package:kuku_project_checker/screens/server_status_screen.dart';
import 'package:kuku_project_checker/support/app_services.dart';
import 'package:kuku_project_checker/support/preferences.dart';
import 'package:kuku_project_checker/support/repo_status.dart';
import 'package:kuku_project_checker/support/server.dart';
import 'package:kuku_project_checker/support/server_api.dart';
import 'package:kuku_project_checker/support/server_health.dart';
import 'package:kuku_project_checker/support/settings.dart';
import 'package:kuku_project_checker/support/site.dart';
import 'package:kuku_project_checker/support/site_info.dart';

const vm = Server(
    name: 'Test VM',
    remote: 'vm',
    sshHost: 'localhost',
    sshPort: 2222,
    sitePort: 8443);

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
        {'name': 'caddy', 'state': healthy ? 'active' : 'inactive', 'ok': healthy},
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
        {required FetchServerHealth fetch}) async {
  // The report is a lazy ListView; a tall test window keeps every section mounted.
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    home: ServerStatusScreen(server: vm, fetch: fetch),
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

void main() {
  group('server status screen', () {
    testWidgets('shows a healthy report and its sites', (tester) async {
      await showScreen(
        tester,
        fetch: (_) async => ServerHealth.fromJson(_json(healthy: true)),
      );

      expect(find.text('Server: Test VM'), findsOneWidget);
      expect(find.text('test-vm'), findsOneWidget);
      expect(find.text('Everything looks OK'), findsOneWidget);
      expect(find.text('starter.localhost'), findsOneWidget);

      await tester.tap(find.text('starter.localhost'));
      await tester.pumpAndSettle();
      expect(find.text('No problems'), findsOneWidget);
    });

    testWidgets('shows problems first and the site reasons', (tester) async {
      await showScreen(
        tester,
        fetch: (_) async => ServerHealth.fromJson(_json()),
      );

      expect(find.text('caddy is inactive'), findsOneWidget);
      expect(find.textContaining('Backup stale since'), findsOneWidget);
      expect(find.text('Last mail failed'), findsOneWidget);

      await tester.tap(find.text('starter.localhost'));
      await tester.pumpAndSettle();
      expect(find.text('starter.localhost: http 000'), findsOneWidget);
      expect(find.text('starter.localhost: last deploy failed'), findsOneWidget);
      expect(find.textContaining('Database connection failed'), findsOneWidget);
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

  testWidgets('the server menu opens the status page', (tester) async {
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

    await tester.tap(
        find.byTooltip('Switch the server the sites deploy to'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Server status…'));
    await tester.pumpAndSettle();

    expect(fetched, [vm]);
    expect(find.text('Server: Test VM'), findsOneWidget);
  });
}
