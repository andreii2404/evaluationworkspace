import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import '../services/cloud_repository.dart';
import '../widgets/cantiere_wordmark.dart';
import '../widgets/liquid_glass.dart';
import 'workspace_forms.dart';

const _chromeTint = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xE6262C36), Color(0xEC191B1F)],
);

enum _ReviewFilter {
  all('All reviews'),
  awaiting('Awaiting feedback'),
  received('Feedback received'),
  assigned('Reviews to do');

  const _ReviewFilter(this.label);
  final String label;
}

enum _Area {
  overview('Overview', Icons.grid_view_rounded),
  projects('Projects', Icons.layers_outlined),
  directory('Evaluators', Icons.group_outlined),
  reviews('Reviews', Icons.rate_review_outlined),
  profile('Profile', Icons.person_outline_rounded),
  moderation('Moderation', Icons.shield_outlined);

  const _Area(this.title, this.icon);
  final String title;
  final IconData icon;
}

class CloudWorkspace extends StatelessWidget {
  const CloudWorkspace({super.key, required this.client, required this.userId});
  final SupabaseClient client;
  final String userId;

  @override
  Widget build(BuildContext context) => Theme(
    data: workshopTheme(Theme.of(context)),
    child: _Workspace(client: client, userId: userId),
  );
}

class _Workspace extends StatefulWidget {
  const _Workspace({required this.client, required this.userId});
  final SupabaseClient client;
  final String userId;

  @override
  State<_Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<_Workspace> {
  late final _repo = CloudRepository(widget.client, widget.userId);
  late Future<WorkspaceData> _data = _repo.load();
  RealtimeChannel? _updates;
  _Area _area = _Area.overview;
  bool _busy = false;
  bool _community = false;
  String _query = '';
  String? _evaluatorType;
  String? _briefProjectId;
  _ReviewFilter _reviewFilter = _ReviewFilter.all;

  @override
  void initState() {
    super.initState();
    _updates = widget.client
        .channel('evalink-reviews-${widget.userId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'review_assignments',
          callback: (_) => _refresh(),
        )
        .subscribe();
  }

  @override
  void dispose() {
    final channel = _updates;
    if (channel != null) widget.client.removeChannel(channel);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() => _data = _repo.load());
  }

