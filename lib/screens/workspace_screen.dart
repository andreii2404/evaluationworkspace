import 'package:flutter/material.dart';

import '../data/sample_data.dart';
import '../models/workspace_models.dart';
import '../services/workspace_repository.dart';
import '../widgets/app_notice.dart';

const _ink = Color(0xFF17283F);
const _muted = Color(0xFF475467);
const _line = Color(0xFFE9EAF1);
const _brandTeal = Color(0xFF0F766E);
const _canvas = Color(0xFFF6F8FA);

enum _Section { overview, projects, evaluators, reviews, trust }

class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({super.key});

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  final _repository = WorkspaceRepository();
  _Section _section = _Section.overview;
  List<EvaluationProject> _projects = sampleProjects;
  List<LocalInvitation> _invitations = const [];
  List<LocalReviewResponse> _responses = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadWorkspace();
  }

  Future<void> _loadWorkspace() async {
    final values = await Future.wait([
      _repository.loadProjects(),
      _repository.loadInvitations(),
      _repository.loadResponses(),
    ]);
    if (!mounted) return;
    setState(() {
      _projects = values[0] as List<EvaluationProject>;
      _invitations = values[1] as List<LocalInvitation>;
      _responses = values[2] as List<LocalReviewResponse>;
      _loading = false;
    });
  }

  Future<void> _saveProjects() => _repository.saveProjects(_projects);

  void _notify(String message) => AppNotice.show(context, message);

  Future<void> _createProject() async {
    final project = await showDialog<EvaluationProject>(
      context: context,
      builder: (context) => const _CreateProjectDialog(),
    );
    if (project == null) return;
    setState(() => _projects = [project, ..._projects]);
    await _saveProjects();
    if (mounted) _notify('Project added to this browser workspace.');
  }

  Future<void> _inviteEvaluator(
    EvaluatorProfile evaluator,
    EvaluationProject project,
  ) async {
    if (_invitations.any(
      (item) =>
          item.evaluatorName == evaluator.name &&
          item.projectName == project.name,
    )) {
      _notify(
        'This evaluator already has a local invitation for that project.',
      );
      return;
    }
    final invitation = LocalInvitation(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      evaluatorName: evaluator.name,
      projectName: project.name,
      createdLabel: 'Just now',
      status: 'Draft · local only',
    );
    setState(() => _invitations = [invitation, ..._invitations]);
    await _repository.saveInvitations(_invitations);
    if (mounted) {
      _notify(
        'Invitation saved locally. Sending requires accounts and a backend.',
      );
    }
  }

  Future<void> _submitReview(
    ReviewTask task,
    int rating,
    String comment,
  ) async {
    final response = LocalReviewResponse(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      projectName: task.projectName,
      evaluatorName: 'You · demo evaluator',
      rating: rating,
      comment: comment,
      createdLabel: 'Just now',
    );
    setState(() {
      _responses = [response, ..._responses];
      _projects = _projects.map((project) {
        if (project.id != task.projectId) return project;
        final updatedResponses = project.responses + 1;
        return project.copyWith(
          responses: updatedResponses,
          status: updatedResponses >= project.responseGoal
              ? ProjectStatus.completed
              : ProjectStatus.reviewing,
          updatedLabel: 'Updated just now',
        );
      }).toList();
    });
    await Future.wait([_repository.saveResponses(_responses), _saveProjects()]);
    if (mounted) _notify('Review saved in this browser.');
  }

  Future<void> _resetWorkspace() async {
    final shouldReset = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset local workspace?'),
        content: const Text(
          'This removes projects you created, invitations, and review responses saved in this browser. Sample projects will return.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset workspace'),
          ),
        ],
      ),
    );
    if (shouldReset != true) return;
    await _repository.resetLocalWorkspace();
    if (!mounted) return;
    setState(() {
      _projects = sampleProjects;
      _invitations = const [];
      _responses = const [];
    });
    _notify('Local workspace reset.');
  }

  void _selectSection(_Section section) => setState(() => _section = section);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1060;
        final content = _buildContent(wide: wide);
        if (_loading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator(color: _brandTeal)),
          );
        }
        if (wide) {
          return Scaffold(
            backgroundColor: _canvas,
            body: Row(
              children: [
                _Sidebar(
                  section: _section,
                  onSelect: _selectSection,
                  projectCount: _projects.length,
                  reviewCount: sampleReviewTasks.length + _responses.length,
                  onReset: _resetWorkspace,
                ),
                Expanded(child: content),
              ],
            ),
          );
        }
        return Scaffold(
          backgroundColor: _canvas,
          appBar: AppBar(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
            title: const _Brand(compact: true),
            actions: [
              IconButton(
                tooltip: 'Local demo workspace',
                onPressed: () => _showDemoInfo(context),
                icon: const Icon(Icons.info_outline_rounded),
              ),
              const SizedBox(width: 8),
            ],
          ),
          drawer: Drawer(
            child: _Sidebar(
              section: _section,
              onSelect: (section) {
                _selectSection(section);
                Navigator.pop(context);
              },
              projectCount: _projects.length,
              reviewCount: sampleReviewTasks.length + _responses.length,
              onReset: _resetWorkspace,
            ),
          ),
          body: content,
        );
      },
    );
  }

  Widget _buildContent({required bool wide}) {
    return Column(
      children: [
        if (wide) const _TopBar(),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              wide ? 42 : 20,
              wide ? 34 : 24,
              wide ? 42 : 20,
              44,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1440),
                child: _sectionBody(wide),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionBody(bool wide) {
    switch (_section) {
      case _Section.overview:
        return _overview(wide);
      case _Section.projects:
        return _projectsView(wide);
      case _Section.evaluators:
        return _evaluatorsView(wide);
      case _Section.reviews:
        return _reviewsView(wide);
      case _Section.trust:
        return _trustView(wide);
    }
  }

  Widget _pageHeading({
    required String eyebrow,
    required String title,
    required String subtitle,
    Widget? action,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow.toUpperCase(),
                style: const TextStyle(
                  color: _brandTeal,
                  fontSize: 11,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(title, style: Theme.of(context).textTheme.headlineLarge),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: const TextStyle(color: _muted, fontSize: 14),
              ),
            ],
          ),
        ),
        ?action,
      ],
    ),
  );

  Widget _overview(bool wide) {
    final projectsActive = _projects
        .where((p) => p.status != ProjectStatus.completed)
        .length;
    final reviewsPending = sampleReviewTasks.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _pageHeading(
          eyebrow: 'Tuesday, November 3, 2026',
          title: 'Good morning, Alex',
          subtitle:
              'Your evaluation workspace is ready. Pick up where you left off.',
          action: FilledButton.icon(
            onPressed: _createProject,
            icon: const Icon(Icons.add_rounded, size: 19),
            label: const Text('New project'),
          ),
        ),
        const _LocalDemoBanner(),
        const SizedBox(height: 20),
        _WelcomePanel(
          onCreate: _createProject,
          onBrowse: () => _selectSection(_Section.evaluators),
        ),
        const SizedBox(height: 20),
        _MetricRow(
          metrics: [
            _MetricData(
              'Active projects',
              '$projectsActive',
              'Across your workspace',
              Icons.grid_view_rounded,
              const Color(0xFF0F766E),
              const Color(0xFFD9F3EE),
            ),
            _MetricData(
              'Reviews to explore',
              '$reviewsPending',
              'Sample review tasks',
              Icons.fact_check_outlined,
              const Color(0xFFE6A53C),
              const Color(0xFFFFF6E7),
            ),
            _MetricData(
              'Responses received',
              '${_responses.length + 9}',
              'Includes sample activity',
              Icons.forum_outlined,
              const Color(0xFF2E9B7E),
              const Color(0xFFE7F6F1),
            ),
            _MetricData(
              'Local invitations',
              '${_invitations.length}',
              'Saved on this device',
              Icons.outgoing_mail,
              const Color(0xFF4E83C4),
              const Color(0xFFEAF2FB),
            ),
          ],
        ),
        const SizedBox(height: 28),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: wide ? 7 : 1,
              child: _Panel(
                title: 'Your projects',
                subtitle: 'Track progress and feedback',
                trailing: TextButton(
                  onPressed: () => _selectSection(_Section.projects),
                  child: const Text('View all'),
                ),
                child: _projects.isEmpty
                    ? _EmptyState(
                        icon: Icons.inventory_2_outlined,
                        title: 'No projects yet',
                        body:
                            'Create a project to start gathering structured feedback.',
                      )
                    : Column(
                        children: _projects
                            .take(3)
                            .map(
                              (project) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _ProjectRow(
                                  project: project,
                                  onTap: () => _showProjectDetails(project),
                                ),
                              ),
                            )
                            .toList(),
                      ),
              ),
            ),
            if (wide) const SizedBox(width: 20),
            if (wide)
              Expanded(
                flex: 4,
                child: _Panel(
                  title: 'Next up',
                  subtitle: 'Review opportunities',
                  trailing: TextButton(
                    onPressed: () => _selectSection(_Section.reviews),
                    child: const Text('See all'),
                  ),
                  child: Column(
                    children: sampleReviewTasks
                        .take(2)
                        .map(
                          (task) => Padding(
                            padding: const EdgeInsets.only(bottom: 11),
                            child: _TaskTile(
                              task: task,
                              onTap: () => _openReview(task),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
          ],
        ),
        if (!wide) ...[
          const SizedBox(height: 18),
          _Panel(
            title: 'Next up',
            subtitle: 'Review opportunities',
            trailing: TextButton(
              onPressed: () => _selectSection(_Section.reviews),
              child: const Text('See all'),
            ),
            child: Column(
              children: sampleReviewTasks
                  .take(2)
                  .map(
                    (task) => Padding(
                      padding: const EdgeInsets.only(bottom: 11),
                      child: _TaskTile(
                        task: task,
                        onTap: () => _openReview(task),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
        const SizedBox(height: 18),
        _TrustNudge(onTap: () => _selectSection(_Section.trust)),
      ],
    );
  }

  Widget _projectsView(bool wide) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _pageHeading(
          eyebrow: 'Workspace',
          title: 'Your projects',
          subtitle: 'Organize prototypes and see the feedback they receive.',
          action: FilledButton.icon(
            onPressed: _createProject,
            icon: const Icon(Icons.add_rounded),
            label: const Text('New project'),
          ),
        ),
        const _LocalDemoBanner(),
        const SizedBox(height: 20),
        _Panel(
          title: '${_projects.length} projects',
          subtitle: 'Project records are stored in this browser.',
          child: _projects.isEmpty
              ? _EmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: 'Start with a project',
                  body:
                      'Add a capstone, prototype, game, study, or other work for evaluation.',
                  action: FilledButton(
                    onPressed: _createProject,
                    child: const Text('Create a project'),
                  ),
                )
              : Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: _projects
                      .map(
                        (project) => SizedBox(
                          width: wide ? 340 : double.infinity,
                          child: _ProjectCard(
                            project: project,
                            onTap: () => _showProjectDetails(project),
                          ),
                        ),
                      )
                      .toList(),
                ),
        ),
        const SizedBox(height: 18),
        _SectionNote(
          icon: Icons.lock_outline_rounded,
          text:
              'Projects are private to this browser profile in the prototype. A production version needs sign-in, access controls, and server-side storage before sharing sensitive work.',
        ),
      ],
    );
  }

  Widget _evaluatorsView(bool wide) {
    return _EvaluatorsView(
      wide: wide,
      projects: _projects,
      invitations: _invitations,
      onInvite: _inviteEvaluator,
    );
  }

  Widget _reviewsView(bool wide) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _pageHeading(
          eyebrow: 'Feedback',
          title: 'Reviews & testing',
          subtitle:
              'Explore review tasks or inspect the feedback saved in this browser.',
        ),
        const _LocalDemoBanner(),
        const SizedBox(height: 20),
        _Panel(
          title: 'Open review tasks',
          subtitle: 'Illustrative examples for this prototype',
          child: Column(
            children: sampleReviewTasks
                .map(
                  (task) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _TaskTile(
                      task: task,
                      onTap: () => _openReview(task),
                      expanded: true,
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 18),
        _Panel(
          title: 'Feedback received',
          subtitle: 'New submissions saved on this device',
          child: _responses.isEmpty
              ? _EmptyState(
                  icon: Icons.chat_bubble_outline_rounded,
                  title: 'No local submissions yet',
                  body:
                      'Submit a sample review from an open task to see how feedback is displayed here.',
                )
              : Column(
                  children: _responses
                      .map((response) => _ResponseTile(response: response))
                      .toList(),
                ),
        ),
        const SizedBox(height: 18),
        _SectionNote(
          icon: Icons.visibility_outlined,
          text:
              'Review prompts are examples. Real evaluations need consent, a defined rubric, clear data retention, and a way to report harmful or conflicted reviews.',
        ),
      ],
    );
  }

  Widget _trustView(bool wide) =>
      _TrustView(wide: wide, onReset: _resetWorkspace);

  Future<void> _showProjectDetails(EvaluationProject project) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            _ProjectIcon(project: project, size: 42),
            const SizedBox(width: 12),
            Expanded(child: Text(project.name)),
          ],
        ),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StatusPill(status: project.status),
              const SizedBox(height: 16),
              Text(
                project.summary,
                style: const TextStyle(color: _muted, height: 1.5),
              ),
              const SizedBox(height: 18),
              _InfoLine(label: 'Type', value: project.category),
              _InfoLine(
                label: 'Responses',
                value: '${project.responses} of ${project.responseGoal} goal',
              ),
              _InfoLine(label: 'Last updated', value: project.updatedLabel),
              const SizedBox(height: 12),
              const _SectionNote(
                icon: Icons.storage_outlined,
                text:
                    'This project is saved locally in your browser. No one else can see it yet.',
              ),
            ],
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
  }

  Future<void> _openReview(ReviewTask task) async {
    final result = await showDialog<_ReviewResult>(
      context: context,
      builder: (context) => _ReviewDialog(task: task),
    );
    if (result != null) {
      await _submitReview(task, result.rating, result.comment);
    }
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.section,
    required this.onSelect,
    required this.projectCount,
    required this.reviewCount,
    required this.onReset,
  });

  final _Section section;
  final ValueChanged<_Section> onSelect;
  final int projectCount;
  final int reviewCount;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 246,
      color: const Color(0xFF17283F),
      padding: const EdgeInsets.fromLTRB(17, 26, 17, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 12, bottom: 32),
            child: _Brand(dark: true),
          ),
          const Padding(
            padding: EdgeInsets.only(left: 12, bottom: 10),
            child: Text(
              'WORKSPACE',
              style: TextStyle(
                color: Color(0xFF8E91A9),
                fontSize: 10,
                letterSpacing: 1.6,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _NavItem(
            icon: Icons.space_dashboard_outlined,
            label: 'Overview',
            selected: section == _Section.overview,
            onTap: () => onSelect(_Section.overview),
          ),
          _NavItem(
            icon: Icons.widgets_outlined,
            label: 'Projects',
            count: '$projectCount',
            selected: section == _Section.projects,
            onTap: () => onSelect(_Section.projects),
          ),
          _NavItem(
            icon: Icons.people_outline_rounded,
            label: 'Find evaluators',
            selected: section == _Section.evaluators,
            onTap: () => onSelect(_Section.evaluators),
          ),
          _NavItem(
            icon: Icons.fact_check_outlined,
            label: 'Reviews & testing',
            count: '$reviewCount',
            selected: section == _Section.reviews,
            onTap: () => onSelect(_Section.reviews),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 27, 12, 10),
            child: Text(
              'ACCOUNT & TRUST',
              style: TextStyle(
                color: Color(0xFF8E91A9),
                fontSize: 10,
                letterSpacing: 1.6,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _NavItem(
            icon: Icons.verified_user_outlined,
            label: 'Trust & safety',
            selected: section == _Section.trust,
            onTap: () => onSelect(_Section.trust),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: const Color(0xFF23243B),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF33344B)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.lightbulb_outline_rounded,
                  color: Color(0xFFB9B5FF),
                  size: 20,
                ),
                SizedBox(height: 12),
                Text(
                  'Build with confidence',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Use clear criteria and protect people’s work while gathering feedback.',
                  style: TextStyle(
                    color: Color(0xFFB7B9C8),
                    height: 1.4,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 17),
          Row(
            children: [
              const CircleAvatar(
                radius: 18,
                backgroundColor: Color(0xFF3C3D59),
                child: Text(
                  'AL',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Alex Lee',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Personal workspace',
                      style: TextStyle(color: Color(0xFF9698AC), fontSize: 10),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Workspace options',
                icon: const Icon(Icons.more_horiz, color: Color(0xFFB7B9C8)),
                onSelected: (value) {
                  if (value == 'reset') onReset();
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'reset',
                    child: Text('Reset local workspace'),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
  });
  final IconData icon;
  final String label;
  final String? count;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Material(
        color: selected ? const Color(0xFF35324F) : Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 19,
                  color: selected
                      ? const Color(0xFFC8C5FF)
                      : const Color(0xFFAAAABD),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: selected ? Colors.white : const Color(0xFFC2C3D0),
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                if (count != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFF4B4770)
                          : const Color(0xFF292A40),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      count!,
                      style: const TextStyle(
                        color: Color(0xFFD5D3FF),
                        fontSize: 10,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({this.dark = false, this.compact = false});
  final bool dark;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final primary = dark ? Colors.white : _ink;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: _brandTeal,
            borderRadius: BorderRadius.circular(11),
          ),
          child: const Icon(Icons.hub_rounded, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 10),
        Text(
          'evalink',
          style: TextStyle(
            fontSize: compact ? 18 : 21,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
            color: primary,
          ),
        ),
        if (!compact) ...[
          const SizedBox(width: 7),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF34344F) : const Color(0xFFD9F3EE),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'BETA',
              style: TextStyle(
                color: dark ? const Color(0xFFC8C5FF) : _brandTeal,
                fontSize: 8,
                fontWeight: FontWeight.w800,
                letterSpacing: .6,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 42),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Your evaluation workspace',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'A clear place to gather useful feedback',
                  style: TextStyle(color: _muted, fontSize: 10),
                ),
              ],
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F0FF),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Row(
              children: [
                Icon(Icons.storage_outlined, size: 15, color: _brandTeal),
                SizedBox(width: 6),
                Text(
                  'LOCAL DEMO',
                  style: TextStyle(
                    color: _brandTeal,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .6,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          IconButton(
            tooltip: 'Notifications are not connected in this demo',
            onPressed: () => _showDemoInfo(context),
            icon: const Icon(Icons.notifications_none_rounded, color: _muted),
          ),
          const SizedBox(width: 10),
          const CircleAvatar(
            radius: 17,
            backgroundColor: Color(0xFFE7E5FF),
            child: Text(
              'AL',
              style: TextStyle(
                color: _brandTeal,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 42),
        ],
      ),
    );
  }
}

class _LocalDemoBanner extends StatelessWidget {
  const _LocalDemoBanner();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8EA),
        border: Border.all(color: const Color(0xFFF4E3BB)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFFAA7620)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Prototype workspace · Sample profiles and activity are illustrative. Changes save only in this browser.',
              style: TextStyle(
                color: Color(0xFF795E2D),
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WelcomePanel extends StatelessWidget {
  const _WelcomePanel({required this.onCreate, required this.onBrowse});
  final VoidCallback onCreate;
  final VoidCallback onBrowse;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(28, 25, 26, 25),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFEFEEFF), Color(0xFFE9F5F5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE6E5F5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .75),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'FROM IDEA TO EVIDENCE',
                    style: TextStyle(
                      color: _brandTeal,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Better feedback starts\nwith a clear question.',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontSize: 23,
                    height: 1.22,
                  ),
                ),
                const SizedBox(height: 9),
                const Text(
                  'Set your goal, find the right reviewers, and collect useful feedback in one place.',
                  style: TextStyle(color: _muted, fontSize: 12, height: 1.5),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 9,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      onPressed: onCreate,
                      child: const Text('Create a project'),
                    ),
                    OutlinedButton(
                      onPressed: onBrowse,
                      child: const Text('Explore evaluators'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (MediaQuery.sizeOf(context).width >= 760) ...[
            const SizedBox(width: 24),
            const _WelcomeIllustration(),
          ],
        ],
      ),
    );
  }
}

class _WelcomeIllustration extends StatelessWidget {
  const _WelcomeIllustration();
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 210,
      height: 150,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            right: 24,
            top: 13,
            child: Transform.rotate(
              angle: -.08,
              child: Container(
                width: 142,
                height: 115,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .82),
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x160D1A40),
                      blurRadius: 20,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 25,
                          height: 25,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE9E7FF),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.task_alt_rounded,
                            size: 15,
                            color: _brandTeal,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Feedback',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 10,
                            color: _ink,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      height: 6,
                      width: 99,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE7E8F0),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Container(
                      height: 6,
                      width: 76,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE7E8F0),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const Spacer(),
                    Row(
                      children: List.generate(
                        5,
                        (index) => const Padding(
                          padding: EdgeInsets.only(right: 2),
                          child: Icon(
                            Icons.star_rounded,
                            size: 12,
                            color: Color(0xFFE8AC4A),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 6,
            top: 17,
            child: _FloatBadge(
              icon: Icons.verified_user_outlined,
              color: const Color(0xFF43A68B),
            ),
          ),
          Positioned(
            left: 32,
            bottom: 1,
            child: _FloatBadge(
              icon: Icons.people_outline_rounded,
              color: _brandTeal,
            ),
          ),
          Positioned(
            right: 1,
            bottom: 14,
            child: _FloatBadge(
              icon: Icons.lightbulb_outline_rounded,
              color: const Color(0xFFE0A13F),
            ),
          ),
        ],
      ),
    );
  }
}

class _FloatBadge extends StatelessWidget {
  const _FloatBadge({required this.icon, required this.color});
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    width: 38,
    height: 38,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: const [
        BoxShadow(
          color: Color(0x160D1A40),
          blurRadius: 12,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: Icon(icon, color: color, size: 19),
  );
}

class _MetricData {
  const _MetricData(
    this.label,
    this.value,
    this.note,
    this.icon,
    this.color,
    this.tint,
  );
  final String label;
  final String value;
  final String note;
  final IconData icon;
  final Color color;
  final Color tint;
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.metrics});
  final List<_MetricData> metrics;
  @override
  Widget build(BuildContext context) {
    final columns = MediaQuery.sizeOf(context).width >= 1240
        ? 4
        : MediaQuery.sizeOf(context).width >= 700
        ? 2
        : 1;
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = columns == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - 14 * (columns - 1)) / columns;
        return Wrap(
          spacing: 14,
          runSpacing: 14,
          children: metrics
              .map(
                (metric) => SizedBox(
                  width: itemWidth,
                  child: _MetricCard(metric: metric),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric});
  final _MetricData metric;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _line),
    ),
    child: Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: metric.tint,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(metric.icon, color: metric.color, size: 20),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                metric.label,
                style: const TextStyle(color: _muted, fontSize: 11),
              ),
              const SizedBox(height: 3),
              Text(
                metric.value,
                style: const TextStyle(
                  color: _ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                  letterSpacing: -.5,
                ),
              ),
              Text(
                metric.note,
                style: const TextStyle(color: Color(0xFF999CAB), fontSize: 9),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: _line),
      borderRadius: BorderRadius.circular(17),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    subtitle,
                    style: const TextStyle(color: _muted, fontSize: 11),
                  ),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
        const SizedBox(height: 18),
        child,
      ],
    ),
  );
}

