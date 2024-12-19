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

class ActivityPageState extends State<ActivityPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> ongoingReports = [];
  List<Map<String, dynamic>> completedReports = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchReports(); // Fetch reports based on the logged-in user's name
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // Fetch reports based on the logged-in user's name
  Future<void> _fetchReports() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print("No user logged in");
        setState(() {
          isLoading = false;
        });
        return;
      }

      final userName = user.displayName; // Get the logged-in user's name
      final databaseRef = FirebaseDatabase.instance.ref("reports_image"); // Reference to reports node
      final snapshot = await databaseRef.get();

      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;

        List<Map<String, dynamic>> allReports = data.entries.map((entry) {
          final reportData = entry.value as Map<dynamic, dynamic>;
          return {
            'id': entry.key,
            'title': reportData['title'] ?? 'Untitled',
            'status': reportData['status'] ?? 'Pending',
            'date': reportData['timestamp'] ?? 'Unknown Date',
            'description': reportData['description'] ?? 'No description provided.',
            'fireTruckNumber': reportData['fireTruckNumber'] ?? 'Unknown',
            'location': reportData['location'] ?? 'No location provided',
            'senderName': reportData['senderName'], // Sender's name
          };
        }).toList();

        setState(() {
          // Filter reports by sender's name (userName)
          ongoingReports = allReports
              .where((report) =>
                  report['senderName'] == userName && report['status'] != 'Resolved')
              .toList();
          completedReports = allReports
              .where((report) =>
                  report['senderName'] == userName && report['status'] == 'Resolved')
              .toList();
          isLoading = false;
        });
      } else {
        setState(() {
          isLoading = false;
        });
      }
    } catch (e) {
      print("Error fetching reports: $e");
      setState(() {
        isLoading = false;
      });
    }
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
                _buildReportList(ongoingReports),
                _buildReportList(completedReports),
              ],
            ),
    );
  }

  Widget _buildReportList(List<Map<String, dynamic>> reports) {
    if (reports.isEmpty) {
      return const Center(
        child: Text('No reports available.'),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: reports.length,
      itemBuilder: (context, index) {
        final report = reports[index];
        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => FireTruckMovementPage(
                  reportTitle: report['title']!,
                  fireTruckNumber: report['fireTruckNumber']!,
                ),
              ),
            );
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
                    'Status: ${report['status']}',
                    style: TextStyle(
                      fontSize: 16,
                      color: _getStatusColor(report['status']!),
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
                ],
              ),
            ),
          ),
        );
      },
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
      default:
        return Colors.black;
    }
  }
}
