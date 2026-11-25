import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'server.dart';

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

  /// The servers the sites can deploy to, and the active one's name ('' = each site uses
  /// its own deploy remote).
  Future<(List<Server>, String)> readServers() async {
    final json = await _read();
    final list = json['servers'] is List ? json['servers'] as List : const [];
    final servers = [
      for (final item in list)
        if (item is Map<String, dynamic>) Server.fromJson(item)
    ]
        .where((server) => server.name.isNotEmpty && server.remote.isNotEmpty)
        .toList();
    final active = json['activeServer'];

    return (
      servers,
      active is String && servers.any((server) => server.name == active)
          ? active
          : ''
    );
  }

  Future<void> writeServers(List<Server> servers, String active) async {
    final preferences = await _read()
      ..['servers'] = [for (final server in servers) server.toJson()]
      ..['activeServer'] = active;
    await _write(preferences);
  }

  Future<void> writeThemeMode(ThemeMode mode) async {
    final preferences = await _read()
      ..['themeMode'] = mode.name;
    await _write(preferences);
  }

  Future<void> _write(Map<String, dynamic> preferences) async {
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
