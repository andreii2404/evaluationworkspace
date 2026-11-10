const questionnaireScales = {
  'standard': [
    'Needs work',
    'Developing',
    'Meets expectations',
    'Strong',
    'Excellent',
  ],
  'iso': [
    'Poor',
    'Needs Improvement',
    'Satisfactory',
    'Very Satisfactory',
    'Excellent',
  ],
  'mars': [
    'Unacceptable',
    'Fairly Acceptable',
    'Acceptable',
    'Highly Acceptable',
  ],
};

typedef QuestionnaireItem = ({String section, String prompt});

class QuestionnaireForm {
  const QuestionnaireForm({
    required this.title,
    this.instructions = '',
    this.scale = 'standard',
    this.fields = const [],
    required this.items,
  });

  factory QuestionnaireForm.fromJson(Map<String, dynamic> json) =>
      QuestionnaireForm(
        title: json['title'] as String,
        instructions: json['instructions'] as String,
        scale: json['scale'] as String,
        fields: List<String>.from(json['fields'] as List),
        items: [
          for (final item in json['items'] as List)
            (
              section: item['section'] as String,
              prompt: item['prompt'] as String,
            ),
        ],
      );

  final String title, instructions, scale;
  final List<String> fields;
  final List<QuestionnaireItem> items;
  List<String> get levels => questionnaireScales[scale]!;

  Map<String, dynamic> toJson() => {
    'title': title,
    'instructions': instructions,
    'scale': scale,
    'fields': fields,
    'items': [
      for (final item in items)
        {'section': item.section, 'prompt': item.prompt},
    ],
  };
}

class QuestionnaireChoice {
  const QuestionnaireChoice({
    required this.id,
    required this.title,
    this.form,
    this.asset,
    this.filePath,
    this.fileName,
  });

  factory QuestionnaireChoice.fromRow(Map<String, dynamic> row) =>
      QuestionnaireChoice(
        id: row['id'] as String,
        title: row['title'] as String,
        form: switch (row['form']) {
          final Map<String, dynamic> form => QuestionnaireForm.fromJson(form),
          _ => null,
        },
        filePath: row['file_path'] as String?,
        fileName: row['file_name'] as String?,
      );

  final String id, title;
  final String? asset, filePath, fileName;
  final QuestionnaireForm? form;
}

QuestionnaireForm? projectQuestionnaire(Map<String, dynamic> project) {
  if (project['questionnaire_form'] case final Map<String, dynamic> form) {
    return QuestionnaireForm.fromJson(form);
  }
  return null;
}

final freeQuestionnaires = [
  QuestionnaireChoice(
    id: 'iso-worksheet',
    title: 'ISO/IEC 25010:2023 website questionnaire',
    asset: 'assets/questionnaires/iso-iec-25010-2023-template.docx',
    form: QuestionnaireForm(
      title: 'ISO/IEC 25010:2023 website questionnaire',
      instructions: 'Select a rating for each item based on what you tested.',
      scale: 'iso',
      fields: const [
        'Name',
        'Gender',
        'Profession',
        'Years of experience',
        'Participant category and position',
      ],
      items: const [
        (
          section: 'Functional suitability',
          prompt:
              'Can you complete the requested website tasks and get the expected results?',
        ),
        (
          section: 'Performance efficiency',
          prompt:
              'Do pages load and respond at an acceptable speed on your test device and connection?',
        ),
        (
          section: 'Compatibility',
          prompt:
              'Does the website behave as expected in the supported browsers or integrations you can test?',
        ),
        (
          section: 'Interaction capability',
          prompt:
              'Can you find controls, understand what to do next, and use the site with your usual access tools?',
        ),
        (
          section: 'Reliability',
          prompt:
              'Do repeated tasks give consistent results, and can you recover from errors or interrupted actions?',
        ),
        (
          section: 'Security',
          prompt:
              'Based on authorized tests, are sensitive information and actions restricted to the expected users?',
        ),
        (
          section: 'Maintainability',
          prompt:
              'From the available code, docs, or demonstration, how readily could a team isolate and verify a change?',
        ),
        (
          section: 'Flexibility',
          prompt:
              'Does the website adapt to changes in screen size, supported settings, or usage conditions you can test?',
        ),
        (
          section: 'Safety',
          prompt:
              'Does the site guard against foreseeable harm, such as accidental destructive actions or misleading instructions?',
        ),
      ],
    ),
  ),
  QuestionnaireChoice(
    id: 'mars-worksheet',
    title: 'MARS mobile app questionnaire',
    asset: 'assets/questionnaires/mars-questionnaire-template.docx',
    form: QuestionnaireForm(
      title: 'MARS mobile app questionnaire',
      instructions:
          'Rate each item after testing the mobile app. Add suggestions at the end.',
      scale: 'mars',
      fields: const [
        'Name',
        'Age',
        'Gender',
        'Participant category and position',
      ],
      items: [
        for (final group in const {
          'Engagement': [
            'Entertainment',
            'Interest',
            'Customization',
            'Interactivity',
            'Target Group',
          ],
          'Functionality': [
            'Performance',
            'Ease of Use',
            'Navigation',
            'Gestural Design',
          ],
          'Aesthetics': ['Layout', 'Graphics', 'Visual Appeal'],
          'Information Quality': [
            'Accuracy of App Description',
            'Quantity of Information',
            'Visual Information',
            'Credibility',
            'Evidence Base',
          ],
          'Subjective Quality': [
            'Recommendation',
            'Encouragement of Regular Use',
            'Willingness to Continue Using',
            'Overall Quality Rating',
          ],
        }.entries)
          for (final prompt in group.value)
            (section: group.key, prompt: prompt),
      ],
    ),
  ),
];
