import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../data/sample_data.dart';
import '../models/workspace_models.dart';

/// Browser-local workspace storage for the first web prototype.
///
/// Replace this repository with an authenticated API repository when shared,
/// cross-device data and real evaluator accounts are introduced.
class WorkspaceRepository {
  WorkspaceRepository({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const _projectsKey = 'evalink.projects.v1';
  static const _invitationsKey = 'evalink.invitations.v1';
  static const _responsesKey = 'evalink.responses.v1';

  final SharedPreferencesAsync _preferences;

  Future<List<EvaluationProject>> loadProjects() async {
    final raw = await _preferences.getString(_projectsKey);
    if (raw == null) return sampleProjects;

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(EvaluationProject.fromJson)
          .toList();
    } on FormatException {
      return sampleProjects;
    } on TypeError {
      return sampleProjects;
    }
  }

  Future<void> saveProjects(List<EvaluationProject> projects) async {
    final encoded = jsonEncode(
      projects.map((project) => project.toJson()).toList(),
    );
    await _preferences.setString(_projectsKey, encoded);
  }

  Future<List<LocalInvitation>> loadInvitations() async {
    return _loadList(_invitationsKey, LocalInvitation.fromJson);
  }

  Future<void> saveInvitations(List<LocalInvitation> invitations) async {
    await _saveList(
      _invitationsKey,
      invitations.map((item) => item.toJson()).toList(),
    );
  }

  Future<List<LocalReviewResponse>> loadResponses() async {
    return _loadList(_responsesKey, LocalReviewResponse.fromJson);
  }

  Future<void> saveResponses(List<LocalReviewResponse> responses) async {
    await _saveList(
      _responsesKey,
      responses.map((item) => item.toJson()).toList(),
    );
  }

  Future<List<T>> _loadList<T>(
    String key,
    T Function(Map<String, Object?>) fromJson,
  ) async {
    final raw = await _preferences.getString(key);
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map((value) => fromJson(value))
          .toList();
    } on FormatException {
      return const [];
    } on TypeError {
      return const [];
    }
  }

  Future<void> _saveList(String key, List<Map<String, Object?>> values) async {
    await _preferences.setString(key, jsonEncode(values));
  }

  Future<void> resetLocalWorkspace() async {
    await _preferences.clear(
      allowList: {_projectsKey, _invitationsKey, _responsesKey},
    );
  }
}
