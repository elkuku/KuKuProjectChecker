import 'local_versions.dart';
import 'repo_status.dart';
import 'site.dart' show Site, SiteTarget;

class SiteInfo {
  final String url;

  /// The site's name, or its host if no name is set.
  final String name;

  /// True if [name] was set in the settings (not taken from the URL).
  final bool hasName;

  /// The required GitHub repository; empty for old incomplete records.
  final String githubRepo;

  /// False for old records missing a required field; the card shows a banner.
  final bool isComplete;

  /// The selected server the versions are compared with; null in local-only mode.
  final String? compareServer;

  /// Null when no server is selected: then only local versions and git status are shown.
  final Future<SystemInfo>? systemInfo;

  /// Null when no local repository is set for the site.
  final Future<RepoStatus>? repoStatus;

  /// The versions in the local repository; null when no local repository is set.
  final Future<LocalVersions>? localVersions;

  /// The local repository folder with ~ expanded, or null if none is set.
  final String? repoPath;

  /// The dev site's address; null if the site has none.
  final String? devUrl;

  /// What the dev site reports; null if the site has none.
  final Future<SystemInfo>? devInfo;

  /// When the newest commit of the code the dev site deploys from (the local repository's
  /// upstream branch, e.g. origin/master) was made; null without a dev site or repository.
  final Future<DateTime?>? upstreamTime;

  /// The project's environments, each with its own server, URL and deploy remote.
  final List<SiteTarget> targets;

  /// The setting this info was built from, so edits can write targets back.
  final Site? site;

  const SiteInfo({
    required this.url,
    required this.name,
    this.hasName = false,
    this.githubRepo = '',
    this.isComplete = true,
    this.compareServer,
    this.systemInfo,
    this.repoStatus,
    this.localVersions,
    this.repoPath,
    this.devUrl,
    this.devInfo,
    this.upstreamTime,
    this.targets = const [],
    this.site,
  });

  /// The target for [server] (a [Server.name]), or null if this project has none there.
  SiteTarget? targetFor(String server) {
    for (final target in targets) {
      if (target.server == server) return target;
    }
    return null;
  }
}

/// How a dev site that deploys itself from the upstream branch is doing.
enum DevState {
  /// The last deploy was fine and is newer than the newest upstream commit.
  upToDate,

  /// The upstream branch has a commit newer than the last deploy: the deploy didn't
  /// run (yet) or is still running.
  behind,

  /// The last deploy finished with errors.
  errors,

  /// The last deploy didn't finish.
  unfinished,

  /// The site doesn't report its deploys.
  unknown;

  /// The state for the dev site's [deploy] and the time of the newest [upstream] commit.
  static DevState of(LastDeploy? deploy, DateTime? upstream) {
    if (deploy == null) return unknown;
    if (deploy.status == 'errors') return errors;
    if (!deploy.ok) return unfinished;
    if (upstream != null &&
        deploy.at != null &&
        deploy.at!.isBefore(upstream)) {
      return behind;
    }
    return upToDate;
  }
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
          dbPlatform:
              json['db_platform'] is String ? json['db_platform'] : null,
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
