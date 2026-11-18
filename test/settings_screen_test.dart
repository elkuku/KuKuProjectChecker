import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuku_project_checker/screens/settings_screen.dart';
import 'package:kuku_project_checker/support/settings.dart';
import 'package:kuku_project_checker/support/site.dart';

/// Keeps the sites in memory, so the test needs no settings file.
class _MemorySettings extends Settings {
  List<Site> sites;
  List<Site>? saved;
  int writes = 0;

  _MemorySettings(this.sites);

  @override
  Future<List<Site>> readSettings() async => sites;

  @override
  Future<File> writeSettings(List<Site> sites) async {
    saved = sites;
    writes++;

    return File('/dev/null');
  }
}

Future<void> openSettings(WidgetTester tester, Settings settings) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => TextButton(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => SettingsPage(settings: settings))),
        child: const Text('open'),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> leave(WidgetTester tester) async {
  await tester.tap(find.byType(BackButton));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the sites start collapsed and open with a click',
      (tester) async {
    await openSettings(
        tester,
        _MemorySettings([
          const Site(
              url: 'https://a.example', repoPath: '~/repos/a', name: 'Alpha'),
          const Site(url: 'https://b.example'),
        ]));

    expect(find.byType(TextField), findsNothing);
    // The collapsed header shows the address and the repository.
    expect(find.text('https://a.example  ·  ~/repos/a'), findsOneWidget);

    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(3));

    await tester.tap(find.byTooltip('Expand all'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(6));

    await tester.tap(find.byTooltip('Collapse all'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('drag a site to another place and the new order is saved',
      (tester) async {
    final settings = _MemorySettings([
      const Site(
          url: 'https://a.example', repoPath: '~/repos/a', name: 'Alpha'),
      const Site(url: 'https://b.example'),
      const Site(url: 'https://c.example'),
    ]);
    await openSettings(tester, settings);

    // Drag the first site's handle below the last site.
    final handle = find.byIcon(Icons.drag_indicator).first;
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(const Offset(0, 300));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(settings.saved, isNull);

    // Saved shortly after the change, without leaving.
    await tester.pump(SettingsPage.saveDelay);
    expect([for (final site in settings.saved!) site.url],
        ['https://b.example', 'https://c.example', 'https://a.example']);
    // The name and repository path move with their site.
    expect(settings.saved!.last.repoPath, '~/repos/a');
    expect(settings.saved!.last.name, 'Alpha');
    expect(find.text('Saved'), findsOneWidget);
  });

  testWidgets('a new site is saved when leaving', (tester) async {
    final settings = _MemorySettings([]);
    await openSettings(tester, settings);

    expect(find.text('No sites yet'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Add site'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Shop');
    await tester.enterText(
        find.widgetWithText(TextField, 'Site URL'), 'https://shop.example.com');
    await tester.pump();
    // The card header shows the name.
    expect(find.text('Shop'), findsNWidgets(2));

    await leave(tester);

    expect(settings.saved!.single.toJson(),
        {'name': 'Shop', 'url': 'https://shop.example.com', 'repoPath': ''});
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('a new site left blank is not saved', (tester) async {
    final settings = _MemorySettings([const Site(url: 'https://a.example')]);
    await openSettings(tester, settings);

    await tester.tap(find.widgetWithText(FilledButton, 'Add site'));
    await tester.pumpAndSettle();
    await leave(tester);

    expect(settings.saved!.single.url, 'https://a.example');
  });

  testWidgets('a site without a valid address is not saved', (tester) async {
    final settings = _MemorySettings([
      const Site(url: 'https://a.example'),
      const Site(url: 'https://b.example'),
    ]);
    await openSettings(tester, settings);

    await tester.tap(find.text('a.example'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Site URL'), 'shop.example.com');
    await tester.pump(SettingsPage.saveDelay);

    expect(settings.saved, isNull);
    expect(find.text('Use a full address, like https://shop.example.com'),
        findsOneWidget);
    expect(find.text('Not saved: fix the address'), findsOneWidget);

    // Leaving asks; "Fix them" stays.
    await leave(tester);
    expect(find.text('Some sites have no valid address'), findsOneWidget);
    await tester.tap(find.text('Fix them'));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsNothing);
    expect(settings.saved, isNull);

    // "Leave without them" saves the others.
    await leave(tester);
    await tester.tap(find.text('Leave without them'));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect([for (final site in settings.saved!) site.url],
        ['https://b.example']);
  });

  testWidgets('a removed site can be brought back', (tester) async {
    final settings = _MemorySettings([
      const Site(url: 'https://a.example', name: 'Alpha'),
      const Site(url: 'https://b.example'),
    ]);
    await openSettings(tester, settings);

    await tester.tap(find.byTooltip('Remove this site').first);
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsNothing);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    await tester.pump(SettingsPage.saveDelay);

    expect([for (final site in settings.saved!) site.name], ['Alpha', '']);
  });
}
