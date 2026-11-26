import 'package:flutter_test/flutter_test.dart';
import 'package:kuku_project_checker/support/db_backup.dart';
import 'package:kuku_project_checker/support/server.dart';

const vm = Server(
  name: 'Test VM',
  remote: 'vm',
  sshHost: 'localhost',
  sshPort: 2222,
);

void main() {
  test('reads dated sets and rejects unsafe dump names', () async {
    final calls = <List<String>>[];
    final choices = await ServerDbBackups.fetch(
      vm,
      (executable, arguments, onOutput, {workingDirectory}) async {
        calls.add(arguments);
        onOutput(
          '{"sets":[{'
          '"date":"2026-11-26","dumps":["pg-good.dump","../bad.dump",'
          '"bad;sh.dump","pg-shop.dump"]},'
          '{"date":"not-a-date","dumps":["pg-ignored.dump"]}'
          ']}',
        );
        return 0;
      },
    );

    expect(calls, [
      [
        '-p',
        '2222',
        'root@localhost',
        '/usr/local/sbin/site-db-backups',
        'list',
      ],
    ]);
    expect(choices, [
      const DbDumpChoice(date: '2026-11-26', file: 'pg-good.dump'),
      const DbDumpChoice(date: '2026-11-26', file: 'pg-shop.dump'),
    ]);
    expect(
        choices.first.path, '/var/backups/server/db/2026-11-26/pg-good.dump');
    expect(choices.first.label, '2026-11-26 · pg-good.dump');
  });

  test('an empty report means no dumps', () async {
    final choices = await ServerDbBackups.fetch(
      vm,
      (_, __, onOutput, {workingDirectory}) async {
        onOutput('{"sets":[]}');
        return 0;
      },
    );
    expect(choices, isEmpty);
  });

  test('a failed read is reported', () async {
    expect(
      () => ServerDbBackups.fetch(
        vm,
        (_, __, onOutput, {workingDirectory}) async {
          onOutput('site-db-backups: denied');
          return 1;
        },
      ),
      throwsStateError,
    );
  });
}
