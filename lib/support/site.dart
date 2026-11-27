import 'server.dart';

/// One environment of a project: local Symfony, Plesk prod, a KMyServer, a VM, …
/// The [server] is a [Server.name], or empty for an environment without a server entry.
/// New environments store only a [subdomain]; [url] is a legacy full address kept for
/// settings written before servers had a base URL.
class SiteTarget {
  static const autoDeploy = '';
  static const noDeploy = '-';

  final String name;
  final String server;

  /// The project's label on [server], e.g. `shop` for `https://shop.vm.example.com`.
  final String subdomain;

  /// Legacy full address from older settings; not written for new environments.
  final String url;

  final String deployRemote;

  const SiteTarget({
    required this.name,
    this.server = '',
    this.subdomain = '',
    this.url = '',
    this.deployRemote = autoDeploy,
  });

  /// The full address, using the selected server's base URL for new environments.
  /// A subdomain without a server cannot be expanded, but is still worth showing.
  String urlFor(Server? server) => subdomain.isEmpty
      ? url
      : server?.siteUrl(subdomain) ?? subdomain;

  /// The host of a legacy [url], or the subdomain of a new environment.
  String get domain =>
      url.isEmpty ? subdomain : (Uri.tryParse(url)?.host ?? '');

  static String? nameError(String text) =>
      text.trim().isEmpty ? 'Enter a name for this environment' : null;

  /// A DNS label: lowercase letters, digits and inner dashes.
  static String? subdomainError(String text) {
    text = text.trim();
    if (text.isEmpty) return 'Enter the subdomain';
    if (!RegExp(r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?$').hasMatch(text)) {
      return 'Use lowercase letters, digits and dashes';
    }
    return null;
  }

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
      subdomain: text('subdomain'),
      url: text('url'),
      deployRemote: text('deployRemote'),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'server': server,
        if (subdomain.isNotEmpty) 'subdomain': subdomain
        // Old settings keep their full URL until the project is edited.
        else
          'url': url,
        if (deployRemote != autoDeploy) 'deployRemote': deployRemote,
      };

  @override
  bool operator ==(Object other) =>
      other is SiteTarget &&
      other.name == name &&
      other.server == server &&
      other.subdomain == subdomain &&
      other.url == url &&
      other.deployRemote == deployRemote;

  @override
  int get hashCode => Object.hash(name, server, subdomain, url, deployRemote);
}

/// A project to check, with its local repository, GitHub repository and environments.
/// The first [targets] entry is the main address of the project.
class Site {
  final String repoPath;
  final String name;

  /// The required GitHub repository, e.g. `https://github.com/elkuku/shop`.
  final String githubRepo;

  /// The address of the project's dev version, which deploys itself from the code on
  /// GitHub (e.g. via a webhook); empty if there is none.
  final String devUrl;

  /// Environments of this project. Never empty for a saved site: adding a project asks
  /// for its first environment before it is stored.
  final List<SiteTarget> targets;

  const Site({
    this.repoPath = '',
    this.name = '',
    this.githubRepo = '',
    this.devUrl = '',
    required this.targets,
  });

  /// The main environment of the project, used for versions and opening it.
  SiteTarget get mainTarget => targets.first;

  Site withTargets(List<SiteTarget> targets) => Site(
        repoPath: repoPath,
        name: name,
        githubRepo: githubRepo,
        devUrl: devUrl,
        targets: targets,
      );

  /// Required for every project. Older records with missing fields are flagged until
  /// they are edited; their name still falls back to the environment for display.
  bool get isComplete =>
      name.trim().isNotEmpty &&
      repoPath.trim().isNotEmpty &&
      githubRepo.trim().isNotEmpty &&
      targets.isNotEmpty &&
      targets.every((target) =>
          target.subdomain.isNotEmpty || target.url.isNotEmpty);

  /// The required fields this record still lacks, in the order the edit form shows them.
  List<String> get missingRequiredFields => [
        if (name.trim().isEmpty) 'display name',
        if (repoPath.trim().isEmpty) 'local repository',
        if (githubRepo.trim().isEmpty) 'GitHub repository',
        if (targets.isEmpty ||
            targets.any((target) =>
                target.subdomain.isEmpty && target.url.isEmpty))
          'environment address',
      ];

  /// A label from the first environment, used for the suggested values below.
  String? get _suggestedLabel {
    if (targets.isEmpty) return null;
    final target = targets.first;
    final label = target.subdomain.isNotEmpty
        ? target.subdomain
        : Uri.tryParse(target.url)?.host.split('.').first ?? '';
    final value = label.trim();
    return value.isEmpty ? null : value;
  }

  /// A display name for an old record that has none, e.g. `Shop`.
  String get suggestedName {
    final label = _suggestedLabel;
    if (label == null) return '';
    return '${label.substring(0, 1).toUpperCase()}${label.substring(1)}';
  }

  /// The conventional local folder for an old record without a repository.
  String get suggestedRepoPath {
    final label = _suggestedLabel;
    return label == null ? '' : '~/repos/$label';
  }

  /// The name part of the suggested GitHub URL, based on the local folder when
  /// it has one. Used to look for an existing repository with a similar name.
  String get suggestedGitHubLabel {
    final folder = repoPath.trim().split(RegExp(r'[/\\]')).lastWhere(
          (part) => part.isNotEmpty,
          orElse: () => '',
        );
    return folder.isEmpty ? _suggestedLabel ?? '' : folder;
  }

  /// The name, or the main environment's name/URL host for an old incomplete record.
  String get displayName {
    if (name.isNotEmpty) return name;
    final target = mainTarget;
    if (target.name.isNotEmpty) return target.name;
    final host = target.domain;

    return host.isNotEmpty ? host : target.url;
  }

  static String? nameError(String text) =>
      text.trim().isEmpty ? 'Enter a display name' : null;

  static String? repoPathError(String text) =>
      text.trim().isEmpty ? 'Enter the local repository folder' : null;

  static String? githubRepoError(String text) {
    text = text.trim();
    if (text.isEmpty) return 'Enter the GitHub repository URL';
    final uri = Uri.tryParse(text);
    final parts = uri?.pathSegments.where((part) => part.isNotEmpty).toList();
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.toLowerCase() != 'github.com' ||
        parts == null ||
        parts.length != 2) {
      return 'Use https://github.com/owner/repo';
    }
    return null;
  }

  /// The owner and repo name from a validated GitHub URL, for `gh repo create`.
  (String, String)? get githubOwnerRepo {
    if (githubRepoError(githubRepo) != null) return null;
    final parts =
        Uri.parse(githubRepo.trim()).pathSegments.where((p) => p.isNotEmpty);
    final list = parts.toList();
    final repo = list[1].replaceFirst(RegExp(r'\.git$'), '');
    return (list[0], repo);
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
      githubRepo: text('githubRepo'),
      devUrl: text('devUrl'),
      targets: parsed,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'repoPath': repoPath,
        'githubRepo': githubRepo,
        if (devUrl.isNotEmpty) 'devUrl': devUrl,
        'targets': [for (final target in targets) target.toJson()],
      };
}
