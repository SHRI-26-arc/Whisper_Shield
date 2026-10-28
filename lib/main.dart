import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:share_plus/share_plus.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:socket_io_client/socket_io_client.dart' as socket_io_client;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'trusted_contacts_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const WhisperShieldApp());
}

// ============================================================
// CONFIGURATION
// ============================================================

class AppConfig {
  static const String backendUrl = 'http://10.72.175.244:3000';

  // For Chrome/web development, use localhost if your backend
  // is running on the same computer.
  // static const String backendUrl = 'http://localhost:3000';

  static const String triggerEndpoint = '$backendUrl/api/trigger';
  static const String uploadEndpoint = '$backendUrl/api/upload-audio';
}

// ============================================================
// APP
// ============================================================

class WhisperShieldApp extends StatelessWidget {
  const WhisperShieldApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Whisper Shield',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7C4DFF),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

// ============================================================
// HOME SCREEN
// ============================================================

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // SOS STATE
  Timer? _countdownTimer;
  int _countdown = 5;
  bool _countingDown = false;
  bool _sosActive = false;

  // AUDIO
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  String? _recordingPath;

  // GPS
  Position? _emergencyPosition;

  // SOS DATA
  Map<String, dynamic>? _sosData;

  // SECRET PHRASE
  final SpeechToText _speechToText = SpeechToText();
  bool _keywordListening = false;
  String _keywordStatus = 'Starting...';
  bool _shouldKeepKeywordListening = true;

  static const String secretPhrase = 'whisper shield';

  // SOCKET.IO
  socket_io_client.Socket? _socket;
  bool _socketConnected = false;
  String _socketStatus = 'Connecting to emergency network...';

  // BACKEND ALERT
  String _backendStatus = 'Backend not contacted';
  bool _alertSentToBackend = false;

  // AUDIO UPLOAD
  bool _audioUploading = false;
  bool _audioUploaded = false;
  String _audioUploadStatus = 'Audio not uploaded';

  // ==========================================================
  // ==========================================================
  // INITIALIZATION
  // ==========================================================

  @override
  void initState() {
    super.initState();
    _initializeSocket();
    _initializeKeywordSpotting();
    _initializeFirebaseMessaging();
  }

  // ==========================================================
  // FIREBASE CLOUD MESSAGING
  // ==========================================================

