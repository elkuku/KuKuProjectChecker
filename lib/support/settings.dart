import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'site.dart';

class Settings {
  Future<List<Site>> readSettings() async {
    try {
      final file = await _localFile;
      final contents = await file.readAsString();

      return (jsonDecode(contents) as List).map(Site.fromJson).toList();
    } catch (e) {
      return [];
    }
  }

  Future<File> writeSettings(List<Site> sites) async {
    final file = await _localFile;

    return file.writeAsString(jsonEncode(sites));
  }

  Future<String> get _localPath async {
    final directory = await getApplicationSupportDirectory();

    return directory.path;
  }

  Future<File> get _localFile async {
    final path = await _localPath;
    return File('$path/settings.json');
  }
}
