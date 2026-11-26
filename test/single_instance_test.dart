import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:kuku_project_checker/support/single_instance.dart';

void main() {
  late Directory dir;
  late String socket;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('single-instance-test-');
    socket = '${dir.path}/kuku-project-checker.sock';
  });

  tearDown(() async {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('only one instance can hold the lock at a time', () async {
    final first = await SingleInstance.acquire(socket);
    expect(first, isNotNull);

    expect(await SingleInstance.acquire(socket), isNull);

    await first!.close();
    final next = await SingleInstance.acquire(socket);
    expect(next, isNotNull);
    await next!.close();
  });

  test('a stale socket from a crash can be reclaimed', () async {
    File(socket).writeAsStringSync('left behind');

    final instance = await SingleInstance.acquire(socket);
    expect(instance, isNotNull);
    await instance!.close();
  });
}