  Future<void> _initializeFirebaseMessaging() async {
    try {
      final messaging = FirebaseMessaging.instance;

      // Request permission to display notifications.
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      debugPrint(
        'Notification permission: ${settings.authorizationStatus}',
      );

      if (settings.authorizationStatus ==
          AuthorizationStatus.denied) {
        debugPrint('Notification permission denied.');
        return;
      }

      // Get this phone's Firebase Cloud Messaging token.
      final token = await messaging.getToken();

      if (token != null) {
        debugPrint('FCM DEVICE TOKEN: $token');
      } else {
        debugPrint('FCM token is not available yet.');
      }

      // Listen for refreshed device tokens.
      FirebaseMessaging.instance.onTokenRefresh.listen(
        (newToken) {
          debugPrint('REFRESHED FCM TOKEN: $newToken');
        },
      );

      // Handle notifications while the app is open.
      FirebaseMessaging.onMessage.listen(
        (RemoteMessage message) {
          debugPrint(
            'FCM notification received: '
            '${message.notification?.title}',
          );
          debugPrint('FCM message data: ${message.data}');

          if (!mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                message.notification?.title ??
                    'New safety notification',
              ),
            ),
          );
        },
      );
    } catch (error, stackTrace) {
      debugPrint('Firebase Messaging error: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  @override
  void dispose() {
    _shouldKeepKeywordListening = false;
    _countdownTimer?.cancel();
    _socket?.disconnect();
    _socket?.dispose();
    _audioRecorder.dispose();
    _speechToText.stop();
    super.dispose();
  }

  // ==========================================================

  // ==========================================================
  // SOCKET.IO — REAL-TIME EMERGENCY NETWORK
  // ==========================================================

  void _initializeSocket() {
    // Prevent duplicate socket connections.
    if (_socket != null) {
      debugPrint('Socket.IO is already initialized.');
      return;
    }

    try {
      debugPrint('Initializing Socket.IO...');
      debugPrint('Backend URL: ${AppConfig.backendUrl}');

      _socket = socket_io_client.io(
        AppConfig.backendUrl,
        socket_io_client.OptionBuilder()
            .setTransports(['websocket'])
            .disableAutoConnect()
            .enableReconnection()
            .setReconnectionAttempts(10)
            .setReconnectionDelay(1000)
            .setReconnectionDelayMax(5000)
            .build(),
      );

      // ----------------------------------------------------------
      // CONNECTION SUCCESS
      // ----------------------------------------------------------
      _socket!.onConnect((_) {
        debugPrint('====================================');
        debugPrint('REAL-TIME NETWORK CONNECTED');
        debugPrint('Socket ID: ${_socket?.id}');
        debugPrint('====================================');

        if (!mounted) return;

        setState(() {
          _socketConnected = true;
          _socketStatus = 'Real-time emergency network connected';
        });
      });

      // ----------------------------------------------------------
      // CONNECTION FAILURE
      // ----------------------------------------------------------
      _socket!.onConnectError((error) {
        debugPrint('SOCKET CONNECTION ERROR: $error');

        if (!mounted) return;

        setState(() {
          _socketConnected = false;
          _socketStatus = 'Unable to connect to emergency network';
        });
      });

      // ----------------------------------------------------------
      // GENERAL SOCKET ERROR
      // ----------------------------------------------------------
      _socket!.onError((error) {
        debugPrint('SOCKET ERROR: $error');
      });

      // ----------------------------------------------------------
      // DISCONNECTION
      // ----------------------------------------------------------
      _socket!.onDisconnect((reason) {
        debugPrint('SOCKET DISCONNECTED: $reason');

        if (!mounted) return;

        setState(() {
          _socketConnected = false;
          _socketStatus = 'Real-time network disconnected';
        });
      });

      // ----------------------------------------------------------
      // RECONNECTION ATTEMPTS
      // ----------------------------------------------------------
      _socket!.io.on('reconnect_attempt', (attempt) {
        debugPrint('Socket reconnection attempt: $attempt');

        if (!mounted) return;

        setState(() {
          _socketConnected = false;
          _socketStatus = 'Reconnecting to emergency network...';
        });
      });

      _socket!.io.on('reconnect', (attempt) {
        debugPrint('Socket.IO reconnected after $attempt attempt(s)');
      });

      _socket!.io.on('reconnect_error', (error) {
        debugPrint('SOCKET RECONNECTION ERROR: $error');
      });

      // ----------------------------------------------------------
      // SERVER EVENT LISTENERS
      // ----------------------------------------------------------
      _socket!.on('alert_received', (data) {
        debugPrint('Alert acknowledgement received: $data');
      });

      _socket!.on('update_alert', (data) {
        debugPrint('Alert updated: $data');
      });

      _socket!.on('sos-alert', (data) {
        debugPrint('SOS broadcast received: $data');
      });

      // ----------------------------------------------------------
      // CONNECT
      // ----------------------------------------------------------
      debugPrint('Attempting to connect to backend...');
      _socket!.connect();
    } catch (error, stackTrace) {
      debugPrint('SOCKET INITIALIZATION ERROR: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() {
        _socketConnected = false;
        _socketStatus = 'Real-time network unavailable';
      });
    }
  }

  // ==========================================================
  // SECRET PHRASE LISTENING
  // ==========================================================

  Future<void> _initializeKeywordSpotting() async {
    if (kIsWeb) {
      if (mounted) {
        setState(() {
          _keywordStatus = 'Keyword spotting requires Android/iOS';
        });
      }
      return;
    }

    final bool available = await _speechToText.initialize(
      onStatus: (status) {
        debugPrint('Speech status: $status');

        if (status == 'done') {
          _keywordListening = false;

          if (_shouldKeepKeywordListening &&
              !_sosActive &&
              !_countingDown) {
            Future.delayed(const Duration(milliseconds: 300), () {
              if (mounted &&
                  _shouldKeepKeywordListening &&
                  !_sosActive &&
                  !_countingDown &&
                  !_keywordListening) {
                _startKeywordListening();
              }
            });
          }
        }
      },
      onError: (error) {
        debugPrint('Speech error: $error');
        _keywordListening = false;

        if (mounted) {
          setState(() {
            _keywordStatus =
                'Keyword detection temporarily unavailable';
          });
        }

        if (_shouldKeepKeywordListening &&
            !_sosActive &&
            !_countingDown) {
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted &&
                _shouldKeepKeywordListening &&
                !_sosActive &&
                !_countingDown &&
                !_keywordListening) {
              _startKeywordListening();
            }
          });
        }
      },
    );

    if (!available) {
      if (mounted) {
        setState(() {
          _keywordStatus = 'Microphone permission needed';
        });
      }
      return;
    }

    await _startKeywordListening();
  }

  Future<void> _startKeywordListening() async {
    if (_sosActive || _countingDown) return;

    _shouldKeepKeywordListening = true;

    if (!_speechToText.isAvailable) {
      if (mounted) {
        setState(() {
          _keywordListening = false;
          _keywordStatus = 'Speech recognition unavailable';
        });
      }
      return;
    }

    if (_keywordListening) return;

    _keywordListening = true;

    try {
      await _speechToText.listen(
        listenOptions: SpeechListenOptions(
          listenMode: ListenMode.dictation,
          listenFor: const Duration(minutes: 10),
          pauseFor: const Duration(seconds: 3),
          partialResults: true,
          cancelOnError: false,
        ),
        onResult: (result) {
          final String text =
              result.recognizedWords.toLowerCase().trim();

          debugPrint('Heard: $text');

          if (text.contains('whisper shield') ||
              text.contains('whisper field') ||
              (text.contains('whisper') && text.contains('shield'))) {
            _onKeywordDetected(0);
          }
        },
      );

      if (mounted) {
        setState(() {
          _keywordListening = true;
          _keywordStatus = 'Listening for "$secretPhrase"';
        });
      }
    } catch (error) {
      debugPrint('Keyword listener error: $error');
      _keywordListening = false;

      if (mounted) {
        setState(() {
          _keywordStatus = 'Restarting keyword protection...';
        });
      }

      if (_shouldKeepKeywordListening &&
          !_sosActive &&
          !_countingDown) {
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted &&
              _shouldKeepKeywordListening &&
              !_sosActive &&
              !_countingDown &&
              !_keywordListening) {
            _startKeywordListening();
          }
        });
      }
    }
  }

  Future<void> _stopKeywordListening() async {
    _shouldKeepKeywordListening = false;

    try {
      await _speechToText.stop();
    } catch (_) {}

    if (mounted) {
      setState(() {
        _keywordListening = false;
        _keywordStatus = 'Keyword protection paused';
      });
    }
  }

  Future<void> _onKeywordDetected(int keywordIndex) async {
    if (_sosActive || _countingDown) return;

    await _stopKeywordListening();

    await _runSosCountdown(
      seconds: 3,
      triggeredByKeyword: true,
    );
  }

  // ==========================================================
  // SOS COUNTDOWN
  // ==========================================================

  Future<void> _startSosCountdown() async {
    if (_sosActive || _countingDown) return;

    await _stopKeywordListening();

    await _runSosCountdown(
      seconds: 5,
      triggeredByKeyword: false,
    );
  }

  Future<void> _runSosCountdown({
    required int seconds,
    required bool triggeredByKeyword,
  }) async {
    _countdownTimer?.cancel();

    setState(() {
      _countingDown = true;
      _countdown = seconds;
    });

    final completer = Completer<void>();

    _countdownTimer = Timer.periodic(
      const Duration(seconds: 1),
      (timer) {
        if (_countdown > 1) {
          if (mounted) {
            setState(() {
              _countdown--;
            });
          }
        } else {
          timer.cancel();

          if (!completer.isCompleted) {
            completer.complete();
          }
        }
      },
    );

    await completer.future;

    if (!mounted || !_countingDown) return;

    setState(() {
      _countingDown = false;
      _countdown = 5;
    });

    await _activateEmergencyMode(
      triggeredByKeyword: triggeredByKeyword,
    );
  }

  Future<void> _cancelCountdown() async {
    _countdownTimer?.cancel();

    setState(() {
      _countingDown = false;
      _countdown = 5;
    });

    await _startKeywordListening();
  }

  // ==========================================================
  // GPS
  // ==========================================================

  Future<Position?> _getCurrentLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        debugPrint('Location services are disabled.');
        return null;
      }

      LocationPermission permission =
          await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        debugPrint('Location permission unavailable.');
        return await Geolocator.getLastKnownPosition();
      }

      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 8),
          ),
        );

        debugPrint(
          'Fresh GPS: ${position.latitude}, ${position.longitude}',
        );

        return position;
      } catch (error) {
        debugPrint('Fresh GPS timed out: $error');

        final lastKnown = await Geolocator.getLastKnownPosition();

        if (lastKnown != null) {
          debugPrint(
            'Using last known GPS: '
            '${lastKnown.latitude}, ${lastKnown.longitude}',
          );
        }

        return lastKnown;
      }
    } catch (error) {
      debugPrint('Location error: $error');
      return null;
    }
  }

  // ==========================================================
  // AUDIO RECORDING
  // ==========================================================

