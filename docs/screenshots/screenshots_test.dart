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
import 'package:kuku_project_checker/support/settings.dart';
import 'package:kuku_project_checker/support/site.dart';
import 'package:kuku_project_checker/support/site_info.dart';

const sites = [
  Site(name: 'Shop', url: 'https://shop.example.com', repoPath: '~/repos/shop'),
  Site(name: 'Blog', url: 'https://blog.example.com', repoPath: '~/repos/blog'),
  Site(url: 'https://docs.example.com'),
  Site(
      name: 'Shop (local)',
      url: 'https://127.0.0.1:8000',
      repoPath: '~/repos/shop-dev'),
];

final versions = {
  'https://shop.example.com':
      const SystemInfo(sfVersion: '8.1.11', phpVersion: '8.5.12'),
  'https://blog.example.com':
      const SystemInfo(sfVersion: '7.4.23', phpVersion: '8.4.15'),
  'https://docs.example.com':
      const SystemInfo(sfVersion: '8.1.11', phpVersion: '8.5.12'),
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
      fetchInfo: (url) async =>
          versions[url] ?? (throw const SocketException('Connection refused')),
      checkRepo: (path) async => statuses[path]!,
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

  Future<void> showApp(WidgetTester tester, ThemeMode mode) async {
    // The app's default window: 1000 wide.
    tester.view.physicalSize = const Size(2000, 1400);
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
        await showApp(tester, mode);
        await snap('01_sites');
      });

      screenshotTest('open in menu', (tester) async {
        await showApp(tester, mode);
        await tester.tap(find.byTooltip('Open in …').first);
        await tester.pumpAndSettle();
        await snap('02_open_in_menu');
      });

      screenshotTest('changes', (tester) async {
        await showApp(tester, mode);
        await tester.tap(find.text('Shop'));
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

        await tester.tap(find.widgetWithText(FilledButton, 'Deploy'));
        await tester.pumpAndSettle();
        await snap('07_deploy_done');
      });

      screenshotTest('settings', (tester) async {
        await showApp(tester, mode);
        await tester.tap(find.byTooltip('Settings'));
        await tester.pumpAndSettle();
        // One site open, the others collapsed.
        await tester.tap(find.byTooltip('Expand').first);
        await tester.pumpAndSettle();
        await snap('05_settings');
      });
    });
  }
}
