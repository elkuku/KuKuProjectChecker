import 'package:flutter/material.dart';

import '../support/repo_changes.dart';

/// For file paths and diffs. Named fonts first: the generic "monospace" is resolved by
/// the desktop's font configuration, which the documentation screenshots don't have.
const monoTextStyle = TextStyle(
  fontFamily: 'Noto Sans Mono',
  fontFamilyFallback: ['DejaVu Sans Mono', 'Liberation Mono', 'monospace'],
);

/// The uncommitted files of a local repository; a tap shows the diff of a file.
class ChangesScreen extends StatefulWidget {
  final String title;
  final RepoChanges changes;

  const ChangesScreen({super.key, required this.title, required this.changes});

  @override
  State<ChangesScreen> createState() => _ChangesScreenState();
}

class _ChangesScreenState extends State<ChangesScreen> {
  late Future<List<ChangedFile>> files = widget.changes.files();

  void _reload() => setState(() => files = widget.changes.files());

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: colors.inversePrimary,
        title: Text('Changes: ${widget.title}'),
        actions: [
          IconButton(
            onPressed: _reload,
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<List<ChangedFile>>(
        future: files,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('${snapshot.error}',
                  style: TextStyle(color: colors.error)),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final changed = snapshot.data!;
          if (changed.isEmpty) {
            return const Center(child: Text('No uncommitted changes.'));
          }

          return ListView(
            children: [
              ListTile(
                dense: true,
                title: Text(
                    '${changed.length} uncommitted file${changed.length == 1 ? '' : 's'} in ${widget.changes.path}'),
              ),
              for (final file in changed)
                ListTile(
                  leading: _StateChip(file: file),
                  title: Text(file.path, style: monoTextStyle),
                  subtitle: file.fromPath == null
                      ? null
                      : Text('from ${file.fromPath}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) =>
                        DiffScreen(file: file, changes: widget.changes),
                  )),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  final ChangedFile file;

  const _StateChip({required this.file});

  @override
  Widget build(BuildContext context) {
    final color = switch (file.state) {
      'new' || 'added' => Colors.green,
      'deleted' => Colors.red,
      'conflict' => Colors.purple,
      _ => Colors.orange,
    };

    return SizedBox(
      width: 84,
      child: Text(
        file.state,
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// The diff of one file, with added and removed lines colored.
class DiffScreen extends StatelessWidget {
  final ChangedFile file;
  final RepoChanges changes;

  const DiffScreen({super.key, required this.file, required this.changes});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: colors.inversePrimary,
        title: Text(file.path),
      ),
      body: FutureBuilder<String>(
        future: changes.diff(file),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('${snapshot.error}',
                  style: TextStyle(color: colors.error)),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final lines = snapshot.data!.trimRight().split('\n');

          return SelectionArea(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: lines.length,
              itemBuilder: (context, index) => DiffLine(line: lines[index]),
            ),
          );
        },
      ),
    );
  }
}

/// One line of a unified diff.
class DiffLine extends StatelessWidget {
  final String line;

  const DiffLine({super.key, required this.line});

  /// How a line is shown: added, removed, a hunk header, a file header or context.
  static String kind(String line) {
    if (line.startsWith('+++') || line.startsWith('---')) return 'header';
    if (line.startsWith('+')) return 'added';
    if (line.startsWith('-')) return 'removed';
    if (line.startsWith('@@')) return 'hunk';
    if (line.startsWith('diff ') ||
        line.startsWith('index ') ||
        line.startsWith('new file') ||
        line.startsWith('deleted file') ||
        line.startsWith('similarity') ||
        line.startsWith('rename ')) {
      return 'header';
    }

    return 'context';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    final (background, foreground) = switch (kind(line)) {
      'added' => (Colors.green.withValues(alpha: dark ? 0.22 : 0.15), null),
      'removed' => (Colors.red.withValues(alpha: dark ? 0.22 : 0.12), null),
      'hunk' => (colors.secondaryContainer, colors.onSecondaryContainer),
      'header' => (null, colors.onSurfaceVariant),
      _ => (null, null),
    };

    return Container(
      color: background,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
      child: Text(
        line.isEmpty ? ' ' : line,
        style: monoTextStyle.copyWith(fontSize: 13, color: foreground),
      ),
    );
  }
}