Future<String> _startEmergencyRecording() async {
  if (!await _audioRecorder.hasPermission()) {
    throw Exception('Microphone permission was denied.');
  }

  // Persistent app-specific storage, not the temporary directory.
  final dir = await getApplicationDocumentsDirectory();

  final recordingsDir = Directory(
    '${dir.path}/whisper_shield_recordings',
  );

  if (!await recordingsDir.exists()) {
    await recordingsDir.create(recursive: true);
  }

  final path =
      '${recordingsDir.path}/whisper_shield_sos_'
      '${DateTime.now().millisecondsSinceEpoch}.m4a';

  await _audioRecorder.start(
    const RecordConfig(
      encoder: AudioEncoder.aacLc,
      bitRate: 128000,
      sampleRate: 44100,
    ),
    path: path,
  );

  // Verify that the recorder actually started.
  final recording = await _audioRecorder.isRecording();

  if (!recording) {
    throw Exception('Audio recorder did not start.');
  }

  _recordingPath = path;

  debugPrint('Recording started: $path');

  return path;
}

  // ==========================================================
  // SEND SOS TO NODE BACKEND
  // ==========================================================

  Future<int?> _sendAlertToBackend({
    required Position? position,
    required bool triggeredByKeyword,
  }) async {
    try {
      if (mounted) {
        setState(() {
          _backendStatus = 'Sending emergency alert...';
          _alertSentToBackend = false;
        });
      }

      final response = await http
          .post(
            Uri.parse(AppConfig.triggerEndpoint),
            headers: {
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'triggerType':
                  triggeredByKeyword ? 'codeword' : 'manual_sos',
              'location': position == null
                  ? null
                  : {
                      'lat': position.latitude,
                      'lng': position.longitude,
                      'accuracy': position.accuracy,
                    },
              'isOffline': false,
              'timestamp':
                  DateTime.now().toUtc().toIso8601String(),
              'socketConnected': _socketConnected,
            }),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        debugPrint('SOS backend response: ${response.body}');

        int? alertId;

        try {
          final data = jsonDecode(response.body);

          if (data is Map && data['alertId'] != null) {
            alertId = int.tryParse(data['alertId'].toString());
          }
        } catch (error) {
          debugPrint('Could not parse alert ID: $error');
        }

        if (mounted) {
          setState(() {
            _alertSentToBackend = alertId != null;
            _backendStatus = alertId != null
                ? 'Emergency alert sent to backend'
                : 'Alert response missing alert ID';
          });
        }

        return alertId;
      }

      if (mounted) {
        setState(() {
          _backendStatus =
              'Backend returned ${response.statusCode}';
        });
      }

      return null;
    } catch (error) {
      debugPrint('Backend error: $error');

      if (mounted) {
        setState(() {
          _alertSentToBackend = false;
          _backendStatus =
              'Backend unavailable — local SOS continues';
        });
      }

      return null;
    }
  }

  // ==========================================================
  // AUDIO UPLOAD
  // ==========================================================

  Future<void> _uploadEmergencyAudio({
    required String filePath,
    int? alertId,
  }) async {
    if (filePath.isEmpty) {
      if (mounted) {
        setState(() {
          _audioUploading = false;
          _audioUploaded = false;
          _audioUploadStatus = 'No audio file available';
        });
      }
      return;
    }

    final file = File(filePath);

    if (!await file.exists()) {
      if (mounted) {
        setState(() {
          _audioUploading = false;
          _audioUploaded = false;
          _audioUploadStatus = 'Audio file not found';
        });
      }
      return;
    }

    final fileSize = await file.length();

    debugPrint('Audio path: $filePath');
    debugPrint('Audio file size: $fileSize bytes');
    debugPrint('Alert ID: $alertId');

    if (fileSize == 0) {
      if (mounted) {
        setState(() {
          _audioUploading = false;
          _audioUploaded = false;
          _audioUploadStatus = 'Audio recording is empty';
        });
      }
      return;
    }

    if (alertId == null) {
      if (mounted) {
        setState(() {
          _audioUploading = false;
          _audioUploaded = false;
          _audioUploadStatus = 'Missing alert ID';
        });
      }

      debugPrint('Audio upload stopped: alertId is null');
      return;
    }

    if (mounted) {
      setState(() {
        _audioUploading = true;
        _audioUploaded = false;
        _audioUploadStatus = 'Uploading audio...';
      });
    }

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse(AppConfig.uploadEndpoint),
      );

      request.fields['alertId'] = alertId.toString();
      request.fields['timestamp'] =
          DateTime.now().toUtc().toIso8601String();

      request.files.add(
        await http.MultipartFile.fromPath(
          'audio',
          filePath,
        ),
      );

      final streamedResponse = await request
          .send()
          .timeout(const Duration(seconds: 60));

      final response =
          await http.Response.fromStream(streamedResponse);

      debugPrint('Audio upload HTTP status: ${response.statusCode}');
      debugPrint('Audio upload response: ${response.body}');

      final success =
          response.statusCode >= 200 &&
          response.statusCode < 300;

      if (mounted) {
        setState(() {
          _audioUploading = false;
          _audioUploaded = success;
          _audioUploadStatus = success
              ? 'Audio uploaded successfully '
                  '(${(fileSize / 1024).toStringAsFixed(1)} KB)'
              : 'Upload failed: HTTP ${response.statusCode}';
        });
      }
    } catch (error, stackTrace) {
      debugPrint('Audio upload error: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (mounted) {
        setState(() {
          _audioUploading = false;
          _audioUploaded = false;
          _audioUploadStatus = 'Audio upload failed: $error';
        });
      }
    }
  }

  // ==========================================================
  // ACTIVATE SOS
  // ==========================================================

  Future<void> _activateEmergencyMode({
    required bool triggeredByKeyword,
  }) async {
    if (_sosActive) return;

    try {
      await _stopKeywordListening();

      debugPrint('SOS ACTIVATION STARTED');

      Position? position;

      try {
        position = await _getCurrentLocation();
      } catch (error) {
        debugPrint('GPS failed: $error');
      }

      debugPrint('GPS result: $position');

      if (!mounted) return;

      setState(() {
        _emergencyPosition = position;
        _alertSentToBackend = false;
        _audioUploaded = false;
        _audioUploading = false;
        _backendStatus = 'Preparing emergency alert';
        _audioUploadStatus = 'Audio not uploaded';
      });

      String? audioPath;

      try {
        audioPath = await _startEmergencyRecording();
        debugPrint('Emergency recording started: $audioPath');
      } catch (error) {
        debugPrint('Recording failed: $error');

        if (mounted) {
          setState(() {
            _audioUploadStatus = 'Microphone unavailable';
          });
        }
      }
      final int? alertId = await _sendAlertToBackend(
        position: position,
        triggeredByKeyword: triggeredByKeyword,
      );

      final sosData = <String, dynamic>{
        'eventType': 'SOS',
        'trigger': triggeredByKeyword
            ? 'secret_phrase'
            : 'manual_button',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'status': 'active',
        'alertId': alertId,
        'location': position == null
            ? null
            : {
                'latitude': position.latitude,
                'longitude': position.longitude,
                'accuracy': position.accuracy,
              },
        'audio': {
          'filePath': audioPath,
          'format': 'm4a',
          'uploaded': false,
        },
      };

      if (!mounted) {
        if (audioPath != null) {
          try {
            await _audioRecorder.stop();
          } catch (_) {}
        }
        return;
      }

      setState(() {
        _sosActive = true;
        _isRecording = audioPath != null;
        _recordingPath = audioPath;
        _sosData = sosData;
      });

debugPrint('Opening Emergency Screen...');

await Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => EmergencyScreen(
      position: _emergencyPosition,
      recordingPath: _recordingPath,
      isRecording: _isRecording,
      sosData: _sosData,
      triggeredByKeyword: triggeredByKeyword,
      secretPhrase: secretPhrase,
      socketConnected: _socketConnected,
      backendStatus: _backendStatus,
      alertSent: _alertSentToBackend,
      audioUploading: _audioUploading,
      audioUploaded: _audioUploaded,
      audioUploadStatus: _audioUploadStatus,
      onUploadAudio: () => _uploadEmergencyAudio(
        filePath: audioPath ?? '',
        alertId: alertId,
      ),
      onEndSos: _endSos,
      onCallEmergencyServices: _callEmergencyServices,
      onShareLocation: _shareCapturedLocation,
      onMessageTrustedContact: () async {
        final position = _emergencyPosition;

        if (position == null) {
          if (!mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location is not available yet.'),
            ),
          );
          return;
        }

        await _prepareSosSms(
          latitude: position.latitude,
          longitude: position.longitude,
        );
      },
    ),
  ),
);

