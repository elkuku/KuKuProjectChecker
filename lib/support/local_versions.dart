import 'dart:convert';
import 'dart:io';

/// The versions a project uses on this machine, read from its repository:
/// Symfony from composer.lock, the database from the docker compose image, and PHP
/// from the local `php` binary.
///
/// Every value is null if it can't be found.
class LocalVersions {
  final String? symfony;
  final String? php;

  /// "mariadb", "mysql" or "postgresql".
  final String? dbPlatform;

  /// The version in the image tag, e.g. "12.3" for mariadb:12.3 or "16" for postgres:16-alpine.
  final String? dbVersion;

  const LocalVersions({this.symfony, this.php, this.dbPlatform, this.dbVersion});

  /// The compose files, in the order docker compose reads them (later ones win).
  static const composeFiles = [
    'compose.yaml',
    'compose.yml',
    'docker-compose.yaml',
    'docker-compose.yml',
    'compose.override.yaml',
    'compose.override.yml',
    'docker-compose.override.yaml',
    'docker-compose.override.yml',
  ];

  /// Reads the versions of the repository at [repoPath] (already expanded).
  /// [phpVersion] gives the local PHP version; by default it asks the `php` binary.
  static Future<LocalVersions> read(String repoPath,
      {Future<String?> Function()? phpVersion}) async {
    String? symfony;
    try {
      symfony = symfonyFromLock(
          await File('$repoPath/composer.lock').readAsString());
    } on IOException {
      symfony = null;
    }

    final composeTexts = <String>[];
    for (final name in composeFiles) {
      final file = File('$repoPath/$name');
      if (await file.exists()) composeTexts.add(await file.readAsString());
    }
    final database = databaseFromCompose(composeTexts);

    return LocalVersions(
      symfony: symfony,
      php: await (phpVersion ?? localPhpVersion)(),
      dbPlatform: database?.$1,
      dbVersion: database?.$2,
    );
  }

  static Future<String?>? _php;

  /// The version of the `php` on the PATH; asked once per app start.
  static Future<String?> localPhpVersion() => _php ??= () async {
        try {
          final result =
              await Process.run('php', ['-r', 'echo PHP_VERSION;']);
          final out = (result.stdout as String).trim();
          return result.exitCode == 0 && out.isNotEmpty ? out : null;
        } on ProcessException {
          return null;
        }
      }();

  /// The version of symfony/http-kernel in a composer.lock, without the "v".
  static String? symfonyFromLock(String lock) {
    try {
      final json = jsonDecode(lock);
      for (final package in [...?json['packages'], ...?json['packages-dev']]) {
        if (package['name'] == 'symfony/http-kernel' &&
            package['version'] is String) {
          return (package['version'] as String).replaceFirst(RegExp('^v'), '');
        }
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  /// The database platform and version from the `image:` lines of compose files,
  /// e.g. ("postgresql", "16") for `postgres:${POSTGRES_VERSION:-16}-alpine`.
  /// The last database image wins, as an override file would.
  static (String, String)? databaseFromCompose(List<String> files) {
    (String, String)? found;

    for (final text in files) {
      for (final match in RegExp(r'''^\s*image:\s*['"]?([^'"\s#]+)''', multiLine: true)
          .allMatches(text)) {
        // ${VAR:-default} and ${VAR-default} become the default.
        final image = match.group(1)!.replaceAllMapped(
            RegExp(r'\$\{[^}:-]+:?-([^}]*)\}'), (m) => m.group(1)!);
        final colon = image.lastIndexOf(':');
        if (colon < 0) continue;

        final name = image.substring(0, colon).split('/').last;
        final platform = switch (name) {
          'mariadb' => 'mariadb',
          'mysql' => 'mysql',
          'postgres' || 'postgis' => 'postgresql',
          _ => null,
        };
        final version =
            RegExp(r'^\d+(\.\d+)*').stringMatch(image.substring(colon + 1));

        if (platform != null && version != null) found = (platform, version);
      }
    }

    return found;
  }

  /// True if [live] is the version [local] names, compared as far as [local] goes
  /// (at most [maxParts] parts): "16" matches "16.4 (Debian…)", "8.1.11" doesn't match "8.1.10".
  /// MySQL's old "5.5.5-" prefix in a live version is skipped.
  static bool matches(String local, String live, {int maxParts = 3}) {
    List<String> parts(String v) =>
        (RegExp(r'^(5\.5\.5-)?(\d+(?:\.\d+)*)').firstMatch(v)?.group(2) ?? '')
            .split('.')
            .where((p) => p.isNotEmpty)
            .toList();

    final wanted = parts(local).take(maxParts).toList();
    final running = parts(live);
    if (wanted.isEmpty || running.length < wanted.length) return false;

    for (var i = 0; i < wanted.length; i++) {
      if (int.parse(wanted[i]) != int.parse(running[i])) return false;
    }
    return true;
  }
}
