import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuku_project_checker/main.dart';
import 'package:kuku_project_checker/support/app_services.dart';
import 'package:kuku_project_checker/support/github_repos.dart';
import 'package:kuku_project_checker/support/local_versions.dart';
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

final _shop = legacySite(
    name: 'Shop', url: 'https://shop.example.com', repoPath: '/repos/shop');
final _blog = legacySite(
    name: 'Blog',
    url: 'https://blog.example.com',
    repoPath: '~/repos/blog');

void main() {
  late _MemorySettings settings;
  late List<String> fetched;

  /// The deploy remote choice of every repository check, in order.
  late List<String> checkedWith;

  /// What the folder chooser returns, and the folders it was opened in.
  String? picked;
  final pickedFrom = <String?>[];

  Future<void> showApp(WidgetTester tester, List<Site> sites,
      {double width = 1000,
      List<GitHubRepo> githubRepos = const [],
      Future<List<GitHubRepo>> Function()? githubLookup}) async {
    tester.view.physicalSize = Size(width, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    settings = _MemorySettings(sites);
    fetched = [];
    checkedWith = [];
    await tester.pumpWidget(MyApp(
      // No server: the cards show git status and local versions only, so fetched
      // stays empty and checkedWith records the repository reloads instead.
      preferences: TestPreferences(),
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
        listGitHubRepos: githubLookup ?? () async => githubRepos,
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

  testWidgets('choose the deploy remote of an environment', (tester) async {
    await showApp(tester, [_shop]);
    expect(checkedWith, isNotEmpty);
    expect(checkedWith.first, SiteTarget.autoDeploy);

    await tapRowButton(tester, 'Shop', 'Environments…');
    await tester.tap(find.byTooltip('Edit Shop'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Deploy remote'), 'staging');
    await tester.tap(find.widgetWithText(FilledButton, 'OK'));
    await tester.pumpAndSettle();
    final before = checkedWith.length;
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(settings.sites.single.mainTarget.deployRemote, 'staging');
    expect(checkedWith.length, before + 1,
        reason: 'Only the edited site is checked again');
    expect(checkedWith.last, 'staging');
  });

  testWidgets('choose the repository folder', (tester) async {
    final home = Platform.environment['HOME']!;
    await showApp(tester, [_blog]);

    await tapRowButton(tester, 'Blog', 'Edit…');

    // Cancelled: the field stays as it is.
    picked = null;
    await tester.tap(find.byTooltip('Choose the folder'));
    await tester.pumpAndSettle();
    expect(field(tester, 'Local repository').controller!.text, '~/repos/blog');

    // A folder in the home folder is shown with ~.
    picked = '$home/repos/blog';
    await tester.tap(find.byTooltip('Choose the folder'));
    await tester.pumpAndSettle();
    expect(field(tester, 'Local repository').controller!.text, '~/repos/blog');

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

  testWidgets('incomplete fields are marked and suggest values', (tester) async {
    final old = legacySite(url: 'https://shop.example.com', incomplete: true);
    await showApp(tester, [old]);

    expect(find.textContaining('Incomplete: display name'), findsOneWidget);
    await tapRowButton(tester, 'shop.example.com', 'Edit…');

    expect(find.text('Enter a display name — suggested: Shop'), findsOneWidget);
    expect(find.text('Enter the local repository folder — suggested: ~/repos/shop'),
        findsOneWidget);
    expect(find.text('Enter the GitHub repository URL'), findsOneWidget);
    expect(find.text('No matching repository found with gh'), findsOneWidget);
    expect(find.byTooltip('Use suggested GitHub repository'), findsNothing);

    await tester.tap(find.byTooltip('Use suggested display name'));
    await tester.tap(find.byTooltip('Use suggested local repository'));
    await tester.pumpAndSettle();

    expect(field(tester, 'Display name').controller!.text, 'Shop');
    expect(field(tester, 'Local repository').controller!.text, '~/repos/shop');

    await tester.enterText(find.widgetWithText(TextField, 'GitHub repository'),
        'https://github.com/elkuku/shop');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(settings.sites.single.isComplete, isTrue);
    expect(find.textContaining('Incomplete:'), findsNothing);
  });

  testWidgets('a similar existing GitHub repo is offered as the suggestion',
      (tester) async {
    final old = legacySite(url: 'https://shop.example.com', incomplete: true);
    await showApp(tester, [old], githubRepos: const [
      GitHubRepo(
          nameWithOwner: 'elkuku/shop-app',
          url: 'https://github.com/elkuku/shop-app'),
    ]);

    await tapRowButton(tester, 'shop.example.com', 'Edit…');

    expect(find.text('Existing repo: elkuku/shop-app'), findsOneWidget);
    expect(
        tester.widget<Text>(find.text('Existing repo: elkuku/shop-app'))
            .style?.color,
        Colors.green.shade700);
    expect(
        find.text('Enter the GitHub repository URL — suggested: '
            'https://github.com/elkuku/shop-app (existing repo)'),
        findsOneWidget);

    await tester.tap(find.byTooltip('Use existing GitHub repository'));
    await tester.pumpAndSettle();

    expect(field(tester, 'GitHub repository').controller!.text,
        'https://github.com/elkuku/shop-app');
    expect(find.text('Existing repo: elkuku/shop-app'), findsOneWidget);
  });

  testWidgets('fuzzy candidates can be chosen and are shown in green',
      (tester) async {
    final old = Site(
      name: '4E Ecuador',
      repoPath: '~/repos/4e-website',
      targets: [
        SiteTarget(name: '4E Ecuador', url: 'https://4e-ecuador.elkuku.dev')
      ],
    );
    await showApp(tester, [old], githubRepos: const [
      GitHubRepo(
          nameWithOwner: '4e-ecuador/website-bot',
          url: 'https://github.com/4e-ecuador/website-bot'),
      GitHubRepo(
          nameWithOwner: '4e-ecuador/website-red',
          url: 'https://github.com/4e-ecuador/website-red'),
    ]);

    await tapRowButton(tester, '4E Ecuador', 'Edit…');

    expect(find.text('Existing repo: 4e-ecuador/website-bot'), findsOneWidget);
    expect(
        tester
            .widget<Text>(find.text('Existing repo: 4e-ecuador/website-bot'))
            .style
            ?.color,
        Colors.green.shade700);
    expect(find.byType(DropdownButton<GitHubRepo>), findsOneWidget);

    await tester.tap(find.byType(DropdownButton<GitHubRepo>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('4e-ecuador/website-red').last);
    await tester.pumpAndSettle();

    expect(find.text('Existing repo: 4e-ecuador/website-red'), findsOneWidget);
    await tester.tap(find.byTooltip('Use existing GitHub repository'));
    await tester.pumpAndSettle();

    expect(field(tester, 'GitHub repository').controller!.text,
        'https://github.com/4e-ecuador/website-red');
  });

  testWidgets('a running gh lookup shows a searching state', (tester) async {
    final old = legacySite(url: 'https://shop.example.com', incomplete: true);
    final completer = Completer<List<GitHubRepo>>();
    await showApp(tester, [old], githubLookup: () => completer.future);

    await tapRowButton(tester, 'shop.example.com', 'Edit…');

    expect(find.text('Searching GitHub with gh…'), findsOneWidget);
    expect(find.text('No matching repository found with gh'), findsNothing);

    completer.complete(const [
      GitHubRepo(
          nameWithOwner: 'elkuku/shop', url: 'https://github.com/elkuku/shop'),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('Searching GitHub with gh…'), findsNothing);
    expect(find.text('Existing repo: elkuku/shop'), findsOneWidget);
  });

  testWidgets('a failed gh lookup is shown instead of a guessed URL',
      (tester) async {
    final old = legacySite(url: 'https://shop.example.com', incomplete: true);
    await showApp(tester, [old],
        githubLookup: () async =>
            throw StateError('gh api user/repos failed (exit 1)'));

    await tapRowButton(tester, 'shop.example.com', 'Edit…');

    expect(
        find.text('GitHub lookup failed: gh api user/repos failed (exit 1)'),
        findsOneWidget);
    expect(find.text('Enter the GitHub repository URL'), findsOneWidget);
    expect(find.byTooltip('Use suggested GitHub repository'), findsNothing);
  });

  test('writes the home folder as ~', () {
    final home = Platform.environment['HOME']!;

    expect(collapseHome('$home/repos/shop'), '~/repos/shop');
    expect(collapseHome(home), '~');
    expect(collapseHome('${home}x/shop'), '${home}x/shop');
    expect(collapseHome('/srv/shop'), '/srv/shop');
  });

  testWidgets('the edit dialog holds only the project details', (tester) async {
    await showApp(tester, [_blog]);

    await tapRowButton(tester, 'Blog', 'Edit…');

    expect(find.widgetWithText(TextField, 'Display name'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'GitHub repository'), findsOneWidget);
    // The address and deploy remote belong to the environments now.
    expect(find.widgetWithText(TextField, 'Site URL'), findsNothing);
    expect(find.text('Deploy remote'), findsNothing);
    await tester.enterText(
        find.widgetWithText(TextField, 'Local repository'), '~/repos/blog');
    await tester.pumpAndSettle();
    expect(find.text('Deploy remote'), findsNothing);
  });

  testWidgets('an empty list offers to add a site', (tester) async {
    await showApp(tester, []);

    expect(find.text('No projects yet'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Add site'));
    await tester.pumpAndSettle();

    // The identity fields are all required now.
    await tester.enterText(
        find.widgetWithText(TextField, 'Display name'), 'Shop');
    await tester.enterText(
        find.widgetWithText(TextField, 'Local repository'), '~/repos/shop');
    await tester.enterText(find.widgetWithText(TextField, 'GitHub repository'),
        'https://github.com/elkuku/shop');

    // The address is part of the first environment, edited inside the same wizard.
    // The wizard's form is scrollable now that the identity fields are required.
    await tester.ensureVisible(find.text('Add environment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add environment'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'plesk');
    // Without a server the environment only stores a subdomain, not a full URL.
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Subdomain'), 'shop');
    await tester.tap(find.widgetWithText(FilledButton, 'OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    expect(find.text('Shop'), findsOneWidget);
    expect(settings.sites.single.mainTarget.subdomain, 'shop');
    expect(settings.sites.single.mainTarget.url, isEmpty);
    expect(fetched, isEmpty, reason: 'No server is selected');
  });

  testWidgets('a new environment needs a valid subdomain', (tester) async {
    await showApp(tester, [_shop]);

    await tapRowButton(tester, 'Shop', 'Environments…');
    await tester.tap(find.text('Add environment'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'vm');
    await tester.tap(find.widgetWithText(FilledButton, 'OK'));
    await tester.pumpAndSettle();
    expect(find.text('Enter the subdomain'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Subdomain'), 'shop.example.com');
    await tester.tap(find.widgetWithText(FilledButton, 'OK'));
    await tester.pumpAndSettle();
    expect(find.text('Use lowercase letters, digits and dashes'), findsOneWidget);
    expect(settings.writes, 0);

    // Cancel adds nothing.
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(settings.sites, hasLength(1));
  });

  testWidgets('edit a site and reload only that one', (tester) async {
    await showApp(tester, [_shop, _blog]);
    expect(fetched, isEmpty, reason: 'No server is selected');
    final before = checkedWith.length;

    await tapRowButton(tester, 'Blog', 'Edit…');

    expect(find.text('Edit site'), findsOneWidget);
    expect(field(tester, 'Display name').controller!.text, 'Blog');
    await tester.enterText(
        find.widgetWithText(TextField, 'Display name'), 'News');
    await tester.enterText(
        find.widgetWithText(TextField, 'Local repository'), '~/repos/news');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('News'), findsOneWidget);
    expect(find.text('Blog'), findsNothing);
    expect(settings.sites[1].name, 'News');
    expect(settings.sites[1].repoPath, '~/repos/news');
    expect(fetched, isEmpty);
    expect(checkedWith.length, before + 1,
        reason: 'Only the edited site is checked again');
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
