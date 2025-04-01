// ignore_for_file: unused_field, use_super_parameters, library_private_types_in_public_api, await_only_futures, deprecated_member_use, prefer_const_constructors, use_build_context_synchronously

import 'dart:async';
import 'dart:convert';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
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
  RtcEngine? _engine;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isCalling = true;
  late DatabaseReference _databaseReference;
  late DatabaseReference _adminStatusReference;
  late DatabaseReference _callQueueReference;
  String? _currentAddress;
  String? _callKey;
  bool _isAnswered = false;
  bool _isCallAvailable = true;
  bool _isInitialized = false;
  bool _isCheckingAdminStatus = true;
  bool _adminBusy = false;
  bool _isInQueue = false;
  int _queuePosition = 0;
  Timer? _queueCheckTimer;
  
  // New State Variables
  double? _latitude;
  double? _longitude;
  bool _callRecordCreated = false; // NEW: Track if call record exists in database
  
  Timer? _adminAvailabilityTimer;

  @override
  void initState() {
    super.initState();
    _databaseReference = FirebaseDatabase.instance.ref().child('Calls');
    _adminStatusReference = FirebaseDatabase.instance.ref().child('AdminCallStatus');
    _callQueueReference = FirebaseDatabase.instance.ref().child('CallQueue');
    
    _initialAdminAvailabilityCheck();
  }

  Future<void> _initialAdminAvailabilityCheck() async {
    try {
      setState(() {
        _isCheckingAdminStatus = true;
      });
      
      final snapshot = await _adminStatusReference.get();
      
      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        final inCall = data['inCall'] as bool? ?? false;
        
        if (inCall) {
          setState(() {
            _isCallAvailable = false;
            _adminBusy = true;
            _isCheckingAdminStatus = false;
          });
          
          await _getCurrentLocationAndAddress(); // NEW: Get location before adding to queue
          await _addToCallQueue();
          return;
        }
      }
      
      setState(() {
        _isCallAvailable = true;
        _adminBusy = false;
        _isCheckingAdminStatus = false;
      });
      
      _getCurrentLocationAndAddress();
      _setupAdminStatusListener();
      _initializeAgora();
      _playRingtone();
      
      _adminAvailabilityTimer = Timer.periodic(Duration(seconds: 5), (timer) {
        _checkAdminAvailability();
      });
    } catch (e) {
      debugPrint('Error in initial admin availability check: $e');
      setState(() {
        _isCallAvailable = true;
        _adminBusy = false;
        _isCheckingAdminStatus = false;
      });
      
      _getCurrentLocationAndAddress();
      _setupAdminStatusListener();
      _initializeAgora();
      _playRingtone();
    }
  }

  Future<void> _addToCallQueue() async {
    try {
      // NEW: Create call record if it doesn't exist yet
      if (!_callRecordCreated) {
        await _saveCallDetails();
      }
      
      // Generate a unique ID for this caller
      String callerId = FirebaseAuth.instance.currentUser?.uid ??
          'user_${DateTime.now().millisecondsSinceEpoch}';
      
      // Create queue entry with timestamp for ordering
      Map<String, dynamic> queueEntry = {
        'callerId': callerId,
        'timestamp': ServerValue.timestamp,
        'channelName': widget.channelName,
        'callKey': _callKey, // NEW: Reference to existing call record
        'status': 'waiting',
      };
      
      // Add to queue
      DatabaseReference newQueueRef = _callQueueReference.push();
      await newQueueRef.set(queueEntry);
      
      String queueKey = newQueueRef.key!;
      
      setState(() {
        _isInQueue = true;
      });
      
      _showQueuePositionDialog();
      _startQueuePositionMonitoring(queueKey);
    } catch (e) {
      debugPrint('Error adding to call queue: $e');
      _showAdminBusyDialog();
    }
  }

  void _startQueuePositionMonitoring(String queueKey) {
    _queueCheckTimer?.cancel();
    
    _queueCheckTimer = Timer.periodic(Duration(seconds: 5), (timer) async {
      try {
        final snapshot = await _callQueueReference.orderByChild('timestamp').get();
        
        if (snapshot.exists) {
          final queueData = snapshot.value as Map<dynamic, dynamic>;
          
          List<MapEntry<dynamic, dynamic>> queueList = queueData.entries.toList();
          queueList.sort((a, b) {
            int timestampA = a.value['timestamp'] as int? ?? 0;
            int timestampB = b.value['timestamp'] as int? ?? 0;
            return timestampA.compareTo(timestampB);
          });
          
          int position = queueList.indexWhere((entry) => entry.key == queueKey);
          
          if (position >= 0) {
            setState(() {
              _queuePosition = position + 1;
            });
            
            if (position == 0) {
              bool adminAvailable = await _checkAdminAvailability();
              
              if (adminAvailable) {
                await _callQueueReference.child(queueKey).remove();
                
                _queueCheckTimer?.cancel();
                
                setState(() {
                  _isInQueue = false;
                  _adminBusy = false;
                  _isCallAvailable = true;
                });
                
                // NEW: Don't create a new call record if we already have one
                if (!_isInitialized) {
                  _setupAdminStatusListener();
                  _initializeAgora();
                  _playRingtone();
                }
                
                _adminAvailabilityTimer = Timer.periodic(Duration(seconds: 5), (timer) {
                  _checkAdminAvailability();
                });
              }
            }
          } else {
            _queueCheckTimer?.cancel();
            
            final callSnapshot = await _databaseReference.child(_callKey ?? '').get();
            if (callSnapshot.exists) {
              final callData = callSnapshot.value as Map<dynamic, dynamic>;
              if (callData['status'] == 'Answered') {
                setState(() {
                  _isInQueue = false;
                  _adminBusy = false;
                  _isCallAvailable = true;
                  _isAnswered = true;
                });
              } else {
                _showMissedCallDialog();
              }
            } else {
              _showMissedCallDialog();
            }
          }
        }
      } catch (e) {
        debugPrint('Error checking queue position: $e');
      }
    });
  }

  void _showQueuePositionDialog() {
    if (!mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('In Queue'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('The admin is currently busy with another call.'),
                  const SizedBox(height: 10),
                  Text('Your position in queue: $_queuePosition'),
                  const SizedBox(height: 10),
                  const Text('Please wait for your turn or cancel to try again later.'),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    _queueCheckTimer?.cancel();
                    
                    if (_callKey != null) {
                      _callQueueReference.orderByChild('callerId')
                          .equalTo(FirebaseAuth.instance.currentUser?.uid ?? '')
                          .get()
                          .then((snapshot) {
                        if (snapshot.exists) {
                          final data = snapshot.value as Map<dynamic, dynamic>;
                          data.forEach((key, value) {
                            _callQueueReference.child(key).remove();
                          });
                        }
                      });
                    }
                    
                    Navigator.of(context).pop();
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (context) => const HomePage()),
                    );
                  },
                  child: const Text('Cancel'),
                ),
              ],
            );
          }
        );
      },
    );
  }

  Future<void> _getCurrentLocationAndAddress() async {
    try {
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

  void _setupCallStatusListener() {
    if (_callKey == null) return;
    
    try {
      _databaseReference.child(_callKey!).onValue.listen((event) {
        if (!event.snapshot.exists) return;
        
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        final status = data['status'] as String?;
        final adminHandling = data['adminHandling'] as bool?;
        
        if (status == 'Answered' && adminHandling == true) {
          setState(() {
            _isAnswered = true;
            _isCalling = false;
          });
          _stopRingtone();
        }
        
        if (status == 'Ended') {
          _endCall(wasAnswered: true);
        }
      });
    } catch (e) {
      debugPrint('Error setting up call listener: $e');
    }
  }
  
  void _setupAdminStatusListener() {
    try {
      _adminStatusReference.onValue.listen((event) {
        if (!event.snapshot.exists) return;
        
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        final inCall = data['inCall'] as bool? ?? false;
        final currentCallId = data['currentCallId'] as String? ?? '';
        
        if (inCall && _callKey != null && currentCallId != _callKey) {
          setState(() {
            _adminBusy = true;
            _isCallAvailable = false;
          });
          
          if (_isCalling && !_isAnswered && !_isInQueue) {
            _stopRingtone();
            _addToCallQueue();
            
            if (_isInitialized && _engine != null) {
              _engine!.leaveChannel();
            }
          }
        } else {
          setState(() {
            _adminBusy = false;
            _isCallAvailable = true;
          });
        }
      });
    } catch (e) {
      debugPrint('Error setting up admin status listener: $e');
    }
  }

  Future<bool> _checkAdminAvailability() async {
    try {
      if (_adminBusy) return false;
      
      final snapshot = await _adminStatusReference.get();
      
      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        final inCall = data['inCall'] as bool? ?? false;
        final currentCallId = data['currentCallId'] as String? ?? '';
        
        if (inCall && _callKey != null && currentCallId != _callKey) {
          setState(() {
            _adminBusy = true;
            _isCallAvailable = false;
          });
          
          if (_isCalling && !_isAnswered && !_isInQueue) {
            _stopRingtone();
            _addToCallQueue();
            
            if (_isInitialized && _engine != null) {
              _engine!.leaveChannel();
            }
            
            return false;
          }
        } else {
          setState(() {
            _adminBusy = false;
            _isCallAvailable = true;
          });
        }
      } else {
        setState(() {
          _adminBusy = false;
          _isCallAvailable = true;
        });
      }
      return !_adminBusy;
    } catch (e) {
      debugPrint('Error checking admin availability: $e');
      return true;
    }
  }

  void _showAdminBusyDialog() {
    _adminAvailabilityTimer?.cancel();
    
    if (!mounted) return;
    
    if (_adminBusy && Navigator.of(context).canPop()) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Admin Busy'),
          content: const Text('The admin is currently on another call. Please try again later.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _endCall(wasAnswered: false);
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

  Future<void> _initializeAgora() async {
    if (_adminBusy) return;
    
    if (_isInitialized) return;
    
    await [Permission.microphone, Permission.camera].request();

    _engine = createAgoraRtcEngine();
    await _engine!.initialize(
      RtcEngineContext(
        appId: widget.appId,
        channelProfile: ChannelProfileType.channelProfileCommunication,
      ),
    );

    _engine!.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
          debugPrint('Resident joined the channel');
          _saveCallDetails(); // This will now check if a record already exists
          _notifyAdmin();
          setState(() {
            _localUserJoined = true;
            _isInitialized = true;
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
          
          if (_isAnswered) {
            _endCall(wasAnswered: true);
          }
        },
        onLeaveChannel: (RtcConnection connection, RtcStats stats) {
          debugPrint('Resident left the channel. Stats: ${stats.toJson()}');
          if (!_isAnswered) {
            _updateCallStatus("Missed Call");
          }
        },
      ),
    );

    await _engine!.enableVideo();
    await _engine!.setClientRole(role: ClientRoleType.clientRoleBroadcaster);

    await _engine!.joinChannel(
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

  // MODIFIED: Check if call record already exists before creating a new one
  Future<void> _saveCallDetails() async {
    // NEW: Check if call record already exists
    if (_callRecordCreated) {
      debugPrint('Call record already exists, skipping creation');
      return;
    }
    
    if (_currentAddress == null) return;

    String callerID = FirebaseAuth.instance.currentUser?.uid ??
        'user_${DateTime.now().millisecondsSinceEpoch}';

    String uniqueChannelName = widget.channelName;

    final callDetails = {
      'channelName': widget.channelName,
      'uniqueChannelName': uniqueChannelName,
      'callerID': callerID,
      'residentName': 'Resident ${DateTime.now().millisecondsSinceEpoch}',
      'address': _currentAddress,
      'latitude': _latitude ?? 0.0,
      'longitude': _longitude ?? 0.0,
      'time': DateTime.now().toIso8601String(),
      'status': 'Ongoing',
      'adminHandling': false,
      'residentUID': callerID,
    };

    DatabaseReference callRef = await _databaseReference.push();
    setState(() {
      _callKey = callRef.key;
      _callRecordCreated = true; // NEW: Mark as created
    });
    await callRef.set(callDetails);
    debugPrint('Call details saved to Firebase with callerID: $callerID');
    
    _setupCallStatusListener();
  }

  Future<void> _updateCallStatus(String status) async {
    if (_callKey == null) return;
    await _databaseReference.child(_callKey!).update({'status': status});
    debugPrint('Call status updated to $status');
  }

  Future<void> _notifyAdmin() async {
    try {
      final response = await http.post(
        Uri.parse('https://localhost:3000/notify_admin.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'channel': widget.channelName,
          'callId': _callKey,
        }),
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
      await _audioPlayer.play(AssetSource('ringtone.mp3'));
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
    if (_engine == null) return;
    
    setState(() {
      _isMicMuted = !_isMicMuted;
    });
    await _engine!.muteLocalAudioStream(_isMicMuted);
  }

  void _switchCamera() async {
    if (_engine == null) return;
    
    setState(() {
      _isCameraFront = !_isCameraFront;
    });
    await _engine!.switchCamera();
  }

  Future<void> _endCall({required bool wasAnswered}) async {
    _adminAvailabilityTimer?.cancel();
    _queueCheckTimer?.cancel();
    
    await _stopRingtone();
    
    if (_isInQueue) {
      _callQueueReference.orderByChild('callerId')
          .equalTo(FirebaseAuth.instance.currentUser?.uid ?? '')
          .get()
          .then((snapshot) {
        if (snapshot.exists) {
          final data = snapshot.value as Map<dynamic, dynamic>;
          data.forEach((key, value) {
            _callQueueReference.child(key).remove();
          });
        }
      });
    }
    
    if (_callKey != null) {
      if (wasAnswered) {
        await _updateCallStatus("Ended");
      } else {
        await _updateCallStatus("Missed Call");
      }
    }
    
    if (_isInitialized && _engine != null) {
      await _engine!.leaveChannel();
    }
    
    if (mounted) {
      if (wasAnswered) {
        _showEndCallDialog();
      } else {
        _showMissedCallDialog();
      }
    }
  }

  void _showEndCallDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Call Ended'),
          content: const Text(
              'Thank you for calling. You will be redirected to the Activity page to monitor your report.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
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
                Navigator.of(context).pop();
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
    _stopRingtone();
    _adminAvailabilityTimer?.cancel();
    _queueCheckTimer?.cancel();
    
    if (_isInQueue) {
      _callQueueReference.orderByChild('callerId')
          .equalTo(FirebaseAuth.instance.currentUser?.uid ?? '')
          .get()
          .then((snapshot) {
        if (snapshot.exists) {
          final data = snapshot.value as Map<dynamic, dynamic>;
          data.forEach((key, value) {
            _callQueueReference.child(key).remove();
          });
        }
      });
    }

    if (!_isAnswered && _callKey != null) {
      _updateCallStatus("Missed Call");
    }

    if (_isInitialized && _engine != null) {
      _engine!.leaveChannel();
      _engine!.release();
    }
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
          if (_isCheckingAdminStatus)
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    'Checking admin availability...',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ],
              ),
            )
          else if (_isInQueue)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.queue, size: 48, color: Colors.orange),
                  SizedBox(height: 16),
                  Text(
                    'You are in queue',
                    style: TextStyle(fontSize: 18, color: Colors.orange),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Position: $_queuePosition',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Please wait for your turn',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else if (_adminBusy)
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, size: 48, color: Colors.red),
                  SizedBox(height: 16),
                  Text(
                    'Admin is currently busy with another call',
                    style: TextStyle(fontSize: 18, color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Please try again later',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else if (_localUserJoined && _engine != null)
            AgoraVideoView(
              controller: VideoViewController(
                rtcEngine: _engine!,
                canvas: const VideoCanvas(uid: 0),
              ),
            )
          else if (!_adminBusy)
            const Center(child: CircularProgressIndicator()),

          if (_isCalling && !_adminBusy && !_isCheckingAdminStatus && !_isInQueue)
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

          if (!_isCheckingAdminStatus && !_adminBusy && !_isInQueue)
            Positioned(
              bottom: 50,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: Icon(
                      _isMicMuted ? Icons.mic_off : Icons.mic,
                      color: Colors.grey,
                    ),
                    onPressed: _toggleMic,
                    tooltip: _isMicMuted ? 'Unmute' : 'Mute',
                  ),
                  const SizedBox(width: 20),

                  IconButton(
                    icon: Icon(
                      _isCameraFront ? Icons.camera_front : Icons.camera_rear,
                      color: Colors.grey,
                    ),
                    onPressed: _switchCamera,
                    tooltip: 'Switch Camera',
                  ),
                  const SizedBox(width: 20),

                  IconButton(
                    icon: const Icon(Icons.call_end, color: Colors.red),
                    onPressed: () => _endCall(wasAnswered: _isAnswered),
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
