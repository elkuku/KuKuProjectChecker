import 'package:flutter/material.dart';

import '../support/settings.dart';

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

class _SettingsPageState extends State<SettingsPage> {
  List<String> sites = [];
  List<TextEditingController> controllers = [];
  Settings settings = Settings();

  @override
  void initState() {
    super.initState();
    sites = [];
    controllers = [];

    settings.readSettings().then((items) {
      for (var item in items) {
        sites.add(item);
      }
      setState(() {});
    }).catchError((error, stackTrace) {
      //print("outer: $error");
    });
  }

  @override
  void dispose() {
    for (var controller in controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  ListTile _getListTile(String text) {
    TextEditingController controller = TextEditingController()..text = text;

    controllers.add(controller);

    return ListTile(
      title: TextField(
        controller: controller,
        onChanged: (text) => {},
      ),
      trailing: TextButton(
        onPressed: () => controller.text = '',
        child: Text('X'),
      ),
    );
  }

  void _writeSettings() {
    List<String> values = [];
    for (var controller in controllers) {
      if (controller.text != '') {
        values.add(controller.text);
      }
    }
    settings.writeSettings(values);
    Navigator.of(context).pop();
  }

  void _addSite() {
    setState(() {
      sites.add('https://');
      controllers = [];
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
          for (var site in sites) _getListTile(site),
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
