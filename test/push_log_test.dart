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
}
