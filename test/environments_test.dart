import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuku_project_checker/main.dart';
import 'package:kuku_project_checker/support/app_services.dart';
import 'package:kuku_project_checker/support/local_versions.dart';
import 'package:kuku_project_checker/support/preferences.dart';
import 'package:kuku_project_checker/support/repo_status.dart';
import 'package:kuku_project_checker/support/server.dart';
import 'package:kuku_project_checker/support/server_health.dart';
import 'package:kuku_project_checker/support/settings.dart';
import 'package:kuku_project_checker/support/site.dart';
import 'package:kuku_project_checker/support/site_info.dart';

import 'helpers.dart';

const plesk = Server(name: 'Plesk', remote: 'elkuku.dev');
const vm1 = Server(
  name: 'VM 1',
  remote: 'vm1',
  sshHost: 'vm1.example.com',
  sshPort: 2222,
  sitePort: 8443,
  domainSuffix: 'vm1.localhost',
);
const vm2 = Server(
  name: 'VM 2',
  remote: 'vm2',
  sshHost: 'vm2.example.com',
  sshPort: 2222,
  sitePort: 8443,
  domainSuffix: 'vm2.localhost',
);

class _MemorySettings extends Settings {
  List<Site> sites;
  int writes = 0;

  _MemorySettings(this.sites);

  @override
  Future<List<Site>> readSettings() async => [...sites];

  @override
  Future<File> writeSettings(List<Site> saved) async {
    sites = [...saved];
    writes++;
    return File('/dev/null');
  }
}

class _Preferences extends Preferences {
  final List<Server> servers;
  final String active;

  _Preferences(this.servers, this.active);

  @override
  Future<ThemeMode> readThemeMode() async => ThemeMode.light;

  @override
  Future<void> writeThemeMode(ThemeMode mode) async {}

  @override
  Future<(List<Server>, String)> readServers() async => (servers, active);

  @override
  Future<void> writeServers(List<Server> servers, String active) async {}
}

Map<String, dynamic> _health(String host, String domain) => {
      'schema': 1,
      'generatedAt': '2026-11-26T09:00:00Z',
      'host': host,
      'problems': 0,
      'system': {
        'os': 'Debian 13.8',
        'kernel': '6.12',
        'uptime': 'up 1:42',
        'rebootRequired': false,
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
        'bannedTotal': 0,
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
          'name': 'shop',
          'domain': domain,
          'http': 200,
          'certificate': {'days': 12, 'issuer': 'Caddy Local Authority'},
          'release': '20261125-1412',
          'revision': '33abb4d',
          'deploy': {'state': 'ok', 'when': '2026-11-26 08:45'},
          'critical24h': 0,
          'lastCritical': null,
          'problems': [],
        },
      ],
    };

AppServices _services(
  Settings settings, {
  Future<ServerHealth> Function(Server)? health,
}) =>
    AppServices(
      settings: settings,
      fetchInfo: (_) async =>
          const SystemInfo(sfVersion: '8.1.11', phpVersion: '8.5.13'),
      checkRepo: (_, __) async =>
          const RepoStatus(branch: 'master', uncommitted: 0),
      readLocal: (_) async => const LocalVersions(),
      openInTargets: const [],
      fetchServerHealth:
          health ?? (_) async => ServerHealth.fromJson(_health('none', 'none')),
    );

