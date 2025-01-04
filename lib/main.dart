import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'support/site_info.dart';
import 'support/settings.dart';
import 'screens/settings_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KuKu Site Info',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'KuKu Site Info'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  late List<SiteInfo> siteInfos = [];
  List<String> sites = [];

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
          url: site,
          systemInfo: fetchInfo(site),
        ));
      }
      setState(() {});
    }).catchError((error, stackTrace) {
      //print("outer: $error");
    });
  }

  Future<SystemInfo> fetchInfo(site) async {
    final response = await http.get(Uri.parse(site + '/system/info/'));

    if (response.statusCode == 200) {
      return SystemInfo.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);
    } else {
      throw Exception('Failed to load system info');
    }
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
              leading: TextButton(
                onPressed: () {
                  _launchUrl(siteInfo.url);
                },
                child: Text('Open'),
              ),
              trailing: FutureBuilder<SystemInfo>(
                future: siteInfo.systemInfo,
                builder: (context, snapshot) {
                  if (snapshot.hasData) {
                    return Text(
                        'PHP: ${snapshot.data!.phpVersion} - SF: ${snapshot.data!.sfVersion}');
                  } else if (snapshot.hasError) {
                    //print(snapshot.error);
                    return Text('Error');
                  }

                  return const CircularProgressIndicator();
                },
              ),
            ),
        ],
      ),
    );
  }
}
