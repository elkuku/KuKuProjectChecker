import 'package:flutter_test/flutter_test.dart';
import 'package:kuku_project_checker/support/server.dart';
import 'package:kuku_project_checker/support/server_actions.dart';

void main() {
  const vm = Server(
      name: 'Test VM',
      remote: 'vm',
      sshHost: 'localhost',
      sshPort: 2222);

  group('ServerAction', () {
    test('host actions run as root with fixed argv', () {
      expect(
        ServerAction.backup.sshArgs(vm, ''),
        ['-p', '2222', 'root@localhost', '/usr/local/sbin/server-backup', 'run'],
      );
      expect(
        ServerAction.mailTest.sshArgs(vm, ''),
        [
          '-p',
          '2222',
          'root@localhost',
          '/usr/local/sbin/mail-setup',
          '--test'
        ],
      );
    });

    test('site actions run as the site user', () {
      expect(
        ServerAction.releases.sshArgs(vm, 'starter'),
        [
          '-p',
          '2222',
          'starter@localhost',
          '/usr/local/sbin/site-deploy',
          'starter',
          '--list'
        ],
      );
      expect(
        ServerAction.rollback.sshArgs(vm, 'starter').last,
        '--rollback',
      );
    });

    test('log viewer is allowlisted per kind', () {
      for (final (action, option) in [
        (ServerAction.logDeploy, '--deploy'),
        (ServerAction.logApp, '--app'),
        (ServerAction.logPhp, '--php'),
        (ServerAction.logCaddy, '--caddy'),
      ]) {
        expect(
          action.sshArgs(vm, 'starter'),
          [
            '-p',
            '2222',
            'root@localhost',
            '/usr/local/sbin/server-log',
            'starter',
            option
          ],
        );
      }
    });

    test('site-remove is a dry run before --yes', () {
      expect(ServerAction.remove.command('starter'), [
        '/usr/local/sbin/site-remove',
        'starter'
      ]);
      expect(ServerAction.remove.command('starter', confirmed: true), [
        '/usr/local/sbin/site-remove',
        'starter',
        '--yes'
      ]);
      expect(
        ServerAction.remove.command('starter',
            confirmed: true, dropDb: true),
        ['/usr/local/sbin/site-remove', 'starter', '--yes', '--drop-db'],
      );
      expect(
        () => ServerAction.remove.command('starter', dropDb: true),
        throwsArgumentError,
      );
    });

    test('rejects an invalid site name or a server without SSH', () {
      for (final site in ['', '../etc', 'Starter', 'a/b', '-x']) {
        expect(
          () => ServerAction.releases.command(site),
          throwsArgumentError,
          reason: site,
        );
      }
      expect(() => ServerAction.logApp.command('../etc'), throwsArgumentError);
      expect(
        () => ServerAction.backup.sshArgs(
            const Server(name: 'Plesk', remote: 'elkuku.dev'), ''),
        throwsArgumentError,
      );
    });

    test('the allowlist is explicit', () {
      expect(ServerAction.all.length, 9);
      expect(ServerAction.all, contains(ServerAction.remove));
      expect(ServerAction.serverActions, [ServerAction.backup, ServerAction.mailTest]);
      expect(ServerAction.logActions.length, 4);
    });
  });
}
