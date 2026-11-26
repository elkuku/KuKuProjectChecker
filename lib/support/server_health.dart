/// The read-only report from `server-health --json` (schema 1).
///
/// [problems] is the number of lines the text report marks with `!!`; [warnings] expands those
/// into readable messages for the status page (a site can have several reasons on one line).
class ServerHealth {
  final int schema;
  final DateTime? generatedAt;
  final String host;
  final int problems;
  final SystemHealth system;
  final List<ServiceHealth> services;
  final List<String> failedUnits;
  final List<DiskHealth> disk;
  final MemoryHealth memory;
  final UpdatesHealth updates;
  final SecurityHealth security;
  final BackupHealth backup;
  final MailHealth mail;
  final List<SiteHealth> sites;

  const ServerHealth({
    required this.schema,
    required this.generatedAt,
    required this.host,
    required this.problems,
    required this.system,
    required this.services,
    required this.failedUnits,
    required this.disk,
    required this.memory,
    required this.updates,
    required this.security,
    required this.backup,
    required this.mail,
    required this.sites,
  });

  factory ServerHealth.fromJson(Map<String, dynamic> json) {
    final schema = _int(json['schema']);
    if (schema != 1) {
      throw FormatException('Unknown server-health schema: $schema');
    }

    return ServerHealth(
      schema: schema,
      generatedAt: _date(json['generatedAt']),
      host: _string(json['host']),
      problems: _int(json['problems']),
      system: SystemHealth.fromJson(_map(json['system'])),
      services: [
        for (final value in _list(json['services']))
          ServiceHealth.fromJson(_map(value)),
      ],
      failedUnits: _strings(json['failedUnits']),
      disk: [
        for (final value in _list(json['disk'])) DiskHealth.fromJson(_map(value)),
      ],
      memory: MemoryHealth.fromJson(_map(json['memory'])),
      updates: UpdatesHealth.fromJson(_map(json['updates'])),
      security: SecurityHealth.fromJson(_map(json['security'])),
      backup: BackupHealth.fromJson(_map(json['backup'])),
      mail: MailHealth.fromJson(_map(json['mail'])),
      sites: [
        for (final value in _list(json['sites'])) SiteHealth.fromJson(_map(value)),
      ],
    );
  }

  /// Everything that needs attention, ready to show at the top of the page.
  List<String> get warnings => [
        if (system.rebootRequired) 'Reboot required',
        for (final unit in failedUnits) 'Failed unit: $unit',
        for (final service in services)
          if (!service.ok) '${service.name} is ${service.state}',
        for (final entry in disk)
          if (entry.percent >= 85) '${entry.mount} is ${entry.percent}% full',
        if (!backup.ok)
          backup.lastOk.isEmpty
              ? 'No backup yet'
              : 'Backup stale since ${backup.lastOk}',
        if (!mail.configured) 'No outgoing mail configured',
        if (mail.configured && !mail.ok) 'Last mail failed',
        for (final site in sites)
          for (final reason in site.problems) '${site.domain}: $reason',
      ];
}

class SystemHealth {
  final String os;
  final String kernel;
  final String uptime;
  final bool rebootRequired;
  final List<String> rebootPackages;

  const SystemHealth({
    required this.os,
    required this.kernel,
    required this.uptime,
    required this.rebootRequired,
    required this.rebootPackages,
  });

  factory SystemHealth.fromJson(Map<String, dynamic> json) => SystemHealth(
        os: _string(json['os']),
        kernel: _string(json['kernel']),
        uptime: _string(json['uptime']),
        rebootRequired: _bool(json['rebootRequired']),
        rebootPackages: _strings(json['rebootPackages']),
      );
}

class ServiceHealth {
  final String name;
  final String state;
  final bool ok;

  const ServiceHealth(
      {required this.name, required this.state, required this.ok});

  factory ServiceHealth.fromJson(Map<String, dynamic> json) => ServiceHealth(
        name: _string(json['name']),
        state: _string(json['state']),
        ok: _bool(json['ok']),
      );
}

class DiskHealth {
  final String mount;
  final String size;
  final String used;
  final String available;
  final int percent;

  const DiskHealth({
    required this.mount,
    required this.size,
    required this.used,
    required this.available,
    required this.percent,
  });

  factory DiskHealth.fromJson(Map<String, dynamic> json) => DiskHealth(
        mount: _string(json['mount']),
        size: _string(json['size']),
        used: _string(json['used']),
        available: _string(json['available']),
        percent: _int(json['percent']),
      );
}

