import 'dart:convert';
import 'dart:io';

import 'repo_status.dart';

/// Pushes a branch to a remote; reports each output line, returns the exit code.
typedef PushFunction = Future<int> Function(String repoPath, String remote,
    String branch, void Function(String line) onOutput);

/// Deploys a project by pushing its branch to the deploy remote; the server (e.g. Plesk)
/// deploys on push.
class Deployer {
  /// Pushes [branch] to [remote] in [repoPath]. Each line of git's output goes to
  /// [onOutput]; returns git's exit code.
  Future<int> push(String repoPath, String remote, String branch,
      void Function(String line) onOutput) async {
    final process = await Process.start(
      'git',
      ['-C', RepoStatus.expandHome(repoPath), 'push', remote, branch],
      environment: gitEnvironment(Platform.environment),
    );

    // git reports progress and the server's messages on stderr.
    final done = Future.wait([
      for (final stream in [process.stdout, process.stderr])
        stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .forEach(onOutput),
    ]);
    final exitCode = await process.exitCode;
    await done;

    return exitCode;
  }

  /// git and ssh can't ask for a passphrase on a terminal here, so a graphical askpass
  /// program asks instead, if one is installed (ksshaskpass on KDE).
  static Map<String, String> gitEnvironment(Map<String, String> environment,
      {bool Function(String path)? exists}) {
    final check = exists ?? (path) => File(path).existsSync();
    final askpass = environment['SSH_ASKPASS'] ??
        [
          '/usr/bin/ksshaskpass',
          '/usr/lib/ssh/ssh-askpass',
          '/usr/libexec/openssh/ssh-askpass',
          '/usr/bin/ssh-askpass',
        ].where(check).firstOrNull;

    return {
      // Never wait for input on a terminal nobody sees.
      'GIT_TERMINAL_PROMPT': '0',
      if (askpass != null) ...{
        'SSH_ASKPASS': askpass,
        'SSH_ASKPASS_REQUIRE': 'force',
      },
    };
  }
}
