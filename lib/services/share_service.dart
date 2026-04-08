import 'package:share_plus/share_plus.dart';
import '../models/pothole_report.dart';

class ShareService {
  static final ShareService _instance = ShareService._internal();
  factory ShareService() => _instance;
  ShareService._internal();

  // Generate shareable link for a report
  String generateShareLink(PotholeReport report) {
    // This creates a deep link - you can later set up dynamic links
    // For now, we'll use a simple format that shows report details
    return 'https://sahabatassaffal.app/report/${report.id}';
  }

  // Share report via system share sheet
  Future<void> shareReport(PotholeReport report) async {
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
  Future<void> shareReportWithImage(PotholeReport report) async {
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
  Future<void> quickShare(PotholeReport report) async {
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
