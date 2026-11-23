import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'support/app_services.dart';
import 'support/preferences.dart';
import 'support/repo_status.dart';
import 'support/site.dart';
import 'support/site_info.dart';
import 'screens/changes_screen.dart';
import 'widgets/deploy_dialog.dart';
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
  });

  final String title;
  final ThemeMode themeMode;
  final VoidCallback? onSwitchTheme;
  final AppServices services;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  /// The sites as saved, and what was read about each; both in the same order.
  List<Site> sites = [];
  List<SiteInfo> siteInfos = [];
  bool loaded = false;

  AppServices get services => widget.services;

  @override
  void initState() {
    super.initState();

    loadInfos();
  }

  /// Reads the sites and everything about them again.
  void loadInfos() {
    services.settings.readSettings().then((saved) {
      if (!mounted) return;
      setState(() {
        sites = saved;
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

    return SiteInfo(
      url: site.url,
      name: site.displayName,
      hasName: site.name.isNotEmpty,
      systemInfo: systemInfo,
      repoStatus: repoPath == null
          ? null
          : (services.checkRepo(site.repoPath)..ignore()),
      localVersions:
          repoPath == null ? null : (services.readLocal(repoPath)..ignore()),
      repoPath: repoPath,
    );
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
    final site = await showSiteDialog(context);
    if (site == null || !mounted) return;

    setState(() {
      sites.add(site);
      siteInfos.add(_siteInfo(site));
    });
    await _save();
  }

  Future<void> _editSite(int index) async {
    final site = await showSiteDialog(context, site: sites[index]);
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
