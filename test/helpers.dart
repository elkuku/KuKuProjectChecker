import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuku_project_checker/support/preferences.dart';
import 'package:kuku_project_checker/support/server.dart';
import 'package:kuku_project_checker/support/site.dart';

/// A complete project for tests written before the required identity fields.
/// [incomplete] builds the old kind of record instead, so the compatibility and
/// warning path can be tested. [server] attaches the address to a configured
/// server; without it the app is in local-only mode for this project.
Site legacySite({
  required String url,
  String name = '',
  String repoPath = '',
  String githubRepo = '',
  String deployRemote = '',
  String devUrl = '',
  String server = '',
  bool incomplete = false,
}) {
  final host = Uri.tryParse(url)?.host ?? '';
  final target = SiteTarget(
    name: name.isNotEmpty ? name : host,
    server: server,
    url: url,
    deployRemote: deployRemote,
  );
  if (incomplete) return Site(targets: [target]);

  return Site(
    name: name.isNotEmpty ? name : host,
    repoPath: repoPath.isNotEmpty ? repoPath : '~/repos/$host',
    githubRepo: githubRepo.isNotEmpty
        ? githubRepo
        : 'https://github.com/elkuku/$host',
    devUrl: devUrl,
    targets: [target],
  );
}

/// Preferences with a fixed theme and server selection, for widget tests.
class TestPreferences extends Preferences {
  TestPreferences({this.servers = const [], this.active = ''});

  final List<Server> servers;
  final String active;

  @override
  Future<ThemeMode> readThemeMode() async => ThemeMode.light;

  @override
  Future<void> writeThemeMode(ThemeMode mode) async {}

  @override
  Future<(List<Server>, String)> readServers() async => (servers, active);

  @override
  Future<void> writeServers(List<Server> servers, String active) async {}
}

/// The card containing [project] in its title.
Finder projectCard(String project) => find.ancestor(
      of: find.text(project),
      matching: find.byType(Card),
    );

/// Expands a project or temporary server row so its details and extra buttons show.
Future<void> expandRow(WidgetTester tester, String title) async {
  await tester.tap(find.descendant(
    of: projectCard(title),
    matching: find.byTooltip('Show details'),
  ));
  await tester.pumpAndSettle();
}

/// Taps a button on the row whose title is [title].
Future<void> tapRowButton(
  WidgetTester tester,
  String title,
  String tooltip, {
  bool expand = false,
}) async {
  if (expand) await expandRow(tester, title);
  await tester.tap(find.descendant(
    of: projectCard(title),
    matching: find.byTooltip(tooltip),
  ));
  await tester.pumpAndSettle();
}

/// Opens the only dropdown left on a row: Open in…
Future<void> openOpenInMenu(WidgetTester tester, String title) async {
  await tester.tap(find.descendant(
    of: projectCard(title),
    matching: find.byTooltip('Open in…'),
  ));
  await tester.pumpAndSettle();
}
