import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../support/repo_status.dart';
import '../support/site.dart';

/// Lists the remotes of a repository as (name, URL).
typedef ListRemotes = Future<List<(String, String)>> Function(String repoPath);

/// Asks for a folder, starting in [initialDirectory]; null if the user cancelled.
typedef PickFolder = Future<String?> Function(String? initialDirectory);

/// The system's folder chooser.
Future<String?> pickFolder(String? initialDirectory) => getDirectoryPath(
    initialDirectory: initialDirectory, confirmButtonText: 'Choose');

/// Asks for a site's name, address, local repository and deploy remote; [site] is the one
/// to edit, or null to add a new one. [listRemotes] reads the repository's remotes for the
/// deploy remote choice, [pickFolder] chooses the repository folder. Returns the site, or
/// null if the dialog was cancelled.
Future<Site?> showSiteDialog(BuildContext context,
        {Site? site,
        ListRemotes listRemotes = RepoStatus.remotes,
        PickFolder pickFolder = pickFolder}) =>
    showDialog<Site>(
      context: context,
      builder: (_) => _SiteDialog(
          site: site, listRemotes: listRemotes, pickFolder: pickFolder),
    );

/// [path] with the home folder written as ~, like the paths typed in by hand.
String collapseHome(String path) {
  final dir = Platform.environment['HOME'];
  if (dir == null || dir.isEmpty) return path;
  if (path == dir) return '~';

  return path.startsWith('$dir/') ? '~${path.substring(dir.length)}' : path;
}

class _SiteDialog extends StatefulWidget {
  final Site? site;
  final ListRemotes listRemotes;
  final PickFolder pickFolder;

  const _SiteDialog(
      {this.site, required this.listRemotes, required this.pickFolder});

  @override
  State<_SiteDialog> createState() => _SiteDialogState();
}

class _SiteDialogState extends State<_SiteDialog> {
  late final name = TextEditingController(text: widget.site?.name ?? '');
  late final url = TextEditingController(text: widget.site?.url ?? 'https://');
  late final repoPath =
      TextEditingController(text: widget.site?.repoPath ?? '');

  /// Site.autoDeploy, Site.noDeploy or a remote name.
  late String deployRemote = widget.site?.deployRemote ?? Site.autoDeploy;

  /// The remotes of the repository in the field, read again when the path changes.
  Future<List<(String, String)>>? remotes;
  String _remotesOf = '';

  /// The address error shows only after the first try to save.
  bool showErrors = false;

  bool get isNew => widget.site == null;

  @override
  void initState() {
    super.initState();
    _readRemotes();
    repoPath.addListener(_readRemotes);
  }

  void _readRemotes() {
    final path = repoPath.text.trim();
    if (path == _remotesOf && remotes != null) return;

    setState(() {
      _remotesOf = path;
      remotes =
          path.isEmpty ? Future.value(const []) : widget.listRemotes(path);
    });
  }

  @override
  void dispose() {
    name.dispose();
    url.dispose();
    repoPath.dispose();
    super.dispose();
  }

  void _save() {
    if (Site.urlError(url.text) != null) {
      setState(() => showErrors = true);
      return;
    }

    Navigator.of(context).pop(Site(
      name: name.text.trim(),
      url: url.text.trim(),
      repoPath: repoPath.text.trim(),
      deployRemote: deployRemote,
    ));
  }

  /// Lets the user choose the repository folder; starts in the folder in the field if it
  /// exists, else in ~/repos or the home folder.
  Future<void> _chooseFolder() async {
    final current = RepoStatus.expandHome(repoPath.text.trim());
    final home = Platform.environment['HOME'] ?? '';
    final start = [current, '$home/repos', home].firstWhere(
        (dir) => dir.isNotEmpty && Directory(dir).existsSync(),
        orElse: () => '');

    final chosen = await widget.pickFolder(start.isEmpty ? null : start);
    if (chosen == null || !mounted) return;

    repoPath.text = collapseHome(chosen);
  }

  Widget _deployRemoteField() => FutureBuilder<List<(String, String)>>(
        future: remotes,
        builder: (context, snapshot) {
          final loaded = snapshot.connectionState == ConnectionState.done;
          final list = snapshot.data ?? const <(String, String)>[];
          final names = [for (final (name, _) in list) name];
          final picked = RepoStatus.pickDeployRemote(list);

          final automatic = !loaded
              ? 'Automatic'
              : picked == null
                  ? 'Automatic (none found)'
                  : 'Automatic ($picked)';

          return DropdownButtonFormField<String>(
            // Rebuilt when the remotes change, so the shown choice stays valid.
            key:
                ValueKey('deployRemote:$_remotesOf:$loaded:${names.join(',')}'),
            initialValue: deployRemote,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Deploy remote',
              helperText: 'The git remote that Deploy pushes to',
            ),
            items: [
              DropdownMenuItem(value: Site.autoDeploy, child: Text(automatic)),
              for (final (name, url) in list)
                DropdownMenuItem(
                  value: name,
                  child:
                      Text('$name  ·  $url', overflow: TextOverflow.ellipsis),
                ),
              // A saved remote the repository doesn't have (any more).
              if (deployRemote != Site.autoDeploy &&
                  deployRemote != Site.noDeploy &&
                  !names.contains(deployRemote))
                DropdownMenuItem(
                  value: deployRemote,
                  child:
                      Text(loaded ? '$deployRemote (not found)' : deployRemote),
                ),
              const DropdownMenuItem(
                  value: Site.noDeploy, child: Text('No deploys')),
            ],
            onChanged: (value) => setState(() => deployRemote = value!),
          );
        },
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(isNew ? 'Add site' : 'Edit site'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: isNew,
              decoration: const InputDecoration(
                labelText: 'Name',
                helperText:
                    'Optional; without one, the host of the address is used',
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            ListenableBuilder(
              listenable: url,
              builder: (context, _) => TextField(
                controller: url,
                decoration: InputDecoration(
                  labelText: 'Site URL',
                  hintText: 'https://shop.example.com',
                  errorText: showErrors ? Site.urlError(url.text) : null,
                ),
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.next,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: repoPath,
              decoration: InputDecoration(
                labelText: 'Local repository',
                hintText: '~/repos/shop',
                helperText:
                    'Optional; shows the repository status, its changes and deploys',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.folder_open),
                  tooltip: 'Choose the folder',
                  onPressed: _chooseFolder,
                ),
              ),
              onSubmitted: (_) => _save(),
            ),
            if (_remotesOf.isNotEmpty) ...[
              const SizedBox(height: 12),
              _deployRemoteField(),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(isNew ? 'Add' : 'Save'),
        ),
      ],
    );
  }
}
