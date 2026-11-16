import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../services/cloud_repository.dart';
import '../services/questionnaire_data.dart';
import '../widgets/app_notice.dart';
import '../widgets/questionnaire_card.dart';
import '../widgets/workspace_select.dart';
import 'workspace_practice_guide.dart';

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
  bool compact = false,
  Key? key,
}) => TextFormField(
  key: key,
  controller: controller,
  maxLength: field.max,
  maxLines: field.lines,
  keyboardType: field.url ? TextInputType.url : null,
  decoration: InputDecoration(
    labelText: field.label,
    hintText: hint,
    counterText: compact ? '' : null,
    isDense: compact,
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
  late String? _profession = widget.initial['profession'] as String?;

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
      if (!validateAndReveal(_form)) return;
      Navigator.pop(context, {
        for (final field in widget.fields)
          field.key: field.url && _controllers[field.key]!.text.trim().isEmpty
              ? null
              : _controllers[field.key]!.text.trim(),
        if (widget.directory) ...{
          'directory_visible': _visible,
          'evaluator_type': _type,
          'profession': _profession,
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
            WorkspaceSelect<String>(
              label: 'Profession',
              choices: professions,
              initial: _profession,
              icon: Icons.work_outline,
              onChanged: (value) => _profession = value,
            ),
            const SizedBox(height: 8),
            ProfileVisibilityFields(
              visible: _visible,
              evaluatorType: _type,
              onVisible: (value) => setState(() => _visible = value),
              onType: (value) => _type = value,
            ),
          ],
        ],
      ),
    ),
  );
}

class ProfileVisibilityFields extends StatelessWidget {
  const ProfileVisibilityFields({
    super.key,
    required this.visible,
    required this.evaluatorType,
    required this.onVisible,
    required this.onType,
  });

  final bool visible;
  final String evaluatorType;
  final ValueChanged<bool> onVisible;
  final ValueChanged<String> onType;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Show me in the member directory'),
        subtitle: const Text(
          'Let members find you, connect, and send review invitations.',
        ),
        value: visible,
        onChanged: onVisible,
      ),
      if (visible) ...[
        const SizedBox(height: 6),
        WorkspaceSelect<String>(
          label: 'Evaluator type',
          initial: evaluatorType,
          choices: evaluatorTypes,
          icon: Icons.rate_review_outlined,
          onChanged: onType,
        ),
      ],
    ],
  );
}

enum _ProjectStep {
  details(
    'Project details',
    'Details',
    'Give evaluators the context and link they need.',
  ),
  instructions(
    'Evaluator instructions',
    'Instructions',
    'Tell evaluators what to try and what to pay attention to.',
  ),
  questionnaire(
    'Questionnaire',
    'Questionnaire',
    'Choose how evaluators will record their feedback.',
  );

  const _ProjectStep(this.title, this.label, this.description);
  final String title, label, description;
}

enum _ProjectGuidePoint {
  identity(
    'Name and categorize the project',
    'Use the title evaluators will recognize, then pick the project type. Try editing the example or keep it for practice.',
  ),
  link(
    'Paste a direct project link',
    'Use the HTTPS link reviewers should open to test your work. Try it in a private browser window first to check that others can access it.',
  ),
  brief(
    'Write a short brief',
    'Explain what the project does, who it serves, and what you want to learn from this evaluation.',
  ),
  instructions(
    'Give evaluators a task to try',
    'Name an action, such as finding a quiet room. Include any setup or test access they need and what they should pay attention to.',
  ),
  template(
    'Choose a questionnaire',
    'Choose an in-app template for a starting point, or select Blank form to design your own. This sample uses one usability question.',
  ),
  edit(
    'Edit or preview your questions',
    'Use Edit questionnaire to change questions and sections. Preview shows how the form will look to an evaluator.',
  ),
  create(
    'Save your project as a draft',
    'Save this practice draft to continue. The tour supplies any missing details or questionnaire. New projects start private.',
  );

  const _ProjectGuidePoint(this.title, this.detail);
  final String title, detail;
}

class ProjectForm extends StatefulWidget {
  const ProjectForm({
    super.key,
    required this.save,
    required this.editQuestionnaire,
    required this.previewQuestionnaire,
    this.questionnaires = const [],
    this.practice = false,
  });