class MemoryHealth {
  final String total;
  final String used;

  const MemoryHealth({required this.total, required this.used});

  factory MemoryHealth.fromJson(Map<String, dynamic> json) =>
      MemoryHealth(total: _string(json['total']), used: _string(json['used']));
}

class UpdatesHealth {
  final int pending;
  final String lastUnattended;

  const UpdatesHealth({required this.pending, required this.lastUnattended});

  factory UpdatesHealth.fromJson(Map<String, dynamic> json) => UpdatesHealth(
        pending: _int(json['pending']),
        lastUnattended: _string(json['lastUnattended']),
      );
}

class SecurityHealth {
  final int bannedNow;
  final int bannedTotal;
  final List<int> listening;
  final List<int> firewall;

  const SecurityHealth({
    required this.bannedNow,
    required this.bannedTotal,
    required this.listening,
    required this.firewall,
  });

  factory SecurityHealth.fromJson(Map<String, dynamic> json) => SecurityHealth(
        bannedNow: _int(json['bannedNow']),
        bannedTotal: _int(json['bannedTotal']),
        listening: _ints(json['listening']),
        firewall: _ints(json['firewall']),
      );
}

class BackupHealth {
  final bool ok;
  final String lastOk;
  final int ageHours;
  final int sets;

  const BackupHealth({
    required this.ok,
    required this.lastOk,
    required this.ageHours,
    required this.sets,
  });

  factory BackupHealth.fromJson(Map<String, dynamic> json) => BackupHealth(
        ok: _bool(json['ok']),
        lastOk: _string(json['lastOk']),
        ageHours: _int(json['ageHours']),
        sets: _int(json['sets']),
      );
}

class MailHealth {
  final bool configured;
  final bool ok;
  final String last;

  const MailHealth(
      {required this.configured, required this.ok, required this.last});

  factory MailHealth.fromJson(Map<String, dynamic> json) => MailHealth(
        configured: _bool(json['configured']),
        ok: _bool(json['ok']),
        last: _string(json['last']),
      );
}

class SiteHealth {
  /// The site user / folder name; older reports only had the domain, so fall back to its label.
  final String name;
  final String domain;
  final int http;
  final int? certificateDays;
  final String issuer;
  final String release;
  final String revision;
  final DeployHealth deploy;
  final int critical24h;
  final String? lastCritical;
  final List<String> problems;

  const SiteHealth({
    required this.name,
    required this.domain,
    required this.http,
    required this.certificateDays,
    required this.issuer,
    required this.release,
    required this.revision,
    required this.deploy,
    required this.critical24h,
    required this.lastCritical,
    required this.problems,
  });

  factory SiteHealth.fromJson(Map<String, dynamic> json) {
    final cert = _map(json['certificate']);
    final last = _string(json['lastCritical']);
    final domain = _string(json['domain']);
    final name = _string(json['name']);
    return SiteHealth(
      name: name.isEmpty ? domain.split('.').first : name,
      domain: domain,
      http: _int(json['http']),
      certificateDays: _intOrNull(cert['days']),
      issuer: _string(cert['issuer']),
      release: _string(json['release']),
      revision: _string(json['revision']),
      deploy: DeployHealth.fromJson(_map(json['deploy'])),
      critical24h: _int(json['critical24h']),
      lastCritical: last.isEmpty ? null : last,
      problems: _strings(json['problems']),
    );
  }
}

class DeployHealth {
  final String state;
  final String when;

  const DeployHealth({required this.state, required this.when});

  factory DeployHealth.fromJson(Map<String, dynamic> json) =>
      DeployHealth(state: _string(json['state']), when: _string(json['when']));

  bool get failed => state == 'failed';
}

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

List<Object?> _list(Object? value) =>
    value is List ? List<Object?>.from(value) : <Object?>[];

String _string(Object? value) => value is String ? value : '';

int _int(Object? value, [int fallback = 0]) {
  if (value is num) return value.toInt();
  return int.tryParse(_string(value)) ?? fallback;
}

int? _intOrNull(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse(_string(value));
}

bool _bool(Object? value) => value == true;

List<String> _strings(Object? value) => _list(value).map(_string).toList();

List<int> _ints(Object? value) => [
      for (final item in _list(value)) _int(item),
    ];

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;