class _ProjectIcon extends StatelessWidget {
  const _ProjectIcon({required this.project, this.size = 44});
  final EvaluationProject project;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: Color(project.accentValue).withValues(alpha: .12),
      borderRadius: BorderRadius.circular(size * .28),
    ),
    child: Icon(
      _iconForProjectCategory(project.category),
      color: Color(project.accentValue),
      size: size * .48,
    ),
  );
}

IconData _iconForProjectCategory(String category) => switch (category) {
  'Mobile application' => Icons.phone_iphone_rounded,
  'Learning tool' => Icons.auto_stories_rounded,
  'Web platform' => Icons.language_rounded,
  'Game or interactive media' => Icons.sports_esports_outlined,
  'Research study' => Icons.science_outlined,
  'Software prototype' => Icons.lightbulb_outline_rounded,
  _ => Icons.widgets_rounded,
};

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final ProjectStatus status;
  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      ProjectStatus.prototype => const Color(0xFF687087),
      ProjectStatus.recruiting => const Color(0xFF2E8C70),
      ProjectStatus.reviewing => _brandTeal,
      ProjectStatus.completed => const Color(0xFF3D7CC2),
    };
    final tint = switch (status) {
      ProjectStatus.prototype => const Color(0xFFF0F1F5),
      ProjectStatus.recruiting => const Color(0xFFE9F6F1),
      ProjectStatus.reviewing => const Color(0xFFD9F3EE),
      ProjectStatus.completed => const Color(0xFFEAF2FB),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ProjectRow extends StatelessWidget {
  const _ProjectRow({required this.project, required this.onTap});
  final EvaluationProject project;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFFFBFBFD),
    borderRadius: BorderRadius.circular(13),
    child: InkWell(
      borderRadius: BorderRadius.circular(13),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Row(
          children: [
            _ProjectIcon(project: project),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          project.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _StatusPill(status: project.status),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${project.category} · ${project.updatedLabel}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 10),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 70,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${project.responses}/${project.responseGoal}',
                    style: const TextStyle(
                      color: _ink,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: project.progress.clamp(0, 1),
                    minHeight: 5,
                    borderRadius: BorderRadius.circular(5),
                    backgroundColor: const Color(0xFFEDEEF4),
                    color: Color(project.accentValue),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 7),
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFFAAACB8),
              size: 18,
            ),
          ],
        ),
      ),
    ),
  );
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project, required this.onTap});
  final EvaluationProject project;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          border: Border.all(color: _line),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _ProjectIcon(project: project),
                const Spacer(),
                _StatusPill(status: project.status),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              project.name,
              style: const TextStyle(
                fontSize: 15,
                color: _ink,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              project.category,
              style: const TextStyle(fontSize: 10, color: _muted),
            ),
            const SizedBox(height: 10),
            Text(
              project.summary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                height: 1.45,
                color: Color(0xFF676B7E),
              ),
            ),
            const SizedBox(height: 15),
            LinearProgressIndicator(
              value: project.progress.clamp(0, 1),
              minHeight: 5,
              borderRadius: BorderRadius.circular(5),
              backgroundColor: const Color(0xFFEDEEF4),
              color: Color(project.accentValue),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  '${project.responses} of ${project.responseGoal} responses',
                  style: const TextStyle(fontSize: 10, color: _muted),
                ),
                const Spacer(),
                Text(
                  project.updatedLabel,
                  style: const TextStyle(fontSize: 9, color: Color(0xFF9B9EAD)),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({
    required this.task,
    required this.onTap,
    this.expanded = false,
  });
  final ReviewTask task;
  final VoidCallback onTap;
  final bool expanded;
  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFFFBFBFD),
    borderRadius: BorderRadius.circular(13),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(13),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Row(
          children: [
            CircleAvatar(
              radius: 19,
              backgroundColor: Color(task.accentValue).withValues(alpha: .13),
              child: Text(
                task.initials,
                style: TextStyle(
                  color: Color(task.accentValue),
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                ),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${task.projectName} · ${task.kind}',
                    style: const TextStyle(color: _muted, fontSize: 9),
                  ),
                  if (expanded) ...[
                    const SizedBox(height: 5),
                    Text(
                      'From ${task.reviewerName} · ${task.dueLabel}',
                      style: const TextStyle(
                        color: Color(0xFF8C90A0),
                        fontSize: 9,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 9),
            if (!expanded)
              Text(
                task.dueLabel,
                style: const TextStyle(color: _muted, fontSize: 9),
              ),
            const SizedBox(width: 6),
            const Icon(
              Icons.chevron_right_rounded,
              size: 17,
              color: Color(0xFFAAAEBB),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ResponseTile extends StatelessWidget {
  const _ResponseTile({required this.response});
  final LocalReviewResponse response;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 11),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFFBFBFD),
      borderRadius: BorderRadius.circular(13),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.chat_bubble_outline_rounded,
          color: _brandTeal,
          size: 18,
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${response.projectName} · ${response.evaluatorName}',
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  _Stars(rating: response.rating, size: 13),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                response.comment,
                style: const TextStyle(
                  color: _muted,
                  fontSize: 11,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                response.createdLabel,
                style: const TextStyle(color: Color(0xFF9A9DAB), fontSize: 9),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Stars extends StatelessWidget {
  const _Stars({required this.rating, this.size = 18});
  final int rating;
  final double size;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: List.generate(
      5,
      (index) => Icon(
        index < rating ? Icons.star_rounded : Icons.star_outline_rounded,
        size: size,
        color: const Color(0xFFE5A642),
      ),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });
  final IconData icon;
  final String title;
  final String body;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Column(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFD9F3EE),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: _brandTeal),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              color: _ink,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontSize: 11, height: 1.45),
          ),
          if (action != null) ...[const SizedBox(height: 12), action!],
        ],
      ),
    ),
  );
}

