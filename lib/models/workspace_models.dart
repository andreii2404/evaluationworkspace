enum ProjectStatus { prototype, recruiting, reviewing, completed }

extension ProjectStatusLabel on ProjectStatus {
  String get label => switch (this) {
    ProjectStatus.prototype => 'In prototype',
    ProjectStatus.recruiting => 'Recruiting testers',
    ProjectStatus.reviewing => 'In review',
    ProjectStatus.completed => 'Completed',
  };

  String get storageValue => name;

  static ProjectStatus fromStorage(String? value) {
    return ProjectStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => ProjectStatus.prototype,
    );
  }
}

class EvaluationProject {
  const EvaluationProject({
    required this.id,
    required this.name,
    required this.category,
    required this.summary,
    required this.status,
    required this.updatedLabel,
    required this.responses,
    required this.responseGoal,
    required this.iconCodePoint,
    required this.accentValue,
  });

  final String id;
  final String name;
  final String category;
  final String summary;
  final ProjectStatus status;
  final String updatedLabel;
  final int responses;
  final int responseGoal;
  final int iconCodePoint;
  final int accentValue;

  double get progress => responseGoal == 0 ? 0 : responses / responseGoal;

  EvaluationProject copyWith({
    String? name,
    String? category,
    String? summary,
    ProjectStatus? status,
    String? updatedLabel,
    int? responses,
    int? responseGoal,
    int? iconCodePoint,
    int? accentValue,
  }) {
    return EvaluationProject(
      id: id,
      name: name ?? this.name,
      category: category ?? this.category,
      summary: summary ?? this.summary,
      status: status ?? this.status,
      updatedLabel: updatedLabel ?? this.updatedLabel,
      responses: responses ?? this.responses,
      responseGoal: responseGoal ?? this.responseGoal,
      iconCodePoint: iconCodePoint ?? this.iconCodePoint,
      accentValue: accentValue ?? this.accentValue,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'category': category,
    'summary': summary,
    'status': status.storageValue,
    'updatedLabel': updatedLabel,
    'responses': responses,
    'responseGoal': responseGoal,
    'iconCodePoint': iconCodePoint,
    'accentValue': accentValue,
  };

  factory EvaluationProject.fromJson(Map<String, Object?> json) {
    return EvaluationProject(
      id:
          json['id'] as String? ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      name: json['name'] as String? ?? 'Untitled project',
      category: json['category'] as String? ?? 'Other',
      summary: json['summary'] as String? ?? '',
      status: ProjectStatusLabel.fromStorage(json['status'] as String?),
      updatedLabel: json['updatedLabel'] as String? ?? 'Just now',
      responses: json['responses'] as int? ?? 0,
      responseGoal: json['responseGoal'] as int? ?? 5,
      iconCodePoint: json['iconCodePoint'] as int? ?? 0xe8b6,
      accentValue: json['accentValue'] as int? ?? 0xFF635BDB,
    );
  }
}

class EvaluatorProfile {
  const EvaluatorProfile({
    required this.id,
    required this.name,
    required this.role,
    required this.location,
    required this.initials,
    required this.specialties,
    required this.signals,
    required this.completedReviews,
    required this.responseTime,
    required this.accentValue,
  });

  final String id;
  final String name;
  final String role;
  final String location;
  final String initials;
  final List<String> specialties;
  final List<String> signals;
  final int completedReviews;
  final String responseTime;
  final int accentValue;
}

class ReviewTask {
  const ReviewTask({
    required this.id,
    required this.title,
    required this.projectName,
    required this.projectId,
    required this.kind,
    required this.dueLabel,
    required this.status,
    required this.reviewerName,
    required this.initials,
    required this.accentValue,
  });

  final String id;
  final String title;
  final String projectName;
  final String projectId;
  final String kind;
  final String dueLabel;
  final String status;
  final String reviewerName;
  final String initials;
  final int accentValue;
}

class LocalInvitation {
  const LocalInvitation({
    required this.id,
    required this.evaluatorName,
    required this.projectName,
    required this.createdLabel,
    required this.status,
  });

  final String id;
  final String evaluatorName;
  final String projectName;
  final String createdLabel;
  final String status;

  Map<String, Object?> toJson() => {
    'id': id,
    'evaluatorName': evaluatorName,
    'projectName': projectName,
    'createdLabel': createdLabel,
    'status': status,
  };

  factory LocalInvitation.fromJson(Map<String, Object?> json) {
    return LocalInvitation(
      id: json['id'] as String? ?? '',
      evaluatorName: json['evaluatorName'] as String? ?? 'Evaluator',
      projectName: json['projectName'] as String? ?? 'Project',
      createdLabel: json['createdLabel'] as String? ?? 'Just now',
      status: json['status'] as String? ?? 'Sent',
    );
  }
}

class LocalReviewResponse {
  const LocalReviewResponse({
    required this.id,
    required this.projectName,
    required this.evaluatorName,
    required this.rating,
    required this.comment,
    required this.createdLabel,
  });

  final String id;
  final String projectName;
  final String evaluatorName;
  final int rating;
  final String comment;
  final String createdLabel;

  Map<String, Object?> toJson() => {
    'id': id,
    'projectName': projectName,
    'evaluatorName': evaluatorName,
    'rating': rating,
    'comment': comment,
    'createdLabel': createdLabel,
  };

  factory LocalReviewResponse.fromJson(Map<String, Object?> json) {
    return LocalReviewResponse(
      id: json['id'] as String? ?? '',
      projectName: json['projectName'] as String? ?? 'Project',
      evaluatorName: json['evaluatorName'] as String? ?? 'You',
      rating: json['rating'] as int? ?? 0,
      comment: json['comment'] as String? ?? '',
      createdLabel: json['createdLabel'] as String? ?? 'Just now',
    );
  }
}
