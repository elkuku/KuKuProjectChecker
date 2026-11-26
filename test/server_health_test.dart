import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kuku_project_checker/support/server.dart';
import 'package:kuku_project_checker/support/server_api.dart';
import 'package:kuku_project_checker/support/server_health.dart';

Map<String, dynamic> _report({bool healthy = false}) => {
      'schema': 1,
      'generatedAt': '2026-11-26T09:00:00Z',
      'host': 'test-vm',
      'problems': healthy ? 0 : 5,
      'system': {
        'os': 'Debian 13.8, kernel 6.12',
        'kernel': '6.12',
        'uptime': ' 09:00:00 up  1:42,  1 user',
        'rebootRequired': false,
        'rebootPackages': [],
      },
      'services': [
        {
          'name': 'caddy',
          'state': healthy ? 'active' : 'inactive',
          'ok': healthy,
        },
        {'name': 'ssh', 'state': 'active', 'ok': true},
      ],
      'failedUnits': healthy ? [] : ['mail-setup.service'],
      'disk': [
        {
          'mount': '/',
          'size': '80G',
          'used': healthy ? '12G' : '70G',
          'available': healthy ? '68G' : '10G',
          'percent': healthy ? 15 : 88,
        },
      ],
      'memory': {'total': '2.0Gi', 'used': healthy ? '380Mi' : '1.4Gi'},
      'updates': {
        'pending': healthy ? 0 : 12,
        'lastUnattended': '2026-11-26 06:12',
      },
      'security': {
        'bannedNow': 0,
        'bannedTotal': 7,
        'listening': [22, 80, 443],
        'firewall': [22, 80, 443],
      },
      'backup': {
        'ok': healthy,
        'lastOk': healthy ? '2026-11-26 02:30' : '2026-11-24 02:30',
        'ageHours': healthy ? 7 : 54,
        'sets': 14,
      },
      'mail': {
        'configured': true,
        'ok': healthy,
        'last': healthy ? '2026-11-26 06:00' : '',
      },
      'sites': [
        {
          'name': 'starter',
          'domain': 'starter.localhost',
          'http': healthy ? 200 : 0,
          'certificate': {'days': healthy ? 0 : null, 'issuer': 'Caddy Local Authority'},
          'release': '20261125-1412',
          'revision': '33abb4d',
          'deploy': {
            'state': healthy ? 'ok' : 'failed',
            'when': '2026-11-25 14:12',
          },
          'critical24h': healthy ? 0 : 2,
          'lastCritical': healthy ? null : 'Database connection failed',
          'problems': healthy ? [] : ['http 000', 'last deploy failed'],
        },
      ],
    };

void main() {
  group('ServerHealth', () {
    test('reads the v1 report', () {
      final health = ServerHealth.fromJson(_report());

      expect(health.schema, 1);
      expect(health.generatedAt, DateTime.utc(2026, 11, 26, 9));
      expect(health.host, 'test-vm');
      expect(health.problems, 5);
      expect(health.services.length, 2);
      expect(health.services.first.ok, isFalse);
      expect(health.disk.single.percent, 88);
      expect(health.security.listening, [22, 80, 443]);
      expect(health.backup.ok, isFalse);
      expect(health.sites.single.deploy.failed, isTrue);
      expect(health.sites.single.certificateDays, isNull);
      expect(health.sites.single.lastCritical, 'Database connection failed');
    });

    test('flattens warnings for the status page', () {
      final warnings = ServerHealth.fromJson(_report()).warnings;

      expect(warnings, contains('Failed unit: mail-setup.service'));
      expect(warnings, contains('caddy is inactive'));
      expect(warnings, contains('/ is 88% full'));
      expect(warnings, contains('Backup stale since 2026-11-24 02:30'));
      expect(warnings, contains('Last mail failed'));
      expect(warnings, contains('starter.localhost: http 000'));
      expect(warnings, contains('starter.localhost: last deploy failed'));
    });

    test('a healthy report has no warnings', () {
      final health = ServerHealth.fromJson(_report(healthy: true));

      expect(health.problems, 0);
      expect(health.warnings, isEmpty);
      expect(health.sites.single.problems, isEmpty);
      expect(health.sites.single.deploy.failed, isFalse);
    });

    test('refuses an unknown schema', () {
      final json = _report();
      json['schema'] = 2;
      expect(() => ServerHealth.fromJson(json), throwsFormatException);
    });
  });

  group('ServerApi', () {
    const vm = Server(
        name: 'Test VM',
        remote: 'vm',
        sshHost: 'localhost',
        sshPort: 2222);

    test('runs the installed script as root with the server\'s SSH port', () async {
      final calls = <String>[];
      final api = ServerApi(
        run: (executable, arguments, onOutput, {workingDirectory}) async {
          calls.add('$executable ${arguments.join(' ')}');
          // ssh notices on stderr are merged with stdout by runCommand.
          onOutput('Warning: no PTY');
          onOutput(jsonEncode(_report(healthy: true)));
          return 0;
        },
      );

      final health = await api.health(vm);

      expect(calls, [
        'ssh -p 2222 root@localhost /usr/local/sbin/server-health --json'
      ]);
      expect(health.host, 'test-vm');
      expect(health.warnings, isEmpty);
    });

    test('reports a failed command and missing JSON', () async {
      final failing = ServerApi(
        run: (_, __, onOutput, {workingDirectory}) async {
          onOutput('Permission denied');
          return 255;
        },
      );
      expect(
        () => failing.health(vm),
        throwsA(isA<Exception>().having(
            (error) => error.toString(), 'message', contains('exit 255'))),
      );

      final noJson = ServerApi(
        run: (_, __, onOutput, {workingDirectory}) async {
          onOutput('Permission denied');
          return 0;
        },
      );
      expect(() => noJson.health(vm), throwsFormatException);
    });

    test('rejects a server without SSH', () async {
      final api = ServerApi(
        run: (_, __, ___, {workingDirectory}) async => 0,
      );
      expect(
          () => api.health(const Server(name: 'Plesk', remote: 'elkuku.dev')),
          throwsArgumentError);
    });
  });
}
