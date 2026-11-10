import 'package:flutter/material.dart';
import '../services/cloud_repository.dart';
import '../services/questionnaire_data.dart';
import '../services/questionnaire_picker.dart'
    if (dart.library.js_interop) '../services/questionnaire_picker_web.dart';
import '../widgets/app_notice.dart';

class FormFieldSpec {
  const FormFieldSpec(
    this.key,
    this.label, {
    required this.max,
    this.lines = 1,
    this.required = false,
    this.url = false,
  });
  final String key, label;
  final int max, lines;
  final bool required, url;
}

String? _validate(String? value, FormFieldSpec field) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) {
    return field.required ? 'Enter ${field.label.toLowerCase()}' : null;
  }
  if (field.url) {
    final uri = Uri.tryParse(text);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return 'Enter an HTTPS link';
    }
  }
  return null;
}

TextFormField _input(
  TextEditingController controller,
  FormFieldSpec field, {
  String? hint,
}) => TextFormField(
  controller: controller,
  maxLength: field.max,
  maxLines: field.lines,
  keyboardType: field.url ? TextInputType.url : null,
  decoration: InputDecoration(
    labelText: field.label,
    hintText: hint,
    hintMaxLines: 2,
    alignLabelWithHint: field.lines > 1,
  ),
  validator: (value) => _validate(value, field),
);

Future<WorkspaceRow?> workspaceForm(
  BuildContext context, {
  required String title,
  required String action,
  required List<FormFieldSpec> fields,
  WorkspaceRow? initial,
  bool directory = false,
}) => showDialog<WorkspaceRow>(
  context: context,
  builder: (_) => _WorkspaceForm(
    title: title,
    action: action,
    fields: fields,
    initial: initial ?? const {},
    directory: directory,
  ),
);

class _WorkspaceForm extends StatefulWidget {
  const _WorkspaceForm({
    required this.title,
    required this.action,
    required this.fields,
    required this.initial,
    required this.directory,
  });
  final String title, action;
  final List<FormFieldSpec> fields;
  final WorkspaceRow initial;
  final bool directory;

  @override
  State<_WorkspaceForm> createState() => _WorkspaceFormState();
}

class _WorkspaceFormState extends State<_WorkspaceForm> {
  final _form = GlobalKey<FormState>();
  late final _controllers = {
    for (final field in widget.fields)
      field.key: TextEditingController(
        text: widget.initial[field.key] as String? ?? '',
      ),
  };
  late bool _visible = widget.initial['directory_visible'] == true;
  late String _type =
      widget.initial['evaluator_type'] as String? ?? 'community';

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WorkspaceDialogForm(
    title: widget.title,
    action: widget.action,
    onSubmit: () {
      if (!_form.currentState!.validate()) return;
      Navigator.pop(context, {
        for (final field in widget.fields)
          field.key: field.url && _controllers[field.key]!.text.trim().isEmpty
              ? null
              : _controllers[field.key]!.text.trim(),
        if (widget.directory) ...{
          'directory_visible': _visible,
          'evaluator_type': _type,
        },
      });
    },
    child: Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final field in widget.fields)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _input(_controllers[field.key]!, field),
            ),
          if (widget.directory) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Show me in the evaluator directory'),
              subtitle: const Text(
                'Let members find your profile and send you review invitations.',
              ),
              value: _visible,
              onChanged: (value) => setState(() => _visible = value),
            ),
            if (_visible) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _type,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Evaluator type'),
                items: evaluatorTypes.entries
                    .map(
                      (type) => DropdownMenuItem(
                        value: type.key,
                        child: Text(type.value),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _type = value!),
              ),
            ],
          ],
        ],
      ),
    ),
  );
}

enum _QuestionnaireMode {
  library('Choose from questionnaire library', Icons.inventory_2_outlined),
  template('Use a quick checklist', Icons.fact_check_outlined),
  custom('Write my own questions', Icons.edit_note_outlined),
  upload('Upload a PDF', Icons.upload_file_outlined),
  external('Use a form or document link', Icons.link_outlined);

  const _QuestionnaireMode(this.label, this.icon);
  final String label;
  final IconData icon;
}

