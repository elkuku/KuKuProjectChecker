import 'package:flutter/material.dart';

import '../screens/changes_screen.dart' show monoTextStyle;
import '../support/server.dart';
import '../support/site.dart';

/// Edits the environments of one project. Returns null when cancelled.
Future<List<SiteTarget>?> showEnvironmentsDialog(
  BuildContext context, {
  required List<SiteTarget> targets,
  required List<Server> servers,
}) =>
    showDialog<List<SiteTarget>>(
      context: context,
      builder: (_) => _EnvironmentsDialog(targets: targets, servers: servers),
    ).then((value) => value);

class _EnvironmentsDialog extends StatefulWidget {
  final List<SiteTarget> targets;
  final List<Server> servers;

  const _EnvironmentsDialog({required this.targets, required this.servers});

  @override
  State<_EnvironmentsDialog> createState() => _EnvironmentsDialogState();
}

class _EnvironmentsDialogState extends State<_EnvironmentsDialog> {
  late List<SiteTarget> targets = [...widget.targets];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      icon: const Icon(Icons.layers_outlined),
      title:
          Text(targets.isEmpty ? 'First environment' : 'Project environments'),
      content: SizedBox(
        width: 560,
        child: EnvironmentEditor(
          targets: widget.targets,
          servers: widget.servers,
          onChanged: (value) => setState(() => targets = value),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed:
              targets.isEmpty ? null : () => Navigator.of(context).pop(targets),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// The editable list of a project's environments. Shared by the environments dialog
/// and the add-site wizard; [onChanged] receives the full list after every edit.
class EnvironmentEditor extends StatefulWidget {
  final List<SiteTarget> targets;
  final List<Server> servers;
  final ValueChanged<List<SiteTarget>> onChanged;

  const EnvironmentEditor({
    super.key,
    required this.targets,
    required this.servers,
    required this.onChanged,
  });

  @override
  State<EnvironmentEditor> createState() => _EnvironmentEditorState();
}

class _EnvironmentEditorState extends State<EnvironmentEditor> {
  late List<SiteTarget> targets = [...widget.targets];

  Future<void> _edit([int? index]) async {
    final target = await showDialog<SiteTarget>(
      context: context,
      builder: (_) => _TargetForm(
        target: index == null ? null : targets[index],
        servers: widget.servers,
        takenNames: {
          for (final (i, t) in targets.indexed)
            if (i != index) t.name
        },
      ),
    );
    if (target == null || !mounted) return;
    setState(
        () => index == null ? targets.add(target) : targets[index] = target);
    widget.onChanged(List.unmodifiable(targets));
  }

  void _remove(int index) {
    setState(() => targets.removeAt(index));
    widget.onChanged(List.unmodifiable(targets));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(targets.isEmpty
            ? 'Add the address of this project. You can add more environments later.'
            : 'Each environment has its own address and deploy remote. A server with a '
                'domain suffix suggests a domain for new sites.'),
        const SizedBox(height: 12),
        if (targets.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('No environment yet — add one to continue.'),
          ),
        for (final (index, target) in targets.indexed)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(target.server.isEmpty
                ? Icons.computer_outlined
                : Icons.dns_outlined),
            title: Text(target.name),
            subtitle: Text(
              '${target.server.isEmpty ? 'no server' : target.server} · '
              '${target.url}'
              '${target.deployRemote.isEmpty ? '' : ' · remote ${target.deployRemote}'}',
              style: monoTextStyle.copyWith(fontSize: 11),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Edit ${target.name}',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _edit(index),
                ),
                IconButton(
                  tooltip: 'Remove ${target.name}',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _remove(index),
                ),
              ],
            ),
          ),
        TextButton.icon(
          onPressed: () => _edit(),
          icon: const Icon(Icons.add),
          label: const Text('Add environment'),
        ),
      ],
    );
  }
}

class _TargetForm extends StatefulWidget {
  final SiteTarget? target;
  final List<Server> servers;
  final Set<String> takenNames;

  const _TargetForm({
    this.target,
    required this.servers,
    required this.takenNames,
  });

  @override
  State<_TargetForm> createState() => _TargetFormState();
}

class _TargetFormState extends State<_TargetForm> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.target?.name);
  late final server = TextEditingController(text: widget.target?.server ?? '');
  late final url = TextEditingController(text: widget.target?.url);
  late final deployRemote =
      TextEditingController(text: widget.target?.deployRemote ?? '');

  @override
  void dispose() {
    for (final controller in [name, server, url, deployRemote]) {
      controller.dispose();
    }
    super.dispose();
  }

  Server? get selectedServer {
    for (final candidate in widget.servers) {
      if (candidate.name == server.text.trim()) return candidate;
    }
    return null;
  }

  void _save() {
    if (!form.currentState!.validate()) return;
    Navigator.of(context).pop(SiteTarget(
      name: name.text.trim(),
      server: server.text.trim(),
      url: url.text.trim(),
      deployRemote: deployRemote.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final chosen = selectedServer;

    return AlertDialog(
      title:
          Text(widget.target == null ? 'Add environment' : 'Edit environment'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(
                    labelText: 'Name', hintText: 'plesk, local, vm…'),
                validator: (text) {
                  final error = SiteTarget.nameError(text ?? '');
                  if (error != null) return error;
                  return widget.takenNames.contains(text!.trim())
                      ? 'There is an environment with this name'
                      : null;
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                // An empty value stands for a local Symfony site or a project whose
                // deploy remote is managed outside a server entry.
                initialValue: widget.servers.any((s) => s.name == server.text)
                    ? server.text
                    : '',
                decoration: const InputDecoration(labelText: 'Server'),
                items: [
                  const DropdownMenuItem(
                      value: '', child: Text('No server (local/own remote)')),
                  for (final candidate in widget.servers)
                    DropdownMenuItem(
                        value: candidate.name, child: Text(candidate.name)),
                ],
                onChanged: (value) => setState(() => server.text = value ?? ''),
              ),
              if (chosen != null && chosen.domainSuffix.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'New sites on ${chosen.name}: <site>.${chosen.domainSuffix}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              TextFormField(
                controller: url,
                decoration: const InputDecoration(
                  labelText: 'Address',
                  hintText: 'https://shop.example.com',
                ),
                validator: (text) => SiteTarget.urlError(text ?? ''),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: deployRemote,
                decoration: const InputDecoration(
                  labelText: 'Deploy remote',
                  helperText: 'blank = automatic, "-" = never deploy',
                ),
                validator: (text) => SiteTarget.deployRemoteError(text ?? ''),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('OK')),
      ],
    );
  }
}
