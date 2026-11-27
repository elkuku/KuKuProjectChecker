import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../widgets/site_dialog.dart' as site_dialog;
import 'deployer.dart';
import 'github_repos.dart';
import 'local_versions.dart';
import 'open_in.dart';
import 'repo_changes.dart';
import 'repo_status.dart';
import 'server_api.dart';
import 'settings.dart';
import 'site_info.dart';

/// Everything the app reads from outside: the settings file, the sites, the git
/// repositories and the installed apps. The defaults are the real ones; tests and
/// the documentation screenshots pass their own.
class AppServices {
  final Settings settings;
  final Future<SystemInfo> Function(String url) fetchInfo;

  /// Checks a repository; the second argument is the site's deploy remote choice.
  final Future<RepoStatus> Function(String repoPath, String deployRemote)
      checkRepo;

  /// The remotes of a repository as (name, URL), for choosing the deploy remote.
  final Future<List<(String, String)>> Function(String repoPath) listRemotes;
  final RepoChanges Function(String repoPath) repoChanges;

  /// Reads the versions a local repository uses, to compare them with the site's.
  final Future<LocalVersions> Function(String repoPath) readLocal;

  /// Pushes a branch to the deploy remote.
  final PushFunction push;

  /// Rolls a KMyServer site back to its previous release.
  final RollbackFunction rollback;

  /// Reads a server's report; the status screen replaces this in tests.
  final FetchServerHealth fetchServerHealth;

  /// Runs a command (ssh, git, gh) and streams its output; used to create sites.
  final RunFunction run;

  /// Whether a file or folder exists (e.g. the folder for a new site's clone).
  final Future<bool> Function(String path) pathExists;

  /// The installed apps that can open a repository.
  final List<(OpenInTarget, String)> openInTargets;

  /// The folder chooser for a site's local repository.
  final site_dialog.PickFolder pickFolder;

  /// Finds existing GitHub repositories with a name similar to a suggestion.
  final GitHubRepoLookup listGitHubRepos;

  /// When the newest commit of a repository's upstream branch was made, to see whether
  /// a dev site that deploys from it is behind.
  final Future<DateTime?> Function(String repoPath) upstreamTime;

  AppServices({
    Settings? settings,
    Future<SystemInfo> Function(String url)? fetchInfo,
    Future<RepoStatus> Function(String repoPath, String deployRemote)?
        checkRepo,
    Future<List<(String, String)>> Function(String repoPath)? listRemotes,
    RepoChanges Function(String repoPath)? repoChanges,
    Future<LocalVersions> Function(String repoPath)? readLocal,
    PushFunction? push,
    RollbackFunction? rollback,
    FetchServerHealth? fetchServerHealth,
    RunFunction? run,
    Future<bool> Function(String path)? pathExists,
    List<(OpenInTarget, String)>? openInTargets,
    site_dialog.PickFolder? pickFolder,
    GitHubRepoLookup? listGitHubRepos,
    Future<DateTime?> Function(String repoPath)? upstreamTime,
  })  : settings = settings ?? Settings(),
        fetchInfo = fetchInfo ?? fetchSystemInfo,
        checkRepo = checkRepo ??
            ((repoPath, deployRemote) =>
                RepoStatus.check(repoPath, deployRemote: deployRemote)),
        listRemotes = listRemotes ?? RepoStatus.remotes,
        repoChanges = repoChanges ?? RepoChanges.new,
        readLocal = readLocal ?? LocalVersions.read,
        push = push ?? Deployer().push,
        rollback = rollback ?? Deployer().rollback,
        fetchServerHealth = fetchServerHealth ?? ServerApi().health,
        run = run ?? runCommand,
        pathExists = pathExists ??
            ((path) async =>
                await FileSystemEntity.type(path) !=
                FileSystemEntityType.notFound),
        openInTargets = openInTargets ?? OpenInTarget.available(),
        pickFolder = pickFolder ?? site_dialog.pickFolder,
        listGitHubRepos = listGitHubRepos ?? lookupGitHubRepos,
        upstreamTime = upstreamTime ?? RepoStatus.upstreamCommitTime;

  /// Local development servers (Caddy's local CA on the test VM, the Symfony CLI) use their
  /// own certificates. They are accepted for loopback addresses only, which never leave
  /// this machine; every other site needs a valid certificate.
  static bool isLocalHost(String host) {
    host = host.toLowerCase();
    return host == 'localhost' ||
        host.endsWith('.localhost') ||
        host == '::1' ||
        host == '[::1]' ||
        RegExp(r'^127\.\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(host);
  }

  static final http.Client _client = IOClient(HttpClient()
    ..badCertificateCallback = (certificate, host, port) => isLocalHost(host));

  /// Reads the versions (and, if exposed, the database and last deploy) from the site's
  /// /system/info/ endpoint.
  static Future<SystemInfo> fetchSystemInfo(String site) async {
    // A site saved with a trailing slash would give "//system/info/", which the sites don't route.
    final base = site.replaceFirst(RegExp(r'/+$'), '');
    final response = await _client.get(Uri.parse('$base/system/info/'));

    if (response.statusCode == 200) {
      return SystemInfo.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);
    }

    throw Exception('Failed to load system info');
  }
}
