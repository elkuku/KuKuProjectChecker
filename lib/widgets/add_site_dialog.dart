import 'dart:io';

import 'package:flutter/material.dart';

import '../support/deployer.dart' show RunFunction;
import '../support/repo_status.dart';
import '../support/server.dart';
import '../support/site.dart';
import '../support/site_creator.dart';
import 'environments_dialog.dart' show EnvironmentEditor;
import 'push_log_view.dart';
import 'site_dialog.dart' show PickFolder, collapseHome;

/// The two ways of adding a site, now handled by one wizard.
enum AddSiteSource { existing, template }

/// Adds a site to the list, either by registering an existing local project or by
/// creating a new one on a KMyServer. Returns the new site, or null if cancelled/failed.
///
/// [servers] holds all configured servers: the KMyServer subset offers the template flow,
/// while the environment editor of an existing project can use any server.
Future<Site?> showAddSiteDialog(
  BuildContext context, {
  required List<Server> servers,
  Server? server,
  AddSiteSource source = AddSiteSource.existing,
  required RunFunction run,
  required PickFolder pickFolder,
  Future<bool> Function(String path)? exists,
}) =>
    showDialog<Site>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AddSiteDialog(
        servers: servers,
        server: server,
        source: source,
        run: run,
        pickFolder: pickFolder,
        exists: exists ??
            (path) async =>
                await Directory(path).exists() || await File(path).exists(),
      ),
    );

enum _Stage { form, running, done, failed }

class _AddSiteDialog extends StatefulWidget {
  final List<Server> servers;
  final Server? server;
  final AddSiteSource source;
  final RunFunction run;
  final PickFolder pickFolder;
  final Future<bool> Function(String path) exists;

  const _AddSiteDialog({
    required this.servers,
    this.server,
    required this.source,
    required this.run,
    required this.pickFolder,
    required this.exists,
  });

  @override
  State<_AddSiteDialog> createState() => _AddSiteDialogState();
}

class _AddSiteDialogState extends State<_AddSiteDialog> {
  final form = GlobalKey<FormState>();
  late AddSiteSource source = widget.source;

  List<Server> get _kmyservers =>
      widget.servers.where((server) => server.isKMyServer).toList();

  // An existing project needs no server; the template form is disabled without one.
  late Server? server = widget.server ?? (_kmyservers.isEmpty ? null : _kmyservers.first);

  /// Fields for an existing project.
  final projectName = TextEditingController();
  final localRepo = TextEditingController();
  final projectGithubRepo = TextEditingController();
  final devUrl = TextEditingController();
  List<SiteTarget> targets = const [];
  String? targetError;

  /// Fields for a new site from a template.
  final name = TextEditingController();
  final displayName = TextEditingController();
  final domain = TextEditingController();
  final githubRepoUrl = TextEditingController();
  final otherTemplate = TextEditingController();
  late final parent =
      TextEditingController(text: RepoStatus.expandHome('~/repos'));
  String template = siteTemplates.keys.first;
  bool github = true;
  bool githubPrivate = true;

  String? folderError;

  _Stage stage = _Stage.form;
  CreateStep? step;
  String? error;
  final List<String> output = [];

  static const _other = '';

