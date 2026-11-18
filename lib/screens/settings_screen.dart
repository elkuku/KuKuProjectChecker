import 'package:flutter/material.dart';

import '../support/settings.dart';
import '../support/site.dart';

class SettingsScreen extends MaterialPageRoute<Null> {
  SettingsScreen()
      : super(builder: (BuildContext ctx) {
          return SettingsPage();
        });
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

/// The two text fields of one site.
class _SiteFields {
  final TextEditingController url;
  final TextEditingController repoPath;

  _SiteFields(Site site)
      : url = TextEditingController(text: site.url),
        repoPath = TextEditingController(text: site.repoPath);

  void dispose() {
    url.dispose();
    repoPath.dispose();
  }
}

class _SettingsPageState extends State<SettingsPage> {
  final List<_SiteFields> fields = [];
  final Settings settings = Settings();

  @override
  void initState() {
    super.initState();

    settings.readSettings().then((sites) {
      setState(() {
        fields.addAll(sites.map(_SiteFields.new));
      });
    });
  }

  @override
  void dispose() {
    for (var field in fields) {
      field.dispose();
    }
    super.dispose();
  }

  Widget _getSiteTile(_SiteFields field) {
    return ListTile(
      title: Column(
        children: [
          TextField(
            controller: field.url,
            decoration: const InputDecoration(labelText: 'Site URL'),
          ),
          TextField(
            controller: field.repoPath,
            decoration: const InputDecoration(
              labelText: 'Local repository (optional)',
              hintText: '~/repos/my-project',
            ),
          ),
        ],
      ),
      trailing: IconButton(
        onPressed: () => setState(() {
          fields.remove(field);
          field.dispose();
        }),
        tooltip: 'Remove',
        icon: const Icon(Icons.delete_outline),
      ),
    );
  }

  void _writeSettings() {
    final sites = [
      for (var field in fields)
        if (field.url.text.trim() != '')
          Site(url: field.url.text.trim(), repoPath: field.repoPath.text.trim()),
    ];
    settings.writeSettings(sites);
    Navigator.of(context).pop();
  }

  void _addSite() {
    setState(() {
      fields.add(_SiteFields(const Site(url: 'https://')));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Settings'),
        actions: [
          IconButton(
            onPressed: () => _addSite(),
            icon: Icon(Icons.add),
          ),
        ],
      ),
      body: ListView(
        children: <Widget>[
          for (var field in fields) _getSiteTile(field),
          ListTile(
            title: TextButton(
              onPressed: () => _writeSettings(),
              child: Text('Save'),
            ),
          ),
        ],
      ),
    );
  }
}
