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

  _MemorySettings(this.sites);

  @override
  Future<List<Site>> readSettings() async => sites;

  @override
  Future<File> writeSettings(List<Site> sites) async {
    saved = sites;

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

void main() {
  testWidgets('drag a site to another place and save the new order',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final settings = _MemorySettings([
      const Site(
          url: 'https://a.example', repoPath: '~/repos/a', name: 'Alpha'),
      const Site(url: 'https://b.example'),
      const Site(url: 'https://c.example'),
    ]);

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

    List<String> urls() => tester
        .widgetList<TextField>(find.byType(TextField))
        .map((field) => field.controller!.text)
        .where((text) => text.startsWith('https://'))
        .toList();

    expect(urls(),
        ['https://a.example', 'https://b.example', 'https://c.example']);

    // Drag the first site's handle below the last site.
    final handle = find.byIcon(Icons.drag_indicator).first;
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(const Offset(0, 1100));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(urls(),
        ['https://b.example', 'https://c.example', 'https://a.example']);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect([for (final site in settings.saved!) site.url],
        ['https://b.example', 'https://c.example', 'https://a.example']);
    // The name and repository path move with their site.
    expect(settings.saved!.last.repoPath, '~/repos/a');
    expect(settings.saved!.last.name, 'Alpha');
  });

  testWidgets('a new site gets a name and is saved with it', (tester) async {
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

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(settings.saved!.single.toJson(),
        {'name': 'Shop', 'url': 'https://shop.example.com', 'repoPath': ''});
  });

  testWidgets('a site without a valid address is not saved', (tester) async {
    final settings = _MemorySettings([const Site(url: 'https://a.example')]);
    await openSettings(tester, settings);

    await tester.enterText(
        find.widgetWithText(TextField, 'Site URL'), 'shop.example.com');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(settings.saved, isNull);
    expect(find.text('Use a full address, like https://shop.example.com'),
        findsOneWidget);
  });
}
