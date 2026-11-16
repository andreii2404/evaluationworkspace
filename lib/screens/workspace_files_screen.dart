import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/cloud_repository.dart';
import '../services/workspace_files.dart'
    if (dart.library.js_interop) '../services/workspace_files_web.dart';
import '../widgets/app_notice.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/workshop_glass.dart';
import '../widgets/workspace_select.dart';
import 'workspace_forms.dart';

class WorkspaceFilesScreen extends StatefulWidget {
  const WorkspaceFilesScreen({
    super.key,
    required this.repository,
    this.projectId,
  });

  final CloudRepository repository;
  final String? projectId;

  @override
  State<WorkspaceFilesScreen> createState() => _WorkspaceFilesScreenState();
}

class _WorkspaceFilesScreenState extends State<WorkspaceFilesScreen> {
  final _path = <WorkspaceRow>[];
  bool _busy = false;
  String get _scope => widget.projectId == null ? 'personal' : 'project';
  String get _scopeId => widget.projectId ?? widget.repository.userId;
  String? get _parent => _path.lastOrNull?['id'] as String?;
  String get _prefix => '$_scope/$_scopeId/${_parent ?? 'root'}';
  SupabaseClient get _client => widget.repository.client;
  StorageFileApi get _storage => _client.storage.from('workspace-files');

  late Future<({List<WorkspaceRow> folders, List<FileObject> files})> _items =
      _load();

  Future<({List<WorkspaceRow> folders, List<FileObject> files})> _load() async {
    final folderQuery = _client
        .from('workspace_folders')
        .select()
        .eq('scope', _scope)
        .eq('scope_id', _scopeId);
    final folderRows =
        (_parent == null
                ? folderQuery.isFilter('parent_id', null)
                : folderQuery.eq('parent_id', _parent!))
            .order('name')
            .limit(100);
    final result = await Future.wait<Object>([
      folderRows,
      _storage.list(path: _prefix),
    ]);
    return (
      folders: result[0] as List<WorkspaceRow>,
      files: (result[1] as List<FileObject>)
          .where((file) => file.id != null)
          .toList(),
    );
  }

