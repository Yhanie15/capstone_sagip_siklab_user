// ignore_for_file: unused_local_variable, avoid_print, deprecated_member_use

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_core/firebase_core.dart';
import 'submit_picture_report.dart'; // Import SubmitPictureReport page

class PictureReportPage extends StatefulWidget {
  const PictureReportPage({super.key});

  @override
  PictureReportPageState createState() => PictureReportPageState();
}

class PictureReportPageState extends State<PictureReportPage> {
  late CameraController _cameraController;
  late Future<void> _initializeControllerFuture;
  File? _imageFile;
  bool _isCameraInitialized = false;
  String? _errorMessage;

  // Initialize the camera
  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras(); // Get the list of available cameras
      if (cameras.isEmpty) {
        setState(() {
          _errorMessage = 'No cameras available';
        });
        print('No cameras available');
        return;
      }

      final camera = cameras.first; // Choose the first available camera (usually the rear camera)
      _cameraController = CameraController(camera, ResolutionPreset.high);

      // Initialize the camera controller
      _initializeControllerFuture = _cameraController.initialize();

      _initializeControllerFuture.then((_) {
        setState(() {
          _isCameraInitialized = true; // Camera has been initialized
        });
        print('Camera initialized successfully');
      }).catchError((e) {
        setState(() {
          _errorMessage = 'Error initializing camera: $e';
        });
        print('Error during camera initialization: $e');
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load cameras: $e';
      });
      print('Error loading cameras: $e');
    }
  }

  // Capture an image
  Future<void> _takePicture() async {
    try {
      await _initializeControllerFuture; // Wait until the camera is initialized
      final tempDir = await getTemporaryDirectory(); // Get temporary directory to save the image
      final imagePath = '${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}.png';

      // Take the picture and save it to the file system
      final image = await _cameraController.takePicture();

      setState(() {
        _imageFile = File(image.path); // Store the captured image
      });
      print('Picture taken: ${image.path}');
    } catch (e) {
      print('Error while taking picture: $e');
    }
  }

  // Retake the picture
  void _retakePicture() {
    setState(() {
      _imageFile = null; // Reset the image to allow retake
    });
  }

  // Request camera and storage permissions
  Future<void> _checkAndRequestPermissions() async {
    var cameraStatus = await Permission.camera.status;
    var storageStatus = await Permission.storage.status;

    if (!cameraStatus.isGranted) {
      await Permission.camera.request();
    }

    if (!storageStatus.isGranted) {
      await Permission.storage.request();
    }
  }

  @override
  void initState() {
    super.initState();
    _checkAndRequestPermissions(); // Request permissions when initializing
    _initializeCamera(); // Initialize the camera
    Firebase.initializeApp(); // Initialize Firebase
  }

  @override
  void dispose() {
    _cameraController.dispose(); // Dispose of the camera controller when no longer needed
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[300],
      body: Stack(
        children: [
          // Camera preview
          if (_isCameraInitialized)
            Positioned.fill(
              child: CameraPreview(_cameraController),
            )
          else if (_errorMessage != null)
            Center(
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red, fontSize: 18),
              ),
            )
          else
            const Center(child: CircularProgressIndicator()),

          // If an image is taken, display it
          if (_imageFile != null)
            Center(
              child: Image.file(
                _imageFile!,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              ),
            ),

          // Bottom action bar with camera, retake, and check buttons
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              color: Colors.black.withOpacity(0.7),
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Camera button - takes a picture
                  GestureDetector(
                    onTap: _takePicture,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.camera_alt,
                        color: Colors.red,
                        size: 40,
                      ),
                    ),
                  ),
                  const SizedBox(width: 30),
                  // Retake button - allows retaking the picture
                  if (_imageFile != null) ...[
                    GestureDetector(
                      onTap: _retakePicture,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                        child: const Icon(
                          Icons.refresh,
                          color: Colors.black,
                          size: 24,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 30),
                  // Check button - proceed to picture confirmation
                  if (_imageFile != null) ...[
                    GestureDetector(
                      onTap: () {
                        // Navigate to SubmitPictureReport with the captured image
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => SubmitPictureReport(imageFile: _imageFile!),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.green,
                        ),
                        child: const Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
