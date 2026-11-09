import 'package:flutter/material.dart';
import '../services/cloud_repository.dart';

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

TextFormField _input(TextEditingController controller, FormFieldSpec field) =>
    TextFormField(
      controller: controller,
      maxLength: field.max,
      maxLines: field.lines,
      keyboardType: field.url ? TextInputType.url : null,
      decoration: InputDecoration(
        labelText: field.label,
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
  Widget build(BuildContext context) => _DialogForm(
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
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('List me as an evaluator'),
              subtitle: const Text(
                'Members can see this profile and invite you.',
              ),
              value: _visible,
              onChanged: (value) => setState(() => _visible = value),
            ),
          ],
        ],
      ),
    ),
  );
}

class ProjectForm extends StatefulWidget {
  const ProjectForm({super.key, required this.rubrics, required this.save});
  final List<WorkspaceRow> rubrics;
  final Future<void> Function(WorkspaceRow) save;
  @override
  State<ProjectForm> createState() => _ProjectFormState();
}

class _ProjectFormState extends State<ProjectForm> {
  static const _categories = [
    'Research',
    'Prototype',
    'Game',
    'Creative work',
    'Other',
  ];
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController(),
      _summary = TextEditingController(),
      _link = TextEditingController();
  String _category = 'Prototype';
  String? _rubric;

  String? get _selectedRubric {
    final suggested =
        _rubric ??
        switch (_category) {
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
    _title.dispose();
    _summary.dispose();
    _link.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _DialogForm(
    title: 'New project',
    action: 'Create project',
    onSave: widget.rubrics.isEmpty
        ? null
        : () async {
            if (!_form.currentState!.validate()) return false;
            await widget.save({
              'title': _title.text.trim(),
              'category': _category,
              'summary': _summary.text.trim(),
              'artifact_url': _link.text.trim().isEmpty
                  ? null
                  : _link.text.trim(),
              'rubric_id': _selectedRubric,
            });
            return true;
          },
    child: Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _input(
            _title,
            const FormFieldSpec(
              'title',
              'Project title',
              max: 100,
              required: true,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _category,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Category'),
            items: _categories
                .map(
                  (value) => DropdownMenuItem(value: value, child: Text(value)),
                )
                .toList(),
            onChanged: (value) => setState(() {
              _category = value!;
              _rubric = null;
            }),
          ),
          const SizedBox(height: 12),
          _input(
            _summary,
            const FormFieldSpec(
              'summary',
              'Project brief',
              max: 2000,
              required: true,
              lines: 3,
            ),
          ),
          const SizedBox(height: 8),
          _input(
            _link,
            const FormFieldSpec(
              'artifact_url',
              'Project link',
              max: 500,
              url: true,
            ),
          ),
          const SizedBox(height: 8),
          if (widget.rubrics.isEmpty)
            const Text('No rubrics are available yet.')
          else
            DropdownButtonFormField<String>(
              key: ValueKey(_category),
              initialValue: _selectedRubric,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Rubric'),
              items: widget.rubrics
                  .map(
                    (row) => DropdownMenuItem(
                      value: row['id'] as String,
                      child: Text(row['name'] as String),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _rubric = value),
              validator: (value) => value == null ? 'Choose a rubric' : null,
            ),
          const SizedBox(height: 10),
          const Text('Private until you share it or invite an evaluator.'),
        ],
      ),
    ),
  );
}

class ReviewDraft {
  const ReviewDraft(this.scores, this.feedback);
  final Map<String, int> scores;
  final String feedback;
}

class ReviewForm extends StatefulWidget {
  const ReviewForm({
    super.key,
    required this.criteria,
    required this.projectTitle,
    required this.save,
  });
  final List<WorkspaceRow> criteria;
  final Future<void> Function(ReviewDraft) save;
  final String projectTitle;
  @override
  State<ReviewForm> createState() => _ReviewFormState();
}

class _ReviewFormState extends State<ReviewForm> {
  static const _levels = [
    '1 · Needs work',
    '2 · Developing',
    '3 · Meets expectations',
    '4 · Strong',
    '5 · Excellent',
  ];
  final _form = GlobalKey<FormState>();
  final _feedback = TextEditingController();
  final Map<String, int> _scores = {};
  bool _noConflict = false;

  @override
  void dispose() {
    _feedback.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _DialogForm(
    title: 'Write review',
    action: 'Submit review',
    onSave: !_noConflict || widget.criteria.isEmpty
        ? null
        : () async {
            if (!_form.currentState!.validate()) return false;
            await widget.save(
              ReviewDraft(Map.of(_scores), _feedback.text.trim()),
            );
            return true;
          },
    child: Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.projectTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 14),
          if (widget.criteria.isEmpty)
            const Text('This rubric has no criteria.'),
          for (final criterion in widget.criteria) ...[
            Text(criterion['prompt'] as String),
            const SizedBox(height: 6),
            DropdownButtonFormField<int>(
              isExpanded: true,
              decoration: InputDecoration(
                labelText: criterion['label'] as String,
              ),
              items: List.generate(
                _levels.length,
                (index) => DropdownMenuItem(
                  value: index + 1,
                  child: Text(_levels[index]),
                ),
              ),
              onChanged: (value) =>
                  _scores[criterion['criterion_key'] as String] = value!,
              validator: (value) => value == null ? 'Choose a score' : null,
            ),
            const SizedBox(height: 14),
          ],
          _input(
            _feedback,
            const FormFieldSpec(
              'feedback',
              'Feedback and next steps',
              max: 4000,
              required: true,
              lines: 4,
            ),
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

class _DialogForm extends StatefulWidget {
  const _DialogForm({
    required this.title,
    required this.action,
    required this.child,
    this.onSubmit,
    this.onSave,
  });
  final String title, action;
  final Widget child;
  final VoidCallback? onSubmit;
  final Future<bool> Function()? onSave;

  @override
  State<_DialogForm> createState() => _DialogFormState();
}

class _DialogFormState extends State<_DialogForm> {
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
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
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
