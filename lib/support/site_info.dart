class SiteInfo {
  final String url;
  final Future<SystemInfo> systemInfo;

  const SiteInfo({
    required this.url,
    required this.systemInfo,
  });
}

class SystemInfo {
  final String sfVersion;
  final String phpVersion;

  const SystemInfo({
    required this.sfVersion,
    required this.phpVersion,
  });

  factory SystemInfo.fromJson(Map<String, dynamic> json) {
    return switch (json) {
      {
      'sf_version': String sfVersion,
      'php_version': String phpVersion,
      } =>
          SystemInfo(
            sfVersion: sfVersion,
            phpVersion: phpVersion,
          ),
      _ => throw const FormatException('Failed to load site info.'),
    };
  }
}
