import 'dart:async';

import 'package:evaluationworkspace/screens/workspace_forms.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'typed confirmation validates, blocks repeat requests and retries',
    (tester) async {
      final pending = Completer<void>();
      var attempts = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => confirmWorkspaceAction(
                  context,
                  title: 'Delete file?',
                  subject: 'Results.csv',
                  message: 'This permanently deletes the shared file.',
                  action: 'Delete file',
                  destructive: true,
                  confirmationText: 'DELETE',
                  perform: () async {
                    if (++attempts == 1) {
                      throw const FormatException('File could not be removed.');
                    }
                    await pending.future;
                  },
                ),
                child: const Text('Open confirmation'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open confirmation'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(attempts, 0);

      await tester.tap(find.text('Open confirmation'));
      await tester.pumpAndSettle();
      final delete = find.widgetWithText(FilledButton, 'Delete file');
      await tester.tap(delete);
      await tester.pumpAndSettle();
      expect(find.text('Enter DELETE exactly as shown.'), findsOneWidget);
      expect(attempts, 0);

      await tester.enterText(find.byType(TextFormField), 'DELETE');
      await tester.tap(delete);
      await tester.pumpAndSettle();
      expect(find.text('File could not be removed.'), findsOneWidget);
      expect(attempts, 1);

      await tester.tap(delete);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Working…'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'))
            .onPressed,
        isNull,
      );
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.text('Delete file?'), findsNothing);
      expect(attempts, 2);
    },
  );

  testWidgets(
    'review needs a declaration and final confirmation before saving',
    (tester) async {
      ReviewDraft? submitted;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<bool>(
                  context: context,
                  builder: (_) => ReviewForm(
                    criteria: const [],
                    projectBrief: const Text('Project brief'),
                    allowUnassessed: false,
                    externalOnly: true,
                    save: (draft) async => submitted = draft,
                  ),
                ),
                child: const Text('Open review'),
              ),
            ),
          ),
        ),
      );

      Future<void> tap(String label) async {
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
      }

      await tap('Open review');
      await tap('Submit review');
      expect(find.text('Enter feedback and next steps'), findsOneWidget);
      expect(submitted, isNull);

      await tester.enterText(
        find.byType(TextFormField),
        'The questionnaire worked.',
      );
      await tap('Submit review');
      expect(
        find.text('Confirm that you have no conflict of interest.'),
        findsOneWidget,
      );
      expect(submitted, isNull);

      final declaration = find.byType(CheckboxListTile);
      await tester.ensureVisible(declaration);
      await tester.tap(declaration);
      await tester.pumpAndSettle();
      await tap('Submit review');
      expect(find.text('Submit this review?'), findsOneWidget);
      await tap('Cancel');
      expect(find.text('Submit review'), findsOneWidget);
      expect(submitted, isNull);
      await tap('Submit review');
      await tap('Submit final review');
      expect(submitted?.feedback, 'The questionnaire worked.');
      expect(find.text('Write review'), findsNothing);
    },
  );
}
