import 'dart:io';

/// Keeps one desktop app instance alive per user session.
///
/// The lock is a Unix domain socket: a second launch connects to the first
/// instance and gives up instead of opening another window. A stale socket left
/// by a crash is removed before binding.
class SingleInstance {
  SingleInstance._(this._server, this.path);

  final ServerSocket _server;

  /// The socket file, exposed for diagnostics and tests.
  final String path;

  bool _closed = false;

  /// A per-user, per-session path; [XDG_RUNTIME_DIR] is used when available.
  static String defaultPath() {
    final runtime = Platform.environment['XDG_RUNTIME_DIR'];
    final home = Platform.environment['HOME'];
    final base = (runtime != null && runtime.isNotEmpty)
        ? runtime
        : '${home ?? '.'}/.local/share';
    return '$base/org.elkuku.kuku_project_checker/single-instance.sock';
  }

  /// Claims the lock, or returns null when another instance already holds it.
  static Future<SingleInstance?> acquire([String? socketPath]) async {
    final path = socketPath ?? defaultPath();
    final file = File(path);
    final address = InternetAddress(path, type: InternetAddressType.unix);

    if (file.existsSync()) {
      try {
        final client = await Socket.connect(address, 0);
        client.destroy();
        return null;
      } on SocketException {
        // A crashed instance cannot clean up its socket. Remove it and retry.
        try {
          file.deleteSync();
        } on FileSystemException {
          // Another process removed it first; the bind below decides who wins.
        }
      }
    }

    Directory(file.parent.path).createSync(recursive: true);
    late final ServerSocket server;
    try {
      server = await ServerSocket.bind(address, 0);
    } on SocketException {
      return null;
    }
    server.listen((socket) => socket.destroy());
    return SingleInstance._(server, path);
  }

  /// Releases the lock. Dart also removes the socket file on close.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _server.close();
  }
}