// If the emergency screen is dismissed, restore a consistent
// state and restart keyword protection.
if (mounted && _sosActive) {
  await _endSos();
}

// If the emergency screen is dismissed, restore a consistent
// state and restart keyword protection.
if (mounted && _sosActive) {
  await _endSos();
}
    } catch (error) {
      debugPrint('SOS ERROR: $error');

      if (_isRecording) {
        try {
          await _audioRecorder.stop();
        } catch (_) {}
      }

      if (!mounted) return;

      setState(() {
        _sosActive = false;
        _isRecording = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not activate SOS: $error'),
        ),
      );

      await _startKeywordListening();
    }
  }

Future<void> _prepareSosSms({
  required double latitude,
  required double longitude,
}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final savedContacts =
        prefs.getString('whisper_shield_trusted_contacts');

    if (savedContacts == null || savedContacts.trim().isEmpty) {
      _showSmsMessage('Please add trusted contacts first.');
      return;
    }

    final decoded = jsonDecode(savedContacts);

    if (decoded is! List) {
      _showSmsMessage('Could not read saved emergency contacts.');
      return;
    }

    final contacts = decoded.whereType<Map>().toList();

    if (contacts.isEmpty) {
      _showSmsMessage('Please add trusted contacts first.');
      return;
    }

    String? phone;

    for (final contact in contacts) {
      final candidate = (contact['phone'] ?? '').toString().trim();

      if (candidate.isNotEmpty) {
        phone = candidate;
        break;
      }
    }

    if (phone == null) {
      _showSmsMessage('No valid trusted-contact phone number found.');
      return;
    }

    final mapsUrl =
        'https://www.google.com/maps/search/?api=1&query='
        '$latitude,$longitude';

    final message =
        'SOS ALERT: I may need help. Please contact me immediately. '
        'My current location: $mapsUrl';

    final smsUri = Uri(
      scheme: 'sms',
      path: phone,
      queryParameters: {'body': message},
    );

    final opened = await launchUrl(smsUri);

    if (!opened) {
      _showSmsMessage('Could not open the SMS app. Please try again.');
    }
  } catch (error, stackTrace) {
    debugPrint('Prepare SOS SMS error: $error');
    debugPrintStack(stackTrace: stackTrace);

    _showSmsMessage('Unable to prepare the emergency SMS.');
  }
}

