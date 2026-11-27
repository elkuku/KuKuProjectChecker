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

  /// The canonical base address of this server, e.g. `https://vm.localhost:8443`.
  /// A project only supplies a subdomain in front of its host.
  final String baseUrl;

  /// Legacy fields, read from older settings but never written for new servers.
  /// [domainSuffix] was `<site name>.<domainSuffix>`; [sitePort] was separate.
  final String domainSuffix;
  final int? sitePort;

  const Server({
    required this.name,
    required this.remote,
    this.sshHost = '',
    this.sshPort,
    this.baseUrl = '',
    this.domainSuffix = '',
    this.sitePort,
  });

  /// New sites can be created on it from a template.
  bool get isKMyServer => sshHost.isNotEmpty;

  /// The configured URL, or the one derived from legacy fields. Old settings stay
  /// usable; editing a server writes [baseUrl] only.
  String get effectiveBaseUrl =>
      baseUrl.isNotEmpty ? baseUrl : _legacyBaseUrl;

  /// False until a valid base URL is configured; such servers are flagged in the UI.
  bool get hasUrl => urlError(effectiveBaseUrl) == null;

  /// The `ssh` arguments that reach [user] on this server, followed by [command].
  List<String> sshArgs(String user, List<String> command) => [
        if (sshPort != null) ...['-p', '$sshPort'],
        '$user@$sshHost',
        ...command,
      ];

  String get _legacyBaseUrl => domainSuffix.isEmpty
      ? ''
      : 'https://$domainSuffix${sitePort == null ? '' : ':$sitePort'}';

  /// The host of a project environment: the project's subdomain in front of this
  /// server's host. A full domain from an older setting stays unchanged.
  String siteDomain(String subdomainOrDomain) {
    final value = subdomainOrDomain.trim();
    if (value.isEmpty) return '';
    final host = effectiveBaseUrl.isEmpty
        ? domainSuffix
        : Uri.parse(effectiveBaseUrl).host;
    if (host.isEmpty) return value;
    if (value == host ||
        value.endsWith('.$host') ||
        (domainSuffix.isNotEmpty &&
            (value == domainSuffix || value.endsWith('.$domainSuffix'))) ||
        // A legacy site on another domain is still a full domain, not a subdomain.
        value.contains('.')) {
      return value;
    }

    return '$value.$host';
  }

  /// The address of a project environment on this server. [subdomainOrDomain] is a
  /// subdomain for new records; a legacy full domain is accepted unchanged so old
  /// settings keep working. Only the scheme, host and port of the base URL are used.
  String siteUrl(String subdomainOrDomain) {
    final host = siteDomain(subdomainOrDomain);
    if (host.isEmpty) return '';
    final base = effectiveBaseUrl;
    if (base.isEmpty) {
      return 'https://$host${sitePort == null ? '' : ':$sitePort'}';
    }

    final uri = Uri.parse(base);
    return '${uri.scheme}://$host${uri.hasPort ? ':${uri.port}' : ''}';
  }

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

  /// A server needs a full http(s) base URL so projects only add a subdomain.
  static String? urlError(String text) {
    text = text.trim();
    if (text.isEmpty || text == 'https://' || text == 'http://') {
      return 'Enter the base URL of the server';
    }
    final uri = Uri.tryParse(text);
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty) {
      return 'Use a full address, like https://vm.example.com';
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
      baseUrl: text('baseUrl'),
      domainSuffix: text('domainSuffix'),
      sitePort: json['sitePort'] is int ? json['sitePort'] : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'remote': remote,
        if (sshHost.isNotEmpty) 'sshHost': sshHost,
        if (sshPort != null) 'sshPort': sshPort,
        if (baseUrl.isNotEmpty) 'baseUrl': baseUrl,
        // Keep an untouched legacy server usable when another server is saved.
        // Editing it writes baseUrl instead and drops these fields.
        if (baseUrl.isEmpty && domainSuffix.isNotEmpty)
          'domainSuffix': domainSuffix,
        if (baseUrl.isEmpty && sitePort != null) 'sitePort': sitePort,
      };

  @override
  bool operator ==(Object other) =>
      other is Server &&
      other.name == name &&
      other.remote == remote &&
      other.sshHost == sshHost &&
      other.sshPort == sshPort &&
      other.baseUrl == baseUrl &&
      other.domainSuffix == domainSuffix &&
      other.sitePort == sitePort;

  @override
  int get hashCode => Object.hash(
      name, remote, sshHost, sshPort, baseUrl, domainSuffix, sitePort);
}
