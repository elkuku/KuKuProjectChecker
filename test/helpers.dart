import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The card containing [project] in its title.
Finder projectCard(String project) => find.ancestor(
      of: find.text(project),
      matching: find.byType(Card),
    );

/// Expands a project or temporary server row so its details and extra buttons show.
Future<void> expandRow(WidgetTester tester, String title) async {
  await tester.tap(find.descendant(
    of: projectCard(title),
    matching: find.byTooltip('Show details'),
  ));
  await tester.pumpAndSettle();
}

/// Taps a button on the row whose title is [title].
Future<void> tapRowButton(
  WidgetTester tester,
  String title,
  String tooltip, {
  bool expand = false,
}) async {
  if (expand) await expandRow(tester, title);
  await tester.tap(find.descendant(
    of: projectCard(title),
    matching: find.byTooltip(tooltip),
  ));
  await tester.pumpAndSettle();
}

/// Opens the only dropdown left on a row: Open in…
Future<void> openOpenInMenu(WidgetTester tester, String title) async {
  await tester.tap(find.descendant(
    of: projectCard(title),
    matching: find.byTooltip('Open in…'),
  ));
  await tester.pumpAndSettle();
}
