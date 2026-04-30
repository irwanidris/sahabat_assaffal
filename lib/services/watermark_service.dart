import 'dart:io';
import 'dart:typed_data'; // Tambah ini untuk Uint8List
import 'package:image/image.dart' as img;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

class WatermarkService {
  static Future<File> addWatermark(File imageFile, {double? lat, double? lon, String? nickname}) async {
    try {
      // 1. Baca bytes dan decode
      final Uint8List imageBytes = await imageFile.readAsBytes();
      img.Image? originalImage = img.decodeImage(imageBytes);

      if (originalImage == null) return imageFile;

      // 2. Ambil Logo
      ByteData logoData = await rootBundle.load('assets/images/logo_s_assaffal.png');
      final Uint8List logoBytes = logoData.buffer.asUint8List();
      img.Image? logo = img.decodeImage(logoBytes);

      if (logo == null) return imageFile;

      // 3. SAIZ LOGO (Dikecilkan sedikit supaya tidak terlalu dominan)
      int logoWidth = (originalImage.width * 0.20).toInt();
      img.Image resizedLogo = img.copyResize(logo, width: logoWidth);

      // 4. POSISI LOGO (Tengah-tengah gambar)
      int posX = (originalImage.width / 2 - resizedLogo.width / 2).toInt();
      int posY = (originalImage.height / 2 - resizedLogo.height / 2).toInt();

      // Lukis logo (Guna blend mode untuk hasil lebih natural jika perlu)
      img.compositeImage(
        originalImage,
        resizedLogo,
        dstX: posX,
        dstY: posY,
        center: false, // Kita dah kira manual posisi X dan Y
      );

      // 5. TAMBAH TEKS METADATA
      String timestamp = DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now());
      String coords = (lat != null && lon != null)
          ? 'Koordinat: ${lat.toStringAsFixed(6)}, ${lon.toStringAsFixed(6)}'
          : 'Koordinat tidak tersedia';
      String nameText = 'Dilaporkan Oleh: ${nickname ?? 'Anonim'}';

      List<String> lines = [timestamp, coords, nameText];

      // Jarak bermula di bawah logo
      int currentY = posY + resizedLogo.height + 15;

      for (String line in lines) {
        // Pengiraan pemusatan teks yang lebih dinamik
        // arial24 biasanya lebar 13-15 pixel per huruf (purata)
        int estimatedWidth = (line.length * 13).toInt();
        int textX = (originalImage.width / 2 - estimatedWidth / 2).toInt();

        // Shadow (Hitam)
        img.drawString(
          originalImage,
          line,
          font: img.arial24,
          x: textX + 2,
          y: currentY + 2,
          color: img.ColorRgba8(0, 0, 0, 180), // Kepekatan shadow dikurangkan sedikit
        );

        // Teks Utama (Putih)
        img.drawString(
          originalImage,
          line,
          font: img.arial24,
          x: textX,
          y: currentY,
          color: img.ColorRgba8(255, 255, 255, 255),
        );

        currentY += 40; // Jarak baris yang lebih selesa
      }

      // 6. Simpan fail unik (Sangat penting untuk elak 'cache' gambar lama)
      final directory = await getTemporaryDirectory();
      final String uniqueName = 'wm_${DateTime.now().microsecondsSinceEpoch}.jpg';
      final String path = '${directory.path}/$uniqueName';

      final File resultFile = File(path);
      await resultFile.writeAsBytes(img.encodeJpg(originalImage, quality: 90));

      return resultFile;
    } catch (e) {
      print("WATERMARK ERROR: $e");
      return imageFile;
    }
  }
}