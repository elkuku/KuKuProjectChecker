import 'dart:io';

import 'package:flutter/material.dart';

/// An app that can open a local repository folder.
class OpenInTarget {
  final String label;
  final IconData icon;

  /// Candidate executables, the first one found is used.
  final List<String> commands;

  /// The arguments for a command and the folder.
  final List<String> Function(String command, String path) arguments;

  const OpenInTarget({
    required this.label,
    required this.icon,
    required this.commands,
    required this.arguments,
  });

  static final List<OpenInTarget> all = [
    OpenInTarget(
      label: 'File manager',
      icon: Icons.folder_open,
      commands: ['xdg-open'],
      arguments: (_, path) => [path],
    ),
    OpenInTarget(
      label: 'Terminal',
      icon: Icons.terminal,
      commands: ['konsole', 'gnome-terminal', 'xfce4-terminal', 'kitty'],
      arguments: (command, path) => switch (command) {
        'konsole' => ['--workdir', path],
        'gnome-terminal' => ['--working-directory=$path'],
        'xfce4-terminal' => ['--working-directory=$path'],
        _ => ['--directory', path],
      },
    ),
    OpenInTarget(
      label: 'PhpStorm',
      icon: Icons.code,
      commands: ['phpstorm', 'phpstorm.sh'],
      arguments: (_, path) => [path],
    ),
    OpenInTarget(
      label: 'VS Code',
      icon: Icons.data_object,
      commands: ['code', 'codium'],
      arguments: (_, path) => [path],
    ),
    OpenInTarget(
      label: 'Kate',
      icon: Icons.edit_note,
      commands: ['kate'],
      arguments: (_, path) => [path],
    ),
    OpenInTarget(
      label: 'gitk (history)',
      icon: Icons.history,
      commands: ['gitk'],
      arguments: (_, path) => ['--all'],
    ),
  ];

  /// The folders searched for the commands: PATH plus the places tools put their launchers,
  /// which a desktop session's PATH often lacks (e.g. JetBrains Toolbox scripts).
  static List<String> searchPath(Map<String, String> environment) {
    final home = environment['HOME'] ?? '';

    return [
      ...(environment['PATH'] ?? '').split(':').where((dir) => dir.isNotEmpty),
      if (home.isNotEmpty) ...[
        '$home/.local/bin',
        '$home/.local/share/JetBrains/Toolbox/scripts',
      ],
    ];
  }

  /// The full path of the first command found, or null if this app is not installed.
  String? findExecutable(List<String> searchPath,
      {bool Function(String path)? isExecutable}) {
    final check = isExecutable ?? _isExecutable;

    for (final command in commands) {
      for (final dir in searchPath) {
        final path = '$dir/$command';
        if (check(path)) {
          return path;
        }
      }
    }

    return null;
  }

  /// The apps of [all] that are installed, with their executable.
  static List<(OpenInTarget, String)> available(
      {Map<String, String>? environment,
      bool Function(String path)? isExecutable}) {
    final path = searchPath(environment ?? Platform.environment);

    return [
      for (final target in all)
        if (target.findExecutable(path, isExecutable: isExecutable)
            case final executable?)
          (target, executable),
    ];
  }

  /// Starts the app for the folder; it keeps running when this app closes.
  Future<void> open(String executable, String folder) async {
    final command = executable.split('/').last;

    await Process.start(
      executable,
      arguments(command, folder),
      workingDirectory: folder,
      mode: ProcessStartMode.detached,
    );
  }

  static bool _isExecutable(String path) {
    final stat = FileStat.statSync(path);

    return stat.type == FileSystemEntityType.file && stat.mode & 0x49 != 0;
  }
}
