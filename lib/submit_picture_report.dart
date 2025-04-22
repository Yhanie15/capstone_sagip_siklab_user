// ignore_for_file: unnecessary_null_comparison, deprecated_member_use, avoid_print, use_build_context_synchronously

import 'dart:convert'; // For JSON encoding/decoding
import 'dart:typed_data'; // For working with bytes
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart'; // For Realtime Database
import 'package:flutter/material.dart';
import 'dart:io'; // For File usage
import 'package:geolocator/geolocator.dart'; // For getting coordinates
import 'package:geocoding/geocoding.dart'; // For reverse and forward geocoding
import 'package:http/http.dart' as http; // For Cloudinary API requests
import 'package:image/image.dart' as img; // For image processing
import 'package:path_provider/path_provider.dart'; // For accessing device storage
import 'package:intl/intl.dart'; // For date formatting
import 'activity_page.dart';
import 'home_page.dart';

class SubmitPictureReport extends StatefulWidget {
  final File imageFile; // Image file passed from PictureReportPage

  const SubmitPictureReport({super.key, required this.imageFile});

  @override
  SubmitPictureReportState createState() => SubmitPictureReportState();
}

class SubmitPictureReportState extends State<SubmitPictureReport> {
  String senderName = 'Loading...';   // Variable to store sender's name
  String residentId = '';            // Variable to store resident's ID
  bool isLoading = true;             // To show loading state while fetching data
  bool isSubmitting = false;         // To show loading state during submission
  String userLocation = 'Fetching location...'; // To store the user's location
  double? latitude;                  // Variable to store latitude
  double? longitude;                 // Variable to store longitude
  File? timestampedImage;           // Variable to store the timestamped image

  @override
  void initState() {
    super.initState();
    _fetchSenderName();
    _getCurrentLocation();
    _addTimestampToImage();
  }

  // Add timestamp to the image
  Future<void> _addTimestampToImage() async {
    try {
      // Read the image file
      final bytes = await widget.imageFile.readAsBytes();
      final originalImage = img.decodeImage(bytes);
      
      if (originalImage == null) {
        print('Failed to decode image');
        return;
      }

      // Create a copy of the image to draw on
      final timestampedImg = img.copyResize(originalImage, width: originalImage.width);
      
      // Get current date and time
      final now = DateTime.now();
      final formattedDate = DateFormat('yyyy-MM-dd HH:mm:ss').format(now);
      
      // Draw the text on the image
      img.drawString(
        timestampedImg,
        formattedDate,
        font: img.arial48,
        x: 20,
        y: timestampedImg.height - 40,
        color: img.ColorRgb8(255, 255, 0), // Yellow text
      );
      
      // Convert the modified image back to a file
      final directory = await getTemporaryDirectory();
      final timestampedFile = File('${directory.path}/timestamped_image.jpg');
      await timestampedFile.writeAsBytes(img.encodeJpg(timestampedImg));
      
      setState(() {
        timestampedImage = timestampedFile;
      });
    } catch (e) {
      print('Error adding timestamp to image: $e');
      // If there's an error, use the original image
      setState(() {
        timestampedImage = widget.imageFile;
      });
    }
  }

  // Fetch the user's name, residentId, and possibly address from Firebase Realtime Database
  Future<void> _fetchSenderName() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final userId = user.uid;
        final databaseReference = FirebaseDatabase.instance.ref("resident/$userId");

