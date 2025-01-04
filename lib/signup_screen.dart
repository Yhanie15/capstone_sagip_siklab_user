// ignore_for_file: use_build_context_synchronously, avoid_print, prefer_interpolation_to_compose_strings

import 'dart:convert';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart'; // For Realtime Database
import 'package:flutter/material.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
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
  final TextEditingController codeController = TextEditingController(); // Controller for Verification Code
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseDatabase _database = FirebaseDatabase.instance;

  String? selectedDistrict;
  String? selectedBarangay;

  bool isLoading = false;
  bool isCodeSent = false;

  // For toggling password visibility
  bool _obscurePassword = true;

  // SMTP Server Configuration
  final String smtpServerHost = 'smtp.gmail.com'; // Gmail SMTP server
  final int smtpServerPort = 465; // SSL port for Gmail
  final String smtpUsername = 'schoolmatter.54321@gmail.com'; // Your Gmail address
  final String smtpPassword = 'rusrhycdkqsrhfnz'; // Your App Password (16 characters, no spaces)

  // Generate a 6-digit verification code
  String generateVerificationCode() {
    final Random random = Random();
    return (100000 + random.nextInt(900000)).toString();
  }

  // Encode email to base64 to use as a key in Firebase Realtime Database
  String encodeEmail(String email) {
    return base64Url.encode(utf8.encode(email));
  }

  // Send verification code via email
  Future<void> sendVerificationCode(String email, String code) async {
    final smtpServer = SmtpServer(
      smtpServerHost,
      port: smtpServerPort,
      username: smtpUsername,
      password: smtpPassword,
      ssl: true, // Enable SSL for port 465
      ignoreBadCertificate: false, // Set to true only for testing
    );

    final message = Message()
      ..from = Address(smtpUsername, 'Sagip Siklab')
      ..recipients.add(email)
      ..subject = 'Your Verification Code'
      ..text = 'Your verification code is: $code';

    try {
      final sendReport = await send(message, smtpServer);
      print('Message sent: ' + sendReport.toString());
    } on MailerException catch (e) {
      print('Message not sent. \n' + e.toString());
      for (var p in e.problems) {
        print('Problem: ${p.code}: ${p.msg}');
      }
      throw Exception('Failed to send verification code. Please try again.');
    } catch (e) {
      print('Unexpected error: $e');
      throw Exception('Failed to send verification code. Please try again.');
    }
  }

  // Handle Get Code button press
  Future<void> handleGetCode() async {
    final email = emailController.text.trim();
    if (email.isEmpty) {
      showErrorDialog('Please enter your email to get the verification code.');
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      // Generate verification code
      final code = generateVerificationCode();

      // Send the code via email
      await sendVerificationCode(email, code);

      // Store the code in Firebase Realtime Database with an expiration time (e.g., 10 minutes)
      final String encodedEmail = encodeEmail(email);
      await _database.ref('email_verification/$encodedEmail').set({
        'code': code,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      setState(() {
        isCodeSent = true;
      });

      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Verification Code Sent'),
            content: const Text('A verification code has been sent to your email.'),
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
    } on FirebaseException catch (e) {
      // Handle Firebase-specific errors
      print('Firebase error: $e');
      showErrorDialog('Failed to store verification code. Please try again.');
    } catch (e) {
      print('General error: $e');
      showErrorDialog(e.toString());
    }

    setState(() {
      isLoading = false;
    });
  }

  // Show error dialog
  void showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Error'),
          content: Text(message),
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

  // Sign Up user function with code verification
  Future<void> signUpUser() async {
    final email = emailController.text.trim();
    final code = codeController.text.trim();

    if (email.isEmpty ||
        passwordController.text.trim().isEmpty ||
        nameController.text.trim().isEmpty ||
        mobileController.text.trim().isEmpty ||
        selectedDistrict == null ||
        selectedBarangay == null) {
      showErrorDialog('Please fill in all the required fields.');
      return;
    }

    if (!isCodeSent) {
      showErrorDialog('Please get the verification code first.');
      return;
    }

    if (code.isEmpty) {
      showErrorDialog('Please enter the verification code.');
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      // Retrieve the stored code from Firebase Realtime Database
      final String encodedEmail = encodeEmail(email);
      final DataSnapshot snapshot =
          await _database.ref('email_verification/$encodedEmail').get();

      if (!snapshot.exists) {
        throw Exception('No verification code found for this email. Please request a new code.');
      }

      final data = snapshot.value as Map<dynamic, dynamic>;
      final storedCode = data['code'] as String?;
      final timestamp = data['timestamp'] as int?;

      if (storedCode == null || timestamp == null) {
        throw Exception('Invalid verification data. Please request a new code.');
      }

      // Check if the code has expired (e.g., valid for 10 minutes)
      final currentTime = DateTime.now().millisecondsSinceEpoch;
      if (currentTime - timestamp > 10 * 60 * 1000) { // 10 minutes in milliseconds
        throw Exception('The verification code has expired. Please request a new code.');
      }

      if (code != storedCode) {
        throw Exception('The verification code is incorrect.');
      }

      // Proceed with creating the user
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: passwordController.text.trim(),
      );

      // Add the new user's data to the "resident" node
      await _database.ref("resident/${userCredential.user!.uid}").set({
        'residentId': userCredential.user!.uid,
        'name': nameController.text.trim(),
        'email': userCredential.user!.email,
        'mobile': mobileController.text.trim(),
        'district': selectedDistrict,
        'barangay': selectedBarangay,
        'createdAt': DateTime.now().toIso8601String(),
      });

      // Optionally, remove the verification code from the database
      await _database.ref('email_verification/$encodedEmail').remove();

      // Navigate to login screen after successful signup
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    } on FirebaseAuthException catch (e) {
      print('FirebaseAuthException: $e');
      String errorMessage = 'An error occurred during signup.';
      if (e.code == 'email-already-in-use') {
        errorMessage = 'This email is already in use.';
      } else if (e.code == 'weak-password') {
        errorMessage = 'The password provided is too weak.';
      }
      showErrorDialog(errorMessage);
    } on FirebaseException catch (e) {
      print('FirebaseException: $e');
      showErrorDialog('Failed to verify the code. Please try again.');
    } catch (e) {
      print('General Exception: $e');
      // Show error message if signup fails
      showErrorDialog(e.toString());
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
            // mainAxisAlignment: MainAxisAlignment.center, // Removed to allow scrolling
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

              // Email text field with Get Code button
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: isLoading ? null : handleGetCode,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(100, 50),
                      backgroundColor: Colors.blue, // Use 'backgroundColor' instead of 'primary'
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                    ),
                    child: isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.0,
                            ),
                          )
                        : const Text(
                            'Get Code',
                            style: TextStyle(fontSize: 14),
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Verification Code text field (visible after code is sent)
              if (isCodeSent)
                TextField(
                  controller: codeController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Verification Code',
                    prefixIcon: Icon(Icons.verified),
                    border: OutlineInputBorder(),
                  ),
                ),
              if (isCodeSent) const SizedBox(height: 20),

              // Password text field with eye icon to toggle visibility
              TextField(
                controller: passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
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
                    selectedBarangay = null; // Reset barangay when district changes
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
              if (selectedDistrict != null) const SizedBox(height: 20),

              // Sign Up Button
              isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      onPressed: signUpUser,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                        backgroundColor: Colors.blue, // Use 'backgroundColor' instead of 'primary'
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
