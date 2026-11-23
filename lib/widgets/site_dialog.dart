import 'package:flutter/material.dart';

import '../support/site.dart';

/// Asks for a site's name, address and local repository; [site] is the one to edit, or
/// null to add a new one. Returns the site, or null if the dialog was cancelled.
Future<Site?> showSiteDialog(BuildContext context, {Site? site}) =>
    showDialog<Site>(
      context: context,
      builder: (_) => _SiteDialog(site: site),
    );

class _SiteDialog extends StatefulWidget {
  final Site? site;

  const _SiteDialog({this.site});

  @override
  State<_SiteDialog> createState() => _SiteDialogState();
}

class _SiteDialogState extends State<_SiteDialog> {
  late final name = TextEditingController(text: widget.site?.name ?? '');
  late final url = TextEditingController(text: widget.site?.url ?? 'https://');
  late final repoPath =
      TextEditingController(text: widget.site?.repoPath ?? '');

  /// The address error shows only after the first try to save.
  bool showErrors = false;

  bool get isNew => widget.site == null;

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
    ));
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
              decoration: const InputDecoration(
                labelText: 'Local repository',
                hintText: '~/repos/shop',
                helperText:
                    'Optional; shows the repository status, its changes and deploys',
              ),
              onSubmitted: (_) => _save(),
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
