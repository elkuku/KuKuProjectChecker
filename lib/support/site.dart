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

/// A project to check, with its local repository and its environments.
/// The first [targets] entry is the main address of the project.
class Site {
  final String repoPath;
  final String name;

  /// The address of the project's dev version, which deploys itself from the code on
  /// GitHub (e.g. via a webhook); empty if there is none.
  final String devUrl;

  /// Environments of this project. Never empty for a saved site: adding a project asks
  /// for its first environment before it is stored.
  final List<SiteTarget> targets;

  const Site({
    this.repoPath = '',
    this.name = '',
    this.devUrl = '',
    required this.targets,
  });

  /// The main address of the project, used for versions, opening it and deploys.
  SiteTarget get mainTarget => targets.first;

  Site withTargets(List<SiteTarget> targets) => Site(
        repoPath: repoPath,
        name: name,
        devUrl: devUrl,
        targets: targets,
      );

  /// The name, or the main environment's name/URL host if no name is set.
  String get displayName {
    if (name.isNotEmpty) return name;
    final target = mainTarget;
    if (target.name.isNotEmpty) return target.name;
    final host = target.domain;

    return host.isNotEmpty ? host : target.url;
  }

  /// An error for an environment address, or null if [text] is a full http(s) URL.
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

  /// Reads current settings and the older formats with a single `url` (and `deployRemote`)
  /// at the top level. Those fields become the first environment; they are not written again.
  factory Site.fromJson(dynamic json) {
    if (json is String) {
      return Site(targets: [
        SiteTarget(name: Uri.tryParse(json)?.host ?? '', url: json)
      ]);
    }
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Invalid site in settings.');
    }

    String text(String key) => json[key] is String ? json[key] : '';
    final parsed = <SiteTarget>[];
    if (json['targets'] is List) {
      for (final target in json['targets']) {
        if (target is Map<String, dynamic>) {
          parsed.add(SiteTarget.fromJson(target));
        }
      }
    }

    final legacyUrl = text('url');
    if (parsed.isEmpty) {
      if (legacyUrl.isEmpty) {
        throw const FormatException('Invalid site in settings.');
      }
      final legacyName = text('name');
      parsed.add(SiteTarget(
        name: legacyName.isNotEmpty
            ? legacyName
            : Uri.tryParse(legacyUrl)?.host ?? '',
        url: legacyUrl,
        deployRemote: text('deployRemote'),
      ));
    }

    return Site(
      name: text('name'),
      repoPath: text('repoPath'),
      devUrl: text('devUrl'),
      targets: parsed,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'repoPath': repoPath,
        if (devUrl.isNotEmpty) 'devUrl': devUrl,
        'targets': [for (final target in targets) target.toJson()],
      };
}
