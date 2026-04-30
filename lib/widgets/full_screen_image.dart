import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../models/assaffal_report.dart';

class FullScreenImage extends StatelessWidget {
  final String imageUrl;
  final String? tag;
  final bool isFile;
  final AssaffalReport? report;

  const FullScreenImage({
    super.key,
    required this.imageUrl,
    this.tag,
    this.isFile = false,
    this.report,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: Hero(
              tag: tag ?? imageUrl,
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    isFile
                        ? Image.file(
                            File(imageUrl),
                            fit: BoxFit.contain,
                          )
                        : CachedNetworkImage(
                            imageUrl: imageUrl,
                            fit: BoxFit.contain,
                            placeholder: (context, url) => const CircularProgressIndicator(color: Colors.white),
                            errorWidget: (context, url, error) => const Icon(Icons.error, color: Colors.white),
                          ),
                    if (report != null) _buildWatermark(),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: CircleAvatar(
                backgroundColor: Colors.black.withOpacity(0.5),
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWatermark() {
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Logo Tengah
            Opacity(
              opacity: 0.7,
              child: Image.asset(
                'assets/images/logo_s_assaffal.png',
                width: 80,
                errorBuilder: (context, error, stackTrace) => const SizedBox(),
              ),
            ),
            const SizedBox(height: 12),
            // Tarikh & Masa
            _buildWatermarkText(
              DateFormat('dd/MM/yyyy HH:mm:ss').format(report!.createdAtMYT),
              fontSize: 14,
            ),
            const SizedBox(height: 4),
            // Coordinates
            _buildWatermarkText(
              report!.coordinates,
              fontSize: 12,
            ),
            const SizedBox(height: 4),
            // Nickname
            _buildWatermarkText(
              'Oleh: ${report!.nickname ?? 'Tanpa Nama'}',
              fontSize: 12,
              isBold: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWatermarkText(String text, {double fontSize = 12, bool isBold = false}) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: Colors.white.withOpacity(0.8),
        fontSize: fontSize,
        fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
        shadows: [
          Shadow(
            blurRadius: 4.0,
            color: Colors.black.withOpacity(0.8),
            offset: const Offset(1.0, 1.0),
          ),
        ],
      ),
    );
  }
}
