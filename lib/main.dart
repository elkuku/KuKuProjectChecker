import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'support/app_services.dart';
import 'support/preferences.dart';
import 'support/repo_status.dart';
import 'support/site_info.dart';
import 'screens/changes_screen.dart';
import 'screens/settings_screen.dart';
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
  late List<SiteInfo> siteInfos = [];
  bool loaded = false;

  AppServices get services => widget.services;

  @override
  void initState() {
    super.initState();

    loadInfos();
  }

  void loadInfos() {
    siteInfos = [];

    services.settings.readSettings().then((sites) {
      for (var site in sites) {
        // The list shows the errors; mark them as handled so a site that is not
        // reachable is not also reported as an uncaught error before that.
        final systemInfo = services.fetchInfo(site.url)..ignore();
        final repoStatus = site.repoPath.isEmpty
            ? null
            : (services.checkRepo(site.repoPath)..ignore());

        siteInfos.add(SiteInfo(
          url: site.url,
          name: site.displayName,
          hasName: site.name.isNotEmpty,
          systemInfo: systemInfo,
          repoStatus: repoStatus,
          repoPath: site.repoPath.isEmpty
              ? null
              : RepoStatus.expandHome(site.repoPath),
        ));
      }
      if (mounted) setState(() => loaded = true);
    }).catchError((error, stackTrace) {
      if (mounted) setState(() => loaded = true);
    });
  }

  /// The "Open in" menu of a site: the site in the browser, and its repository
  /// in the installed apps if a local repository is set.
  Widget _openInMenu(SiteInfo siteInfo) {
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
      tooltip: 'Open in …',
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
        item(Icons.public, 'Browser', () => _launchUrl(siteInfo.url)),
        if (repoPath != null)
          item(Icons.difference_outlined, 'Changes',
              () async => _showChanges(siteInfo)),
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

  void _openSettings(BuildContext context) {
    Navigator.push(context, SettingsScreen(settings: services.settings))
        .then((value) => loadInfos());
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
          const Text('Add your Symfony sites in the settings.'),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _openSettings(context),
            icon: const Icon(Icons.settings),
            label: const Text('Open settings'),
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
          IconButton(
            onPressed: () => _openSettings(ctx),
            tooltip: 'Settings',
            icon: Icon(Icons.settings),
          ),
        ],
      ),
      body: !loaded
          ? const Center(child: CircularProgressIndicator())
          : siteInfos.isEmpty
              ? _emptyState(ctx)
              : ListView(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  children: [
                    for (final siteInfo in siteInfos)
                      SiteCard(
                        site: siteInfo,
                        menu: _openInMenu(siteInfo),
                        onTap: siteInfo.repoPath == null
                            ? null
                            : () => _showChanges(siteInfo),
                      ),
                  ],
                ),
    );
  }
}
