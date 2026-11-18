import 'dart:convert';
import 'dart:io';

import 'repo_status.dart';

/// A file with uncommitted changes, from `git status`.
class ChangedFile {
  /// The two-letter status of `git status --porcelain`, e.g. " M", "A ", "??".
  final String code;
  final String path;

  /// The old path of a renamed or copied file.
  final String? fromPath;

  const ChangedFile(this.code, this.path, {this.fromPath});

  bool get isUntracked => code == '??';

  /// A word for the change, from the staged and the working tree status.
  String get state {
    if (isUntracked) return 'new';
    final letters = code.replaceAll(' ', '');

    return switch (letters.isEmpty ? '' : letters[0]) {
      'M' => 'modified',
      'A' => 'added',
      'D' => 'deleted',
      'R' => 'renamed',
      'C' => 'copied',
      'U' => 'conflict',
      'T' => 'type changed',
      _ => code.trim(),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is ChangedFile &&
      other.code == code &&
      other.path == path &&
      other.fromPath == fromPath;

  @override
  int get hashCode => Object.hash(code, path, fromPath);

  @override
  String toString() => '$code $path${fromPath == null ? '' : ' <- $fromPath'}';
}

/// Reads the uncommitted changes of a local repository.
class RepoChanges {
  final String path;

  RepoChanges(String repoPath) : path = RepoStatus.expandHome(repoPath);

  /// The changed files, staged or not, and untracked files.
  Future<List<ChangedFile>> files() async {
    // -z: NUL separated, paths unquoted, so spaces and umlauts come through as they are.
    final output = await _git(['status', '--porcelain=v1', '-z']);

    return parseStatus(output);
  }

  /// The diff of one file against the last commit (staged and unstaged changes).
  /// An untracked file is shown as completely added.
  Future<String> diff(ChangedFile file) async {
    if (file.isUntracked) {
      final target = '$path/${file.path}';
      if (await Directory(target).exists()) {
        final files = await _git(
            ['ls-files', '--others', '--exclude-standard', '--', file.path]);

        return 'New folder with these untracked files:\n$files';
      }

      // Exit code 1 means "there are differences" here.
      return _git(
          ['diff', '--no-color', '--no-index', '--', '/dev/null', file.path],
          okExitCodes: {0, 1});
    }

    final diff = await _git([
      'diff',
      '--no-color',
      'HEAD',
      '--',
      if (file.fromPath != null) file.fromPath!,
      file.path,
    ]);

    return diff.isEmpty
        ? 'No differences to the last commit (only the file mode changed?)'
        : diff;
  }

  static List<ChangedFile> parseStatus(String output) {
    final entries = output.split('\x00');
    final files = <ChangedFile>[];

    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      if (entry.length < 4) continue;

      final code = entry.substring(0, 2);
      final filePath = entry.substring(3);

      // A rename or copy is followed by the old path.
      if (code.contains('R') || code.contains('C')) {
        files.add(ChangedFile(code, filePath,
            fromPath: i + 1 < entries.length ? entries[++i] : null));
      } else {
        files.add(ChangedFile(code, filePath));
      }
    }

    return files;
  }

  Future<String> _git(List<String> args,
      {Set<int> okExitCodes = const {0}}) async {
    final result = await Process.run('git', ['-C', path, ...args],
        stdoutEncoding: utf8, stderrEncoding: utf8);

    if (!okExitCodes.contains(result.exitCode)) {
      throw RepoStatusException(
          'git ${args.first} failed: ${(result.stderr as String).trim()}');
    }

    return result.stdout as String;
  }
}
