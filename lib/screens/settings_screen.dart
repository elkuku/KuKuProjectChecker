import 'dart:async';

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

  /// How long to wait after the last change before saving.
  static const saveDelay = Duration(milliseconds: 600);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

/// The text fields of one site.
class _SiteFields {
  final TextEditingController name;
  final TextEditingController url;
  final TextEditingController repoPath;
  final String _initialUrl;

  /// A site just added with the "Add site" button; its name field gets the focus.
  final bool isNew;

  /// Whether the card shows the fields or only its header.
  bool expanded;

  _SiteFields(Site site, {this.isNew = false})
      : name = TextEditingController(text: site.name),
        url = TextEditingController(text: site.url),
        repoPath = TextEditingController(text: site.repoPath),
        _initialUrl = site.url,
        expanded = isNew;

  Listenable get changes => Listenable.merge([name, url, repoPath]);

  Site toSite() => Site(
        name: name.text.trim(),
        url: url.text.trim(),
        repoPath: repoPath.text.trim(),
      );

  /// A new site nobody has filled in yet; it is left out when saving.
  bool get isBlank {
    final site = toSite();

    return site.name.isEmpty &&
        site.repoPath.isEmpty &&
        (site.url.isEmpty || site.url == 'https://' || site.url == 'http://');
  }

  /// The URL was edited, so a wrong one is worth pointing out.
  bool get urlTouched => url.text != _initialUrl;

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

enum _SaveState { saved, pending, invalid }

class _SettingsPageState extends State<SettingsPage> {
  final List<_SiteFields> fields = [];
  late final Settings settings = widget.settings ?? Settings();
  bool loaded = false;

  /// Shows the address errors of all sites, also those not edited yet.
  bool showErrors = false;

  _SaveState saveState = _SaveState.saved;
  Timer? _saveTimer;

  /// The last write; the next one waits for it, so the file is written in order.
  Future<void> _lastWrite = Future.value();

  @override
  void initState() {
    super.initState();

    settings.readSettings().then((sites) {
      if (!mounted) return;
      setState(() {
        fields.addAll(sites.map(_watch));
        loaded = true;
      });
    });
  }

  @override
  void dispose() {
    // Closing the app with the settings open still saves what is valid.
    if (_saveTimer?.isActive ?? false) _write(_validSites());
    _saveTimer?.cancel();
    for (var field in fields) {
      field.dispose();
    }
    super.dispose();
  }

  _SiteFields _watch(Site site, {bool isNew = false}) {
    final field = _SiteFields(site, isNew: isNew);
    field.changes.addListener(_changed);

    return field;
  }

  List<_SiteFields> get _toSave => [
        for (final field in fields)
          if (!field.isBlank) field
      ];

  List<Site> _validSites() => [
        for (final field in _toSave)
          if (field.urlError == null) field.toSite()
      ];

  bool get _allValid => _toSave.every((field) => field.urlError == null);

  /// Something changed: save soon, once the user stops typing.
  void _changed() {
    _saveTimer?.cancel();
    if (!_allValid) {
      setState(() => saveState = _SaveState.invalid);

      return;
    }
    setState(() => saveState = _SaveState.pending);
    _saveTimer = Timer(SettingsPage.saveDelay, _saveNow);
  }

  void _saveNow() {
    _saveTimer?.cancel();
    if (!_allValid) return;
    _write(_validSites());
    if (mounted) setState(() => saveState = _SaveState.saved);
  }

  Future<void> _write(List<Site> sites) =>
      _lastWrite = _lastWrite.then((_) => settings.writeSettings(sites));

