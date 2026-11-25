/// A server the sites can deploy to. Every site reaches it through a git remote of the same
/// name in its local repository (e.g. `elkuku.dev` for the Plesk server, `kmyserver` for the
/// new one), so switching the active server switches the deploy remote of all sites.
class Server {
  final String name;

  /// The git remote the sites use for this server.
  final String remote;

  /// For a KMyServer server (github.com/elkuku/KMyServer): the SSH host of the server, for
  /// creating sites (as root) and cloning them (as the site user). Empty for other servers.
  final String sshHost;

  /// The SSH port, if not 22 (e.g. 2222 for the local test VM).
  final int? sshPort;

  const Server({
    required this.name,
    required this.remote,
    this.sshHost = '',
    this.sshPort,
  });

  /// New sites can be created on it from a template.
  bool get isKMyServer => sshHost.isNotEmpty;

  /// The `ssh` arguments that reach [user] on this server, followed by [command].
  List<String> sshArgs(String user, List<String> command) => [
        if (sshPort != null) ...['-p', '$sshPort'],
        '$user@$sshHost',
        ...command,
      ];

  /// The git URL of a site's repository on this KMyServer server.
  String siteRepoUrl(String site) => sshPort == null
      ? '$site@$sshHost:/srv/sites/$site/repo.git'
      : 'ssh://$site@$sshHost:$sshPort/srv/sites/$site/repo.git';

  /// An error for a git remote name, or null if [text] can be one.
  static String? remoteError(String text) {
    text = text.trim();
    if (text.isEmpty) return 'Enter the name of the git remote';
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$').hasMatch(text)) {
      return 'Letters, digits, ".", "_" and "-" only';
    }

    return null;
  }

  factory Server.fromJson(Map<String, dynamic> json) {
    String text(String key) => json[key] is String ? json[key] : '';

    return Server(
      name: text('name'),
      remote: text('remote'),
      sshHost: text('sshHost'),
      sshPort: json['sshPort'] is int ? json['sshPort'] : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'remote': remote,
        if (sshHost.isNotEmpty) 'sshHost': sshHost,
        if (sshPort != null) 'sshPort': sshPort,
      };

  @override
  bool operator ==(Object other) =>
      other is Server &&
      other.name == name &&
      other.remote == remote &&
      other.sshHost == sshHost &&
      other.sshPort == sshPort;

  @override
  int get hashCode => Object.hash(name, remote, sshHost, sshPort);
}
