import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'support/app_services.dart';
import 'support/kmyserver.dart';
import 'support/preferences.dart';
import 'support/repo_status.dart';
import 'support/single_instance.dart';
import 'support/server.dart';
import 'support/server_actions.dart';
import 'support/site.dart';
import 'support/site_info.dart';
import 'screens/changes_screen.dart';
import 'screens/server_status_screen.dart';
import 'support/server_health.dart' show ServerHealth, SiteHealth;
import 'widgets/deploy_dialog.dart';
import 'widgets/deploy_to_server_dialog.dart';
import 'widgets/environments_dialog.dart';
import 'widgets/add_site_dialog.dart';
import 'widgets/rollback_dialog.dart';
import 'widgets/servers_dialog.dart';
import 'widgets/server_action_dialog.dart';
import 'widgets/server_site_card.dart';
import 'widgets/site_dialog.dart';
import 'widgets/site_card.dart';
import 'widgets/site_row_action.dart';

/// Held for the lifetime of the app; a second launch cannot claim it.
SingleInstance? _instance;

Future<void> main() async {
  // Check before initializing Flutter: a rejected second launch must exit at
  // once, without starting a GTK event loop.
  _instance = await SingleInstance.acquire();
  if (_instance == null) {
    stderr.writeln('KuKuProjectChecker is already running.');
    // The Linux runner starts its event loop before Dart main; returning is
    // not enough to end a rejected second launch.
    exit(0);
  }
  runApp(const MyApp());
}

IconData _serverActionIcon(ServerAction action) => switch (action.id) {
      'releases' => Icons.list_alt,
      'rollback' => Icons.history,
      'logDeploy' ||
      'logApp' ||
      'logPhp' ||
      'logCaddy' =>
        Icons.article_outlined,
      'remove' => Icons.delete_outline,
      _ => Icons.settings_outlined,
    };

PopupMenuItem<Future<void> Function()> _menuItem(
        IconData icon, String label, Future<void> Function() action) =>
    PopupMenuItem(
      value: action,
      child: ListTile(
        leading: Icon(icon),
        title: Text(label),
        contentPadding: EdgeInsets.zero,
      ),
    );