  /// Saves before leaving. Sites without a valid address can't be saved: the user
  /// fixes them or leaves without them.
  Future<void> _leave() async {
    _saveTimer?.cancel();

    if (!_allValid) {
      final invalid = _toSave.where((field) => field.urlError != null).toList();
      setState(() {
        showErrors = true;
        for (final field in invalid) {
          field.expanded = true;
        }
      });

      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.warning_amber),
          title: const Text('Some sites have no valid address'),
          content: Text(invalid.length == 1
              ? 'The site without a valid address can\'t be saved.'
              : 'The ${invalid.length} sites without a valid address can\'t be saved.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Leave without them'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Fix them'),
            ),
          ],
        ),
      );
      if (discard != true) return;
    }

    await _write(_validSites());
    saveState = _SaveState.saved;
    if (mounted) Navigator.of(context).pop();
  }

  void _moveSite(int oldIndex, int newIndex) {
    setState(() {
      fields.insert(newIndex, fields.removeAt(oldIndex));
    });
    _changed();
  }

  void _addSite() {
    setState(() {
      fields.add(_watch(const Site(url: 'https://'), isNew: true));
    });
  }

  void _removeSite(_SiteFields field) {
    final index = fields.indexOf(field);
    final site = field.toSite();

    setState(() {
      fields.remove(field);
    });
    // Dispose once the card is gone.
    WidgetsBinding.instance.addPostFrameCallback((_) => field.dispose());
    _changed();

    if (field.isBlank) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text('Removed ${site.name.isNotEmpty ? site.name : site.url}'),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () {
          if (!mounted) return;
          setState(() {
            fields.insert(index.clamp(0, fields.length), _watch(site));
          });
          _changed();
        },
      ),
    ));
  }

  void _setAllExpanded(bool expanded) {
    setState(() {
      for (final field in fields) {
        field.expanded = expanded;
      }
    });
  }

  Widget _siteCard(_SiteFields field, int index) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

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
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Header: drag handle, the site's name and address, remove. A click on it
          // shows or hides the fields.
          ListenableBuilder(
            listenable: field.changes,
            builder: (context, _) {
              final site = field.toSite();
              final hasUrl = !(site.url.isEmpty || site.url == 'https://');
              final error = field.urlError != null &&
                  (showErrors || field.urlTouched) &&
                  !field.isBlank;

              return InkWell(
                onTap: () => setState(() => field.expanded = !field.expanded),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
                  child: Row(
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              !hasUrl
                                  ? (site.name.isEmpty ? 'New site' : site.name)
                                  : site.displayName,
                              style: theme.textTheme.titleMedium,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (!field.expanded && hasUrl)
                              Text(
                                [
                                  site.url,
                                  if (site.repoPath.isNotEmpty) site.repoPath,
                                ].join('  ·  '),
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: colors.onSurfaceVariant),
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                      if (error)
                        Tooltip(
                          message: field.urlError!,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Icon(Icons.error_outline,
                                color: colors.error, size: 20),
                          ),
                        ),
                      IconButton(
                        onPressed: () => _removeSite(field),
                        tooltip: 'Remove this site',
                        color: colors.error,
                        icon: const Icon(Icons.delete_outline),
                      ),
                      IconButton(
                        onPressed: () =>
                            setState(() => field.expanded = !field.expanded),
                        tooltip: field.expanded ? 'Collapse' : 'Expand',
                        icon: AnimatedRotation(
                          turns: field.expanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: const Icon(Icons.expand_more),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: !field.expanded
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 12, 16),
                    child: Column(
                      children: [
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
                                error: showErrors || field.urlTouched
                                    ? field.urlError
                                    : null),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: field.repoPath,
                          decoration: decoration(
                              'Local repository', Icons.folder_outlined,
                              hint: '~/repos/shop'),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
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

  Widget _saveStatus() {
    final colors = Theme.of(context).colorScheme;
    final (IconData icon, String text, Color? color) = switch (saveState) {
      _SaveState.saved => (Icons.cloud_done_outlined, 'Saved', null),
      _SaveState.pending => (Icons.sync, 'Saving …', null),
      _SaveState.invalid => (
          Icons.error_outline,
          'Not saved: fix the address',
          colors.error
        ),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(color: color)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allExpanded = fields.isNotEmpty && fields.every((f) => f.expanded);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          title: const Text('Sites'),
          actions: [
            if (loaded) _saveStatus(),
            if (fields.isNotEmpty)
              IconButton(
                onPressed: () => _setAllExpanded(!allExpanded),
                tooltip: allExpanded ? 'Collapse all' : 'Expand all',
                icon: Icon(allExpanded ? Icons.unfold_less : Icons.unfold_more),
              ),
            if (fields.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 4, right: 12),
                child: FilledButton.icon(
                  onPressed: _addSite,
                  icon: const Icon(Icons.add),
                  label: const Text('Add site'),
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
      ),
    );
  }
}
