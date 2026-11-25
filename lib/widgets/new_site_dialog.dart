import 'dart:io';

import 'package:flutter/material.dart';

import '../support/deployer.dart' show RunFunction;
import '../support/repo_status.dart';
import '../support/server.dart';
import '../support/site.dart';
import '../support/site_creator.dart';
import 'push_log_view.dart';
import 'site_dialog.dart' show PickFolder;

/// Creates a site from a template on one of the KMyServer [servers], clones it into a local
/// folder and optionally makes a private GitHub repository. Returns the new site for the
/// list, or null if cancelled or failed.
Future<Site?> showNewSiteDialog(
  BuildContext context, {
  required List<Server> servers,
  Server? server,
  required RunFunction run,
  required PickFolder pickFolder,
  Future<bool> Function(String path)? exists,
}) =>
    showDialog<Site>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _NewSiteDialog(
        servers: servers,
        server: server,
        run: run,
        pickFolder: pickFolder,
        exists: exists ??
            (path) async =>
                await Directory(path).exists() || await File(path).exists(),
      ),
    );

enum _Stage { form, running, done, failed }

class _NewSiteDialog extends StatefulWidget {
  final List<Server> servers;
  final Server? server;
  final RunFunction run;
  final PickFolder pickFolder;
  final Future<bool> Function(String path) exists;

  const _NewSiteDialog({
    required this.servers,
    this.server,
    required this.run,
    required this.pickFolder,
    required this.exists,
  });

  @override
  State<_NewSiteDialog> createState() => _NewSiteDialogState();
}

class _NewSiteDialogState extends State<_NewSiteDialog> {
  final form = GlobalKey<FormState>();
  late Server server = widget.server ?? widget.servers.first;
  final name = TextEditingController();
  final domain = TextEditingController();
  final url = TextEditingController();
  final otherTemplate = TextEditingController();
  late final parent =
      TextEditingController(text: RepoStatus.expandHome('~/repos'));
  String template = siteTemplates.keys.first;
  bool github = true;

  /// The URL follows the domain until the user edits it.
  bool urlEdited = false;
  String? folderError;

  _Stage stage = _Stage.form;
  CreateStep? step;
  String? error;
  final List<String> output = [];

  static const _other = '';

  @override
  void dispose() {
    for (final c in [name, domain, url, otherTemplate, parent]) {
      c.dispose();
    }
    super.dispose();
  }

  NewSite get _site => NewSite(
        server: server,
        name: name.text.trim(),
        domain: domain.text.trim(),
        url: url.text.trim(),
        template: template == _other ? otherTemplate.text.trim() : template,
        parentDir: parent.text.trim(),
        github: github,
      );

  Future<void> _create() async {
    setState(() => folderError = null);
    if (!form.currentState!.validate()) return;
    final site = _site;
    if (await widget.exists(site.dir)) {
      setState(() => folderError = '${site.dir} exists already');
      return;
    }

    setState(() => stage = _Stage.running);
    String? failed;
    try {
      failed = await SiteCreator(widget.run).create(
        site,
        onStep: (s) => setState(() => step = s),
        onOutput: (line) {
          if (mounted) setState(() => output.add(line));
        },
      );
    } catch (e) {
      output.add('$e');
      failed = 'Something went wrong';
    }
    if (!mounted) return;
    setState(() {
      error = failed;
      stage = failed == null ? _Stage.done : _Stage.failed;
    });
  }

  Future<void> _chooseFolder() async {
    final path = await widget.pickFolder(parent.text);
    if (path != null) setState(() => parent.text = path);
  }

