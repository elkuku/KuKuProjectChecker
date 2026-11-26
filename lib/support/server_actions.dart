import 'server.dart';

/// Who runs an action on the server: root for host tools, the site user for deploys.
enum ServerActionTarget { host, site }

/// [write] changes state; [destructive] also needs a dry run and a typed confirmation.
enum ServerActionRisk { read, write, destructive }

/// An action the status page may run. It is a fixed argv sent over SSH — never free-form input.
class ServerAction {
  final String id;
  final String label;
  final String description;
  final String confirmation;
  final ServerActionTarget target;
  final ServerActionRisk risk;
  final List<String> argv;

  /// True for `site-remove`: a dry run is shown before the confirmed call.
  final bool dryRun;

  const ServerAction({
    required this.id,
    required this.label,
    required this.description,
    required this.confirmation,
    required this.target,
    required this.risk,
    required this.argv,
    this.dryRun = false,
  });

  static const backup = ServerAction(
    id: 'backup',
    label: 'Run backup',
    description:
        'Writes a new backup set of the databases, secrets and shared site files.',
    confirmation: 'Run a backup now?',
    target: ServerActionTarget.host,
    risk: ServerActionRisk.write,
    argv: ['/usr/local/sbin/server-backup', 'run'],
  );

  static const mailTest = ServerAction(
    id: 'mailTest',
    label: 'Test mail',
    description:
        'Sends one test mail with the server’s configured send-only account.',
    confirmation: 'Send a test mail?',
    target: ServerActionTarget.host,
    risk: ServerActionRisk.write,
    argv: ['/usr/local/sbin/mail-setup', '--test'],
  );

  static const releases = ServerAction(
    id: 'releases',
    label: 'Releases',
    description: 'Lists the site’s releases and which one is live.',
    confirmation: 'List the releases?',
    target: ServerActionTarget.site,
    risk: ServerActionRisk.read,
    argv: ['/usr/local/sbin/site-deploy', '{site}', '--list'],
  );

  static const rollback = ServerAction(
    id: 'rollback',
    label: 'Roll back',
    description:
        'Switches the site back to its previous release. The database is not rolled back.',
    confirmation: 'Roll this site back to its previous release?',
    target: ServerActionTarget.site,
    risk: ServerActionRisk.write,
    argv: ['/usr/local/sbin/site-deploy', '{site}', '--rollback'],
  );

  static const logDeploy = ServerAction(
    id: 'logDeploy',
    label: 'Deploy log',
    description:
        'Reads the last 200 lines of this site’s build and switch log.',
    confirmation: 'Show the deploy log?',
    target: ServerActionTarget.host,
    risk: ServerActionRisk.read,
    argv: ['/usr/local/sbin/server-log', '{site}', '--deploy'],
  );

  static const logApp = ServerAction(
    id: 'logApp',
    label: 'App log',
    description:
        'Reads the last 200 lines of the Symfony log (or PHP error log).',
    confirmation: 'Show the app log?',
    target: ServerActionTarget.host,
    risk: ServerActionRisk.read,
    argv: ['/usr/local/sbin/server-log', '{site}', '--app'],
  );

  static const logPhp = ServerAction(
    id: 'logPhp',
    label: 'PHP log',
    description:
        'Reads the last 200 lines of this site’s PHP-FPM pool messages.',
    confirmation: 'Show the PHP log?',
    target: ServerActionTarget.host,
    risk: ServerActionRisk.read,
    argv: ['/usr/local/sbin/server-log', '{site}', '--php'],
  );

  static const logCaddy = ServerAction(
    id: 'logCaddy',
    label: 'Caddy log',
    description: 'Reads the last 200 lines of this site’s access log.',
    confirmation: 'Show the Caddy log?',
    target: ServerActionTarget.host,
    risk: ServerActionRisk.read,
    argv: ['/usr/local/sbin/server-log', '{site}', '--caddy'],
  );

  static const remove = ServerAction(
    id: 'remove',
    label: 'Remove site',
    description:
        'Deletes the site after a final backup. Its database is kept unless you ask to drop it.',
    confirmation: 'Remove this site?',
    target: ServerActionTarget.host,
    risk: ServerActionRisk.destructive,
    argv: ['/usr/local/sbin/site-remove', '{site}'],
    dryRun: true,
  );

  static const all = [
    backup,
    mailTest,
    releases,
    rollback,
    logDeploy,
    logApp,
    logPhp,
    logCaddy,
    remove,
  ];

  static const serverActions = [backup, mailTest];
  static const siteActions = [
    releases,
    rollback,
    logDeploy,
    logApp,
    logPhp,
    logCaddy,
    remove,
  ];
  static const logActions = [logDeploy, logApp, logPhp, logCaddy];

  /// Whether this action needs a site name (and therefore a site user or site log).
  bool get needsSite => argv.contains('{site}');

  static final _siteName = RegExp(r'^[a-z][a-z0-9-]*$');

  /// The fixed remote command. [site] is validated; no other input reaches the argv.
  List<String> command(String site,
      {bool confirmed = false, bool dropDb = false}) {
    if (needsSite && !_siteName.hasMatch(site)) {
      throw ArgumentError.value(site, 'site', 'Not a KMyServer site name');
    }
    if (dropDb && !(dryRun && confirmed)) {
      throw ArgumentError.value(
          dropDb, 'dropDb', 'Only after a confirmed dry run');
    }

    final args = [
      for (final part in argv)
        if (part == '{site}') site else part
    ];
    // The bare site-remove call is the dry run; --yes is added only on confirmation.
    if (dryRun && confirmed) args.add('--yes');
    if (dropDb) args.add('--drop-db');
    return args;
  }

  /// The SSH command for [server]. Host actions run as root, site actions as the site user.
  List<String> sshArgs(Server server, String site,
      {bool confirmed = false, bool dropDb = false}) {
    if (!server.isKMyServer) {
      throw ArgumentError.value(server.name, 'server', 'No SSH host is set');
    }
    final user = target == ServerActionTarget.site ? site : 'root';
    return server.sshArgs(
      user,
      command(site, confirmed: confirmed, dropDb: dropDb),
    );
  }

  @override
  String toString() => id;
}
