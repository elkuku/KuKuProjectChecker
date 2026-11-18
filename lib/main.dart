import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'support/open_in.dart';
import 'support/preferences.dart';
import 'support/repo_status.dart';
import 'support/site_info.dart';
import 'support/settings.dart';
import 'screens/settings_screen.dart';
import 'widgets/repo_status_text.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, this.preferences});

  /// Where the theme choice is saved; the default is the app's support folder.
  final Preferences? preferences;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final Preferences preferences = widget.preferences ?? Preferences();
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
      title: 'KuKu Site Info',
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: themeMode,
      home: MyHomePage(
        title: 'KuKu Site Info',
        themeMode: themeMode,
        onSwitchTheme: _switchTheme,
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
  });

  final String title;
  final ThemeMode themeMode;
  final VoidCallback? onSwitchTheme;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  late List<SiteInfo> siteInfos = [];

  /// The installed apps that can open a repository, looked up once.
  final List<(OpenInTarget, String)> openInTargets = OpenInTarget.available();

  @override
  void initState() {
    super.initState();

    loadInfos();
  }

  void loadInfos() {
    var settings = Settings();
    siteInfos = [];

    settings.readSettings().then((sites) {
      for (var site in sites) {
        siteInfos.add(SiteInfo(
          url: site.url,
          systemInfo: fetchInfo(site.url),
          repoStatus:
              site.repoPath.isEmpty ? null : RepoStatus.check(site.repoPath),
          repoPath: site.repoPath.isEmpty
              ? null
              : RepoStatus.expandHome(site.repoPath),
        ));
      }
      setState(() {});
    }).catchError((error, stackTrace) {
      //print("outer: $error");
    });
  }

  Future<SystemInfo> fetchInfo(String site) async {
    // A site saved with a trailing slash would give "//system/info/", which the sites don't route.
    final base = site.replaceFirst(RegExp(r'/+$'), '');
    final response = await http.get(Uri.parse('$base/system/info/'));

    if (response.statusCode == 200) {
      return SystemInfo.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);
    } else {
      throw Exception('Failed to load system info');
    }
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
        if (repoPath != null && openInTargets.isNotEmpty) ...[
          const PopupMenuDivider(),
          for (final (target, executable) in openInTargets)
            item(target.icon, target.label,
                () => target.open(executable, repoPath)),
        ],
      ],
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
            onPressed: () {
              Navigator.push(ctx, SettingsScreen()).then((value) {
                loadInfos();
              });
            },
            icon: Icon(Icons.settings),
          ),
        ],
      ),
      body: ListView(
        children: <Widget>[
          for (var siteInfo in siteInfos)
            ListTile(
              title: Text(siteInfo.url),
              subtitle: siteInfo.repoStatus == null
                  ? null
                  : RepoStatusText(status: siteInfo.repoStatus!),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FutureBuilder<SystemInfo>(
                    future: siteInfo.systemInfo,
                    builder: (context, snapshot) {
                      if (snapshot.hasData) {
                        return Text(
                            'PHP: ${snapshot.data!.phpVersion} - SF: ${snapshot.data!.sfVersion}');
                      } else if (snapshot.hasError) {
                        return Text('Error');
                      }

                      return const CircularProgressIndicator();
                    },
                  ),
                  _openInMenu(siteInfo),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
