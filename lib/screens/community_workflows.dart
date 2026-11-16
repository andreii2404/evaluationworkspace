import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/cloud_repository.dart';
import '../services/questionnaire_data.dart';
import '../services/workspace_files.dart'
    if (dart.library.js_interop) '../services/workspace_files_web.dart';
import '../widgets/app_notice.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/workshop_glass.dart';
import '../widgets/workspace_select.dart';
import 'workspace_files_screen.dart';
import 'workspace_forms.dart';

Future<bool> _form(
  BuildContext context,
  String title,
  String action,
  List<Widget> fields,
  Future<void> Function() save, {
  bool destructive = false,
}) async {
  final key = GlobalKey<FormState>();
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => WorkspaceDialogForm(
          title: title,
          action: action,
          destructive: destructive,
          child: Form(
            key: key,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: fields,
            ),
          ),
          onSave: () async {
            if (!validateAndReveal(key)) return false;
            await save();
            return true;
          },
        ),
      ) ??
      false;
}

Widget _field(
  String label,
  int max,
  ValueChanged<String> change, {
  int min = 1,
  int lines = 1,
  bool link = false,
}) => TextFormField(
  maxLength: max,
  minLines: lines,
  maxLines: lines + (lines == 1 ? 0 : 2),
  decoration: InputDecoration(labelText: label, counterText: ''),
  onChanged: change,
  validator: (value) {
    final text = (value ?? '').trim();
    if (text.length < min) return 'Enter at least $min characters.';
    if (link) {
      final uri = Uri.tryParse(text);
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          RegExp(r'\s').hasMatch(text)) {
        return 'Enter a direct HTTPS link.';
      }
    }
    return null;
  },
);

String _memberName(Object? profile, [String fallback = 'Member']) =>
    profile is Map ? profile['display_name']?.toString() ?? fallback : fallback;

String _date(BuildContext context, Object? timestamp) {
  final value = DateTime.tryParse(timestamp?.toString() ?? '')?.toLocal();
  if (value == null) return '';
  final local = MaterialLocalizations.of(context);
  return '${local.formatShortDate(value)} · ${local.formatTimeOfDay(TimeOfDay.fromDateTime(value))}';
}

class _CommunityRows extends StatefulWidget {
  const _CommunityRows({
    required this.load,
    required this.label,
    required this.builder,
    this.subscribe,
    this.unsubscribe,
  });
  final Future<List<WorkspaceRow>> Function() load;
  final String label;
  final Widget Function(List<WorkspaceRow>, VoidCallback) builder;
  final RealtimeChannel Function(VoidCallback)? subscribe;
  final void Function(RealtimeChannel)? unsubscribe;

  @override
  State<_CommunityRows> createState() => _CommunityRowsState();
}

class _CommunityRowsState extends State<_CommunityRows> {
  late Future<List<WorkspaceRow>> _rows = widget.load();
  RealtimeChannel? _channel;
  void _refresh() => setState(() => _rows = widget.load());

  @override
  void initState() {
    super.initState();
    _channel = widget.subscribe?.call(() {
      if (mounted) _refresh();
    });
  }

  @override
  void dispose() {
    if (_channel case final channel?) widget.unsubscribe?.call(channel);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _rows,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return SkeletonRows(
          label: 'Loading ${widget.label.toLowerCase()}',
          count: 2,
        );
      }
      if (snapshot.hasError) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            AppNotice(workspaceError(snapshot.error!), tone: NoticeTone.error),
            OutlinedButton(onPressed: _refresh, child: const Text('Try again')),
          ],
        );
      }
      return widget.builder(snapshot.data!, _refresh);
    },
  );
}

Future<void> _run(
  BuildContext context,
  Future<void> Function() action,
  VoidCallback refresh,
) async {
  try {
    await action();
    if (context.mounted) refresh();
  } catch (error) {
    if (context.mounted) {
      AppNotice.show(context, workspaceError(error), tone: NoticeTone.error);
    }
  }
}

class ProjectTeamTools extends StatefulWidget {
  const ProjectTeamTools({
    super.key,
    required this.repository,
    required this.project,
    required this.directory,
  });
  final CloudRepository repository;
  final WorkspaceRow project;
  final List<WorkspaceRow> directory;

  @override
  State<ProjectTeamTools> createState() => _ProjectTeamToolsState();
}