  void _notice(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _change(Future<void> Function() action, String done) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      _refresh();
      _notice(done);
    } catch (error) {
      if (mounted) _notice(workspaceError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _select(_Area area, {_ReviewFilter reviews = _ReviewFilter.all}) =>
      setState(() {
        _area = area;
        _reviewFilter = reviews;
        _query = '';
      });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 960;
      final nav = _navigation(drawer: !wide);
      return Scaffold(
        backgroundColor: workshopNight,
        drawer: wide
            ? null
            : Drawer(
                backgroundColor: workshopSurface,
                surfaceTintColor: Colors.transparent,
                child: SafeArea(child: nav),
              ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            const _WorkspaceBackdrop(),
            SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1400),
                  child: Padding(
                    padding: EdgeInsets.all(wide ? 24 : 12),
                    child: Column(
                      children: [
                        _toolbar(wide),
                        SizedBox(height: wide ? 16 : 10),
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (wide) ...[
                                SizedBox(
                                  width: 196,
                                  child: GlassSurface(
                                    blur: 8,
                                    radius: 17,
                                    rim: workshopEdge,
                                    tint: _chromeTint,
                                    child: nav,
                                  ),
                                ),
                                const SizedBox(width: 24),
                              ],
                              Expanded(child: _content(wide)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );

  Widget _toolbar(bool wide) => GlassSurface(
    blur: 8,
    radius: 17,
    rim: workshopEdge,
    tint: _chromeTint,
    child: Padding(
      padding: EdgeInsets.fromLTRB(wide ? 18 : 5, 7, 8, 7),
      child: Row(
        children: [
          if (!wide)
            Builder(
              builder: (context) => IconButton(
                tooltip: 'Open workspace menu',
                icon: const Icon(Icons.menu_rounded),
                onPressed: Scaffold.of(context).openDrawer,
              ),
            ),
          const Expanded(child: CantiereWordmark(fontSize: 24)),
          if (wide) ...[
            const Text(
              'Personal workspace',
              style: TextStyle(color: workshopMuted),
            ),
            const SizedBox(width: 16),
          ],
          IconButton(
            tooltip: 'Refresh workspace',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded, size: 20),
          ),
          IconButton(
            tooltip: 'Open profile',
            isSelected: _area == _Area.profile,
            onPressed: () => _select(_Area.profile),
            icon: const Icon(Icons.account_circle_outlined, size: 23),
            selectedIcon: const Icon(Icons.account_circle, size: 23),
          ),
        ],
      ),
    ),
  );

  Widget _navigation({required bool drawer}) {
    final areas = _Area.values.where(
      (area) => area != _Area.moderation || _repo.isModerator,
    );
    return Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 20, 12, 12),
            child: _Kicker('WORKSPACE'),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (final area in areas)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: ListTile(
                      selected: _area == area,
                      selectedTileColor: const Color(0x24FFFFFF),
                      selectedColor: workshopText,
                      iconColor: workshopMuted,
                      textColor: workshopMuted,
                      hoverColor: const Color(0x16FFFFFF),
                      focusColor: const Color(0x27FFFFFF),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 11,
                      ),
                      minLeadingWidth: 18,
                      horizontalTitleGap: 11,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      leading: Icon(area.icon, size: 19),
                      title: Text(area.title),
                      onTap: () {
                        if (drawer) Navigator.pop(context);
                        _select(area);
                      },
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, indent: 14, endIndent: 14),
          Padding(
            padding: const EdgeInsets.all(8),
            child: ListTile(
              leading: const Icon(Icons.logout, size: 19),
              title: const Text('Sign out'),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              onTap: _busy
                  ? null
                  : () async {
                      try {
                        await widget.client.auth.signOut();
                      } catch (error) {
                        if (mounted) _notice(workspaceError(error));
                      }
                    },
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(bool wide) => FutureBuilder<WorkspaceData>(
    future: _data,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _Blank(
          icon: Icons.cloud_off_outlined,
          title: 'Couldn’t load your workspace',
          action: TextButton(
            onPressed: _refresh,
            child: const Text('Try again'),
          ),
        );
      }
      final data = snapshot.data;
      if (data == null) {
        return const Center(child: CircularProgressIndicator());
      }
      final reduceMotion = MediaQuery.disableAnimationsOf(context);
      return Column(
        children: [
          if (_busy || snapshot.connectionState == ConnectionState.waiting)
            const LinearProgressIndicator(minHeight: 2)
          else
            const SizedBox(height: 2),
          Expanded(
            child: SingleChildScrollView(
              key: PageStorageKey(_area),
              padding: EdgeInsets.fromLTRB(wide ? 2 : 0, wide ? 8 : 4, 2, 20),
              child: TweenAnimationBuilder<double>(
                key: ValueKey(_area),
                tween: Tween(begin: 0, end: 1),
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 420),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) => value == 1
                    ? child!
                    : Opacity(
                        opacity: .6 + .4 * value,
                        child: Transform.translate(
                          offset: Offset(0, 12 * (1 - value)),
                          child: child,
                        ),
                      ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_area != _Area.overview) ...[
                          Semantics(
                            header: true,
                            child: Text(
                              _area.title,
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        switch (_area) {
                          _Area.overview => _overview(data),
                          _Area.projects => _projects(data),
                          _Area.directory => _directory(data),
                          _Area.reviews => _reviews(data),
                          _Area.profile => _profile(data),
                          _Area.moderation => _moderation(data),
                        },
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );

  void _showMyProjects() {
    _community = false;
    _select(_Area.projects);
  }

  bool _isOpenReview(WorkspaceRow row) =>
      row['status'] == 'invited' || row['status'] == 'accepted';

  Widget _overview(WorkspaceData data) {
    final requests = data.assignments.where(
      (row) => row['creator_id'] == widget.userId,
    );
    final awaiting = requests.where(_isOpenReview);
    final received = requests.where((row) => row['status'] == 'submitted');
    final assigned = data.assignments.where(
      (row) => row['evaluator_id'] == widget.userId && _isOpenReview(row),
    );
    final name = (data.profile['display_name'] as String?)?.trim() ?? '';
    final welcome = name.isEmpty ? 'Your workspace' : 'Welcome, $name.';
    final metrics = [
      _Metric(
        'My projects',
        data.projects.length,
        Icons.layers_outlined,
        _showMyProjects,
      ),
      _Metric(
        'Awaiting feedback',
        awaiting.length,
        Icons.schedule,
        () => _select(_Area.reviews, reviews: _ReviewFilter.awaiting),
      ),
      _Metric(
        'Feedback received',
        received.length,
        Icons.rate_review_outlined,
        () => _select(_Area.reviews, reviews: _ReviewFilter.received),
      ),
      _Metric(
        'Reviews to do',
        assigned.length,
        Icons.task_alt_outlined,
        () => _select(_Area.reviews, reviews: _ReviewFilter.assigned),
      ),
    ];
    final activity = [
      ?assigned.firstOrNull,
      ?received.firstOrNull,
      ?awaiting.firstOrNull,
    ];
    final projectsPanel = _overviewPanel(
      'Recent projects',
      action: data.projects.isEmpty
          ? null
          : TextButton(
              onPressed: _showMyProjects,
              child: const Text('View all projects'),
            ),
      children: [
        if (data.projects.isEmpty)
          _overviewNote('Add a project to start requesting feedback.')
        else
          for (final project in data.projects.take(3))
            _projectOverviewRow(project, requests),
      ],
    );
    final activityPanel = _overviewPanel(
      'Review activity',
      action: activity.isEmpty
          ? null
          : TextButton(
              onPressed: () => _select(_Area.reviews),
              child: const Text('All reviews'),
            ),
      children: [
        if (activity.isEmpty)
          _overviewNote(
            'Review requests, invitations, and feedback will appear here.',
          )
        else
          for (final assignment in activity)
            _activityOverviewRow(assignment, data),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 20,
          runSpacing: 12,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _Kicker('OVERVIEW'),
                const SizedBox(height: 6),
                Semantics(
                  header: true,
                  child: Text(
                    welcome,
                    style: const TextStyle(
                      fontFamily: 'Instrument Serif',
                      color: workshopText,
                      fontSize: 30,
                      height: 1.04,
                      letterSpacing: .12,
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Track your projects, feedback, and reviews you’re invited to.',
                  style: TextStyle(color: workshopMuted),
                ),
              ],
            ),
            FilledButton.icon(
              onPressed: _busy ? null : _createProject,
              style: FilledButton.styleFrom(
                backgroundColor: workshopBlue,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New project'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, bounds) {
            final columns = bounds.maxWidth >= 760 ? 4 : 2;
            const gap = 10.0;
            final width = (bounds.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: 2,
              children: [
                for (final metric in metrics)
                  SizedBox(width: width, child: metric),
              ],
            );
          },
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, bounds) => bounds.maxWidth >= 730
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: projectsPanel),
                    const SizedBox(width: 14),
                    Expanded(child: activityPanel),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [projectsPanel, activityPanel],
                ),
        ),
        if (data.projects.isNotEmpty) ...[
          const SizedBox(height: 6),
          _reviewKit(data.projects),
        ],
      ],
    );
  }

  Widget _reviewKit(List<WorkspaceRow> projects) {
    final project =
        projects.where((row) => row['id'] == _briefProjectId).firstOrNull ??
        projects.first;
    final link = (project['artifact_url'] as String?)?.trim();
    final hasLink = link != null && link.isNotEmpty;
    final hasChecklist = (project['rubric_id'] as String?)?.isNotEmpty == true;
    final private = project['visibility'] == 'private';
    final picker = InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Project for review kit',
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: project['id'] as String,
          isExpanded: true,
          menuMaxHeight: 360,
          items: [
            for (final row in projects)
              DropdownMenuItem(
                value: row['id'] as String,
                child: Text(
                  row['title'] as String,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (id) => setState(() => _briefProjectId = id),
        ),
      ),
    );
    return GlassSurface(
      radius: 15,
      blur: 0,
      rim: const Color(0x50A3C9F3),
      tint: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF1E2B3A), Color(0xFF1B1D21), Color(0xFF1B1D21)],
      ),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: LayoutBuilder(
          builder: (context, bounds) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 16,
                runSpacing: 12,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _Kicker('FIELD TOOLS'),
                      const SizedBox(height: 4),
                      Semantics(
                        header: true,
                        child: const Text(
                          'Review kit',
                          style: TextStyle(
                            fontFamily: 'Instrument Serif',
                            fontSize: 23,
                            height: 1.1,
                            color: workshopText,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Copy your brief, project link, and feedback prompts.',
                        style: TextStyle(fontSize: 11, color: workshopMuted),
                      ),
                    ],
                  ),
                  SizedBox(
                    width: bounds.maxWidth >= 645 ? 250 : bounds.maxWidth,
                    child: picker,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 6,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _KitTag(
                        private ? Icons.lock_outline : Icons.group_outlined,
                        private ? 'Private' : 'Community',
                      ),
                      _KitTag(
                        hasLink ? Icons.link : Icons.info_outline,
                        hasLink ? 'Link attached' : 'Link missing',
                        attention: !hasLink,
                      ),
                      _KitTag(
                        hasChecklist ? Icons.checklist : Icons.info_outline,
                        hasChecklist
                            ? 'Checklist selected'
                            : 'Checklist missing',
                        attention: !hasChecklist,
                      ),
                    ],
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _copyReviewBrief(project, link),
                    icon: const Icon(Icons.copy_outlined, size: 15),
                    label: const Text('Copy review brief'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _copyReviewBrief(WorkspaceRow project, String? link) async {
    final text = [
      project['title'] as String,
      '',
      project['summary'] as String,
      if (link != null && link.isNotEmpty) ...['', 'Project link: $link'],
      '',
      'Please try the project and share your feedback.',
      '• What worked well?',
      '• Where did you get stuck?',
      '• What would you change first?',
    ].join('\n');
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) _notice('Review brief copied');
    } on PlatformException {
      if (mounted) _notice('Couldn’t copy the review brief');
    }
  }

  Widget _overviewPanel(
    String title, {
    Widget? action,
    required List<Widget> children,
  }) => _Surface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(15, 6, 7, 6),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              if (action != null) action else const SizedBox(height: 40),
            ],
          ),
        ),
        for (final row in children) ...[
          const Divider(height: 1, indent: 15, endIndent: 15),
          row,
        ],
      ],
    ),
  );

  Widget _overviewNote(String message) => Padding(
    padding: const EdgeInsets.fromLTRB(15, 13, 15, 16),
    child: Text(message, style: const TextStyle(color: workshopMuted)),
  );

  Widget _projectOverviewRow(
    WorkspaceRow project,
    Iterable<WorkspaceRow> requests,
  ) {
    final related = requests.where((row) => row['project_id'] == project['id']);
    final open = related.where(_isOpenReview).length;
    final finished = related
        .where((row) => row['status'] == 'submitted')
        .length;
    return ListTile(
      leading: Icon(
        project['visibility'] == 'private'
            ? Icons.lock_outline
            : Icons.layers_outlined,
        size: 19,
      ),
      title: Text(project['title'] as String),
      titleTextStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: workshopText,
      ),
      subtitleTextStyle: const TextStyle(fontSize: 11, color: workshopMuted),
      subtitle: Text(
        [
          project['category'],
          if (open > 0) '$open pending',
          if (finished > 0) '$finished completed',
          if (open == 0 && finished == 0) 'No active reviews',
        ].join(' · '),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, size: 18),
      onTap: () => _showProject(project, owned: true),
    );
  }

