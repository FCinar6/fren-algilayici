import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BrakeDetectorApp());
}

class BrakeDetectorApp extends StatelessWidget {
  const BrakeDetectorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Araç Fren Algılayıcı',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.black,
      ),
      home: const BrakeDetectorScreen(),
    );
  }
}

class MovingAverageFilter {
  final int windowSize;
  final Queue<double> _queue = Queue<double>();
  double _runningSum = 0.0;

  MovingAverageFilter({this.windowSize = 8});

  double add(double value) {
    _queue.addLast(value);
    _runningSum += value;

    if (_queue.length > windowSize) {
      _runningSum -= _queue.removeFirst();
    }

    return _runningSum / _queue.length;
  }
}

class BrakeDetectorScreen extends StatefulWidget {
  const BrakeDetectorScreen({super.key});

  @override
  State<BrakeDetectorScreen> createState() => _BrakeDetectorScreenState();
}

class _BrakeDetectorScreenState extends State<BrakeDetectorScreen> {
  double _brakeThreshold = -3.5;
  int _debounceDurationMs = 150;

  StreamSubscription<dynamic>? _accelerometerSubscription;
  final MovingAverageFilter _filter = MovingAverageFilter(windowSize: 8);

  double _filteredY = 0.0;
  bool _isBraking = false;
  DateTime? _belowThresholdStartTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initSensors();
    });
  }

  Future<void> _initSensors() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _brakeThreshold = prefs.getDouble('brake_threshold') ?? -3.5;
          _debounceDurationMs = prefs.getInt('debounce_duration_ms') ?? 150;
        });
      }
    } catch (_) {}

    try {
      _accelerometerSubscription = userAccelerometerEventStream().listen(
        (UserAccelerometerEvent event) => _processData(event.y),
        onError: (_) => _fallback(),
        cancelOnError: false,
      );
    } catch (_) {
      _fallback();
    }
  }

  void _fallback() {
    _accelerometerSubscription?.cancel();
    try {
      _accelerometerSubscription = accelerometerEventStream().listen(
        (AccelerometerEvent event) => _processData(event.y),
        cancelOnError: false,
      );
    } catch (_) {}
  }

  void _processData(double rawY) {
    final double smoothedY = _filter.add(rawY);
    final DateTime now = DateTime.now();
    bool currentBrakingState = _isBraking;

    if (smoothedY <= _brakeThreshold) {
      _belowThresholdStartTime ??= now;
      final int elapsedMs = now.difference(_belowThresholdStartTime!).inMilliseconds;
      if (elapsedMs >= _debounceDurationMs) {
        currentBrakingState = true;
      }
    } else {
      _belowThresholdStartTime = null;
      currentBrakingState = false;
    }

    if (mounted) {
      setState(() {
        _filteredY = smoothedY;
        _isBraking = currentBrakingState;
      });
    }
  }

  void _openSettingsDialog() {
    double tempThreshold = _brakeThreshold;
    int tempDebounce = _debounceDurationMs;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: MediaQuery.of(context).viewInsets.bottom + 32,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Algoritma Ayarları', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                      IconButton(icon: const Icon(Icons.close, color: Colors.white70), onPressed: () => Navigator.of(context).pop()),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Frenleme Eşiği', style: TextStyle(color: Colors.white)),
                      Text('${tempThreshold.toStringAsFixed(1)} m/s²', style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Slider(
                    value: tempThreshold,
                    min: -7.0,
                    max: -1.5,
                    divisions: 55,
                    activeColor: Colors.redAccent,
                    onChanged: (val) => setModalState(() => tempThreshold = double.parse(val.toStringAsFixed(1))),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Debounce (Doğrulama)', style: TextStyle(color: Colors.white)),
                      Text('$tempDebounce ms', style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Slider(
                    value: tempDebounce.toDouble(),
                    min: 50.0,
                    max: 500.0,
                    divisions: 45,
                    activeColor: Colors.amberAccent,
                    onChanged: (val) => setModalState(() => tempDebounce = (val / 10).round() * 10),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, padding: const EdgeInsets.symmetric(vertical: 14)),
                      onPressed: () async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setDouble('brake_threshold', tempThreshold);
                        await prefs.setInt('debounce_duration_ms', tempDebounce);
                        setState(() {
                          _brakeThreshold = tempThreshold;
                          _debounceDurationMs = tempDebounce;
                        });
                        if (mounted) Navigator.of(context).pop();
                      },
                      child: const Text('Kaydet & Uygula', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _accelerometerSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color backgroundColor = _isBraking ? const Color(0xFF8B0000) : Colors.black;
    final Color statusTextColor = _isBraking ? Colors.white : const Color(0xFF00E676);
    final String statusText = _isBraking ? 'FREN YAPILIYOR!' : 'SABİT / HIZLANIYOR';

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Y-EKSENİ · sensors_plus', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.tune_rounded, color: Colors.white),
                    onPressed: _openSettingsDialog,
                  ),
                ],
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_isBraking ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded, size: 90, color: statusTextColor),
                  const SizedBox(height: 20),
                  Text(statusText, textAlign: TextAlign.center, style: TextStyle(color: statusTextColor, fontSize: 32, fontWeight: FontWeight.w900)),
                ],
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white12)),
                child: Column(
                  children: [
                    const Text('FİLTRELENMİŞ ANLIK Y İVMESİ', style: TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(_filteredY.toStringAsFixed(2), style: TextStyle(color: statusTextColor, fontSize: 48, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                        const Text('m/s²', style: TextStyle(color: Colors.white70, fontSize: 20)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text('Eşik: $_brakeThreshold m/s² ($_debounceDurationMs ms)', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