  @override
  void dispose() {
    for (final c in [
      projectName,
      localRepo,
      projectGithubRepo,
      devUrl,
      name,
      displayName,
      domain,
      githubRepoUrl,
      otherTemplate,
      parent,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Site get _projectSite => Site(
        name: projectName.text.trim(),
        repoPath: localRepo.text.trim(),
        githubRepo: projectGithubRepo.text.trim(),
        devUrl: devUrl.text.trim(),
        targets: targets,
      );

  NewSite get _site => NewSite(
        server: server!,
        name: name.text.trim(),
        displayName: displayName.text.trim(),
        domain: domain.text.trim(),
        url: server!.siteUrl(domain.text.trim()),
        githubRepo: githubRepoUrl.text.trim(),
        template: template == _other ? otherTemplate.text.trim() : template,
        parentDir: parent.text.trim(),
        github: github,
        githubPrivate: githubPrivate,
      );

  Future<void> _create() async {
    if (source == AddSiteSource.existing) {
      setState(() => targetError = null);
      if (!form.currentState!.validate()) return;
      if (targets.isEmpty) {
        setState(() => targetError = 'Add at least one environment');
        return;
      }
      if (mounted) Navigator.of(context).pop(_projectSite);
      return;
    }

    setState(() => folderError = null);
    if (server == null) {
      setState(() => folderError = 'Add a KMyServer in Servers… first');
      return;
    }
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

  Future<void> _chooseRepo() async {
    final current = RepoStatus.expandHome(localRepo.text.trim());
    final home = Platform.environment['HOME'] ?? '';
    final start = [current, '$home/repos', home].firstWhere(
        (dir) => dir.isNotEmpty && Directory(dir).existsSync(),
        orElse: () => '');
    final chosen = await widget.pickFolder(start.isEmpty ? null : start);
    if (chosen != null && mounted) {
      setState(() => localRepo.text = collapseHome(chosen));
    }
  }

  Future<void> _chooseFolder() async {
    final path = await widget.pickFolder(parent.text);
    if (path != null) setState(() => parent.text = path);
  }

  String _stepLabel(CreateStep s) => switch (s) {
        CreateStep.server =>
          'Create ${name.text.trim()} on ${server?.name ?? 'the server'} and deploy the template',
        CreateStep.clone => 'Clone it to ${_site.dir}',
        CreateStep.github =>
          'Create the ${githubPrivate ? 'private' : 'public'} GitHub repository',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final creating = source == AddSiteSource.template;

    return AlertDialog(
      scrollable: true,
      icon: Icon(switch (stage) {
        _Stage.done => Icons.check_circle,
        _Stage.failed => Icons.error,
        _ => creating ? Icons.add_box_outlined : Icons.folder_open_outlined,
      }),
      iconColor: switch (stage) {
        _Stage.done => Colors.green,
        _Stage.failed => theme.colorScheme.error,
        _ => null,
      },
      title: Text(switch (stage) {
        _Stage.form => creating ? 'New site from a template' : 'Add site',
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
              label: Text(creating ? 'Create' : 'Add'),
            ),
          ],
        _Stage.running => const [],
        _Stage.done => [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(Site(
                name: _site.displayName,
                repoPath: _site.dir,
                githubRepo: _site.githubRepo,
                targets: [
                  SiteTarget(
                    name: _site.name,
                    server: server!.name,
                    subdomain: _site.domain,
                    deployRemote: server!.remote,
                  )
                ],
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

  Widget _sourceSelector() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<AddSiteSource>(
            showSelectedIcon: false,
            segments: [
              const ButtonSegment(
                value: AddSiteSource.existing,
                icon: Icon(Icons.folder_open_outlined),
                label: Text('Existing project'),
              ),
              ButtonSegment(
                value: AddSiteSource.template,
                icon: const Icon(Icons.add_box_outlined),
                label: const Text('New on KMyServer'),
                enabled: _kmyservers.isNotEmpty,
              ),
            ],
            selected: {source},
            onSelectionChanged: (selected) =>
                setState(() => source = selected.first),
          ),
          if (_kmyservers.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child:
                  Text('Add a KMyServer in Servers… to create a site there.'),
            ),
          const SizedBox(height: 12),
        ],
      );

  Widget _form() => Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sourceSelector(),
            if (source == AddSiteSource.existing)
              _projectForm()
            else
              _templateForm(),
          ],
        ),
      );

  Widget _projectForm() => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: projectName,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Display name',
              hintText: 'Shop',
            ),
            validator: (text) => Site.nameError(text ?? ''),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: localRepo,
            decoration: InputDecoration(
              labelText: 'Local repository',
              hintText: '~/repos/shop',
              helperText: 'Shows the repository status, its changes and deploys',
              suffixIcon: IconButton(
                icon: const Icon(Icons.folder_open),
                tooltip: 'Choose the folder',
                onPressed: _chooseRepo,
              ),
            ),
            validator: (text) => Site.repoPathError(text ?? ''),
            onFieldSubmitted: (_) => _create(),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: projectGithubRepo,
            decoration: const InputDecoration(
              labelText: 'GitHub repository',
              hintText: 'https://github.com/elkuku/shop',
            ),
            keyboardType: TextInputType.url,
            validator: (text) => Site.githubRepoError(text ?? ''),
            onFieldSubmitted: (_) => _create(),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: devUrl,
            decoration: const InputDecoration(
              labelText: 'Dev site URL',
              hintText: 'https://dev.shop.example.com',
              helperText:
                  'Optional; a version that deploys itself from the upstream branch',
            ),
            keyboardType: TextInputType.url,
            validator: (text) =>
                (text ?? '').trim().isEmpty ? null : Site.urlError(text!),
            onFieldSubmitted: (_) => _create(),
          ),
          const SizedBox(height: 12),
          EnvironmentEditor(
            targets: targets,
            servers: widget.servers,
            onChanged: (value) => setState(() => targets = value),
          ),
          if (targetError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                targetError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      );

  Widget _templateForm() => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<Server>(
            isExpanded: true,
            initialValue: server,
            decoration: const InputDecoration(labelText: 'Server'),
            items: [
              for (final s in _kmyservers)
                DropdownMenuItem(
                    value: s,
                    child: Text(
                        '${s.name}  (${s.sshHost}${s.sshPort == null ? '' : ':${s.sshPort}'})',
                        overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (s) => setState(() => server = s!),
          ),
          if (server != null && !server!.hasUrl)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Set a base URL for ${server!.name} in Servers… first.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          TextFormField(
            controller: name,
            autofocus: true,
            decoration: const InputDecoration(
                labelText: 'Site name',
                hintText: 'shop',
                helperText:
                    'User, folder and database on the server; also the local folder'),
            validator: (text) => NewSite.nameError(text ?? ''),
          ),
          TextFormField(
            controller: displayName,
            decoration: const InputDecoration(
                labelText: 'Display name',
                hintText: 'Shop',
                helperText: 'How the project appears in the list'),
            validator: (text) => Site.nameError(text ?? ''),
          ),
          TextFormField(
            controller: domain,
            decoration: InputDecoration(
              labelText: 'Subdomain',
              hintText: 'shop',
              helperText: server?.hasUrl == true
                  ? 'Address: ${server!.siteUrl(domain.text.trim().isEmpty ? 'shop' : domain.text.trim())}'
                  : 'The label added to the server’s base URL',
            ),
            validator: (text) => NewSite.subdomainError(text ?? ''),
            onChanged: (_) => setState(() {}),
          ),
          TextFormField(
            controller: githubRepoUrl,
            decoration: const InputDecoration(
                labelText: 'GitHub repository',
                hintText: 'https://github.com/elkuku/shop',
                helperText: 'Required, even when the repository is created below'),
            keyboardType: TextInputType.url,
            validator: (text) => Site.githubRepoError(text ?? ''),
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
            title: const Text('Create a GitHub repository'),
            subtitle: const Text('With the GitHub CLI (gh); it becomes origin'),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: githubPrivate,
            onChanged: github
                ? (value) => setState(() => githubPrivate = value!)
                : null,
            title: const Text('Private repository'),
            subtitle: const Text('Unchecked creates a public repository'),
          ),
        ],
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
