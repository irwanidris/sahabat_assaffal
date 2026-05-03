import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';

class ICCaptureScreen extends StatefulWidget {
  final String side; // 'DEPAN' atau 'BELAKANG'
  const ICCaptureScreen({super.key, required this.side});

  @override
  State<ICCaptureScreen> createState() => _ICCaptureScreenState();
}

class _ICCaptureScreenState extends State<ICCaptureScreen> {
  CameraController? _controller;
  ObjectDetector? _objectDetector;
  bool _isBusy = false;
  bool _hasCaptured = false;
  String _statusMessage = "Mencari Kad...";
  Color _boxColor = Colors.white;

  @override
  void initState() {
    super.initState();
    _initializeDetector();
    _initializeCamera();
  }

  void _initializeDetector() {
    final options = ObjectDetectorOptions(
      mode: DetectionMode.stream,
      classifyObjects: false,
      multipleObjects: false,
    );
    _objectDetector = ObjectDetector(options: options);
  }

  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    _controller = CameraController(cameras[0], ResolutionPreset.high, enableAudio: false);
    await _controller?.initialize();

    _controller?.startImageStream(_processCameraImage);
    if (mounted) setState(() {});
  }

  // LOGIK UTAMA: Mengesan kedudukan kad
  void _processCameraImage(CameraImage image) async {
    if (_isBusy || _hasCaptured || _objectDetector == null) return;
    _isBusy = true;

    try {
      final inputImage = _inputImageFromCameraImage(image);
      if (inputImage == null) return;

      final objects = await _objectDetector!.processImage(inputImage);

      if (objects.isNotEmpty) {
        final obj = objects.first;
        final rect = obj.boundingBox;

        // Semak jika saiz objek menyerupai saiz kad di skrin
        // (Logik ringkas: Jika lebar objek > 200 pixel dan tinggi > 120 pixel)
        if (rect.width > 220 && rect.height > 140) {
          setState(() {
            _boxColor = Colors.green;
            _statusMessage = "Sempurna! Pegang sebentar...";
          });

          // Auto-capture selepas dikesan tepat (delay 1 saat untuk stabil)
          _hasCaptured = true;
          Future.delayed(const Duration(milliseconds: 800), () => _takePicture());
        } else {
          setState(() {
            _boxColor = Colors.orange;
            _statusMessage = "Dekatkan sikit lagi...";
          });
        }
      } else {
        setState(() {
          _boxColor = Colors.white;
          _statusMessage = "Letakkan kad dalam kotak";
        });
      }
    } catch (e) {
      debugPrint("AI Error: $e");
    } finally {
      _isBusy = false;
    }
  }

  Future<void> _takePicture() async {
    try {
      await _controller?.stopImageStream();
      final image = await _controller?.takePicture();
      if (image != null && mounted) {
        _showPreviewDialog(File(image.path));
      }
    } catch (e) {
      _hasCaptured = false;
      _controller?.startImageStream(_processCameraImage);
    }
  }

  void _showPreviewDialog(File file) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Sahkan Gambar ${widget.side}', style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.file(file)),
            const SizedBox(height: 10),
            const Text('Pastikan maklumat pada kad jelas dan tidak silau.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(onPressed: () {
            Navigator.pop(context);
            setState(() => _hasCaptured = false);
            _controller?.startImageStream(_processCameraImage);
          }, child: const Text('AMBIL SEMULA')),
          ElevatedButton(onPressed: () {
            Navigator.pop(context);
            Navigator.pop(context, file);
          }, child: const Text('OK, GUNA INI')),
        ],
      ),
    );
  }

  // Tukar format kamera ke format yang AI faham
  InputImage? _inputImageFromCameraImage(CameraImage image) {
    final sensorOrientation = _controller!.description.sensorOrientation;
    final InputImageRotation? rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    if (rotation == null) return null;

    final InputImageFormat? format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null || (Platform.isAndroid && format != InputImageFormat.nv21)) return null;

    final plane = image.planes.first;

    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    _objectDetector?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(child: CameraPreview(_controller!)),
          // Kesan Kabur di luar kotak rujukan
          ColorFiltered(
            colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.7), BlendMode.srcOut),
            child: Stack(
              children: [
                Container(decoration: const BoxDecoration(color: Colors.black, backgroundBlendMode: BlendMode.dstOut)),
                _buildHole(),
              ],
            ),
          ),
          // Kotak Rujukan Berwarna
          Center(
            child: Container(
              width: 300, height: 190,
              decoration: BoxDecoration(
                border: Border.all(color: _boxColor, width: 3),
                borderRadius: BorderRadius.circular(15),
              ),
            ),
          ),
          // Status & Arahan
          Positioned(
            bottom: 100, left: 0, right: 0,
            child: Center(
              child: Text(_statusMessage, style: TextStyle(color: _boxColor, fontSize: 18, fontWeight: FontWeight.bold, backgroundColor: Colors.black45)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHole() {
    return Center(
      child: Container(
        width: 300, height: 190,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
      ),
    );
  }
}