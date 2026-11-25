import 'package:flutter_test/flutter_test.dart';
import 'package:kuku_project_checker/support/push_log.dart';

void main() {
  test('sorts the output of a push to a Plesk repository', () {
    // The output of a real deploy (git splits curl's \r progress into lines).
    final lines = parsePushOutput([
      '** WARNING: connection is not using a post-quantum key exchange algorithm.',
      '** This session may be vulnerable to "store now, decrypt later" attacks.',
      '** The server may need to be upgraded. See https://openssh.com/pq.html',
      'remote:   % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current',
      'remote:                                  Dload  Upload   Total   Spent    Left  Speed',
      'remote: ',
      'remote: remote:   0     0    0     0    0     0      0      0 --:--:-- --:--:-- --:--:--     0',
      'remote:   0     0    0     0    0     0      0      0 --:--:-- --:--:-- --:--:--     0',
      'To maxfielder.elkuku.dev:~/git/maxfielder.git',
      '   72c6c5a..298cc88  master -> master',
    ]);

    expect(lines.where((line) => line.kind != PushLineKind.noise), [
      const PushLine(PushLineKind.warning,
          'SSH: the server does not support post-quantum key exchange (see openssh.com/pq.html)'),
      const PushLine(
          PushLineKind.target, 'To maxfielder.elkuku.dev:~/git/maxfielder.git'),
      const PushLine(
          PushLineKind.updated, '72c6c5a..298cc88  master -> master'),
    ]);
  });

  test('keeps server messages and marks errors', () {
    final lines = parsePushOutput([
      'Enumerating objects: 5, done.',
      'remote: Deploying to /httpdocs',
      'remote: error: composer install failed',
      ' ! [rejected]        master -> master (fetch first)',
      'error: failed to push some refs to \'server:~/git/shop.git\'',
      'Permission denied (publickey).',
      ' * [new branch]      feature -> feature',
      'Everything up-to-date',
    ]);

    expect([
      for (final line in lines) line.kind
    ], [
      PushLineKind.progress,
      PushLineKind.server,
      PushLineKind.error,
      PushLineKind.error,
      PushLineKind.error,
      PushLineKind.error,
      PushLineKind.updated,
      PushLineKind.updated,
    ]);
    expect(lines[1].text, 'Deploying to /httpdocs');
  });

  test('strips terminal colors', () {
    expect(parsePushOutput(['\x1B[32mremote: done\x1B[0m']).single,
        const PushLine(PushLineKind.server, 'done'));
  });

  group('KMyServer deploy', () {
    // Real output of a push to a KMyServer site (site-deploy in the post-receive hook).
    const ok = [
      'remote: >>>=============================================================================',
      'remote: Wed Nov 25 15:23:00 UTC 2026',
      'remote: **** Release releases/20261125-152300 from 33abb4d Paginate the user list',
      'remote: **** Installing composer dependencies...',
      'remote: **** Switching to releases/20261125-152300',
      'remote: <<<=============================================================================',
      'To ssh://localhost:2222/srv/sites/test2/repo.git',
      '   1a2b3c4..33abb4d  master -> master',
    ];
    const failed = [
      'remote: >>>=============================================================================',
      'remote: **** Executing db migrations...',
      'remote: !!!! deploy FAILED (line 93): releases/20261125-144122 removed, still live: releases/20261125-144119',
      'remote: <<<=============================================================================',
      '   1a2b3c4..5d6e7f8  master -> master',
    ];

    test('shows the steps and hides the frame of the run', () {
      final lines = parsePushOutput(ok)
          .where((line) => line.kind != PushLineKind.noise)
          .toList();

      expect(lines.take(4), [
        const PushLine(PushLineKind.server, 'Wed Nov 25 15:23:00 UTC 2026'),
        const PushLine(PushLineKind.step,
            'Release releases/20261125-152300 from 33abb4d Paginate the user list'),
        const PushLine(PushLineKind.step, 'Installing composer dependencies'),
        const PushLine(
            PushLineKind.step, 'Switching to releases/20261125-152300'),
      ]);
      expect(
          parsePushOutput(failed).where((l) => l.kind == PushLineKind.error), [
        const PushLine(PushLineKind.error,
            '!!!! deploy FAILED (line 93): releases/20261125-144122 removed, still live: releases/20261125-144119'),
      ]);
    });

    test('reads how the deploy ended', () {
      expect(serverDeployResult(ok).result, ServerDeploy.finished);

      final fail = serverDeployResult(failed);
      expect(fail.result, ServerDeploy.failed);
      expect(fail.detail, contains('still live: releases/20261125-144119'));

      expect(serverDeployResult(ok.take(3)).result, ServerDeploy.unfinished);
      expect(
          serverDeployResult(['To server:~/git/shop.git', 'remote: Deploying'])
              .result,
          ServerDeploy.unknown);
      // A later run counts: a failed run followed by a good one.
      expect(
          serverDeployResult([...failed, ...ok]).result, ServerDeploy.finished);
    });
  });
}
