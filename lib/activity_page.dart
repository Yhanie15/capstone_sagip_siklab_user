// ignore_for_file: avoid_print, no_leading_underscores_for_local_identifiers, use_build_context_synchronously, prefer_const_constructors

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'fire_truck_movement.dart';
import 'home_page.dart';
import 'package:firebase_auth/firebase_auth.dart'; // For getting the current user's UID

class ActivityPage extends StatefulWidget {
  const ActivityPage({super.key});

  @override
  ActivityPageState createState() => ActivityPageState();
}

class ActivityPageState extends State<ActivityPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> ongoingReports = [];
  List<Map<String, dynamic>> completedReports = [];
  bool isLoading = true;

  // Flag to ensure feedback prompts are shown only once per page load
  bool _feedbackPrompted = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchReports();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // Fetch reports based on the logged-in user's UID
  Future<void> _fetchReports() async {
    setState(() {
      isLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print("No user logged in");
        setState(() {
          isLoading = false;
        });
        return;
      }

      final userId = user.uid;

      // References to the necessary database nodes
      final reportsImageRef = FirebaseDatabase.instance.ref("reports_image");
      final callsRef = FirebaseDatabase.instance.ref("Calls");
      final dispatchesRef = FirebaseDatabase.instance.ref("dispatches");

      // Temporary storage for all combined reports
      List<Map<String, dynamic>> allReports = [];

      // 1) Fetch from "reports_image"
      final reportsImageSnapshot = await reportsImageRef.get();
      if (reportsImageSnapshot.exists) {
        final reportsImageData =
            reportsImageSnapshot.value as Map<dynamic, dynamic>;
        reportsImageData.forEach((key, value) {
          final reportData = value as Map<dynamic, dynamic>;

          // Grab location, latitude, and longitude from "reports_image" node
          final fetchedLocation =
              reportData['location'] ?? 'No location provided';
          final fetchedLat =
              double.tryParse(reportData['latitude']?.toString() ?? '') ?? 0.0;
          final fetchedLong =
              double.tryParse(reportData['longitude']?.toString() ?? '') ?? 0.0;

          allReports.add({
            'id': key,
            'reportVia': 'Image',
            'title': reportData['title'] ?? 'Untitled',
            'status': reportData['status'] ?? 'Pending',
            'date': reportData['timestamp'] ?? 'Unknown Date',
            'description':
                reportData['description'] ?? 'No description provided.',
            'fireTruckNumber': reportData['fireTruckNumber'] ?? 'Unknown',
            'location': fetchedLocation,
            'senderId': reportData['senderId'] ?? '',
            'senderName': reportData['senderName'] ?? 'Unknown',

            // Fire station name if you store it in the same node (adjust field name as needed)
            'fireStationName':
                reportData['fireStationName'] ?? 'Unknown Fire Station',

            // Direct lat/long from the node
            'latitude': fetchedLat,
            'longitude': fetchedLong,

            // Placeholder for rescuer's location
            'rescuer_latitude': null,
            'rescuer_longitude': null,
          });
        });
      }

      // 2) Fetch from "Calls"
      final callsSnapshot = await callsRef.get();
      if (callsSnapshot.exists) {
        final callsData = callsSnapshot.value as Map<dynamic, dynamic>;
        callsData.forEach((key, value) {
          final callData = value as Map<dynamic, dynamic>;

          final fetchedLocation =
              callData['address'] ?? 'No address provided';
          final fetchedLat =
              double.tryParse(callData['latitude']?.toString() ?? '') ?? 0.0;
          final fetchedLong =
              double.tryParse(callData['longitude']?.toString() ?? '') ?? 0.0;

          allReports.add({
            'id': key,
            'reportVia': 'Call',
            'title': 'Phone Call', // or something else if you like
            'status': callData['status'] ?? 'Unknown',
            'date': callData['time'] ?? 'Unknown Date',
            'description':
                'Caller Name: ${callData['callerName'] ?? 'N/A'}\n'
                'Contact Number: ${callData['contactNumber'] ?? 'N/A'}\n'
                'Address: $fetchedLocation',
            'fireTruckNumber': 'N/A', // calls may not have a fireTruckNumber
            'location': fetchedLocation,
            'senderId': callData['callerID'] ?? '',
            'senderName': callData['callerName'] ?? 'Unknown',

            // Fire station name if you store it in the same node
            'fireStationName':
                callData['fireStationName'] ?? 'Unknown Fire Station',

            // Direct lat/long from the node
            'latitude': fetchedLat,
            'longitude': fetchedLong,

            // Placeholder for rescuer's location
            'rescuer_latitude': null,
            'rescuer_longitude': null,
          });
        });
      }

      // 3) Fetch from "dispatches"
      final dispatchesSnapshot = await dispatchesRef.get();
      Map<String, Map<dynamic, dynamic>> reportKeyToDispatch = {};
      if (dispatchesSnapshot.exists) {
        final dispatchesData = dispatchesSnapshot.value as Map<dynamic, dynamic>;
        dispatchesData.forEach((key, value) {
          final dispatchData = value as Map<dynamic, dynamic>;
          final reportKey = dispatchData['reportKey'];
          if (reportKey != null) {
            reportKeyToDispatch[reportKey.toString()] = dispatchData;
          }
        });
      }

      // 4) Associate dispatches with reports
      for (var report in allReports) {
        final dispatch = reportKeyToDispatch[report['id']];
        if (dispatch != null) {
          final realTimeLocation = dispatch['realTimeLocation'];
          if (realTimeLocation != null) {
            final rescuerLat = double.tryParse(
                    realTimeLocation['latitude']?.toString() ?? '') ??
                0.0;
            final rescuerLong = double.tryParse(
                    realTimeLocation['longitude']?.toString() ?? '') ??
                0.0;
            report['rescuer_latitude'] = rescuerLat;
            report['rescuer_longitude'] = rescuerLong;
          }
        }
      }

      // 5) Filter the combined list into ongoing / completed
      ongoingReports = allReports
          .where((report) =>
              report['senderId'] == userId && report['status'] != 'Resolved')
          .toList();

      completedReports = allReports
          .where((report) =>
              report['senderId'] == userId && report['status'] == 'Resolved')
          .toList();

      setState(() {
        isLoading = false;
      });

      // After setting the state, prompt feedback if not already prompted
      if (!_feedbackPrompted) {
        _feedbackPrompted = true;
        _promptFeedbacks();
      }
    } catch (e) {
      print("Error fetching reports: $e");
      setState(() {
        isLoading = false;
      });
    }
  }

  // Function to prompt feedback for all resolved reports without feedback
  Future<void> _promptFeedbacks() async {
    // Collect all completed reports without feedback
    List<Map<String, dynamic>> reportsNeedingFeedback = [];

    for (var report in completedReports) {
      // Check if feedback exists regardless of report type
      bool hasFeedback = await _hasFeedback(report['id'], report['reportVia']);
      if (!hasFeedback) {
        reportsNeedingFeedback.add(report);
      }
    }

    // Iterate through each report and show feedback dialog
    for (var report in reportsNeedingFeedback) {
      await _showFeedbackDialog(
          report['id'], report['title'], report['reportVia']);
    }

    // After all feedbacks are prompted, refresh the reports
    _fetchReports();
  }

  // Function to show feedback dialog for a specific report
  Future<void> _showFeedbackDialog(
      String reportId, String reportTitle, String reportVia) async {
    int _rating = 0;
    String _comment = '';
    final _formKey = GlobalKey<FormState>();

    // Show the feedback dialog
    await showDialog(
      context: context,
      barrierDismissible:
          false, // Prevent dismissing by tapping outside
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Report Resolved'),
              content: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Report: $reportTitle',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      const Text('Please rate our service:'),
                      const SizedBox(height: 10),
                      Wrap(
                        alignment: WrapAlignment.center,
                        children: List.generate(5, (index) {
                          return IconButton(
                            icon: Icon(
                              index < _rating
                                  ? Icons.star
                                  : Icons.star_border,
                              color: Colors.amber,
                            ),
                            onPressed: () {
                              setState(() {
                                _rating = index + 1;
                              });
                            },
                          );
                        }),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        decoration: const InputDecoration(
                          labelText: 'Additional Comments (Optional)',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 3,
                        onChanged: (value) {
                          _comment = value;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  child: const Text('Cancel'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                ElevatedButton(
                  child: const Text('Submit'),
                  onPressed: () async {
                    if (_rating == 0) {
                      // Show error if no rating is selected
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content:
                              Text('Please select a rating before submitting.'),
                        ),
                      );
                      return;
                    }

                    // Determine the correct feedback path based on report type
                    String feedbackPath = '';
                    if (reportVia == 'Image') {
                      feedbackPath = "reports_image/$reportId/feedback";
                    } else if (reportVia == 'Call') {
                      feedbackPath = "Calls/$reportId/feedback";
                    } else {
                      feedbackPath = "reports/$reportId/feedback";
                    }

                    // Save feedback to Firebase under the appropriate node
                    final feedbackRef =
                        FirebaseDatabase.instance.ref(feedbackPath);
                    await feedbackRef.set({
                      'rating': _rating,
                      'comment': _comment,
                      'timestamp': DateTime.now().toIso8601String(),
                    });

                    // Show confirmation
                    Navigator.of(context).pop(); // Close the dialog
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Thank you for your feedback!'),
                      ),
                    );
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Helper function to check if feedback exists for a report
  Future<bool> _hasFeedback(String reportId, String reportVia) async {
    String feedbackPath = '';
    if (reportVia == 'Image') {
      feedbackPath = "reports_image/$reportId/feedback";
    } else if (reportVia == 'Call') {
      feedbackPath = "Calls/$reportId/feedback";
    } else {
      feedbackPath = "reports/$reportId/feedback"; // Generic path
    }
    final feedbackRef = FirebaseDatabase.instance.ref(feedbackPath);
    final feedbackSnapshot = await feedbackRef.get();
    return feedbackSnapshot.exists;
  }

  // Function to show feedback dialog when a completed report is tapped
  Future<void> _showFeedbackOnTap(String reportId, String reportVia) async {
    // Check if feedback already exists
    bool feedbackExists = await _hasFeedback(reportId, reportVia);

    if (feedbackExists) {
      // Feedback already provided, optionally show it or inform the user
      String feedbackPath = '';
      if (reportVia == 'Image') {
        feedbackPath = "reports_image/$reportId/feedback";
      } else if (reportVia == 'Call') {
        feedbackPath = "Calls/$reportId/feedback";
      } else {
        feedbackPath = "reports/$reportId/feedback";
      }

      final feedbackRef = FirebaseDatabase.instance.ref(feedbackPath);
      final feedbackSnapshot = await feedbackRef.get();

      if (feedbackSnapshot.exists) {
        final existingFeedback =
            feedbackSnapshot.value as Map<dynamic, dynamic>;
        showDialog(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('Feedback Already Provided'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Rating: ${existingFeedback['rating']}'),
                  const SizedBox(height: 10),
                  Text(
                      'Comment: ${existingFeedback['comment'] ?? 'No comment provided.'}'),
                ],
              ),
              actions: [
                TextButton(
                  child: const Text('OK'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            );
          },
        );
        return;
      }
    }

    // If no feedback exists, show the feedback dialog
    await _showFeedbackDialog(reportId, "Report $reportId", reportVia);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[300],
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          'Report History',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const HomePage()),
            );
          },
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50.0),
          child: TabBar(
            controller: _tabController,
            labelColor: Colors.white,
            unselectedLabelColor: const Color.fromARGB(255, 255, 249, 249),
            indicator: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(5),
            ),
            indicatorSize: TabBarIndicatorSize.label,
            tabs: [
              Container(
                width: MediaQuery.of(context).size.width * 0.5,
                alignment: Alignment.center,
                child: const Tab(text: 'Ongoing'),
              ),
              Container(
                width: MediaQuery.of(context).size.width * 0.5,
                alignment: Alignment.center,
                child: const Tab(text: 'Completed'),
              ),
            ],
          ),
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildReportList(ongoingReports, isCompleted: false),
                _buildReportList(completedReports, isCompleted: true),
              ],
            ),
    );
  }

  Widget _buildReportList(List<Map<String, dynamic>> reports,
      {required bool isCompleted}) {
    if (reports.isEmpty) {
      return Center(
        child: Text(
          'No reports available.',
          style: TextStyle(fontSize: 16, color: Colors.grey[700]),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchReports,
      child: ListView.builder(
        padding: const EdgeInsets.all(10),
        itemCount: reports.length,
        itemBuilder: (context, index) {
          final report = reports[index];
          return GestureDetector(
            onTap: () async {
              if (report['status'] == 'Resolved') {
                await _showFeedbackOnTap(report['id'], report['reportVia']);
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => FireTruckMovementPage(
                      location: report['location'] ?? 'Unknown Location',
                      fireTruckNumber:
                          report['fireTruckNumber'] ?? 'Unknown Truck',
                      fireStationName:
                          report['fireStationName'] ?? 'Unknown Station',
                      // Pass latitude & longitude to FireTruckMovementPage
                      latitude: (report['latitude'] is num)
                          ? report['latitude']
                          : 0.0,
                      longitude: (report['longitude'] is num)
                          ? report['longitude']
                          : 0.0,
                      rescuerLatitude: (report['rescuer_latitude'] is num)
                          ? report['rescuer_latitude']
                          : 0.0,
                      rescuerLongitude: (report['rescuer_longitude'] is num)
                          ? report['rescuer_longitude']
                          : 0.0,
                    ),
                  ),
                );
              }
            },
            child: Card(
              elevation: 5,
              margin: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              child: Container(
                padding: const EdgeInsets.all(15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      // Include "reportVia" if you want to show "Call" vs "Image"
                      'Status: ${report['status']} (${report['reportVia']})',
                      style: TextStyle(
                        fontSize: 16,
                        color: _getStatusColor(report['status']!),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Date: ${report['date']}',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Location: ${report['location']}',
                      style: const TextStyle(
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 5),
                    if (isCompleted)
                      FutureBuilder<bool>(
                        future: _hasFeedback(report['id'], report['reportVia']),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Padding(
                              padding: EdgeInsets.only(top: 10),
                              child: CircularProgressIndicator(),
                            );
                          } else if (snapshot.hasData && snapshot.data == true) {
                            return const Padding(
                              padding: EdgeInsets.only(top: 10),
                              child: Text(
                                'Feedback Provided',
                                style: TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            );
                          } else {
                            return const SizedBox.shrink();
                          }
                        },
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Resolved':
        return Colors.green;
      case 'Pending':
        return Colors.orange;
      case 'In Progress':
        return Colors.blue;
      case 'Accepted':
        return Colors.purple; // You can change it to any color you like
      case 'Dispatched':
        return Colors.red; // Added color for 'Dispatched' status
      default:
        return Colors.black;
    }
  }
}
