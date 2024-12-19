import 'dart:convert'; // For JSON encoding/decoding
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart'; // For Realtime Database
import 'package:flutter/material.dart';
import 'dart:io'; // For File usage
import 'package:geolocator/geolocator.dart'; // For getting coordinates
import 'package:geocoding/geocoding.dart'; // For reverse geocoding
import 'package:http/http.dart' as http; // For Cloudinary API requests
import 'activity_page.dart';
import 'home_page.dart';

class SubmitPictureReport extends StatefulWidget {
  final File imageFile; // Image file passed from PictureReportPage

  const SubmitPictureReport({super.key, required this.imageFile});

  @override
  SubmitPictureReportState createState() => SubmitPictureReportState();
}

class SubmitPictureReportState extends State<SubmitPictureReport> {
  String senderName = 'Loading...'; // Variable to store sender's name
  bool isLoading = true; // To show loading state while fetching data
  String userLocation = 'Fetching location...'; // To store the user's location

  @override
  void initState() {
    super.initState();
    _fetchSenderName();
    _getCurrentLocation();
  }

  // Fetch the user's name from Firebase Realtime Database
  Future<void> _fetchSenderName() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final userId = user.uid;
        final databaseReference = FirebaseDatabase.instance.ref("users/$userId");

        final snapshot = await databaseReference.once();
        if (snapshot.snapshot.value != null) {
          final userData = snapshot.snapshot.value as Map<dynamic, dynamic>;
          setState(() {
            senderName = userData['name'] ?? 'Unknown';
            isLoading = false;
          });
        } else {
          setState(() {
            senderName = user.displayName ?? 'Unknown';
            isLoading = false;
          });
        }
      } else {
        setState(() {
          senderName = 'Guest';
          isLoading = false;
        });
      }
    } catch (e) {
      print("Error fetching sender's name: $e");
      setState(() {
        senderName = 'Error fetching name';
        isLoading = false;
      });
    }
  }

  // Fetch the current location and decode it into an address
  Future<void> _getCurrentLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        setState(() {
          userLocation = 'Location services are disabled. Please enable them.';
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.deniedForever) {
          setState(() {
            userLocation =
                'Location permissions are permanently denied. Please enable them in settings.';
          });
          return;
        } else if (permission == LocationPermission.denied) {
          setState(() {
            userLocation = 'Location permission denied.';
          });
          return;
        }
      }

      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);

      List<Placemark> placemarks =
          await placemarkFromCoordinates(position.latitude, position.longitude);

      Placemark place = placemarks[0];
      setState(() {
        userLocation =
            '${place.street}, ${place.locality}, ${place.administrativeArea}, ${place.country}';
      });
    } catch (e) {
      print("Error: $e");
      setState(() {
        userLocation =
            'Error retrieving location. Please check permissions and try again.';
      });
    }
  }

  // Upload image to Cloudinary
Future<String> _uploadImageToCloudinary(File imageFile) async {
  const cloudinaryUrl = 'https://api.cloudinary.com/v1_1/db6foxkv8/image/upload';
  const uploadPreset = 'sagip_siklab_images'; // Replace with your Cloudinary upload preset

  // Create a multipart request
  final request = http.MultipartRequest('POST', Uri.parse(cloudinaryUrl))
    ..fields['upload_preset'] = uploadPreset
    ..files.add(await http.MultipartFile.fromPath('file', imageFile.path));

  // Send the request
  final response = await request.send();

  if (response.statusCode == 200) {
    // Parse the response body
    final responseBody = await response.stream.bytesToString();
    final responseData = json.decode(responseBody);
    return responseData['secure_url']; // Return the secure URL of the uploaded image
  } else {
    // Handle upload error
    final responseBody = await response.stream.bytesToString();
    print('Error uploading to Cloudinary: $responseBody');
    throw Exception('Failed to upload image to Cloudinary');
  }
}


  // Submit report to Firebase Realtime Database
  Future<void> _submitReport() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print("No user logged in");
        return;
      }

      // Upload image to Cloudinary
      final imageUrl = await _uploadImageToCloudinary(widget.imageFile);

      // Save report data to Firebase Realtime Database
      final databaseRef = FirebaseDatabase.instance.ref("reports_image").push();
      await databaseRef.set({
        'senderName': senderName,
        'location': userLocation,
        'imageUrl': imageUrl,
        'timestamp': DateTime.now().toIso8601String(),
      });

      _showThankYouDialog(context);
    } catch (e) {
      print("Error submitting report: $e");
    }
  }

  void _showThankYouDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Thank You!'),
          content: const Text(
              'Thank you for reporting. You will be redirected to the Activity Page to monitor your report.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => const ActivityPage()),
                );
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFB71C1C), Color(0xFF880E4F)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Image.asset(
                  'assets/text.png',
                  height: 25,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 4),
                const Text(
                  'FIRE RESPONSE SYSTEM',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/bg.png'),
                fit: BoxFit.cover,
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 200,
                  height: 200,
                  color: Colors.grey[300],
                  child: widget.imageFile != null
                      ? Image.file(widget.imageFile)
                      : const Center(
                          child: Icon(
                            Icons.image,
                            size: 100,
                            color: Colors.grey,
                          ),
                        ),
                ),
                const SizedBox(height: 20),
                isLoading
                    ? const CircularProgressIndicator()
                    : Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 8, horizontal: 16),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Sender: $senderName\nCurrent Location: $userLocation',
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 16,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed: _submitReport,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 40, vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'SUBMIT',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ),
                    const SizedBox(width: 20),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (context) => const HomePage()),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 40, vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'CANCEL',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