class ProjectForm extends StatefulWidget {
  const ProjectForm({
    super.key,
    required this.rubrics,
    required this.save,
    required this.openUrl,
    required this.previewTemplate,
    this.questionnaires = const [],
    this.previewChoice,
    this.editChoice,
  });
  final List<WorkspaceRow> rubrics;
  final List<QuestionnaireChoice> questionnaires;
  final Future<void> Function(
    WorkspaceRow, {
    QuestionnaireFile? questionnairePdf,
  })
  save;
  final ValueChanged<String> openUrl;
  final ValueChanged<String> previewTemplate;
  final ValueChanged<QuestionnaireChoice>? previewChoice;
  final Future<QuestionnaireForm?> Function(QuestionnaireForm)? editChoice;

  @override
  State<ProjectForm> createState() => _ProjectFormState();
}

class _ProjectFormState extends State<ProjectForm> {
  static const _categories = [
    'Website',
    'Mobile app',
    'Research',
    'Prototype',
    'Game',
    'Creative work',
    'Other',
  ];
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController(),
      _summary = TextEditingController(),
      _link = TextEditingController(),
      _audience = TextEditingController(),
      _instructions = TextEditingController(),
      _questions = TextEditingController(),
      _questionnaireLink = TextEditingController();
  String _category = 'Website';
  String? _rubric;
  late _QuestionnaireMode _mode = widget.questionnaires.isEmpty
      ? _QuestionnaireMode.template
      : _QuestionnaireMode.library;
  String? _questionnaireId;
  QuestionnaireForm? _editedQuestionnaire;
  QuestionnaireFile? _pdf;
  String? _pdfError;
  bool _choosingFile = false;

  QuestionnaireChoice? get _libraryChoice {
    final suggested =
        _questionnaireId ??
        switch (_category) {
          'Website' => 'iso-worksheet',
          'Mobile app' => 'mars-worksheet',
          _ => null,
        };
    return widget.questionnaires
        .where((choice) => choice.id == suggested)
        .firstOrNull;
  }

  Future<void> _editLibraryChoice(QuestionnaireChoice choice) async {
    final edited = await widget.editChoice?.call(
      _editedQuestionnaire ?? choice.form!,
    );
    if (!mounted || edited == null) return;
    setState(() {
      _questionnaireId = choice.id;
      _editedQuestionnaire = edited;
    });
  }

  Future<void> _choosePdf(FormFieldState<QuestionnaireFile> field) async {
    setState(() {
      _choosingFile = true;
      _pdfError = null;
    });
    try {
      final file = await pickQuestionnaireFile();
      if (!mounted || file == null) return;
      setState(() => _pdf = file);
      if (field.mounted) field.didChange(file);
    } on FormatException catch (error) {
      if (mounted) setState(() => _pdfError = error.message);
    } catch (_) {
      if (mounted) setState(() => _pdfError = 'Couldn’t open the PDF picker.');
    } finally {
      if (mounted) setState(() => _choosingFile = false);
    }
  }

  List<String> _questionLines(String value) => value
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();

  String? get _selectedRubric {
    final suggested =
        _rubric ??
        switch (_category) {
          'Website' => 'website-iso25010-v1',
          'Mobile app' => 'mobile-mars-v1',
          'Research' => 'research-v1',
          'Prototype' => 'prototype-v1',
          'Game' => 'game-v1',
          _ => 'general-v1',
        };
    return widget.rubrics.any((row) => row['id'] == suggested)
        ? suggested
        : null;
  }

