import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../services/cloud_repository.dart';
import '../widgets/app_notice.dart';
import '../widgets/cantiere_wordmark.dart';
import '../widgets/evaluation_backdrop.dart';
import '../widgets/workshop_glass.dart';
import '../widgets/workspace_select.dart';
import 'workspace_forms.dart';

class AccountSetupFrame extends StatelessWidget {
  const AccountSetupFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Stack(
      fit: StackFit.expand,
      children: [
        const EvaluationBackdrop(),
        SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: (constraints.maxHeight - 32).clamp(
                    0.0,
                    double.infinity,
                  ),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 496),
                    child: WorkshopGlass(
                      featured: true,
                      child: Padding(
                        padding: EdgeInsets.all(
                          constraints.maxWidth < 460 ? 16 : 22,
                        ),
                        child: child,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class AccountSetupScreen extends StatefulWidget {
  const AccountSetupScreen({
    super.key,
    required this.profile,
    required this.save,
    required this.signOut,
  });

  final WorkspaceRow profile;
  final Future<void> Function(WorkspaceRow) save;
  final Future<void> Function() signOut;

  @override
  State<AccountSetupScreen> createState() => _AccountSetupScreenState();
}

class _AccountSetupScreenState extends State<AccountSetupScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(
    text: widget.profile['display_name'] as String? ?? '',
  );
  late final _expertise = TextEditingController(
    text: widget.profile['expertise'] as String? ?? '',
  );
  late String? _profession = widget.profile['profession'] as String?;
  late bool _visible = widget.profile['directory_visible'] == true;
  late String _evaluatorType =
      widget.profile['evaluator_type'] as String? ?? 'community';
  bool _intro = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _expertise.dispose();
    super.dispose();
  }

  void _continue() {
    FocusScope.of(context).unfocus();
    setState(() => _intro = false);
  }

  Future<void> _finish() async {
    if (!validateAndReveal(_form)) return;
    await _submit(
      () => widget.save({
        'display_name': _name.text.trim(),
        'profession': _profession,
        'expertise': _expertise.text.trim(),
        'directory_visible': _visible,
        'evaluator_type': _evaluatorType,
      }),
    );
  }

  Future<void> _submit(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = workspaceError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AccountSetupFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: CantiereWordmark(fontSize: 24)),
              TextButton(
                onPressed: _busy ? null : () => _submit(widget.signOut),
                child: const Text('Sign out'),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Text(
            _intro ? 'STEP 1 OF 2 · WELCOME' : 'STEP 2 OF 2 · PROFILE',
            style: text.labelSmall?.copyWith(
              color: workshopIce,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 7),
          Semantics(
            header: true,
            child: Text(
              _intro ? 'Welcome to In Cantiere' : 'Set up your profile',
              style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _intro
                ? 'Get structured feedback on work in progress, and help other members improve theirs.'
                : 'Choose how your name and profession appear to other members.',
            style: text.bodyMedium?.copyWith(color: workshopMuted),
          ),
          const SizedBox(height: 17),
          if (_intro) ...[
            const _SetupTip(
              Icons.layers_outlined,
              'Create a project',
              'Add a link and tell reviewers what to try.',
            ),
            const _SetupTip(
              Icons.fact_check_outlined,
              'Choose a questionnaire',
              'Build a form or edit an in-app template before you publish.',
            ),
            const _SetupTip(
              Icons.rate_review_outlined,
              'Give feedback',
              'Test a community project and submit your findings here.',
            ),
          ] else
            Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _name,
                    maxLength: 80,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Display name',
                      counterText: '',
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enter a display name'
                        : null,
                  ),
                  const SizedBox(height: 13),
                  WorkspaceSelect<String>(
                    label: 'Profession',
                    initial: _profession,
                    choices: professions,
                    icon: Icons.work_outline,
                    onChanged: (value) => _profession = value,
                    validator: (value) =>
                        value == null ? 'Choose a profession' : null,
                  ),
                  const SizedBox(height: 13),
                  TextFormField(
                    controller: _expertise,
                    maxLength: 240,
                    decoration: const InputDecoration(
                      labelText: 'Areas of expertise (optional)',
                      hintText: 'e.g. Web development, usability, research',
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 10),
                  ProfileVisibilityFields(
                    visible: _visible,
                    evaluatorType: _evaluatorType,
                    onVisible: (value) => setState(() => _visible = value),
                    onType: (value) => _evaluatorType = value,
                  ),
                ],
              ),
            ),
          const SizedBox(height: 14),
          if (!_intro)
            Text(
              'You can change these details in Profile.',
              style: text.bodySmall?.copyWith(color: workshopMuted),
            ),
          if (_error case final message?) ...[
            const SizedBox(height: 10),
            AppNotice(message, tone: NoticeTone.error),
          ],
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (!_intro)
                TextButton(
                  onPressed: _busy ? null : () => setState(() => _intro = true),
                  child: const Text('Back'),
                ),
              Flexible(
                child: FilledButton(
                  onPressed: _busy
                      ? null
                      : _intro
                      ? _continue
                      : _finish,
                  child: Text(
                    _busy
                        ? 'Please wait…'
                        : _intro
                        ? 'Continue'
                        : 'Finish setup',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SetupTip extends StatelessWidget {
  const _SetupTip(this.icon, this.title, this.description);

  final IconData icon;
  final String title, description;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2, right: 9),
          child: Icon(icon, color: workshopIce, size: 17),
        ),
        Expanded(
          child: Text.rich(
            TextSpan(
              text: '$title\n',
              style: const TextStyle(fontWeight: FontWeight.w700),
              children: [
                TextSpan(
                  text: description,
                  style: const TextStyle(
                    color: workshopMuted,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
