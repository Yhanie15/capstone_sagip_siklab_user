import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';  // For Realtime Database
import 'package:flutter/material.dart';
import 'login_screen.dart';

// Example data for Districts and Barangays
const Map<String, List<String>> districtsAndBarangays = {
  'District 1': ['Barangay 1A', 'Barangay 1B', 'Barangay 1C'],
  'District 2': ['Barangay 2A', 'Barangay 2B', 'Barangay 2C'],
  'District 3': ['Barangay 3A', 'Barangay 3B', 'Barangay 3C'],
  'District 4': ['Barangay 4A', 'Barangay 4B', 'Barangay 4C'],
  'District 5': ['Barangay 5A', 'Barangay 5B', 'Barangay 5C'],
  'District 6': ['Barangay 6A', 'Barangay 6B', 'Barangay 6C'],
};

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  SignupScreenState createState() => SignupScreenState();
}

class SignupScreenState extends State<SignupScreen> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController nameController = TextEditingController();
  final TextEditingController mobileController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseDatabase _database = FirebaseDatabase.instance;
  
  String? selectedDistrict;
  String? selectedBarangay;

  bool isLoading = false;

  // Sign Up user function
  Future<void> signUpUser() async {
  setState(() {
    isLoading = true;
  });

  try {
    // Creating a user with email and password
    UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
      email: emailController.text.trim(),
      password: passwordController.text.trim(),
    );

    // Save user data in Firebase Realtime Database under the "resident" node
    await _database.ref("resident/${userCredential.user!.uid}").set({
      'name': nameController.text.trim(),
      'email': userCredential.user!.email,
      'mobile': mobileController.text.trim(),
      'district': selectedDistrict,
      'barangay': selectedBarangay,
      'createdAt': DateTime.now().toIso8601String(),
    });

    // Navigate to login screen after successful signup
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  } catch (e) {
    print(e);
    // Show error message if signup fails
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Error'),
          content: Text(e.toString()),
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

  setState(() {
    isLoading = false;
  });
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // White background
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo and text at the top
              Container(
                alignment: Alignment.center,
                child: Column(
                  children: [
                    Image.asset('assets/text.png', height: 120), // Logo from assets
                    const SizedBox(height: 20),
                    const Text(
                      'Create New Account',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),

              // Name text field
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Full Name',
                  prefixIcon: Icon(Icons.person),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),

              // Mobile Number text field
              TextField(
                controller: mobileController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Mobile Number',
                  prefixIcon: Icon(Icons.phone),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),

              // Email text field
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),

              // Password text field
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  prefixIcon: Icon(Icons.lock),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),

              // District dropdown
              DropdownButtonFormField<String>(
                value: selectedDistrict,
                hint: const Text('Select District'),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.location_city),
                ),
                onChanged: (newDistrict) {
                  setState(() {
                    selectedDistrict = newDistrict;
                    selectedBarangay = null;  // Reset barangay when district changes
                  });
                },
                items: districtsAndBarangays.keys.map((district) {
                  return DropdownMenuItem<String>(
                    value: district,
                    child: Text(district),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              // Barangay dropdown (only enabled after selecting a district)
              if (selectedDistrict != null)
                DropdownButtonFormField<String>(
                  value: selectedBarangay,
                  hint: const Text('Select Barangay'),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.place),
                  ),
                  onChanged: (newBarangay) {
                    setState(() {
                      selectedBarangay = newBarangay;
                    });
                  },
                  items: districtsAndBarangays[selectedDistrict]!
                      .map((barangay) {
                    return DropdownMenuItem<String>(
                      value: barangay,
                      child: Text(barangay),
                    );
                  }).toList(),
                ),
              const SizedBox(height: 20),

              // Sign Up Button
              isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      onPressed: signUpUser,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                        backgroundColor: Colors.blue,  // Use 'backgroundColor' instead of 'primary'
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                      ),
                      child: const Text(
                        'Sign Up',
                        style: TextStyle(fontSize: 18),
                      ),
                    ),

              const SizedBox(height: 20),

              // Already have an account text
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const LoginScreen()),
                  );
                },
                child: const Text(
                  'Already have an account? Login',
                  style: TextStyle(
                    color: Colors.blue,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
