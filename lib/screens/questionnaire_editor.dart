import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../services/questionnaire_data.dart';
import '../widgets/questionnaire_card.dart';
import '../widgets/workspace_select.dart';
import 'workspace_forms.dart';

Future<QuestionnaireForm?> editQuestionnaire(
  BuildContext context, {
  QuestionnaireForm? initial,
  Future<void> Function(QuestionnaireForm)? save,
}) async {
  QuestionnaireForm? result;
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _QuestionnaireEditor(
      initial: initial,
      action: save == null ? 'Use this version' : 'Save questionnaire',
      onSave: (form) async {
        await save?.call(form);
        result = form;
      },
    ),
  );
  return confirmed == true ? result : null;
}

Future<void> previewQuestionnaire(
  BuildContext context,
  QuestionnaireForm form,
) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('Questionnaire preview'),
    content: SizedBox(
      width: 490,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            QuestionnaireCard(
              header: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 8,
                children: [
                  Text(
                    form.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (form.instructions.isNotEmpty) Text(form.instructions),
                  Text(
                    '${form.items.length} required rating questions',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (form.fields.isNotEmpty) ...[
              Text(
                'Optional respondent details',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text(form.fields.join(' · ')),
              const SizedBox(height: 12),
            ],
            for (final (index, item) in form.items.indexed) ...[
              if (item.section.isNotEmpty &&
                  (index == 0 || item.section != form.items[index - 1].section))
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 6),
                  child: Text(
                    item.section,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: QuestionnaireCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 8,
                    children: [
                      Text('${index + 1}. ${item.prompt}'),
                      WorkspaceSelect<int>(
                        label: 'Rating',
                        choices: {
                          for (final (index, level) in form.levels.indexed)
                            index + 1: '${index + 1} · $level',
                        },
                        onChanged: (_) {},
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const Divider(height: 24),
            const Text('Comments and suggestions'),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  ),
);

class _SectionDraft {
  _SectionDraft(String title) : title = TextEditingController(text: title);

  final TextEditingController title;
  final questions = <TextEditingController>[];

  void dispose() {
    title.dispose();
    for (final question in questions) {
      question.dispose();
    }
  }
}

class _QuestionnaireEditor extends StatefulWidget {
  const _QuestionnaireEditor({
    required this.initial,
    required this.action,
    required this.onSave,
  });

  final QuestionnaireForm? initial;
  final String action;
  final Future<void> Function(QuestionnaireForm) onSave;

  @override
  State<_QuestionnaireEditor> createState() => _QuestionnaireEditorState();
}

class _QuestionnaireEditorState extends State<_QuestionnaireEditor> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.initial?.title);
  late final _instructions = TextEditingController(
    text: widget.initial?.instructions,
  );
  late final _fields = TextEditingController(
    text: widget.initial?.fields.join('\n'),
  );
  late String _scale = widget.initial?.scale ?? 'standard';
  final List<_SectionDraft> _sections = [];
  int get _questionCount =>
      _sections.fold(0, (total, section) => total + section.questions.length);

  @override
  void initState() {
    super.initState();
    for (final item in widget.initial?.items ?? const <QuestionnaireItem>[]) {
      if (_sections.isEmpty || _sections.last.title.text != item.section) {
        _sections.add(_SectionDraft(item.section));
      }
      _sections.last.questions.add(TextEditingController(text: item.prompt));
    }
    if (_sections.isEmpty) {
      _sections.add(_SectionDraft('')..questions.add(TextEditingController()));
    }
  }

  List<String> _lines(String value) => value
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();

  QuestionnaireForm? _readForm() {
    if (!validateAndReveal(_form)) return null;
    final items = [
      for (final section in _sections)
        for (final question in section.questions)
          (section: section.title.text.trim(), prompt: question.text.trim()),
    ];
    return QuestionnaireForm(
      title: _title.text.trim(),
      instructions: _instructions.text.trim(),
      scale: _scale,
      fields: _lines(_fields.text),
      items: items,
    );
  }

  @override
  void dispose() {
    for (final controller in [_title, _instructions, _fields]) {
      controller.dispose();
    }
    for (final section in _sections) {
      section.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WorkspaceDialogForm(
    title: widget.initial == null ? 'New questionnaire' : 'Edit questionnaire',
    action: widget.action,
    width: 560,
    onSave: () async {
      final form = _readForm();
      if (form == null) return false;
      await widget.onSave(form);
      return true;
    },
    child: Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          QuestionnaireCard(
            header: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 10,
              children: [
                TextFormField(
                  controller: _title,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    labelText: 'Questionnaire name',
                  ),
                  validator: (value) => value!.trim().isEmpty
                      ? 'Enter a questionnaire name'
                      : null,
                ),
                TextFormField(
                  controller: _instructions,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 1000,
                  decoration: const InputDecoration(
                    labelText: 'Instructions (optional)',
                  ),
                ),
                WorkspaceSelect<String>(
                  label: 'Rating scale',
                  initial: _scale,
                  choices: const {
                    'standard': '1–5 · General feedback',
                    'iso': '1–5 · ISO worksheet',
                    'mars': '1–4 · MARS worksheet',
                  },
                  onChanged: (scale) => setState(() => _scale = scale),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _fields,
                  minLines: 2,
                  maxLines: 6,
                  maxLength: 647,
                  decoration: const InputDecoration(
                    labelText: 'Respondent fields (optional)',
                    helperText:
                        'One label per line. Evaluators can skip these.',
                    helperMaxLines: 2,
                  ),
                  validator: (value) {
                    final fields = _lines(value!);
                    return fields.length > 8 ||
                            fields.any((field) => field.runes.length > 80)
                        ? 'Use up to 8 fields, with up to 80 characters each.'
                        : null;
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          for (final (index, section) in _sections.indexed)
            Padding(
              key: ObjectKey(section),
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: section.title,
                          maxLength: 100,
                          decoration: InputDecoration(
                            labelText:
                                'Section ${index + 1} heading (optional)',
                          ),
                        ),
                      ),
                      if (_sections.length > 1)
                        IconButton(
                          tooltip: 'Remove section ${index + 1}',
                          onPressed: () async {
                            final hasContent =
                                section.title.text.trim().isNotEmpty ||
                                section.questions.any(
                                  (question) => question.text.trim().isNotEmpty,
                                );
                            if (hasContent &&
                                !await confirmWorkspaceAction(
                                  context,
                                  title: 'Remove section?',
                                  subject: section.title.text.trim(),
                                  action: 'Remove section',
                                  message:
                                      'This removes the section and its questions from this draft.',
                                  destructive: true,
                                )) {
                              return;
                            }
                            if (!mounted) return;
                            setState(() => _sections.remove(section));
                            WidgetsBinding.instance.addPostFrameCallback(
                              (_) => section.dispose(),
                            );
                          },
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                    ],
                  ),
                  for (final (number, question) in section.questions.indexed)
                    Padding(
                      key: ObjectKey(question),
                      padding: const EdgeInsets.only(bottom: 10),
                      child: QuestionnaireCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextFormField(
                              controller: question,
                              minLines: 1,
                              maxLines: 3,
                              decoration: InputDecoration(
                                labelText: 'Question ${number + 1}',
                              ),
                              validator: (value) {
                                final prompt = value!.trim();
                                if (prompt.isEmpty) return 'Enter a question';
                                return prompt.runes.length > 300
                                    ? 'Use up to 300 characters per question.'
                                    : null;
                              },
                            ),
                            const Divider(height: 16),
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 3,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(right: 8),
                                  child: Text(
                                    'Required rating',
                                    style: TextStyle(color: workshopMuted),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Duplicate question',
                                  onPressed: _questionCount >= 60
                                      ? null
                                      : () => setState(
                                          () => section.questions.insert(
                                            number + 1,
                                            TextEditingController(
                                              text: question.text,
                                            ),
                                          ),
                                        ),
                                  icon: const Icon(
                                    Icons.content_copy_outlined,
                                    size: 17,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Move question up',
                                  onPressed: number == 0
                                      ? null
                                      : () => setState(() {
                                          section.questions.removeAt(number);
                                          section.questions.insert(
                                            number - 1,
                                            question,
                                          );
                                        }),
                                  icon: const Icon(
                                    Icons.arrow_upward_rounded,
                                    size: 18,
                                  ),
                                ),
                                if (section.questions.length > 1)
                                  IconButton(
                                    tooltip:
                                        'Remove question ${number + 1} from section ${index + 1}',
                                    onPressed: () async {
                                      if (question.text.trim().isNotEmpty &&
                                          !await confirmWorkspaceAction(
                                            context,
                                            title: 'Remove question?',
                                            subject: question.text.trim(),
                                            action: 'Remove question',
                                            message:
                                                'This removes the question from this draft.',
                                            destructive: true,
                                          )) {
                                        return;
                                      }
                                      if (!mounted) return;
                                      setState(
                                        () =>
                                            section.questions.remove(question),
                                      );
                                      WidgetsBinding.instance
                                          .addPostFrameCallback(
                                            (_) => question.dispose(),
                                          );
                                    },
                                    icon: const Icon(
                                      Icons.remove_circle_outline,
                                      size: 18,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _questionCount >= 60
                          ? null
                          : () => setState(
                              () => section.questions.add(
                                TextEditingController(),
                              ),
                            ),
                      icon: const Icon(Icons.add, size: 17),
                      label: const Text('Add question'),
                    ),
                  ),
                  const Divider(height: 12),
                ],
              ),
            ),
          Text(
            '$_questionCount of 60 questions',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: _questionCount >= 60
                    ? null
                    : () => setState(
                        () => _sections.add(
                          _SectionDraft('')
                            ..questions.add(TextEditingController()),
                        ),
                      ),
                icon: const Icon(Icons.add),
                label: const Text('Add section'),
              ),
              TextButton.icon(
                onPressed: () {
                  if (_readForm() case final form?) {
                    previewQuestionnaire(context, form);
                  }
                },
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Preview'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
