import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VehicleStatusApp());
}

/// Uygulamanın ana MaterialApp widget'ı
class VehicleStatusApp extends StatelessWidget {
  const VehicleStatusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Araç Durum Algılayıcı',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.black,
      ),
      home: const VehicleStatusScreen(),
    );
  }
}

/// 8 Elemanlı FIFO Kuyruğu ile Çalışan Hareketli Ortalama Filtresi
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

/// 3 Araç Durumu
enum VehicleState {
  braking,      // Fren Yapılıyor (Kırmızı)
  accelerating, // Hızlanıyor (Koyu Mavi)
  cruising,     // Sabit Hızla Gidiyor (Siyah)
}

/// Ana Ekran
class VehicleStatusScreen extends StatefulWidget {
  const VehicleStatusScreen({super.key});

  @override
  State<VehicleStatusScreen> createState() => _VehicleStatusScreenState();
}

class _VehicleStatusScreenState extends State<VehicleStatusScreen> {
  // Varsayılan Parametreler
  static const double _defaultBrakeThreshold = -3.5;
  static const int _defaultBrakeDebounceMs = 150;
  static const double _defaultAccelThreshold = 1.5;
  static const int _defaultAccelDebounceMs = 150;
  static const String _defaultAxis = 'Z'; // Dik araç tutucu

  // Aktif Parametreler
  double _brakeThreshold = _defaultBrakeThreshold;
  int _brakeDebounceMs = _defaultBrakeDebounceMs;
  double _accelThreshold = _defaultAccelThreshold;
  int _accelDebounceMs = _defaultAccelDebounceMs;
  String _selectedAxis = _defaultAxis;

  StreamSubscription<dynamic>? _accelerometerSubscription;
  final MovingAverageFilter _filter = MovingAverageFilter(windowSize: 8);

  double _filteredAcceleration = 0.0;
  VehicleState _currentState = VehicleState.cruising;

  DateTime? _belowBrakeThresholdStart;
  DateTime? _aboveAccelThresholdStart;

  @override
  void initState() {
    super.initState();
    _startListeningSensors();
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

    // Seçili eksene göre ivmeyi yönlendir
    switch (_selectedAxis) {
      case 'Z': // 📱 Dik Araç Tutucu (Ekran size dönük, arkası ön cama bakar)
        targetAcc = -z;
        break;
      case '-Z': // 📱 Dik Araç Tutucu (Ters Montaj)
        targetAcc = z;
        break;
      case 'Y': // Yatay Konsol / Koltuk
        targetAcc = y;
        break;
      default:
        targetAcc = -z;
    }

    final double smoothed = _filter.add(targetAcc);
    final DateTime now = DateTime.now();
    VehicleState nextState = VehicleState.cruising;

    if (smoothed <= _brakeThreshold) {
      // Fren Eşiği Aşıldı
      _belowBrakeThresholdStart ??= now;
      _aboveAccelThresholdStart = null;
      final int elapsed = now.difference(_belowBrakeThresholdStart!).inMilliseconds;
      if (elapsed >= _brakeDebounceMs) {
        nextState = VehicleState.braking;
      }
    } else if (smoothed >= _accelThreshold) {
      // Hızlanma Eşiği Aşıldı
      _aboveAccelThresholdStart ??= now;
      _belowBrakeThresholdStart = null;
      final int elapsed = now.difference(_aboveAccelThresholdStart!).inMilliseconds;
      if (elapsed >= _accelDebounceMs) {
        nextState = VehicleState.accelerating;
      }
    } else {
      // Eşikler Arasında (Sabit Hız / Sakin Seyir)
      _belowBrakeThresholdStart = null;
      _aboveAccelThresholdStart = null;
      nextState = VehicleState.cruising;
    }

    if (mounted) {
      setState(() {
        _filteredAcceleration = smoothed;
        _currentState = nextState;
      });
    }
  }

  @override
  void dispose() {
    _accelerometerSubscription?.cancel();
    super.dispose();
  }

