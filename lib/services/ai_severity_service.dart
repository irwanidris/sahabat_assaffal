import 'dart:io';
import 'dart:ui' show Color;
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:flutter/foundation.dart';

class AISeverityService {
  static final AISeverityService _instance = AISeverityService._internal();
  factory AISeverityService() => _instance;
  AISeverityService._internal();

  ImageLabeler? _imageLabeler;

  Future<void> initialize() async {
    if (_imageLabeler == null) {
      final options = ImageLabelerOptions(confidenceThreshold: 0.4);
      _imageLabeler = ImageLabeler(options: options);
    }
  }

  // Analisis Tahap Bahaya mengikut Kategori
  Future<SeverityResult> analyzeSeverity(File imageFile, String category) async {
    try {
      await initialize();
      final inputImage = InputImage.fromFile(imageFile);
      final labels = await _imageLabeler!.processImage(inputImage);
      
      return _determineSeverity(labels, category);
    } catch (e) {
      return SeverityResult(
        severity: 'medium',
        confidence: 0.0,
        details: 'Gagal menganalisis imej',
        labels: [],
      );
    }
  }

  SeverityResult _determineSeverity(List<ImageLabel> labels, String category) {
    const criticalKeywords = ['hole', 'damage', 'broken', 'danger', 'hazard', 'waste', 'flood', 'overflow'];
    
    int score = 0;
    double maxConfidence = 0.0;
    final detectedLabels = <String>[];
    
    for (final label in labels) {
      final labelLower = label.label.toLowerCase();
      detectedLabels.add('${label.label} (${(label.confidence * 100).toInt()}%)');
      
      if (label.confidence > maxConfidence) maxConfidence = label.confidence;

      for (final keyword in criticalKeywords) {
        if (labelLower.contains(keyword)) score += (label.confidence * 100).toInt();
      }
    }

    String severity;
    String details;
    
    if (score > 40) {
      severity = 'critical';
      details = 'Masalah serius dikesan - perlukan tindakan segera';
    } else if (score > 15) {
      severity = 'high';
      details = 'Kerosakan/gangguan ketara dikesan';
    } else {
      severity = 'medium';
      details = 'Masalah tahap sederhana';
    }

    return SeverityResult(
      severity: severity,
      confidence: maxConfidence,
      details: details,
      labels: detectedLabels,
    );
  }

  // Pengesahan Imej yang lebih fleksibel mengikut Kategori
  Future<ValidationResult> validateImageByCategory(File imageFile, String category) async {
    // JIKA KATEGORI ADALAH 'Lain-lain', KITA KOSONGKAN SEBARANG SEKATAN (RESTRICTION)
    if (category == 'Lain-lain') {
      return ValidationResult(
        isValid: true,
        message: 'Kategori Lain-lain: Tiada sekaran AI ✓',
        details: 'Meneruskan laporan tanpa pengesahan imej.',
      );
    }

    try {
      await initialize();
      final inputImage = InputImage.fromFile(imageFile);
      final labels = await _imageLabeler!.processImage(inputImage);

      List<String> validKeywords = [];
      
      if (category == 'Lubang Jalan' || category == 'Longkang Tersumbat') {
        validKeywords = ['road', 'asphalt', 'pavement', 'street', 'concrete', 'water', 'drain', 'ground'];
      } else if (category == 'Lampu Jalan Padam') {
        validKeywords = ['light', 'pole', 'sky', 'night', 'lamp', 'electricity', 'tower'];
      } else if (category == 'Sampah Sarap') {
        validKeywords = ['trash', 'waste', 'plastic', 'bag', 'bottle', 'litter', 'ground', 'environment'];
      } else if (category == 'Pokok Tumbang') {
        validKeywords = ['tree', 'branch', 'wood', 'plant', 'leaf', 'nature', 'forest', 'road'];
      }

      bool isValid = false;
      String detectedAs = '';

      for (final label in labels) {
        final labelLower = label.label.toLowerCase();
        for (final kw in validKeywords) {
          if (labelLower.contains(kw)) {
            isValid = true;
            detectedAs = label.label;
            break;
          }
        }
        if (isValid) break;
      }

      if (labels.isEmpty) {
        return ValidationResult(
          isValid: false,
          message: 'Imej terlalu kabur atau gelap untuk dikenal pasti.',
          details: 'Sila ambil foto yang lebih jelas.',
        );
      }

      if (!isValid) {
        return ValidationResult(
          isValid: false,
          message: 'Imej ini tidak kelihatan seperti aduan $category.',
          details: 'Pastikan subjek aduan nampak jelas dalam foto.',
        );
      }

      return ValidationResult(
        isValid: true,
        message: 'Imej disahkan: $detectedAs ✓',
        details: 'Imej sesuai dengan kategori $category.',
      );
      
    } catch (e) {
      return ValidationResult(isValid: true, message: 'Langkau ralat AI', details: 'Meneruskan laporan...');
    }
  }

  static Color getSeverityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical': return const Color(0xFFE53935);
      case 'high': return const Color(0xFFFF9800);
      case 'medium': return const Color(0xFFFFC107);
      default: return const Color(0xFF4CAF50);
    }
  }

  static String getSeverityEmoji(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical': return '🚨';
      case 'high': return '⚠️';
      case 'medium': return '⚡';
      default: return '✅';
    }
  }
}

class ValidationResult {
  final bool isValid;
  final String message;
  final String details;
  ValidationResult({required this.isValid, required this.message, required this.details});
}

class SeverityResult {
  final String severity;
  final double confidence;
  final String details;
  final List<String> labels;
  SeverityResult({required this.severity, required this.confidence, required this.details, required this.labels});
}
