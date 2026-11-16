import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_theme.dart';
import '../services/cloud_repository.dart';
import '../widgets/app_notice.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/workshop_glass.dart';
import 'workspace_forms.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({
    super.key,
    required this.repository,
    required this.profile,
    required this.directory,
    required this.openProfile,
    required this.editVisibility,
    required this.openProjects,
    required this.onSessionEnded,
  });

  final CloudRepository repository;
  final WorkspaceRow profile;
  final List<WorkspaceRow> directory;
  final ValueChanged<WorkspaceRow> openProfile;
  final VoidCallback editVisibility, openProjects;
  final Future<void> Function() onSessionEnded;

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  late Future<List<WorkspaceRow>> _network = _readNetwork();
  final _busy = <String>{};
  final _search = TextEditingController();
  bool _showNetwork = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<List<WorkspaceRow>> _readNetwork() async {
    try {
      return await widget.repository.memberConnections();
    } catch (error) {
      if (mounted && workspaceSessionEnded(error)) {
        await widget.onSessionEnded();
      }
      rethrow;
    }
  }

  void _refresh() {
    final network = _readNetwork();
    setState(() {
      _network = network;
    });
  }

  Future<void> _change(
    String memberId,
    Future<void> Function() action,
    String done,
  ) async {
    if (_busy.contains(memberId)) return;
    setState(() => _busy.add(memberId));
    try {
      await action();
      if (!mounted) return;
      _refresh();
      AppNotice.show(context, done, tone: NoticeTone.success);
    } catch (error) {
      if (!mounted) return;
      if (workspaceSessionEnded(error)) {
        await widget.onSessionEnded();
      } else {
        if (error is PostgrestException && error.code == '23505') _refresh();
        AppNotice.show(context, workspaceError(error), tone: NoticeTone.error);
      }
    } finally {
      if (mounted) setState(() => _busy.remove(memberId));
    }
  }

  String get _me => widget.repository.userId;
  bool get _listed => widget.profile['directory_visible'] == true;
  bool _incoming(WorkspaceRow connection) => connection['recipient_id'] == _me;
  String _memberId(WorkspaceRow connection) =>
      connection[_incoming(connection) ? 'requester_id' : 'recipient_id']
          as String;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      WorkshopGlass(
        featured: true,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Build your network',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 5),
              const Text(
                'Meet creators and evaluators. Find people who share your interests or bring a different perspective.',
              ),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: widget.openProjects,
                icon: const Icon(Icons.layers_outlined, size: 17),
                label: const Text('Browse community projects'),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      FutureBuilder<List<WorkspaceRow>>(
        future: _network,
        builder: (context, snapshot) {
          final waiting = snapshot.connectionState != ConnectionState.done;
          if (snapshot.hasError && !waiting) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppNotice(
                  'Couldn’t load your network.',
                  tone: NoticeTone.error,
                ),
                TextButton(onPressed: _refresh, child: const Text('Try again')),
              ],
            );
          }
          final rows = snapshot.data;
          if (rows == null) {
            return const Padding(
              padding: EdgeInsets.all(14),
              child: SkeletonRows(label: 'Loading your network', leading: true),
            );
          }
          final incoming = rows
              .where((row) => _incoming(row) && row['status'] == 'pending')
              .toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ChoiceChip(
                    label: const Text('Discover people'),
                    selected: !_showNetwork,
                    onSelected: (_) => setState(() => _showNetwork = false),
                  ),
                  ChoiceChip(
                    label: Text(
                      incoming.isEmpty
                          ? 'My network'
                          : 'My network · ${incoming.length} new',
                    ),
                    selected: _showNetwork,
                    onSelected: (_) => setState(() => _showNetwork = true),
                  ),
                  IconButton(
                    tooltip: 'Refresh connections',
                    onPressed: waiting ? null : _refresh,
                    icon: const Icon(Icons.refresh_rounded, size: 19),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (waiting)
                const LoadingSkeleton(
                  label: 'Refreshing connections',
                  child: SkeletonBlock(height: 3, width: double.infinity),
                ),
              if (_showNetwork)
                _networkPanel(rows, incoming, waiting)
              else
                _discover(rows, waiting),
            ],
          );
        },
      ),
    ],
  );

  Widget _discover(List<WorkspaceRow> rows, bool waiting) {
    final byMember = {for (final row in rows) _memberId(row): row};
    final query = _search.text.trim().toLowerCase();
    final people = widget.directory.where((person) {
      final searchable = [
        person['display_name'],
        person['headline'],
        person['expertise'],
        professions[person['profession']],
      ].whereType<String>().join(' ').toLowerCase();
      return searchable.contains(query);
    }).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_listed) ...[
          const AppNotice(
            'Turn on your directory listing in Profile to send connection requests.',
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: widget.editVisibility,
              child: const Text('Open profile settings'),
            ),
          ),
        ],
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search_rounded),
            hintText: 'Search people, professions, or expertise',
          ),
        ),
        const SizedBox(height: 12),
        _list(people.isEmpty ? 'No matching members' : 'Members', [
          for (final person in people)
            _discoverRow(person, byMember[person['id']], waiting),
        ]),
      ],
    );
  }

  Widget _discoverRow(
    WorkspaceRow person,
    WorkspaceRow? connection,
    bool waiting,
  ) {
    final id = person['id'] as String;
    final disabled = waiting || _busy.contains(id);
    final action = switch (connection?['status']) {
      'accepted' => const Text(
        'Connected',
        style: TextStyle(color: workshopIce),
      ),
      'pending' when _incoming(connection!) => TextButton(
        onPressed: () => setState(() => _showNetwork = true),
        child: const Text('Respond'),
      ),
      'pending' => const Text(
        'Request sent',
        style: TextStyle(color: workshopMuted),
      ),
      _ => OutlinedButton(
        onPressed: disabled || !_listed
            ? null
            : () => _change(
                id,
                () => widget.repository.requestConnection(id),
                'Connection request sent',
              ),
        child: const Text('Connect'),
      ),
    };
    return _memberRow(person, [
      action,
    ], openProfile: () => widget.openProfile(person));
  }

  Widget _networkPanel(
    List<WorkspaceRow> rows,
    List<WorkspaceRow> incoming,
    bool waiting,
  ) {
    final accepted = rows.where((row) => row['status'] == 'accepted');
    final outgoing = rows.where(
      (row) => !_incoming(row) && row['status'] == 'pending',
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _list('Incoming requests', [
          for (final row in incoming) _networkRow(row, waiting),
        ], empty: 'No incoming requests.'),
        const SizedBox(height: 10),
        _list('Connections', [
          for (final row in accepted) _networkRow(row, waiting),
        ], empty: 'Accepted requests will appear here.'),
        const SizedBox(height: 10),
        _list('Sent requests', [
          for (final row in outgoing) _networkRow(row, waiting),
        ], empty: 'No pending requests.'),
      ],
    );
  }

  Widget _networkRow(WorkspaceRow connection, bool waiting) {
    final id = connection['id'] as String;
    final memberId = _memberId(connection);
    final incoming = _incoming(connection);
    final accepted = connection['status'] == 'accepted';
    final person =
        connection[incoming ? 'requester' : 'recipient'] as WorkspaceRow?;
    final details = widget.directory
        .where((row) => row['id'] == memberId)
        .firstOrNull;
    final disabled = waiting || _busy.contains(memberId);
    final removeLabel = accepted
        ? 'Remove'
        : incoming
        ? 'Decline'
        : 'Cancel request';
    return _memberRow(person, [
      if (!accepted && incoming && person != null)
        FilledButton.tonal(
          onPressed: disabled
              ? null
              : () => _change(
                  memberId,
                  () => widget.repository.acceptConnection(id),
                  'Connection accepted',
                ),
          child: const Text('Accept'),
        ),
      TextButton(
        onPressed: disabled
            ? null
            : () async {
                final action = accepted
                    ? 'Remove connection'
                    : incoming
                    ? 'Decline request'
                    : 'Cancel request';
                final changed = await confirmWorkspaceAction(
                  context,
                  title: '$action?',
                  subject: person?['display_name'] as String?,
                  action: action,
                  message: accepted
                      ? 'This member will be removed from your connections.'
                      : incoming
                      ? 'This closes the incoming connection request.'
                      : 'This withdraws your outgoing connection request.',
                  destructive: true,
                  perform: () => widget.repository.removeConnection(id),
                );
                if (!mounted || !changed) return;
                _refresh();
                AppNotice.show(
                  context,
                  accepted
                      ? 'Connection removed'
                      : incoming
                      ? 'Request declined'
                      : 'Request cancelled',
                  tone: NoticeTone.success,
                );
              },
        child: Text(removeLabel),
      ),
    ], openProfile: details == null ? null : () => widget.openProfile(details));
  }

  Widget _list(String title, List<Widget> children, {String? empty}) =>
      WorkshopGlass(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (children.isEmpty && empty != null) ...[
                const SizedBox(height: 7),
                Text(empty, style: const TextStyle(color: workshopMuted)),
              ],
              for (final row in children) ...[const Divider(height: 17), row],
            ],
          ),
        ),
      );

  Widget _memberRow(
    WorkspaceRow? person,
    List<Widget> actions, {
    VoidCallback? openProfile,
  }) {
    final name = person?['display_name'] as String? ?? 'Private member';
    final details = [professions[person?['profession']], person?['headline']]
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .toSet()
        .join(' · ');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 17,
        backgroundColor: const Color(0xFF26354B),
        foregroundColor: workshopIce,
        child: Text(
          name.isEmpty
              ? '?'
              : String.fromCharCode(name.runes.first).toUpperCase(),
        ),
      ),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (details.isNotEmpty) Text(details),
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: actions,
          ),
        ],
      ),
      trailing: openProfile == null
          ? null
          : IconButton(
              tooltip: 'View $name',
              onPressed: openProfile,
              icon: const Icon(Icons.chevron_right, size: 20),
            ),
    );
  }
}
