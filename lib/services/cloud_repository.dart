import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'questionnaire_data.dart';

typedef WorkspaceRow = Map<String, dynamic>;
typedef QuestionnaireFile = ({String name, Uint8List bytes});

const workspaceSessionEndedMessage =
    'Your session ended. Please sign in again.';

class _ProfileMissing implements Exception {
  const _ProfileMissing();
}

bool workspaceSessionEnded(Object? error) => switch (error) {
  _ProfileMissing() || AuthSessionMissingException() => true,
  AuthException(
    code: 'user_not_found' ||
        'session_not_found' ||
        'session_expired' ||
        'session_missing' ||
        'refresh_token_not_found' ||
        'bad_jwt' ||
        'invalid_jwt',
  ) =>
    true,
  PostgrestException(code: 'PGRST301' || 'PGRST303') => true,
  _ => false,
};

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

bool hasNativeQuestionnaire(WorkspaceRow project) =>
    project['questionnaire_form'] != null ||
    project['rubric_id'] != null ||
    project['custom_questions'] != null;

const evaluatorTypes = {
  'peer': 'Peer reviewer',
  'professional': 'Professional',
  'community': 'Community evaluator',
};

const professions = {
  'student': 'Student',
  'educator': 'Educator',
  'researcher': 'Researcher',
  'it_expert': 'IT expert',
  'subject_expert': 'Subject matter expert',
  'industry_professional': 'Industry professional',
  'independent_creator': 'Independent creator',
  'other': 'Other',
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

  Future<WorkspaceRow> loadProfile() async {
    final profiles = await client
        .from('profiles')
        .select()
        .eq('id', userId)
        .limit(1)
        .timeout(const Duration(seconds: 12));
    final profile = profiles.firstOrNull;
    if (profile == null) throw const _ProfileMissing();
    return profile;
  }

  Future<void> finishWalkthrough() async {
    await client
        .from('profiles')
        .update({'walkthrough_finished': true})
        .eq('id', userId)
        .select('id')
        .single();
  }

  Future<WorkspaceData> load({WorkspaceRow? initialProfile}) async {
    final showReports = isModerator;
    final batches = await Future.wait([
      if (initialProfile == null)
        loadProfile().then((profile) => [profile])
      else
        Future.value([initialProfile]),
      client
          .from('projects')
          .select('*, team:project_collaborators!left(member_id)')
          .eq('team.member_id', userId)
          .or('creator_id.eq.$userId,team.not.is.null')
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
            '*, projects(*), round:project_review_rounds(label,artifact_url), '
            'evaluator:profiles!review_assignments_evaluator_id_fkey(display_name)',
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

  Future<List<WorkspaceRow>> memberConnections() => client
      .from('member_connections')
      .select(
        'id,requester_id,recipient_id,status,'
        'requester:profiles!member_connections_requester_id_fkey(id,display_name,profession,headline),'
        'recipient:profiles!member_connections_recipient_id_fkey(id,display_name,profession,headline)',
      )
      .order('created_at');

  Future<void> requestConnection(String memberId) async {
    await client.from('member_connections').insert({'recipient_id': memberId});
  }

  Future<void> acceptConnection(String connectionId) async {
    await client
        .from('member_connections')
        .update({'status': 'accepted'})
        .eq('id', connectionId)
        .select('id')
        .single();
  }

  Future<void> removeConnection(String connectionId) async {
    await client
        .from('member_connections')
        .delete()
        .eq('id', connectionId)
        .select('id')
        .single();
  }

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

  Future<WorkspaceRow> completeOnboarding(WorkspaceRow values) async {
    final updated = await client
        .from('profiles')
        .update({...values, 'onboarding_completed': true})
        .eq('id', userId)
        .eq('onboarding_completed', false)
        .select();
    return updated.firstOrNull ?? await loadProfile();
  }

  Future<void> invite(
    String projectId,
    String evaluatorId, {
    String? roundId,
  }) async {
    await client.from('review_assignments').insert({
      'project_id': projectId,
      'evaluator_id': evaluatorId,
      'round_id': ?roundId,
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

  Future<void> submitCommunityEvaluation(
    String projectId,
    QuestionnaireForm? form,
    Map<String, int> scores,
    String feedback,
    List<String> details,
  ) async {
    try {
      await client.rpc(
        'submit_community_evaluation',
        params: {
          'p_project': projectId,
          'p_form': form?.toJson(),
          'p_scores': scores,
          'p_feedback': feedback,
          'p_details': details,
        },
      );
    } on PostgrestException catch (error) {
      if (error.code == 'P0001') throw FormatException(error.message);
      rethrow;
    }
  }

  Future<void> updateProjectQuestionnaire(
    String projectId,
    QuestionnaireForm form,
  ) async {
    try {
      await client.rpc(
        'update_project_questionnaire',
        params: {'p_project': projectId, 'p_form': form.toJson()},
      );
    } on PostgrestException catch (error) {
      if (error.code == 'P0001') throw FormatException(error.message);
      rethrow;
    }
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
  _ when workspaceSessionEnded(error) => workspaceSessionEndedMessage,
  FormatException(:final message) => message,
  TimeoutException() ||
  http.ClientException() ||
  AuthRetryableFetchException() =>
    'Couldn’t connect. Check your connection and try again.',
  AuthException(code: 'email_not_confirmed') =>
    'Confirm your email using the link in your inbox, then sign in again.',
  AuthException(
    code: 'over_request_rate_limit' || 'over_email_send_rate_limit',
  ) =>
    'Too many attempts. Wait a moment and try again.',
  AuthException(:final message) => message,
  PostgrestException(code: '23505') => 'This action has already been recorded.',
  PostgrestException(code: 'PGRST116' || '42501') =>
    'This action is no longer available.',
  _ => 'Something went wrong. Please try again.',
};