enum _ProjectTab {
  team('Team'),
  files('Files'),
  results('Results'),
  revisions('Revisions'),
  rounds('Rounds');

  const _ProjectTab(this.label);
  final String label;
}

class _ProjectTeamToolsState extends State<ProjectTeamTools> {
  _ProjectTab _tab = _ProjectTab.team;
  CloudRepository get _repo => widget.repository;
  String get _project => widget.project['id'];
  bool get _owner => widget.project['creator_id'] == _repo.userId;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 14,
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 5,
        children: [
          for (final tab in _ProjectTab.values)
            ChoiceChip(
              selected: _tab == tab,
              showCheckmark: false,
              label: Text(tab.label),
              onSelected: (_) => setState(() => _tab = tab),
            ),
        ],
      ),
      switch (_tab) {
        _ProjectTab.team => _team(),
        _ProjectTab.files => WorkspaceFilesScreen(
          repository: _repo,
          projectId: _project,
        ),
        _ProjectTab.revisions => _revisions(),
        _ProjectTab.rounds => _rounds(),
        _ProjectTab.results => ProjectResponses(
          repository: _repo,
          project: widget.project,
        ),
      },
    ],
  );

  Widget _team() => _CommunityRows(
    label: 'Collaborators',
    load: () async => _repo.client
        .from('project_collaborators')
        .select('member_id, member:profiles(display_name)')
        .eq('project_id', _project)
        .order('joined_at'),
    builder: (rows, refresh) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        const Text(
          'Team members can open the project and access its results, conversations, revisions, and files.',
        ),
        if (_owner)
          WorkshopAction(
            label: 'Add collaborator',
            icon: Icons.person_add_alt,
            onPressed: () => _addMember(rows, refresh),
          ),
        if (rows.isEmpty) const Text('No collaborators yet.'),
        for (final row in rows)
          WorkshopGlass(
            child: ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(
                _memberName(
                  row['member'],
                  row['member_id'] == _repo.userId
                      ? 'You'
                      : 'Project collaborator',
                ),
              ),
              subtitle: const Text('Collaborator'),
              trailing: _owner || row['member_id'] == _repo.userId
                  ? IconButton(
                      tooltip: _owner ? 'Remove collaborator' : 'Leave project',
                      onPressed: () => _removeMember(row, refresh),
                      icon: const Icon(Icons.person_remove_outlined),
                    )
                  : null,
            ),
          ),
      ],
    ),
  );

  Future<void> _removeMember(WorkspaceRow row, VoidCallback refresh) async {
    final title = _owner ? 'Remove collaborator' : 'Leave project';
    final saved = await confirmWorkspaceAction(
      context,
      title: '$title?',
      action: title,
      subject: _owner
          ? _memberName(row['member'], 'Project collaborator')
          : widget.project['title'],
      message: _owner
          ? 'This member will lose access to the project’s private results and shared files.'
          : 'You will lose access to the project’s private results and shared files.',
      destructive: true,
      perform: () async {
        await _repo.client
            .from('project_collaborators')
            .delete()
            .eq('project_id', _project)
            .eq('member_id', row['member_id'])
            .select('member_id')
            .single();
      },
    );
    if (saved && mounted) {
      if (_owner) {
        refresh();
      } else {
        Navigator.pop(context);
      }
    }
  }

  Future<void> _addMember(List<WorkspaceRow> rows, VoidCallback refresh) async {
    try {
      final connections = await _repo.memberConnections();
      if (!mounted) return;
      final existing = rows.map((row) => row['member_id']).toSet();
      final choices = <String, String>{
        for (final member in widget.directory)
          if (!existing.contains(member['id']))
            member['id']: member['display_name'],
        for (final connection in connections)
          if (connection['status'] == 'accepted')
            if (connection['requester_id'] == _repo.userId) ...{
              if (!existing.contains(connection['recipient_id']))
                connection['recipient_id']: _memberName(
                  connection['recipient'],
                  'Connection',
                ),
            } else ...{
              if (!existing.contains(connection['requester_id']))
                connection['requester_id']: _memberName(
                  connection['requester'],
                  'Connection',
                ),
            },
      };
      if (choices.isEmpty) {
        AppNotice.show(
          context,
          'No directory members or connections are available to add.',
        );
        return;
      }
      String? member;
      final saved = await _form(
        context,
        'Add collaborator',
        'Grant access',
        [
          WorkspaceSelect<String>(
            label: 'Member',
            choices: choices,
            onChanged: (value) => member = value,
            validator: (value) => value == null ? 'Choose a member.' : null,
          ),
          const Text(
            'Only include people who should see the project’s private evaluation results.',
          ),
        ],
        () async {
          await _repo.client.from('project_collaborators').insert({
            'project_id': _project,
            'member_id': member,
          });
        },
      );
      if (saved && mounted) refresh();
    } catch (error) {
      if (mounted) {
        AppNotice.show(context, workspaceError(error), tone: NoticeTone.error);
      }
    }
  }

  Widget _revisions() => _CommunityRows(
    label: 'Revisions',
    load: () async => _repo.client
        .from('project_revision_tasks')
        .select()
        .eq('project_id', _project)
        .order('created_at')
        .limit(100),
    builder: (rows, refresh) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        Text(
          '${rows.where((row) => row['done'] == true).length} of ${rows.length} revisions complete',
        ),
        OutlinedButton.icon(
          onPressed: () =>
              addProjectRevision(context, _repo, _project).then((saved) {
                if (saved && mounted) refresh();
              }),
          icon: const Icon(Icons.add),
          label: const Text('Add revision'),
        ),
        for (final row in rows)
          WorkshopGlass(
            child: CheckboxListTile(
              value: row['done'],
              onChanged: (value) => _run(context, () async {
                await _repo.client
                    .from('project_revision_tasks')
                    .update({'done': value})
                    .eq('id', row['id'])
                    .select('id')
                    .single();
              }, refresh),
              title: Text(row['description']),
              controlAffinity: ListTileControlAffinity.leading,
              secondary: IconButton(
                tooltip: 'Remove revision',
                onPressed: () async {
                  final saved = await confirmWorkspaceAction(
                    context,
                    title: 'Remove revision?',
                    action: 'Remove revision',
                    subject: row['description'],
                    message:
                        'This removes the task and its completion status from the shared checklist.',
                    destructive: true,
                    perform: () async {
                      await _repo.client
                          .from('project_revision_tasks')
                          .delete()
                          .eq('id', row['id'])
                          .select('id')
                          .single();
                    },
                  );
                  if (saved && mounted) refresh();
                },
                icon: const Icon(Icons.delete_outline, size: 18),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _rounds() => _CommunityRows(
    label: 'Review rounds',
    load: () => projectRounds(_repo, _project),
    builder: (rows, refresh) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        const Text(
          'Use a separate round when you have a new version ready for evaluation.',
        ),
        if (_owner)
          OutlinedButton.icon(
            onPressed: () => _createRound(refresh),
            icon: const Icon(Icons.add),
            label: const Text('New round'),
          ),
        for (final round in rows)
          WorkshopGlass(
            child: ListTile(
              title: Text(round['label']),
              subtitle: Text(_date(context, round['created_at'])),
              trailing: IconButton(
                tooltip: 'Open version link',
                onPressed: () => _run(context, () async {
                  if (!await launchUrl(
                    Uri.parse(round['artifact_url']),
                    webOnlyWindowName: '_blank',
                  )) {
                    throw const FormatException(
                      'Couldn’t open the version link.',
                    );
                  }
                }, () {}),
                icon: const Icon(Icons.open_in_new, size: 17),
              ),
            ),
          ),
      ],
    ),
  );

  Future<void> _createRound(VoidCallback refresh) async {
    String label = '', link = '';
    final saved = await _form(
      context,
      'Create a review round',
      'Create round',
      [
        _field('Version or round name', 80, (value) => label = value),
        _field('Direct version link', 500, (value) => link = value, link: true),
      ],
      () async {
        await _repo.client.from('project_review_rounds').insert({
          'project_id': _project,
          'label': label.trim(),
          'artifact_url': link.trim(),
        });
      },
    );
    if (saved && mounted) refresh();
  }
}

Future<List<WorkspaceRow>> projectRounds(
  CloudRepository repo,
  String project,
) async => repo.client
    .from('project_review_rounds')
    .select()
    .eq('project_id', project)
    .order('created_at');

Future<bool> addProjectRevision(
  BuildContext context,
  CloudRepository repo,
  String project, {
  String? assignment,
}) {
  String description = '';
  return _form(
    context,
    'Add a revision',
    'Add revision',
    [
      _field(
        'What needs to change?',
        240,
        (value) => description = value,
        lines: 2,
      ),
    ],
    () async {
      await repo.client.from('project_revision_tasks').insert({
        'project_id': project,
        'assignment_id': ?assignment,
        'description': description.trim(),
      });
    },
  );
}

class ProjectResponses extends StatelessWidget {
  const ProjectResponses({
    super.key,
    required this.repository,
    required this.project,
    this.loadResponses,
  });
  final CloudRepository repository;
  final WorkspaceRow project;
  final Future<List<WorkspaceRow>> Function()? loadResponses;

  Future<List<WorkspaceRow>> _results() async {
    final assignments = await repository.client
        .from('review_assignments')
        .select(
          'id, round:project_review_rounds(label), reviews(scores, feedback, created_at, respondent_details)',
        )
        .eq('project_id', project['id'])
        .eq('status', 'submitted')
        .order('submitted_at')
        .limit(1000);
    final criteria = await repository.projectCriteria(project);
    final labels = {
      for (final criterion in criteria)
        criterion['key']?.toString() ?? criterion['criterion_key'].toString():
            (criterion['prompt'] ?? criterion['label']).toString(),
    };
    return [
      for (final row in assignments)
        if (row['reviews'] is Map)
          {
            'round': (row['round'] as Map?)?['label'] ?? 'Initial review',
            'round_id': (row['round'] as Map?)?['label'],
            ...Map<String, dynamic>.from(row['reviews']),
            'labels': labels,
          },
    ];
  }

  @override
  Widget build(BuildContext context) => _CommunityRows(
    label: 'Responses',
    load: loadResponses ?? _results,
    builder: (rows, refresh) {
      if (rows.isEmpty) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Submitted evaluations will appear here.'),
            TextButton(
              onPressed: refresh,
              child: const Text('Refresh responses'),
            ),
          ],
        );
      }
      final groups = <Object?, List<WorkspaceRow>>{};
      for (final row in rows) {
        (groups[row['round_id']] ??= []).add(row);
      }
      final labels = rows.first['labels'] as Map<String, String>;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${rows.length}${rows.length == 1000 ? '+' : ''} ${rows.length == 1 ? 'response' : 'responses'}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Refresh responses',
                onPressed: refresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          for (final group in groups.values)
            WorkshopGlass(
              child: ExpansionTile(
                title: Text(group.first['round']),
                subtitle: Text(
                  '${group.length} submitted ${group.length == 1 ? 'review' : 'reviews'}',
                ),
                children: [
                  for (final entry in labels.entries)
                    if (_mean(group, entry.key) case final mean?)
                      ListTile(
                        dense: true,
                        title: Text(entry.value),
                        trailing: Text(mean.toStringAsFixed(2)),
                      ),
                  const Divider(height: 12),
                  for (final (index, row) in group.indexed)
                    ExpansionTile(
                      title: Text('Response ${index + 1}'),
                      subtitle: Text(_date(context, row['created_at'])),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                      children: [
                        for (final (index, label)
                            in (projectQuestionnaire(project)?.fields ??
                                    const <String>[])
                                .indexed)
                          if (row['respondent_details'] case final List details
                              when index < details.length &&
                                  details[index].toString().isNotEmpty)
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(label),
                              subtitle: Text(details[index].toString()),
                            ),
                        for (final entry in labels.entries)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(entry.value),
                            subtitle: Text(switch ((row['scores']
                                as Map?)?[entry.key]) {
                              0 => 'Not assessed',
                              final num value => value.toString(),
                              _ => 'No answer',
                            }),
                          ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: SelectableText(row['feedback']),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          if (labels.isNotEmpty)
            const Text('Averages exclude unanswered and not-assessed items.'),
          OutlinedButton.icon(
            label: const Text('Export questionnaire results'),
            icon: const Icon(Icons.download_outlined),
            onPressed: () => _export(context, rows, labels),
          ),
        ],
      );
    },
  );

  double? _mean(List<WorkspaceRow> group, String key) {
    final scores = group
        .map((row) => (row['scores'] as Map?)?[key])
        .whereType<num>()
        .where((score) => score > 0)
        .toList();
    return scores.isEmpty
        ? null
        : scores.reduce((a, b) => a + b) / scores.length;
  }

  void _export(
    BuildContext context,
    List<WorkspaceRow> rows,
    Map<String, String> labels,
  ) {
    try {
      final csv = <List<Object?>>[
        ['Round', 'Submitted', ...labels.values, 'Feedback'],
        for (final row in rows)
          [
            row['round'],
            row['created_at'],
            for (final key in labels.keys)
              switch ((row['scores'] as Map?)?[key]) {
                0 => 'Not assessed',
                final value => value,
              },
            row['feedback'],
          ],
      ];
      downloadWorkspaceCsv(
        'evaluation-results.csv',
        csv.map((row) => row.map(_csvCell).join(',')).join('\r\n'),
      );
    } catch (error) {
      AppNotice.show(context, workspaceError(error), tone: NoticeTone.error);
    }
  }

  String _csvCell(Object? value) {
    var text = value?.toString() ?? '';
    if (value is String &&
        RegExp(r'^[\s\x00-\x1f]*[=+@-]|^[\t\r\n]').hasMatch(text)) {
      text = "'$text"; // Prevent spreadsheet formula interpretation.
    }
    return '"${text.replaceAll('"', '""')}"';
  }
}