class _SectionNote extends StatelessWidget {
  const _SectionNote({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: const Color(0xFFF0F2F8),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: const Color(0xFF72778C)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Color(0xFF6D7285),
              fontSize: 10,
              height: 1.5,
            ),
          ),
        ),
      ],
    ),
  );
}

class _TrustNudge extends StatelessWidget {
  const _TrustNudge({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFFEFEEFF),
    borderRadius: BorderRadius.circular(14),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          children: [
            const Icon(
              Icons.verified_user_outlined,
              color: _brandTeal,
              size: 20,
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Trust comes from clear evidence. Learn what profile signals mean and what they don’t prove.',
                style: TextStyle(
                  color: Color(0xFF4D4A86),
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ),
            const Icon(
              Icons.arrow_forward_rounded,
              color: _brandTeal,
              size: 18,
            ),
          ],
        ),
      ),
    ),
  );
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Row(
      children: [
        SizedBox(
          width: 125,
          child: Text(
            label,
            style: const TextStyle(color: _muted, fontSize: 11),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: _ink,
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
        ),
      ],
    ),
  );
}

class _CreateProjectDialog extends StatefulWidget {
  const _CreateProjectDialog();
  @override
  State<_CreateProjectDialog> createState() => _CreateProjectDialogState();
}

class _CreateProjectDialogState extends State<_CreateProjectDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _summaryController = TextEditingController();
  final _goalController = TextEditingController(text: '8');
  String _category = 'Software prototype';
  @override
  void dispose() {
    _nameController.dispose();
    _summaryController.dispose();
    _goalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Create a project'),
    content: SizedBox(
      width: 450,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Project name',
                  hintText: 'e.g. Campus wayfinding app',
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter a project name'
                    : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(labelText: 'Project type'),
                items:
                    const [
                          'Software prototype',
                          'Mobile application',
                          'Web platform',
                          'Game or interactive media',
                          'Research study',
                          'Learning tool',
                          'Other',
                        ]
                        .map(
                          (item) =>
                              DropdownMenuItem(value: item, child: Text(item)),
                        )
                        .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _category = value);
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _summaryController,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'What should evaluators know?',
                  hintText: 'Describe what it does and what feedback you need',
                ),
                validator: (value) => value == null || value.trim().length < 12
                    ? 'Add a short description (at least 12 characters)'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _goalController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Target number of responses',
                ),
                validator: (value) {
                  final number = int.tryParse(value ?? '');
                  return number == null || number < 1 || number > 1000
                      ? 'Choose a number from 1 to 1,000'
                      : null;
                },
              ),
              const SizedBox(height: 8),
              const _SectionNote(
                icon: Icons.storage_outlined,
                text:
                    'This creates a private record in local browser storage. It will not be visible to other people.',
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _create, child: const Text('Create project')),
    ],
  );
  void _create() {
    if (!_formKey.currentState!.validate()) return;
    final now = DateTime.now().microsecondsSinceEpoch;
    final project = EvaluationProject(
      id: 'project-$now',
      name: _nameController.text.trim(),
      category: _category,
      summary: _summaryController.text.trim(),
      status: ProjectStatus.prototype,
      updatedLabel: 'Created just now',
      responses: 0,
      responseGoal: int.parse(_goalController.text),
      iconCodePoint: Icons.lightbulb_outline_rounded.codePoint,
      accentValue: 0xFF0F766E,
    );
    Navigator.pop(context, project);
  }
}

