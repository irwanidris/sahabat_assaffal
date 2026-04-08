import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

class InAppCameraScreen extends StatefulWidget {
  final String category;
  const InAppCameraScreen({super.key, this.category = 'Masalah'});

  @override
  State<InAppCameraScreen> createState() => _InAppCameraScreenState();
}

class _InAppCameraScreenState extends State<InAppCameraScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  bool _isCapturing = false;
  int _selectedCameraIndex = 0;
  FlashMode _flashMode = FlashMode.auto;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _controller;
    if (cameraController == null || !cameraController.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tiada kamera tersedia')));
          Navigator.pop(context);
        }
        return;
      }
      await _setupCamera(_selectedCameraIndex);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ralat kamera: $e')));
        Navigator.pop(context);
      }
    }
  }

  Future<void> _setupCamera(int cameraIndex) async {
    if (_cameras == null || _cameras!.isEmpty) return;
    if (_controller != null) await _controller!.dispose();
    _controller = CameraController(_cameras![cameraIndex], ResolutionPreset.high, enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
    try {
      await _controller!.initialize();
      await _controller!.setFlashMode(_flashMode);
      if (mounted) setState(() { _isInitialized = true; _selectedCameraIndex = cameraIndex; });
    } catch (e) {
      debugPrint('Camera setup error: $e');
    }
  }

  Future<void> _capturePhoto() async {
    if (_controller == null || !_controller!.value.isInitialized || _isCapturing) return;
    setState(() => _isCapturing = true);
    try {
      final XFile photo = await _controller!.takePicture();
      if (mounted) Navigator.pop(context, File(photo.path));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal mengambil gambar: $e')));
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  void _toggleFlash() {
    if (_controller == null) return;
    setState(() {
      if (_flashMode == FlashMode.off) _flashMode = FlashMode.auto;
      else if (_flashMode == FlashMode.auto) _flashMode = FlashMode.always;
      else _flashMode = FlashMode.off;
    });
    _controller!.setFlashMode(_flashMode);
  }

  void _switchCamera() async {
    if (_cameras == null || _cameras!.length < 2) return;
    final newIndex = (_selectedCameraIndex + 1) % _cameras!.length;
    await _setupCamera(newIndex);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (_isInitialized && _controller != null)
            Positioned.fill(child: AspectRatio(aspectRatio: _controller!.value.aspectRatio, child: CameraPreview(_controller!)))
          else
            const Center(child: CircularProgressIndicator(color: Colors.white)),
          
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28)),
                    IconButton(onPressed: _toggleFlash, icon: Icon(_flashMode == FlashMode.off ? Icons.flash_off : Icons.flash_on, color: Colors.white, size: 28)),
                  ],
                ),
              ),
            ),
          ),

          Positioned(
            bottom: 0, left: 0, right: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    const SizedBox(width: 60),
                    GestureDetector(
                      onTap: _capturePhoto,
                      child: Container(
                        width: 80, height: 80,
                        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4)),
                        child: Container(margin: const EdgeInsets.all(4), decoration: BoxDecoration(shape: BoxShape.circle, color: _isCapturing ? Colors.grey : Colors.white)),
                      ),
                    ),
                    IconButton(onPressed: _switchCamera, icon: const Icon(Icons.flip_camera_ios_rounded, color: Colors.white, size: 32)),
                  ],
                ),
              ),
            ),
          ),

          Positioned(
            bottom: 140, left: 0, right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                child: Text(
                  'Ambil foto ${widget.category}',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
