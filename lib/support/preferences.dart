import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// App preferences, kept in preferences.json next to the site settings.
class Preferences {
  final Future<Directory> Function() _directory;

  Preferences({Future<Directory> Function()? directory})
      : _directory = directory ?? getApplicationSupportDirectory;

  Future<File> get _file async =>
      File('${(await _directory()).path}/preferences.json');

  Future<Map<String, dynamic>> _read() async {
    try {
      final json = jsonDecode(await (await _file).readAsString());

      return json is Map<String, dynamic> ? json : {};
    } catch (e) {
      return {};
    }
  }

  /// The saved theme; follows the system if nothing (or something unknown) is saved.
  Future<ThemeMode> readThemeMode() async {
    final name = (await _read())['themeMode'];

    return ThemeMode.values.firstWhere(
      (mode) => mode.name == name,
      orElse: () => ThemeMode.system,
    );
  }

  Future<void> writeThemeMode(ThemeMode mode) async {
    final preferences = await _read()
      ..['themeMode'] = mode.name;
    final file = await _file;

    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(preferences));
  }
}

/// The theme after [mode] when switching: system → light → dark → system.
ThemeMode nextThemeMode(ThemeMode mode) => switch (mode) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };

/// The icon and label of the theme switch for [mode].
(IconData, String) themeModeButton(ThemeMode mode) => switch (mode) {
      ThemeMode.system => (Icons.brightness_auto, 'Theme: system'),
      ThemeMode.light => (Icons.light_mode, 'Theme: light'),
      ThemeMode.dark => (Icons.dark_mode, 'Theme: dark'),
    };
