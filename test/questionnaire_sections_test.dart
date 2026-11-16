import 'package:evaluationworkspace/screens/questionnaire_editor.dart';
import 'package:evaluationworkspace/services/questionnaire_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('an ISO section saves multiple questions in order', (
    tester,
  ) async {
    final original = freeQuestionnaires.first.form!;
    QuestionnaireForm? edited;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                edited = await editQuestionnaire(context, initial: original);
              },
              child: const Text('Edit ISO template'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Edit ISO template'));
    await tester.pumpAndSettle();
    final add = find.text('Add question').first;
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();
    final question = find.widgetWithText(TextFormField, 'Question 2');
    await tester.ensureVisible(question);
    await tester.enterText(
      question,
      'Does the page recover after a failed request?',
    );
    await tester.tap(find.text('Use this version'));
    await tester.pumpAndSettle();

    expect(edited!.items.length, original.items.length + 1);
    expect(edited!.items.first, original.items.first);
    expect(edited!.items[1].section, original.items.first.section);
    expect(
      edited!.items[1].prompt,
      'Does the page recover after a failed request?',
    );
    expect(edited!.items[2], original.items[1]);
  });
}