/// Runs an Open in… item and shows failures instead of swallowing them.
Future<void> _runOpenAction(
    BuildContext context, Future<void> Function() open) async {
  try {
    await open();
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not open it: $e')),
    );
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, this.preferences, this.services});

  /// Where the theme choice is saved; the default is the app's support folder.
  final Preferences? preferences;

  /// The settings, sites, repositories and apps; the default is the real ones.
  final AppServices? services;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final Preferences preferences = widget.preferences ?? Preferences();
  late final AppServices services = widget.services ?? AppServices();
  ThemeMode themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();

    preferences.readThemeMode().then((mode) {
      if (mounted) setState(() => themeMode = mode);
    });
  }

  void _switchTheme() {
    setState(() => themeMode = nextThemeMode(themeMode));
    preferences.writeThemeMode(themeMode);
  }

  ThemeData _theme(Brightness brightness) => ThemeData(
        colorScheme: _colorScheme(brightness),
        useMaterial3: true,
        // Material 3 draws tooltips in the inverse colors: nearly white in the dark
        // theme. Keep them dark there.
        tooltipTheme: brightness == Brightness.dark
            ? TooltipThemeData(
                decoration: BoxDecoration(
                  color: _colorScheme(brightness).surfaceContainerHighest,
                  border: Border.all(
                      color: _colorScheme(brightness).outlineVariant),
                  borderRadius: BorderRadius.circular(4),
                ),
                textStyle: TextStyle(color: _colorScheme(brightness).onSurface),
              )
            : null,
      );

  static ColorScheme _colorScheme(Brightness brightness) =>
      ColorScheme.fromSeed(seedColor: Colors.green, brightness: brightness);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KuKu Project Checker',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: themeMode,
      home: MyHomePage(
        title: 'KuKu Project Checker',
        themeMode: themeMode,
        onSwitchTheme: _switchTheme,
        services: services,
        preferences: preferences,
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({
    super.key,
    required this.title,
    this.themeMode = ThemeMode.system,
    this.onSwitchTheme,
    required this.services,
    this.preferences,
  });

  final String title;
  final ThemeMode themeMode;
  final VoidCallback? onSwitchTheme;
  final AppServices services;

  /// Where the servers are saved; null keeps them in memory only.
  final Preferences? preferences;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  /// The sites as saved, and what was read about each; both in the same order.
  List<Site> sites = [];
  List<SiteInfo> siteInfos = [];
  bool loaded = false;

  /// The sites whose deploy remote is on a KMyServer server (they can be rolled back);
  /// filled in when their repository status arrives.
  final Map<SiteInfo, KMyServerSite> kmyserverSites = {};

  /// The servers the sites can deploy to, and the active one ('' = each site's own remote).
  List<Server> servers = [];
  String activeServer = '';

  /// Health reports of all configured KMyServers, keyed by [Server.name]. The status pane
  /// shows the active one; every project card can show its own target on any of them.
  final Map<String, Future<ServerHealth>> _health = {};
  final Map<String, List<SiteHealth>> _siteHealth = {};

  AppServices get services => widget.services;

  Server? get _active => _serverNamed(activeServer);

  Server? _serverNamed(String name) => name.isEmpty
      ? null
      : servers.where((server) => server.name == name).firstOrNull;

  /// The full address of [target], using its server's base URL when it stores only
  /// a subdomain.
  String _targetUrl(SiteTarget target) =>
      target.urlFor(_serverNamed(target.server));

  @override
  void initState() {
    super.initState();

    loadInfos();
    // With an active server the sites deploy elsewhere: read them again once it is known.
    _loadServers().then((_) {
      if (!mounted) return;
      // Server base URLs are needed to derive environment addresses even when no
      // server is selected for comparison.
      loadInfos();
      _reloadHealth();
    });
  }

  Future<void> _loadServers() async {
    final preferences = widget.preferences;
    if (preferences == null) return;
    try {
      final (saved, active) = await preferences.readServers();
      if (mounted) {
        setState(() {
          servers = saved;
          activeServer = active;
        });
      }
    } catch (_) {}
  }

  Future<void> _saveServers() async =>
      widget.preferences?.writeServers(servers, activeServer);

  /// Reads the health report of every configured KMyServer. One future per server feeds
  /// the status pane (when that server is active) and the matching project cards.
  void _reloadHealth() {
    final futures = <String, Future<ServerHealth>>{
      for (final server in servers)
        if (server.isKMyServer) server.name: services.fetchServerHealth(server),
    };
    setState(() {
      _health
        ..clear()
        ..addAll(futures);
      _siteHealth.clear();
    });

    for (final entry in futures.entries) {
      entry.value.then((report) {
        if (!mounted || _health[entry.key] != entry.value) return;
        setState(() => _siteHealth[entry.key] = report.sites);
      }, onError: (_) {
        if (!mounted || _health[entry.key] != entry.value) return;
        setState(() => _siteHealth[entry.key] = []);
      });
    }
  }

  /// All sites deploy to [name]'s remote ('' = each site's own deploy remote).
  Future<void> _switchServer(String name) async {
    setState(() => activeServer = name);
    _reloadHealth();
    await _saveServers();
    loadInfos();
  }

  Future<void> _manageServers() async {
    final edited = await showServersDialog(context, servers);
    if (edited == null || !mounted) return;
    setState(() {
      servers = edited;
      if (_active == null) activeServer = '';
    });
    _reloadHealth();
    await _saveServers();
    loadInfos();
  }

  List<Server> get _kmyServers =>
      servers.where((server) => server.isKMyServer).toList();

  /// The environment of [info] on [server].
  SiteTarget? _targetForServer(SiteInfo info, Server server) =>
      info.targetFor(server.name);

  /// A server site and an environment are the same when their subdomain, address or
  /// environment name matches.
  static bool _sameTarget(SiteTarget target, SiteHealth health) {
    final label = target.subdomain.isNotEmpty
        ? target.subdomain
        : target.domain.split('.').first;
    if (label.isNotEmpty && health.domain.split('.').first == label) return true;
    if (health.name == target.name) return true;
    if (label.isNotEmpty && health.name == label) return true;
    return false;
  }

  bool _matchesOn(Server server, SiteInfo info, SiteHealth health) {
    final target = _targetForServer(info, server);
    return target != null && _sameTarget(target, health);
  }

  SiteHealth? _healthFor(Server server, SiteInfo info) {
    for (final health in _siteHealth[server.name] ?? const <SiteHealth>[]) {
      if (_matchesOn(server, info, health)) return health;
    }
    return null;
  }

  /// The servers where this project was found, active server first.
  List<MapEntry<Server, SiteHealth>> _matchedServers(SiteInfo info) {
    final matched = <Server, SiteHealth>{
      for (final server in _kmyServers)
        if (_healthFor(server, info) case final health?) server: health,
    };
    final ordered = <MapEntry<Server, SiteHealth>>[];
    final active = _active;
    if (active != null && matched.containsKey(active)) {
      ordered.add(MapEntry(active, matched[active]!));
    }
    ordered.addAll(matched.entries.where((entry) => entry.key != active));
    return ordered;
  }

  /// Every report shown on a project card: one per environment/server match.
  List<SiteServerHealth> _cardHealths(SiteInfo info) => [
        for (final entry in _matchedServers(info))
          SiteServerHealth(server: entry.key.name, health: entry.value),
      ];

  /// Runs one allowlisted server action for the given environment.
  Future<void> _runServerAction(
      ServerAction action, Server server, SiteHealth health) async {
    final done = await showServerActionDialog(
      context,
      action: action,
      server: server,
      siteName: health.name,
      run: services.run,
    );
    if (!mounted || !done) return;
    if (action.risk != ServerActionRisk.read) {
      loadInfos();
      _reloadHealth();
    }
  }

  /// Writes the edited environments back to the setting [info] came from.
  void _storeTargets(SiteInfo info, List<SiteTarget> targets) {
    var index = info.site == null
        ? -1
        : sites.indexWhere((site) => identical(site, info.site));
    if (index < 0) {
      index = sites.indexWhere((site) =>
          site.displayName == info.name && site.repoPath == info.repoPath);
    }
    if (index >= 0) sites[index] = sites[index].withTargets(targets);
  }

  Future<void> _editEnvironments(SiteInfo info) async {
    final edited = await showEnvironmentsDialog(
      context,
      targets: info.targets,
      servers: servers,
    );
    if (edited == null || edited.isEmpty || !mounted) return;
    _storeTargets(info, edited);
    await _save();
    if (!mounted) return;
    loadInfos();
    _reloadHealth();
  }

  /// Creates a site on [server] for a project that is not there yet, then deploys it.
  /// The chosen domain/name is recorded as the project's environment on that server.
  Future<void> _deployToServer(
      SiteInfo info, Server server, SiteTarget? target) async {
    final repoPath = info.repoPath;
    if (!server.isKMyServer || repoPath == null) return;

    final remotes = await services.listRemotes(repoPath);
    final status = await services.checkRepo(repoPath, server.remote);
    if (!mounted) return;

    // A local database (compose/.env) prefills the dialog's DB option; the user
    // can still override it. KMyServer creates PostgreSQL only.
    var dbDetected = false;
    try {
      final local = await services.readLocal(RepoStatus.expandHome(repoPath));
      dbDetected = local.dbPlatform != null;
    } catch (_) {
      dbDetected = false;
    }
    if (!mounted) return;

    final subdomain = target?.subdomain.isNotEmpty == true
        ? target!.subdomain
        : suggestedSiteName(info.name);
    final result = await showDeployToServerDialog(
      context,
      server: server,
      site: info,
      subdomain: subdomain,
      repoPath: repoPath,
      status: status,
      remotes: remotes,
      dbDetected: dbDetected,
      run: services.run,
      push: services.push,
    );
    if (result == null || !mounted) return;
    // A failed import still records the site, but must stay visible as an error.
    if (result.error case final message?) _showMessage(message);

    final targets = [...info.targets];
    final index = targets.indexWhere((item) => item.server == server.name);
    final updated = SiteTarget(
      name: index < 0 ? server.name : targets[index].name,
      server: server.name,
      subdomain: result.subdomain,
      deployRemote: server.remote,
    );
    if (index < 0) {
      targets.add(updated);
    } else {
      targets[index] = updated;
    }
    _storeTargets(info, targets);
    await _save();
    if (!mounted) return;
    loadInfos();
    _reloadHealth();
  }

  /// Reads the sites and everything about them again.
  void loadInfos() {
    services.settings.readSettings().then((saved) {
      if (!mounted) return;
      setState(() {
        sites = saved;
        kmyserverSites.clear();
        siteInfos = saved.map(_siteInfo).toList();
        loaded = true;
      });
    }).catchError((error, stackTrace) {
      if (mounted) setState(() => loaded = true);
    });
  }

  /// Starts reading a site's git status and local versions, plus the versions of
  /// the selected server's environment when one is selected.
  SiteInfo _siteInfo(Site site) {
    final main = site.mainTarget;
    final repoPath =
        site.repoPath.isEmpty ? null : RepoStatus.expandHome(site.repoPath);

    // The target for the active server wins; otherwise the main environment is used
    // only for display, not for a remote request.
    final active = _active;
    final activeTarget = active == null
        ? null
        : site.targets
            .where((target) => target.server == active.name)
            .firstOrNull;
    final visibleTarget = activeTarget ?? main;
    final url = _targetUrl(visibleTarget);
    final deployRemote = activeTarget?.deployRemote ?? main.deployRemote;

    // Only a selected server triggers a /system/info/ comparison.
    Future<SystemInfo>? systemInfo;
    if (active != null && activeTarget != null && url.isNotEmpty) {
      systemInfo = services.fetchInfo(url)..ignore();
    }

    final info = SiteInfo(
      url: url,
      name: site.displayName,
      hasName: site.name.isNotEmpty,
      githubRepo: site.githubRepo,
      isComplete: site.isComplete,
      compareServer: systemInfo == null ? null : active?.name,
      systemInfo: systemInfo,
      repoStatus: repoPath == null
          ? null
          : (services.checkRepo(site.repoPath, deployRemote)..ignore()),
      localVersions:
          repoPath == null ? null : (services.readLocal(repoPath)..ignore()),
      repoPath: repoPath,
      devUrl: site.devUrl.isEmpty ? null : site.devUrl,
      devInfo: active != null && site.devUrl.isNotEmpty
          ? (services.fetchInfo(site.devUrl)..ignore())
          : null,
      upstreamTime: site.devUrl.isEmpty || repoPath == null
          ? null
          : (services.upstreamTime(repoPath)..ignore()),
      targets: site.targets,
      site: site,
    );
    info.repoStatus?.then((status) {
      final server = status.deployUrl == null
          ? null
          : KMyServerSite.fromRemoteUrl(status.deployUrl!);
      if (server != null) kmyserverSites[info] = server;
    }, onError: (_) {});

    return info;
  }

  void _showMessage(String text, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), action: action));
  }

  /// Saves the sites; a failure is shown, the list keeps the change.
  Future<void> _save() async {
    try {
      await services.settings.writeSettings(sites);
    } catch (e) {
      if (mounted) _showMessage('Could not save the sites: $e');
    }
  }

  /// One wizard for both ways of adding a site. The server pane preselects the
  /// template flow; the top bar and the empty list open it on an existing project.
  Future<void> _addSite(
      {AddSiteSource source = AddSiteSource.existing, Server? server}) async {
    final site = await showAddSiteDialog(
      context,
      servers: servers,
      server: server,
      source: source,
      run: services.run,
      pickFolder: services.pickFolder,
      exists: services.pathExists,
    );
    if (site == null || !mounted) return;

    setState(() {
      sites.add(site);
      siteInfos.add(_siteInfo(site));
    });
    await _save();
    _reloadHealth();
  }

  Future<void> _editSite(int index) async {
    final current = sites[index];
    final details = await showSiteDialog(context,
        site: current,
        pickFolder: services.pickFolder,
        listGitHubRepos: services.listGitHubRepos);
    if (details == null || !mounted) return;

    final site = Site(
      name: details.name,
      repoPath: details.repoPath,
      githubRepo: details.githubRepo,
      devUrl: details.devUrl,
      targets: current.targets,
    );
    setState(() {
      sites[index] = site;
      siteInfos[index] = _siteInfo(site);
    });
    await _save();
  }

  Future<void> _removeSite(int index) async {
    final site = sites[index];
    final info = siteInfos[index];

    setState(() {
      sites.removeAt(index);
      siteInfos.removeAt(index);
    });
    await _save();
    if (!mounted) return;

    _showMessage(
      'Removed ${info.name}',
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () {
          if (!mounted) return;
          final at = index.clamp(0, sites.length);
          setState(() {
            sites.insert(at, site);
            siteInfos.insert(at, info);
          });
          _save();
        },
      ),
    );
  }

  Future<void> _moveSite(int from, int to) async {
    if (to == from) return;

    setState(() {
      sites.insert(to, sites.removeAt(from));
      siteInfos.insert(to, siteInfos.removeAt(from));
    });
    await _save();
  }

  /// Buttons for one project. Common actions stay in the collapsed row; the rest
  /// are shown when the row is expanded. The Open in… actions have their own menu.
  List<SiteRowAction> _siteActions(int index) {
    final info = siteInfos[index];
    final repoPath = info.repoPath;
    final kmyServers = _kmyServers;
    final matched = _matchedServers(info);
    String label(String base, Server server) =>
        kmyServers.length > 1 ? '$base on ${server.name}…' : '$base…';

    final actions = <SiteRowAction>[
      SiteRowAction(Icons.edit_outlined, 'Edit…', () => _editSite(index)),
      SiteRowAction(Icons.layers_outlined, 'Environments…',
          () => _editEnvironments(info)),
    ];

    // The most relevant server's two common actions stay in the collapsed row.
    if (matched.isNotEmpty) {
      final first = matched.first;
      actions.add(SiteRowAction(
        Icons.list_alt,
        label('Releases', first.key),
        () => _runServerAction(ServerAction.releases, first.key, first.value),
      ));
      actions.add(SiteRowAction(
        Icons.history,
        label('Roll back', first.key),
        () => _runServerAction(ServerAction.rollback, first.key, first.value),
      ));
    } else if (kmyserverSites[info] != null) {
      actions.add(SiteRowAction(
        Icons.history,
        'Roll back…',
        () => _rollback(info, kmyserverSites[info]!),
      ));
    }

    for (final (position, entry) in matched.indexed) {
      final server = entry.key;
      final health = entry.value;
      if (position > 0) {
        actions.add(SiteRowAction(
          Icons.list_alt,
          label('Releases', server),
          () => _runServerAction(ServerAction.releases, server, health),
          place: SiteActionPlace.details,
        ));
        actions.add(SiteRowAction(
          Icons.history,
          label('Roll back', server),
          () => _runServerAction(ServerAction.rollback, server, health),
          place: SiteActionPlace.details,
        ));
      }
      for (final log in ServerAction.logActions) {
        actions.add(SiteRowAction(
          _serverActionIcon(log),
          label(log.label, server),
          () => _runServerAction(log, server, health),
          place: SiteActionPlace.details,
        ));
      }
      actions.add(SiteRowAction(
        Icons.delete_outline,
        'Remove site on ${server.name}…',
        () => _runServerAction(ServerAction.remove, server, health),
        place: SiteActionPlace.details,
        danger: true,
      ));
    }

    // Creating a site on a server is only offered for the selected one, and only
    // while this project is not there yet. Other servers keep their own actions.
    final selected = _active;
    if (repoPath != null &&
        selected != null &&
        selected.isKMyServer &&
        _health[selected.name] != null &&
        !matched.any((entry) => entry.key == selected) &&
        _targetForServer(info, selected) == null) {
      actions.add(SiteRowAction(
        Icons.rocket_launch,
        'Deploy to ${selected.name}…',
        () => _deployToServer(info, selected, null),
        place: SiteActionPlace.details,
        filled: true,
      ));
    }

    actions.add(SiteRowAction(
      Icons.delete_outline,
      'Remove',
      () => _removeSite(index),
      place: SiteActionPlace.details,
      danger: true,
    ));
    return actions;
  }

  /// The only dropdown on a project row: open its environments or local tools.
  Widget _siteOpenInMenu(int index) {
    final info = siteInfos[index];

    return PopupMenuButton<Future<void> Function()>(
      tooltip: 'Open in…',
      icon: const Icon(Icons.open_in_new),
      onSelected: (open) => _runOpenAction(context, open),
      itemBuilder: (context) => [
        if (Site.urlError(info.url) == null)
          _menuItem(Icons.public, 'Open in browser', () => _launchUrl(info.url)),
        for (final target in info.targets.skip(1))
          if (Site.urlError(_targetUrl(target)) == null)
            _menuItem(
                Icons.public,
                'Open ${target.name} (${Uri.parse(_targetUrl(target)).host})',
                () => _launchUrl(_targetUrl(target))),
        if (info.devUrl != null)
          _menuItem(Icons.science_outlined, 'Open dev site',
              () => _launchUrl(info.devUrl!)),
        if (info.repoPath != null && services.openInTargets.isNotEmpty) ...[
          const PopupMenuDivider(),
          for (final (target, executable) in services.openInTargets)
            _menuItem(target.icon, target.label,
                () => target.open(executable, info.repoPath!)),
        ],
      ],
    );
  }

  /// Buttons for a site that exists only on [server]. Nothing about it is written
  /// to the project settings.
  List<SiteRowAction> _serverSiteActions(Server server, SiteHealth health) => [
        SiteRowAction(
          Icons.list_alt,
          'Releases…',
          () => _runServerAction(ServerAction.releases, server, health),
        ),
        SiteRowAction(
          Icons.history,
          'Roll back…',
          () => _runServerAction(ServerAction.rollback, server, health),
        ),
        for (final log in ServerAction.logActions)
          SiteRowAction(
            _serverActionIcon(log),
            '${log.label}…',
            () => _runServerAction(log, server, health),
            place: SiteActionPlace.details,
          ),
        SiteRowAction(
          Icons.delete_outline,
          'Remove site…',
          () => _runServerAction(ServerAction.remove, server, health),
          place: SiteActionPlace.details,
          danger: true,
        ),
      ];

  /// The only dropdown on a temporary server row: open it in the browser.
  Widget _serverOpenInMenu(Server server, SiteHealth health) =>
      PopupMenuButton<Future<void> Function()>(
        tooltip: 'Open in…',
        icon: const Icon(Icons.open_in_new),
        onSelected: (open) => _runOpenAction(context, open),
        itemBuilder: (context) => [
          _menuItem(Icons.public, 'Open in browser',
              () => _launchUrl(server.siteUrl(health.domain))),
        ],
      );

  void _showChanges(SiteInfo siteInfo) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChangesScreen(
        title: siteInfo.name,
        changes: services.repoChanges(siteInfo.repoPath!),
      ),
    ));
  }

  Future<void> _deploy(SiteInfo siteInfo, RepoStatus status) async {
    final pushed = await showDeployDialog(
      context,
      siteName: siteInfo.name,
      repoPath: siteInfo.repoPath!,
      status: status,
      push: services.push,
    );

    // The deploy remote has the commits now.
    if (pushed && mounted) {
      loadInfos();
      _reloadHealth();
    }
  }

  Future<void> _rollback(SiteInfo siteInfo, KMyServerSite server) async {
    final rolledBack = await showRollbackDialog(
      context,
      siteName: siteInfo.name,
      site: server,
      rollback: services.rollback,
    );

    // The site reports the rollback as its newest deploy.
    if (rolledBack && mounted) {
      loadInfos();
      _reloadHealth();
    }
  }

  /// The active server: where all sites deploy, or each site's own remote.
  Widget _serverMenu() {
    const manage = '\u0000manage';

    return PopupMenuButton<String>(
      tooltip: 'Switch the server the sites deploy to',
      onSelected: (value) {
        if (value == manage) {
          _manageServers();
        } else {
          _switchServer(value);
        }
      },
      itemBuilder: (context) => [
        CheckedPopupMenuItem(
          value: '',
          checked: activeServer.isEmpty,
          child: const Text("Each site's own deploy remote"),
        ),
        for (final server in servers)
          CheckedPopupMenuItem(
            value: server.name,
            checked: server.name == activeServer,
            child: Text('${server.name}  (remote ${server.remote})'),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: manage,
          child: ListTile(
            leading: Icon(Icons.edit_outlined),
            title: Text('Servers…'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.dns_outlined),
            const SizedBox(width: 6),
            Text(_active?.name ?? 'Own remotes'),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.travel_explore,
              size: 64, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text('No projects yet', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('Add your Symfony projects to see their versions.'),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _addSite,
            icon: const Icon(Icons.add),
            label: const Text('Add site'),
          ),
        ],
      ),
    );
  }

  Future<void> _launchUrl(String uri) async {
    final Uri url = Uri.parse(uri);
    if (!await launchUrl(url)) {
      throw Exception('Could not launch $uri');
    }
  }

  /// Server sites without a matching project environment. They are temporary list
  /// entries, not settings, and keep the server they came from.
  List<({Server server, SiteHealth health})> get _serverOnlySites {
    final result = <({Server server, SiteHealth health})>[];
    for (final server in _kmyServers) {
      for (final health in _siteHealth[server.name] ?? const <SiteHealth>[]) {
        if (!siteInfos.any((info) => _matchesOn(server, info, health))) {
          result.add((server: server, health: health));
        }
      }
    }
    return result;
  }

  Widget _statusPane(Server server) => ServerStatusPanel(
        server: server,
        report: _health[server.name]!,
        onReload: _reloadHealth,
        run: services.run,
        onNewSite: () =>
            _addSite(source: AddSiteSource.template, server: server),
      );

  Widget _siteList(BuildContext context) {
    final extra = _serverOnlySites;
    if (siteInfos.isEmpty && extra.isEmpty) return _emptyState(context);

    return ReorderableListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 6),
      // The handle on the left moves a project; the rest of the card stays clickable.
      buildDefaultDragHandles: false,
      itemCount: siteInfos.length + extra.length,
      onReorderItem: (from, to) {
        // The temporary server entries stay at the end of the list.
        if (from >= siteInfos.length) return;
        _moveSite(from, to.clamp(0, siteInfos.length - 1).toInt());
      },
      itemBuilder: (context, index) {
        if (index >= siteInfos.length) {
          final entry = extra[index - siteInfos.length];
          return ServerSiteCard(
            key: ValueKey('server-${entry.server.name}-${entry.health.domain}'),
            health: entry.health,
            serverName: entry.server.name,
            actions: _serverSiteActions(entry.server, entry.health),
            openInMenu: _serverOpenInMenu(entry.server, entry.health),
          );
        }

        final siteInfo = siteInfos[index];
        return SiteCard(
          // Stays with the site when it moves.
          key: ObjectKey(siteInfo),
          site: siteInfo,
          dragHandle: ReorderableDragStartListener(
            index: index,
            child: const MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: Tooltip(
                message: 'Drag to move the site',
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.drag_indicator, size: 20),
                ),
              ),
            ),
          ),
          actions: _siteActions(index),
          openInMenu: _siteOpenInMenu(index),
          onTap:
              siteInfo.repoPath == null ? null : () => _showChanges(siteInfo),
          onDeploy: siteInfo.repoPath == null
              ? null
              : (status) => _deploy(siteInfo, status),
          serverHealths: _cardHealths(siteInfo),
        );
      },
    );
  }

  /// The status of the selected KMyServer is always beside the sites. The Linux window
  /// has a minimum width (linux/runner/my_application.cc) so both panes fit.
  Widget _body(BuildContext context) {
    if (!loaded) return const Center(child: CircularProgressIndicator());
    final server = _active;
    if (server == null || !server.isKMyServer || _health[server.name] == null) {
      return _siteList(context);
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 400,
          child: SingleChildScrollView(child: _statusPane(server)),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: _siteList(context)),
      ],
    );
  }

  @override
  Widget build(BuildContext ctx) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
        actions: [
          _serverMenu(),
          IconButton(
            onPressed: _addSite,
            tooltip: 'Add site',
            icon: const Icon(Icons.add),
          ),
          if (widget.onSwitchTheme != null)
            IconButton(
              onPressed: widget.onSwitchTheme,
              tooltip: themeModeButton(widget.themeMode).$2,
              icon: Icon(themeModeButton(widget.themeMode).$1),
            ),
          IconButton(
            onPressed: loadInfos,
            tooltip: 'Refresh',
            icon: Icon(Icons.refresh),
          ),
        ],
      ),
      body: _body(ctx),
    );
  }
}