  String _stepLabel(CreateStep s) => switch (s) {
        CreateStep.server =>
          'Create ${name.text.trim()} on ${server.name} and deploy the template',
        CreateStep.clone => 'Clone it to ${_site.dir}',
        CreateStep.github => 'Create the private GitHub repository',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      scrollable: true,
      icon: Icon(switch (stage) {
        _Stage.done => Icons.check_circle,
        _Stage.failed => Icons.error,
        _ => Icons.add_box_outlined,
      }),
      iconColor: switch (stage) {
        _Stage.done => Colors.green,
        _Stage.failed => theme.colorScheme.error,
        _ => null,
      },
      title: Text(switch (stage) {
        _Stage.form => 'New site from a template',
        _Stage.running => 'Creating ${name.text.trim()} …',
        _Stage.done => '${name.text.trim()} is ready',
        _Stage.failed => error ?? 'Failed',
      }),
      content: SizedBox(
        width: 620,
        child: stage == _Stage.form ? _form() : _progress(theme),
      ),
      actions: switch (stage) {
        _Stage.form => [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: _create,
              icon: const Icon(Icons.add),
              label: const Text('Create'),
            ),
          ],
        _Stage.running => const [],
        _Stage.done => [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(Site(
                url: _site.url,
                repoPath: _site.dir,
              )),
              child: const Text('Add to the list'),
            ),
          ],
        _Stage.failed => [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
      },
    );
  }

  Widget _form() => Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<Server>(
              isExpanded: true,
              initialValue: server,
              decoration: const InputDecoration(labelText: 'Server'),
              items: [
                for (final s in widget.servers)
                  DropdownMenuItem(
                      value: s,
                      child: Text(
                          '${s.name}  (${s.sshHost}${s.sshPort == null ? '' : ':${s.sshPort}'})',
                          overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (s) => setState(() => server = s!),
            ),
            TextFormField(
              controller: name,
              autofocus: true,
              decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'shop',
                  helperText:
                      'User, folder and database on the server; also the local folder'),
              validator: (text) => NewSite.nameError(text ?? ''),
            ),
            TextFormField(
              controller: domain,
              decoration: const InputDecoration(
                  labelText: 'Domain', hintText: 'shop.example.com'),
              validator: (text) => NewSite.domainError(text ?? ''),
              onChanged: (text) {
                if (!urlEdited) url.text = 'https://${text.trim()}';
              },
            ),
            TextFormField(
              controller: url,
              decoration: const InputDecoration(
                  labelText: 'Site address',
                  helperText: 'For the list; e.g. with a port for the test VM'),
              validator: (text) => Site.urlError(text ?? ''),
              onChanged: (_) => urlEdited = true,
            ),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: template,
              decoration: const InputDecoration(labelText: 'Template'),
              items: [
                for (final MapEntry(:key, :value) in siteTemplates.entries)
                  DropdownMenuItem(
                      value: key,
                      child: Text(value, overflow: TextOverflow.ellipsis)),
                const DropdownMenuItem(
                    value: _other, child: Text('Another git repository…')),
              ],
              onChanged: (value) => setState(() => template = value!),
            ),
            if (template == _other)
              TextFormField(
                controller: otherTemplate,
                decoration: const InputDecoration(
                    labelText: 'Git URL',
                    hintText: 'https://github.com/symfony/demo.git#main'),
                validator: (text) => NewSite.templateError(text ?? ''),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: parent,
                    decoration: InputDecoration(
                        labelText:
                            'Local folder (the clone goes into <folder>/<name>)',
                        errorText: folderError),
                    validator: (text) =>
                        (text ?? '').trim().isEmpty ? 'Choose a folder' : null,
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                    onPressed: _chooseFolder, child: const Text('Choose…')),
              ],
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: github,
              onChanged: (value) => setState(() => github = value!),
              title: const Text('Create a private GitHub repository'),
              subtitle:
                  const Text('With the GitHub CLI (gh); it becomes origin'),
            ),
          ],
        ),
      );

  Widget _progress(ThemeData theme) {
    final steps = [
      CreateStep.server,
      CreateStep.clone,
      if (github) CreateStep.github,
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final s in steps)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: switch ((s, step, stage)) {
                    _ when step == null || s.index > step!.index =>
                      const Icon(Icons.radio_button_unchecked, size: 18),
                    _ when s == step && stage == _Stage.running =>
                      const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    _ when s == step && stage == _Stage.failed => Icon(
                        Icons.error,
                        size: 18,
                        color: theme.colorScheme.error),
                    _ => const Icon(Icons.check_circle,
                        size: 18, color: Colors.green),
                  },
                ),
                const SizedBox(width: 6),
                Expanded(child: Text(_stepLabel(s))),
              ],
            ),
          ),
        const SizedBox(height: 8),
        PushLogView(output: output, running: stage == _Stage.running),
        if (stage == _Stage.done)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Add it to the list to see it with the other sites.'),
          ),
      ],
    );
  }
}
