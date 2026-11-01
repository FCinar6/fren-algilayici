import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  PlatformDispatcher.instance.onError = (error, stack) => true;
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

  void reset() {
    _queue.clear();
    _runningSum = 0.0;
  }
}

class BrakeDetectorScreen extends StatefulWidget {
  const BrakeDetectorScreen({super.key});

  @override
  State<BrakeDetectorScreen> createState() => _BrakeDetectorScreenState();
}

class _BrakeDetectorScreenState extends State<BrakeDetectorScreen> {
  static const String _keyThreshold = 'brake_threshold';
  static const String _keyDebounceMs = 'debounce_duration_ms';
  static const String _keySelectedAxis = 'selected_axis';

  double _brakeThreshold = -3.5;
  int _debounceDurationMs = 150;
  String _selectedAxis = 'Z'; // Varsayılan olarak Dik Tutucu Z-ekseni

  StreamSubscription<dynamic>? _accelerometerSubscription;
  final MovingAverageFilter _filter = MovingAverageFilter(windowSize: 8);

  double _filteredAcceleration = 0.0;
  bool _isBraking = false;
  DateTime? _belowThresholdStartTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initApp();
    });
  }

  Future<void> _initApp() async {
    await _loadPreferences();
    _startListeningSensors();
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _brakeThreshold = prefs.getDouble(_keyThreshold) ?? -3.5;
          _debounceDurationMs = prefs.getInt(_keyDebounceMs) ?? 150;
          _selectedAxis = prefs.getString(_keySelectedAxis) ?? 'Z';
        });
      }
    } catch (_) {}
  }

  Future<void> _savePreferences(double newThreshold, int newDebounceMs, String newAxis) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_keyThreshold, newThreshold);
      await prefs.setInt(_keyDebounceMs, newDebounceMs);
      await prefs.setString(_keySelectedAxis, newAxis);
    } catch (_) {}

    if (mounted) {
      setState(() {
        _brakeThreshold = newThreshold;
        _debounceDurationMs = newDebounceMs;
        _selectedAxis = newAxis;
        _filter.reset();
        _belowThresholdStartTime = null;
        _isBraking = false;
      });
    }
  }

  void _startListeningSensors() {
    try {
      _accelerometerSubscription = userAccelerometerEventStream().listen(
        (UserAccelerometerEvent event) {
          _processSensorReading(event.x, event.y, event.z);
        },
        onError: (_) => _fallbackToStandard(),
        cancelOnError: false,
      );
    } catch (_) {
      _fallbackToStandard();
    }
  }

  void _fallbackToStandard() {
    _accelerometerSubscription?.cancel();
    try {
      _accelerometerSubscription = accelerometerEventStream().listen(
        (AccelerometerEvent event) {
          _processSensorReading(event.x, event.y, event.z);
        },
        cancelOnError: false,
      );
    } catch (_) {}
  }

  void _processSensorReading(double x, double y, double z) {
    double targetAcc = 0.0;

    // Seçilen montaj pozisyonuna göre ilgili ekseni filtrele
    switch (_selectedAxis) {
      case 'Y': // Yatay
        targetAcc = y;
        break;
      case 'Z': // Dik Tutucu (Ekran sürücüye bakıyor)
        targetAcc = -z;
        break;
      case '-Z': // Dik Tutucu (Ters Tepki)
        targetAcc = z;
        break;
      case 'X': // Yan Tutucu
        targetAcc = x;
        break;
      default:
        targetAcc = -z;
    }

    final double smoothed = _filter.add(targetAcc);
    final DateTime now = DateTime.now();
    bool currentBrakingState = _isBraking;

    if (smoothed <= _brakeThreshold) {
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
        _filteredAcceleration = smoothed;
        _isBraking = currentBrakingState;
      });
    }
  }

  String _getAxisDisplayName(String axis) {
    switch (axis) {
      case 'Z':
        return '📱 Dik Tutucu (Z-Ekseni)';
      case '-Z':
        return '📱 Dik Tutucu (-Z Ekseni)';
      case 'Y':
        return 'Yatay (Y-Ekseni)';
      case 'X':
        return 'Yan Tutucu (X-Ekseni)';
      default:
        return 'Dik Tutucu (Z)';
    }
  }

  void _openSettingsDialog() {
    double tempThreshold = _brakeThreshold;
    int tempDebounce = _debounceDurationMs;
    String tempAxis = _selectedAxis;

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
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Eksen & Fren Ayarları', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                        IconButton(icon: const Icon(Icons.close, color: Colors.white70), onPressed: () => Navigator.of(context).pop()),
                      ],
                    ),
                    const Divider(color: Colors.white24, height: 20),

                    const Text('Telefonun Arabadaki Konumu', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                    const SizedBox(height: 8),

                    _buildAxisTile('Z', '📱 Dik Araç Tutucu (Tavsiye Edilen)', 'Telefon tutucuda dik, ekran sürücüye bakar', tempAxis, (val) => setModalState(() => tempAxis = val)),
                    const SizedBox(height: 8),
                    _buildAxisTile('-Z', '📱 Dik Tutucu (Ters Yön)', 'Frende değer artıya çıkarsa bunu seçin', tempAxis, (val) => setModalState(() => tempAxis = val)),
                    const SizedBox(height: 8),
                    _buildAxisTile('Y', 'Yatay (Konsol / Koltuk)', 'Telefon düz yatarken (ekran tavana bakar)', tempAxis, (val) => setModalState(() => tempAxis = val)),

                    const SizedBox(height: 18),
                    const Divider(color: Colors.white24),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Frenleme Eşiği', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                        Text('${tempThreshold.toStringAsFixed(1)} m/s²', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.redAccent)),
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

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Debounce (Doğrulama Süresi)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                        Text('$tempDebounce ms', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.amberAccent)),
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

                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, padding: const EdgeInsets.symmetric(vertical: 14)),
                        onPressed: () async {
                          await _savePreferences(tempThreshold, tempDebounce, tempAxis);
                          if (mounted) Navigator.of(context).pop();
                        },
                        child: const Text('Kaydet & Uygula', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAxisTile(String value, String title, String subtitle, String currentVal, Function(String) onSelect) {
    final bool isSelected = value == currentVal;
    return InkWell(
      onTap: () => onSelect(value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.redAccent.withOpacity(0.18) : Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? Colors.redAccent : Colors.white12, width: isSelected ? 1.5 : 1),
        ),
        child: Row(
          children: [
            Icon(isSelected ? Icons.radio_button_checked : Icons.radio_button_off, color: isSelected ? Colors.redAccent : Colors.white54, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontWeight: FontWeight.bold, fontSize: 13)),
                  Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      ),
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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          color: backgroundColor,
          width: double.infinity,
          height: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Text(
                      _getAxisDisplayName(_selectedAxis),
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.tune_rounded, color: Colors.white),
                    tooltip: 'Eksen ve Eşik Ayarları',
                    onPressed: _openSettingsDialog,
                  ),
                ],
              ),

              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isBraking ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
                    size: 96,
                    color: statusTextColor,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    statusText,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: statusTextColor, fontSize: 34, fontWeight: FontWeight.w900),
                  ),
                ],
              ),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  children: [
                    Text('FİLTRELENMİŞ İVME ($_selectedAxis EKSENİ)', style: const TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          _filteredAcceleration.toStringAsFixed(2),
                          style: TextStyle(color: statusTextColor, fontSize: 48, fontWeight: FontWeight.bold),
                        ),
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