  Widget _activityOverviewRow(WorkspaceRow row, WorkspaceData data) {
    final incoming = row['evaluator_id'] == widget.userId;
    final project = row['projects'] as WorkspaceRow?;
    final (label, icon, tone) = switch ((incoming, row['status'])) {
      (true, 'invited') => (
        'Invitation to review',
        Icons.mark_email_unread_outlined,
        const Color(0xFFFFD99D),
      ),
      (true, _) => (
        'Ready for your review',
        Icons.task_alt_outlined,
        workshopIce,
      ),
      (_, 'submitted') => (
        'Feedback received',
        Icons.check_circle_outline,
        const Color(0xFFB6F3D8),
      ),
      (_, 'accepted') => ('In review', Icons.rate_review_outlined, workshopIce),
      _ => ('Awaiting a reply', Icons.schedule, const Color(0xFFFFD99D)),
    };
    final reviewer =
        (row['evaluator'] as WorkspaceRow?)?['display_name'] as String?;
    final review = !incoming && row['status'] == 'submitted'
        ? data.reviewFor(row['id'] as String)
        : null;
    return ListTile(
      leading: Icon(icon, color: tone, size: 19),
      title: Text(project?['title'] as String? ?? 'Project'),
      titleTextStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: workshopText,
      ),
      subtitleTextStyle: const TextStyle(fontSize: 11, color: workshopMuted),
      subtitle: Text(
        !incoming && reviewer != null ? '$label · $reviewer' : label,
      ),
      trailing: const Icon(Icons.chevron_right_rounded, size: 18),
      onTap: review != null && project != null
          ? () => _readReview(review, project)
          : () => _select(
              _Area.reviews,
              reviews: incoming
                  ? _ReviewFilter.assigned
                  : row['status'] == 'submitted'
                  ? _ReviewFilter.received
                  : _ReviewFilter.awaiting,
            ),
    );
  }

  Widget _projects(WorkspaceData data) {
    final items = _community ? data.community : data.projects;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ChoiceChip(
              label: const Text('My projects'),
              selected: !_community,
              onSelected: (_) => setState(() => _community = false),
            ),
            ChoiceChip(
              label: const Text('Community'),
              selected: _community,
              onSelected: (_) => setState(() => _community = true),
            ),
            FilledButton.icon(
              onPressed: _busy ? null : _createProject,
              icon: const Icon(Icons.add),
              label: const Text('New project'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (items.isEmpty)
          _Blank(
            icon: Icons.layers_outlined,
            title: _community ? 'No community projects yet' : 'No projects yet',
          )
        else
          for (final project in items)
            _projectTile(project, owned: !_community),
      ],
    );
  }

  Widget _projectTile(WorkspaceRow project, {required bool owned}) => _Surface(
    child: ListTile(
      leading: Icon(
        owned && project['visibility'] == 'private'
            ? Icons.lock_outline
            : Icons.layers_outlined,
      ),
      title: Text(project['title'] as String),
      subtitle: Text(
        '${project['category']} · ${project['visibility'] == 'private' ? 'Private' : 'Community'}',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showProject(project, owned: owned),
    ),
  );

  Future<void> _showProject(WorkspaceRow project, {required bool owned}) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(project['title'] as String),
        content: SizedBox(
          width: 470,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${project['category']} · ${project['visibility'] == 'private' ? 'Private' : 'Community'}',
                  style: const TextStyle(color: workshopMuted),
                ),
                const SizedBox(height: 12),
                SelectableText(project['summary'] as String),
                if (project['artifact_url'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: TextButton.icon(
                      onPressed: () =>
                          _openUrl(project['artifact_url'] as String),
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: const Text('Open project material'),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          if (owned) ...[
            TextButton(
              onPressed: _busy
                  ? null
                  : () => Navigator.pop(context, 'visibility'),
              child: Text(
                project['visibility'] == 'private'
                    ? 'Share with community'
                    : 'Make private',
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'directory'),
              child: const Text('Find evaluators'),
            ),
          ] else if (project['visibility'] == 'community')
            TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context, 'report'),
              child: const Text('Report'),
            ),
        ],
      ),
    );
    if (!mounted) return;
    final id = project['id'] as String;
    if (result == 'directory') _select(_Area.directory);
    if (result == 'visibility') {
      final share = project['visibility'] == 'private';
      if (share) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Share with the community?'),
            content: const Text(
              'Signed-in members will be able to see the brief and project link.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Share project'),
              ),
            ],
          ),
        );
        if (!mounted || confirmed != true) return;
      }
      await _change(() => _repo.setVisibility(id, share), 'Visibility updated');
    }
    if (mounted && result == 'report') {
      final values = await workspaceForm(
        context,
        title: 'Report project',
        action: 'Submit report',
        fields: const [
          FormFieldSpec('reason', 'Reason', required: true, max: 500, lines: 3),
        ],
      );
      if (mounted && values != null) {
        await _change(
          () => _repo.report(id, values['reason'] as String),
          'Report submitted',
        );
      }
    }
  }

  Future<void> _createProject() async {
    try {
      final rubrics = await _repo.rubrics();
      if (!mounted) return;
      final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            ProjectForm(rubrics: rubrics, save: _repo.createProject),
      );
      if (mounted && saved == true) {
        _refresh();
        _notice('Project created');
      }
    } catch (error) {
      if (mounted) _notice(workspaceError(error));
    }
  }

  Widget _directory(WorkspaceData data) {
    final people = data.directory.where((row) {
      if (_evaluatorType != null && row['evaluator_type'] != _evaluatorType) {
        return false;
      }
      final searchable =
          '${row['display_name']} ${row['expertise']} ${row['headline']}';
      return searchable.toLowerCase().contains(_query);
    }).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          decoration: const InputDecoration(
            labelText: 'Search by name or expertise',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (value) =>
              setState(() => _query = value.trim().toLowerCase()),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            ChoiceChip(
              label: const Text('All types'),
              selected: _evaluatorType == null,
              onSelected: (_) => setState(() => _evaluatorType = null),
            ),
            for (final type in evaluatorTypes.entries)
              ChoiceChip(
                label: Text(type.value),
                selected: _evaluatorType == type.key,
                onSelected: (_) => setState(() => _evaluatorType = type.key),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (people.isEmpty)
          const _Blank(
            icon: Icons.group_outlined,
            title: 'No evaluators found',
          ),
        for (final person in people)
          _Surface(
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFF2D3036),
                child: Icon(Icons.person_outline, color: workshopMuted),
              ),
              title: Text(person['display_name'] as String),
              subtitle: Text(
                [
                      evaluatorTypes[person['evaluator_type']],
                      person['headline'],
                      if (person['email_confirmed'] == true) 'Email confirmed',
                    ]
                    .whereType<String>()
                    .where((value) => value.isNotEmpty)
                    .join(' · '),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showEvaluator(person, data),
            ),
          ),
      ],
    );
  }

  Future<void> _showEvaluator(WorkspaceRow person, WorkspaceData data) async {
    final projects = data.projects
        .where(
          (project) => !data.assignments.any(
            (assignment) =>
                assignment['project_id'] == project['id'] &&
                assignment['evaluator_id'] == person['id'],
          ),
        )
        .toList();
    final projectId = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(person['display_name'] as String),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(evaluatorTypes[person['evaluator_type']] ?? 'Evaluator'),
                if (person['email_confirmed'] == true)
                  const Text(
                    'Email confirmed',
                    style: TextStyle(color: workshopIce),
                  ),
                const SizedBox(height: 12),
                const Text(
                  'Self-reported expertise',
                  style: TextStyle(color: workshopMuted),
                ),
                const SizedBox(height: 8),
                Text(
                  (person['expertise'] as String).isEmpty
                      ? 'No expertise listed'
                      : person['expertise'] as String,
                ),
                if (person['portfolio_url'] != null)
                  TextButton.icon(
                    onPressed: () =>
                        _openUrl(person['portfolio_url'] as String),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('Portfolio'),
                  ),
                const SizedBox(height: 16),
                Text(
                  projects.isEmpty
                      ? 'No projects available to invite for.'
                      : 'Invite to review a project',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                for (final project in projects)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(project['title'] as String),
                    trailing: const Icon(Icons.arrow_outward, size: 18),
                    onTap: _busy
                        ? null
                        : () => Navigator.pop(context, project['id']),
                  ),
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
    if (!mounted || projectId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send review invitation?'),
        content: Text(
          '${person['display_name']} will be able to see the project brief and link.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send invitation'),
          ),
        ],
      ),
    );
    if (mounted && confirmed == true) {
      await _change(
        () => _repo.invite(projectId, person['id'] as String),
        'Invitation sent',
      );
    }
  }

  Widget _reviews(WorkspaceData data) {
    final all = _reviewFilter == _ReviewFilter.all;
    final assigned = _reviewFilter == _ReviewFilter.assigned;
    final incoming = data.assignments.where(
      (item) =>
          item['evaluator_id'] == widget.userId && (all || _isOpenReview(item)),
    );
    final outgoing = data.assignments.where(
      (item) =>
          item['creator_id'] == widget.userId &&
          switch (_reviewFilter) {
            _ReviewFilter.awaiting => _isOpenReview(item),
            _ReviewFilter.received => item['status'] == 'submitted',
            _ => true,
          },
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 7,
          runSpacing: 4,
          children: [
            for (final filter in _ReviewFilter.values)
              ChoiceChip(
                label: Text(filter.label),
                selected: filter == _reviewFilter,
                onSelected: (_) => setState(() => _reviewFilter = filter),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (!assigned) ...[
          _heading('Requested by me'),
          if (outgoing.isEmpty)
            _Blank(
              icon: Icons.send_outlined,
              title: switch (_reviewFilter) {
                _ReviewFilter.awaiting => 'No reviews awaiting feedback',
                _ReviewFilter.received => 'No feedback received yet',
                _ => 'No invitations sent',
              },
            ),
          for (final item in outgoing) _assignment(item, data, incoming: false),
        ],
        if (all) const SizedBox(height: 25),
        if (all || assigned) ...[
          _heading('Assigned to me'),
          if (incoming.isEmpty)
            _Blank(
              icon: Icons.inbox_outlined,
              title: assigned ? 'You’re caught up' : 'No assignments yet',
            ),
          for (final item in incoming) _assignment(item, data, incoming: true),
        ],
      ],
    );
  }

  Widget _assignment(
    WorkspaceRow assignment,
    WorkspaceData data, {
    required bool incoming,
  }) {
    final status = assignment['status'] as String;
    final project = assignment['projects'] as WorkspaceRow?;
    final reviewer = assignment['evaluator'] as WorkspaceRow?;
    final id = assignment['id'] as String;
    final review = data.reviewFor(id);
    return _Surface(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  project?['title'] as String? ?? 'Project',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                _Status(status),
              ],
            ),
            if (!incoming && reviewer != null)
              Text(
                reviewer['display_name'] as String,
                style: const TextStyle(color: workshopMuted),
              ),
            if (project != null || review != null) const SizedBox(height: 8),
            Wrap(
              spacing: 9,
              runSpacing: 5,
              children: [
                if (project != null)
                  TextButton(
                    onPressed: () => _showProject(project, owned: !incoming),
                    child: const Text('Project brief'),
                  ),
                if (incoming && status == 'invited') ...[
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _change(
                            () => _repo.respond(id, true),
                            'Invitation accepted',
                          ),
                    child: const Text('Accept'),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _change(
                            () => _repo.respond(id, false),
                            'Invitation declined',
                          ),
                    child: const Text('Decline'),
                  ),
                ],
                if (incoming && status == 'accepted' && project != null)
                  FilledButton(
                    onPressed: _busy ? null : () => _writeReview(id, project),
                    child: const Text('Write review'),
                  ),
                if (review != null && project != null)
                  FilledButton.tonal(
                    onPressed: () => _readReview(review, project),
                    child: const Text('View feedback'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _writeReview(String assignmentId, WorkspaceRow project) async {
    try {
      final criteria = await _repo.criteria(project['rubric_id'] as String);
      if (!mounted) return;
      final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ReviewForm(
          criteria: criteria,
          projectTitle: project['title'] as String,
          save: (review) =>
              _repo.submitReview(assignmentId, review.scores, review.feedback),
        ),
      );
      if (mounted && saved == true) {
        _refresh();
        _notice('Review submitted');
      }
    } catch (error) {
      if (mounted) _notice(workspaceError(error));
    }
  }

  Future<void> _readReview(WorkspaceRow review, WorkspaceRow project) async {
    try {
      final criteria = await _repo.criteria(project['rubric_id'] as String);
      if (!mounted) return;
      final scores = review['scores'] as WorkspaceRow;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Evaluation feedback'),
          content: SizedBox(
            width: 470,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final criterion in criteria)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(criterion['label'] as String),
                      trailing: Text(
                        '${scores[criterion['criterion_key']]} / 5',
                      ),
                    ),
                  const Divider(),
                  SelectableText(review['feedback'] as String),
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
    } catch (error) {
      if (mounted) _notice(workspaceError(error));
    }
  }

  Widget _profile(WorkspaceData data) {
    final profile = data.profile;
    final emailConfirmed =
        widget.client.auth.currentUser?.emailConfirmedAt != null;
    return _Surface(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              profile['display_name'] as String,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            if ((profile['headline'] as String).isNotEmpty)
              Text(profile['headline'] as String),
            const SizedBox(height: 12),
            Text(
              emailConfirmed ? 'Email confirmed' : 'Email confirmation pending',
            ),
            Text(
              profile['directory_visible'] == true
                  ? 'Listed in evaluator directory'
                  : 'Hidden from evaluator directory',
            ),
            const SizedBox(height: 8),
            const Text(
              'Use the same account to create projects and accept review invitations. You can choose whether to appear in the evaluator directory.',
              style: TextStyle(color: workshopMuted),
            ),
            if ((profile['expertise'] as String).isNotEmpty)
              Text('Expertise · ${profile['expertise']}'),
            const SizedBox(height: 18),
            FilledButton.tonal(
              onPressed: _busy
                  ? null
                  : () async {
                      final values = await workspaceForm(
                        context,
                        title: 'Edit profile',
                        action: 'Save profile',
                        initial: profile,
                        directory: true,
                        fields: const [
                          FormFieldSpec(
                            'display_name',
                            'Display name',
                            required: true,
                            max: 80,
                          ),
                          FormFieldSpec('headline', 'Headline', max: 120),
                          FormFieldSpec(
                            'expertise',
                            'Expertise',
                            max: 240,
                            lines: 2,
                          ),
                          FormFieldSpec(
                            'portfolio_url',
                            'Portfolio link',
                            max: 500,
                            url: true,
                          ),
                        ],
                      );
                      if (mounted && values != null) {
                        await _change(
                          () => _repo.saveProfile(values),
                          'Profile updated',
                        );
                      }
                    },
              child: const Text('Edit profile'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _moderation(WorkspaceData data) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _heading('Open reports'),
      if (data.reports.isEmpty)
        const _Blank(icon: Icons.shield_outlined, title: 'No open reports'),
      for (final report in data.reports)
        _Surface(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(report['reason'] as String),
                const SizedBox(height: 8),
                Text(
                  (report['projects'] as WorkspaceRow?)?['title'] as String? ??
                      'Project ID · ${report['project_id']}',
                  style: const TextStyle(color: workshopMuted),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _change(
                              () => _repo.moderate(
                                report['id'] as String,
                                'dismissed',
                              ),
                              'Report dismissed',
                            ),
                      child: const Text('Dismiss'),
                    ),
                    FilledButton.tonal(
                      onPressed: _busy
                          ? null
                          : () => _change(
                              () => _repo.moderate(
                                report['id'] as String,
                                'resolved',
                              ),
                              'Report resolved',
                            ),
                      child: const Text('Resolve'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
    ],
  );

  Future<void> _openUrl(String value) async {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return;
    }
    try {
      if (await launchUrl(uri, webOnlyWindowName: '_blank')) return;
    } catch (_) {
      // Show the same message if the browser refuses to open the link.
    }
    if (mounted) _notice('Couldn’t open this link.');
  }

  Widget _heading(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Semantics(
      header: true,
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
    ),
  );
}

class _WorkspaceBackdrop extends StatelessWidget {
  const _WorkspaceBackdrop();

  @override
  Widget build(BuildContext context) => MediaQuery.highContrastOf(context)
      ? const ColoredBox(color: workshopNight)
      : const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(.35, -.95),
              radius: 1.3,
              colors: [Color(0xFF202630), workshopNight],
            ),
          ),
        );
}

class _Kicker extends StatelessWidget {
  const _Kicker(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.labelSmall?.copyWith(
      color: workshopMuted,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.5,
    ),
  );
}

class _Surface extends StatelessWidget {
  const _Surface({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: workshopSurface,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: MediaQuery.highContrastOf(context)
              ? workshopMuted
              : workshopEdge,
        ),
      ),
      child: child,
    ),
  );
}

