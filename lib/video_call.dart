import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'activity_page.dart';   // to redirect after thank‑you dialog

class FireReportVideoCallPage extends StatefulWidget {
  const FireReportVideoCallPage({super.key});

  @override
  State<FireReportVideoCallPage> createState() =>
      _FireReportVideoCallPageState();
}

class _FireReportVideoCallPageState extends State<FireReportVideoCallPage> {
  // ---------------------------------------------------------------------------
  // UTILS
  // ---------------------------------------------------------------------------

  String _formatErrorMessage(String error) {
    _logger.fine('Formatting error message for: $error');
    if (error.contains('Failed to create room')) {
      return 'Could not create video session. Please try again later.';
    }
    if (error.contains('SocketException') ||
        error.contains('TimeoutException') ||
        error.contains('Network error')) {
      return 'Network error. Please check your connection and try again.';
    }
    if (error.contains('permission')) {
      return 'Permission denied. Please check app settings.';
    }
    return 'An unexpected error occurred. Please try again.';
  }

  // ---------------------------------------------------------------------------
  // CONFIG
  // ---------------------------------------------------------------------------

  final String _serverUrl = 'https://fourbzone.com/create_daily_room.php';
  final Logger _logger = Logger('VideoCall');
  final DatabaseReference _callsRef =
      FirebaseDatabase.instance.ref().child('Calls');
  final User? _currentUser = FirebaseAuth.instance.currentUser;
  final bool _isDebugMode = true;
  static const int _maxRetries = 3;

  // ---------------------------------------------------------------------------
  // STATE
  // ---------------------------------------------------------------------------

  String _callId = '';
  String _roomUrl = '';
  String _currentAddress = 'Finding location...';
  String _errorMessage = '';
  Position? _currentPosition;

  WebViewController? _webViewController;
  Timer? _callStatusTimer;
  StreamSubscription? _callStatusSubscription;

  bool _isCallActive = false;
  bool _isLoading = true; // overlay while WebView loads
  bool _adminJoined = false;
  bool _isCallEnded = false;

  bool _isVideoEnabled = true;
  bool _isAudioEnabled = true;
  bool _dailyJsReady = false;

  int _retryCount = 0;

