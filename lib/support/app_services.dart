import 'dart:convert';

import 'package:http/http.dart' as http;

import 'deployer.dart';
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
  final Future<RepoStatus> Function(String repoPath) checkRepo;
  final RepoChanges Function(String repoPath) repoChanges;

  /// Pushes a branch to the deploy remote.
  final PushFunction push;

  /// The installed apps that can open a repository.
  final List<(OpenInTarget, String)> openInTargets;

  AppServices({
    Settings? settings,
    Future<SystemInfo> Function(String url)? fetchInfo,
    Future<RepoStatus> Function(String repoPath)? checkRepo,
    RepoChanges Function(String repoPath)? repoChanges,
    PushFunction? push,
    List<(OpenInTarget, String)>? openInTargets,
  })  : settings = settings ?? Settings(),
        fetchInfo = fetchInfo ?? fetchSystemInfo,
        checkRepo = checkRepo ?? RepoStatus.check,
        repoChanges = repoChanges ?? RepoChanges.new,
        push = push ?? Deployer().push,
        openInTargets = openInTargets ?? OpenInTarget.available();

  /// Reads the Symfony and PHP versions from the site's /system/info/ endpoint.
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
