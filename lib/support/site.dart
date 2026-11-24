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

  const Site({
    required this.url,
    this.repoPath = '',
    this.name = '',
    this.deployRemote = autoDeploy,
  });

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

  /// Reads all formats: the old plain URL string and the {url, repoPath, name, deployRemote}
  /// map.
  factory Site.fromJson(dynamic json) {
    String text(String key) => json[key] is String ? json[key] : '';

    return switch (json) {
      String url => Site(url: url),
      {'url': String url} => Site(
          url: url,
          repoPath: text('repoPath'),
          name: text('name'),
          deployRemote: text('deployRemote'),
        ),
      _ => throw const FormatException('Invalid site in settings.'),
    };
  }

  /// The deploy remote is only written when it is not automatic.
  Map<String, String> toJson() => {
        'name': name,
        'url': url,
        'repoPath': repoPath,
        if (deployRemote != autoDeploy) 'deployRemote': deployRemote,
      };
}
