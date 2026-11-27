import 'deployer.dart' show RunFunction;
import 'server.dart';
import 'site.dart' show Site, SiteTarget;

/// The templates KMyServer's site-add knows by name; other templates are public git URLs.
const siteTemplates = {
  'symfony-starter': 'Symfony starter (github.com/elkuku/symfony-starter)',
};

/// A new site to create on a KMyServer server from a template.
class NewSite {
  final Server server;

  /// The site's name on the server (its user, folder and database), and the folder name.
  final String name;

  /// The project's label on [server]; the full address is derived from its base URL.
  final String domain;

  /// The full address derived from the server's base URL, passed to `site-add`.
  final String url;

  /// Required project identity; [displayName] may differ from the server site name.
  final String displayName;
  final String githubRepo;

  /// A name from [siteTemplates] or a public https git URL (optionally `#branch`).
  final String template;

  /// The folder the local clone goes into: [parentDir]/[name].
  final String parentDir;

  /// Also create a GitHub repository (gh) as origin and push to it.
  final bool github;

  /// Whether that repository is private; when false it is public.
  final bool githubPrivate;

  const NewSite({
    required this.server,
    required this.name,
    required this.domain,
    required this.url,
    required this.template,
    required this.parentDir,
    this.displayName = '',
    this.githubRepo = '',
    this.github = false,
    this.githubPrivate = true,
  });

  String get dir => '${parentDir.replaceFirst(RegExp(r'/+$'), '')}/$name';

  static String? nameError(String text) => RegExp(r'^[a-z][a-z0-9-]{1,30}$')
          .hasMatch(text.trim())
      ? null
      : '2–31 characters: lowercase letters, digits, "-"; starts with a letter';

  /// A project only supplies a subdomain; the server supplies the rest of the address.
  static String? subdomainError(String text) =>
      SiteTarget.subdomainError(text);

  /// Kept for old settings; new sites validate a subdomain instead.
  static String? domainError(String text) =>
      RegExp(r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$')
              .hasMatch(text.trim())
          ? null
          : 'A domain like shop.example.com';

  /// `gh repo create` takes owner/repo for an existing GitHub account.
  String get githubRepoArg {
    final pair = Site(githubRepo: githubRepo, targets: const [])
        .githubOwnerRepo;
    return pair == null ? name : '${pair.$1}/${pair.$2}';
  }

  static String? templateError(String text) {
    text = text.trim();
    if (siteTemplates.containsKey(text)) return null;
    return RegExp(r'^https://[^\s"' "'" r'`$\\;|&<>]+$').hasMatch(text)
        ? null
        : 'A public https git URL, optionally with #branch';
  }
}

/// The steps of creating a site, in order.
enum CreateStep { server, clone, github }

/// Creates a site on a KMyServer server from a template, clones it and (optionally) makes
/// a GitHub repository (private by default) for it.
class SiteCreator {
  final RunFunction run;

  const SiteCreator(this.run);

  /// Runs the steps; [onStep] tells which one starts, [onOutput] gets every line.
  /// Returns null on success, or what failed.
  Future<String?> create(NewSite site,
      {required void Function(CreateStep step) onStep,
      required void Function(String line) onOutput}) async {
    final server = site.server;

    onStep(CreateStep.server);
    // site-add as root: user, database, PHP pool, Caddy site; the template is deployed at once.
    // Its output looks like a push's server output, so the log shows its steps.
    var code = await run(
        'ssh',
        server.sshArgs('root', [
          '/usr/local/sbin/site-add',
          site.name,
          '--domain',
          server.siteDomain(site.domain),
          '--template',
          site.template,
        ]),
        (line) => onOutput('remote: $line'));
    if (code != 0) return 'Creating the site on ${server.name} failed';

    onStep(CreateStep.clone);
    code = await run(
        'git',
        ['clone', '-o', server.remote, server.siteRepoUrl(site.name), site.dir],
        onOutput);
    if (code != 0) return 'Cloning the site failed';

    if (site.github) {
      onStep(CreateStep.github);
      code = await run(
          'gh',
          [
            'repo',
            'create',
            site.githubRepoArg,
            site.githubPrivate ? '--private' : '--public',
            '--source',
            site.dir,
            '--remote',
            'origin',
            '--push',
          ],
          onOutput,
          workingDirectory: site.dir);
      if (code != 0) return 'Creating the GitHub repository failed';
    }

    return null;
  }
}
