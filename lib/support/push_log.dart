/// The output of `git push`, sorted into what matters and what is noise.
enum PushLineKind {
  /// A branch or tag was updated: "72c6c5a..298cc88  master -> master".
  updated,

  /// Something failed: "error: …", "fatal: …", "! [rejected] …".
  error,

  /// The address pushed to: "To server:~/git/shop.git".
  target,

  /// A message from the server ("remote: …"), e.g. from its deploy hook.
  server,

  /// A notice from ssh ("** WARNING: …").
  warning,

  /// git's own progress: "Enumerating objects", "Writing objects", …
  progress,

  /// Lines without information, e.g. the progress table of curl in a Plesk hook.
  noise,
}

class PushLine {
  final PushLineKind kind;
  final String text;

  const PushLine(this.kind, this.text);

  @override
  bool operator ==(Object other) =>
      other is PushLine && other.kind == kind && other.text == text;

  @override
  int get hashCode => Object.hash(kind, text);

  @override
  String toString() => '${kind.name}: $text';
}

final _ansi = RegExp(r'\x1B\[[0-9;?]*[A-Za-z]');
final _remotePrefix = RegExp(r'^(remote:\s?)+');
final _updated = RegExp(
    r'^\s*(\+|\*|=|-)?\s*([0-9a-f]{7,}\.{2,3}[0-9a-f]{7,}|\[new (branch|tag)\]|\[deleted\])\s+\S+\s+->\s+\S+');
final _error = RegExp(
    r'^(error|fatal):|^\s*!\s*\[|Permission denied|Could not read from remote',
    caseSensitive: false);
// curl's progress table: its header lines and the rows of numbers and dashes.
final _curlTable = RegExp(r'^(% Total|Dload)|^[\d.\skKMG%:-]+$');

/// Sorts the lines of `git push` output. Repeated "remote:" prefixes are dropped,
/// and the ssh post-quantum notice is shortened to one line.
List<PushLine> parsePushOutput(Iterable<String> lines) {
  final result = <PushLine>[];
  var sshNotice = false;

  for (final raw in lines) {
    final line = raw.replaceAll(_ansi, '').trimRight();

    if (line.startsWith('**')) {
      // ssh prints a three-line notice when the server lacks post-quantum key exchange.
      if (line.contains('post-quantum')) {
        sshNotice = true;
        result.add(const PushLine(PushLineKind.warning,
            'SSH: the server does not support post-quantum key exchange (see openssh.com/pq.html)'));
      } else if (!sshNotice) {
        result.add(PushLine(
            PushLineKind.warning, line.replaceFirst(RegExp(r'^\*+\s*'), '')));
      }
      continue;
    }

    if (_remotePrefix.hasMatch(line)) {
      final message = line.replaceFirst(_remotePrefix, '').trim();
      if (message.isEmpty || _curlTable.hasMatch(message)) {
        result.add(PushLine(PushLineKind.noise, line));
      } else {
        result.add(PushLine(
            _error.hasMatch(message) ? PushLineKind.error : PushLineKind.server,
            message));
      }
      continue;
    }

    final kind = switch (line) {
      _ when line.trim().isEmpty => PushLineKind.noise,
      _ when _updated.hasMatch(line) => PushLineKind.updated,
      _ when _error.hasMatch(line) => PushLineKind.error,
      _ when line.startsWith('To ') => PushLineKind.target,
      _ when line.startsWith('Everything up-to-date') => PushLineKind.updated,
      _ => PushLineKind.progress,
    };
    result
        .add(PushLine(kind, kind == PushLineKind.updated ? line.trim() : line));
  }

  return result;
}