void showReviewConversation(
  BuildContext context,
  CloudRepository repo,
  WorkspaceRow assignment,
) {
  final id = assignment['id'] as String;
  final project = assignment['projects'] as WorkspaceRow?;
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Review conversation'),
      content: SizedBox(
        width: 490,
        child: SingleChildScrollView(
          child: _CommunityRows(
            label: 'Conversation',
            subscribe: (refresh) => repo.client
                .channel('review-conversation-$id')
                .onPostgresChanges(
                  event: PostgresChangeEvent.insert,
                  schema: 'public',
                  table: 'review_messages',
                  filter: PostgresChangeFilter(
                    type: PostgresChangeFilterType.eq,
                    column: 'assignment_id',
                    value: id,
                  ),
                  callback: (_) => refresh(),
                )
                .subscribe(),
            unsubscribe: repo.client.removeChannel,
            load: () async {
              final rows = await repo.client
                  .from('review_messages')
                  .select('*, sender:profiles(display_name)')
                  .eq('assignment_id', id)
                  .order('created_at', ascending: false)
                  .limit(100);
              return rows.reversed.toList();
            },
            builder: (rows, refresh) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 10,
              children: [
                Text(project?['title'] ?? 'Project review'),
                Wrap(
                  spacing: 8,
                  runSpacing: 5,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: () async {
                        String text = '';
                        final sent = await _form(
                          dialogContext,
                          'New message',
                          'Send',
                          [
                            _field(
                              'Message',
                              2000,
                              (value) => text = value,
                              lines: 4,
                            ),
                          ],
                          () async {
                            await repo.client.from('review_messages').insert({
                              'assignment_id': id,
                              'body': text.trim(),
                            });
                          },
                        );
                        if (sent && dialogContext.mounted) refresh();
                      },
                      label: const Text('New message'),
                      icon: const Icon(Icons.edit_outlined, size: 17),
                    ),
                    IconButton(
                      tooltip: 'Refresh conversation',
                      onPressed: refresh,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                if (rows.isEmpty)
                  const Text('Use this thread for questions about the review.'),
                for (final row in rows)
                  WorkshopGlass(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 5,
                        children: [
                          Text(
                            '${row['sender_id'] == repo.userId ? 'You' : _memberName(row['sender'])} · ${_date(dialogContext, row['created_at'])}',
                          ),
                          SelectionArea(child: Text(row['body'])),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

class WorkspaceUpdates extends StatelessWidget {
  const WorkspaceUpdates({
    super.key,
    required this.repository,
    required this.open,
    required this.close,
  });
  final CloudRepository repository;
  final ValueChanged<WorkspaceRow> open;
  final VoidCallback close;

  static const _labels = {
    'team': 'You were added to a project',
    'invited': 'New review invitation',
    'accepted': 'Review invitation accepted',
    'declined': 'Review invitation declined',
    'submitted': 'New evaluation feedback',
    'message': 'New review message',
    'reminder': 'Review reminder',
  };

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 6, 4),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  'Updates',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            IconButton(
              onPressed: close,
              tooltip: 'Close updates',
              icon: const Icon(Icons.close_rounded, size: 19),
            ),
          ],
        ),
      ),
      const Divider(height: 1),
      Flexible(
        child: SingleChildScrollView(
          primary: false,
          padding: const EdgeInsets.all(10),
          child: _list(context),
        ),
      ),
    ],
  );

  Widget _list(BuildContext context) => _CommunityRows(
    label: 'Updates',
    subscribe: (refresh) => repository.client
        .channel('workspace-updates-${repository.userId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'workspace_notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'recipient_id',
            value: repository.userId,
          ),
          callback: (_) => refresh(),
        )
        .subscribe(),
    unsubscribe: repository.client.removeChannel,
    load: () async => repository.client
        .from('workspace_notifications')
        .select(
          'id,kind,project_id,assignment_id,created_at,read_at, projects(title)',
        )
        .order('created_at', ascending: false)
        .limit(100),
    builder: (rows, refresh) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            onPressed: refresh,
            tooltip: 'Refresh updates',
            icon: const Icon(Icons.refresh),
          ),
        ),
        if (rows.isEmpty)
          const WorkshopGlass(
            child: ListTile(
              leading: Icon(Icons.inbox_outlined),
              title: Text('You’re caught up'),
            ),
          ),
        for (final row in rows)
          WorkshopGlass(
            child: ListTile(
              leading: Icon(
                row['read_at'] == null ? Icons.circle : Icons.circle_outlined,
                size: 14,
              ),
              title: Text(_labels[row['kind']] ?? 'Project update'),
              subtitle: Text(
                [
                  (row['projects'] as Map?)?['title'],
                  _date(context, row['created_at']),
                ].whereType<String>().join(' · '),
              ),
              trailing: row['read_at'] == null
                  ? IconButton(
                      tooltip: 'Mark as read',
                      onPressed: () => _mark(context, row, refresh),
                      icon: const Icon(Icons.done),
                    )
                  : null,
              onTap: () async {
                if (row['read_at'] == null) {
                  await _mark(context, row, refresh);
                }
                if (context.mounted) open(row);
              },
            ),
          ),
      ],
    ),
  );

  Future<void> _mark(
    BuildContext context,
    WorkspaceRow row,
    VoidCallback refresh,
  ) => _run(context, () async {
    await repository.client
        .from('workspace_notifications')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', row['id'])
        .select('id')
        .single();
  }, refresh);
}