  @override
  void dispose() {
    for (final controller in [
      _title,
      _summary,
      _link,
      _audience,
      _instructions,
      _questions,
      _questionnaireLink,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final source = questionnaireSources[_selectedRubric];
    final choice = _mode == _QuestionnaireMode.library ? _libraryChoice : null;
    final form = choice == null ? null : _editedQuestionnaire ?? choice.form;
    return WorkspaceDialogForm(
      title: 'New project',
      action: 'Create project',
      width: 540,
      onSave: () async {
        if (_choosingFile || !validateAndReveal(_form)) return false;
        await widget.save({
          'title': _title.text.trim(),
          'category': _category,
          'summary': _summary.text.trim(),
          'artifact_url': _link.text.trim(),
          'audience': _audience.text.trim().isEmpty
              ? null
              : _audience.text.trim(),
          'test_instructions': _instructions.text.trim(),
          'rubric_id': _mode == _QuestionnaireMode.template
              ? _selectedRubric
              : null,
          'custom_questions': _mode == _QuestionnaireMode.custom
              ? _questionLines(_questions.text)
              : null,
          if (form != null) 'questionnaire_form': form.toJson(),
          if (choice?.filePath case final path?) ...{
            'questionnaire_file_path': path,
            'questionnaire_file_name': choice!.fileName,
          },
          'questionnaire_url': _questionnaireLink.text.trim().isEmpty
              ? null
              : _questionnaireLink.text.trim(),
        }, questionnairePdf: _mode == _QuestionnaireMode.upload ? _pdf : null);
        return true;
      },
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const _FormSection('01', 'Project details'),
            _input(
              _title,
              const FormFieldSpec(
                'title',
                'Project title',
                max: 100,
                required: true,
              ),
            ),
            WorkspaceSelect<String>(
              label: 'Project type',
              initial: _category,
              icon: Icons.layers_outlined,
              choices: {for (final type in _categories) type: type},
              onChanged: (value) => setState(() {
                _category = value;
                _rubric = null;
              }),
            ),
            const SizedBox(height: 12),
            _input(
              _link,
              const FormFieldSpec(
                'artifact_url',
                'Direct project link',
                max: 500,
                url: true,
                required: true,
              ),
              hint: 'Paste the HTTPS link that opens the site or test build.',
            ),
            _input(
              _summary,
              const FormFieldSpec(
                'summary',
                'Project brief',
                max: 2000,
                required: true,
                lines: 2,
              ),
              hint: 'What does the project do, and what are you evaluating?',
            ),
            const _FormSection('02', 'Evaluator instructions'),
            _input(
              _audience,
              const FormFieldSpec(
                'audience',
                'Intended users (optional)',
                max: 250,
              ),
            ),
            _input(
              _instructions,
              const FormFieldSpec(
                'test_instructions',
                'What should evaluators try?',
                max: 1600,
                required: true,
                lines: 3,
              ),
              hint: 'List the tasks, test setup, and any access instructions.',
            ),
            const _FormSection('03', 'Questionnaire'),
            WorkspaceSelect<_QuestionnaireMode>(
              label: 'Questionnaire method',
              initial: _mode,
              icon: _mode.icon,
              choices: {
                for (final mode in _QuestionnaireMode.values)
                  if (mode != _QuestionnaireMode.library ||
                      widget.questionnaires.isNotEmpty)
                    mode: mode.label,
              },
              onChanged: (value) => setState(() => _mode = value),
            ),
            const SizedBox(height: 12),
            if (_mode == _QuestionnaireMode.library) ...[
              WorkspaceSelect<String>(
                key: ValueKey(choice?.id),
                label: 'Questionnaire',
                initial: choice?.id,
                icon: Icons.assignment_outlined,
                choices: {
                  for (final item in widget.questionnaires)
                    item.id:
                        item.id == choice?.id && _editedQuestionnaire != null
                        ? _editedQuestionnaire!.title
                        : item.title,
                },
                onChanged: (value) => setState(() {
                  _questionnaireId = value;
                  _editedQuestionnaire = null;
                }),
                validator: (value) =>
                    value == null ? 'Choose a questionnaire' : null,
              ),
              if (choice != null)
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: () => widget.previewChoice?.call(
                        form == null
                            ? choice
                            : QuestionnaireChoice(
                                id: choice.id,
                                title: form.title,
                                form: form,
                              ),
                      ),
                      icon: const Icon(Icons.visibility_outlined, size: 16),
                      label: const Text('Preview questionnaire'),
                    ),
                    if (form != null)
                      TextButton.icon(
                        onPressed: () => _editLibraryChoice(choice),
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: const Text('Edit for this project'),
                      ),
                  ],
                ),
            ],
            if (_mode == _QuestionnaireMode.template) ...[
              WorkspaceSelect<String>(
                key: ValueKey(_category),
                label: 'Questionnaire template',
                initial: _selectedRubric,
                icon: Icons.assignment_outlined,
                choices: {
                  for (final row in widget.rubrics)
                    row['id'] as String: row['name'] as String,
                },
                onChanged: (value) => setState(() => _rubric = value),
                validator: (value) =>
                    value == null ? 'Choose a questionnaire template' : null,
              ),
              Wrap(
                spacing: 8,
                children: [
                  if (_selectedRubric case final String rubric)
                    TextButton.icon(
                      onPressed: () => widget.previewTemplate(rubric),
                      icon: const Icon(Icons.list_alt_outlined, size: 16),
                      label: const Text('Preview questions'),
                    ),
                  if (source != null)
                    TextButton.icon(
                      onPressed: () => widget.openUrl(source.url),
                      icon: const Icon(Icons.open_in_new, size: 14),
                      label: Text(source.name),
                    ),
                ],
              ),
            ],
            if (_mode == _QuestionnaireMode.custom) ...[
              TextFormField(
                controller: _questions,
                minLines: 3,
                maxLines: 7,
                maxLength: 5784,
                decoration: const InputDecoration(
                  labelText: 'Your questions',
                  alignLabelWithHint: true,
                  helperText:
                      'One question per line. Each is rated from 1 to 5.',
                  helperMaxLines: 2,
                ),
                validator: (value) {
                  final lines = _questionLines(value ?? '');
                  if (lines.isEmpty || lines.length > 24) {
                    return 'Enter 1–24 questions';
                  }
                  if (lines.any((line) => line.length > 240)) {
                    return 'Use up to 240 characters per question';
                  }
                  return null;
                },
              ),
            ],
            if (_mode == _QuestionnaireMode.upload)
              FormField<QuestionnaireFile>(
                initialValue: _pdf,
                validator: (value) => value == null ? 'Choose a PDF' : null,
                builder: (field) => InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Questionnaire PDF',
                    helperText: 'PDF, up to 5 MB.',
                    errorText: _pdfError ?? field.errorText,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _choosingFile ? null : () => _choosePdf(field),
                      icon: const Icon(Icons.upload_file_outlined, size: 18),
                      label: Text(
                        _pdf?.name ?? 'Choose PDF',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              ),
            _input(
              _questionnaireLink,
              FormFieldSpec(
                'questionnaire_url',
                _mode == _QuestionnaireMode.external
                    ? 'Questionnaire link'
                    : 'Extra questionnaire link (optional)',
                max: 500,
                url: true,
                required: _mode == _QuestionnaireMode.external,
              ),
              hint: 'Use an HTTPS link to a form, shared PDF, or document.',
            ),
            const Text(
              'Your project starts private. Set file and form access before inviting evaluators.',
            ),
          ],
        ),
      ),
    );
  }
}

