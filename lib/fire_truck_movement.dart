// ignore_for_file: deprecated_member_use, prefer_const_literals_to_create_immutables

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as lat_lng;
import 'package:http/http.dart' as http;
import 'package:firebase_database/firebase_database.dart';

class FireTruckMovementPage extends StatefulWidget {
  final String location;
  final String fireTruckNumber;
  final String fireStationName;
  final double latitude;
  final double longitude;
  final double rescuerLatitude;
  final double rescuerLongitude;
  final String rescuerId;
  final String reportKey;

  const FireTruckMovementPage({
    super.key,
    required this.location,
    required this.fireTruckNumber,
    required this.fireStationName,
    required this.latitude,
    required this.longitude,
    required this.rescuerLatitude,
    required this.rescuerLongitude,
    required this.rescuerId,
    required this.reportKey,
  });

  @override
  State<FireTruckMovementPage> createState() => _FireTruckMovementPageState();
}

class _FireTruckMovementPageState extends State<FireTruckMovementPage> {
  List<lat_lng.LatLng> routePoints = [];
  bool isLoading = true;
  String? errorMessage;

  // Current position of the fire truck
  late lat_lng.LatLng currentRescuerPosition;

  // Timer for updating the fire truck position
  Timer? _updateTimer;

  // Firebase references for real-time updates
  late DatabaseReference _dispatchesRef;
  late DatabaseReference _rescuerRef;
  late DatabaseReference _fireStationRef;
  StreamSubscription<DatabaseEvent>? _dispatchStream;
  StreamSubscription<DatabaseEvent>? _rescuerStream;
  StreamSubscription<DatabaseEvent>? _fireStationStream;

  // Estimated time of arrival in minutes
  String estimatedArrival = "Calculating...";

  // Status of the dispatch
  String dispatchStatus = "Dispatched";

  // Fire station details
  String fireStationName = "";
  String fireTruckNumber = "";

  // MapController to update map position
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    // Initialize with the starting position
    currentRescuerPosition = lat_lng.LatLng(
      widget.rescuerLatitude != 0.0
          ? widget.rescuerLatitude
          : 14.6760, // Default Manila latitude
      widget.rescuerLongitude != 0.0
          ? widget.rescuerLongitude
          : 121.0437, // Default Manila longitude
    );

    // Initialize with passed values (fallback)
    fireStationName = widget.fireStationName;
    fireTruckNumber = widget.fireTruckNumber;

    // Set up Firebase real-time listener
    _setupRealtimeUpdates();

    // Fetch initial route
    _fetchRoute();

    final mapOptions = MapOptions(
      initialCenter: lat_lng.LatLng(
        (widget.latitude + currentRescuerPosition.latitude) / 2,
        (widget.longitude + currentRescuerPosition.longitude) / 2,
      ),
      initialZoom: 12.0, // Increase zoom level for better visibility
    );