class ReviewerTrust extends StatelessWidget {
  const ReviewerTrust({
    super.key,
    required this.repository,
    required this.reviewer,
  });
  final CloudRepository repository;
  final String reviewer;

  @override
  Widget build(BuildContext context) => _CommunityRows(
    label: 'Review history',
    load: () async {
      final rows = await Future.wait<dynamic>([
        repository.client.rpc(
          'completed_review_count',
          params: {'p_evaluator': reviewer},
        ),
        repository.client
            .from('checked_credentials')
            .select('kind,label,checked_at')
            .eq('member_id', reviewer)
            .order('checked_at', ascending: false),
      ]);
      return [
        {'count': rows[0]},
        ...rows[1] as List<WorkspaceRow>,
      ];
    },
    builder: (rows, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 7,
      children: [
        Text('${rows.first['count']} completed reviews on In Cantiere'),
        for (final row in rows.skip(1))
          Text(
            'Moderator-checked ${row['kind'].toString().toLowerCase()} · ${row['label']}',
          ),
      ],
    ),
  );
}

class CredentialWorkflow extends StatelessWidget {
  const CredentialWorkflow({
    super.key,
    required this.repository,
    this.staff = false,
  });
  final CloudRepository repository;
  final bool staff;

  @override
  Widget build(BuildContext context) => _CommunityRows(
    label: 'Credentials',
    load: () async {
      final query = repository.client
          .from('credential_requests')
          .select('*, applicant:profiles(display_name)');
      return (staff
              ? query.neq('applicant_id', repository.userId).inFilter(
                  'status',
                  ['pending', 'approved'],
                )
              : query.eq('applicant_id', repository.userId))
          .order('created_at', ascending: false)
          .limit(50);
    },
    builder: (rows, refresh) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        Text(
          staff ? 'Credential review' : 'Credential checks',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (!staff)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: () => _submit(context, refresh),
              child: const Text('Request a credential check'),
            ),
          ),
        if (rows.isEmpty)
          Text(
            staff
                ? 'No credential requests in the queue.'
                : 'You haven’t requested a credential check.',
          ),
        for (final row in rows)
          WorkshopGlass(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 7,
                children: [
                  Text('${row['kind']} · ${row['label']}'),
                  Text(switch (row['status']) {
                    'approved' => 'Checked',
                    'declined' => 'Declined',
                    _ => 'Awaiting review',
                  }),
                  if (staff)
                    Text(_memberName(row['applicant'], 'Directory hidden')),
                  if (row['decision_note'] case final String note) Text(note),
                  Wrap(
                    spacing: 6,
                    runSpacing: 5,
                    children: [
                      TextButton(
                        onPressed: () => _run(context, () async {
                          if (!await launchUrl(
                            Uri.parse(row['evidence_url']),
                            webOnlyWindowName: '_blank',
                          )) {
                            throw const FormatException(
                              'Couldn’t open evidence.',
                            );
                          }
                        }, () {}),
                        child: const Text('Open evidence'),
                      ),
                      if (staff) ...[
                        if (row['status'] == 'pending')
                          FilledButton.tonal(
                            onPressed: () =>
                                _decide(context, row, true, refresh),
                            child: const Text('Approve'),
                          ),
                        OutlinedButton(
                          onPressed: () =>
                              _decide(context, row, false, refresh),
                          child: Text(
                            row['status'] == 'approved' ? 'Revoke' : 'Decline',
                          ),
                        ),
                      ] else
                        OutlinedButton(
                          onPressed: () => _withdraw(context, row, refresh),
                          child: const Text('Withdraw'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );

  Future<void> _submit(BuildContext context, VoidCallback refresh) async {
    String kind = 'Affiliation', label = '', link = '';
    final saved = await _form(
      context,
      'Request a credential check',
      'Submit evidence',
      [
        WorkspaceSelect<String>(
          label: 'Credential type',
          initial: kind,
          choices: const {
            'Affiliation': 'Affiliation',
            'Certification': 'Certification',
            'Professional license': 'Professional license',
            'Portfolio': 'Portfolio',
          },
          onChanged: (value) => kind = value,
        ),
        _field(
          'Credential or institution name',
          120,
          (value) => label = value,
          min: 3,
        ),
        _field('Evidence link', 500, (value) => link = value, link: true),
        const Text(
          'Share a link a moderator can check. Approved labels appear on your reviewer profile.',
        ),
      ],
      () async {
        await repository.client.from('credential_requests').insert({
          'kind': kind,
          'label': label.trim(),
          'evidence_url': link.trim(),
        });
      },
    );
    if (saved && context.mounted) refresh();
  }

  Future<void> _withdraw(
    BuildContext context,
    WorkspaceRow row,
    VoidCallback refresh,
  ) async {
    final saved = await confirmWorkspaceAction(
      context,
      title: 'Withdraw credential?',
      action: 'Withdraw credential',
      subject: row['label'],
      message:
          'This removes the evidence request and any checked credential label from your profile.',
      destructive: true,
      perform: () async {
        await repository.client
            .from('credential_requests')
            .delete()
            .eq('id', row['id'])
            .select('id')
            .single();
      },
    );
    if (saved && context.mounted) refresh();
  }

  Future<void> _decide(
    BuildContext context,
    WorkspaceRow row,
    bool approved,
    VoidCallback refresh,
  ) async {
    String reason = '';
    final action = approved
        ? 'Approve'
        : row['status'] == 'approved'
        ? 'Revoke'
        : 'Decline';
    final saved = await _form(
      context,
      '$action credential',
      action,
      [
        _field(
          'What did you check or decide?',
          800,
          (value) => reason = value,
          min: 3,
          lines: 3,
        ),
        if (approved)
          const Text(
            'Approve only after checking that the evidence supports the label and belongs to the applicant.',
          ),
        if (!approved && row['status'] == 'approved')
          const Text(
            'Revoking this credential removes its checked label from the member’s profile.',
          ),
      ],
      () async {
        await repository.client.rpc(
          'decide_credential',
          params: {
            'p_id': row['id'],
            'p_approve': approved,
            'p_note': reason.trim(),
          },
        );
      },
      destructive: !approved,
    );
    if (saved && context.mounted) refresh();
  }
}
