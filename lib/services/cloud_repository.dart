import 'dart:math';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'questionnaire_data.dart';

typedef WorkspaceRow = Map<String, dynamic>;
typedef QuestionnaireFile = ({String name, Uint8List bytes});

const questionnaireSources = {
  'website-iso25010-v1': (
    name: 'ISO/IEC 25010:2023',
    url: 'https://www.iso.org/standard/78176.html',
  ),
  'mobile-mars-v1': (
    name: 'MARS study and original form',
    url: 'https://mhealth.jmir.org/2015/1/e27/',
  ),
};

bool hasQuestionnaire(WorkspaceRow project) =>
    project['questionnaire_form'] != null ||
    project['rubric_id'] != null ||
    project['custom_questions'] != null ||
    project['questionnaire_url'] != null ||
    project['questionnaire_file_path'] != null;

const evaluatorTypes = {
  'peer': 'Peer reviewer',
  'professional': 'Professional',
  'community': 'Community evaluator',
};

class WorkspaceData {
  const WorkspaceData(
    this.profile,
    this.projects,
    this.community,
    this.directory,
    this.assignments,
    this.reviews,
    this.reports,
  );
  final WorkspaceRow profile;
  final List<WorkspaceRow> projects,
      community,
      directory,
      assignments,
      reviews,
      reports;

  WorkspaceRow? reviewFor(String assignmentId) {
    for (final review in reviews) {
      if (review['assignment_id'] == assignmentId) return review;
    }
    return null;
  }
}

class CloudRepository {
  CloudRepository(this.client, this.userId);
  final SupabaseClient client;
  final String userId;

  bool get isModerator =>
      client.auth.currentUser?.appMetadata['evalink_moderator'] == true;

  Future<WorkspaceData> load() async {
    final profileFuture = client
        .from('profiles')
        .select()
        .eq('id', userId)
        .single();
    final showReports = isModerator;
    final batches = await Future.wait([
      profileFuture.then((profile) => [profile]),
      client
          .from('projects')
          .select()
          .eq('creator_id', userId)
          .order('created_at')
          .limit(100),
      client
          .from('projects')
          .select()
          .eq('visibility', 'community')
          .neq('creator_id', userId)
          .order('created_at')
          .limit(100),
      client
          .from('profiles')
          .select()
          .eq('directory_visible', true)
          .neq('id', userId)
          .order('display_name', ascending: true)
          .limit(100),
      client
          .from('review_assignments')
          .select(
            '*, projects(*), evaluator:profiles!review_assignments_evaluator_id_fkey(display_name)',
          )
          .order('requested_at')
          .limit(100),
      client.from('reviews').select().order('created_at').limit(100),
      if (showReports)
        client
            .from('project_reports')
            .select('*, projects(title)')
            .eq('status', 'open')
            .order('created_at')
            .limit(100),
    ]);
    return WorkspaceData(
      batches[0].single,
      batches[1],
      batches[2],
      batches[3],
      batches[4],
      batches[5],
      showReports ? batches[6] : const [],
    );
  }

  Future<List<WorkspaceRow>> rubrics() async =>
      await client.from('rubrics').select().order('name', ascending: true);

  Future<List<WorkspaceRow>> criteria(String rubric) async => await client
      .from('rubric_criteria')
      .select()
      .eq('rubric_id', rubric)
      .order('position', ascending: true);

  Future<List<WorkspaceRow>> projectCriteria(WorkspaceRow project) async {
    if (projectQuestionnaire(project) case final form?) {
      return [
        for (final (index, item) in form.items.indexed)
          {
            'criterion_key': 'form_${index + 1}',
            'label': item.prompt,
            'prompt': item.prompt,
            'section': item.section,
          },
      ];
    }
    if (project['rubric_id'] case final String rubric) return criteria(rubric);
    if (project['custom_questions'] case final List<dynamic> questions) {
      return [
        for (final (index, question) in questions.indexed)
          {
            'criterion_key': 'custom_${index + 1}',
            'label': 'Question ${index + 1}',
            'prompt': question as String,
          },
      ];
    }
    return const [];
  }

  StorageFileApi get _questionnaireFiles =>
      client.storage.from('project-questionnaires');

