import 'package:flutter/material.dart';

import '../services/questionnaire_data.dart';
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
    title: Text(form.title),
    content: SizedBox(
      width: 490,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (form.instructions.isNotEmpty) ...[
              Text(form.instructions),
              const SizedBox(height: 12),
            ],
            if (form.fields.isNotEmpty) ...[
              Text(
                'Optional respondent details',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text(form.fields.join(' · ')),
              const SizedBox(height: 12),
            ],
            Text('Rating scale', style: Theme.of(context).textTheme.titleSmall),
            for (final (index, level) in form.levels.indexed)
              Text('${index + 1} · $level'),
            const Divider(height: 24),
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
                padding: const EdgeInsets.only(bottom: 7),
                child: Text('${index + 1}. ${item.prompt}'),
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
  final questions = TextEditingController();

  void dispose() {
    title.dispose();
    questions.dispose();
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
  String? _questionCountError;

  @override
  void initState() {
    super.initState();
    for (final item in widget.initial?.items ?? const <QuestionnaireItem>[]) {
      if (_sections.isEmpty || _sections.last.title.text != item.section) {
        _sections.add(_SectionDraft(item.section));
      }
      final questions = _sections.last.questions;
      questions.text = [
        questions.text,
        item.prompt,
      ].where((text) => text.isNotEmpty).join('\n');
    }
    if (_sections.isEmpty) _sections.add(_SectionDraft(''));
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
        for (final question in _lines(section.questions.text))
          (section: section.title.text.trim(), prompt: question),
    ];
    setState(
      () => _questionCountError = items.length > 60
          ? 'Use up to 60 questions per questionnaire.'
          : null,
    );
    if (_questionCountError != null) return null;
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
          const SizedBox(height: 6),
          TextFormField(
            controller: _title,
            maxLength: 120,
            decoration: const InputDecoration(labelText: 'Questionnaire name'),
            validator: (value) =>
                value!.trim().isEmpty ? 'Enter a questionnaire name' : null,
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
              helperText: 'One label per line. Evaluators can skip these.',
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
                          onPressed: () {
                            setState(() => _sections.remove(section));
                            WidgetsBinding.instance.addPostFrameCallback(
                              (_) => section.dispose(),
                            );
                          },
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                    ],
                  ),
                  TextFormField(
                    controller: section.questions,
                    minLines: 2,
                    maxLines: 7,
                    decoration: const InputDecoration(
                      labelText: 'Questions',
                      helperText: 'One question per line.',
                    ),
                    validator: (value) {
                      final questions = _lines(value!);
                      if (questions.isEmpty) {
                        return 'Enter at least one question';
                      }
                      return questions.any(
                            (question) => question.runes.length > 300,
                          )
                          ? 'Use up to 300 characters per question.'
                          : null;
                    },
                  ),
                ],
              ),
            ),
          if (_questionCountError case final error?)
            Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: _sections.length == 60
                    ? null
                    : () => setState(() => _sections.add(_SectionDraft(''))),
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
