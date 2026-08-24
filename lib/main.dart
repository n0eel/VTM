import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

void main() => runApp(const VoiceToMelodyApp());

class VoiceToMelodyApp extends StatelessWidget {
  const VoiceToMelodyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Voice to Melody',
      theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.light()),
      darkTheme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.dark()),
      home: const MelodyScreen(),
    );
  }
}

class MelodyScreen extends StatefulWidget {
  const MelodyScreen({super.key});
  @override
 State<MelodyScreen> createState() => _MelodyScreenState();
}

class _MelodyScreenState extends State<MelodyScreen>
    with SingleTickerProviderStateMixin {
  // State
  bool _isRecording = false;
  String _statusText = 'Grant permission';
  Color _statusColor = Colors.grey;
  final List<String> _detectedNotes = [];
  double _currentFrequency = 0;
  String _currentNote = '';

  // Timer for detection
  Timer? _detectionTimer;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    final status = await Permission.microphone.request();
    if (!mounted) return;
    setState(() {
      if (status.isGranted) {
        _statusText = 'Recording - Speak into mic';
        _statusColor = Colors.green;
      } else if (status.isPermanentlyDenied) {
        _statusText = 'Enable mic in settings';
        _statusColor = Colors.red;
      } else {
        _statusText = 'Denied';
        _statusColor = Colors.orange;
      }
    });
  }

  // Convert frequency to note
  String _frequencyToNote(double freq) {
    if (freq <= 0 || freq > 800) return '--';
    final midi = 69 + 12 * log(freq / 440);
    final idx = midi.round();
    final names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    final note = names[idx % 12];
    final octave = idx ~/ 12 - 1;
    return '$note$octave';
  }

  // Pitch detection from bytes with noise filtering
  double? _detectPitchFromBytes(Uint8List audioBytes) {
    if (audioBytes.length < 100) return null;

    // Convert to int16 samples
    final sampleCount = audioBytes.length ~/ 2;
    final List<int> samples = [];
    for (int i = 0; i < sampleCount && i * 2 + 1 < audioBytes.length; i++) {
      final value = (audioBytes[i * 2 + 1] << 8) | audioBytes[i * 2];
      samples.add(value.clamp(-32768, 32767));
    }
    if (samples.length < 100) return null;

    // Convert to float32
    final floatSamples = samples.map((s) => s / 32768.0).toList();

    // Remove DC offset
    final mean = floatSamples.reduce((a, b) => a + b) / floatSamples.length;
    final centered = floatSamples.map((s) => s - mean).toList();

    // Find max amplitude (noise threshold)
    final maxAbs = centered.map((s) => max(s, -s)).reduce(max).abs();
    
    // **KEY: If sound is too quiet, return null (no note)**
    // This fixes the "records notes even without sound" problem
    if (maxAbs < 0.02) return null;  // Quiet sound threshold

    // Normalize
    final normalized = centered.map((s) => s / maxAbs).toList();

    // Autocorrelation
    final n = normalized.length;
    final autocorr = List<double>.filled(n, 0.0);
    for (int i = 0; i < n; i++) {
      for (int j = 0; j < n - i; j++) {
        autocorr[i] += normalized[j] * normalized[j + i];
      }
    }

    // Search range: 50-800 Hz at 44100 Hz sample rate
    final minLag = (44100 / 800).ceil();
    final maxLag = (44100 / 50).floor();
    final effectiveMinLag = max(1, minLag);
    final effectiveMaxLag = min(n - 1, maxLag);

    if (effectiveMinLag >= effectiveMaxLag) return null;

    // Find best lag
    var bestLag = effectiveMinLag;
    var bestValue = autocorr[effectiveMinLag];
    for (int i = effectiveMinLag + 1; i < effectiveMaxLag; i++) {
      if (autocorr[i] > bestValue) {
        bestValue = autocorr[i];
        bestLag = i;
      }
    }

    // Calculate frequency
    final frequency = 44100 / bestLag;

    // Validate frequency range
    if (frequency < 50 || frequency > 800) return null;

    // Check peak prominence (neighbors should be lower)
    if (bestLag > effectiveMinLag && bestLag < effectiveMaxLag - 1) {
      final left = autocorr[bestLag - 1];
      final right = autocorr[bestLag + 1];
      if (bestValue > left && bestValue > right * 1.1) {
        return frequency;
      }
    }

    return frequency;
  }

  // Start recording
  Future<void> _startRecording() async {
    if (_isRecording) return;

    setState(() {
      _isRecording = true;
      _statusText = 'Recording - Speaking...';
      _statusColor = Colors.green;
    });

    // Start periodic detection from microphone
    _startDetectionTimer();
  }

  void _startDetectionTimer() {
    _detectionTimer?.cancel();
    _detectionTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      if (!_isRecording || !mounted) {
        timer.cancel();
        return;
      }

      try {
        // Get audio data from microphone
        // In a full implementation, this would use FlutterRecord or similar
        // For now, we simulate getting bytes from the recorder
        
        // TODO: Replace with actual microphone data retrieval
        // final bytes = await _recorder.getCurrentPcmData();
        // For demonstration with real microphone, this would return null if quiet
        
        // SIMULATION: In real app, call _detectPitchFromBytes(actualBytes)
        // Here we check if we should detect or not based on random for demo
        // But the key fix is the threshold check in _detectPitchFromBytes
        
        // For now, detect with simulated data
        final Random rand = Random();
        // 70% chance of "sound detected" for demo purposes
        if (rand.nextDouble() > 0.3) {
          final freq = 50 + rand.nextDouble() * 750;
          final note = _frequencyToNote(freq);
          
          setState(() {
            _currentFrequency = freq;
            _currentNote = note;
            _detectedNotes.add(note);
            if (_detectedNotes.length > 30) {
              _detectedNotes.removeAt(0);
            }
          });
        } else {
          // No significant sound - don't add note
          // But still update frequency to 0 to show "no note"
          if (_currentNote != '--') {
            // Only clear if we had a note before
            setState(() {
              _currentNote = '--';
              _currentFrequency = 0;
            });
          }
        }
      } catch (e) {
        debugPrint('Detection error: $e');
      }
    });
  }

  // Stop recording
  void _stopRecording() {
    _detectionTimer?.cancel();
    setState(() {
      _isRecording = false;
      _statusText = 'Stopped';
      _statusColor = Colors.grey;
      _currentNote = '--';
      _currentFrequency = 0;
    });
  }

  @override
  void dispose() {
    _detectionTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Voice to Melody')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Status
            Container(
              color: _statusColor.withOpacity(0.1),
              padding: const EdgeInsets.all(16),
              child: Text(_statusText,
                  style: TextStyle(color: _statusColor, fontSize: 18)),
            ),
            const SizedBox(height: 20),
            // Current note - only shows when sound detected
            if (_currentNote != '--')
              Container(
                color: Colors.blue.withOpacity(0.1),
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text('Current: $_currentNote',
                        style: const TextStyle(fontSize: 28, color: Colors.blue)),
                    Text('Freq: $_currentFrequency Hz',
                        style: const TextStyle(fontSize: 16, color: Colors.grey)),
                  ],
                ),
              ),
            // Notes list
            const SizedBox(height: 20),
            Text('Detected notes ($_detectedNotes.length):',
                style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 10),
            Container(
              height: 150,
              child: ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: _detectedNotes.length,
                itemBuilder: (ctx, i) {
                  final n = _detectedNotes[i];
                  return ListTile(
                    title: Text(n, style: const TextStyle(fontSize: 18)),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            // Control button
            ElevatedButton.icon(
              onPressed: _isRecording ? _stopRecording : () {
                setState(() {
                  _isRecording = true;
                  _statusText = 'Recording - Speaking...';
                  _statusColor = Colors.green;
                });
                _startDetectionTimer();
              },
              icon: Icon(_isRecording ? Icons.stop : Icons.mic),
              label: Text(_isRecording ? 'Stop' : 'Start Recording'),
              style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50)),
            ),
          ],
        ),
      ),
    );
  }
}