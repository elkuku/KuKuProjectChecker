import 'server.dart';

/// One environment of a project: local Symfony, Plesk prod, a KMyServer, a VM, …
/// The [server] is a [Server.name], or empty for an environment without a server entry.
class SiteTarget {
  static const autoDeploy = '';
  static const noDeploy = '-';

  final String name;
  final String server;
  final String url;
  final String deployRemote;

  const SiteTarget({
    required this.name,
    this.server = '',
    required this.url,
    this.deployRemote = autoDeploy,
  });

  /// The host of [url], used to match a server health report to this environment.
  String get domain => Uri.tryParse(url)?.host ?? '';

  static String? nameError(String text) =>
      text.trim().isEmpty ? 'Enter a name for this environment' : null;

  static String? urlError(String text) => Site.urlError(text);

  static String? deployRemoteError(String text) {
    text = text.trim();
    if (text == autoDeploy || text == noDeploy) return null;
    return Server.remoteError(text);
  }

  factory SiteTarget.fromJson(Map<String, dynamic> json) {
    String text(String key) => json[key] is String ? json[key] : '';

    return SiteTarget(
      name: text('name'),
      server: text('server'),
      url: text('url'),
      deployRemote: text('deployRemote'),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'server': server,
        'url': url,
        if (deployRemote != autoDeploy) 'deployRemote': deployRemote,
      };

  @override
  bool operator ==(Object other) =>
      other is SiteTarget &&
      other.name == name &&
      other.server == server &&
      other.url == url &&
      other.deployRemote == deployRemote;

  @override
  int get hashCode => Object.hash(name, server, url, deployRemote);
}

/// A site to check, with an optional name and the optional path to its local git repository.
class Site {
  final String url;
  final String repoPath;
  final String name;

  /// Which git remote Deploy pushes to: [autoDeploy] (the default) lets the app pick one,
  /// [noDeploy] turns deploying off, anything else is the name of a remote.
  final String deployRemote;

  /// [deployRemote] value: the app picks the deploy remote, see RepoStatus.pickDeployRemote.
  static const autoDeploy = '';

  /// [deployRemote] value: the site is not deployed from the app. Git doesn't allow this
  /// as a remote name.
  static const noDeploy = '-';

  /// The address of the site's dev version, which deploys itself from the code on
  /// GitHub (e.g. via a webhook); empty if there is none.
  final String devUrl;

  /// Environments of this project. Empty for settings written before this existed:
  /// [environments] then derives one target from the fields above.
  final List<SiteTarget> targets;

  const Site({
    required this.url,
    this.repoPath = '',
    this.name = '',
    this.deployRemote = autoDeploy,
    this.devUrl = '',
    this.targets = const [],
  });

  /// The saved targets, or one legacy target built from [url]/[deployRemote].
  List<SiteTarget> get environments => targets.isNotEmpty
      ? targets
      : [
          SiteTarget(
            name: displayName,
            url: url,
            deployRemote: deployRemote,
          )
        ];

  Site withTargets(List<SiteTarget> targets) => Site(
        url: url,
        repoPath: repoPath,
        name: name,
        deployRemote: deployRemote,
        devUrl: devUrl,
        targets: targets,
      );

  /// The name, or the URL's host if no name is set.
  String get displayName {
    if (name.isNotEmpty) return name;
    final host = Uri.tryParse(url)?.host ?? '';

    return host.isNotEmpty ? host : url;
  }

  /// An error for a site address, or null if [text] is a full http(s) URL.
  static String? urlError(String text) {
    text = text.trim();
    if (text.isEmpty || text == 'https://' || text == 'http://') {
      return 'Enter the address of the site';
    }
    final uri = Uri.tryParse(text);
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty) {
      return 'Use a full address, like https://shop.example.com';
    }

    return null;
  }

  /// Reads all formats: the old plain URL string and the {url, repoPath, name, deployRemote,
  /// devUrl} map.
  factory Site.fromJson(dynamic json) {
    String text(String key) => json[key] is String ? json[key] : '';

    return switch (json) {
      String url => Site(url: url),
      {'url': String url} => Site(
          url: url,
          repoPath: text('repoPath'),
          name: text('name'),
          deployRemote: text('deployRemote'),
          devUrl: text('devUrl'),
          targets: [
            for (final target
                in json['targets'] is List ? json['targets'] : const [])
              if (target is Map<String, dynamic>) SiteTarget.fromJson(target),
          ],
        ),
      _ => throw const FormatException('Invalid site in settings.'),
    };
  }

  /// The deploy remote, the dev site and the targets are only written when set.
  Map<String, dynamic> toJson() => {
        'name': name,
        'url': url,
        'repoPath': repoPath,
        if (deployRemote != autoDeploy) 'deployRemote': deployRemote,
        if (devUrl.isNotEmpty) 'devUrl': devUrl,
        if (targets.isNotEmpty)
          'targets': [for (final target in targets) target.toJson()],
      };
}
