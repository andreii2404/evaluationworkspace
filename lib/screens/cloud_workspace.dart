import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import '../services/cloud_repository.dart';
import 'workspace_forms.dart';

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

class CloudWorkspace extends StatefulWidget {
  const CloudWorkspace({super.key, required this.client, required this.userId});
  final SupabaseClient client;
  final String userId;

  @override
  State<CloudWorkspace> createState() => _CloudWorkspaceState();
}

class _CloudWorkspaceState extends State<CloudWorkspace> {
  late final _repo = CloudRepository(widget.client, widget.userId);
  late Future<WorkspaceData> _data = _repo.load();
  RealtimeChannel? _updates;
  _Area _area = _Area.overview;
  bool _busy = false;
  bool _community = false;
  String _query = '';
  String? _evaluatorType;

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

  void _select(_Area area) => setState(() {
    _area = area;
    _query = '';
  });

  @override
  Widget build(BuildContext context) {
    final areas = _Area.values
        .where((area) => area != _Area.moderation || _repo.isModerator)
        .toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 920;
        final nav = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(22, 20, 18, 25),
              child: EvalinkMark(),
            ),
            for (final area in areas)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 2,
                ),
                child: ListTile(
                  selected: _area == area,
                  selectedTileColor: mint,
                  selectedColor: teal,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                  ),
                  leading: Icon(area.icon),
                  title: Text(area.title),
                  onTap: () {
                    if (!wide) Navigator.pop(context);
                    _select(area);
                  },
                ),
              ),
            const Spacer(),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Sign out'),
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
            const SizedBox(height: 10),
          ],
        );
        return Scaffold(
          appBar: AppBar(
            title: Text(_area.title),
            actions: [
              IconButton(
                tooltip: 'Refresh workspace',
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
              ),
              const SizedBox(width: 10),
            ],
          ),
          drawer: wide ? null : Drawer(child: SafeArea(child: nav)),
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (wide) ...[
                SizedBox(
                  width: 216,
                  child: Material(color: Colors.white, child: nav),
                ),
                const VerticalDivider(width: 1),
              ],
              Expanded(
                child: FutureBuilder<WorkspaceData>(
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
                    return Column(
                      children: [
                        if (_busy ||
                            snapshot.connectionState == ConnectionState.waiting)
                          const LinearProgressIndicator(minHeight: 2)
                        else
                          const SizedBox(height: 2),
                        Expanded(
                          child: SingleChildScrollView(
                            key: PageStorageKey(_area),
                            padding: EdgeInsets.all(wide ? 32 : 16),
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 1000,
                                ),
                                child: SizedBox(
                                  width: double.infinity,
                                  child: switch (_area) {
                                    _Area.overview => _overview(data),
                                    _Area.projects => _projects(data),
                                    _Area.directory => _directory(data),
                                    _Area.reviews => _reviews(data),
                                    _Area.profile => _profile(data),
                                    _Area.moderation => _moderation(data),
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _overview(WorkspaceData data) {
    final incoming = data.assignments
        .where(
          (row) =>
              row['evaluator_id'] == widget.userId &&
              row['status'] == 'invited',
        )
        .length;
    final results = data.assignments
        .where(
          (row) =>
              row['creator_id'] == widget.userId &&
              row['status'] == 'submitted',
        )
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(25),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFE3F3FF), Color(0xFFD9F3EE)],
            ),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Welcome, ${data.profile['display_name']}.',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              const Text('Pick up where you left off.'),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _busy ? null : _createProject,
                icon: const Icon(Icons.add),
                label: const Text('New project'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _Metric(
              'My projects',
              data.projects.length,
              () => _select(_Area.projects),
            ),
            _Metric(
              'Review invitations',
              incoming,
              () => _select(_Area.reviews),
            ),
            _Metric('Feedback received', results, () => _select(_Area.reviews)),
          ],
        ),
        const SizedBox(height: 26),
        _heading('Recent projects'),
        if (data.projects.isEmpty)
          const _Blank(icon: Icons.layers_outlined, title: 'No projects yet')
        else
          for (final project in data.projects.take(4))
            _projectTile(project, owned: true),
      ],
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
                  style: const TextStyle(color: muted),
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
                backgroundColor: mint,
                child: Icon(Icons.person_outline, color: teal),
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
                  const Text('Email confirmed', style: TextStyle(color: teal)),
                const SizedBox(height: 12),
                const Text(
                  'Self-reported expertise',
                  style: TextStyle(color: muted),
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
    final incoming = data.assignments.where(
      (item) => item['evaluator_id'] == widget.userId,
    );
    final outgoing = data.assignments.where(
      (item) => item['creator_id'] == widget.userId,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading('Assigned to me'),
        if (incoming.isEmpty)
          const _Blank(icon: Icons.inbox_outlined, title: 'No assignments yet'),
        for (final item in incoming) _assignment(item, data, incoming: true),
        const SizedBox(height: 25),
        _heading('Requested by me'),
        if (outgoing.isEmpty)
          const _Blank(icon: Icons.send_outlined, title: 'No invitations sent'),
        for (final item in outgoing) _assignment(item, data, incoming: false),
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
                style: const TextStyle(color: muted),
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
                  style: const TextStyle(color: muted),
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
    child: Text(title, style: Theme.of(context).textTheme.titleLarge),
  );
}

class _Surface extends StatelessWidget {
  const _Surface({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
        side: const BorderSide(color: line),
      ),
      clipBehavior: Clip.antiAlias,
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
          Icon(icon, color: muted, size: 28),
          const SizedBox(height: 9),
          Text(title, style: const TextStyle(color: muted)),
          ?action,
        ],
      ),
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric(this.title, this.value, this.onTap);
  final String title;
  final int value;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onTap,
    style: OutlinedButton.styleFrom(
      backgroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
    child: Text('$value  $title'),
  );
}

class _Status extends StatelessWidget {
  const _Status(this.state);
  final String state;

  @override
  Widget build(BuildContext context) {
    final (label, foreground, background) = switch (state) {
      'accepted' => (
        'Accepted',
        const Color(0xFF175CD3),
        const Color(0xFFD1E9FF),
      ),
      'submitted' => (
        'Submitted',
        const Color(0xFF067647),
        const Color(0xFFD1FADF),
      ),
      'declined' => (
        'Declined',
        const Color(0xFFB42318),
        const Color(0xFFFEE4E2),
      ),
      _ => ('Invited', const Color(0xFFB54708), const Color(0xFFFEF0C7)),
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