bool validateAndReveal(GlobalKey<FormState> form) {
  final invalid = form.currentState!.validateGranularly();
  if (invalid.isEmpty) return true;
  final first = invalid.first;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (first.mounted) {
      Scrollable.ensureVisible(first.context, alignment: .15);
    }
  });
  return false;
}

class _FormSection extends StatelessWidget {
  const _FormSection(this.number, this.title);
  final String number, title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 12),
    child: Row(
      children: [
        Text(
          number,
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    ),
  );
}

class WorkspaceSelect<T> extends StatelessWidget {
  const WorkspaceSelect({
    super.key,
    required this.label,
    required this.choices,
    required this.onChanged,
    this.initial,
    this.icon,
    this.validator,
  });
  final String label;
  final Map<T, String> choices;
  final ValueChanged<T> onChanged;
  final T? initial;
  final IconData? icon;
  final FormFieldValidator<T>? validator;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DropdownButtonFormField<T>(
      initialValue: initial,
      isExpanded: true,
      menuMaxHeight: 320,
      borderRadius: BorderRadius.circular(16),
      dropdownColor: colors.surface,
      icon: Icon(Icons.expand_more_rounded, color: colors.primary),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: icon == null
            ? null
            : Icon(icon, size: 18, color: colors.primary),
      ),
      items: [
        for (final choice in choices.entries)
          DropdownMenuItem(
            value: choice.key,
            child: Text(choice.value, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
      validator: validator,
    );
  }
}

class ReviewDraft {
  const ReviewDraft(
    this.scores,
    this.feedback, {
    this.respondentDetails = const [],
  });
  final Map<String, int> scores;
  final String feedback;
  final List<String> respondentDetails;
}

class ReviewForm extends StatefulWidget {
  const ReviewForm({
    super.key,
    required this.criteria,
    required this.projectBrief,
    required this.allowUnassessed,
    required this.externalOnly,
    required this.save,
    this.questionnaire,
  });
  final List<WorkspaceRow> criteria;
  final Future<void> Function(ReviewDraft) save;
  final Widget projectBrief;
  final bool allowUnassessed, externalOnly;
  final QuestionnaireForm? questionnaire;
  @override
  State<ReviewForm> createState() => _ReviewFormState();
}

class _ReviewFormState extends State<ReviewForm> {
  List<String> get _levels =>
      widget.questionnaire?.levels ?? questionnaireScales['standard']!;
  final _form = GlobalKey<FormState>();
  final _feedback = TextEditingController();
  final Map<String, int> _scores = {};
  late final _details = List.filled(
    widget.questionnaire?.fields.length ?? 0,
    '',
  );
  bool _noConflict = false;

