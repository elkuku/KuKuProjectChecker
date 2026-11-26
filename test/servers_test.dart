import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuku_project_checker/main.dart';
import 'package:kuku_project_checker/support/app_services.dart';
import 'package:kuku_project_checker/support/preferences.dart';
import 'package:kuku_project_checker/support/repo_status.dart';
import 'package:kuku_project_checker/support/server.dart';
import 'package:kuku_project_checker/support/server_health.dart';
import 'package:kuku_project_checker/support/settings.dart';
import 'package:kuku_project_checker/support/site.dart';
import 'package:kuku_project_checker/support/site_creator.dart';
import 'package:kuku_project_checker/support/site_info.dart';

import 'helpers.dart';

const _plesk = Server(name: 'Plesk', remote: 'elkuku.dev');
const _vm = Server(
    name: 'Test VM',
    remote: 'vm',
    sshHost: 'localhost',
    sshPort: 2222,
    sitePort: 8443);

ServerHealth _healthy() => ServerHealth.fromJson({
      'schema': 1,
      'generatedAt': '2026-11-26T09:00:00Z',
      'host': 'test-vm',
      'problems': 0,
      'system': {
        'os': 'Debian 13.8, kernel 6.12',
        'kernel': '6.12',
        'uptime': ' 09:00:00 up  1:42',
        'rebootRequired': false,
        'rebootPackages': [],
      },
      'services': [
        {'name': 'caddy', 'state': 'active', 'ok': true},
      ],
      'failedUnits': [],
      'disk': [
        {
          'mount': '/',
          'size': '80G',
          'used': '12G',
          'available': '68G',
          'percent': 15,
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
        'ok': true,
        'lastOk': '2026-11-26 02:30',
        'ageHours': 7,
        'sets': 14,
      },
      'mail': {'configured': true, 'ok': true, 'last': '2026-11-26 06:00'},
      'sites': [
        {
          'name': 'starter',
          'domain': 'starter.localhost',
          'http': 200,
          'certificate': {'days': 0, 'issuer': 'Caddy Local Authority'},
          'release': '20261125-1412',
          'revision': '33abb4d',
          'deploy': {'state': 'ok', 'when': '2026-11-26 08:45'},
          'critical24h': 0,
          'lastCritical': null,
          'problems': [],
        },
      ],
    });

/// Preferences in memory: tests can't read files inside the fake clock of widget tests.
class _Memory extends Preferences {
  List<Server> servers;
  String active;

  _Memory(this.servers, [this.active = '']);

  @override
  Future<ThemeMode> readThemeMode() async => ThemeMode.light;

  @override
  Future<void> writeThemeMode(ThemeMode mode) async {}

  @override
  Future<(List<Server>, String)> readServers() async => (servers, active);

  @override
  Future<void> writeServers(List<Server> servers, String active) async {
    this.servers = servers;
    this.active = active;
  }
}

class _Sites extends Settings {
  final List<Site> sites;
  _Sites(this.sites);

  @override
  Future<List<Site>> readSettings() async => sites;

  @override
  Future<File> writeSettings(List<Site> sites) async {
    final saved = [...sites];
    this.sites
      ..clear()
      ..addAll(saved);
    return File('unused');
  }
}

void main() {
  group('Server', () {
    test('reads back what it saves', () {
      for (final server in [_plesk, _vm]) {
        expect(Server.fromJson(server.toJson()), server);
      }
      expect(_plesk.toJson(), {'name': 'Plesk', 'remote': 'elkuku.dev'});
      expect(_plesk.isKMyServer, isFalse);
      expect(_vm.isKMyServer, isTrue);
    });

    test('builds the ssh arguments and the site repository URL', () {
      expect(_vm.sshArgs('root', ['uptime']),
          ['-p', '2222', 'root@localhost', 'uptime']);
      expect(_vm.siteRepoUrl('shop'),
          'ssh://shop@localhost:2222/srv/sites/shop/repo.git');
      expect(
          const Server(name: 'New', remote: 'kmyserver', sshHost: 'h')
              .siteRepoUrl('shop'),
          'shop@h:/srv/sites/shop/repo.git');
      expect(_vm.siteUrl('shop.localhost'), 'https://shop.localhost:8443');
      expect(_plesk.siteUrl('shop.example.com'), 'https://shop.example.com');
      expect(Server.remoteError('kmyserver'), isNull);
      expect(Server.remoteError('my remote'), isNotNull);
    });

    test('are kept in preferences.json next to the theme', () async {
      final dir = await Directory.systemTemp.createTemp('servers_test');
      addTearDown(() => dir.delete(recursive: true));
      final preferences = Preferences(directory: () async => dir);

      final (none, noActive) = await preferences.readServers();
      expect(none, isEmpty);
      expect(noActive, '');
      await preferences.writeThemeMode(ThemeMode.dark);
      await preferences.writeServers([_plesk, _vm], 'Test VM');

      final (servers, active) = await preferences.readServers();
      expect(servers, [_plesk, _vm]);
      expect(active, 'Test VM');
      expect(await preferences.readThemeMode(), ThemeMode.dark);

      // An active server that is no longer in the list means: each site's own remote.
      await preferences.writeServers([_plesk], 'Test VM');
      expect((await preferences.readServers()).$2, '');
    });
  });

  group('switching the server', () {
    Future<List<String>> showApp(WidgetTester tester, _Memory preferences,
        {String siteRemote = SiteTarget.autoDeploy}) async {
      final checked = <String>[];
      await tester.pumpWidget(MyApp(
        preferences: preferences,
        services: AppServices(
          settings: _Sites([
            legacySite(
                name: 'Shop',
                url: 'https://shop.example.com',
                repoPath: '/repo',
                deployRemote: siteRemote)
          ]),
          fetchInfo: (_) async =>
              const SystemInfo(sfVersion: '8.1.11', phpVersion: '8.5.13'),
          checkRepo: (_, remote) async {
            checked.add(remote);
            return const RepoStatus(branch: 'master', uncommitted: 0);
          },
          readLocal: (_) async => throw Exception('none'),
          openInTargets: const [],
          fetchServerHealth: (_) async => _healthy(),
        ),
      ));
      await tester.pumpAndSettle();
      return checked;
    }

    testWidgets('uses the project environment remote on every server',
        (tester) async {
      final preferences = _Memory([_plesk, _vm], 'Test VM');
      final checked = await showApp(tester, preferences);

      expect(checked.last, SiteTarget.autoDeploy);
      expect(find.text('Test VM'), findsOneWidget);

      await tester.tap(find.byTooltip('Switch the server the sites deploy to'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Plesk  (remote elkuku.dev)'));
      await tester.pumpAndSettle();
      expect(checked.last, SiteTarget.autoDeploy);
      expect(preferences.active, 'Plesk');

      await tester.tap(find.byTooltip('Switch the server the sites deploy to'));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Each site's own deploy remote"));
      await tester.pumpAndSettle();
      expect(checked.last, SiteTarget.autoDeploy);
      expect(preferences.active, '');
    });

    testWidgets('leaves sites alone that never deploy', (tester) async {
      final checked = await showApp(tester, _Memory([_vm], 'Test VM'),
          siteRemote: SiteTarget.noDeploy);

      expect(checked.last, SiteTarget.noDeploy);
    });

    testWidgets('servers can be added in the app', (tester) async {
      final preferences = _Memory([]);
      await showApp(tester, preferences);

      await tester.tap(find.byTooltip('Switch the server the sites deploy to'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Servers…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add server'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Name'), 'New server');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Git remote'), 'kmyserver');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'SSH host'), 'new.example.com');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(preferences.servers, [
        const Server(
            name: 'New server', remote: 'kmyserver', sshHost: 'new.example.com')
      ]);
    });
  });

  group('new site from a template', () {
    const site = NewSite(
      server: _vm,
      name: 'shop',
      domain: 'shop.localhost',
      url: 'https://shop.localhost:8443',
      template: 'symfony-starter',
      parentDir: '/home/me/repos/',
      github: true,
    );

    test('creates it on the server, clones it and makes a GitHub repo',
        () async {
      final runs = <String>[];
      final steps = <CreateStep>[];
      final lines = <String>[];
      final failed = await SiteCreator((exe, args, onOutput,
          {String? workingDirectory}) async {
        runs.add('$exe ${args.join(' ')}');
        onOutput('$exe ok');
        return 0;
      }).create(site, onStep: steps.add, onOutput: lines.add);

      expect(failed, isNull);
      expect(steps, CreateStep.values);
      expect(runs, [
        'ssh -p 2222 root@localhost /usr/local/sbin/site-add shop --domain shop.localhost --template symfony-starter',
        'git clone -o vm ssh://shop@localhost:2222/srv/sites/shop/repo.git /home/me/repos/shop',
        'gh repo create shop --private --source /home/me/repos/shop --remote origin --push',
      ]);
      // site-add's output is shown like a server's output (its deploy steps, errors).
      expect(lines.first, 'remote: ssh ok');
    });

    test('stops at the first failing step', () async {
      final runs = <String>[];
      final failed = await SiteCreator((exe, args, onOutput,
          {String? workingDirectory}) async {
        runs.add(exe);
        return exe == 'git' ? 128 : 0;
      }).create(site, onStep: (_) {}, onOutput: (_) {});

      expect(failed, 'Cloning the site failed');
      expect(runs, ['ssh', 'git']);
    });

    test('checks name, domain and template', () {
      expect(NewSite.nameError('shop-2'), isNull);
      expect(NewSite.nameError('Shop'), isNotNull);
      expect(NewSite.nameError('s'), isNotNull);
      expect(NewSite.domainError('shop.example.com'), isNull);
      expect(NewSite.domainError('shop'), isNotNull);
      expect(NewSite.templateError('symfony-starter'), isNull);
      expect(NewSite.templateError('https://github.com/symfony/demo.git#main'),
          isNull);
      expect(NewSite.templateError('https://x.git; rm -rf /'), isNotNull);
      expect(NewSite.templateError('git@github.com:a/b.git'), isNotNull);
    });

    testWidgets('the dialog creates the site and adds it to the list',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final runs = <String>[];
      final sites = <Site>[];
      await tester.pumpWidget(MyApp(
        preferences: _Memory([_plesk, _vm], 'Plesk'),
        services: AppServices(
          settings: _Sites(sites),
          fetchInfo: (_) async =>
              const SystemInfo(sfVersion: '8.1.11', phpVersion: '8.5.13'),
          checkRepo: (_, __) async =>
              const RepoStatus(branch: 'master', uncommitted: 0),
          readLocal: (_) async => throw Exception('none'),
          openInTargets: const [],
          pathExists: (_) async => false,
          run: (exe, args, onOutput, {String? workingDirectory}) async {
            runs.add(exe);
            onOutput('done');
            return 0;
          },
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('New site from a template'));
      await tester.pumpAndSettle();
      expect(find.text('New site from a template'), findsOneWidget);

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Name'), 'shop');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Domain'), 'shop.localhost');
      // The address follows the domain, with the server's port for the sites.
      expect(find.text('https://shop.localhost:8443'), findsOneWidget);
      await tester.tap(find.text('Create a private GitHub repository'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();

      expect(runs, ['ssh', 'git']);
      expect(find.text('shop is ready'), findsOneWidget);
      await tester.tap(find.text('Add to the list'));
      await tester.pumpAndSettle();

      expect(sites.single.mainTarget.url, 'https://shop.localhost:8443');
      expect(sites.single.mainTarget.server, 'Test VM');
      expect(sites.single.repoPath, endsWith('/repos/shop'));
    });
  });

  test('local certificates are accepted for loopback addresses only', () {
    for (final host in ['localhost', 'shop.localhost', '127.0.0.1', '::1']) {
      expect(AppServices.isLocalHost(host), isTrue, reason: host);
    }
    for (final host in [
      'example.com',
      'localhost.example.com',
      'shop.localhost.evil.com',
      '10.0.0.1',
      '1270.0.0.1',
    ]) {
      expect(AppServices.isLocalHost(host), isFalse, reason: host);
    }
  });
}