  void _refresh() => setState(() => _items = _load());

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) _refresh();
    } catch (error) {
      if (mounted) {
        AppNotice.show(context, workspaceError(error), tone: NoticeTone.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _folder([WorkspaceRow? folder]) async {
    String name = folder?['name'] ?? '';
    final form = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => WorkspaceDialogForm(
        title: folder == null ? 'New folder' : 'Rename folder',
        action: 'Save folder',
        child: Form(
          key: form,
          child: TextFormField(
            initialValue: name,
            autofocus: true,
            maxLength: 100,
            decoration: const InputDecoration(
              labelText: 'Folder name',
              counterText: '',
            ),
            onChanged: (value) => name = value,
            validator: (value) => _validName((value ?? '').trim())
                ? null
                : 'Enter a folder name without slashes.',
          ),
        ),
        onSave: () async {
          if (!validateAndReveal(form)) return false;
          if (folder == null) {
            await _client.from('workspace_folders').insert({
              'scope': _scope,
              'scope_id': _scopeId,
              'parent_id': _parent,
              'name': name.trim(),
            });
          } else {
            await _client
                .from('workspace_folders')
                .update({'name': name.trim()})
                .eq('id', folder['id'])
                .select('id')
                .single();
          }
          return true;
        },
      ),
    );
    if (saved == true && mounted) _refresh();
  }

  Future<void> _upload() => _run(() async {
    final file = await pickWorkspaceFile();
    if (file == null) return;
    final name = file.name.trim();
    final extension = name.split('.').last.toLowerCase();
    final contentType = workspaceFileTypes[extension];
    if (!_validName(name) ||
        name.length > 180 ||
        contentType == null ||
        !name.contains('.')) {
      throw const FormatException(
        'Choose a supported file with a shorter file name.',
      );
    }
    await _storage.uploadBinary(
      '$_prefix/$name',
      file.bytes,
      fileOptions: FileOptions(contentType: contentType, cacheControl: '0'),
    );
    if (mounted) {
      AppNotice.show(context, 'File uploaded.', tone: NoticeTone.success);
    }
  });

  Future<void> _download(String name) => _run(() async {
    final url = await _storage.createSignedUrl(
      '$_prefix/$name',
      60,
      download: DownloadBehavior.named(name),
    );
    if (!await launchUrl(Uri.parse(url), webOnlyWindowName: '_self')) {
      throw const FormatException('The download could not be opened.');
    }
  });

  Future<void> _delete(String name) async {
    final path = '$_prefix/$name';
    final deleted = await confirmWorkspaceAction(
      context,
      title: 'Delete file?',
      subject: name,
      message: widget.projectId == null
          ? 'This permanently deletes the file from your workspace.'
          : 'This permanently deletes the shared file for everyone on the project.',
      action: 'Delete file',
      destructive: true,
      confirmationText: 'DELETE',
      perform: () async {
        final removed = await _storage.remove([path]);
        if (removed.isEmpty) {
          throw const FormatException(
            'The file is missing or you no longer have permission to delete it. Close this dialog and refresh the folder.',
          );
        }
      },
    );
    if (deleted && mounted) {
      _refresh();
      AppNotice.show(context, 'File deleted.', tone: NoticeTone.success);
    }
  }

  Future<void> _move(String currentName, {required bool rename}) async {
    final prefix = _prefix;
    final scopeRoot = '$_scope/$_scopeId';
    final extension = currentName.split('.').last;
    var name = currentName.substring(0, currentName.lastIndexOf('.'));
    var destination = 'root';
    final choices = <String, String>{};
    if (!rename) {
      try {
        final folders = await _client
            .from('workspace_folders')
            .select('id, parent_id, name')
            .eq('scope', _scope)
            .eq('scope_id', _scopeId)
            .order('name', ascending: true)
            .limit(1000);
        final byId = {for (final row in folders) row['id'] as String: row};
        String pathLabel(WorkspaceRow folder) {
          final labels = <String>[folder['name']];
          var parent = byId[folder['parent_id']];
          while (parent != null) {
            labels.add(parent['name']);
            parent = byId[parent['parent_id']];
          }
          return labels.reversed.join(' / ');
        }

        if (_parent != null) choices['root'] = 'Top level';
        for (final folder in folders) {
          final id = folder['id'] as String;
          if (id != _parent) choices[id] = pathLabel(folder);
        }
        if (!mounted) return;
        if (choices.isEmpty) {
          AppNotice.show(context, 'Create another folder to move this file.');
          return;
        }
        destination = choices.keys.first;
      } catch (error) {
        if (mounted) {
          AppNotice.show(
            context,
            workspaceError(error),
            tone: NoticeTone.error,
          );
        }
        return;
      }
    }
    final form = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => WorkspaceDialogForm(
        title: rename ? 'Rename file' : 'Move file',
        action: rename ? 'Save name' : 'Move file',
        child: Form(
          key: form,
          child: rename
              ? TextFormField(
                  initialValue: name,
                  maxLength: 179 - extension.length,
                  decoration: InputDecoration(
                    labelText: 'File name',
                    suffixText: '.$extension',
                    counterText: '',
                  ),
                  onChanged: (value) => name = value,
                  validator: (value) => _validName((value ?? '').trim())
                      ? null
                      : 'Enter a valid file name.',
                )
              : WorkspaceSelect<String>(
                  label: 'Destination folder',
                  initial: destination,
                  choices: choices,
                  onChanged: (value) => destination = value,
                ),
        ),
        onSave: () async {
          if (!validateAndReveal(form)) return false;
          final source = '$prefix/$currentName';
          final target = rename
              ? '$prefix/${name.trim()}.$extension'
              : '$scopeRoot/$destination/$currentName';
          if (source != target) await _storage.move(source, target);
          return true;
        },
      ),
    );
    if (saved == true && mounted) _refresh();
  }

  bool _validName(String name) =>
      name.isNotEmpty &&
      name != '.' &&
      name != '..' &&
      !RegExp(r'[/\\\x00-\x1f\x7f]').hasMatch(name);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 12,
    children: [
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 7,
        runSpacing: 7,
        children: [
          TextButton.icon(
            icon: const Icon(Icons.folder_copy_outlined, size: 17),
            label: Text(
              widget.projectId == null ? 'My files' : 'Project files',
            ),
            onPressed: _busy || _path.isEmpty
                ? null
                : () {
                    _path.clear();
                    _refresh();
                  },
          ),
          for (final (index, folder) in _path.indexed) ...[
            const Icon(Icons.chevron_right, size: 15),
            TextButton(
              onPressed: _busy || index == _path.length - 1
                  ? null
                  : () {
                      _path.removeRange(index + 1, _path.length);
                      _refresh();
                    },
              child: Text(folder['name']),
            ),
          ],
        ],
      ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          WorkshopAction(
            label: 'Upload file',
            icon: Icons.upload_outlined,
            onPressed: _busy ? null : _upload,
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : _folder,
            icon: const Icon(Icons.create_new_folder_outlined, size: 18),
            label: const Text('New folder'),
          ),
          IconButton(
            onPressed: _busy ? null : _refresh,
            tooltip: 'Refresh files',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      Text(
        widget.projectId == null
            ? 'Private to you · Up to 10 MB per file'
            : 'Shared with this project’s team · Up to 10 MB per file',
      ),
      WorkshopGlass(
        child: FutureBuilder(
          future: _items,
          builder: (context, snapshot) {
            if (_busy || snapshot.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.all(14),
                child: SkeletonRows(label: 'Loading files', count: 2),
              );
            }
            if (snapshot.hasError) {
              return ListTile(
                title: Text(workspaceError(snapshot.error!)),
                trailing: TextButton(
                  onPressed: _refresh,
                  child: const Text('Retry'),
                ),
              );
            }
            final items = snapshot.data!;
            if (items.files.isEmpty && items.folders.isEmpty) {
              return const ListTile(
                leading: Icon(Icons.folder_open_outlined),
                title: Text('This folder is empty'),
              );
            }
            return Column(
              children: [
                for (final folder in items.folders)
                  ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(folder['name']),
                    onTap: () {
                      _path.add(folder);
                      _refresh();
                    },
                    trailing: IconButton(
                      onPressed: () => _folder(folder),
                      tooltip: 'Rename folder',
                      icon: const Icon(Icons.edit_outlined, size: 18),
                    ),
                  ),
                for (final file in items.files)
                  ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: Text(file.name),
                    onTap: () => _download(file.name),
                    trailing: PopupMenuButton<String>(
                      tooltip: 'File options',
                      onSelected: (action) {
                        if (action == 'download') _download(file.name);
                        if (action == 'rename') _move(file.name, rename: true);
                        if (action == 'move') _move(file.name, rename: false);
                        if (action == 'delete') _delete(file.name);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'download',
                          child: Text('Download'),
                        ),
                        PopupMenuItem(value: 'rename', child: Text('Rename')),
                        PopupMenuItem(value: 'move', child: Text('Move')),
                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    ],
  );
}
