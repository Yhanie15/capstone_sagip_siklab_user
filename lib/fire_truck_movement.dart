// ignore_for_file: deprecated_member_use, prefer_const_literals_to_create_immutables

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as lat_lng;

class FireTruckMovementPage extends StatelessWidget {
  final String location;
  final String fireTruckNumber;
  final String fireStationName;
  final double latitude;
  final double longitude;
  final double rescuerLatitude;
  final double rescuerLongitude;

  const FireTruckMovementPage({
    super.key,
    required this.location,
    required this.fireTruckNumber,
    required this.fireStationName,
    required this.latitude,
    required this.longitude,
    required this.rescuerLatitude,
    required this.rescuerLongitude,
  });

  @override
  Widget build(BuildContext context) {
    // Define the points
    final residentPoint = lat_lng.LatLng(latitude, longitude);
    final rescuerPoint = lat_lng.LatLng(rescuerLatitude, rescuerLongitude);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fire Truck Movement'),
        backgroundColor: Colors.red, // Optional: Customize AppBar color
      ),
      body: Stack(
        children: [
          // FlutterMap as a background
          FlutterMap(
            options: MapOptions(
              initialCenter: lat_lng.LatLng(
                (latitude + rescuerLatitude) / 2,
                (longitude + rescuerLongitude) / 2,
              ),
              initialZoom: 10.0,
            ),
            children: [
              TileLayer(
                // Replace urlTemplate with your actual Mapbox style URL and access token
                urlTemplate:
                    'https://api.mapbox.com/styles/v1/mapbox/streets-v11/tiles/{z}/{x}/{y}?access_token=pk.eyJ1IjoieWhhbmllMTUiLCJhIjoiY2x5bHBrenB1MGxmczJpczYxbjRxbGxsYSJ9.DPO8TGv3Z4Q9zg08WhfoCQ',
                additionalOptions: {
                  'accessToken': 'YOUR_MAPBOX_ACCESS_TOKEN',
                  'id': 'mapbox/streets-v11',
                },
              ),
              // MarkerLayer for showing the fire icon at resident location
              MarkerLayer(
                markers: [
                  Marker(
                width: 30,
                height: 30,
                point: residentPoint,
               child: const Icon(
               Icons.home,
               color: Colors.blue,
               size: 40,
                     ), 
                  ),
                  Marker(
                width: 30,
                height: 30,
                point: rescuerPoint,
               child: const Icon(
               Icons.local_fire_department,
               color: Colors.red,
               size: 40,
                     ), 
                  ),
                ],
              ),
              // PolylineLayer for drawing the route
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: [residentPoint, rescuerPoint],
                    strokeWidth: 4.0,
                    color: Colors.purple,
                  ),
                ],
              ),
            ],
          ),

          // Top overlay with information
          Positioned(
            top: 16.0,
            left: 16.0,
            right: 16.0,
            child: Card(
              elevation: 4,
              color: Colors.white.withOpacity(0.9), // Slight transparency
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 12.0,
                  horizontal: 16.0,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'The fire truck is on its way to the scene at $location',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),
          ),

          // Bottom overlay with actions or additional info (optional)
          // You can add more widgets here if needed
        ],
      ),
    );
  }
}
