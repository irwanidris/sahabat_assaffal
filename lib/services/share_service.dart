import 'package:share_plus/share_plus.dart';
import '../models/assaffal_report.dart';

class ShareService {
  static final ShareService _instance = ShareService._internal();
  factory ShareService() => _instance;
  ShareService._internal();

  // Generate shareable link for a report
  String generateShareLink(AssaffalReport report) {
    // Andaian pautan Google Play Store dengan parameter report_id
    // Apabila pengguna klik, ia buka Play Store. Selepas install, app boleh baca 'report_id' ini.
    return 'https://play.google.com/store/apps/details?id=com.sahabatassaffal.hero&referrer=report_id=${report.id}';
  }

  // Share report via system share sheet
  Future<void> shareReport(AssaffalReport report) async {
    final link = generateShareLink(report);
    final address = report.address ?? 'Unknown location';
    final areaName = report.areaName ?? 'Unknown area';
    final status = report.status.toUpperCase();

    final shareText = '''
🚧 Amaran Lubang Jalan! 🚧

📍 Lokasi: $areaName
📌 Alamat: $address
📊 Status: $status

Saya melaporkan lubang ini menggunakan aplikasi Sahabat Assaffal. Bantu jadikan jalan raya kita lebih selamat!

🔗 Lihat Laporan: $link

Muat turun Sahabat Assaffal dan lapor kerosakan jalan di kawasan anda! 🦸‍♂️
''';

    await Share.share(
      shareText,
      subject: 'Laporan Lubang Jalan - $areaName',
    );
  }

  // Share report with image
  Future<void> shareReportWithImage(AssaffalReport report) async {
    final address = report.address ?? 'Unknown location';
    final areaName = report.areaName ?? 'Unknown area';
    final status = report.status.toUpperCase();
    final link = generateShareLink(report);

    final shareText = '''
🚧 Amaran Lubang Jalan di $areaName! 🚧

📍 $address
📊 Status: $status

$link

#SahabatAssaffal #KeselamatanJalanRaya #WargaPrihatin
''';

    // Share with the image URL if available
    if (report.imageUrl.isNotEmpty) {
      await Share.shareUri(Uri.parse(report.imageUrl));
    } else {
      await Share.share(shareText, subject: 'Laporan Lubang Jalan - $areaName');
    }
  }

  // Quick share (just the link)
  Future<void> quickShare(AssaffalReport report) async {
    final link = generateShareLink(report);
    final areaName = report.areaName ?? 'Laporan Lubang';
    
    await Share.share(
      '🚧 Lubang di $areaName: $link',
      subject: 'Laporan Lubang Jalan',
    );
  }

  // Share leaderboard position
  Future<void> shareAchievement({
    required int rank,
    required int points,
    required int reports,
    required List<String> badges,
  }) async {
    final badgeEmojis = badges.take(5).join(' ');
    
    final shareText = '''
🏆 Statistik Sahabat Assaffal Saya 🏆

🥇 Kedudukan: #$rank
⭐ Mata: $points
📝 Laporan: $reports
${badges.isNotEmpty ? '🎖️ Lencana: $badgeEmojis' : ''}

Sertai saya dalam misi menyelamatkan jalan raya kita! Muat turun Sahabat Assaffal hari ini! 🦸‍♂️

#SahabatAssaffal #KeselamatanJalanRaya #HeroKomuniti
''';

    await Share.share(shareText, subject: 'Pencapaian Sahabat Assaffal Saya');
  }

  // Share app
  Future<void> shareApp() async {
    const shareText = '''
🦸 Sahabat Assaffal - Selamatkan Jalanraya Kita! 🦸

📸 Ambil foto lubang jalan
📍 Kesan lokasi secara automatik
📧 Lapor terus kepada pihak berkuasa
🏆 Kumpul mata dan lencana!

Muat turun sekarang dan jadi wira jalan raya! 🚧

#SahabatAssaffal #KeselamatanJalanRaya
''';

    await Share.share(shareText, subject: 'Jom guna aplikasi Sahabat Assaffal!');
  }
}