  /// Ayarlar Paneli (Hem Klavyeyle Sayı Yazma Hem Slider)
  void _openSettingsDialog() {
    double tempBrakeThresh = _brakeThreshold;
    int tempBrakeDebounce = _brakeDebounceMs;
    double tempAccelThresh = _accelThreshold;
    int tempAccelDebounce = _accelDebounceMs;
    String tempAxis = _selectedAxis;

    final brakeThreshCtrl = TextEditingController(text: tempBrakeThresh.toStringAsFixed(1));
    final brakeDebounceCtrl = TextEditingController(text: tempBrakeDebounce.toString());
    final accelThreshCtrl = TextEditingController(text: tempAccelThresh.toStringAsFixed(1));
    final accelDebounceCtrl = TextEditingController(text: tempAccelDebounce.toString());

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
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Eksen, İvme & Süre Ayarları', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                        IconButton(icon: const Icon(Icons.close, color: Colors.white70), onPressed: () => Navigator.of(context).pop()),
                      ],
                    ),
                    const Divider(color: Colors.white24),

                    // Montaj Pozisyonu
                    const Text('Telefonun Montaj Pozisyonu', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white70)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _buildAxisBtn('Z', '📱 Dik Tutucu', tempAxis, (val) => setModalState(() => tempAxis = val)),
                        const SizedBox(width: 8),
                        _buildAxisBtn('-Z', '📱 Ters Z', tempAxis, (val) => setModalState(() => tempAxis = val)),
                        const SizedBox(width: 8),
                        _buildAxisBtn('Y', 'Yatay Konsol', tempAxis, (val) => setModalState(() => tempAxis = val)),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // FREN AYARLARI (Manuel Giriş + Slider)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.red.withOpacity(0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.redAccent.withOpacity(0.3))),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('🛑 FREN PARAMETRELERİ', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                              Text('${tempBrakeThresh.toStringAsFixed(1)} m/s² · $tempBrakeDebounce ms', style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: brakeThreshCtrl,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                                  style: const TextStyle(color: Colors.white, fontSize: 14),
                                  decoration: const InputDecoration(labelText: 'Fren Eşiği (m/s²)', border: OutlineInputBorder(), isDense: true),
                                  onChanged: (val) {
                                    final d = double.tryParse(val);
                                    if (d != null && d < 0) setModalState(() => tempBrakeThresh = d);
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextFormField(
                                  controller: brakeDebounceCtrl,
                                  keyboardType: TextInputType.number,
                                  style: const TextStyle(color: Colors.white, fontSize: 14),
                                  decoration: const InputDecoration(labelText: 'Fren Süresi (ms)', border: OutlineInputBorder(), isDense: true),
                                  onChanged: (val) {
                                    final i = int.tryParse(val);
                                    if (i != null && i > 0) setModalState(() => tempBrakeDebounce = i);
                                  },
                                ),
                              ),
                            ],
                          ),
                          Slider(
                            value: tempBrakeThresh.clamp(-7.0, -1.0),
                            min: -7.0,
                            max: -1.0,
                            divisions: 60,
                            activeColor: Colors.redAccent,
                            onChanged: (val) {
                              setModalState(() {
                                tempBrakeThresh = double.parse(val.toStringAsFixed(1));
                                brakeThreshCtrl.text = tempBrakeThresh.toStringAsFixed(1);
                              });
                            },
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // HIZLANMA AYARLARI (Manuel Giriş + Slider)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.blue.withOpacity(0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blueAccent.withOpacity(0.3))),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('⚡ HIZLANMA PARAMETRELERİ', style: TextStyle(color: Colors.lightBlueAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                              Text('+${tempAccelThresh.toStringAsFixed(1)} m/s² · $tempAccelDebounce ms', style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: accelThreshCtrl,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  style: const TextStyle(color: Colors.white, fontSize: 14),
                                  decoration: const InputDecoration(labelText: 'Hızlanma Eşiği (m/s²)', border: OutlineInputBorder(), isDense: true),
                                  onChanged: (val) {
                                    final d = double.tryParse(val);
                                    if (d != null && d > 0) setModalState(() => tempAccelThresh = d);
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextFormField(
                                  controller: accelDebounceCtrl,
                                  keyboardType: TextInputType.number,
                                  style: const TextStyle(color: Colors.white, fontSize: 14),
                                  decoration: const InputDecoration(labelText: 'Hızlanma Süresi (ms)', border: OutlineInputBorder(), isDense: true),
                                  onChanged: (val) {
                                    final i = int.tryParse(val);
                                    if (i != null && i > 0) setModalState(() => tempAccelDebounce = i);
                                  },
                                ),
                              ),
                            ],
                          ),
                          Slider(
                            value: tempAccelThresh.clamp(0.5, 6.0),
                            min: 0.5,
                            max: 6.0,
                            divisions: 55,
                            activeColor: Colors.lightBlueAccent,
                            onChanged: (val) {
                              setModalState(() {
                                tempAccelThresh = double.parse(val.toStringAsFixed(1));
                                accelThreshCtrl.text = tempAccelThresh.toStringAsFixed(1);
                              });
                            },
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 18),

                    // Butonlar
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white24), padding: const EdgeInsets.symmetric(vertical: 14)),
                            onPressed: () {
                              setModalState(() {
                                tempBrakeThresh = _defaultBrakeThreshold;
                                tempBrakeDebounce = _defaultBrakeDebounceMs;
                                tempAccelThresh = _defaultAccelThreshold;
                                tempAccelDebounce = _defaultAccelDebounceMs;
                                tempAxis = _defaultAxis;
                                brakeThreshCtrl.text = tempBrakeThresh.toString();
                                brakeDebounceCtrl.text = tempBrakeDebounce.toString();
                                accelThreshCtrl.text = tempAccelThresh.toString();
                                accelDebounceCtrl.text = tempAccelDebounce.toString();
                              });
                            },
                            child: const Text('Varsayılan'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.emerald, padding: const EdgeInsets.symmetric(vertical: 14)),
                            onPressed: () {
                              setState(() {
                                _brakeThreshold = tempBrakeThresh;
                                _brakeDebounceMs = tempBrakeDebounce;
                                _accelThreshold = tempAccelThresh;
                                _accelDebounceMs = tempAccelDebounce;
                                _selectedAxis = tempAxis;
                                _filter.reset();
                                _belowBrakeThresholdStart = null;
                                _aboveAccelThresholdStart = null;
                                _currentState = VehicleState.cruising;
                              });
                              Navigator.of(context).pop();
                            },
                            child: const Text('Uygula', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
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

  Widget _buildAxisBtn(String key, String title, String selected, ValueChanged<String> onSelect) {
    final bool isSelected = key == selected;
    return Expanded(
      child: GestureDetector(
        onTap: () => onSelect(key),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? Colors.amber.withOpacity(0.2) : Colors.white10,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isSelected ? Colors.amber : Colors.white24),
          ),
          alignment: Alignment.center,
          child: Text(title, style: TextStyle(color: isSelected ? Colors.amber : Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Color backgroundColor;
    Color textColor;
    String statusTitle;
    IconData statusIcon;

    switch (_currentState) {
      case VehicleState.braking:
        backgroundColor = const Color(0xFF8B0000); // Koyu Kırmızı
        textColor = Colors.white;
        statusTitle = 'FREN YAPILIYOR!';
        statusIcon = Icons.warning_amber_rounded;
        break;
      case VehicleState.accelerating:
        backgroundColor = const Color(0xFF0D47A1); // Koyu Mavi
        textColor = const Color(0xFF00E5FF); // Parlak Turkuaz
        statusTitle = 'HIZLANIYOR';
        statusIcon = Icons.speed_rounded;
        break;
      case VehicleState.cruising:
        backgroundColor = Colors.black;
        textColor = const Color(0xFF00E676); // Parlak Yeşil
        statusTitle = 'SABİT HIZLA GİDİYOR';
        statusIcon = Icons.check_circle_rounded;
        break;
    }

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          _selectedAxis == 'Z' ? '📱 Dik Tutucu (Z)' : _selectedAxis == '-Z' ? '📱 Dik Ters (-Z)' : 'Yatay Konsol (Y)',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white70),
        ),
        actions: [
          TextButton.icon(
            onPressed: _openSettingsDialog,
            icon: const Icon(Icons.tune, color: Colors.white, size: 18),
            label: const Text('Ayarlar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),
            Icon(statusIcon, size: 100, color: textColor),
            const SizedBox(height: 24),
            Text(
              statusTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w900,
                color: textColor,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _currentState == VehicleState.braking
                  ? 'Fren Eşiği: ≤ ${_brakeThreshold.toStringAsFixed(1)} m/s² · ${_brakeDebounceMs}ms'
                  : _currentState == VehicleState.accelerating
                      ? 'Hızlanma Eşiği: ≥ +${_accelThreshold.toStringAsFixed(1)} m/s² · ${_accelDebounceMs}ms'
                      : 'Eşikler Arası Normal Seyir',
              style: TextStyle(fontSize: 13, color: textColor.withOpacity(0.85), fontWeight: FontWeight.w500),
            ),
            const Spacer(),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.4),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Filtreli İvme:', style: TextStyle(color: Colors.white70, fontSize: 14)),
                  Text(
                    '${_filteredAcceleration >= 0 ? "+" : ""}${_filteredAcceleration.toStringAsFixed(2)} m/s²',
                    style: TextStyle(color: textColor, fontSize: 22, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