  @override
  void dispose() {
    _feedback.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WorkspaceDialogForm(
    title: 'Write review',
    action: 'Submit review',
    width: 540,
    onSave: !_noConflict || (widget.criteria.isEmpty && !widget.externalOnly)
        ? null
        : () async {
            if (!validateAndReveal(_form)) return false;
            await widget.save(
              ReviewDraft(
                Map.of(_scores),
                _feedback.text.trim(),
                respondentDetails: [
                  for (final detail in _details) detail.trim(),
                ],
              ),
            );
            return true;
          },
    child: Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          widget.projectBrief,
          const SizedBox(height: 18),
          if (widget.questionnaire case final form?) ...[
            if (form.instructions.isNotEmpty) ...[
              Text(form.instructions),
              const SizedBox(height: 14),
            ],
            if (form.fields.isNotEmpty)
              ExpansionTile(
                title: const Text('Optional respondent details'),
                subtitle: const Text(
                  'Responses are shared with the project creator.',
                ),
                tilePadding: EdgeInsets.zero,
                maintainState: true,
                children: [
                  for (final (index, field) in form.fields.indexed)
                    TextFormField(
                      maxLength: 160,
                      decoration: InputDecoration(labelText: field),
                      onChanged: (value) => _details[index] = value,
                    ),
                ],
              ),
            const SizedBox(height: 10),
          ],
          const _FormSection('01', 'Evaluation questions'),
          if (widget.externalOnly)
            const Text(
              'Complete the questionnaire, then summarize your findings here.',
            )
          else if (widget.criteria.isEmpty)
            const Text('This questionnaire has no questions.')
          else if (widget.allowUnassessed)
            const Text(
              'Choose Not assessed for anything you could not verify. Explain the limitation in your feedback.',
            ),
          const SizedBox(height: 10),
          for (final (index, criterion) in widget.criteria.indexed) ...[
            if (criterion['section'] case final String section
                when section.isNotEmpty &&
                    (index == 0 ||
                        widget.criteria[index - 1]['section'] != section))
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 10),
                child: Text(
                  section,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            Text('${index + 1}. ${criterion['prompt']}'),
            const SizedBox(height: 6),
            WorkspaceSelect<int>(
              label: widget.questionnaire == null
                  ? criterion['label'] as String
                  : 'Rating',
              choices: {
                for (final (index, level) in _levels.indexed)
                  index + 1: '${index + 1} · $level',
                if (widget.allowUnassessed) 0: 'Not assessed',
              },
              onChanged: (value) =>
                  _scores[criterion['criterion_key'] as String] = value,
              validator: (value) => value == null ? 'Choose a score' : null,
            ),
            const SizedBox(height: 14),
          ],
          const _FormSection('02', 'Feedback'),
          _input(
            _feedback,
            const FormFieldSpec(
              'feedback',
              'Feedback and next steps',
              max: 4000,
              required: true,
              lines: 4,
            ),
            hint:
                'What did you test, what did you find, and what should change first?',
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _noConflict,
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: (value) => setState(() => _noConflict = value == true),
            title: const Text('I have no conflict of interest.'),
          ),
        ],
      ),
    ),
  );
}

class WorkspaceDialogForm extends StatefulWidget {
  const WorkspaceDialogForm({
    super.key,
    required this.title,
    required this.action,
    required this.child,
    this.onSubmit,
    this.onSave,
    this.width = 460,
  });
  final String title, action;
  final Widget child;
  final VoidCallback? onSubmit;
  final Future<bool> Function()? onSave;
  final double width;

  @override
  State<WorkspaceDialogForm> createState() => _WorkspaceDialogFormState();
}

class _WorkspaceDialogFormState extends State<WorkspaceDialogForm> {
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    final save = widget.onSave;
    if (_saving || save == null) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await save();
      if (!mounted) return;
      setState(() => _saving = false);
      if (saved) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = workspaceError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: widget.width,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error case final message?)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: AppNotice(message, tone: NoticeTone.error),
                ),
              IgnorePointer(ignoring: _saving, child: widget.child),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving
              ? null
              : widget.onSave != null
              ? _save
              : widget.onSubmit,
          child: Text(_saving ? 'Saving…' : widget.action),
        ),
      ],
    ),
  );
}