    // Set up periodic updates (as a fallback)
    _updateTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _updateEstimatedArrival();
    });
  }

  @override
  void dispose() {
    // Cancel the timer when the page is disposed
    _updateTimer?.cancel();

    // Cancel Firebase listeners
    _dispatchStream?.cancel();
    _rescuerStream?.cancel();
    _fireStationStream?.cancel();

    super.dispose();
  }

  void _setupRealtimeUpdates() {
    // Initialize Firebase references
    _dispatchesRef = FirebaseDatabase.instance.ref().child('dispatches');
    _rescuerRef = FirebaseDatabase.instance.ref().child('rescuer');
    _fireStationRef = FirebaseDatabase.instance.ref().child('fire_stations');

    // Listen for changes in dispatches that match our rescuer ID and report key
    _dispatchStream = _dispatchesRef.onValue.listen((event) {
      if (event.snapshot.value != null) {
        try {
          // Convert the data to a usable format
          Map<dynamic, dynamic> dispatches =
              Map<dynamic, dynamic>.from(event.snapshot.value as Map);

          // Track if we found a matching dispatch
          bool foundDispatch = false;
          String? dispatchId;
          String? fireStationId;

          // Look for dispatches that match our criteria
          dispatches.forEach((key, value) {
            Map<dynamic, dynamic> dispatch = Map<dynamic, dynamic>.from(value);

            // Check if this is our dispatch (matching rescuerID and reportKey)
            if (dispatch['rescuerID'] == widget.rescuerId &&
                dispatch['reportKey'] == widget.reportKey) {
              foundDispatch = true;
              dispatchId = key;

              // Update dispatch status
              setState(() {
                dispatchStatus = dispatch['status'] ?? "Dispatched";
              });

              // Store fire station ID if available
              if (dispatch['fireStationId'] != null) {
                fireStationId = dispatch['fireStationId'].toString();
                _fetchFireStationDetails(fireStationId!);
              }

              // Update fire truck number if available
              if (dispatch['fireTruckNumber'] != null) {
                setState(() {
                  fireTruckNumber = dispatch['fireTruckNumber'].toString();
                });
              }

              // Check if real-time location is available in dispatch
              if (dispatch['realTimeLocation'] != null) {
                Map<dynamic, dynamic> location =
                    Map<dynamic, dynamic>.from(dispatch['realTimeLocation']);

                // Update the position if there's a change
                double newLat = location['latitude'] is double
                    ? location['latitude']
                    : double.tryParse(location['latitude'].toString()) ??
                        currentRescuerPosition.latitude;
                double newLng = location['longitude'] is double
                    ? location['longitude']
                    : double.tryParse(location['longitude'].toString()) ??
                        currentRescuerPosition.longitude;

                lat_lng.LatLng newPosition = lat_lng.LatLng(newLat, newLng);

                if (_isSignificantMove(newPosition)) {
                  setState(() {
                    currentRescuerPosition = newPosition;
                    _updateMap();
                  });
                }
              }

              // If status is changed to Resolved, update the UI
              if (dispatch['status'] == 'Resolved') {
                setState(() {
                  estimatedArrival = "Arrived";
                });
              }
            }
          });

          // If we couldn't find the dispatch, fall back to static rescuer data
          if (!foundDispatch) {
            _fallbackToRescuerData();
          }
        } catch (e) {
          print('Error processing dispatch data: $e');
          _fallbackToRescuerData();
        }
      } else {
        // No dispatches data available, fall back to static rescuer data
        _fallbackToRescuerData();
      }
    }, onError: (error) {
      print('Error receiving dispatch updates: $error');
      _fallbackToRescuerData();
    });
  }

  void _fetchFireStationDetails(String fireStationId) {
    // Query the fire station details
    _fireStationStream?.cancel();
    _fireStationStream =
        _fireStationRef.child(fireStationId).onValue.listen((event) {
      if (event.snapshot.value != null) {
        try {
          Map<dynamic, dynamic> stationData =
              Map<dynamic, dynamic>.from(event.snapshot.value as Map);

          // Update fire station name
          setState(() {
            fireStationName = stationData['name'] ?? widget.fireStationName;
          });
        } catch (e) {
          print('Error processing fire station data: $e');
        }
      }
    }, onError: (error) {
      print('Error receiving fire station updates: $error');
    });
  }

  void _fallbackToRescuerData() {
    // Set up listener for rescuer location as fallback
    _rescuerStream =
        _rescuerRef.child(widget.rescuerId).onValue.listen((event) {
      if (event.snapshot.value != null) {
        try {
          Map<dynamic, dynamic> rescuerData =
              Map<dynamic, dynamic>.from(event.snapshot.value as Map);

          // Check if location data is available
          if (rescuerData['latitude'] != null &&
              rescuerData['longitude'] != null) {
            double newLat = double.parse(rescuerData['latitude'].toString());
            double newLng = double.parse(rescuerData['longitude'].toString());
            lat_lng.LatLng newPosition = lat_lng.LatLng(newLat, newLng);

            if (_isSignificantMove(newPosition)) {
              setState(() {
                currentRescuerPosition = newPosition;
                _updateMap();
              });
            }
          }

          // Update status if available
          if (rescuerData['status'] != null) {
            setState(() {
              dispatchStatus = rescuerData['status'];
            });
          }

          // Try to fetch fire station info from rescuer data
          if (rescuerData['fireStationId'] != null) {
            _fetchFireStationDetails(rescuerData['fireStationId'].toString());
          }
        } catch (e) {
          print('Error processing rescuer data: $e');
        }
      }
    }, onError: (error) {
      setState(() {
        errorMessage = 'Error receiving rescuer updates: $error';
      });
    });
  }

  // Check if the movement is significant enough to update the map
  bool _isSignificantMove(lat_lng.LatLng newPosition) {
    // Calculate distance between current and new position
    double distance = _calculateDistance(currentRescuerPosition, newPosition);

    // Consider a move significant if it's more than 10 meters
    return distance > 0.01; // 0.01 km = 10 meters
  }

  void _updateMap() {
    // Recenter the map to keep the truck and destination visible
    _mapController.move(
        lat_lng.LatLng(
          (currentRescuerPosition.latitude + widget.latitude) / 2,
          (currentRescuerPosition.longitude + widget.longitude) / 2,
        ),
        12.0 // Zoom level
        );

    // Re-fetch route if position has changed significantly
    _fetchRoute();
  }

  Future<void> _fetchRoute() async {
    try {
      setState(() {
        isLoading = true;
      });

      // Define the points
      final incidentPoint = lat_lng.LatLng(widget.latitude, widget.longitude);

      // Add the start and end points to the route initially (fallback in case API fails)
      routePoints = [currentRescuerPosition, incidentPoint];

      // Fetch the route from Mapbox Directions API
      final response = await http.get(
        Uri.parse('https://api.mapbox.com/directions/v5/mapbox/driving/'
            '${currentRescuerPosition.longitude},${currentRescuerPosition.latitude};'
            '${widget.longitude},${widget.latitude}'
            '?alternatives=false&geometries=geojson&overview=full&steps=false'
            '&access_token=pk.eyJ1IjoieWhhbmllMTUiLCJhIjoiY2x5bHBrenB1MGxmczJpczYxbjRxbGxsYSJ9.DPO8TGv3Z4Q9zg08WhfoCQ'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['routes'] != null && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final geometry = route['geometry'];

          if (geometry != null && geometry['coordinates'] != null) {
            final List<dynamic> coordinates = geometry['coordinates'];

            // Convert coordinates to LatLng points
            setState(() {
              routePoints = coordinates.map((coord) {
                // Mapbox returns coordinates as [longitude, latitude]
                return lat_lng.LatLng(coord[1], coord[0]);
              }).toList();

              // If we have a duration from the API, use it for ETA
              if (route['duration'] != null) {
                double durationMinutes = route['duration'] / 60;
                if (durationMinutes < 1) {
                  estimatedArrival = "Less than a minute";
                } else {
                  estimatedArrival = "${durationMinutes.toInt()} minutes";
                }
              } else {
                // Otherwise calculate our own estimate
                _updateEstimatedArrival();
              }
            });
          }
        }
      } else {
        // Handle API error but don't show to user - just use our own calculation
        print('Failed to fetch route: ${response.statusCode}');
        _updateEstimatedArrival();
      }
    } catch (e) {
      print('Error fetching route: $e');
      _updateEstimatedArrival();
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  void _updateEstimatedArrival() {
    if (routePoints.isEmpty) return;

    // Calculate estimated arrival time (rough estimate)
    double totalDistance = 0;
    for (int i = 0; i < routePoints.length - 1; i++) {
      totalDistance += _calculateDistance(routePoints[i], routePoints[i + 1]);
    }

    // Assuming average speed of 40 km/h in city
    double estimatedMinutes = (totalDistance / 40) * 60;

    // Don't update if status is Resolved/Arrived
    if (dispatchStatus == 'Resolved') {
      setState(() {
        estimatedArrival = "Arrived";
      });
      return;
    }

    setState(() {
      if (estimatedMinutes < 1) {
        estimatedArrival = "Less than a minute";
      } else {
        estimatedArrival = "${estimatedMinutes.toInt()} minutes";
      }
    });
  }

  // Calculate distance between two points in kilometers
  double _calculateDistance(lat_lng.LatLng start, lat_lng.LatLng end) {
    // Using the Haversine formula
    const double earthRadius = 6371; // kilometers

    double dLat = _toRadians(end.latitude - start.latitude);
    double dLon = _toRadians(end.longitude - start.longitude);

    double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(start.latitude)) *
            cos(_toRadians(end.latitude)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadius * c;
  }

  double _toRadians(double degree) {
    return degree * (pi / 180);
  }

  @override
  Widget build(BuildContext context) {
    // Define the incident point
    final incidentPoint = lat_lng.LatLng(widget.latitude, widget.longitude);

    // Use fetched names or fallback to widget values
    final displayFireStationName = fireStationName.isEmpty
        ? (widget.fireStationName.isEmpty
            ? "Unknown Fire Station"
            : widget.fireStationName)
        : fireStationName;

    final displayFireTruckNumber = fireTruckNumber.isEmpty
        ? (widget.fireTruckNumber.isEmpty ? "Unknown" : widget.fireTruckNumber)
        : fireTruckNumber;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fire Truck Movement'),
        backgroundColor: Colors.red,
      ),
      body: Stack(
        children: [
          // FlutterMap as a background
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: lat_lng.LatLng(
                (widget.latitude + currentRescuerPosition.latitude) / 2,
                (widget.longitude + currentRescuerPosition.longitude) / 2,
              ),
              initialZoom: 12.0, // Increased from 5.0 for better visibility
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://api.mapbox.com/styles/v1/mapbox/streets-v11/tiles/{z}/{x}/{y}?access_token=pk.eyJ1IjoieWhhbmllMTUiLCJhIjoiY2x5bHBrenB1MGxmczJpczYxbjRxbGxsYSJ9.DPO8TGv3Z4Q9zg08WhfoCQ',
                additionalOptions: {
                  'accessToken':
                      'pk.eyJ1IjoieWhhbmllMTUiLCJhIjoiY2x5bHBrenB1MGxmczJpczYxbjRxbGxsYSJ9.DPO8TGv3Z4Q9zg08WhfoCQ',
                  'id': 'mapbox/streets-v11',
                },
              ),
              // PolylineLayer for drawing the route (draw before markers so markers appear on top)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: routePoints,
                    strokeWidth: 4.0,
                    color: Colors.blue,
                  ),
                ],
              ),
              // MarkerLayer for showing the markers
              MarkerLayer(
                markers: [
                  // Incident location marker
                  Marker(
                    width: 40,
                    height: 40,
                    point: incidentPoint,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.local_fire_department,
                        color: Colors.red,
                        size: 40,
                      ),
                    ),
                  ),
                  // Fire truck marker with current position
                  Marker(
                    width: 40,
                    height: 40,
                    point: currentRescuerPosition,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: dispatchStatus == 'Dispatched'
                              ? Colors.red
                              : Colors.green,
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.fire_truck,
                        color: Colors.blue,
                        size: 30,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Loading indicator
          if (isLoading)
            const Center(
              child: CircularProgressIndicator(),
            ),

          // Error message
          if (errorMessage != null && !isLoading)
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      errorMessage!,
                      style: const TextStyle(color: Colors.red),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          errorMessage = null;
                          _fetchRoute();
                        });
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
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
                      'Fire truck is responding to fire at ${widget.location}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Expanded(
                        //   child: Text(
                        //     'Fire Truck: $displayFireTruckNumber',
                        //     style: const TextStyle(fontSize: 14),
                        //   ),
                        // ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: dispatchStatus == 'Resolved'
                                ? Colors.green
                                : Colors.red,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'ETA: $estimatedArrival',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Expanded(
                        //   child: Text(
                        //     'Station: $displayFireStationName',
                        //     style: const TextStyle(fontSize: 14),
                        //     overflow: TextOverflow.ellipsis,
                        //   ),
                        // ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: dispatchStatus == 'Resolved'
                                ? Colors.green
                                : dispatchStatus == 'Dispatched'
                                    ? Colors.orange
                                    : Colors.blue,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            dispatchStatus,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Legend
          Positioned(
            bottom: 16.0,
            right: 16.0,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.9),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 5,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.local_fire_department,
                          color: Colors.red, size: 20),
                      SizedBox(width: 8),
                      Text('Fire Incident'),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: dispatchStatus == 'Resolved'
                                  ? Colors.green
                                  : Colors.red,
                              width: 2),
                        ),
                        child: const Icon(Icons.fire_truck,
                            color: Colors.blue, size: 16),
                      ),
                      const SizedBox(width: 8),
                      Text('Fire Truck ($dispatchStatus)'),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        width: 20,
                        height: 4,
                        color: Colors.blue,
                      ),
                      SizedBox(width: 8),
                      Text('Route'),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Refresh button
          Positioned(
            bottom: 16.0,
            left: 16.0,
            child: FloatingActionButton(
              onPressed: () {
                _fetchRoute();
              },
              backgroundColor: Colors.white,
              child: const Icon(Icons.refresh, color: Colors.blue),
            ),
          ),
        ],
      ),
    );
  }
}
