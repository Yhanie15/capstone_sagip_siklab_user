// ignore_for_file: unused_field, use_super_parameters, library_private_types_in_public_api, await_only_futures, deprecated_member_use, prefer_const_constructors, use_build_context_synchronously

import 'dart:async';
import 'dart:convert';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Add Firebase Auth if needed
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart'; // Geocoding package for reverse and forward geocoding
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'home_page.dart';
import 'activity_page.dart';

class FireReportVideoCallPage extends StatefulWidget {
  final String appId;
  final String token;
  final String channelName;

  const FireReportVideoCallPage({
    Key? key,
    required this.appId,
    required this.token,
    required this.channelName,
  }) : super(key: key);

  @override
  _FireReportVideoCallPageState createState() =>
      _FireReportVideoCallPageState();
}

class _FireReportVideoCallPageState extends State<FireReportVideoCallPage> {
  int? _remoteUid;
  bool _localUserJoined = false;
  bool _isMicMuted = false;
  bool _isCameraFront = true;
  late RtcEngine _engine;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isCalling = true;
  late DatabaseReference _databaseReference;
  String? _currentAddress;
  String? _callKey;
  bool _isAnswered = false; // Whether the admin joined

  // New State Variables for Latitude and Longitude
  double? _latitude;
  double? _longitude;

  @override
  void initState() {
    super.initState();
    _databaseReference = FirebaseDatabase.instance.ref().child('Calls');
    _getCurrentLocationAndAddress();
    _initializeAgora();
    _playRingtone();
  }

