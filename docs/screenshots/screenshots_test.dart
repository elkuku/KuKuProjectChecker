// Renders the screenshots for the documentation from sample data, in both themes.
//
// Regenerate them after changing the app:
//   flutter test --update-goldens docs/screenshots/screenshots_test.dart
//
// Without --update-goldens the test compares against the existing images, which only
// matches on the same machine and fonts, so this file is not part of `flutter test`.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuku_project_checker/main.dart';
import 'package:kuku_project_checker/support/app_services.dart';
import 'package:kuku_project_checker/support/open_in.dart';
import 'package:kuku_project_checker/support/preferences.dart';
import 'package:kuku_project_checker/support/repo_changes.dart';
import 'package:kuku_project_checker/support/repo_status.dart';
import 'package:kuku_project_checker/support/server.dart';
import 'package:kuku_project_checker/support/server_health.dart';
import 'package:kuku_project_checker/support/settings.dart';
import 'package:kuku_project_checker/support/site.dart';
import 'package:kuku_project_checker/support/site_info.dart';

/// A sample project with one environment on the test VM. The project stores only
/// a subdomain; the server's base URL makes the full address.
Site sampleSite(
  String name,
  String subdomain, {
  String repoPath = '',
  String deployRemote = '',
  String devUrl = '',
}) =>
    Site(
      name: name,
      repoPath: repoPath,
      githubRepo: 'https://github.com/example/$subdomain',
      devUrl: devUrl,
      targets: [
        SiteTarget(
          name: 'vm',
          server: 'Test VM',
          subdomain: subdomain,
          deployRemote: deployRemote,
        )
      ],
    );

final sites = [
  sampleSite('Shop', 'shop',
      repoPath: '~/repos/shop',
      deployRemote: 'production',
      devUrl: 'https://dev.shop.example.com'),
  sampleSite('Blog', 'blog',
      repoPath: '~/repos/blog', deployRemote: 'production'),
  sampleSite('Docs', 'docs'),
  // No environment on the active server: only its git status and local versions show.
  Site(
    name: 'Shop (local)',
    repoPath: '~/repos/shop-dev',
    githubRepo: 'https://github.com/example/shop-dev',
    targets: [
      const SiteTarget(
          name: 'local', url: 'https://127.0.0.1:8000', deployRemote: '-')
    ],
  ),
  // Matches the site in sampleHealth, so the server-side badges show in the screenshot.
  sampleSite('Starter', 'starter'),
];

final versions = {
  'https://shop.localhost:8443':
      const SystemInfo(sfVersion: '8.1.11', phpVersion: '8.5.12'),
  'https://blog.localhost:8443':
      const SystemInfo(sfVersion: '7.4.23', phpVersion: '8.4.15'),
  'https://docs.localhost:8443':
      const SystemInfo(sfVersion: '8.1.11', phpVersion: '8.5.12'),
  'https://starter.localhost:8443':
      const SystemInfo(sfVersion: '8.1.11', phpVersion: '8.5.13'),
  // The dev site deployed itself 12 minutes ago, after the newest commit on GitHub.
  'https://dev.shop.example.com': SystemInfo(
      sfVersion: '8.1.11',
      phpVersion: '8.5.12',
      lastDeploy: LastDeploy(
          at: DateTime.now().subtract(const Duration(minutes: 12)),
          status: 'ok')),
};

final statuses = {
  '~/repos/shop': const RepoStatus(
      branch: 'master',
      uncommitted: 3,
      unpushed: 1,
      deployRemote: 'production',
      undeployed: 2),
  '~/repos/blog': const RepoStatus(
      branch: 'master',
      uncommitted: 0,
      unpushed: 0,
      deployRemote: 'production',
      undeployed: 0),
  '~/repos/shop-dev':
      const RepoStatus(branch: 'feature/checkout', uncommitted: 1),
};

const sampleServers = [
  Server(
    name: 'Test VM',
    remote: 'vm',
    sshHost: 'localhost',
    sshPort: 2222,
    baseUrl: 'https://localhost:8443',
  ),
];

