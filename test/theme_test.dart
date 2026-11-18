import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuku_project_checker/main.dart';
import 'package:kuku_project_checker/support/app_services.dart';
import 'package:kuku_project_checker/support/preferences.dart';
import 'package:kuku_project_checker/support/settings.dart';
import 'package:kuku_project_checker/support/site.dart';

void main() {
  late Directory tmp;
  late Preferences preferences;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('preferences_test');
    preferences = Preferences(directory: () async => tmp);
  });

  tearDown(() => tmp.delete(recursive: true));

  test('follows the system until a theme is saved', () async {
    expect(await preferences.readThemeMode(), ThemeMode.system);

    await preferences.writeThemeMode(ThemeMode.dark);
    expect(await preferences.readThemeMode(), ThemeMode.dark);
    expect(await File('${tmp.path}/preferences.json').readAsString(),
        '{"themeMode":"dark"}');
  });

  test('ignores an unreadable or unknown saved theme', () async {
    await File('${tmp.path}/preferences.json').writeAsString('not json');
    expect(await preferences.readThemeMode(), ThemeMode.system);

    await File('${tmp.path}/preferences.json')
        .writeAsString('{"themeMode":"purple"}');
    expect(await preferences.readThemeMode(), ThemeMode.system);
  });

  test('switches system → light → dark → system', () {
    expect(nextThemeMode(ThemeMode.system), ThemeMode.light);
    expect(nextThemeMode(ThemeMode.light), ThemeMode.dark);
    expect(nextThemeMode(ThemeMode.dark), ThemeMode.system);
  });

  testWidgets('the app bar button switches and saves the theme',
      (tester) async {
    final recording = _RecordingPreferences();
    await tester
        .pumpWidget(MyApp(preferences: recording, services: _services()));
    await tester.pump();

    Brightness brightness() =>
        Theme.of(tester.element(find.byType(Scaffold))).brightness;

    expect(find.byTooltip('Theme: system'), findsOneWidget);

    await tester.tap(find.byTooltip('Theme: system'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Theme: light'), findsOneWidget);
    expect(brightness(), Brightness.light);

    await tester.tap(find.byTooltip('Theme: light'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Theme: dark'), findsOneWidget);
    expect(brightness(), Brightness.dark);
    expect(recording.saved, [ThemeMode.light, ThemeMode.dark]);
  });

  testWidgets('starts with the saved theme', (tester) async {
    await tester.pumpWidget(MyApp(
        preferences: _RecordingPreferences(initial: ThemeMode.dark),
        services: _services()));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Theme: dark'), findsOneWidget);
    expect(Theme.of(tester.element(find.byType(Scaffold))).brightness,
        Brightness.dark);
  });

  testWidgets('tooltips are dark in the dark theme', (tester) async {
    await tester.pumpWidget(MyApp(
        preferences: _RecordingPreferences(initial: ThemeMode.dark),
        services: _services()));
    await tester.pumpAndSettle();

    final theme = Theme.of(tester.element(find.byType(Scaffold)));
    final decoration = theme.tooltipTheme.decoration as BoxDecoration;

    expect(decoration.color, theme.colorScheme.surfaceContainerHighest);
    expect(decoration.color!.computeLuminance(), lessThan(0.2));
    expect(theme.tooltipTheme.textStyle!.color, theme.colorScheme.onSurface);
  });
}

/// Keeps the theme in memory, so widget tests need no files.
class _RecordingPreferences extends Preferences {
  final ThemeMode initial;
  final List<ThemeMode> saved = [];

  _RecordingPreferences({this.initial = ThemeMode.system});

  @override
  Future<ThemeMode> readThemeMode() async => initial;

  @override
  Future<void> writeThemeMode(ThemeMode mode) async => saved.add(mode);
}

/// No sites, no installed apps: the theme tests need no files or plugins.
AppServices _services() =>
    AppServices(settings: _NoSites(), openInTargets: const []);

class _NoSites extends Settings {
  @override
  Future<List<Site>> readSettings() async => [];
}
