import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'home_page.dart';
import 'edit_profile_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  _ProfilePageState createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final DatabaseReference _databaseRef = FirebaseDatabase.instance.ref();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Map<String, dynamic>? _userData;

  @override
  void initState() {
    super.initState();
    _fetchLoggedInUserData();
  }

  Future<void> _fetchLoggedInUserData() async {
    try {
      // Get the currently logged-in user
      final User? user = _auth.currentUser;

      if (user != null) {
        // Fetch user data from Firebase Realtime Database
        final snapshot =
            await _databaseRef.child('resident/${user.uid}').get();

        if (snapshot.exists) {
          setState(() {
            _userData = Map<String, dynamic>.from(snapshot.value as Map);
          });
        } else {
          print("No user data found");
        }
      } else {
        print("No user is currently logged in");
      }
    } catch (e) {
      print("Error fetching user data: $e");
    }
  }

  void _navigateToEditProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const EditProfilePage()),
    ).then((_) {
      // Trigger data refresh when returning from EditProfilePage
      _fetchLoggedInUserData();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          'SAGIPSIKLAB',
          style: TextStyle(
            color: Colors.red,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (context) => const HomePage()),
              (route) => false,
            );
          },
        ),
      ),
      body: _userData == null
          ? const Center(child: CircularProgressIndicator())
          : Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.grey[850]!, Colors.redAccent[100]!],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 30,
                          backgroundColor: Colors.grey[400],
                          child: Icon(
                            Icons.person,
                            size: 50,
                            color: Colors.grey[700],
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _userData?['name'] ?? 'Unknown Name',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                _userData?['email'] ?? 'Unknown Email',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                _userData?['mobile'] ?? 'Unknown Mobile',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: _navigateToEditProfile,
                          icon: const Icon(
                            Icons.edit,
                            color: Colors.redAccent,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 40),
                    ListTile(
                      leading: const Icon(Icons.location_on,
                          color: Colors.redAccent),
                      title: const Text(
                        'Location',
                        style: TextStyle(color: Colors.white),
                      ),
                      onTap: () {
                        // Navigate to location settings
                      },
                    ),
                    ListTile(
                      leading:
                          const Icon(Icons.support, color: Colors.redAccent),
                      title: const Text(
                        'Support',
                        style: TextStyle(color: Colors.white),
                      ),
                      onTap: () {
                        // Navigate to support page
                      },
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