  Future<List<QuestionnaireChoice>> savedQuestionnaires() async {
    final rows = await client
        .from('saved_questionnaires')
        .select()
        .order('created_at');
    return rows.map(QuestionnaireChoice.fromRow).toList();
  }

  Future<void> saveQuestionnaire(QuestionnaireForm form, {String? id}) async {
    final table = client.from('saved_questionnaires');
    final data = {'title': form.title, 'form': form.toJson()};
    if (id == null) {
      await table.insert(data);
    } else {
      await table.update(data).eq('id', id).select('id').single();
    }
  }

  Future<void> saveQuestionnaireFile(QuestionnaireFile file) =>
      _attachQuestionnaire(file, (path) async {
        final title = file.name.substring(0, file.name.lastIndexOf('.')).trim();
        await client.from('saved_questionnaires').insert({
          'title': title.isEmpty
              ? 'Questionnaire'
              : String.fromCharCodes(title.runes.take(120)),
          'file_path': path,
          'file_name': file.name,
        });
      });

  Future<void> createProject(
    WorkspaceRow values, {
    QuestionnaireFile? questionnairePdf,
  }) async {
    if (questionnairePdf == null) {
      await client.from('projects').insert(values);
      return;
    }

    await _attachQuestionnaire(questionnairePdf, (path) async {
      await client.from('projects').insert({
        ...values,
        'questionnaire_file_path': path,
        'questionnaire_file_name': questionnairePdf.name,
      });
    });
  }

  Future<void> _attachQuestionnaire(
    QuestionnaireFile file,
    Future<void> Function(String path) save,
  ) async {
    final isWord = file.name.toLowerCase().endsWith('.docx');
    final random = Random.secure();
    final id = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final path = '$userId/$id.${isWord ? 'docx' : 'pdf'}';
    try {
      await _questionnaireFiles.uploadBinary(
        path,
        file.bytes,
        fileOptions: FileOptions(
          contentType: isWord
              ? 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
              : 'application/pdf',
        ),
      );
      await save(path);
    } catch (_) {
      try {
        await _questionnaireFiles.remove([path]);
      } catch (_) {
        // Preserve the original error if cleanup fails.
      }
      rethrow;
    }
  }

  Future<String> questionnaireDownloadUrl(String path) =>
      _questionnaireFiles.createSignedUrl(
        path,
        60,
        download: DownloadBehavior.named(
          'questionnaire.${path.split('.').last}',
        ),
      );

  Future<void> setVisibility(String projectId, bool community) async {
    await client
        .from('projects')
        .update({'visibility': community ? 'community' : 'private'})
        .eq('id', projectId)
        .select('id')
        .single();
  }

  Future<void> saveProfile(WorkspaceRow values) async {
    await client
        .from('profiles')
        .update(values)
        .eq('id', userId)
        .select('id')
        .single();
  }

  Future<void> invite(String projectId, String evaluatorId) async {
    await client.from('review_assignments').insert({
      'project_id': projectId,
      'evaluator_id': evaluatorId,
    });
  }

  Future<void> respond(String assignmentId, bool accept) async {
    await client
        .from('review_assignments')
        .update({'status': accept ? 'accepted' : 'declined'})
        .eq('id', assignmentId)
        .eq('status', 'invited')
        .select('id')
        .single();
  }

  Future<void> submitReview(
    String assignmentId,
    Map<String, int> scores,
    String feedback, {
    List<String> respondentDetails = const [],
  }) async {
    await client.from('reviews').insert({
      'assignment_id': assignmentId,
      'scores': scores,
      'feedback': feedback,
      'no_conflict': true,
      'respondent_details': respondentDetails,
    });
  }

  Future<void> report(String projectId, String reason) async {
    await client.from('project_reports').insert({
      'project_id': projectId,
      'reason': reason,
    });
  }

  Future<void> moderate(String reportId, String status) async {
    await client
        .from('project_reports')
        .update({'status': status})
        .eq('id', reportId)
        .eq('status', 'open')
        .select('id')
        .single();
  }
}

String workspaceError(Object error) => switch (error) {
  AuthException(:final message) => message,
  PostgrestException(code: '23505') => 'This action has already been recorded.',
  PostgrestException(code: 'PGRST116' || '42501') =>
    'This action is no longer available.',
  _ => 'Something went wrong. Please try again.',
};