class _Blank extends StatelessWidget {
  const _Blank({required this.icon, required this.title, this.action});
  final IconData icon;
  final String title;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(26),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: workshopIce, size: 28),
          const SizedBox(height: 9),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(color: workshopMuted),
          ),
          ?action,
        ],
      ),
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric(this.title, this.value, this.icon, this.onTap);
  final String title;
  final int value;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => _Surface(
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: workshopMuted),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(color: workshopMuted, fontSize: 11),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$value',
                    style: const TextStyle(
                      color: workshopText,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const Icon(
                  Icons.arrow_outward_rounded,
                  size: 14,
                  color: workshopMuted,
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _KitTag extends StatelessWidget {
  const _KitTag(this.icon, this.label, {this.attention = false});
  final IconData icon;
  final String label;
  final bool attention;

  @override
  Widget build(BuildContext context) {
    final color = attention ? const Color(0xFFFFD99D) : workshopIce;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: .20)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Flexible(
              child: Text(label, style: TextStyle(color: color, fontSize: 11)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status(this.state);
  final String state;

  @override
  Widget build(BuildContext context) {
    final (label, foreground, background) = switch (state) {
      'accepted' => ('Accepted', workshopIce, const Color(0x544991E1)),
      'submitted' => (
        'Submitted',
        const Color(0xFFB6F3D8),
        const Color(0x4842AE82),
      ),
      'declined' => (
        'Declined',
        const Color(0xFFFFC9CC),
        const Color(0x46D16D76),
      ),
      _ => ('Invited', const Color(0xFFFFD99D), const Color(0x48C28C46)),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        child: Text(
          label,
          style: TextStyle(color: foreground, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
