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

  const LocalVersions(
      {this.symfony, this.php, this.dbPlatform, this.dbVersion});

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
    // The Symfony project may be in a subfolder; the compose files are read from the
    // repository and then from that subfolder (the subfolder's last, so they win).
    final project = await projectFolder(repoPath);

    String? symfony;
    try {
      symfony =
          symfonyFromLock(await File('$project/composer.lock').readAsString());
    } on IOException {
      symfony = null;
    }

    final composeTexts = <String>[];
    for (final folder in {repoPath, project}) {
      for (final name in composeFiles) {
        final file = File('$folder/$name');
        if (await file.exists()) composeTexts.add(await file.readAsString());
      }
    }
    final database = databaseFromCompose(composeTexts);

    // A project may point at a database without a compose service (e.g. the
    // production DATABASE_URL in .env.local), so fall back to the env files.
    final envTexts = <String>[];
    for (final folder in {repoPath, project}) {
      for (final name in const ['.env', '.env.local']) {
        final file = File('$folder/$name');
        if (await file.exists()) envTexts.add(await file.readAsString());
      }
    }

    return LocalVersions(
      symfony: symfony,
      php: await (phpVersion ?? localPhpVersion)(),
      dbPlatform: database?.$1 ?? databasePlatformFromEnv(envTexts),
      dbVersion: database?.$2,
    );
  }

  /// Folders that never hold the project itself.
  static const _skippedFolders = {'vendor', 'node_modules'};

  /// The folder of the PHP project in the repository at [repoPath]: the repository itself
  /// if it has a composer.json, else the first direct subfolder (by name) that has one,
  /// e.g. web/ when the repository also holds an Android app. Falls back to [repoPath].
  static Future<String> projectFolder(String repoPath) async {
    if (await File('$repoPath/composer.json').exists()) return repoPath;

    final candidates = <String>[];
    try {
      await for (final entry in Directory(repoPath).list(followLinks: false)) {
        final name = entry.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
        if (entry is Directory &&
            !name.startsWith('.') &&
            !_skippedFolders.contains(name) &&
            await File('${entry.path}/composer.json').exists()) {
          candidates.add(entry.path);
        }
      }
    } on FileSystemException {
      return repoPath;
    }

    candidates.sort();
    return candidates.firstOrNull ?? repoPath;
  }

  static Future<String?>? _php;

  /// The version of the `php` on the PATH; asked once per app start.
  static Future<String?> localPhpVersion() => _php ??= () async {
        try {
          final result = await Process.run('php', ['-r', 'echo PHP_VERSION;']);
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
      for (final match
          in RegExp(r'''^\s*image:\s*['"]?([^'"\s#]+)''', multiLine: true)
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

  /// The database platform in a local `DATABASE_URL`, when no compose image was found.
  /// The URL scheme is enough for the deploy dialog's checkbox; no credentials are read.
  static String? databasePlatformFromEnv(List<String> files) {
    final url = RegExp(
      r'''^\s*(?:export\s+)?DATABASE_URL\s*=\s*["']?([^"'\s#]+)''',
      multiLine: true,
    );
    for (final text in files) {
      for (final match in url.allMatches(text)) {
        final scheme = match.group(1)!.split('://').first.toLowerCase();
        if (scheme.startsWith('postgres')) return 'postgresql';
        if (scheme.startsWith('mysql')) return 'mysql';
        if (scheme.startsWith('mariadb')) return 'mariadb';
      }
    }
    return null;
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
