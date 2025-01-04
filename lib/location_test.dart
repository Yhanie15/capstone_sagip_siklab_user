// ignore_for_file: library_private_types_in_public_api, avoid_print, deprecated_member_use

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart'; // Geolocator package
import 'package:permission_handler/permission_handler.dart'; // For permission handling
import 'package:geocoding/geocoding.dart'; // Geocoding package

class LocationTestPage extends StatefulWidget {
  const LocationTestPage({super.key});

  @override
  _LocationTestPage createState() => _LocationTestPage();
}

class _LocationTestPage extends State<LocationTestPage> {
  Position? _currentPosition; // Declare the variable to store the position
  String? _currentAddress; // Variable to store the address

  // Function to check and request permission for location
  Future<void> _checkLocationPermission() async {
    var permissionStatus = await Permission.location.status;

    if (permissionStatus.isDenied) {
      permissionStatus = await Permission.location.request();
    }

    if (permissionStatus.isGranted) {
      _getCurrentLocation();
    } else {
      print("Location permission denied");
    }
  }

  // Fetch the current location
  Future<void> _getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      _showLocationServiceDialog();
    } else {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        _currentPosition = position; // Store the fetched position
      });
      await _getAddressFromLatLng(position); // Get address from coordinates
    }
  }

  // Get address from latitude and longitude
  Future<void> _getAddressFromLatLng(Position position) async {
    try {
      // Fetch the placemarks from the coordinates
      List<Placemark> placemarks = await placemarkFromCoordinates(
          position.latitude, position.longitude);
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0]; // Get the first placemark
        setState(() {
          // Construct the address string
          _currentAddress =
              "${place.street ?? ''}, ${place.locality ?? ''}, ${place.postalCode ?? ''}, ${place.country ?? ''}";
        });
      } else {
        print("No placemarks found");
        setState(() {
          _currentAddress = "No address found"; // Handle case with no results
        });
      }
    } catch (e) {
      print("Error fetching address: $e");
      setState(() {
        _currentAddress = "Error fetching address"; // Handle errors
      });
    }
  }

  // Show a dialog if the location services are disabled
  void _showLocationServiceDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Location Services Disabled'),
          content: const Text('Please enable location services to use this feature.'),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Geolocator.openLocationSettings(); // Opens the location settings
              },
              child: const Text('Open Settings'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context); // Close the dialog
              },
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _checkLocationPermission(); // Check permission on app launch
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Location Fetcher"),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: _checkLocationPermission, // Trigger location fetch on tap
              child: const Text("Get Current Location"),
            ),
            if (_currentPosition != null) 
              Text(
                "Location: ${_currentPosition!.latitude}, ${_currentPosition!.longitude}",
                style: const TextStyle(fontSize: 18),
              ),
            if (_currentAddress != null) 
              Text(
                "Address: $_currentAddress",
                style: const TextStyle(fontSize:  18),
              ),
          ],
        ),
      ),
    );
  }
}