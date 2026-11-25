/// A site on a KMyServer server (github.com/elkuku/KMyServer): its deploy remote is the
/// site user's repository, `<site>@<host>:/srv/sites/<site>/repo.git`
/// (or `ssh://<site>@<host>[:port]/srv/sites/<site>/repo.git`).
class KMyServerSite {
  /// The site's name, which is also its user on the server.
  final String name;
  final String host;
  final int? port;

  const KMyServerSite({required this.name, required this.host, this.port});

  static final _scp =
      RegExp(r'^([a-z][a-z0-9-]*)@([^:/]+):(/srv/sites/[^/]+/repo\.git)/?$');
  static final _path = RegExp(r'^/srv/sites/([a-z][a-z0-9-]*)/repo\.git/?$');

  /// The site behind a git remote URL, or null if the remote is not a KMyServer site.
  static KMyServerSite? fromRemoteUrl(String url) {
    String? user, host, path;
    int? port;

    if (url.startsWith('ssh://')) {
      final uri = Uri.tryParse(url);
      if (uri == null) return null;
      user = uri.userInfo;
      host = uri.host;
      path = uri.path;
      port = uri.hasPort ? uri.port : null;
    } else {
      final match = _scp.firstMatch(url);
      if (match == null) return null;
      (user, host, path) = (match[1], match[2], match[3]);
    }

    final site = _path.firstMatch(path ?? '')?[1];
    // The site user pushes to its own repository only.
    if (site == null || site != user || host == null || host.isEmpty) {
      return null;
    }

    return KMyServerSite(name: site, host: host, port: port);
  }

  /// The arguments for `ssh` that run site-deploy as the site user. The site user's PATH
  /// lacks /usr/local/sbin, so the full path is used.
  List<String> siteDeployArgs(List<String> options) => [
        if (port != null) ...['-p', '$port'],
        '$name@$host',
        '/usr/local/sbin/site-deploy',
        name,
        ...options,
      ];

  @override
  bool operator ==(Object other) =>
      other is KMyServerSite &&
      other.name == name &&
      other.host == host &&
      other.port == port;

  @override
  int get hashCode => Object.hash(name, host, port);

  @override
  String toString() => '$name@$host${port == null ? '' : ':$port'}';
}
