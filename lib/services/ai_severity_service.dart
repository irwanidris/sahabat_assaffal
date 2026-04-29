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
      // Tingkatkan tahap keyakinan minimum kepada 0.5 untuk mengurangkan laporan palsu
      final options = ImageLabelerOptions(confidenceThreshold: 0.5);
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

  // Pengesahan Imej yang lebih ketat mengikut Kategori
  Future<ValidationResult> validateImageByCategory(File imageFile, String category) async {
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

      List<String> contextKeywords = [];
      List<String> damageKeywords = ['hole', 'damage', 'broken', 'hazard', 'crack', 'pitted', 'dent', 'cavity'];
      
      if (category == 'Lubang Jalan') {
        contextKeywords = ['road', 'asphalt', 'pavement', 'street', 'concrete', 'highway', 'tar'];
      } else if (category == 'Longkang Tersumbat') {
        contextKeywords = ['water', 'drain', 'gutter', 'ditch', 'flood', 'ground', 'culvert'];
      } else if (category == 'Lampu Jalan Padam') {
        contextKeywords = ['light', 'pole', 'lamp', 'electricity', 'tower', 'sky', 'night'];
      } else if (category == 'Sampah Sarap') {
        contextKeywords = ['trash', 'waste', 'plastic', 'bag', 'bottle', 'litter', 'garbage'];
      } else if (category == 'Pokok Tumbang') {
        contextKeywords = ['tree', 'branch', 'wood', 'plant', 'leaf', 'nature', 'log'];
      }

      bool hasContext = false;
      bool hasDamage = false;
      String detectedAs = '';

      for (final label in labels) {
        final labelLower = label.label.toLowerCase();
        
        // Semak konteks (cth: adakah ini jalan?)
        for (final cw in contextKeywords) {
          if (labelLower.contains(cw)) {
            hasContext = true;
            detectedAs = label.label;
          }
        }
        
        // Semak kerosakan (cth: adakah ada lubang/rosak?)
        for (final dw in damageKeywords) {
          if (labelLower.contains(dw)) {
            hasDamage = true;
          }
        }
      }

      if (labels.isEmpty) {
        return ValidationResult(
          isValid: false,
          message: 'Imej terlalu kabur atau tidak dapat dikenal pasti.',
          details: 'Sila ambil foto yang lebih jelas dan dekat.',
        );
      }

      // Syarat Khas untuk Lubang Jalan: Mesti ada konteks jalan DAN tanda kerosakan
      if (category == 'Lubang Jalan') {
        if (!hasContext) {
          return ValidationResult(
            isValid: false,
            message: 'Imej ini tidak dikesan sebagai jalan raya.',
            details: 'Pastikan gambar menunjukkan permukaan jalan dengan jelas.',
          );
        }
        if (!hasDamage) {
          return ValidationResult(
            isValid: false,
            message: 'Tiada kerosakan atau lubang dikesan dalam imej.',
            details: 'AI tidak menemui tanda lubang. Sila pastikan lubang nampak jelas.',
          );
        }
      } else {
        // Untuk kategori lain, memadai jika ada konteks sahaja buat masa ini
        if (!hasContext) {
          return ValidationResult(
            isValid: false,
            message: 'Imej tidak sepadan dengan kategori $category.',
            details: 'Sila pastikan subjek aduan nampak jelas.',
          );
        }
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
      case 'critical': return const Color(0xFFE53935); // Merah
      case 'high': return const Color(0xFFFF5722);     // Merah-Jingga
      case 'medium': return const Color(0xFFFF9800);   // Jingga
      default: return const Color(0xFF4CAF50);         // Hijau
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