  Future<void> _initializeAgora() async {
    // Request permissions
    await [Permission.microphone, Permission.camera].request();

    // Initialize Agora
    _engine = createAgoraRtcEngine();
    await _engine.initialize(
      RtcEngineContext(
        appId: widget.appId,
        channelProfile: ChannelProfileType.channelProfileCommunication,
      ),
    );

    // Register event handlers
    _engine.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
          debugPrint('Resident joined the channel');
          _saveCallDetails(); // Save the call details to Firebase
          _notifyAdmin(); // Notify admin about the call
          setState(() {
            _localUserJoined = true;
          });
        },
        onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
          debugPrint('Admin user $remoteUid joined');
          _stopRingtone();
          _updateCallStatus("Answered");
          setState(() {
            _isCalling = false;
            _remoteUid = remoteUid;
            _isAnswered = true;
          });
        },
        onUserOffline: (RtcConnection connection, int remoteUid,
            UserOfflineReasonType reason) {
          debugPrint('Admin user $remoteUid left');
          setState(() {
            _remoteUid = null;
          });
        },
        onLeaveChannel: (RtcConnection connection, RtcStats stats) {
          debugPrint('Resident left the channel. Stats: ${stats.toJson()}');
          // If user leaves the channel but the call was never answered:
          if (!_isAnswered) {
            _updateCallStatus("Missed Call");
          }
        },
      ),
    );

    // Enable Video and Set Role
    await _engine.enableVideo();
    await _engine.setClientRole(role: ClientRoleType.clientRoleBroadcaster);

    // Join Channel
    await _engine.joinChannel(
      token: widget.token,
      channelId: widget.channelName,
      uid: 0,
      options: const ChannelMediaOptions(
        autoSubscribeAudio: true,
        autoSubscribeVideo: true,
        publishCameraTrack: true,
        publishMicrophoneTrack: true,
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
      ),
    );
  }

  Future<void> _getCurrentLocationAndAddress() async {
    try {
      // Check and request location permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        permission = await Geolocator.requestPermission();
        if (permission != LocationPermission.whileInUse &&
            permission != LocationPermission.always) {
          debugPrint('Location permissions are denied');
          return;
        }
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // Store latitude and longitude
      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
      });

      List<Placemark> placemarks =
          await placemarkFromCoordinates(position.latitude, position.longitude);

      Placemark place = placemarks[0];
      setState(() {
        _currentAddress =
            "${place.street}, ${place.subLocality}, ${place.locality}, ${place.postalCode}, ${place.country}";
      });
    } catch (e) {
      debugPrint('Error fetching location/address: $e');
    }
  }

  Future<void> _saveCallDetails() async {
    if (_currentAddress == null) return;

    // Assuming you have a way to get the caller's unique ID, e.g., from the user's auth information
    String callerID = FirebaseAuth.instance.currentUser?.uid ??
        'user_${DateTime.now().millisecondsSinceEpoch}'; // Use Firebase UID or fallback

    final callDetails = {
      'channelName': widget.channelName,
      'callerID': callerID, // Add the callerID here
      'residentName': 'Resident ${DateTime.now().millisecondsSinceEpoch}',
      'address': _currentAddress,
      'latitude': _latitude ?? 0.0, // Save latitude, default to 0.0 if null
      'longitude': _longitude ?? 0.0, // Save longitude, default to 0.0 if null
      'time': DateTime.now().toIso8601String(),
      'status': 'Ongoing',
    };

    DatabaseReference callRef = await _databaseReference.push();
    setState(() {
      _callKey = callRef.key;
    });
    await callRef.set(callDetails);
    debugPrint('Call details saved to Firebase with callerID: $callerID');
  }

  Future<void> _updateCallStatus(String status) async {
    if (_callKey == null) return;
    await _databaseReference.child(_callKey!).update({'status': status});
    debugPrint('Call status updated to $status');
  }

  Future<void> _notifyAdmin() async {
    try {
      final response = await http.post(
        Uri.parse('https://yourserver.com/notify_admin.php'), // Replace with your server URL
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'channel': widget.channelName}),
      );

      if (response.statusCode == 200) {
        debugPrint('Admin notified successfully');
      } else {
        debugPrint('Failed to notify admin');
      }
    } catch (e) {
      debugPrint('Error notifying admin: $e');
    }
  }

  Future<void> _playRingtone() async {
    try {
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      await _audioPlayer.play(AssetSource('ringtone.mp3')); // Ensure ringtone.mp3 is in assets
    } catch (e) {
      debugPrint("Error playing ringtone: $e");
    }
  }

  Future<void> _stopRingtone() async {
    try {
      await _audioPlayer.stop();
    } catch (e) {
      debugPrint("Error stopping ringtone: $e");
    }
  }

  void _toggleMic() async {
    setState(() {
      _isMicMuted = !_isMicMuted;
    });
    await _engine.muteLocalAudioStream(_isMicMuted);
  }

  void _switchCamera() async {
    setState(() {
      _isCameraFront = !_isCameraFront;
    });
    await _engine.switchCamera();
  }

  // Show the "Thank You" dialog
  void _showEndCallDialog() {
    showDialog(
      context: context,
      barrierDismissible: false, // Prevent closing the dialog by tapping outside
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Call Ended'),
          content: const Text(
              'Thank you for calling. You will be redirected to the Activity page to monitor your report.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close the dialog
                // Navigate to ActivityPage
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

  // Show the "Sorry admin didn't answer" dialog
  void _showMissedCallDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Call Ended'),
          content: const Text('Sorry, the admin did not answer your call.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close the dialog
                // Navigate to HomePage
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => const HomePage()),
                );
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    // Stop the ringtone if still playing
    _stopRingtone();

    // Only mark as "Missed Call" if admin never joined.
    // If admin joined, we do not update the status here (retains last status).
    if (!_isAnswered) {
      _updateCallStatus("Missed Call");
    }

    _engine.leaveChannel();
    _engine.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Resident Video Call'),
        backgroundColor: Colors.red,
      ),
      body: Stack(
        children: [
          // Local video preview
          if (_localUserJoined)
            AgoraVideoView(
              controller: VideoViewController(
                rtcEngine: _engine,
                canvas: const VideoCanvas(uid: 0),
              ),
            )
          else
            const Center(child: CircularProgressIndicator()),

          // Show "Calling Admin..." text while waiting
          if (_isCalling)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Text(
                    'Calling Admin...',
                    style: TextStyle(fontSize: 20, color: Colors.grey),
                  ),
                ],
              ),
            ),

          // Control buttons
          Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Mute/Unmute button
                IconButton(
                  icon: Icon(
                    _isMicMuted ? Icons.mic_off : Icons.mic,
                    color: Colors.grey,
                  ),
                  onPressed: _toggleMic,
                  tooltip: _isMicMuted ? 'Unmute' : 'Mute',
                ),
                const SizedBox(width: 20),

                // Switch camera button
                IconButton(
                  icon: Icon(
                    _isCameraFront ? Icons.camera_front : Icons.camera_rear,
                    color: Colors.grey,
                  ),
                  onPressed: _switchCamera,
                  tooltip: 'Switch Camera',
                ),
                const SizedBox(width: 20),

                // End call button
                IconButton(
                  icon: const Icon(Icons.call_end, color: Colors.red),
                  onPressed: () async {
                    // Always stop the ring first
                    await _stopRingtone();

                    // Update call status based on whether it was answered
                    if (_isAnswered) {
                      // Leave the Agora channel
                      await _engine.leaveChannel();
                      // Show the thank you dialog and navigate to ActivityPage
                      _showEndCallDialog();
                    } else {
                      _updateCallStatus("Missed Call");
                      // Leave the Agora channel
                      await _engine.leaveChannel();
                      // Show missed call dialog and navigate to HomePage
                      _showMissedCallDialog();
                    }
                  },
                  tooltip: 'End Call',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
