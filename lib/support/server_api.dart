import 'dart:convert';

import 'deployer.dart';
import 'server.dart';
import 'server_health.dart';

/// Reads a server's status over SSH. Commands are fixed: no free-form input is sent.
typedef FetchServerHealth = Future<ServerHealth> Function(Server server);

class ServerApi {
  final RunFunction run;

  ServerApi({RunFunction? run}) : run = run ?? runCommand;

  /// Runs the installed `server-health --json` as root on [server].
  Future<ServerHealth> health(Server server) async {
    if (!server.isKMyServer) {
      throw ArgumentError.value(server.name, 'server', 'No SSH host is set');
    }

    final output = <String>[];
    final exitCode = await run(
      'ssh',
      server.sshArgs('root', const [
        '/usr/local/sbin/server-health',
        '--json',
      ]),
      output.add,
    );
    if (exitCode != 0) {
      throw Exception(
          'server-health failed (exit $exitCode)\n${output.join('\n')}');
    }

    return ServerHealth.fromJson(_json(output));
  }

  /// ssh can write connection notices to stderr; [runCommand] merges both streams. Use the
  /// JSON object in the middle instead of requiring the first line to be `{`.
  Map<String, dynamic> _json(List<String> output) {
    final text = output.join('\n');
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw FormatException('No JSON in server-health output', text);
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(text.substring(start, end + 1));
    } on FormatException {
      throw FormatException('Invalid server-health JSON', text);
    }
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('server-health did not return an object', text);
    }
    return decoded;
  }
}