final sampleHealth = ServerHealth.fromJson({
  'schema': 1,
  'generatedAt': '2026-11-26T09:00:00Z',
  'host': 'test-vm',
  'problems': 3,
  'system': {
    'os': 'Debian 13.8, kernel 6.12.57+deb13-amd64',
    'kernel': '6.12.57+deb13-amd64',
    'uptime': ' 09:00:00 up  1:42,  1 user,  load average: 0.12, 0.08, 0.03',
    'rebootRequired': false,
    'rebootPackages': [],
  },
  'services': [
    {'name': 'caddy', 'state': 'active', 'ok': true},
    {'name': 'php8.5-fpm', 'state': 'active', 'ok': true},
    {'name': 'postgresql', 'state': 'active', 'ok': true},
    {'name': 'nftables', 'state': 'active', 'ok': true},
    {'name': 'fail2ban', 'state': 'active', 'ok': true},
    {'name': 'ssh', 'state': 'active', 'ok': true},
    {'name': 'server-backup.timer', 'state': 'active', 'ok': true},
    {'name': 'unattended-upgrades', 'state': 'active', 'ok': true},
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
  'mail': {'configured': true, 'ok': false, 'last': ''},
  'sites': [
    {
      'name': 'starter',
      'domain': 'starter.localhost',
      'http': 200,
      'certificate': {'days': 0, 'issuer': 'Caddy Local Authority'},
      'release': '20261125-1412',
      'revision': '33abb4d',
      'deploy': {'state': 'ok', 'when': '2026-11-25 14:12'},
      'critical24h': 0,
      'lastCritical': null,
      'problems': [],
    },
    // No project in the list matches this one: it is a temporary entry.
    {
      'name': 'pgtest',
      'domain': 'pgtest.localhost',
      'http': 0,
      'certificate': {'days': 0, 'issuer': 'Caddy Local Authority'},
      'release': '20261124-0915',
      'revision': 'a1b2c3d',
      'deploy': {'state': 'failed', 'when': '2026-11-24 09:15'},
      'critical24h': 1,
      'lastCritical': 'Database connection failed',
      'problems': ['http 000', 'last deploy failed'],
    },
  ],
});

class SampleSettings extends Settings {
  @override
  Future<List<Site>> readSettings() async => sites;

  // The settings save on their own; never touch the real settings file.
  @override
  Future<File> writeSettings(List<Site> sites) async => File('/dev/null');
}

class SamplePreferences extends Preferences {
  final ThemeMode mode;

  SamplePreferences(this.mode);

  @override
  Future<ThemeMode> readThemeMode() async => mode;

  @override
  Future<void> writeThemeMode(ThemeMode mode) async {}

  @override
  Future<(List<Server>, String)> readServers() async =>
      (sampleServers, 'Test VM');
}

class SampleChanges extends RepoChanges {
  // A demo home folder, so the screenshots don't show the real one. The app passes
  // the path with ~ already expanded.
  SampleChanges(String repoPath)
      : super(repoPath.replaceFirst(
            RegExp(
                '^(~|${RegExp.escape(Platform.environment['HOME'] ?? '~')})'),
            '/home/demo'));

  @override
  Future<List<ChangedFile>> files() async => const [
        ChangedFile(' M', 'src/Controller/CartController.php'),
        ChangedFile('A ', 'migrations/Version20261118120000.php'),
        ChangedFile('??', 'templates/cart/summary.html.twig'),
      ];

  @override
  Future<String> diff(ChangedFile file) async => '''
diff --git a/src/Controller/CartController.php b/src/Controller/CartController.php
index 3f2a9c1..8d41b0e 100644
--- a/src/Controller/CartController.php
+++ b/src/Controller/CartController.php
@@ -24,11 +24,15 @@ final class CartController extends AbstractController
     #[Route('/cart', name: 'cart')]
     public function index(CartService \$cart): Response
     {
-        return \$this->render('cart/index.html.twig', [
-            'items' => \$cart->items(),
-        ]);
+        \$items = \$cart->items();
+
+        return \$this->render('cart/index.html.twig', [
+            'items' => \$items,
+            'total' => \$cart->total(\$items),
+            'shipping' => \$cart->shippingFor(\$items),
+        ]);
     }
 
     #[Route('/cart/add/{id}', name: 'cart_add', methods: ['POST'])]
''';
}

AppServices sampleServices() => AppServices(
      settings: SampleSettings(),
      fetchServerHealth: (_) async => sampleHealth,
      fetchInfo: (url) async =>
          versions[url] ?? (throw const SocketException('Connection refused')),
      checkRepo: (path, _) async => statuses[path]!,
      // Like a typical project: the code on GitHub, the deploys to a Plesk repository.
      upstreamTime: (_) async =>
          DateTime.now().subtract(const Duration(minutes: 15)),
      listRemotes: (_) async => const [
        ('origin', 'git@github.com:example/shop.git'),
        ('production', 'shop@server.example.com:~/git/shop.git'),
      ],
      repoChanges: SampleChanges.new,
      push: (repoPath, remote, branch, onOutput) async {
        // Like a push to a Plesk repository: ssh's notice, curl's progress table
        // from the deploy hook, then the result.
        for (final line in [
          '** WARNING: connection is not using a post-quantum key exchange algorithm.',
          '** This session may be vulnerable to "store now, decrypt later" attacks.',
          '** The server may need to be upgraded. See https://openssh.com/pq.html',
          'Enumerating objects: 23, done.',
          'Writing objects: 100% (14/14), 2.31 KiB | 2.31 MiB/s, done.',
          'Total 14 (delta 9), reused 0 (delta 0), pack-reused 0',
          'remote:   % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current',
          'remote:                                  Dload  Upload   Total   Spent    Left  Speed',
          'remote:   0     0    0     0    0     0      0      0 --:--:-- --:--:-- --:--:--     0',
          'To shop.example.com:~/git/shop.git',
          '   4c1d2e9..8f7a6b5  master -> master',
        ]) {
          onOutput(line);
        }
        return 0;
      },
      openInTargets: [
        for (final target in OpenInTarget.all)
          (target, '/usr/bin/${target.commands.first}'),
      ],
    );

Future<void> loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final file in files) {
    loader.addFont(
        File(file).readAsBytes().then((bytes) => ByteData.sublistView(bytes)));
  }
  await loader.load();
}

