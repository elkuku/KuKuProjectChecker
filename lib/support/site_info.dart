import 'local_versions.dart';
import 'repo_status.dart';

class SiteInfo {
  final String url;

  /// The site's name, or its host if no name is set.
  final String name;

  /// True if [name] was set in the settings (not taken from the URL).
  final bool hasName;
  final Future<SystemInfo> systemInfo;

  /// Null when no local repository is set for the site.
  final Future<RepoStatus>? repoStatus;

  /// The versions in the local repository; null when no local repository is set.
  final Future<LocalVersions>? localVersions;

  /// The local repository folder with ~ expanded, or null if none is set.
  final String? repoPath;

  const SiteInfo({
    required this.url,
    required this.name,
    this.hasName = false,
    required this.systemInfo,
    this.repoStatus,
    this.localVersions,
    this.repoPath,
  });
}

/// What a site reports at /system/info/.
///
/// The Symfony and PHP versions are always there ("N/A" when the site hides them); the
/// database and the last deploy only when the site exposes them (KuKu system tools bundle 1.7+).
class SystemInfo {
  final String sfVersion;
  final String phpVersion;

  /// "mariadb", "mysql", "postgresql", ...; null if not exposed or unknown.
  final String? dbPlatform;

  /// What the database server reports, e.g. "12.3.4-MariaDB-deb12" or "13.23".
  final String? dbVersion;

  /// The newest run in the site's deploy log; null if not exposed or there is no log.
  final LastDeploy? lastDeploy;

  const SystemInfo({
    required this.sfVersion,
    required this.phpVersion,
    this.dbPlatform,
    this.dbVersion,
    this.lastDeploy,
  });

  factory SystemInfo.fromJson(Map<String, dynamic> json) {
    return switch (json) {
      {
        'sf_version': String sfVersion,
        'php_version': String phpVersion,
      } =>
        SystemInfo(
          sfVersion: sfVersion,
          phpVersion: phpVersion,
          dbPlatform: json['db_platform'] is String ? json['db_platform'] : null,
          dbVersion: json['db_version'] is String ? json['db_version'] : null,
          lastDeploy: LastDeploy.fromJson(json['last_deploy']),
        ),
      _ => throw const FormatException('Failed to load site info.'),
    };
  }
}

/// The newest run of a site's deploy log.
class LastDeploy {
  /// When the run started; null if the site couldn't read its date.
  final DateTime? at;

  /// "ok", "errors" or "unfinished".
  final String status;

  const LastDeploy({this.at, required this.status});

  bool get ok => status == 'ok';

  /// Null for anything that isn't a {at, status} map.
  static LastDeploy? fromJson(dynamic json) => switch (json) {
        {'status': String status} => LastDeploy(
            at: json['at'] is String ? DateTime.tryParse(json['at']) : null,
            status: status,
          ),
        _ => null,
      };
}
