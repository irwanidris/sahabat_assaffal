import 'package:equatable/equatable.dart';

class AssaffalReport extends Equatable {
  final String id;
  final String imageUrl;
  final String? resolvedImageUrl;
  final double latitude;
  final double longitude;
  final String? address;
  final String? areaName;
  final String? description;
  final String? duration;
  final String status;
  final DateTime createdAt;
  final String? reportCode; // TK0001
  final String? resolvedBy;
  final String? department;
  final String? assignedTo; // ID Moderator yang sedang memproses
  final String? assignedName; // Nama Moderator yang sedang memproses
  final DateTime? deletedAt; // For soft delete
  
  // New gamification/community fields
  final String? deviceId;
  final String? userId;
  final String severity; // 'low', 'medium', 'high', 'critical'
  final int upvoteCount;
  final int commentCount;
  final int shareCount;
  
  // Waze-style Community Verification
  final int verifiedStillExists;
  final int verifiedResolved;
  final int verifiedFake;

  // Added integrity fields
  final String category;
  final String? reporterName;
  final String? reporterContact;
  final String? nickname;
  final String? reporterNickname; // From device_users join
  final String? reporterAvatar;   // From device_users join
  final int editCount;

  const AssaffalReport({
    required this.id,
    required this.imageUrl,
    this.resolvedImageUrl,
    required this.latitude,
    required this.longitude,
    this.address,
    this.areaName,
    this.description,
    this.duration,
    required this.status,
    required this.createdAt,
    this.reportCode,
    this.resolvedBy,
    this.department,
    this.assignedTo,
    this.assignedName,
    this.deviceId,
    this.userId,
    this.severity = 'medium',
    this.upvoteCount = 0,
    this.commentCount = 0,
    this.shareCount = 0,
    this.verifiedStillExists = 0,
    this.verifiedResolved = 0,
    this.verifiedFake = 0,
    this.category = 'Lubang Jalan',
    this.reporterName,
    this.reporterContact,
    this.nickname,
    this.reporterNickname,
    this.reporterAvatar,
    this.editCount = 0,
    this.deletedAt,
  });

  factory AssaffalReport.fromJson(Map<String, dynamic> json) {
    return AssaffalReport(
      id: json['id'].toString(),
      imageUrl: json['image_url'] ?? '',
      resolvedImageUrl: json['resolved_image_url'],
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      address: json['address'],
      areaName: json['area_name'],
      description: json['description'],
      duration: json['duration'],
      status: json['status'] ?? 'pending',
      createdAt: DateTime.parse(json['created_at']),
      reportCode: json['report_code'],
      resolvedBy: json['resolved_by_name'],
      department: json['department'],
      assignedTo: json['assigned_to'],
      assignedName: json['assigned_name'],
      deviceId: json['device_id'],
      userId: json['user_id'],
      severity: json['severity'] ?? 'medium',
      upvoteCount: json['upvote_count'] ?? 0,
      commentCount: json['comment_count'] ?? 0,
      shareCount: json['share_count'] ?? 0,
      verifiedStillExists: json['verified_still_exists'] ?? 0,
      verifiedResolved: json['verified_resolved'] ?? 0,
      verifiedFake: json['verified_fake'] ?? 0,
      category: json['category'] ?? 'Lubang Jalan',
      reporterName: json['reporter_name'],
      reporterContact: json['reporter_contact'],
      nickname: json['nickname'],
      reporterNickname: json['reporter_nickname'],
      reporterAvatar: json['reporter_avatar'],
      editCount: json['edit_count'] ?? 0,
      deletedAt: json['deleted_at'] != null ? DateTime.parse(json['deleted_at']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'image_url': imageUrl,
      'resolved_image_url': resolvedImageUrl,
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
      'area_name': areaName,
      'description': description,
      'duration': duration,
      'status': status,
      'report_code': reportCode,
      'resolved_by_name': resolvedBy,
      'department': department,
      'assigned_to': assignedTo,
      'assigned_name': assignedName,
      'device_id': deviceId,
      'user_id': userId,
      'severity': severity,
      'category': category,
      'reporter_name': reporterName,
      'reporter_contact': reporterContact,
      'nickname': nickname,
      'edit_count': editCount,
      'deleted_at': deletedAt?.toIso8601String(),
    };
  }

  bool isSoftDeleted() {
    return deletedAt != null;
  }

  bool canRestore() {
    if (deletedAt == null) return false;
    final now = DateTime.now();
    final difference = now.difference(deletedAt!);
    return difference.inDays < 3;
  }

  bool canEdit() {
    return editCount < 5; // Dibenarkan edit sehingga 5 kali tanpa had masa
  }

  bool canDelete() {
    return true; // Sentiasa dibenarkan padam laporan sendiri
  }

  // Check if user has upvoted this report
  bool isOwnReport(String? currentUserId, {String? currentDeviceId}) {
    if (userId != null && currentUserId != null) {
      return userId == currentUserId;
    }
    return deviceId != null && deviceId == currentDeviceId;
  }

  @override
  List<Object?> get props => [id, imageUrl, latitude, longitude, status, upvoteCount, category, nickname];

  // Helper for Malaysia Time (GMT+8)
  DateTime get createdAtMYT => createdAt.toUtc().add(const Duration(hours: 8));

  // Getter for coordinates
  String get coordinates => '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';

  // Image helpers
  List<String> get allImages => imageUrl.split(',').where((s) => s.isNotEmpty).toList();
  String get firstImage => allImages.isNotEmpty ? allImages[0] : '';
}
