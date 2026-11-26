import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuku_project_checker/support/deployer.dart' show RunFunction;
import 'package:kuku_project_checker/support/server.dart';
import 'package:kuku_project_checker/support/server_actions.dart';
import 'package:kuku_project_checker/widgets/server_action_dialog.dart';

const vm = Server(
    name: 'Test VM', remote: 'vm', sshHost: 'localhost', sshPort: 2222);

Future<void> showDialog_(WidgetTester tester, ServerAction action,
    RunFunction run) async {
  // A tall window keeps the whole dialog (including the dry run form) on screen.
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    home: ServerActionDialog(
      action: action,
      server: vm,
      siteName: 'starter',
      run: run,
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('server action dialog', () {
    testWidgets('cancel runs nothing', (tester) async {
      final calls = <List<String>>[];
      await showDialog_(tester, ServerAction.backup,
          (_, arguments, __, {workingDirectory}) async {
        calls.add(arguments);
        return 0;
      });

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(calls, isEmpty);
    });

    testWidgets('shows streamed output and never hides a failed exit',
        (tester) async {
      await showDialog_(tester, ServerAction.backup,
          (_, __, onOutput, {workingDirectory}) async {
        onOutput('backup started');
        onOutput('backup failed');
        return 3;
      });

      await tester.tap(find.text('Run backup'));
      await tester.pumpAndSettle();

      expect(find.text('backup started'), findsOneWidget);
      expect(find.text('backup failed'), findsOneWidget);
      expect(find.textContaining('== exit 3'), findsOneWidget);
      expect(find.textContaining('Failed with exit 3.'), findsOneWidget);
    });

    testWidgets('site-remove shows the dry run and needs a typed name',
        (tester) async {
      final calls = <List<String>>[];
      await showDialog_(tester, ServerAction.remove,
          (_, arguments, onOutput, {workingDirectory}) async {
        calls.add(arguments);
        onOutput('would remove starter');
        return 0;
      });

      await tester.tap(find.text('Show dry run'));
      await tester.pumpAndSettle();
      expect(calls.single, ['-p', '2222', 'root@localhost',
        '/usr/local/sbin/site-remove', 'starter']);
      expect(find.textContaining('would remove starter'), findsOneWidget);

      final remove = find.ancestor(
          of: find.text('Remove site'), matching: find.byType(FilledButton));
      expect(tester.widget<FilledButton>(remove).onPressed, isNull);
      await tester.enterText(find.byType(TextField), 'starter');
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(remove).onPressed, isNotNull);

      await tester.tap(find.byType(Checkbox).at(0));
      await tester.pumpAndSettle();
      // The database option needs a second confirmation, not just the typed site name.
      expect(
          tester
              .widget<FilledButton>(find.ancestor(
                  of: find.text('Remove and drop DB'),
                  matching: find.byType(FilledButton)))
              .onPressed,
          isNull);
      await tester.tap(find.byType(Checkbox).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove and drop DB'));
      await tester.pumpAndSettle();

      expect(calls.last, [
        '-p',
        '2222',
        'root@localhost',
        '/usr/local/sbin/site-remove',
        'starter',
        '--yes',
        '--drop-db',
      ]);
    });
  });
}