void _showSmsMessage(String message) {
  if (!mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message)),
  );
}


  // ==========================================================
  // END SOS
  // ==========================================================

  Future<void> _endSos() async {
    if (!_sosActive && !_isRecording) return;

    _shouldKeepKeywordListening = false;

    String? stoppedPath;

    try {
      if (_isRecording) {
        stoppedPath = await _audioRecorder.stop();
      }
    } catch (error) {
      debugPrint('Could not stop recording: $error');
    }

    if (!mounted) return;

    setState(() {
      _sosActive = false;
      _isRecording = false;

      if (stoppedPath != null) {
        _recordingPath = stoppedPath;
      }
    });

    final path = _recordingPath;
    final rawAlertId = _sosData?['alertId'];

    final int? alertId = rawAlertId is int
        ? rawAlertId
        : int.tryParse(rawAlertId?.toString() ?? '');

    if (path != null) {
      await _uploadEmergencyAudio(
        filePath: path,
        alertId: alertId,
      );
    }

    if (!mounted) return;

    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }

    await _startKeywordListening();
  }

  // ==========================================================
  // CALL EMERGENCY SERVICES
  // ==========================================================

  Future<void> _callEmergencyServices() async {
    final uri = Uri(
      scheme: 'tel',
      path: '112',
    );

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  // ==========================================================
  // SHARE LOCATION
  // ==========================================================

  Future<void> _shareCapturedLocation() async {
    final Position? pos = _emergencyPosition;

    if (pos == null) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Location is currently unavailable. Please check GPS permissions.',
          ),
        ),
      );
      return;
    }

    final String mapsUrl =
        'https://www.google.com/maps/search/?api=1&query='
        '${pos.latitude},${pos.longitude}';

    final String message =
        'EMERGENCY — I need help.\n'
        'My current location is:\n'
        '$mapsUrl\n'
        'Please contact me as soon as possible.';

    try {
      await SharePlus.instance.share(
        ShareParams(
          text: message,
          subject: 'Whisper Shield SOS — Emergency Location',
        ),
      );
    } catch (error) {
      debugPrint('Location sharing failed: $error');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not open sharing options. Please try again.',
          ),
        ),
      );
    }
  }

  // ==========================================================
  // HOME UI
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FC),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: const Row(
          children: [
            Icon(
              Icons.shield_rounded,
              color: Color(0xFF7C4DFF),
              size: 30,
            ),
            SizedBox(width: 10),
            Text(
              'Whisper Shield',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF7C4DFF),
                      Color(0xFF9C6DFF),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'You are protected.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Whisper Shield is ready when you need it.',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _networkStatusCard(),
              const SizedBox(height: 18),
              _keywordStatusCard(),
              const SizedBox(height: 25),
              Center(
                child: GestureDetector(
                  onTap: _countingDown || _sosActive
                      ? null
                      : _startSosCountdown,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    width: 190,
                    height: 190,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.red,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.red.withValues(alpha: 0.25),
                          blurRadius: 30,
                          spreadRadius: 8,
                        ),
                      ],
                    ),
                    child: Center(
                      child: _countingDown
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  '$_countdown',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 58,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const Text(
                                  'GET READY',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            )
                          : const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.sos,
                                  color: Colors.white,
                                  size: 55,
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'SOS',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (_countingDown)
                Center(
                  child: OutlinedButton.icon(
                    onPressed: _cancelCountdown,
                    icon: const Icon(Icons.close),
                    label: const Text('CANCEL SOS'),
                  ),
                ),
              const SizedBox(height: 30),
              _statusCard(),
              const SizedBox(height: 18),
              _sectionCard(
                icon: Icons.contacts_rounded,
                title: 'Emergency Contacts',
                subtitle: 'Add and merge trusted contacts.',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const TrustedContactsScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 14),
              _sectionCard(
                icon: Icons.settings_rounded,
                title: 'Settings',
                subtitle: 'Manage preferences.',
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Settings are not implemented yet.',
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 25),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _callEmergencyServices,
                  icon: const Icon(Icons.phone),
                  label: const Text('Call Emergency Services'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // NETWORK STATUS CARD
  // ==========================================================

  Widget _networkStatusCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _socketConnected
              ? Colors.green.shade200
              : Colors.orange.shade200,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _socketConnected
                  ? Colors.green.shade50
                  : Colors.orange.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(
              _socketConnected ? Icons.cloud_done : Icons.cloud_off,
              color: _socketConnected ? Colors.green : Colors.orange,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Real-Time Network',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _socketStatus,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            _socketConnected ? Icons.check_circle : Icons.warning,
            color: _socketConnected ? Colors.green : Colors.orange,
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // KEYWORD STATUS CARD
  // ==========================================================

  Widget _keywordStatusCard() {
    final active = _keywordListening;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: active
              ? Colors.green.shade200
              : Colors.orange.shade200,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: active
                  ? Colors.green.shade50
                  : Colors.orange.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(
              active ? Icons.graphic_eq : Icons.mic_off,
              color: active ? Colors.green : Colors.orange,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Secret Phrase Protection',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _keywordStatus,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          if (active)
            const Icon(Icons.check_circle, color: Colors.green),
        ],
      ),
    );
  }

  // ==========================================================
  // SOS STATUS CARD
  // ==========================================================

  Widget _statusCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _sosActive
              ? Colors.red.shade200
              : Colors.green.shade200,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: _sosActive
                      ? Colors.red.shade50
                      : Colors.green.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _sosActive
                      ? Icons.warning_rounded
                      : Icons.verified_user_rounded,
                  color: _sosActive ? Colors.red : Colors.green,
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _sosActive
                          ? 'Emergency Mode Active'
                          : 'Protection Active',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _sosActive
                          ? (_isRecording
                              ? 'Emergency recording is active.'
                              : 'Emergency mode is active; recording is unavailable.')
                          : 'Whisper Shield is ready for emergencies.',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_sosActive) ...[
            const SizedBox(height: 18),
            _miniStatus(
              'Backend',
              _backendStatus,
              _alertSentToBackend,
            ),
            const SizedBox(height: 8),
            _miniStatus(
              'Audio',
              _audioUploadStatus,
              _audioUploaded,
            ),
          ],
        ],
      ),
    );
  }

  Widget _miniStatus(
    String title,
    String status,
    bool success,
  ) {
    return Row(
      children: [
        Icon(
          success ? Icons.check_circle : Icons.info_outline,
          size: 18,
          color: success ? Colors.green : Colors.orange,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$title: $status',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade700,
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================================
  // SECTION CARD
  // ==========================================================

  Widget _sectionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFFF0EBFF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                icon,
                color: const Color(0xFF7C4DFF),
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// EMERGENCY SCREEN
// ============================================================

class EmergencyScreen extends StatelessWidget {
  final Position? position;
  final String? recordingPath;
  final bool isRecording;
  final Map<String, dynamic>? sosData;
  final bool triggeredByKeyword;
  final String secretPhrase;
  final bool socketConnected;
  final String backendStatus;
  final bool alertSent;
  final bool audioUploading;
  final bool audioUploaded;
  final String audioUploadStatus;

  final Future<void> Function() onUploadAudio;
  final Future<void> Function() onEndSos;
  final Future<void> Function() onCallEmergencyServices;
  final Future<void> Function() onShareLocation;
  final Future<void> Function() onMessageTrustedContact;

  const EmergencyScreen({
    super.key,
    required this.position,
    required this.recordingPath,
    required this.isRecording,
    required this.sosData,
    required this.triggeredByKeyword,
    required this.secretPhrase,
    required this.socketConnected,
    required this.backendStatus,
    required this.alertSent,
    required this.audioUploading,
    required this.audioUploaded,
    required this.audioUploadStatus,
    required this.onUploadAudio,
    required this.onEndSos,
    required this.onCallEmergencyServices,
    required this.onShareLocation,
    required this.onMessageTrustedContact,
  });

  Widget _statusTile({
    required IconData icon,
    required String title,
    required String status,
    required bool active,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: active
              ? Colors.green.withValues(alpha: 0.4)
              : Colors.white12,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: active ? Colors.greenAccent : Colors.white54,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  status,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            active ? Icons.check_circle : Icons.info_outline,
            color: active ? Colors.greenAccent : Colors.white38,
            size: 20,
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasLocation = position != null;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF160909),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const SizedBox(height: 25),
                const Icon(
                  Icons.warning_rounded,
                  color: Colors.red,
                  size: 65,
                ),
                const SizedBox(height: 15),
                const Text(
                  'EMERGENCY MODE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 27,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  triggeredByKeyword
                      ? 'Activated by secret phrase'
                      : 'Activated manually',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 25),

                if (triggeredByKeyword)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.red.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.record_voice_over,
                          color: Colors.redAccent,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Secret phrase detected: "$secretPhrase"',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                if (triggeredByKeyword) const SizedBox(height: 15),

                _statusTile(
                  icon: Icons.location_on,
                  title: 'GPS Location',
                  status: hasLocation
                      ? 'Location captured'
                      : 'Location unavailable',
                  active: hasLocation,
                ),
                const SizedBox(height: 15),

                _statusTile(
                  icon: Icons.mic,
                  title: 'Emergency Audio',
                  status: isRecording
                      ? 'Recording active'
                      : 'Recording stopped or unavailable',
                  active: isRecording,
                ),
                const SizedBox(height: 15),

                _statusTile(
                  icon: Icons.cloud_done,
                  title: 'Backend Alert',
                  status: alertSent ? 'Alert sent' : backendStatus,
                  active: alertSent,
                ),
                const SizedBox(height: 15),

                _statusTile(
                  icon: Icons.cloud_upload,
                  title: 'Cloud Audio',
                  status: audioUploading
                      ? 'Uploading...'
                      : audioUploaded
                          ? 'Uploaded'
                          : audioUploadStatus,
                  active: audioUploaded,
                ),
                const SizedBox(height: 15),

                _statusTile(
                  icon: Icons.wifi,
                  title: 'Real-Time Network',
                  status: socketConnected
                      ? 'Socket.IO connected'
                      : 'Socket.IO disconnected',
                  active: socketConnected,
                ),
                const SizedBox(height: 15),

                _statusTile(
                  icon: Icons.data_object_rounded,
                  title: 'SOS Data',
                  status: sosData != null
                      ? 'Prepared locally'
                      : 'Not prepared',
                  active: sosData != null,
                ),
                const SizedBox(height: 20),

                if (hasLocation)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Captured GPS Data',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _detailRow(
                          'Latitude',
                          position!.latitude.toStringAsFixed(6),
                        ),
                        _detailRow(
                          'Longitude',
                          position!.longitude.toStringAsFixed(6),
                        ),
                        _detailRow(
                          'Accuracy',
                          '${position!.accuracy.toStringAsFixed(1)} m',
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 30),

                // Existing location-sharing button
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: OutlinedButton.icon(
                    onPressed: onShareLocation,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white38),
                    ),
                    icon: const Icon(Icons.share_location),
                    label: const Text('SHARE CAPTURED LOCATION'),
                  ),
                ),
                const SizedBox(height: 12),

                // NEW: Message a saved trusted contact
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton.icon(
                    onPressed: onMessageTrustedContact,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade800,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.sms),
                    label: const Text('MESSAGE TRUSTED CONTACT'),
                  ),
                ),
                const SizedBox(height: 12),

                // Existing audio upload button
                if (recordingPath != null &&
                    !isRecording &&
                    !audioUploaded)
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: OutlinedButton.icon(
                      onPressed: audioUploading ? null : onUploadAudio,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white38),
                      ),
                      icon: audioUploading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.cloud_upload),
                      label: Text(
                        audioUploading
                            ? 'UPLOADING AUDIO...'
                            : 'UPLOAD AUDIO',
                      ),
                    ),
                  ),

                const SizedBox(height: 12),

                // Existing emergency call button
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton.icon(
                    onPressed: onCallEmergencyServices,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.phone),
                    label: const Text('CALL 112'),
                  ),
                ),
                const SizedBox(height: 12),

                // Existing end SOS button
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton.icon(
                    onPressed: onEndSos,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.red.shade900,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    icon: const Icon(Icons.stop_circle),
                    label: const Text(
                      'END SOS',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 15),

                const Text(
                  'Ending SOS stops emergency recording and resumes keyword protection.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 15),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
  // STATUS TILE
  Widget _statusTile({
    required IconData icon,
    required String title,
    required String status,
    required bool active,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: active
              ? Colors.green.withValues(alpha: 0.5)
              : Colors.white12,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: active ? Colors.greenAccent : Colors.white54,
            size: 30,
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  status,
                  style: TextStyle(
                    color: active
                        ? Colors.greenAccent
                        : Colors.white54,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            active ? Icons.check_circle : Icons.cancel,
            color: active ? Colors.greenAccent : Colors.white38,
          ),
        ],
      ),
    );
  }

  // DETAIL ROW
  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: const TextStyle(color: Colors.white54),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