class _EvaluatorsView extends StatefulWidget {
  const _EvaluatorsView({
    required this.wide,
    required this.projects,
    required this.invitations,
    required this.onInvite,
  });
  final bool wide;
  final List<EvaluationProject> projects;
  final List<LocalInvitation> invitations;
  final Future<void> Function(
    EvaluatorProfile evaluator,
    EvaluationProject project,
  )
  onInvite;
  @override
  State<_EvaluatorsView> createState() => _EvaluatorsViewState();
}

class _EvaluatorsViewState extends State<_EvaluatorsView> {
  final _searchController = TextEditingController();
  String _specialty = 'All specialties';
  String _query = '';
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final specialties = {
      'All specialties',
      ...sampleEvaluators.expand((e) => e.specialties),
    }.toList();
    final filtered = sampleEvaluators.where((evaluator) {
      final matchesQuery =
          _query.isEmpty ||
          '${evaluator.name} ${evaluator.role} ${evaluator.specialties.join(' ')}'
              .toLowerCase()
              .contains(_query.toLowerCase());
      return matchesQuery &&
          (_specialty == 'All specialties' ||
              evaluator.specialties.contains(_specialty));
    }).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _pageHeading(context),
        const _LocalDemoBanner(),
        const SizedBox(height: 20),
        _Panel(
          title: 'Evaluator directory',
          subtitle:
              'Sample profiles to demonstrate how evidence can be displayed',
          child: Column(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final search = TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: 'Search skills or roles',
                    ),
                  );
                  final filter = DropdownButtonFormField<String>(
                    initialValue: _specialty,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.tune_rounded),
                      labelText: 'Filter specialty',
                    ),
                    items: specialties
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) setState(() => _specialty = value);
                    },
                  );
                  if (constraints.maxWidth < 540) {
                    return Column(
                      children: [search, const SizedBox(height: 10), filter],
                    );
                  }
                  return Row(
                    children: [
                      SizedBox(width: 330, child: search),
                      const SizedBox(width: 12),
                      Expanded(child: filter),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              if (filtered.isEmpty)
                const _EmptyState(
                  icon: Icons.person_search_outlined,
                  title: 'No matching profiles',
                  body: 'Try another name, role, or specialty.',
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 760 ? 2 : 1;
                    final width = columns == 1
                        ? constraints.maxWidth
                        : (constraints.maxWidth - 14) / 2;
                    return Wrap(
                      spacing: 14,
                      runSpacing: 14,
                      children: filtered
                          .map(
                            (evaluator) => SizedBox(
                              width: width,
                              child: _EvaluatorCard(
                                evaluator: evaluator,
                                onInvite: () =>
                                    _chooseProject(context, evaluator),
                              ),
                            ),
                          )
                          .toList(),
                    );
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        if (widget.invitations.isNotEmpty)
          _Panel(
            title: 'Local invitation drafts',
            subtitle: 'These have not been sent to anyone',
            child: Column(
              children: widget.invitations
                  .map(
                    (invitation) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.mail_outline_rounded,
                            color: _brandTeal,
                            size: 17,
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              '${invitation.evaluatorName} · ${invitation.projectName}',
                              style: const TextStyle(fontSize: 11, color: _ink),
                            ),
                          ),
                          Text(
                            invitation.status,
                            style: const TextStyle(fontSize: 9, color: _muted),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        const SizedBox(height: 18),
        const _SectionNote(
          icon: Icons.fact_check_outlined,
          text:
              'Profile signals shown here are fictional sample data. A production directory should show what was checked, by whom, when, and for which scope. Self-reported credentials must be labeled clearly.',
        ),
      ],
    );
  }

  Widget _pageHeading(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'DISCOVERY',
          style: TextStyle(
            color: _brandTeal,
            fontSize: 11,
            letterSpacing: 1.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Find evaluators',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'Find relevant perspectives for your project and invite reviewers.',
          style: TextStyle(color: _muted, fontSize: 14),
        ),
      ],
    ),
  );

  Future<void> _chooseProject(
    BuildContext context,
    EvaluatorProfile evaluator,
  ) async {
    if (widget.projects.isEmpty) {
      AppNotice.show(context, 'Create a project first to send an invitation.');
      return;
    }
    final project = await showDialog<EvaluationProject>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Invite ${evaluator.name}'),
        children: widget.projects
            .map(
              (project) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, project),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Text(project.name),
                ),
              ),
            )
            .toList(),
      ),
    );
    if (project != null) await widget.onInvite(evaluator, project);
  }
}