  final List<QuestionnaireChoice> questionnaires;
  final bool practice;
  final Future<void> Function(WorkspaceRow) save;
  final Future<QuestionnaireForm?> Function(QuestionnaireForm?)
  editQuestionnaire;
  final ValueChanged<QuestionnaireForm> previewQuestionnaire;

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
  final _forms = [for (final _ in _ProjectStep.values) GlobalKey<FormState>()];
  final _scroll = ScrollController();
  final _stepFocus = FocusNode();
  late final _guideTargets = {
    for (final point in _ProjectGuidePoint.values) point: GlobalKey(),
  };

  Key? _guideTarget(_ProjectGuidePoint point) =>
      widget.practice ? _guideTargets[point] : null;

  _ProjectStep _step = _ProjectStep.details;
  bool _saving = false;
  String? _saveError;
  final _title = TextEditingController(),
      _summary = TextEditingController(),
      _link = TextEditingController(),
      _audience = TextEditingController(),
      _instructions = TextEditingController();
  String _category = 'Website';
  String _template = '';
  int _templateSelectRevision = 0;
  QuestionnaireForm? _questionnaireForm;
  static const _sampleTitle = 'Campus Study Finder';
  static const _sampleSummary =
      'A sample website that helps students find a place to study.';
  static const _sampleLink = 'https://example.com/study-finder';
  static const _sampleInstructions =
      'Find a quiet study space and rate how easy it was to choose a room.';

  @override
  void initState() {
    super.initState();
    if (!widget.practice) return;
    _title.text = _sampleTitle;
    _summary.text = _sampleSummary;
    _link.text = _sampleLink;
    _audience.text = 'Students looking for a study space';
    _instructions.text = _sampleInstructions;
    final sample = widget.questionnaires.first;
    _template = sample.id;
    _questionnaireForm = sample.form;
  }

