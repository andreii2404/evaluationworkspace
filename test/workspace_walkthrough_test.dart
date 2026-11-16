import 'package:evaluationworkspace/app_theme.dart';
import 'package:evaluationworkspace/screens/workspace_forms.dart';
import 'package:evaluationworkspace/services/cloud_repository.dart';
import 'package:evaluationworkspace/services/questionnaire_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _sample = QuestionnaireForm(
  title: 'Sample usability check',
  items: [(section: 'Usability', prompt: 'How easy was it to find a room?')],
);

Future<void> _openForm(WidgetTester tester, Widget form) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: workshopTheme(ThemeData.dark()),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showDialog<bool>(context: context, builder: (_) => form),
            child: const Text('Open form'),
          ),
        ),
      ),
    ),
  );
  await _tap(tester, 'Open form');
}

Future<void> _tap(WidgetTester tester, String text) async {
  final button = find.text(text);
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'practice review submits straight from the tour with sample answers',
    (tester) async {
      ReviewDraft? saved;
      await _openForm(
        tester,
        ReviewForm(
          criteria: const [
            {
              'criterion_key': 'form_1',
              'prompt': 'How easy was it to find a room?',
            },
          ],
          projectBrief: const Text('Sample project brief'),
          questionnaire: _sample,
          allowUnassessed: false,
          externalOnly: false,
          practice: true,
          save: (draft) async => saved = draft,
        ),
      );

      for (var step = 0; step < 4; step++) {
        await _tap(tester, 'Next tip');
      }
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        false,
      );
      await _tap(tester, 'Submit practice');

      expect(find.text('Evaluate project · Practice'), findsNothing);
      expect(saved?.scores, {'form_1': 4});
      expect(saved?.feedback, contains('Quiet rooms'));
    },
  );

  testWidgets('practice project fills in a cleared title', (tester) async {
    WorkspaceRow? saved;
    await _openForm(
      tester,
      ProjectForm(
        practice: true,
        questionnaires: const [
          QuestionnaireChoice(id: 'practice', title: 'Practice', form: _sample),
        ],
        save: (draft) async => saved = draft,
        editQuestionnaire: (_) async => null,
        previewQuestionnaire: (_) {},
      ),
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Project title'),
      '',
    );
    await tester.pumpAndSettle();
    await _tap(tester, 'Continue');
    await _tap(tester, 'Continue');
    await _tap(tester, 'Create practice project');

    expect(find.text('New project · Practice'), findsNothing);
    expect(saved?['title'], 'Campus Study Finder');
    expect(saved?['questionnaire_form'], _sample.toJson());
  });
}
