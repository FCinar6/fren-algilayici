import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: VehicleDetectorScreen(),
  ));
}

/// 8 Elemanlı FIFO Kuyruğu ile Hareketli Ortalama Filtresi
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

class VehicleDetectorScreen extends StatefulWidget {
  const VehicleDetectorScreen({super.key});

  @override
  State<VehicleDetectorScreen> createState() => _VehicleDetectorScreenState();
}

class _VehicleDetectorScreenState extends State<VehicleDetectorScreen> {
  // Parametreler
  double _brakeThresh = -3.5;
  int _brakeDebounce = 150;
  double _accelThresh = 1.5;
  int _accelDebounce = 150;
  String _axis = 'Z'; // Dik tutucu varsayılan

  StreamSubscription<dynamic>? _sub;
  final MovingAverageFilter _filter = MovingAverageFilter();

  double _acc = 0.0;
  String _status = 'SABİT HIZLA GİDİYOR';
  Color _bgColor = Colors.black;
  Color _textColor = const Color(0xFF00E676);
  IconData _icon = Icons.check_circle_outline;

  DateTime? _brakeStart;
  DateTime? _accelStart;

  @override
  void initState() {
    super.initState();
    _startSensors();
  }

  void _startSensors() {
    try {
      _sub = userAccelerometerEventStream().listen((event) {
        _process(event.x, event.y, event.z);
      }, onError: (_) => _fallback());
    } catch (_) {
      _fallback();
    }
  }

  void _fallback() {
    _sub?.cancel();
    try {
      _sub = accelerometerEventStream().listen((event) {
        _process(event.x, event.y, event.z);
      });
    } catch (_) {}
  }

  void _process(double x, double y, double z) {
    double raw = 0.0;
    if (_axis == 'Z') {
      raw = -z; // 📱 Dik Tutucu (Ekran sürücüye, sırtı ön cama bakar)
    } else if (_axis == '-Z') {
      raw = z; // 📱 Dik Ters
    } else {
      raw = y; // Yatay Konsol
    }

    final val = _filter.add(raw);
    final now = DateTime.now();

    if (val <= _brakeThresh) {
      _brakeStart ??= now;
      _accelStart = null;
      if (now.difference(_brakeStart!).inMilliseconds >= _brakeDebounce) {
        _update(val, 'FREN YAPILIYOR!', const Color(0xFF8B0000), Colors.white, Icons.warning_amber_rounded);
        return;
      }
    } else if (val >= _accelThresh) {
      _accelStart ??= now;
      _brakeStart = null;
      if (now.difference(_accelStart!).inMilliseconds >= _accelDebounce) {
        _update(val, 'HIZLANIYOR', const Color(0xFF0D47A1), const Color(0xFF00E5FF), Icons.speed);
        return;
      }
    } else {
      _brakeStart = null;
      _accelStart = null;
    }

    _update(val, 'SABİT HIZLA GİDİYOR', Colors.black, const Color(0xFF00E676), Icons.check_circle_outline);
  }

  void _update(double acc, String status, Color bg, Color text, IconData icon) {
    if (!mounted) return;
    setState(() {
      _acc = acc;
      _status = status;
      _bgColor = bg;
      _textColor = text;
      _icon = icon;
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _openSettings() {
    final bCtrl = TextEditingController(text: _brakeThresh.toStringAsFixed(1));
    final bdCtrl = TextEditingController(text: _brakeDebounce.toString());
    final aCtrl = TextEditingController(text: _accelThresh.toStringAsFixed(1));
    final adCtrl = TextEditingController(text: _accelDebounce.toString());
    String curAxis = _axis;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setM) => Padding(
          padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Eksen & İvme/Süre Ayarları', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                const Text('Telefon Tutucu Yönü', style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _axisBtn('Z', '📱 Dik', curAxis, (v) => setM(() => curAxis = v)),
                    const SizedBox(width: 8),
                    _axisBtn('-Z', '📱 Ters Z', curAxis, (v) => setM(() => curAxis = v)),
                    const SizedBox(width: 8),
                    _axisBtn('Y', 'Yatay', curAxis, (v) => setM(() => curAxis = v)),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('Fren Eşiği (m/s²) ve Süresi (ms)', style: TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: bCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(labelText: 'Fren Eşiği', border: OutlineInputBorder(), isDense: true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: bdCtrl,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(labelText: 'Fren Süresi (ms)', border: OutlineInputBorder(), isDense: true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('Hızlanma Eşiği (m/s²) ve Süresi (ms)', style: TextStyle(color: Colors.lightBlueAccent, fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: aCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(labelText: 'Hızlanma Eşiği', border: OutlineInputBorder(), isDense: true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: adCtrl,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(labelText: 'Hızlanma Süresi (ms)', border: OutlineInputBorder(), isDense: true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                    onPressed: () {
                      final b = double.tryParse(bCtrl.text);
                      final bd = int.tryParse(bdCtrl.text);
                      final a = double.tryParse(aCtrl.text);
                      final ad = int.tryParse(adCtrl.text);
                      setState(() {
                        if (b != null) _brakeThresh = b;
                        if (bd != null) _brakeDebounce = bd;
                        if (a != null) _accelThresh = a;
                        if (ad != null) _accelDebounce = ad;
                        _axis = curAxis;
                      });
                      Navigator.pop(context);
                    },
                    child: const Text('Uygula', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _axisBtn(String val, String label, String cur, ValueChanged<String> onS) {
    final sel = val == cur;
    return Expanded(
      child: GestureDetector(
        onTap: () => onS(val),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: sel ? Colors.amber.withOpacity(0.2) : Colors.white10,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: sel ? Colors.amber : Colors.white24),
          ),
          alignment: Alignment.center,
          child: Text(label, style: TextStyle(color: sel ? Colors.amber : Colors.white70, fontWeight: FontWeight.bold, fontSize: 12)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(_axis.contains('Z') ? '📱 Dik Tutucu ($_axis)' : 'Yatay (Y)', style: const TextStyle(color: Colors.white70, fontSize: 13)),
        actions: [
          IconButton(icon: const Icon(Icons.tune, color: Colors.white), onPressed: _openSettings),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              Icon(_icon, size: 90, color: _textColor),
              const SizedBox(height: 20),
              Text(
                _status,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: _textColor),
              ),
              const SizedBox(height: 8),
              Text(
                _status == 'FREN YAPILIYOR!'
                    ? 'Eşik: ≤ ${_brakeThresh.toStringAsFixed(1)} m/s² · $_brakeDebounce ms'
                    : _status == 'HIZLANIYOR'
                        ? 'Eşik: ≥ +${_accelThresh.toStringAsFixed(1)} m/s² · $_accelDebounce ms'
                        : 'Eşikler Arası Normal Seyir',
                style: TextStyle(color: _textColor.withOpacity(0.8), fontSize: 13),
              ),
              const Spacer(),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Filtreli İvme:', style: TextStyle(color: Colors.white70, fontSize: 14)),
                    Text(
                      '${_acc >= 0 ? "+" : ""}${_acc.toStringAsFixed(2)} m/s²',
                      style: TextStyle(color: _textColor, fontSize: 22, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                    ),
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
