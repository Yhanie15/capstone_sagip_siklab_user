// ignore_for_file: unused_element, use_build_context_synchronously, avoid_print

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/services.dart'; // For exiting the app
import 'signup_screen.dart';
import 'home_page.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart'; // Import for location
import 'package:geocoding/geocoding.dart'; // Import for geocoding

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  LoginScreenState createState() => LoginScreenState();
}

class LoginScreenState extends State<LoginScreen> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  bool isLoading = false;
  bool isPasswordVisible = false;
  // Define Quezon City boundaries using coordinates
  final double _qcNorthLat = 14.7859; // North boundary latitude
  final double _qcSouthLat = 14.5995; // South boundary latitude
  final double _qcEastLong = 121.1329; // East boundary longitude
  final double _qcWestLong = 121.0193; // West boundary longitude

  @override
  void initState() {
    super.initState();
    _checkAppRequirements();
  }

  // Check all app requirements in sequence
  Future<void> _checkAppRequirements() async {
    await _checkTermsAcceptance();
  }

  // Check if terms have been accepted, show terms dialog if not
  Future<void> _checkTermsAcceptance() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool hasAcceptedTerms = prefs.getBool('hasAcceptedTerms') ?? false;
    
    if (!hasAcceptedTerms) {
      // Show terms and conditions dialog
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showTermsAndConditions();
      });
    } else {
      // If terms are accepted, check location
      _checkLocation();
    }
  }

  // Check if the user is in Quezon City
  Future<void> _checkLocation() async {
    setState(() {
      isLoading = true;
    });

    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showLocationError('Location services are disabled. Please enable them to use this app.');
        setState(() {
          isLoading = false;
        });
        return;
      }

      // Check location permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showLocationError('Location permissions are denied. This app requires location access.');
          setState(() {
            isLoading = false;
          });
          return;
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        _showLocationError(
          'Location permissions are permanently denied. Please enable them in your device settings.'
        );
        setState(() {
          isLoading = false;
        });
        return;
      }

      // Get current position
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high
      );
      
      // Check if within Quezon City boundaries
      bool isInQuezonCity = await _isInQuezonCity(position);
      
      // Store location status
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isInQuezonCity', isInQuezonCity);
      
      if (!isInQuezonCity) {
        _showLocationError(
          'This application is only available for Quezon City residents. '
          'You appear to be outside Quezon City.'
        );
      } else {
        // Location is verified, proceed to check login status
        _checkLoginStatus();
      }
    } catch (e) {
      print('Location check error: $e');
      _showLocationError('Failed to determine your location: $e');
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }
  
  // Check if coordinates are within Quezon City
  Future<bool> _isInQuezonCity(Position position) async {
    // Method 1: Check using coordinate boundaries
    bool withinBoundaries = position.latitude <= _qcNorthLat && 
                            position.latitude >= _qcSouthLat && 
                            position.longitude <= _qcEastLong && 
                            position.longitude >= _qcWestLong;
    
    // Method 2: Use geocoding to verify address
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude, 
        position.longitude
      );
      
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        // Check if sublocality, locality or administrativeArea contains "Quezon City"
        bool isQC = place.subLocality?.toLowerCase().contains('quezon city') == true ||
                    place.locality?.toLowerCase().contains('quezon city') == true ||
                    place.administrativeArea?.toLowerCase().contains('quezon city') == true;
                    
        // Use both methods to determine if in Quezon City
        return withinBoundaries || isQC;
      }
    } catch (e) {
      print('Geocoding error: $e');
      // Fall back to coordinate check if geocoding fails
      return withinBoundaries;
    }
    
    return withinBoundaries;
  }

  // Show location error dialog
  void _showLocationError(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Location Required'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                SystemNavigator.pop(); // Exit the app
              },
              child: const Text('Exit App'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _checkLocation(); // Try again
              },
              child: const Text('Try Again'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _checkLoginStatus() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool? isLoggedIn = prefs.getBool('isLoggedIn');

    if (isLoggedIn == true && _auth.currentUser != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const HomePage()),
      );
    }
  }

  void _showTermsAndConditions() {
    showDialog(
      context: context,
      barrierDismissible: false, // User must respond to the dialog
      builder: (BuildContext context) {
        return WillPopScope(
          // Prevent closing with back button
          onWillPop: () async => false,
          child: AlertDialog(
            title: const Text('Terms and Conditions'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Text(
                    'Welcome to our application!',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'By using this application, you agree to the following terms and conditions:\n\n'
                    '1. You will use this application responsibly.\n'
                    '2. Your personal information will be handled as described in our Privacy Policy.\n'
                    '3. You are responsible for maintaining the confidentiality of your account.\n'
                    '4. You will not use the application for any illegal activities.\n'
                    '5. This application is intended for Quezon City residents only and requires location access.\n\n'
                    'Please read our full Terms of Service and Privacy Policy for more details.',
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  // User rejected terms, close app
                  Navigator.of(context).pop();
                  SystemNavigator.pop(); // Exit the app
                },
                child: const Text('Decline'),
              ),
              ElevatedButton(
                onPressed: () async {
                  // User accepted terms
                  SharedPreferences prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('hasAcceptedTerms', true);
                  Navigator.of(context).pop();
                  _checkLocation(); // Check location after accepting terms
                },
                child: const Text('Accept'),
              ),
            ],
          ),
        );
      },
    );
  }

  // Save login state to SharedPreferences
  Future<void> _saveLoginState() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', true);
  }

  // Clear login state from SharedPreferences
  Future<void> _clearLoginState() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', false);
  }

  // Verify app requirements before any action
  Future<bool> _verifyAppRequirements() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool hasAcceptedTerms = prefs.getBool('hasAcceptedTerms') ?? false;
    bool isInQuezonCity = prefs.getBool('isInQuezonCity') ?? false;
    
    if (!hasAcceptedTerms) {
      _showTermsAndConditions();
      return false;
    }
    
    if (!isInQuezonCity) {
      _checkLocation();
      return false;
    }
    
    return true;
  }

  // Sign in with Google
  Future<void> signInWithGoogle() async {
    // Check app requirements first
    bool canProceed = await _verifyAppRequirements();
    if (!canProceed) return;

    setState(() {
      isLoading = true;
    });

    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        setState(() {
          isLoading = false;
        });
        return; // User canceled sign-in
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      if (googleAuth.accessToken == null || googleAuth.idToken == null) {
        throw Exception('Missing Google authentication tokens');
      }

      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      UserCredential userCredential = await _auth.signInWithCredential(credential);
      final User? user = userCredential.user;

      if (user != null) {
        DatabaseReference residentRef = FirebaseDatabase.instance.ref("resident/${user.uid}");

        // Fetch existing data
        DataSnapshot snapshot = await residentRef.get();
        Map<String, dynamic> existingData = snapshot.exists
            ? Map<String, dynamic>.from(snapshot.value as Map)
            : {};

        // Merge existing data with new data, leave mobile and barangay blank if not present
        Map<String, dynamic> updatedData = {
          'name': existingData['name'] ?? user.displayName ?? 'No Name',
          'email': existingData['email'] ?? user.email,
          'mobile': existingData['mobile'] ?? '',
          'barangay': existingData['barangay'] ?? '',
          'residentId': user.uid,
          'createdAt': existingData['createdAt'] ?? DateTime.now().toIso8601String(),
        };

        await residentRef.set(updatedData);
        await _saveLoginState(); // Save login state
      }

      // Navigate to HomePage after successful login
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const HomePage()),
      );
    } catch (e) {
      _handleAuthError(e);
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  // Improved error handling function
  void _handleAuthError(dynamic error) {
    print('Authentication error: $error');
    String errorMessage = 'An unknown error occurred. Please try again.';

    if (error is FirebaseAuthException) {
      // Handle specific Firebase auth errors with user-friendly messages
      switch (error.code) {
        case 'user-not-found':
          errorMessage = 'No account found with this email. Please check or sign up.';
          break;
        case 'wrong-password':
          errorMessage = 'Incorrect password. Please try again or reset your password.';
          break;
        case 'invalid-email':
          errorMessage = 'Please enter a valid email address.';
          break;
        case 'user-disabled':
          errorMessage = 'This account has been disabled. Please contact support.';
          break;
        case 'too-many-requests':
          errorMessage = 'Too many failed login attempts. Please try again later.';
          break;
        case 'network-request-failed':
          errorMessage = 'Network error. Please check your internet connection and try again.';
          break;
        case 'account-exists-with-different-credential':
          errorMessage = 'An account already exists with the same email address but different sign-in credentials.';
          break;
        case 'invalid-credential':
          errorMessage = 'The authentication credential is invalid. Please try again.';
          break;
        case 'operation-not-allowed':
          errorMessage = 'This sign-in method is not enabled. Please contact support.';
          break;
        default:
          errorMessage = 'Authentication error: ${error.message ?? error.code}';
          break;
      }
    } else if (error is Exception) {
      errorMessage = 'Error: ${error.toString()}';
    }

    // Show error dialog
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Login Failed'),
        content: Text(errorMessage),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // Forgot password functionality
  Future<void> resetPassword() async {
    // Check app requirements first
    bool canProceed = await _verifyAppRequirements();
    if (!canProceed) return;

    if (emailController.text.trim().isEmpty) {
      _showSnackBar('Please enter your email address.');
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      await _auth.sendPasswordResetEmail(email: emailController.text.trim());
      _showSnackBar('Password reset email sent. Please check your inbox.');
    } catch (e) {
      String errorMessage = 'Failed to send password reset email.';
      
      if (e is FirebaseAuthException) {
        switch (e.code) {
          case 'invalid-email':
            errorMessage = 'Please enter a valid email address.';
            break;
          case 'user-not-found':
            errorMessage = 'No account found with this email.';
            break;
          default:
            errorMessage = 'Error: ${e.message ?? e.code}';
        }
      }
      
      _showSnackBar(errorMessage);
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // Sign in with email and password
  Future<void> signInUser() async {
    // Check app requirements first
    bool canProceed = await _verifyAppRequirements();
    if (!canProceed) return;

    // Validate input fields
    if (emailController.text.trim().isEmpty || passwordController.text.trim().isEmpty) {
      _showSnackBar('Please enter both email and password.');
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      // Attempt to sign in the user
      await _auth.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      await _saveLoginState(); // Save login state

      // Navigate to HomePage after successful login
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const HomePage()),
      );
    } catch (e) {
      _handleAuthError(e);
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }
  
  // Navigate to signup screen
  Future<void> _navigateToSignup() async {
    // Check app requirements first
    bool canProceed = await _verifyAppRequirements();
    if (!canProceed) return;
    
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SignupScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo and App Title
              Container(
                alignment: Alignment.center,
                child: Column(
                  children: [
                    const SizedBox(height: 40),
                    Image.asset('assets/logo.png', height: 120),
                    const Text(
                      'Welcome Back!',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Sign in to continue.',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),

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
                obscureText: !isPasswordVisible,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () {
                      setState(() {
                        isPasswordVisible = !isPasswordVisible;
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Sign In Button
              isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      onPressed: signInUser,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                        backgroundColor: Colors.blue,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                      ),
                      child: const Text(
                        'Sign In',
                        style: TextStyle(fontSize: 18, color: Colors.white),
                      ),
                    ),

              const SizedBox(height: 20),

              // Google Sign-In Button with Google Icon
              isLoading
                  ? const SizedBox.shrink()
                  : ElevatedButton.icon(
                      onPressed: signInWithGoogle,
                      icon: Image.asset('assets/google_logo.png', height: 30),
                      label: const Text(
                        'Log in with Google',
                        style: TextStyle(fontSize: 18, color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                        backgroundColor: Colors.grey,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                      ),
                    ),

              const SizedBox(height: 20),

              // Forgot Password & Sign Up links
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: resetPassword,
                    child: const Text(
                      'Forgot Password?',
                      style: TextStyle(
                        color: Colors.blue,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _navigateToSignup,
                    child: const Text(
                      'Sign Up',
                      style: TextStyle(
                        color: Colors.blue,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
              
              // Terms and conditions link
              const SizedBox(height: 20),
              TextButton(
                onPressed: _showTermsAndConditions,
                child: const Text(
                  'Terms and Conditions',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 14,
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