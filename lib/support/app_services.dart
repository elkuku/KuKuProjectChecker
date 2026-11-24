import 'dart:convert';

import 'package:http/http.dart' as http;

import '../widgets/site_dialog.dart' as site_dialog;
import 'deployer.dart';
import 'local_versions.dart';
import 'open_in.dart';
import 'repo_changes.dart';
import 'repo_status.dart';
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

  /// The installed apps that can open a repository.
  final List<(OpenInTarget, String)> openInTargets;

  /// The folder chooser for a site's local repository.
  final site_dialog.PickFolder pickFolder;

  AppServices({
    Settings? settings,
    Future<SystemInfo> Function(String url)? fetchInfo,
    Future<RepoStatus> Function(String repoPath, String deployRemote)?
        checkRepo,
    Future<List<(String, String)>> Function(String repoPath)? listRemotes,
    RepoChanges Function(String repoPath)? repoChanges,
    Future<LocalVersions> Function(String repoPath)? readLocal,
    PushFunction? push,
    List<(OpenInTarget, String)>? openInTargets,
    site_dialog.PickFolder? pickFolder,
  })  : settings = settings ?? Settings(),
        fetchInfo = fetchInfo ?? fetchSystemInfo,
        checkRepo = checkRepo ??
            ((repoPath, deployRemote) =>
                RepoStatus.check(repoPath, deployRemote: deployRemote)),
        listRemotes = listRemotes ?? RepoStatus.remotes,
        repoChanges = repoChanges ?? RepoChanges.new,
        readLocal = readLocal ?? LocalVersions.read,
        push = push ?? Deployer().push,
        openInTargets = openInTargets ?? OpenInTarget.available(),
        pickFolder = pickFolder ?? site_dialog.pickFolder;

  /// Reads the versions (and, if exposed, the database and last deploy) from the site's
  /// /system/info/ endpoint.
  static Future<SystemInfo> fetchSystemInfo(String site) async {
    // A site saved with a trailing slash would give "//system/info/", which the sites don't route.
    final base = site.replaceFirst(RegExp(r'/+$'), '');
    final response = await http.get(Uri.parse('$base/system/info/'));

    if (response.statusCode == 200) {
      return SystemInfo.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);
    }

    throw Exception('Failed to load system info');
  }
}