  // ---------------------------------------------------------------------------
  // LIFECYCLE
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _setupLogging();
    _initSequence();
  }

  void _setupLogging() {
    if (_isDebugMode) {
      Logger.root.level = Level.ALL;
      Logger.root.onRecord.listen((record) {
        developer.log(record.message,
            time: record.time,
            level: record.level.value,
            name: record.loggerName,
            error: record.error,
            stackTrace: record.stackTrace);
      });
    } else {
      Logger.root.level = Level.INFO;
      Logger.root.onRecord.listen((record) {
        if (record.level >= Level.INFO) {
          developer.log(record.message,
              time: record.time,
              level: record.level.value,
              name: record.loggerName,
              error: record.error,
              stackTrace: record.stackTrace);
        }
      });
    }
    _logger.info('Logging initialized');
  }

  // ---------------------------------------------------------------------------
  // INIT SEQUENCE  (permissions ➜ room ➜ firebase ➜ WebView)
  // ---------------------------------------------------------------------------

  Future<void> _initSequence() async {
    setState(() => _isLoading = true);

    if (!await _checkAndRequestPermissions()) {
      setState(() => _isLoading = false);
      return;
    }

    _getCurrentLocation(); // fire‑and‑forget
    await _initializeCall();

    if (_isCallActive && _roomUrl.isNotEmpty) {
      await _setupWebViewController();
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage =
            _errorMessage.isEmpty ? 'Failed to initialise call.' : _errorMessage;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // PERMISSIONS / LOCATION
  // ---------------------------------------------------------------------------

  Future<bool> _checkAndRequestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.camera,
      Permission.microphone,
      Permission.locationWhenInUse,
    ].request();

    bool ok = (statuses[Permission.camera]?.isGranted ?? false) &&
        (statuses[Permission.microphone]?.isGranted ?? false);

    if (!ok) {
      _errorMessage = 'Camera & Microphone permissions are required.';
    }
    return ok;
  }

  Future<void> _getCurrentLocation() async {
    if (!await Permission.locationWhenInUse.isGranted) {
      setState(() => _currentAddress = 'Location permission denied');
      return;
    }
    try {
      Position pos = await Geolocator.getCurrentPosition(
              locationSettings:
                  const LocationSettings(accuracy: LocationAccuracy.high))
          .timeout(const Duration(seconds: 25));
      _currentPosition = pos;
      await _getAddressFromLatLng();
    } catch (_) {
      setState(() => _currentAddress = 'Location unavailable');
    }
  }

  Future<void> _getAddressFromLatLng() async {
    if (_currentPosition == null) return;
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
          _currentPosition!.latitude, _currentPosition!.longitude);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final parts = [
          p.street,
          p.subLocality,
          p.locality,
          p.postalCode,
          p.country
        ].where((e) => (e ?? '').isNotEmpty).toList();
        setState(() => _currentAddress = parts.join(', '));
      }
    } catch (_) {
      setState(() => _currentAddress = 'Address lookup failed');
    }
  }

  // ---------------------------------------------------------------------------
  // DAILY ROOM / FIREBASE
  // ---------------------------------------------------------------------------

  Future<void> _initializeCall() async {
    if (_currentUser == null) {
      _errorMessage = 'User not logged in';
      return;
    }
    try {
      _callId = const Uuid().v4();
      await _createDailyRoomWithRetries();
      await _addCallToFirebase();
      _monitorCallStatus();
      setState(() => _isCallActive = true);
    } catch (e) {
      _errorMessage = _formatErrorMessage(e.toString());
    }
  }

  Future<void> _createDailyRoomWithRetries() async {
    _retryCount = 0;
    bool created = false;
    String lastError = '';
    while (_retryCount <= _maxRetries && !created) {
      try {
        final res = await http
            .post(Uri.parse(_serverUrl),
                headers: {'Content-Type': 'application/json'},
                body: json.encode(
                    {'roomName': 'emergency-$_callId', 'expiryMinutes': 120}))
            .timeout(const Duration(seconds: 15));
        if (res.statusCode == 200) {
          _roomUrl = json.decode(res.body)['url'] ?? '';
          if (_roomUrl.isEmpty) throw Exception('Empty room URL');
          created = true;
        } else {
          throw Exception(res.body);
        }
      } catch (e) {
        lastError = e.toString();
        _retryCount++;
        if (_retryCount > _maxRetries) throw Exception(lastError);
        await Future.delayed(Duration(seconds: 2 * _retryCount));
      }
    }
    _roomUrl +=
        '${_roomUrl.contains('?') ? '&' : '?'}preferScreenshareSmall=true';
  }

  Future<void> _addCallToFirebase() async {
    final userSnap =
        await FirebaseDatabase.instance.ref('resident/${_currentUser!.uid}').once();
    final userData = (userSnap.snapshot.value is Map)
        ? userSnap.snapshot.value as Map
        : null;
    await _callsRef.child(_callId).set({
      'residentId': _currentUser!.uid,
      'residentName':
          userData?['name'] ?? _currentUser!.displayName ?? 'Unknown',
      'mobile': userData?['mobile'] ?? 'Unknown',
      'time': DateTime.now().toIso8601String(),
      'status': 'Connecting',
      'roomUrl': _roomUrl,
      'address': _currentAddress,
      'latitude': _currentPosition?.latitude ?? 0.0,
      'longitude': _currentPosition?.longitude ?? 0.0,
      'adminHandling': false,
      'adminJoined': false,
      'residentJoined': true,
    });
  }

  // ---------------------------------------------------------------------------
  // CALL STATUS LISTENER
  // ---------------------------------------------------------------------------

  void _monitorCallStatus() {
    _callStatusSubscription?.cancel();
    _callStatusSubscription =
        _callsRef.child(_callId).onValue.listen((event) {
      if (!mounted) return;
      if (event.snapshot.value is! Map) {
        _handleCallEnded(isRemote: true, status: 'Deleted');
        return;
      }
      final data = Map<dynamic, dynamic>.from(event.snapshot.value as Map);

      final bool adminNow = data['adminJoined'] == true;
      if (adminNow != _adminJoined) setState(() => _adminJoined = adminNow);

      final status = data['status'] ?? 'Unknown';

      //  ★ show thank‑you dialog when admin leaves but status is still Answered
      if (status == 'Answered' &&
          data['adminJoined'] == false &&
          !_isCallEnded) {
        _handleCallEnded(isRemote: true, status: 'Answered');
        return;
      }

      // ★ NEW ★ handled by nearby dispatch
      if (status == 'Handled' && !_isCallEnded) {
  _handleCallEnded(isRemote: true, status: 'Handled');
  return;
}

      if (['Ended', 'Missed Call'].contains(status)) {
        _handleCallEnded(isRemote: true, status: status);
      }
    });
  }

  // ---------------------------------------------------------------------------
  // WEBVIEW & DAILY.JS
  // ---------------------------------------------------------------------------

  Future<void> _setupWebViewController() async {
    if (_webViewController != null) return;
    final c = WebViewController(onPermissionRequest: (r) => r.grant());
    await c.setJavaScriptMode(JavaScriptMode.unrestricted);
    await c.setBackgroundColor(const Color(0x00000000));
    await c.addJavaScriptChannel('FlutterChannel',
        onMessageReceived: (msg) => _handleJs(msg.message));
    c.setNavigationDelegate(NavigationDelegate(
      onPageStarted: (_) => mounted ? setState(() => _isLoading = true) : null,
      onPageFinished: (_) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        _injectDailyDetection(c);
      },
    ));
    _webViewController = c;
    await c.loadRequest(Uri.parse(_roomUrl));
    setState(() {}); // rebuild
  }

  void _injectDailyDetection(WebViewController c) {
    const js = '''
      if (window.DailyIframe) {
        window.FlutterChannel.postMessage('DAILY_READY');
      } else {
        const obs = new MutationObserver(() => {
          if (window.DailyIframe || document.querySelector('iframe[allow*="camera"]')) {
            window.FlutterChannel.postMessage('DAILY_READY');
            obs.disconnect();
          }
        });
        obs.observe(document.body, {childList:true, subtree:true});
      }
      window.addEventListener('message', e => {
        if (e.data && e.data.action === 'daily-iframe-ready') {
          const iframe = document.querySelector('iframe[allow*="camera"]');
          if (iframe && iframe.contentWindow) {
            window.call = iframe.contentWindow.call;
            window.FlutterChannel.postMessage('DAILY_JS');
          }
        }
      });
    ''';
    c.runJavaScript(js);
  }

  void _handleJs(String msg) {
    if (msg == 'DAILY_JS') {
      setState(() => _dailyJsReady = true);
      _updateMediaStateInJs();
    }
  }

  // ---------------------------------------------------------------------------
  // END CALL & CLEANUP
  // ---------------------------------------------------------------------------

  void _endCallByUser() async {
    if (_isCallEnded || _callId.isEmpty) return;
    setState(() => _isLoading = true);

    try {
      if (_webViewController != null) {
        await _webViewController!.runJavaScript('''
          (async () => {
            try {
              if (window.call && typeof window.call.leave === 'function') await window.call.leave();
              if (window.call && typeof window.call.destroy === 'function') await window.call.destroy();
            } catch (_) {}
          })();
        ''').timeout(const Duration(seconds: 3));
        await _webViewController!
            .loadRequest(Uri.parse('about:blank'))
            .catchError((_) {});
      }

      await _callsRef.child(_callId).update({
        'status': 'Ended',
        'endTime': DateTime.now().toIso8601String(),
        'residentJoined': false,
      });

      _handleCallEnded(isRemote: false, status: 'Left Meeting');
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Error ending call. Please close the screen manually.')));
      }
      _handleCallEnded(isRemote: false, status: 'Ended (Error)');
    }
  }

  void _handleCallEnded({bool isRemote = false, String status = 'Ended'}) {
    if (_isCallEnded) return;

    if (_webViewController != null) {
      _webViewController!.runJavaScript(
          '(async () => { try { if (window.call && typeof window.call.destroy === "function") await window.call.destroy(); } catch (_) {} })();');
      _webViewController!
          .loadRequest(Uri.parse('about:blank'))
          .catchError((_) {});
    }

    setState(() {
      _isCallEnded = true;
      _isLoading = false;
    });

    _callStatusSubscription?.cancel();
    _callStatusTimer?.cancel();

    if (!isRemote && _callId.isNotEmpty) {
      _callsRef
          .child(_callId)
          .update({'residentJoined': false}).catchError((_) {});
    }

    // ★ thank‑you dialog when admin leaves but status remains Answered
    if (status == 'Answered' && mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Report Received'),
          content: const Text(
              'Thank you for reporting.\nYou will be redirected to the activity page to track your report.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const ActivityPage()),
                  (_) => false,
                );
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    if (status == 'Handled' && mounted) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      title: const Text('Report Already Handled'),
      content: const Text(
        'A team is already dispatched to your location. Thank you for reporting.'),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const ActivityPage()),
              (_) => false,
            );
          },
          child: const Text('OK'),
        )
      ],
    ),
  );
  return;
}

    if (mounted) {
      String msg = 'Call has ended.';
      if (status == 'Missed Call') msg = 'Call missed. No operator joined.';
      else if (status.contains('Error')) msg = 'Call ended due to an error.';
      else if (status == 'Deleted') msg = 'Call record was removed.';
      else if (status == 'Left Meeting') msg = 'You left the meeting.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) Navigator.maybePop(context);
      });
    }
  }

  // ---------------------------------------------------------------------------
  // MEDIA TOGGLES
  // ---------------------------------------------------------------------------

  void _toggleVideo() {
    if (!_dailyJsReady || _webViewController == null) return;
    setState(() => _isVideoEnabled = !_isVideoEnabled);
    _updateMediaStateInJs();
  }

  void _toggleAudio() {
    if (!_dailyJsReady || _webViewController == null) return;
    setState(() => _isAudioEnabled = !_isAudioEnabled);
    _updateMediaStateInJs();
  }

  Future<void> _updateMediaStateInJs() async {
    if (!_dailyJsReady || _webViewController == null) return;
    try {
      await _webViewController!
          .runJavaScript('if(window.call){window.call.setLocalVideo($_isVideoEnabled);}');
      await _webViewController!
          .runJavaScript('if(window.call){window.call.setLocalAudio($_isAudioEnabled);}');
    } catch (e) {
      _logger.severe('Media state JS error: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // RETRY / DISPOSE
  // ---------------------------------------------------------------------------

  void _retryCall() {
    setState(() {
      _callId = '';
      _roomUrl = '';
      _errorMessage = '';
      _isCallActive = false;
      _adminJoined = false;
      _isCallEnded = false;
      _dailyJsReady = false;
      _isLoading = true;
      _webViewController = null;
    });
    _callStatusSubscription?.cancel();
    _callStatusTimer?.cancel();
    _initSequence();
  }

  @override
  void dispose() {
    _callStatusSubscription?.cancel();
    _callStatusTimer?.cancel();
    if (_webViewController != null) {
      _webViewController!.runJavaScript(
          'if(window.call && typeof window.call.destroy==="function"){window.call.destroy();}');
      _webViewController!
          .loadRequest(Uri.parse('about:blank'))
          .catchError((_) {});
    }
    if (_callId.isNotEmpty && !_isCallEnded && _isCallActive) {
      _callsRef
          .child(_callId)
          .update({'residentJoined': false}).catchError((_) {});
    }
    _webViewController = null;
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_errorMessage.isNotEmpty && !_isCallEnded) {
      return Scaffold(
        appBar:
            AppBar(title: const Text('Error'), backgroundColor: Colors.red.shade800),
        body: Center(child: Text(_errorMessage)),
      );
    }

    final bool hasWebView = _webViewController != null;
    final bool showWebLoad = _isLoading && hasWebView;

    return Scaffold(
      appBar: AppBar(
        title: Text(_adminJoined ? 'Call In Progress' : 'Waiting for Operator'),
        backgroundColor:
            _adminJoined ? const Color(0xFFB71C1C) : const Color(0xFFB71C1C),
        actions: [
          if (_dailyJsReady)
            IconButton(
                icon: Icon(
                    _isVideoEnabled ? Icons.videocam : Icons.videocam_off),
                onPressed: _toggleVideo),
          if (_dailyJsReady)
            IconButton(
                icon: Icon(_isAudioEnabled ? Icons.mic : Icons.mic_off),
                onPressed: _toggleAudio),
        ],
      ),
      backgroundColor: Colors.black,
      body: Stack(children: [
        if (hasWebView)
          WebViewWidget(controller: _webViewController!)
        else
          Container(color: Colors.black),
        if (showWebLoad)
          Container(
            color: Colors.black.withOpacity(0.7),
            child: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 15),
                  Text('Loading Video Interface...',
                      style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
          ),
        if (!_adminJoined)
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.8),
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                  const SizedBox(height: 30),
                  Text('Waiting for Fire Department Operator...',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(color: Colors.white),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 15),
                  if (_currentAddress.isNotEmpty &&
                      !_currentAddress.contains('Finding') &&
                      !_currentAddress.contains('unavailable') &&
                      !_currentAddress.contains('denied'))
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text('Location: $_currentAddress',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: Colors.white70),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ),
                  const Spacer(),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.call_end),
                    label: const Text('End Call'),
                    onPressed: _endCallByUser,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 40, vertical: 15),
                      textStyle: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
      ]),
    );
  }
}