  Future<void> _editForm() async {
    final form = await widget.editQuestionnaire(_questionnaireForm);
    if (mounted && form != null) setState(() => _questionnaireForm = form);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _stepFocus.dispose();
    for (final controller in [
      _title,
      _summary,
      _link,
      _audience,
      _instructions,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _showStep(_ProjectStep step) {
    if (_scroll.hasClients) _scroll.jumpTo(0);
    setState(() {
      _step = step;
      _saveError = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _step == step) _stepFocus.requestFocus();
    });
  }

  String _draftText(TextEditingController controller, String sample) {
    final value = controller.text.trim();
    return widget.practice && value.isEmpty ? sample : value;
  }

  Future<void> _continue() async {
    if (_saving ||
        (!widget.practice && !validateAndReveal(_forms[_step.index]))) {
      return;
    }
    if (_step != _ProjectStep.questionnaire) {
      _showStep(_ProjectStep.values[_step.index + 1]);
      return;
    }
    FocusScope.of(context).unfocus();
    final form = _questionnaireForm ?? widget.questionnaires.first.form!;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await widget.save({
        'title': _draftText(_title, _sampleTitle),
        'category': _category,
        'summary': _draftText(_summary, _sampleSummary),
        'artifact_url': _draftText(_link, _sampleLink),
        'audience': _audience.text.trim().isEmpty
            ? null
            : _audience.text.trim(),
        'test_instructions': _draftText(_instructions, _sampleInstructions),
        'questionnaire_form': form.toJson(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _saveError = workspaceError(error);
        });
        if (_scroll.hasClients) _scroll.jumpTo(0);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final size = MediaQuery.sizeOf(context);
    final mobile = size.width < 600;
    final busy = _saving;
    final last = _step == _ProjectStep.questionnaire;
    final inset = mobile ? 12.0 : 28.0;
    final horizontal = mobile ? 16.0 : 28.0;
    final duration = widget.practice || MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);
    final dialog = PopScope(
      canPop: !busy,
      child: Dialog(
        insetPadding: EdgeInsets.all(inset),
        constraints: const BoxConstraints(maxWidth: 720),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 720,
          height: (size.height - 2 * inset).clamp(0.0, 636.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                decoration: const BoxDecoration(
                  color: workshopNight,
                  border: Border(bottom: BorderSide(color: workshopEdge)),
                ),
                padding: EdgeInsets.fromLTRB(
                  horizontal,
                  12,
                  mobile ? 8 : 20,
                  12,
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: workshopIce.withValues(alpha: .10),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: workshopEdge),
                      ),
                      child: const Icon(
                        Icons.create_new_folder_outlined,
                        size: 21,
                        color: workshopIce,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          widget.practice
                              ? 'New project · Practice'
                              : 'New project',
                          style: text.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close new project',
                      onPressed: busy ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded, size: 20),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(horizontal, 12, horizontal, 10),
                child: Row(
                  children: [
                    for (final step in _ProjectStep.values) ...[
                      if (step.index != 0)
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: mobile ? 2 : 8,
                          ),
                          child: const Icon(
                            Icons.chevron_right_rounded,
                            size: 14,
                            color: workshopMuted,
                          ),
                        ),
                      Expanded(child: _stepIndicator(step, busy, duration)),
                    ],
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  controller: _scroll,
                  padding: EdgeInsets.fromLTRB(horizontal, 20, horizontal, 20),
                  child: TweenAnimationBuilder<double>(
                    key: ValueKey(_step),
                    tween: Tween(
                      begin: duration == Duration.zero ? 1 : 0,
                      end: 1,
                    ),
                    duration: duration,
                    curve: Curves.easeOutCubic,
                    builder: (context, progress, child) => Opacity(
                      opacity: progress,
                      child: Transform.translate(
                        offset: Offset(0, 6 * (1 - progress)),
                        child: child,
                      ),
                    ),
                    child: Form(
                      key: _forms[_step.index],
                      child: AbsorbPointer(
                        absorbing: _saving,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: 14,
                          children: [
                            Focus(
                              focusNode: _stepFocus,
                              skipTraversal: true,
                              child: Semantics(
                                header: true,
                                liveRegion: true,
                                child: Text(
                                  _step.title,
                                  style: text.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                            Text(
                              _step.description,
                              style: const TextStyle(color: workshopMuted),
                            ),
                            if (_saveError case final error?)
                              AppNotice(error, tone: NoticeTone.error),
                            switch (_step) {
                              _ProjectStep.details => _details(),
                              _ProjectStep.instructions =>
                                _reviewInstructions(),
                              _ProjectStep.questionnaire => _questionnaire(),
                            },
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: EdgeInsets.fromLTRB(horizontal, 10, horizontal, 12),
                child: OverflowBar(
                  alignment: MainAxisAlignment.spaceBetween,
                  overflowAlignment: OverflowBarAlignment.end,
                  overflowSpacing: 4,
                  children: [
                    TextButton(
                      onPressed: busy
                          ? null
                          : () {
                              if (_step == _ProjectStep.details) {
                                Navigator.pop(context);
                              } else {
                                _showStep(_ProjectStep.values[_step.index - 1]);
                              }
                            },
                      child: Text(
                        _step == _ProjectStep.details ? 'Cancel' : 'Back',
                      ),
                    ),
                    FilledButton(
                      key: last
                          ? _guideTarget(_ProjectGuidePoint.create)
                          : null,
                      onPressed: busy ? null : _continue,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 8,
                        children: [
                          if (_saving)
                            const SizedBox.square(
                              dimension: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          Flexible(
                            child: Text(
                              _saving
                                  ? 'Creating…'
                                  : last
                                  ? widget.practice
                                        ? 'Create practice project'
                                        : 'Create project'
                                  : 'Continue',
                            ),
                          ),
                          if (!last)
                            const Icon(Icons.arrow_forward_rounded, size: 16),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!widget.practice) return dialog;
    final (points, offset, advanceLabel) = switch (_step) {
      _ProjectStep.details => (
        const [
          _ProjectGuidePoint.identity,
          _ProjectGuidePoint.link,
          _ProjectGuidePoint.brief,
        ],
        0,
        'Go to instructions',
      ),
      _ProjectStep.instructions => (
        const [_ProjectGuidePoint.instructions],
        3,
        'Go to questionnaire',
      ),
      _ProjectStep.questionnaire => (
        const [
          _ProjectGuidePoint.template,
          _ProjectGuidePoint.edit,
          _ProjectGuidePoint.create,
        ],
        4,
        'Save practice draft',
      ),
    };
    return PracticeFormGuide(
      label: 'Project practice',
      offset: offset,
      total: _ProjectGuidePoint.values.length,
      tips: [
        for (final point in points)
          PracticeTip(_guideTargets[point]!, point.title, point.detail),
      ],
      advance: _continue,
      advanceLabel: advanceLabel,
      child: dialog,
    );
  }

  Widget _stepIndicator(_ProjectStep step, bool busy, Duration duration) {
    final active = step == _step;
    final done = step.index < _step.index;
    final color = active || done ? workshopIce : workshopMuted;
    return Semantics(
      label:
          'Step ${step.index + 1} of ${_ProjectStep.values.length}, ${step.label}${done ? ', completed' : ''}',
      selected: active,
      button: done,
      excludeSemantics: true,
      onTap: done && !busy ? () => _showStep(step) : null,
      child: InkWell(
        onTap: done && !busy ? () => _showStep(step) : null,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: duration,
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
          decoration: BoxDecoration(
            color: active
                ? workshopIce.withValues(alpha: .10)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active ? workshopEdge : Colors.transparent,
            ),
          ),
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 3,
            children: [
              Container(
                width: 23,
                height: 23,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active ? workshopIce : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(color: color),
                ),
                child: done
                    ? Icon(Icons.check_rounded, size: 14, color: color)
                    : Text(
                        '${step.index + 1}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: active ? workshopNight : color,
                        ),
                      ),
              ),
              Text(
                step.label,
                style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _details() {
    final title = _input(
      _title,
      const FormFieldSpec('title', 'Project title', max: 100, required: true),
      hint: 'e.g. Campus Clinic',
      compact: true,
    );
    final type = WorkspaceSelect<String>(
      label: 'Project type',
      initial: _category,
      icon: Icons.layers_outlined,
      choices: {for (final type in _categories) type: type},
      onChanged: (value) => setState(() => _category = value),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 16,
      children: [
        LayoutBuilder(
          key: _guideTarget(_ProjectGuidePoint.identity),
          builder: (context, constraints) => constraints.maxWidth >= 480
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 12,
                  children: [
                    Expanded(flex: 2, child: title),
                    Expanded(child: type),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 16,
                  children: [title, type],
                ),
        ),
        _input(
          _link,
          const FormFieldSpec(
            'artifact_url',
            'Direct project link',
            max: 500,
            url: true,
            required: true,
          ),
          hint: 'https://…',
          compact: true,
          key: _guideTarget(_ProjectGuidePoint.link),
        ),
        _input(
          _summary,
          const FormFieldSpec(
            'summary',
            'Project brief',
            max: 2000,
            required: true,
            lines: 3,
          ),
          hint: 'What does it do, and what are you evaluating?',
          compact: true,
          key: _guideTarget(_ProjectGuidePoint.brief),
        ),
      ],
    );
  }

  Widget _reviewInstructions() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 16,
    children: [
      _input(
        _audience,
        const FormFieldSpec('audience', 'Intended users (optional)', max: 250),
        hint: 'e.g. Students booking a clinic appointment',
        compact: true,
      ),
      _input(
        _instructions,
        const FormFieldSpec(
          'test_instructions',
          'What should evaluators try?',
          max: 1600,
          required: true,
          lines: 4,
        ),
        hint: 'List the tasks and any setup or access instructions.',
        compact: true,
        key: _guideTarget(_ProjectGuidePoint.instructions),
      ),
    ],
  );

  Widget _questionnaire() {
    final form = _questionnaireForm;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 16,
      children: [
        if (widget.questionnaires.any((choice) => choice.form != null))
          KeyedSubtree(
            key: _guideTarget(_ProjectGuidePoint.template),
            child: WorkspaceSelect<String>(
              key: ValueKey((_template, _templateSelectRevision)),
              label: 'Start from an in-app template',
              initial: _template,
              choices: {
                '': 'Blank form',
                for (final item in widget.questionnaires)
                  if (item.form != null) item.id: item.title,
              },
              onChanged: (value) async {
                if (value == _template) return;
                final replace =
                    form == null ||
                    await confirmWorkspaceAction(
                      context,
                      title: 'Replace the draft questionnaire?',
                      message:
                          'Switching templates replaces this project’s current draft questions.',
                      action: 'Replace questionnaire',
                    );
                if (!mounted) return;
                if (!replace) {
                  setState(() => _templateSelectRevision++);
                  return;
                }
                setState(() {
                  _template = value;
                  _questionnaireForm = widget.questionnaires
                      .where((choice) => choice.id == value)
                      .firstOrNull
                      ?.form;
                });
              },
            ),
          ),
        FormField<QuestionnaireForm>(
          validator: (_) => form == null
              ? 'Build a questionnaire with at least one question.'
              : null,
          builder: (field) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 10,
            children: [
              if (form != null)
                Text(
                  form.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              if (form != null)
                Text(
                  '${form.items.length} ${form.items.length == 1 ? 'question' : 'questions'}',
                ),
              Wrap(
                key: _guideTarget(_ProjectGuidePoint.edit),
                spacing: 8,
                runSpacing: 6,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () async {
                      await _editForm();
                      if (field.mounted) field.didChange(_questionnaireForm);
                    },
                    icon: const Icon(Icons.edit_note_rounded),
                    label: Text(
                      form == null
                          ? 'Build questionnaire'
                          : 'Edit questionnaire',
                    ),
                  ),
                  if (form != null)
                    TextButton.icon(
                      onPressed: () => widget.previewQuestionnaire(form),
                      icon: const Icon(Icons.visibility_outlined, size: 17),
                      label: const Text('Preview'),
                    ),
                ],
              ),
              if (field.errorText case final message?)
                AppNotice(message, tone: NoticeTone.error),
            ],
          ),
        ),
        const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            Icon(Icons.lock_outline_rounded, size: 17, color: workshopIce),
            Expanded(
              child: Text(
                'Your project starts private. Publish it to Community when the questionnaire is ready.',
                style: TextStyle(color: workshopMuted),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

bool validateAndReveal(GlobalKey<FormState> form) {
  final state = form.currentState;
  if (state == null) return false;
  final invalid = state.validateGranularly();
  if (invalid.isEmpty) return true;
  final first = invalid.first;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (first.mounted) {
      Scrollable.ensureVisible(first.context, alignment: .15);
    }
  });
  return false;
}

Future<bool> confirmWorkspaceAction(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
  bool destructive = false,
  String? subject,
  String? confirmationText,
  Future<void> Function()? perform,
}) async {
  final form = GlobalKey<FormState>();
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => WorkspaceDialogForm(
          title: title,
          action: action,
          destructive: destructive,
          width: 400,
          pendingLabel: 'Working…',
          onSave: () async {
            if (!validateAndReveal(form)) return false;
            await perform?.call();
            return true;
          },
          child: Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: [
                if (subject != null && subject.isNotEmpty)
                  Text(
                    subject,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                Text(message),
                if (confirmationText != null)
                  TextFormField(
                    decoration: InputDecoration(
                      labelText: 'Type $confirmationText to confirm',
                    ),
                    autocorrect: false,
                    enableSuggestions: false,
                    validator: (value) => value?.trim() == confirmationText
                        ? null
                        : 'Enter $confirmationText exactly as shown.',
                  ),
              ],
            ),
          ),
        ),
      ) ??
      false;
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

enum _ReviewGuidePoint {
  test(
    'Try the project first',
    'Open project to try the sample site. Follow the task under What to try before giving a rating.',
  ),
  rating(
    'Rate what you observed',
    'Try changing the sample rating, or keep it and continue. For an actual evaluation, rate each question based on what you observed.',
  ),
  feedback(
    'Write feedback the creator can act on',
    'Keep the sample feedback or try editing it. Useful feedback says what you tried, what happened, and what should change.',
  ),
  independence(
    'Review independently',
    'For a live evaluation, confirm you have no conflict of interest. You can continue through practice with this box unchecked.',
  ),
  submit(
    'Submit the evaluation',
    'Choose Submit practice to see the results. The tour uses sample answers for any fields you leave blank.',
  );

  const _ReviewGuidePoint(this.title, this.detail);
  final String title, detail;
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
    this.practice = false,
  });
  final List<WorkspaceRow> criteria;
  final Future<void> Function(ReviewDraft) save;
  final Widget projectBrief;
  final bool allowUnassessed, externalOnly, practice;
  final QuestionnaireForm? questionnaire;
  @override
  State<ReviewForm> createState() => _ReviewFormState();
}

class _ReviewFormState extends State<ReviewForm> {
  static const _sampleFeedback =
      'The Quiet rooms filter helped me find a study spot. Add a filter for power outlets.';
  List<String> get _levels =>
      widget.questionnaire?.levels ?? questionnaireScales['standard']!;
  final _form = GlobalKey<FormState>();
  final _feedback = TextEditingController();
  final Map<String, int> _scores = {};
  late final _guideTargets = {
    for (final point in _ReviewGuidePoint.values) point: GlobalKey(),
  };

  Key? _guideTarget(_ReviewGuidePoint point) =>
      widget.practice ? _guideTargets[point] : null;

  late final _details = List.filled(
    widget.questionnaire?.fields.length ?? 0,
    '',
  );

  @override
  void initState() {
    super.initState();
    if (!widget.practice) return;
    final score = _levels.length < 4 ? _levels.length : 4;
    for (final criterion in widget.criteria) {
      _scores[criterion['criterion_key'] as String] = score;
    }
    _feedback.text = _sampleFeedback;
  }

  @override
  void dispose() {
    _feedback.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WorkspaceDialogForm(
    title: widget.practice
        ? 'Evaluate project · Practice'
        : widget.questionnaire == null
        ? 'Write review'
        : 'Evaluate project',
    action: widget.practice ? 'Submit practice review' : 'Submit review',
    width: 540,
    submitKey: _guideTarget(_ReviewGuidePoint.submit),
    practiceTips: widget.practice
        ? [
            for (final point in _ReviewGuidePoint.values)
              PracticeTip(_guideTargets[point]!, point.title, point.detail),
          ]
        : null,
    onSave: widget.criteria.isEmpty && !widget.externalOnly
        ? null
        : () async {
            if (!widget.practice && !validateAndReveal(_form)) return false;
            final feedback = _feedback.text.trim();
            final draft = ReviewDraft(
              Map.of(_scores),
              widget.practice && feedback.isEmpty ? _sampleFeedback : feedback,
              respondentDetails: [for (final detail in _details) detail.trim()],
            );
            if (widget.practice) {
              await widget.save(draft);
              return true;
            }
            return confirmWorkspaceAction(
              context,
              title: 'Submit this review?',
              message:
                  'Your ratings and feedback will be shared with the project owner and collaborators. Your submission is final.',
              action: 'Submit final review',
              perform: () => widget.save(draft),
            );
          },
    child: Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          KeyedSubtree(
            key: _guideTarget(_ReviewGuidePoint.test),
            child: widget.projectBrief,
          ),
          const SizedBox(height: 18),
          if (widget.questionnaire case final form?) ...[
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
                    widget.practice
                        ? 'Sample answers are included. Edit them or continue as they are.'
                        : 'All ratings and feedback are required.',
                    style: const TextStyle(color: workshopMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (form.fields.isNotEmpty)
              ExpansionTile(
                title: const Text('Optional respondent details'),
                subtitle: Text(
                  widget.practice
                      ? 'You can leave these blank during practice.'
                      : 'Details are shared with the project owner and collaborators.',
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
            QuestionnaireCard(
              key: index == 0 ? _guideTarget(_ReviewGuidePoint.rating) : null,
              child: Column(
                spacing: 10,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('${index + 1}. ${criterion['prompt']}'),
                  WorkspaceSelect<int>(
                    initial: _scores[criterion['criterion_key']],
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
                    validator: (value) =>
                        value == null ? 'Choose a score' : null,
                  ),
                ],
              ),
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
            key: _guideTarget(_ReviewGuidePoint.feedback),
          ),
          FormField<bool>(
            initialValue: false,
            validator: (value) => value == true
                ? null
                : 'Confirm that you have no conflict of interest.',
            builder: (field) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CheckboxListTile(
                  key: _guideTarget(_ReviewGuidePoint.independence),
                  contentPadding: EdgeInsets.zero,
                  value: field.value ?? false,
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: field.didChange,
                  title: const Text('I have no conflict of interest.'),
                ),
                if (field.errorText case final message?)
                  AppNotice(message, tone: NoticeTone.error),
              ],
            ),
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
    this.destructive = false,
    this.pendingLabel = 'Saving…',
    this.submitKey,
    this.practiceTips,
  });
  final String title, action;
  final Widget child;
  final VoidCallback? onSubmit;
  final Future<bool> Function()? onSave;
  final double width;
  final bool destructive;
  final String pendingLabel;
  final Key? submitKey;
  final List<PracticeTip>? practiceTips;

  @override
  State<WorkspaceDialogForm> createState() => _WorkspaceDialogFormState();
}

class _WorkspaceDialogFormState extends State<WorkspaceDialogForm> {
  final _scroll = ScrollController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

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
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dialog = PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: Text(widget.title),
        content: SizedBox(
          width: widget.width,
          child: SingleChildScrollView(
            controller: _scroll,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_error case final message?)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: AppNotice(message, tone: NoticeTone.error),
                  ),
                ExcludeFocus(
                  excluding: _saving,
                  child: IgnorePointer(ignoring: _saving, child: widget.child),
                ),
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
            key: widget.submitKey,
            style: widget.destructive
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                  )
                : null,
            onPressed: _saving
                ? null
                : widget.onSave != null
                ? _save
                : widget.onSubmit,
            child: Text(_saving ? widget.pendingLabel : widget.action),
          ),
        ],
      ),
    );
    final tips = widget.practiceTips;
    if (tips == null) return dialog;
    return PracticeFormGuide(
      label: 'Evaluation practice',
      tips: tips,
      total: tips.length,
      advance: _save,
      advanceLabel: 'Submit practice',
      child: dialog,
    );
  }
}
