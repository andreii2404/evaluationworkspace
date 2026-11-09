import 'package:supabase_flutter/supabase_flutter.dart';

typedef WorkspaceRow = Map<String, dynamic>;

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

  Future<void> createProject(WorkspaceRow values) async {
    await client.from('projects').insert(values);
  }

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
    String feedback,
  ) async {
    await client.from('reviews').insert({
      'assignment_id': assignmentId,
      'scores': scores,
      'feedback': feedback,
      'no_conflict': true,
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
