import 'package:flutter/material.dart';

import '../support/settings.dart';
import '../support/site.dart';

class SettingsScreen extends MaterialPageRoute<Null> {
  SettingsScreen({Settings? settings})
      : super(builder: (BuildContext ctx) {
          return SettingsPage(settings: settings);
        });
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.settings});

  /// Where the sites are read from and saved to; the default is the settings file.
  final Settings? settings;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

/// The text fields of one site.
class _SiteFields {
  final TextEditingController name;
  final TextEditingController url;
  final TextEditingController repoPath;

  /// A site just added with the "Add site" button; its name field gets the focus.
  final bool isNew;

  _SiteFields(Site site, {this.isNew = false})
      : name = TextEditingController(text: site.name),
        url = TextEditingController(text: site.url),
        repoPath = TextEditingController(text: site.repoPath);

  Listenable get changes => Listenable.merge([name, url]);

  Site toSite() => Site(
        name: name.text.trim(),
        url: url.text.trim(),
        repoPath: repoPath.text.trim(),
      );

  /// An error for the URL field, or null if the URL is fine.
  String? get urlError {
    final text = url.text.trim();
    if (text.isEmpty || text == 'https://' || text == 'http://') {
      return 'Enter the address of the site';
    }
    final uri = Uri.tryParse(text);
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty) {
      return 'Use a full address, like https://shop.example.com';
    }

    return null;
  }

  void dispose() {
    name.dispose();
    url.dispose();
    repoPath.dispose();
  }
}

class _SettingsPageState extends State<SettingsPage> {
  final List<_SiteFields> fields = [];
  late final Settings settings = widget.settings ?? Settings();
  bool loaded = false;

  /// Errors are shown only after the first try to save.
  bool showErrors = false;

  @override
  void initState() {
    super.initState();

    settings.readSettings().then((sites) {
      if (!mounted) return;
      setState(() {
        fields.addAll(sites.map(_SiteFields.new));
        loaded = true;
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

  void _save() {
    if (fields.any((field) => field.urlError != null)) {
      setState(() => showErrors = true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Some sites have no valid address. Fix or remove them.'),
      ));

      return;
    }

    settings.writeSettings([for (final field in fields) field.toSite()]);
    Navigator.of(context).pop();
  }

  void _moveSite(int oldIndex, int newIndex) {
    setState(() {
      fields.insert(newIndex, fields.removeAt(oldIndex));
    });
  }

  void _addSite() {
    setState(() {
      fields.add(_SiteFields(const Site(url: 'https://'), isNew: true));
    });
  }

  void _removeSite(_SiteFields field) {
    setState(() {
      fields.remove(field);
      field.dispose();
    });
  }

  Widget _siteCard(_SiteFields field, int index) {
    final colors = Theme.of(context).colorScheme;

    InputDecoration decoration(String label, IconData icon,
            {String? hint, String? helper, String? error}) =>
        InputDecoration(
          labelText: label,
          hintText: hint,
          helperText: helper,
          errorText: error,
          prefixIcon: Icon(icon),
          border: const OutlineInputBorder(),
          isDense: true,
        );

    return Card(
      key: ObjectKey(field),
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 12, 16),
        child: Column(
          children: [
            // Header: drag handle, the site's name as it appears in the list, remove.
            ListenableBuilder(
              listenable: field.changes,
              builder: (context, _) {
                final site = field.toSite();

                return Row(
                  children: [
                    ReorderableDragStartListener(
                      index: index,
                      child: const MouseRegion(
                        cursor: SystemMouseCursors.grab,
                        child: Tooltip(
                          message: 'Drag to reorder',
                          child: Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(Icons.drag_indicator),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        site.url.isEmpty || site.url == 'https://'
                            ? (site.name.isEmpty ? 'New site' : site.name)
                            : site.displayName,
                        style: Theme.of(context).textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      onPressed: () => _removeSite(field),
                      tooltip: 'Remove this site',
                      color: colors.error,
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                );
              },
            ),
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  TextField(
                    controller: field.name,
                    autofocus: field.isNew,
                    decoration: decoration('Name', Icons.label_outline,
                        hint: 'My shop',
                        helper: 'Optional; the host is used if empty'),
                  ),
                  const SizedBox(height: 12),
                  ListenableBuilder(
                    listenable: field.url,
                    builder: (context, _) => TextField(
                      controller: field.url,
                      keyboardType: TextInputType.url,
                      decoration: decoration('Site URL', Icons.link,
                          hint: 'https://shop.example.com',
                          error: showErrors ? field.urlError : null),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: field.repoPath,
                    decoration: decoration(
                        'Local repository', Icons.folder_outlined,
                        hint: '~/repos/shop',
                        helper:
                            'Optional; shows the git status, the changes and the "Open in" apps'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
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
          const Text('Add the Symfony sites you want to keep an eye on.'),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Sites'),
        actions: [
          IconButton(
            onPressed: _addSite,
            tooltip: 'Add site',
            icon: const Icon(Icons.add),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 12),
            child: FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: const Text('Save'),
            ),
          ),
        ],
      ),
      body: !loaded
          ? const Center(child: CircularProgressIndicator())
          : fields.isEmpty
              ? _emptyState()
              : ReorderableListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  buildDefaultDragHandles: false,
                  itemCount: fields.length,
                  itemBuilder: (context, index) =>
                      _siteCard(fields[index], index),
                  onReorderItem: _moveSite,
                ),
    );
  }
}
