/// A site to check, with the optional path to its local git repository.
class Site {
  final String url;
  final String repoPath;

  const Site({required this.url, this.repoPath = ''});

  /// Reads both formats: the old plain URL string and the {url, repoPath} map.
  factory Site.fromJson(dynamic json) {
    return switch (json) {
      String url => Site(url: url),
      {'url': String url} => Site(
          url: url,
          repoPath: json['repoPath'] is String ? json['repoPath'] : '',
        ),
      _ => throw const FormatException('Invalid site in settings.'),
    };
  }

  Map<String, String> toJson() => {'url': url, 'repoPath': repoPath};
}
