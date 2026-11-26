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
import 'package:kuku_project_checker/widgets/site_dialog.dart';

import 'helpers.dart';

/// Settings in memory: what the app saves can be checked.
class _MemorySettings extends Settings {
  List<Site> sites;
  int writes = 0;

  _MemorySettings(this.sites);

  @override
  Future<List<Site>> readSettings() async => [...sites];

  @override
  Future<File> writeSettings(List<Site> s) async {
    sites = [...s];
    writes++;
    return File('/dev/null');
  }
}

class _Light extends Preferences {
  @override
  Future<ThemeMode> readThemeMode() async => ThemeMode.light;

  @override
  Future<void> writeThemeMode(ThemeMode mode) async {}
}

const _shop = Site(
    name: 'Shop', url: 'https://shop.example.com', repoPath: '/repos/shop');
const _blog = Site(name: 'Blog', url: 'https://blog.example.com');

void main() {
  late _MemorySettings settings;
  late List<String> fetched;

  /// The deploy remote choice of every repository check, in order.
  late List<String> checkedWith;

  /// What the folder chooser returns, and the folders it was opened in.
  String? picked;
  final pickedFrom = <String?>[];

  Future<void> showApp(WidgetTester tester, List<Site> sites,
      {double width = 1000}) async {
    tester.view.physicalSize = Size(width, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    settings = _MemorySettings(sites);
    fetched = [];
    checkedWith = [];
    await tester.pumpWidget(MyApp(
      preferences: _Light(),
      services: AppServices(
        settings: settings,
        fetchInfo: (url) async {
          fetched.add(url);
          return const SystemInfo(sfVersion: '8.1.11', phpVersion: '8.5.12');
        },
        checkRepo: (_, deployRemote) async {
          checkedWith.add(deployRemote);
          return const RepoStatus(
              branch: 'master', uncommitted: 0, unpushed: 0);
        },
        listRemotes: (_) async => const [
          ('origin', 'git@github.com:me/shop.git'),
          ('production', 'shop@server:~/git/shop.git'),
          ('staging', 'shop@staging:~/git/shop.git'),
        ],
        readLocal: (_) async => const LocalVersions(),
        openInTargets: const [],
        pickFolder: (initial) async {
          pickedFrom.add(initial);
          return picked;
        },
      ),
    ));
    await tester.pumpAndSettle();
  }

  TextField field(WidgetTester tester, String label) =>
      tester.widget<TextField>(find.widgetWithText(TextField, label));

  testWidgets('choose the deploy remote of a site', (tester) async {
    await showApp(tester, [_shop]);
    expect(checkedWith, [Site.autoDeploy]);

    await tapRowButton(tester, 'Shop', 'Edit…');

    // Automatic shows what it would pick; every remote is offered.
    expect(find.text('Automatic (production)'), findsOneWidget);
    await tester.tap(find.text('Automatic (production)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('staging  ·  shop@staging'), findsOneWidget);
    expect(find.text('No deploys'), findsOneWidget);

    await tester.tap(find.textContaining('staging  ·  shop@staging').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(settings.sites.single.deployRemote, 'staging');
    expect(checkedWith, [Site.autoDeploy, 'staging'],
        reason: 'The site is checked again with the chosen remote');
  });

  testWidgets('choose the repository folder', (tester) async {
    final home = Platform.environment['HOME']!;
    await showApp(tester, [_blog]);

    await tapRowButton(tester, 'Blog', 'Edit…');

    // Cancelled: the field stays as it is.
    picked = null;
    await tester.tap(find.byTooltip('Choose the folder'));
    await tester.pumpAndSettle();
    expect(field(tester, 'Local repository').controller!.text, '');

    // A folder in the home folder is shown with ~, and the deploy remote appears.
    picked = '$home/repos/blog';
    await tester.tap(find.byTooltip('Choose the folder'));
    await tester.pumpAndSettle();
    expect(field(tester, 'Local repository').controller!.text, '~/repos/blog');
    expect(find.text('Deploy remote'), findsOneWidget);

    // Other folders stay as they are.
    picked = '/srv/blog';
    await tester.tap(find.byTooltip('Choose the folder'));
    await tester.pumpAndSettle();
    expect(field(tester, 'Local repository').controller!.text, '/srv/blog');

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(settings.sites.single.repoPath, '/srv/blog');
    picked = null;
  });

  test('writes the home folder as ~', () {
    final home = Platform.environment['HOME']!;

    expect(collapseHome('$home/repos/shop'), '~/repos/shop');
    expect(collapseHome(home), '~');
    expect(collapseHome('${home}x/shop'), '${home}x/shop');
    expect(collapseHome('/srv/shop'), '/srv/shop');
  });

  testWidgets('no deploy remote choice without a repository', (tester) async {
    await showApp(tester, [_blog]);

    await tapRowButton(tester, 'Blog', 'Edit…');

    expect(find.text('Deploy remote'), findsNothing);
    await tester.enterText(
        find.widgetWithText(TextField, 'Local repository'), '~/repos/blog');
    await tester.pumpAndSettle();
    expect(find.text('Deploy remote'), findsOneWidget);
  });

  testWidgets('an empty list offers to add a site', (tester) async {
    await showApp(tester, []);

    expect(find.text('No projects yet'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Add site'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Shop');
    await tester.enterText(
        find.widgetWithText(TextField, 'Site URL'), 'https://shop.example.com');
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    expect(find.text('Shop'), findsOneWidget);
    expect(settings.sites.single.url, 'https://shop.example.com');
    expect(fetched, ['https://shop.example.com']);
  });

  testWidgets('a new site needs a valid address', (tester) async {
    await showApp(tester, [_shop]);

    await tester.tap(find.byTooltip('Add site'));
    await tester.pumpAndSettle();
    expect(field(tester, 'Site URL').controller!.text, 'https://');

    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
    expect(find.text('Enter the address of the site'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextField, 'Site URL'), 'shop.example.com');
    await tester.pump();
    expect(find.text('Use a full address, like https://shop.example.com'),
        findsOneWidget);
    expect(settings.writes, 0);

    // Cancel adds nothing.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(settings.sites, hasLength(1));
  });

  testWidgets('edit a site and reload only that one', (tester) async {
    await showApp(tester, [_shop, _blog]);
    expect(fetched, hasLength(2));

    await tapRowButton(tester, 'Blog', 'Edit…');

    expect(find.text('Edit site'), findsOneWidget);
    expect(field(tester, 'Name').controller!.text, 'Blog');
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'News');
    await tester.enterText(
        find.widgetWithText(TextField, 'Local repository'), '~/repos/news');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('News'), findsOneWidget);
    expect(find.text('Blog'), findsNothing);
    expect(settings.sites[1].name, 'News');
    expect(settings.sites[1].repoPath, '~/repos/news');
    expect(fetched, hasLength(3), reason: 'Only the edited site is read again');
    // The repository status is in the expanded details.
    await expandRow(tester, 'News');
    expect(find.textContaining('master'), findsOneWidget);
  });

  testWidgets('remove a site and bring it back', (tester) async {
    await showApp(tester, [_shop, _blog]);

    await tapRowButton(tester, 'Shop', 'Remove', expand: true);

    expect(find.text('Shop'), findsNothing);
    expect(settings.sites.map((s) => s.name), ['Blog']);
    expect(find.text('Removed Shop'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(find.text('Shop'), findsOneWidget);
    expect(settings.sites.map((s) => s.name), ['Shop', 'Blog']);
  });

  testWidgets('drag a site to another place', (tester) async {
    await showApp(tester, [_shop, _blog]);

    final handle = find.byIcon(Icons.drag_indicator);
    expect(handle, findsNWidgets(2));

    // Drag Blog's handle above Shop.
    final drag = await tester.startGesture(tester.getCenter(handle.last));
    await tester.pump(const Duration(milliseconds: 100));
    await drag.moveBy(const Offset(0, -150));
    await tester.pump();
    await drag.up();
    await tester.pumpAndSettle();

    expect(settings.sites.map((s) => s.name), ['Blog', 'Shop']);
    expect(tester.getTopLeft(find.text('Blog')).dy,
        lessThan(tester.getTopLeft(find.text('Shop')).dy));
  });

  testWidgets('buttons edit the site and the menu opens it', (tester) async {
    await showApp(tester, [_shop]);

    expect(
        find.descendant(
            of: projectCard('Shop'), matching: find.byTooltip('Edit…')),
        findsOneWidget);
    expect(
        find.descendant(
            of: projectCard('Shop'), matching: find.byTooltip('Open in…')),
        findsOneWidget);

    await openOpenInMenu(tester, 'Shop');
    expect(find.text('Open in browser'), findsOneWidget);
    expect(find.text('Remove'), findsNothing);
  });

  test('Site.urlError', () {
    expect(Site.urlError('https://shop.example.com'), isNull);
    expect(Site.urlError('  http://127.0.0.1:8000 '), isNull);
    expect(Site.urlError(''), isNotNull);
    expect(Site.urlError('https://'), isNotNull);
    expect(Site.urlError('ftp://shop.example.com'), isNotNull);
  });
}