class _EvaluatorCard extends StatelessWidget {
  const _EvaluatorCard({required this.evaluator, required this.onInvite});
  final EvaluatorProfile evaluator;
  final VoidCallback onInvite;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFBFD),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 21,
                backgroundColor: Color(
                  evaluator.accentValue,
                ).withValues(alpha: .13),
                child: Text(
                  evaluator.initials,
                  style: TextStyle(
                    color: Color(evaluator.accentValue),
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      evaluator.name,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      evaluator.role,
                      style: const TextStyle(color: _muted, fontSize: 10),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Profile signals are illustrative',
                onPressed: () => _showDemoInfo(context),
                icon: const Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: _muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            evaluator.location,
            style: const TextStyle(color: Color(0xFF878B9A), fontSize: 9),
          ),
          const SizedBox(height: 11),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: evaluator.specialties
                .map(
                  (tag) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F1F6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      tag,
                      style: const TextStyle(
                        color: Color(0xFF62677B),
                        fontSize: 9,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 11),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: evaluator.signals
                .map(
                  (signal) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF6E7),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          size: 11,
                          color: Color(0xFFAA7620),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          signal,
                          style: const TextStyle(
                            color: Color(0xFF87652F),
                            fontSize: 8,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              const Icon(Icons.rate_review_outlined, size: 14, color: _muted),
              const SizedBox(width: 5),
              Text(
                '${evaluator.completedReviews} sample reviews',
                style: const TextStyle(color: _muted, fontSize: 9),
              ),
              const Spacer(),
              FilledButton.tonal(
                onPressed: onInvite,
                child: const Text('Invite'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrustView extends StatelessWidget {
  const _TrustView({required this.wide, required this.onReset});
  final bool wide;
  final VoidCallback onReset;
  @override
  Widget build(BuildContext context) {
    final signals = [
      _TrustSignal(
        Icons.alternate_email_rounded,
        'Email confirmed',
        'Confirms access to an email address. It does not confirm a legal identity, workplace, or professional skill.',
        'Account signal',
      ),
      _TrustSignal(
        Icons.badge_outlined,
        'Identity checked',
        'A provider compared a person to identity evidence. Store only the result, method, scope, and date that the user needs to see.',
        'Identity signal',
      ),
      _TrustSignal(
        Icons.school_outlined,
        'Affiliation or credential',
        'A school, employer, license issuer, or credential body was checked. Show the issuer and verification date.',
        'Credential signal',
      ),
      _TrustSignal(
        Icons.work_outline_rounded,
        'Relevant work reviewed',
        'Evidence of relevant work was reviewed against a stated specialty. It does not certify all claims or guarantee review quality.',
        'Experience signal',
      ),
      _TrustSignal(
        Icons.history_rounded,
        'Review history',
        'Completed reviews and reliability indicators come from platform activity. They should be scoped, explainable, and appealable.',
        'Behavior signal',
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'TRUST & SAFETY',
                style: TextStyle(
                  color: _brandTeal,
                  fontSize: 11,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Trust should be specific.',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Show people what was checked, what it means, and what remains unknown.',
                style: TextStyle(color: _muted, fontSize: 14),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFFEFEEFF),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: const Color(0xFFE1DFFF)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(Icons.shield_outlined, color: _brandTeal),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Trust profile for this prototype',
                      style: TextStyle(
                        color: _ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'No accounts or verification checks are active. The people, badges, locations, and activity shown elsewhere are fictional examples. This prototype cannot establish whether a person is real.',
                      style: TextStyle(
                        color: Color(0xFF65618F),
                        fontSize: 11,
                        height: 1.55,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _Panel(
          title: 'Profile signals and their limits',
          subtitle:
              'A reliable system uses multiple narrow, explainable signals instead of one universal trust score.',
          child: Column(
            children: signals
                .map((signal) => _TrustSignalTile(signal: signal))
                .toList(),
          ),
        ),
        const SizedBox(height: 18),
        _Panel(
          title: 'Safety foundations for a real service',
          subtitle:
              'Needed before public accounts, sensitive files, or cross-border use',
          child: Column(
            children: [
              _ChecklistRow(
                icon: Icons.security_rounded,
                title: 'Account security',
                body:
                    'Verified email, secure session handling, optional MFA, rate limits, and account recovery controls.',
              ),
              _ChecklistRow(
                icon: Icons.lock_outline_rounded,
                title: 'Project access and privacy',
                body:
                    'Private by default, explicit sharing, revocable evaluator access, retention controls, and deletion/export paths.',
              ),
              _ChecklistRow(
                icon: Icons.fact_check_outlined,
                title: 'Moderation and recourse',
                body:
                    'Report, block, appeal, conflict disclosure, rubric guidance, and an audit trail for consequential actions.',
              ),
              _ChecklistRow(
                icon: Icons.public_rounded,
                title: 'Global readiness',
                body:
                    'Minimize collected identity data, document processors and regions, support accessibility, and review local privacy requirements before launch.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _SectionNote(
          icon: Icons.warning_amber_rounded,
          text:
              'Do not upload private, regulated, or confidential material to this prototype. Browser storage is not an access-controlled or encrypted server service.',
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: onReset,
            icon: const Icon(Icons.restart_alt_rounded),
            label: const Text('Reset local workspace'),
          ),
        ),
      ],
    );
  }
}

class _TrustSignal {
  const _TrustSignal(this.icon, this.title, this.body, this.label);
  final IconData icon;
  final String title;
  final String body;
  final String label;
}

class _TrustSignalTile extends StatelessWidget {
  const _TrustSignalTile({required this.signal});
  final _TrustSignal signal;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 13),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: const Color(0xFFD9F3EE),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(signal.icon, size: 17, color: _brandTeal),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      signal.title,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    signal.label,
                    style: const TextStyle(
                      color: _brandTeal,
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                signal.body,
                style: const TextStyle(
                  color: _muted,
                  fontSize: 10,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title;
  final String body;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: _brandTeal, size: 18),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                body,
                style: const TextStyle(
                  color: _muted,
                  fontSize: 10,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ReviewResult {
  const _ReviewResult(this.rating, this.comment);
  final int rating;
  final String comment;
}

class _ReviewDialog extends StatefulWidget {
  const _ReviewDialog({required this.task});
  final ReviewTask task;
  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  final _commentController = TextEditingController();
  int _rating = 0;
  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.task.title),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.task.projectName} · ${widget.task.kind}',
              style: const TextStyle(color: _muted, fontSize: 11),
            ),
            const SizedBox(height: 15),
            const Text(
              'Overall usefulness',
              style: TextStyle(
                color: _ink,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: List.generate(
                5,
                (index) => IconButton(
                  onPressed: () => setState(() => _rating = index + 1),
                  icon: Icon(
                    index < _rating
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: const Color(0xFFE5A642),
                    size: 25,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 7),
            TextField(
              controller: _commentController,
              autofocus: true,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'What did you learn?',
                hintText: 'Share specific, constructive feedback',
              ),
            ),
            const SizedBox(height: 12),
            const _SectionNote(
              icon: Icons.storage_outlined,
              text:
                  'Submitting saves a sample response in this browser. It does not contact the listed reviewer or project owner.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save feedback')),
      ],
    );
  }

  void _submit() {
    if (_rating == 0) {
      AppNotice.show(
        context,
        'Choose a rating before saving.',
        tone: NoticeTone.error,
      );
      return;
    }
    if (_commentController.text.trim().length < 8) {
      AppNotice.show(
        context,
        'Add a little more detail to your feedback.',
        tone: NoticeTone.error,
      );
      return;
    }
    Navigator.pop(
      context,
      _ReviewResult(_rating, _commentController.text.trim()),
    );
  }
}

void _showDemoInfo(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Prototype information'),
      content: const Text(
        'Evalink is currently a local web prototype. Sample people, credentials, review counts, and tasks are fictional. There is no account service, identity verification, messaging, or shared server storage yet. Changes are stored in this browser only.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Got it'),
        ),
      ],
    ),
  );
}
