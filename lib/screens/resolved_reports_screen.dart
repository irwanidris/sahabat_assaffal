import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/pothole_report.dart';
import '../theme/app_theme.dart';
import 'edit_report_screen.dart';

class ResolvedReportsScreen extends StatelessWidget {
  final List<PotholeReport> reports;
  final bool isAdmin;
  final bool isYB;

  const ResolvedReportsScreen({
    super.key,
    required this.reports,
    required this.isAdmin,
    required this.isYB,
  });

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDarkMode ? AppTheme.darkBackground : AppTheme.lightBackground,
      appBar: AppBar(
        title: const Text('Laporan Selesai', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: reports.isEmpty
          ? const Center(child: Text('Tiada laporan selesai.'))
          : ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: reports.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final report = reports[index];
                final String firstImageUrl = report.imageUrl.split(',').first;
                final String? resolvedImageUrl = report.resolvedImageUrl;

                return Card(
                  color: Colors.red.shade900.withOpacity(0.8),
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      _showComparisonDialog(context, report);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: ListTile(
                        leading: Stack(
                          children: [
                            Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(11),
                                child: (resolvedImageUrl ?? firstImageUrl).isNotEmpty
                                    ? Image.network(
                                        resolvedImageUrl ?? firstImageUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white70),
                                      )
                                    : const Icon(Icons.image, color: Colors.white70),
                              ),
                            ),
                            if (resolvedImageUrl != null)
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: const BoxDecoration(
                                    color: Colors.green,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.check, size: 10, color: Colors.white),
                                ),
                              ),
                          ],
                        ),
                        title: Text(
                          report.category,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.location_on, size: 14, color: Colors.white70),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    report.areaName ?? '-',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13, color: Colors.white70),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                const Icon(Icons.calendar_today, size: 14, color: Colors.white60),
                                const SizedBox(width: 4),
                                Text(
                                  'Selesai: ${DateFormat('dd/MM/yyyy').format(report.createdAtMYT)}',
                                  style: const TextStyle(fontSize: 12, color: Colors.white60),
                                ),
                              ],
                            ),
                          ],
                        ),
                        trailing: const Icon(Icons.compare_arrows, color: Colors.white70, size: 24),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  void _showComparisonDialog(BuildContext context, PotholeReport report) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Perbandingan Sebelum & Selepas',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _buildImageSection('SEBELUM', report.imageUrl),
                    const Divider(height: 1),
                    if (report.resolvedImageUrl != null)
                      _buildImageSection('SELEPAS', report.resolvedImageUrl!)
                    else
                      const Padding(
                        padding: EdgeInsets.all(20.0),
                        child: Text('Tiada imej selepas dikemaskini.'),
                      ),
                  ],
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Tutup'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildImageSection(String label, String url) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
          color: label == 'SELEPAS' ? Colors.green.shade700 : Colors.red.shade700,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ),
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image, size: 50)),
          ),
        ),
      ],
    );
  }
}
