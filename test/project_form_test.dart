import 'package:evaluationworkspace/app_theme.dart';
import 'package:evaluationworkspace/screens/workspace_forms.dart';
import 'package:evaluationworkspace/services/cloud_repository.dart';
import 'package:evaluationworkspace/services/questionnaire_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('project wizard preserves inputs and retries a failed save', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    WorkspaceRow? created;
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: workshopTheme(ThemeData.dark()),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (_) => ProjectForm(
                  save: (values) async {
                    if (++attempts == 1) {
                      throw const FormatException('Try saving again.');
                    }
                    created = values;
                  },
                  editQuestionnaire: (_) async =>
                      freeQuestionnaires.first.form!,
                  previewQuestionnaire: (_) {},
                ),
              ),
              child: const Text('Open project form'),
            ),
          ),
        ),
      ),
    );

    Future<void> tap(String label) async {
      final button = find.text(label);
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    Future<void> enter(String label, String value) async {
      final field = find.widgetWithText(TextFormField, label);
      await tester.ensureVisible(field);
      await tester.enterText(field, value);
      await tester.pumpAndSettle();
    }

    await tap('Open project form');
    await tap('Continue');
    expect(find.text('Enter project title'), findsOneWidget);
    expect(find.text('Evaluator instructions'), findsNothing);
    await enter('Project title', 'Campus Clinic');
    await enter('Direct project link', 'https://example.test/clinic');
    await enter('Project brief', 'Help students book appointments.');
    await tap('Continue');
    expect(find.text('Evaluator instructions'), findsOneWidget);
    await enter(
      'What should evaluators try?',
      'Book an appointment and check the confirmation.',
    );
    await tap('Back');
    expect(find.text('Campus Clinic'), findsOneWidget);
    await tap('Continue');
    expect(
      find.text('Book an appointment and check the confirmation.'),
      findsOneWidget,
    );
    await tap('Continue');
    await tap('Create project');
    expect(
      find.text('Build a questionnaire with at least one question.'),
      findsOneWidget,
    );
    expect(attempts, 0);
    await tap('Build questionnaire');
    await tap('Create project');
    expect(find.text('Try saving again.'), findsOneWidget);
    expect(find.text(freeQuestionnaires.first.title), findsOneWidget);
    await tap('Create project');
    expect(find.text('New project'), findsNothing);
    expect(created?['title'], 'Campus Clinic');
    expect(
      created?['test_instructions'],
      'Book an appointment and check the confirmation.',
    );
    expect(
      created?['questionnaire_form'],
      freeQuestionnaires.first.form!.toJson(),
    );
    expect(created?['rubric_id'], isNull);
  });
}
