import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuku_project_checker/main.dart';
import 'package:kuku_project_checker/support/app_services.dart';
import 'package:kuku_project_checker/support/preferences.dart';
import 'package:kuku_project_checker/support/repo_status.dart';
import 'package:kuku_project_checker/support/settings.dart';
import 'package:kuku_project_checker/support/site.dart';
import 'package:kuku_project_checker/support/site_info.dart';

class _MemorySettings extends Settings {
  List<Site> sites = [
    const Site(name: 'Shop', url: 'https://shop.example.com', repoPath: '/repo')
  ];
  @override
  Future<List<Site>> readSettings() async => sites;
  @override
  Future<File> writeSettings(List<Site> s) async {
    sites = s;
    return File('/dev/null');
  }
}

class _Light extends Preferences {
  @override
  Future<ThemeMode> readThemeMode() async => ThemeMode.light;
  @override
  Future<void> writeThemeMode(ThemeMode mode) async {}
}

void main() {
  testWidgets(
      'the list shows the git status and the menu again after the settings',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MyApp(
      preferences: _Light(),
      services: AppServices(
        settings: _MemorySettings(),
        fetchInfo: (_) async =>
            const SystemInfo(sfVersion: '8.1.11', phpVersion: '8.5.12'),
        checkRepo: (_) async =>
            const RepoStatus(branch: 'master', uncommitted: 0, unpushed: 0),
        openInTargets: const [],
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('master'), findsOneWidget);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Expand'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Shop2');
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Shop2'), findsOneWidget);
    expect(find.textContaining('master'), findsOneWidget);
    expect(find.byTooltip('Open in …'), findsOneWidget);
  });
}
