import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class DisclaimerScreen extends StatelessWidget {
  const DisclaimerScreen({super.key});

  static void show(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => const DisclaimerScreen(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDarkMode
                ? [const Color(0xFF1A1A1A), const Color(0xFF2C2C2C)]
                : [const Color(0xFFE3F2FD), const Color(0xFFFFFDE7)], // Biru Muda & Kuning Muda
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.gavel_rounded, color: AppTheme.primaryRed, size: 28),
                  const SizedBox(width: 12),
                  const Text(
                    'Penafian Rasmi',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildText(
                'Sahabat Assaffal ialah inisiatif komuniti untuk memudahkan penyaluran dan pengesahan maklumat kerosakan infrastruktur secara telus.',
              ),
              _buildText(
                'Laporan anda akan disiarkan terus dan disahkan oleh komuniti sebelum dipanjangkan kepada pihak berkuasa untuk rekod dan tindakan lanjut.',
              ),
              _buildText(
                'Tindakan pembaikan adalah tertakluk sepenuhnya kepada agensi berkaitan. Sahabat Assaffal tidak bertanggungjawab atas sebarang keputusan atau tindakan pihak berkuasa.',
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Pertanyaan:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'sahabatassaffal@gmail.com',
                      style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryRed,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Faham & Tutup', style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildText(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        textAlign: TextAlign.justify,
        style: const TextStyle(fontSize: 14, height: 1.5),
      ),
    );
  }
}
