import 'dart:convert';

import 'deployer.dart' show RunFunction;
import 'server.dart';

/// One PostgreSQL dump from a dated backup set on a KMyServer.
class DbDumpChoice {
  final String date;
  final String file;

  const DbDumpChoice({required this.date, required this.file});

  /// The validated path passed to `site-db-import` on the server.
  String get path => '/var/backups/server/db/$date/$file';

  String get label => '$date · $file';

  @override
  bool operator ==(Object other) =>
      other is DbDumpChoice && other.date == date && other.file == file;

  @override
  int get hashCode => Object.hash(date, file);
}

/// Reads the backup sets a KMyServer reports through `site-db-backups list`.
///
/// The server command is a fixed argv; only the JSON it returns is interpreted, and
/// every date/file is checked before it becomes a command argument.
class ServerDbBackups {
  static final RegExp _date = RegExp(r'^\d{4}-\d{2}-\d{2}$');
  static final RegExp _file = RegExp(r'^pg-[A-Za-z0-9_.-]+\.dump$');

  static Future<List<DbDumpChoice>> fetch(
      Server server, RunFunction run) async {
    final lines = <String>[];
    final code = await run(
      'ssh',
      server.sshArgs('root', [
        '/usr/local/sbin/site-db-backups',
        'list',
      ]),
      lines.add,
    );
    if (code != 0) {
      throw StateError('Reading the backup sets failed (exit $code)');
    }

    final json = jsonDecode(lines.join('\n'));
    final sets = json is Map ? json['sets'] : null;
    if (sets is! List) return const [];

    final choices = <DbDumpChoice>[];
    for (final set in sets) {
      if (set is! Map) continue;
      final date = set['date'];
      final dumps = set['dumps'];
      if (date is! String || !_date.hasMatch(date) || dumps is! List) continue;
      for (final dump in dumps) {
        if (dump is String && _file.hasMatch(dump)) {
          choices.add(DbDumpChoice(date: date, file: dump));
        }
      }
    }
    return choices;
  }
}