void main() {
  setUpAll(() async {
    final fonts =
        '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
    await loadFont('Roboto', [
      for (final weight in ['Regular', 'Medium', 'Bold'])
        '$fonts/Roboto-$weight.ttf',
    ]);
    await loadFont('MaterialIcons', ['$fonts/MaterialIcons-Regular.otf']);

    // The app's monospace font (see monoTextStyle). fc-match can't find it here:
    // flutter test points fontconfig at its own fonts.
    final mono = [
      '/usr/share/fonts/noto/NotoSansMono-Regular.ttf',
      '/usr/share/fonts/truetype/noto/NotoSansMono-Regular.ttf',
      '/usr/share/fonts/TTF/DejaVuSansMono.ttf',
      '/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf',
    ].firstWhere((path) => File(path).existsSync(),
        orElse: () => throw StateError(
            'No monospace font found; install Noto Sans Mono or DejaVu Sans Mono'));
    await loadFont('Noto Sans Mono', [mono]);
  });

  Future<void> showApp(WidgetTester tester, ThemeMode mode,
      {double height = 1600}) async {
    // The app's default window: 1200 wide, above its 1100 px minimum.
    tester.view.physicalSize = Size(2400, height);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MyApp(
        preferences: SamplePreferences(mode), services: sampleServices()));
    await tester.pumpAndSettle();
  }

  /// A test with real shadows (tests draw outlines by default); the setting has to be
  /// restored within the test.
  void screenshotTest(String description, WidgetTesterCallback body) {
    testWidgets(description, (tester) async {
      debugDisableShadows = false;
      try {
        await body(tester);
      } finally {
        debugDisableShadows = true;
      }
    });
  }

  for (final mode in [ThemeMode.dark, ThemeMode.light]) {
    // Each screenshot in both themes, e.g. 01_sites-dark.png and 01_sites-light.png;
    // the docs show the one matching the reader's theme.
    Future<void> snap(String name) => expectLater(
        find.byType(MaterialApp), matchesGoldenFile('$name-${mode.name}.png'));

    group(mode.name, () {
      screenshotTest('site list', (tester) async {
        // Taller so the temporary server-only site at the end is visible too.
        await showApp(tester, mode, height: 3200);
        await snap('01_sites');
      });

      screenshotTest('open in menu', (tester) async {
        await showApp(tester, mode);
        await tester.tap(find.byTooltip('Open in…').first);
        await tester.pumpAndSettle();
        await snap('02_open_in_menu');
      });

      screenshotTest('expanded row', (tester) async {
        await showApp(tester, mode, height: 2200);
        // The first row (Shop) collapsed; then its on-demand details.
        await snap('09_compact_rows');
        await tester.tap(find.byTooltip('Show details').first);
        await tester.pumpAndSettle();
        await snap('10_expanded_row');
      });

      screenshotTest('environments', (tester) async {
        await showApp(tester, mode);
        await tester.tap(find.byTooltip('Environments…').first);
        await tester.pumpAndSettle();
        await snap('11_environments');
      });

      screenshotTest('changes', (tester) async {
        await showApp(tester, mode);
        await tester.tap(find.byTooltip('Show the 3 uncommitted files'));
        await tester.pumpAndSettle();
        await snap('03_changes');

        await tester.tap(find.text('src/Controller/CartController.php'));
        await tester.pumpAndSettle();
        await snap('04_diff');
      });

      screenshotTest('deploy', (tester) async {
        await showApp(tester, mode);
        await tester.tap(find.byTooltip('Deploy 2 commits to production'));
        await tester.pumpAndSettle();
        await snap('06_deploy_confirm');

        await tester.tap(find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Deploy'),
        ));
        await tester.pumpAndSettle();
        await snap('07_deploy_done');
      });

      screenshotTest('edit site', (tester) async {
        await showApp(tester, mode);
        await tester.tap(find.byTooltip('Edit…').first);
        await tester.pumpAndSettle();
        await snap('05_edit_site');
      });

      screenshotTest('server status', (tester) async {
        await showApp(tester, mode);
        tester.view.physicalSize = const Size(2400, 2600);
        await tester.pumpAndSettle();
        // The selected server's status is now a panel on the main screen.
        await snap('08_server_status');
      });
    });
  }
}
