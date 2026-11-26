import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../support/repo_status.dart';
import '../support/site.dart';

/// The parts of a project that are not an environment. The address and deploy remote
/// are edited in the Environments dialog.
typedef SiteDetails = ({String name, String repoPath, String devUrl});

/// Asks for a folder, starting in [initialDirectory]; null if the user cancelled.
typedef PickFolder = Future<String?> Function(String? initialDirectory);

/// The system's folder chooser.
Future<String?> pickFolder(String? initialDirectory) => getDirectoryPath(
      initialDirectory: initialDirectory,
      confirmButtonText: 'Choose',
    );

/// Asks for a project's name, local repository and dev site; [site] is the one to edit,
/// or null to add a new one. Returns the details, or null if the dialog was cancelled.
Future<SiteDetails?> showSiteDialog(BuildContext context,
        {Site? site, PickFolder pickFolder = pickFolder}) =>
    showDialog<SiteDetails>(
      context: context,
      builder: (_) => _SiteDialog(site: site, pickFolder: pickFolder),
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
  final PickFolder pickFolder;

  const _SiteDialog({this.site, required this.pickFolder});

  @override
  State<_SiteDialog> createState() => _SiteDialogState();
}

class _SiteDialogState extends State<_SiteDialog> {
  late final name = TextEditingController(text: widget.site?.name ?? '');
  late final repoPath =
      TextEditingController(text: widget.site?.repoPath ?? '');
  late final devUrl = TextEditingController(text: widget.site?.devUrl ?? '');

  /// An error for the optional dev site address, or null if it is empty or valid.
  String? get devUrlError =>
      devUrl.text.trim().isEmpty ? null : Site.urlError(devUrl.text);

  /// The address error shows only after the first try to save.
  bool showErrors = false;

  bool get isNew => widget.site == null;

  @override
  void dispose() {
    name.dispose();
    repoPath.dispose();
    devUrl.dispose();
    super.dispose();
  }

  void _save() {
    if (devUrlError != null) {
      setState(() => showErrors = true);
      return;
    }

    Navigator.of(context).pop((
      name: name.text.trim(),
      repoPath: repoPath.text.trim(),
      devUrl: devUrl.text.trim(),
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
                    'Optional; the first environment is used when empty',
              ),
              textInputAction: TextInputAction.next,
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
            const SizedBox(height: 12),
            ListenableBuilder(
              listenable: devUrl,
              builder: (context, _) => TextField(
                controller: devUrl,
                decoration: InputDecoration(
                  labelText: 'Dev site URL',
                  hintText: 'https://dev.shop.example.com',
                  helperText:
                      'Optional; a version that deploys itself from the upstream branch',
                  errorText: showErrors ? devUrlError : null,
                ),
                keyboardType: TextInputType.url,
                onSubmitted: (_) => _save(),
              ),
            ),
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
