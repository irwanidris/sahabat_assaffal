import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

class WatermarkService {
  static Future<File> addWatermark(File imageFile, {double? lat, double? lon, String? nickname}) async {
    try {
      final Uint8List imageBytes = await imageFile.readAsBytes();
      img.Image? originalImage = img.decodeImage(imageBytes);

      if (originalImage == null) return imageFile;

      ByteData logoData = await rootBundle.load('assets/images/logo_s_assaffal.png');
      final Uint8List logoBytes = logoData.buffer.asUint8List();
      img.Image? watermark = img.decodeImage(logoBytes);

      if (watermark == null) return imageFile;

      // 1. SESUAIKAN SAIZ WATERMARK (25% daripada lebar gambar asal)
      int watermarkWidth = (originalImage.width * 0.25).toInt();
      img.Image resizedWatermark = img.copyResize(watermark, width: watermarkWidth);

      // 2. LETAK LOGO DI TENGAH-TENGAH FOTO
      int posX = (originalImage.width / 2 - resizedWatermark.width / 2).toInt();
      int posY = (originalImage.height / 2 - resizedWatermark.height / 2).toInt();

      img.compositeImage(
        originalImage, 
        resizedWatermark, 
        dstX: posX, 
        dstY: posY,
      );

      // 3. TAMBAH TEKS TARIKH, KOORDINAT & NICKNAME DI BAWAH LOGO
      String timestamp = DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now());
      String coords = (lat != null && lon != null) 
          ? 'Lat: ${lat.toStringAsFixed(6)}, Lon: ${lon.toStringAsFixed(6)}'
          : 'Koordinat tidak tersedia';
      String nameText = (nickname != null && nickname.isNotEmpty) ? 'Oleh: $nickname' : '';
      
      // Lukis baris demi baris untuk kawalan lebih baik
      List<String> lines = [timestamp, coords];
      if (nameText.isNotEmpty) lines.add(nameText);
      
      int currentY = posY + resizedWatermark.height + 15;
      
      for (String line in lines) {
        // Anggaran lebar teks untuk pemusatan (font arial24 kira-kira 12 pixel per huruf)
        int textWidth = line.length * 12; 
        int textX = (originalImage.width / 2 - textWidth / 2).toInt();

        // Lukis bayang hitam (shadow) untuk kejelasan
        img.drawString(
          originalImage, 
          line,
          font: img.arial24,
          x: textX + 2,
          y: currentY + 2,
          color: img.ColorRgba8(0, 0, 0, 128), // Hitam lutsinar
        );

        // Lukis teks putih utama
        img.drawString(
          originalImage, 
          line,
          font: img.arial24,
          x: textX,
          y: currentY,
          color: img.ColorRgba8(255, 255, 255, 255), // Putih
        );
        
        currentY += 30; // Jarak antara baris
      }

      final directory = await getTemporaryDirectory();
      final String path = '${directory.path}/wm_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final Uint8List wmImageBytes = Uint8List.fromList(img.encodeJpg(originalImage, quality: 95));
      
      final File resultFile = File(path);
      await resultFile.writeAsBytes(wmImageBytes);
      return resultFile;
    } catch (e) {
      print("WATERMARK ERROR: $e");
      return imageFile;
    }
  }
}
