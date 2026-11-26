import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'support/app_services.dart';
import 'support/kmyserver.dart';
import 'support/preferences.dart';
import 'support/repo_status.dart';
import 'support/server.dart';
import 'support/site.dart';
import 'support/site_info.dart';
import 'screens/changes_screen.dart';
import 'screens/server_status_screen.dart';
import 'support/server_health.dart' show SiteHealth;
import 'widgets/deploy_dialog.dart';
import 'widgets/new_site_dialog.dart';
import 'widgets/rollback_dialog.dart';
import 'widgets/servers_dialog.dart';
import 'widgets/site_dialog.dart';
import 'widgets/site_card.dart';

void main() {
  runApp(const MyApp());
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

  AppServices get services => widget.services;

  Server? get _active =>
      servers.where((server) => server.name == activeServer).firstOrNull;

  @override
  void initState() {
    super.initState();

    loadInfos();
    // With an active server the sites deploy elsewhere: read them again once it is known.
    _loadServers().then((_) {
      if (mounted && activeServer.isNotEmpty) loadInfos();
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

  /// All sites deploy to [name]'s remote ('' = each site's own deploy remote).
  Future<void> _switchServer(String name) async {
    setState(() => activeServer = name);
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
    await _saveServers();
    loadInfos();
  }

  /// Opens the read-only status report of the active (or only) KMyServer server.
  Future<void> _showServerStatus() async {
    final candidates = servers.where((server) => server.isKMyServer).toList();
    final server = _active?.isKMyServer == true
        ? _active
        : candidates.length == 1
            ? candidates.single
            : null;

    if (server == null) {
      _showMessage(candidates.isEmpty
          ? 'Add a KMyServer server first (Servers…, with its SSH host)'
          : 'Choose a KMyServer server in the app bar first');
      return;
    }

    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ServerStatusScreen(
        server: server,
        fetch: services.fetchServerHealth,
        run: services.run,
        onDeploy: _deployFromServerStatus,
        onNewSite: _newSite,
      ),
    ));
  }

  /// The status page's Deploy button uses the same dialog as the site card: a git push from
  /// the local repository. Only sites that are in the app's settings can be deployed here.
  Future<bool> _deployFromServerStatus(SiteHealth site) async {
    final index = siteInfos.indexWhere((info) =>
        info.name == site.name || Uri.tryParse(info.url)?.host == site.domain);
    if (index < 0 || siteInfos[index].repoPath == null) {
      _showMessage('No local repository is set for ${site.domain}');
      return false;
    }

    final repoPath = siteInfos[index].repoPath!;
    final status = await services.checkRepo(repoPath, sites[index].deployRemote);
    if (!mounted) return false;
    final pushed = await showDeployDialog(
      context,
      siteName: siteInfos[index].name,
      repoPath: repoPath,
      status: status,
      push: services.push,
    );
    if (pushed && mounted) loadInfos();
    return pushed;
  }

  Future<void> _newSite() async {
    final kmyservers = servers.where((server) => server.isKMyServer).toList();
    if (kmyservers.isEmpty) {
      _showMessage(
          'Add a KMyServer server first (Servers…, with its SSH host)');
      return;
    }
    final site = await showNewSiteDialog(
      context,
      servers: kmyservers,
      server: _active?.isKMyServer == true ? _active : null,
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

  /// Starts reading a site's versions, repository status and local versions.
  SiteInfo _siteInfo(Site site) {
    // The list shows the errors; mark them as handled so a site that is not
    // reachable is not also reported as an uncaught error before that.
    final systemInfo = services.fetchInfo(site.url)..ignore();
    final repoPath =
        site.repoPath.isEmpty ? null : RepoStatus.expandHome(site.repoPath);

    final info = SiteInfo(
      url: site.url,
      name: site.displayName,
      hasName: site.name.isNotEmpty,
      systemInfo: systemInfo,
      repoStatus: repoPath == null
          ? null
          : (services.checkRepo(
              site.repoPath,
              // The active server's remote, unless the site never deploys.
              _active != null && site.deployRemote != Site.noDeploy
                  ? _active!.remote
                  : site.deployRemote)
            ..ignore()),
      localVersions:
          repoPath == null ? null : (services.readLocal(repoPath)..ignore()),
      repoPath: repoPath,
      devUrl: site.devUrl.isEmpty ? null : site.devUrl,
      devInfo: site.devUrl.isEmpty
          ? null
          : (services.fetchInfo(site.devUrl)..ignore()),
      upstreamTime: site.devUrl.isEmpty || repoPath == null
          ? null
          : (services.upstreamTime(repoPath)..ignore()),
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

  Future<void> _addSite() async {
    final site = await showSiteDialog(context,
        listRemotes: services.listRemotes, pickFolder: services.pickFolder);
    if (site == null || !mounted) return;

    setState(() {
      sites.add(site);
      siteInfos.add(_siteInfo(site));
    });
    await _save();
  }

  Future<void> _editSite(int index) async {
    final site = await showSiteDialog(context,
        site: sites[index],
        listRemotes: services.listRemotes,
        pickFolder: services.pickFolder);
    if (site == null || !mounted) return;

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

  /// The menu of a site: edit or remove it, open the site in the browser, and its
  /// repository in the installed apps if a local repository is set.
  Widget _siteMenu(int index) {
    final siteInfo = siteInfos[index];
    final repoPath = siteInfo.repoPath;

    PopupMenuItem<Future<void> Function()> item(
            IconData icon, String label, Future<void> Function() open) =>
        PopupMenuItem(
          value: open,
          child: ListTile(
            leading: Icon(icon),
            title: Text(label),
            contentPadding: EdgeInsets.zero,
          ),
        );

    return PopupMenuButton<Future<void> Function()>(
      tooltip: 'Edit, remove or open the site',
      icon: const Icon(Icons.more_vert),
      onSelected: (open) async {
        try {
          await open();
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not open it: $e')),
          );
        }
      },
      itemBuilder: (context) => [
        item(Icons.edit_outlined, 'Edit…', () => _editSite(index)),
        item(Icons.delete_outline, 'Remove', () => _removeSite(index)),
        const PopupMenuDivider(),
        item(Icons.public, 'Open in browser', () => _launchUrl(siteInfo.url)),
        if (siteInfo.devUrl != null)
          item(Icons.science_outlined, 'Open dev site',
              () => _launchUrl(siteInfo.devUrl!)),
        if (kmyserverSites[siteInfo] case final server?) ...[
          const PopupMenuDivider(),
          item(Icons.history, 'Roll back…', () => _rollback(siteInfo, server)),
        ],
        if (repoPath != null && services.openInTargets.isNotEmpty) ...[
          const PopupMenuDivider(),
          for (final (target, executable) in services.openInTargets)
            item(target.icon, target.label,
                () => target.open(executable, repoPath)),
        ],
      ],
    );
  }

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
    if (pushed && mounted) loadInfos();
  }

  Future<void> _rollback(SiteInfo siteInfo, KMyServerSite server) async {
    final rolledBack = await showRollbackDialog(
      context,
      siteName: siteInfo.name,
      site: server,
      rollback: services.rollback,
    );

    // The site reports the rollback as its newest deploy.
    if (rolledBack && mounted) loadInfos();
  }

  /// The active server: where all sites deploy, or each site's own remote.
  Widget _serverMenu() {
    const manage = '\u0000manage';
    const status = '\u0000status';

    return PopupMenuButton<String>(
      tooltip: 'Switch the server the sites deploy to',
      onSelected: (value) {
        if (value == manage) {
          _manageServers();
        } else if (value == status) {
          _showServerStatus();
        } else {
          _switchServer(value);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: status,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.monitor_heart_outlined, size: 20),
              SizedBox(width: 12),
              Text('Server status…'),
            ],
          ),
        ),
        const PopupMenuDivider(),
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
          Text('No sites yet', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('Add your Symfony sites to see their versions.'),
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

  @override
  Widget build(BuildContext ctx) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
        actions: [
          _serverMenu(),
          IconButton(
            onPressed: _newSite,
            tooltip: 'New site from a template',
            icon: const Icon(Icons.add_box_outlined),
          ),
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
      body: !loaded
          ? const Center(child: CircularProgressIndicator())
          : siteInfos.isEmpty
              ? _emptyState(ctx)
              : ReorderableListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  // The handle on the left moves a site; the rest of the card stays clickable.
                  buildDefaultDragHandles: false,
                  itemCount: siteInfos.length,
                  onReorderItem: _moveSite,
                  itemBuilder: (context, index) {
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
                      menu: _siteMenu(index),
                      onTap: siteInfo.repoPath == null
                          ? null
                          : () => _showChanges(siteInfo),
                      onDeploy: siteInfo.repoPath == null
                          ? null
                          : (status) => _deploy(siteInfo, status),
                    );
                  },
                ),
    );
  }
}