        final snapshot = await databaseReference.once();
        if (snapshot.snapshot.value != null) {
          final userData = snapshot.snapshot.value as Map<dynamic, dynamic>;
          setState(() {
            senderName = userData['name'] ?? 'Unknown';
            residentId = userData['residentId'] ?? '';  // Fetch the residentId
            isLoading = false;
          });

          // If the resident has an address, you can perform forward geocoding here
          if (userData['address'] != null && userData['address'].toString().isNotEmpty) {
            await _geocodeAddress(userData['address']);
          }
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

  // Geocode an address to get latitude and longitude
  Future<void> _geocodeAddress(String address) async {
    try {
      List<Location> locations = await locationFromAddress(address);
      if (locations.isNotEmpty) {
        setState(() {
          latitude = locations.first.latitude;
          longitude = locations.first.longitude;
          userLocation = address;
        });
      }
    } catch (e) {
      print("Error geocoding address: $e");
      // Optionally fallback to device location or handle the error
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
        desiredAccuracy: LocationAccuracy.high,
      );

      List<Placemark> placemarks =
          await placemarkFromCoordinates(position.latitude, position.longitude);

      Placemark place = placemarks[0];
      setState(() {
        userLocation =
            '${place.street}, ${place.locality}, ${place.administrativeArea}, ${place.country}';
        latitude = position.latitude;
        longitude = position.longitude;
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
    // Set isSubmitting to true to show loading indicator
    setState(() {
      isSubmitting = true;
    });
    
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print("No user logged in");
        setState(() {
          isSubmitting = false;
        });
        return;
      }
      
      // Use the timestamped image if available, otherwise use the original
      final imageToUpload = timestampedImage ?? widget.imageFile;

      // 1) Upload image to Cloudinary
      final imageUrl = await _uploadImageToCloudinary(imageToUpload);

      // 2) Push a new node under "reports_image"
      final databaseRef = FirebaseDatabase.instance.ref("reports_image").push();
      final reportId = databaseRef.key; // The unique ID generated by push()

      // Get current date and time for the report timestamp
      final now = DateTime.now();
      final reportTimestamp = now.toIso8601String();

      // 3) Set data, including the "reportId" so we can reference it later
      await databaseRef.set({
        'reportId': reportId,       // Unique ID for this report
        'senderName': senderName,
        'senderId': residentId,     // We store the residentId too
        'location': userLocation,
        'latitude': latitude ?? 0.0,   // Save latitude, default to 0.0 if null
        'longitude': longitude ?? 0.0, // Save longitude, default to 0.0 if null
        'imageUrl': imageUrl,
        'timestamp': reportTimestamp,
        'pictureTimestamp': reportTimestamp, // Also storing when picture was taken
        'status': 'Pending',       // Set default status to 'pending'
      });

      // Set isSubmitting to false when done
      setState(() {
        isSubmitting = false;
      });

      _showThankYouDialog(context);
    } catch (e) {
      print("Error submitting report: $e");
      // Set isSubmitting to false on error
      setState(() {
        isSubmitting = false;
      });
      // Show error dialog to user
      _showErrorDialog(context, e.toString());
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
  
  void _showErrorDialog(BuildContext context, String errorMessage) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Error'),
          content: Text('Failed to submit report: $errorMessage'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
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
                  child: timestampedImage != null
                      ? Image.file(timestampedImage!)
                      : (widget.imageFile != null
                          ? Image.file(widget.imageFile)
                          : const Center(
                              child: Icon(
                                Icons.image,
                                size: 100,
                                color: Colors.grey,
                              ),
                            )),
                ),
                const SizedBox(height: 20),
                isLoading
                    ? const CircularProgressIndicator()
                    : Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 16,
                        ),
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
                // Modified section: Using Wrap instead of Row for better handling of overflow
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Wrap(
                    spacing: 20, // horizontal space between items
                    runSpacing: 10, // vertical space between lines
                    alignment: WrapAlignment.center,
                    children: [
                      ElevatedButton(
                        onPressed: isSubmitting ? null : _submitReport,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20, // Reduced from 40 to save space
                            vertical: 15,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: isSubmitting
                            ? const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 16, // Reduced size
                                    height: 16, // Reduced size
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  SizedBox(width: 8), // Reduced spacing
                                  Text(
                                    'UPLOADING...',
                                    style: TextStyle(color: Colors.white, fontSize: 14), // Reduced font size
                                  ),
                                ],
                              )
                            : const Text(
                                'SUBMIT',
                                style: TextStyle(color: Colors.white, fontSize: 16),
                              ),
                      ),
                      ElevatedButton(
                        onPressed: isSubmitting
                            ? null
                            : () {
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(builder: (context) => const HomePage()),
                                );
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20, // Reduced from 40 to save space
                            vertical: 15,
                          ),
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
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}