import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'domain.dart';
import 'services/history_repository.dart';
import 'services/robot_transport.dart';

class AppController extends ChangeNotifier {
  AppController({
    RobotTransport? transport,
    HistoryRepository? repository,
    DateTime Function()? clock,
  }) : _transport = transport ?? BleRobotTransport(),
       _repository = repository ?? FirestoreHistoryRepository(),
       _now = clock ?? DateTime.now;
  final RobotTransport _transport;
  final HistoryRepository _repository;
  final DateTime Function() _now;
  StreamSubscription<List<int>>? _packetSubscription;
  StreamSubscription<bool>? _connectionSubscription;
  StreamSubscription<RobotDevice>? _scanSubscription;
  Timer? _timer;
  Timer? _scanTimer;
  bool _disposed = false;
  bool _initialized = false;
  bool _link = false;
  bool _armed = false;
  bool _background = false;
  bool _dirty = false;
  bool _emergency = false;
  int _stopRevision = 0;
  int? _lastAcknowledgedSequence;
  DateTime? _lastAcknowledgedAt;
  Future<void>? _writing;
  int _generation = 0;
  int _sequence = 0;
  int? _handshakeSequence;
  DateTime? _connectingAt;
  DateTime? _lastSampleAt;
  DateTime? _lastSavedAt;
  String? _lastState;
  String? _deviceId;
  Motion _motion = Motion.stop;
  int _demoTick = 0;
  int _demoAutoStartedTick = 0;
  final Completer<void> _repositoryReady = Completer<void>();
  late Future<void> _databaseQueue = _repositoryReady.future;
  bool isDemo = false;
  bool isConnecting = false;
  bool isScanning = false;
  String? error;
  Telemetry? telemetry;
  RobotMode selectedMode = RobotMode.manual;
  int speed = 150;
  int servo = 90;
  bool pumpRequested = false;
  final List<RobotDevice> devices = [];
  final List<Telemetry> samples = [];
  final List<ActivityEntry> activities = [];
  int storedSampleCount = 0;
  bool get isConnected => _link && _armed && !isDemo;
  bool get isStale =>
      telemetry != null &&
      _now().difference(telemetry!.receivedAt) >
          const Duration(milliseconds: 1000);
  bool get canControl =>
      !_background &&
      (isDemo || (isConnected && !isStale && telemetry!.pwmReady));
  String get databaseLabel =>
      isDemo ? 'Demo · nothing saved to Firebase' : _repository.label;
  String get connectionLabel => isDemo
      ? 'Demo mode'
      : isConnecting
      ? 'Connecting…'
      : isConnected && !isStale
      ? 'Bluetooth connected'
      : 'Disconnected';

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    _repository.onChanged = _notify;
    _packetSubscription = _transport.packets.listen(
      _receive,
      onError: (Object e) {
        if (_link)
          unawaited(
            _trip(
              'Invalid or interrupted Bluetooth stream. Reconnect to continue.',
            ),
          );
      },
    );
    _connectionSubscription = _transport.connectionChanges.listen((connected) {
      if (!connected && (_link || isConnecting))
        unawaited(
          _trip('Bluetooth disconnected. Robot controls have been reset.'),
        );
    });
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
    try {
      await _repository.open();
      if (!_repositoryReady.isCompleted) _repositoryReady.complete();
      if (!_link && !isConnecting && !isDemo) await refreshHistory();
    } catch (e) {
      error = 'History is unavailable. Bluetooth control is still available.';
    } finally {
      if (!_repositoryReady.isCompleted) _repositoryReady.complete();
    }
    _notify();
  }

  Future<void> scan() async {
    if (isConnecting || _link) return;
    if (isDemo) await stopDemo();
    await _stopScan();
    devices.clear();
    error = null;
    isScanning = true;
    _notify();
    _scanSubscription = _transport.scan().listen(
      (device) {
        final index = devices.indexWhere((d) => d.id == device.id);
        if (index < 0) {
          devices.add(device);
        } else {
          devices[index] = device;
        }
        devices.sort((a, b) => b.rssi.compareTo(a.rssi));
        _notify();
      },
      onError: (Object e) {
        error = _cleanError(e);
        unawaited(_stopScan());
      },
      onDone: () {
        isScanning = false;
        _notify();
      },
    );
    _scanTimer = Timer(const Duration(seconds: 8), () {
      unawaited(_stopScan());
    });
  }

  Future<void> _stopScan() async {
    _scanTimer?.cancel();
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    isScanning = false;
    _notify();
  }

  Future<void> connect(RobotDevice device) async {
    if (isConnecting) return;
    await disconnect();
    await _stopScan();
    isDemo = false;
    _background = false;
    isConnecting = true;
    error = null;
    _resetControls();
    telemetry = null;
    samples.clear();
    activities.clear();
    storedSampleCount = 0;
    _lastState = null;
    _lastAcknowledgedSequence = null;
    _lastAcknowledgedAt = null;
    _lastSavedAt = null;
    _lastSampleAt = null;
    _deviceId = device.id;
    final generation = ++_generation;
    _notify();
    try {
      await _transport.connect(device.id);
      if (_disposed || generation != _generation) return;
      _link = true;
      _armed = false;
      _connectingAt = _now();
      _handshakeSequence = _nextSequence();
      _emergency = true;
      _stopRevision++;
      _enqueueDatabase(() => _repository.selectDevice(device.id));
      await _queueWrite();
    } catch (e) {
      if (generation == _generation) await _trip(_cleanError(e));
    }
  }

  Future<void> disconnect() async {
    if (_link) {
      _background = true;
      _resetControls();
      _emergency = true;
      _stopRevision++;
      try {
        await _queueWrite().timeout(const Duration(milliseconds: 650));
      } catch (_) {
        /* Firmware watchdog is the final stop path. */
      }
    }
    _generation++;
    _link = false;
    _armed = false;
    isConnecting = false;
    _handshakeSequence = null;
    _dirty = false;
    await _transport.disconnect();
    _resetControls();
    _notify();
  }

  Future<void> _trip(String message) async {
    if (_disposed) return;
    _generation++;
    _link = false;
    _armed = false;
    isConnecting = false;
    _dirty = false;
    _handshakeSequence = null;
    _resetControls();
    error = message;
    _addActivity('Connection interrupted', message, alert: true);
    _notify();
    await _transport.disconnect();
  }

  void _tick() {
    if (_disposed || _background) return;
    if (isDemo) {
      _demoTick++;
      _demoSample();
      return;
    }
    if (!_link) return;
    if (!_armed &&
        _connectingAt != null &&
        _now().difference(_connectingAt!) > const Duration(seconds: 5)) {
      unawaited(
        _trip(
          'Robot did not acknowledge STOP. Check the FireGuard BLE firmware.',
        ),
      );
      return;
    }
    if (_armed && isStale) {
      unawaited(
        _trip('Sensor data is stale. Controls stopped; reconnect to resume.'),
      );
      return;
    }
    if (_armed &&
        _lastAcknowledgedAt != null &&
        _now().difference(_lastAcknowledgedAt!) >
            const Duration(milliseconds: 1200)) {
      unawaited(
        _trip('Robot stopped acknowledging commands. Reconnect to continue.'),
      );
      return;
    }
    unawaited(_queueWrite());
  }

  int _nextSequence() => _sequence = (_sequence + 1) & 255;
  Future<void> _queueWrite() {
    if (!_link || isDemo) return Future.value();
    _dirty = true;
    return _writing ??= _drainWrites();
  }

  Future<void> _drainWrites() async {
    final generation = _generation;
    try {
      while (_dirty && _link && generation == _generation) {
        _dirty = false;
        final emergency = _emergency || !_armed;
        final stopRevision = _stopRevision;
        final sequence = _handshakeSequence ?? _nextSequence();
        final bytes = RobotProtocol.command(
          sequence: sequence,
          mode: selectedMode,
          motion: selectedMode == RobotMode.auto ? Motion.stop : _motion,
          speed: speed,
          servo: selectedMode == RobotMode.auto ? 90 : servo,
          pump: selectedMode == RobotMode.manual && pumpRequested,
          emergency: emergency,
        );
        await _transport
            .write(bytes)
            .timeout(const Duration(milliseconds: 700));
        if (generation != _generation) break;
        // An older in-flight command must not clear a newer STOP request.
        if (emergency && _armed && stopRevision == _stopRevision) {
          _emergency = false;
        }
      }
    } catch (e) {
      if (generation == _generation && _link)
        await _trip(
          'Bluetooth command timed out. Reconnect before controlling the robot.',
        );
    } finally {
      _writing = null;
    }
  }

  void _receive(List<int> packet) {
    if (!_link || isDemo || _disposed) return;
    try {
      final value = RobotProtocol.decode(packet, receivedAt: _now());
      if (value.acknowledgedSequence != _lastAcknowledgedSequence) {
        _lastAcknowledgedSequence = value.acknowledgedSequence;
        _lastAcknowledgedAt = _now();
      }
      if (!_armed &&
          value.acknowledgedSequence == _handshakeSequence &&
          value.mode == RobotMode.manual &&
          value.motion == Motion.stop &&
          !value.pump &&
          value.pwmReady &&
          !value.watchdogTripped) {
        _armed = true;
        _handshakeSequence = null;
        _emergency = false;
        isConnecting = false;
        _addActivity(
          'Robot connected',
          'STOP confirmed. Manual control is ready.',
        );
      }
      if (_armed && (!value.pwmReady || value.watchdogTripped)) {
        unawaited(
          _trip(
            'Robot reported a hardware fault or command timeout. Reconnect after checking the robot.',
          ),
        );
        return;
      }
      _accept(value);
    } on FormatException {
      unawaited(
        _trip(
          'Incompatible robot data. Install the included FireGuard BLE firmware.',
        ),
      );
    }
  }

  void _accept(Telemetry value) {
    telemetry = value;
    if (_lastSampleAt == null ||
        value.receivedAt.difference(_lastSampleAt!) >=
            const Duration(seconds: 1)) {
      samples.add(value);
      if (samples.length > 60) samples.removeAt(0);
      _lastSampleAt = value.receivedAt;
    }
    final key =
        '${value.mode.index}:${value.statusCode}:${value.motion.index}:${value.pump}:${value.flameLeft}:${value.flameCenter}:${value.flameRight}';
    final changed = key != _lastState;
    if (changed) {
      _lastState = key;
      _addActivity(
        value.hasFlame ? 'Flame detected' : value.statusLabel,
        '${value.statusLabel} · MQ2 ${value.mq2} raw ADC',
        alert: value.hasFlame || value.obstacle,
      );
    }
    if (!isDemo &&
        _repository.available &&
        (changed ||
            _lastSavedAt == null ||
            value.receivedAt.difference(_lastSavedAt!) >=
                const Duration(seconds: 5))) {
      _lastSavedAt = value.receivedAt;
      final deviceId = _deviceId ?? 'unknown';
      _enqueueDatabase(() async {
        await _repository.saveSample(value, deviceId);
        storedSampleCount = await _repository.sampleCount();
        _notify();
      });
    }
    _notify();
  }

  void _enqueueDatabase(Future<void> Function() action) {
    _databaseQueue = _databaseQueue.then((_) => action()).catchError((
      Object e,
    ) {
      error =
          'Cloud history is unavailable. Check Firebase configuration and rules.';
      _notify();
    });
  }

  void _addActivity(String title, String detail, {bool alert = false}) {
    final event = ActivityEntry(
      at: _now(),
      title: title,
      detail: detail,
      alert: alert,
      demo: isDemo,
    );
    activities.insert(0, event);
    if (activities.length > 100) activities.removeLast();
    if (!isDemo && _repository.available)
      _enqueueDatabase(() => _repository.saveActivity(event));
  }

  Future<void> setMode(RobotMode mode) async {
    if (!canControl) return;
    if (isDemo && mode == RobotMode.auto && selectedMode != mode) {
      _demoAutoStartedTick = _demoTick;
    }
    _motion = Motion.stop;
    pumpRequested = false;
    servo = 90;
    selectedMode = mode;
    await _changed();
  }

  Future<void> setPump(bool enabled) async {
    if (!canControl || selectedMode != RobotMode.manual) return;
    pumpRequested = enabled;
    await _changed();
  }

  Future<void> setSpeed(int value) async {
    if (!canControl) return;
    speed = value.clamp(0, 255);
    await _changed();
  }

  Future<void> setServo(int value) async {
    if (!canControl || selectedMode != RobotMode.manual) return;
    servo = value.clamp(0, 180);
    await _changed();
  }

  Future<void> startMotion(Motion motion) async {
    if (!canControl || selectedMode != RobotMode.manual) return;
    if (motion == Motion.forward && (telemetry?.obstacle ?? false)) {
      error = 'Forward motion blocked: obstacle is closer than 15 cm.';
      _notify();
      return;
    }
    _motion = motion;
    await _changed();
  }

  Future<void> stopMotion() async {
    _motion = Motion.stop;
    await _changed();
  }

  Future<void> emergencyStop() async {
    _resetControls();
    _emergency = true;
    _stopRevision++;
    _addActivity(
      'STOP requested',
      'Motor and pump off; manual mode; nozzle centered.',
    );
    await _changed();
  }

  Future<void> _changed() async {
    if (isDemo) _demoSample();
    _notify();
    await _queueWrite();
  }

  void _resetControls() {
    selectedMode = RobotMode.manual;
    _motion = Motion.stop;
    pumpRequested = false;
    servo = 90;
  }

  void onAppBackground() {
    _background = true;
    if (isDemo) {
      _resetControls();
      _demoSample();
    }
    if (_link || isConnecting) unawaited(disconnect());
    unawaited(_stopScan());
  }

  void onAppResumed() => onAppForeground();
  void onAppForeground() {
    _background = false;
    // A real connection is never resumed automatically.
    _notify();
  }

  void clearError() {
    error = null;
    _notify();
  }

  Future<void> startDemo() async {
    await disconnect();
    await _stopScan();
    _background = false;
    isDemo = true;
    error = null;
    _demoTick = 0;
    _lastState = null;
    _lastSampleAt = null;
    samples.clear();
    activities.clear();
    _resetControls();
    // A clearly labelled synthetic trend gives the preview a useful starting point.
    for (var i = 0; i < 40; i++) {
      samples.add(_makeDemo(_now().subtract(Duration(seconds: 40 - i)), i));
    }
    _addActivity(
      'Demo started',
      'Simulated sensors. No robot connected and no Firebase writes.',
    );
    _demoSample();
  }

  Future<void> stopDemo() async {
    if (!isDemo) return;
    isDemo = false;
    _background = false;
    telemetry = null;
    samples.clear();
    activities.clear();
    _lastState = null;
    _resetControls();
    await refreshHistory();
    _notify();
  }

  Telemetry _makeDemo(DateTime at, int tick) {
    final auto = selectedMode == RobotMode.auto;
    // A scripted sensor sequence illustrates patrol, avoidance, flame response,
    // the 1.5-second clear interval, and stopping when range is unavailable.
    final phase = (tick - _demoAutoStartedTick) % 72;
    final avoiding = auto && phase >= 16 && phase < 28;
    final left = auto && phase >= 28 && phase < 36;
    final center = auto && phase >= 36 && phase < 52;
    final checking = auto && phase >= 52 && phase < 58;
    final rangeUnknown = auto && phase >= 58 && phase < 64;
    final pumping = auto ? center : pumpRequested;
    var motion = _motion;
    var status = motion == Motion.stop ? 0 : 1;
    double? distance = 46 + math.sin(tick / 8) * 6;
    if (auto) {
      motion = Motion.forward;
      status = 10;
      if (avoiding) {
        final turnTime = ((phase - 16) * 250) % 650;
        motion = turnTime >= 100 && turnTime < 350 ? Motion.right : Motion.stop;
        distance = 20 + (phase - 16) * .7;
        status = 11;
      } else if (left) {
        motion = phase == 28 ? Motion.stop : Motion.left;
        status = 1;
      } else if (center || checking || rangeUnknown) {
        motion = Motion.stop;
        status = center
            ? 4
            : checking
            ? 13
            : 12;
        if (rangeUnknown) distance = null;
      }
    }
    if (speed == 0) motion = Motion.stop;
    return Telemetry(
      mode: selectedMode,
      motion: motion,
      speed: speed,
      servo: auto
          ? pumping
                ? 90 + (math.sin(tick / 3) * 30).round()
                : 90
          : servo,
      distanceCm: distance,
      mq2: 440 + (math.sin(tick / 5) * 65).round() + (center ? 260 : 0),
      flameLeft: left,
      flameCenter: center,
      flameRight: false,
      pump: pumping,
      pwmReady: true,
      watchdogTripped: false,
      uptimeSeconds: tick ~/ 4,
      acknowledgedSequence: 0,
      receivedAt: at,
      statusCode: auto
          ? status
          : motion == Motion.stop
          ? 0
          : 1,
    );
  }

  void _demoSample() => _accept(_makeDemo(_now(), _demoTick));

  Future<void> refreshHistory() async {
    if (isDemo || !_repository.available) return;
    final generation = _generation;
    try {
      final recent = await _repository.recentSamples();
      final events = await _repository.recentActivities();
      if (isDemo || _disposed || generation != _generation) return;
      // Never overwrite fresh live data with historical records.
      if (!_link) {
        samples
          ..clear()
          ..addAll(recent);
      }
      if (!_link) {
        activities
          ..clear()
          ..addAll(events);
      }
      storedSampleCount = await _repository.sampleCount();
    } catch (e) {
      error =
          'Could not load cloud history. Check your connection and Firebase rules.';
    }
    _notify();
  }

  Future<String> exportCsv() async {
    if (isDemo) return telemetryCsv(samples, source: 'demo');
    if (!_repository.available)
      throw StateError('Configure Firebase to export robot history.');
    return _repository.exportCsv();
  }

  static String _cleanError(Object e) => e
      .toString()
      .replaceFirst('Bad state: ', '')
      .replaceFirst('Exception: ', '');
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    _scanTimer?.cancel();
    _repository.onChanged = null;
    unawaited(_scanSubscription?.cancel() ?? Future.value());
    unawaited(_packetSubscription?.cancel() ?? Future.value());
    unawaited(_connectionSubscription?.cancel() ?? Future.value());
    // Closing the BLE connection also triggers the firmware's immediate stop.
    unawaited(_transport.dispose());
    unawaited(_repository.close());
    super.dispose();
  }
}
