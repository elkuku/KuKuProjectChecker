import 'package:flutter/material.dart';

import '../screens/changes_screen.dart' show monoTextStyle;
import '../support/server.dart';

/// Lets the user add, edit and remove servers. Returns the new list, or null if cancelled.
Future<List<Server>?> showServersDialog(
        BuildContext context, List<Server> servers) =>
    showDialog<List<Server>>(
      context: context,
      builder: (_) => _ServersDialog(servers: servers),
    );

class _ServersDialog extends StatefulWidget {
  final List<Server> servers;

  const _ServersDialog({required this.servers});

  @override
  State<_ServersDialog> createState() => _ServersDialogState();
}

class _ServersDialogState extends State<_ServersDialog> {
  late final List<Server> servers = [...widget.servers];

  Future<void> _edit([int? index]) async {
    final server = await showDialog<Server>(
      context: context,
      builder: (_) => _ServerForm(
        server: index == null ? null : servers[index],
        takenNames: {
          for (final (i, s) in servers.indexed)
            if (i != index) s.name
        },
      ),
    );
    if (server == null) return;

    setState(
        () => index == null ? servers.add(server) : servers[index] = server);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      icon: const Icon(Icons.dns_outlined),
      title: const Text('Servers'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                'Each server is reached through a git remote of the same name in the sites\' '
                'repositories. The active server (in the app bar) is where all sites deploy.'),
            const SizedBox(height: 12),
            if (servers.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('No servers yet.'),
              ),
            for (final (index, server) in servers.indexed)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(server.isKMyServer
                    ? Icons.rocket_launch
                    : Icons.dns_outlined),
                title: Text(server.name),
                subtitle: Text(
                  'remote ${server.remote}'
                  '${server.isKMyServer ? ' · KMyServer ${server.sshHost}${server.sshPort == null ? '' : ':${server.sshPort}'}' : ''}',
                  style: monoTextStyle.copyWith(fontSize: 12),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Edit ${server.name}',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _edit(index),
                    ),
                    IconButton(
                      tooltip: 'Remove ${server.name}',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => setState(() => servers.removeAt(index)),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: () => _edit(),
              icon: const Icon(Icons.add),
              label: const Text('Add server'),
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
          onPressed: () => Navigator.of(context).pop(servers),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _ServerForm extends StatefulWidget {
  final Server? server;
  final Set<String> takenNames;

  const _ServerForm({this.server, required this.takenNames});

  @override
  State<_ServerForm> createState() => _ServerFormState();
}

String? _portError(String? text) {
  text = (text ?? '').trim();
  final n = int.tryParse(text);
  return text.isEmpty || (n != null && n > 0 && n < 65536) ? null : 'Port?';
}

class _ServerFormState extends State<_ServerForm> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.server?.name);
  late final remote = TextEditingController(text: widget.server?.remote);
  late final host = TextEditingController(text: widget.server?.sshHost);
  late final port =
      TextEditingController(text: widget.server?.sshPort?.toString() ?? '');
  late final sitePort =
      TextEditingController(text: widget.server?.sitePort?.toString() ?? '');

  @override
  void dispose() {
    for (final c in [name, remote, host, port, sitePort]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (!form.currentState!.validate()) return;
    Navigator.of(context).pop(Server(
      name: name.text.trim(),
      remote: remote.text.trim(),
      sshHost: host.text.trim(),
      sshPort: int.tryParse(port.text.trim()),
      sitePort: int.tryParse(sitePort.text.trim()),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.server == null ? 'Add server' : 'Edit server'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(
                    labelText: 'Name', hintText: 'New server'),
                validator: (text) => (text ?? '').trim().isEmpty
                    ? 'Enter a name'
                    : widget.takenNames.contains(text!.trim())
                        ? 'There is a server with this name'
                        : null,
              ),
              TextFormField(
                controller: remote,
                decoration: const InputDecoration(
                    labelText: 'Git remote', hintText: 'kmyserver'),
                validator: (text) => Server.remoteError(text ?? ''),
              ),
              const SizedBox(height: 16),
              const Align(
                alignment: Alignment.centerLeft,
                child:
                    Text('KMyServer only (to create sites from a template):'),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: host,
                      decoration: const InputDecoration(
                          labelText: 'SSH host', hintText: 'new.example.com'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 90,
                    child: TextFormField(
                      controller: port,
                      decoration: const InputDecoration(
                          labelText: 'Port', hintText: '22'),
                      validator: _portError,
                    ),
                  ),
                ],
              ),
              TextFormField(
                controller: sitePort,
                decoration: const InputDecoration(
                    labelText: 'HTTPS port of the sites',
                    hintText: '443',
                    helperText: 'e.g. 8443 for the local test VM'),
                validator: _portError,
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
