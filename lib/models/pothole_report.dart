import 'package:equatable/equatable.dart';

class PotholeReport extends Equatable {
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
  final String? reportCode; // AA0001
  final String? resolvedBy;
  final String? department;
  final String? assignedTo; // ID Moderator yang sedang memproses
  final String? assignedName; // Nama Moderator yang sedang memproses
  
  // New gamification/community fields
  final String? deviceId;
  final String severity; // 'low', 'medium', 'high', 'critical'
  final int upvoteCount;
  final int commentCount;
  final int shareCount;

  // Added integrity fields
  final String category;
  final String? reporterName;
  final String? reporterContact;
  final int editCount;

  const PotholeReport({
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
    this.severity = 'medium',
    this.upvoteCount = 0,
    this.commentCount = 0,
    this.shareCount = 0,
    this.category = 'Lubang Jalan',
    this.reporterName,
    this.reporterContact,
    this.editCount = 0,
  });

  factory PotholeReport.fromJson(Map<String, dynamic> json) {
    return PotholeReport(
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
      severity: json['severity'] ?? 'medium',
      upvoteCount: json['upvote_count'] ?? 0,
      commentCount: json['comment_count'] ?? 0,
      shareCount: json['share_count'] ?? 0,
      category: json['category'] ?? 'Lubang Jalan',
      reporterName: json['reporter_name'],
      reporterContact: json['reporter_contact'],
      editCount: json['edit_count'] ?? 0,
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
      'severity': severity,
      'category': category,
      'reporter_name': reporterName,
      'reporter_contact': reporterContact,
      'edit_count': editCount,
    };
  }

  bool canEdit() {
    final now = DateTime.now();
    final difference = now.difference(createdAt);
    return difference.inHours < 24 && editCount < 2;
  }

  bool canDelete() {
    final now = DateTime.now();
    final difference = now.difference(createdAt);
    return difference.inHours < 24;
  }

  // Check if user has upvoted this report
  bool isOwnReport(String? currentDeviceId) {
    return deviceId != null && deviceId == currentDeviceId;
  }

  @override
  List<Object?> get props => [id, imageUrl, latitude, longitude, status, upvoteCount, category];

  // Helper for Malaysia Time (GMT+8)
  DateTime get createdAtMYT => createdAt.toUtc().add(const Duration(hours: 8));
}