void main() {
  group('project environments', () {
    test('save and read targets including Plesk and KMyServer', () {
      const pleskTarget = SiteTarget(
        name: 'plesk',
        url: 'https://shop.example.com',
        deployRemote: 'elkuku.dev',
      );
      const vmTarget = SiteTarget(
        name: 'vm',
        server: 'VM 1',
        url: 'https://shop.vm1.localhost:8443',
        deployRemote: 'vm1',
      );
      final site = Site(
        name: 'Shop',
        targets: const [pleskTarget, vmTarget],
      );

      final json = site.toJson();
      expect(json['targets'], hasLength(2));
      final restored = Site.fromJson(json);
      expect(restored.targets, [pleskTarget, vmTarget]);
      expect(restored.targets.last.server, 'VM 1');
      expect(restored.targets.last.domain, 'shop.vm1.localhost');
    });

    test('old settings are migrated into the first environment', () {
      final site = Site.fromJson({
        'name': 'Shop',
        'url': 'https://shop.example.com',
        'deployRemote': 'production',
      });
      expect(site.targets, [
        const SiteTarget(
          name: 'Shop',
          url: 'https://shop.example.com',
          deployRemote: 'production',
        ),
      ]);
      final json = site.toJson();
      expect(json, isNot(contains('url')));
      expect(json, isNot(contains('deployRemote')));
      expect(Site.fromJson(json).targets, site.targets);
    });

    test('a server domain suffix is saved only when set', () {
      final json = vm1.toJson();
      expect(json['domainSuffix'], 'vm1.localhost');
      expect(Server.fromJson(json), vm1);
      expect(vm1.siteDomain('shop'), 'shop.vm1.localhost');
      expect(plesk.toJson(), isNot(contains('domainSuffix')));
      expect(plesk.siteDomain('shop'), 'shop');
    });

    testWidgets('Environments… adds a Plesk target and saves it',
        (tester) async {
      final settings = _MemorySettings([
        legacySite(name: 'Shop', url: 'https://shop.example.com'),
      ]);
      await tester.pumpWidget(MyApp(
        preferences: _Preferences([plesk, vm1], ''),
        services: _services(settings),
      ));
      await tester.pumpAndSettle();

      await tapRowButton(tester, 'Shop', 'Environments…');
      expect(find.text('Project environments'), findsOneWidget);

      await tester.tap(find.text('Add environment'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Name'), 'plesk');
      await tester.tap(find.widgetWithText(
          DropdownButtonFormField<String>, 'No server (local/own remote)'));
      await tester.pumpAndSettle();
      // The overlay item is repainted while the menu closes, so Flutter's hit-test
      // warning is a false positive here; the selection does go through.
      await tester.tap(find.widgetWithText(DropdownMenuItem<String>, 'Plesk'),
          warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Address'),
          'https://shop.example.com');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Deploy remote'), 'elkuku.dev');
      await tester.tap(find.widgetWithText(FilledButton, 'OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(settings.writes, 1);
      // The legacy address stays editable, and the new Plesk environment is added.
      expect(settings.sites.single.targets, [
        const SiteTarget(name: 'Shop', url: 'https://shop.example.com'),
        const SiteTarget(
          name: 'plesk',
          server: 'Plesk',
          url: 'https://shop.example.com',
          deployRemote: 'elkuku.dev',
        ),
      ]);

      await openOpenInMenu(tester, 'Shop');
      expect(find.text('Open plesk (shop.example.com)'), findsOneWidget);
    });

    testWidgets('deploy-to is only offered for the selected server',
        (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final settings = _MemorySettings([
        legacySite(
            name: 'Shop',
            url: 'https://shop.example.com',
            repoPath: '~/repos/shop'),
      ]);
      await tester.pumpWidget(MyApp(
        preferences: _Preferences([vm1, vm2], 'VM 1'),
        services: _services(settings, health: (server) async {
          return ServerHealth.fromJson(
              _health('test-${server.name}', 'shop.${server.domainSuffix}'));
        }),
      ));
      await tester.pumpAndSettle();

      await expandRow(tester, 'Shop');
      expect(find.byTooltip('Deploy to VM 1…'), findsOneWidget);
      expect(find.byTooltip('Deploy to VM 2…'), findsNothing);
    });

    testWidgets('no deploy-to when the site is on the selected server',
        (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final settings = _MemorySettings([
        Site(
          name: 'Shop',
          repoPath: '~/repos/shop',
          targets: [
            const SiteTarget(
              name: 'vm1',
              server: 'VM 1',
              url: 'https://shop.vm1.localhost:8443',
            ),
          ],
        ),
      ]);
      await tester.pumpWidget(MyApp(
        preferences: _Preferences([vm1, vm2], 'VM 1'),
        services: _services(settings, health: (server) async {
          return ServerHealth.fromJson(
              _health('test-${server.name}', 'shop.${server.domainSuffix}'));
        }),
      ));
      await tester.pumpAndSettle();

      await expandRow(tester, 'Shop');
      expect(find.byTooltip('Deploy to VM 1…'), findsNothing);
      expect(find.byTooltip('Deploy to VM 2…'), findsNothing);
    });

    testWidgets('one project shows every server environment', (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final fetched = <String>[];
      final settings = _MemorySettings([
        Site(
          name: 'Shop',
          targets: [
            SiteTarget(
                name: 'vm1',
                server: 'VM 1',
                url: 'https://shop.vm1.localhost:8443',
                deployRemote: 'vm1'),
            SiteTarget(
                name: 'vm2',
                server: 'VM 2',
                url: 'https://shop.vm2.localhost:8443',
                deployRemote: 'vm2'),
          ],
        ),
      ]);
      await tester.pumpWidget(MyApp(
        preferences: _Preferences([vm1, vm2], 'VM 1'),
        services: _services(settings, health: (server) async {
          fetched.add(server.name);
          return ServerHealth.fromJson(
              _health('test-${server.name}', 'shop.${server.domainSuffix}'));
        }),
      ));
      await tester.pumpAndSettle();

      expect(fetched, ['VM 1', 'VM 2']);
      // Both reports are on the same compact row, labelled by server.
      expect(find.text('VM 1'), findsWidgets);
      expect(find.text('VM 2'), findsWidgets);
      expect(find.textContaining('not in the projects'), findsNothing);

      await expandRow(tester, 'Shop');
      expect(find.text('Releases on VM 2…'), findsOneWidget);
      expect(find.text('Roll back on VM 2…'), findsOneWidget);
      expect(find.text('Deploy log on VM 1…'), findsOneWidget);
      expect(find.text('Deploy log on VM 2…'), findsOneWidget);

      await openOpenInMenu(tester, 'Shop');
      // The first environment is the main address: Open in browser covers it.
      expect(find.text('Open in browser'), findsOneWidget);
      expect(find.text('Open vm1 (shop.vm1.localhost)'), findsNothing);
      expect(find.text('Open vm2 (shop.vm2.localhost)'), findsOneWidget);
    });
  });
}
