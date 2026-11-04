import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../domain.dart';

abstract class RobotTransport {
  Stream<List<int>> get packets;
  Stream<bool> get connectionChanges;
  Stream<RobotDevice> scan();
  Future<void> connect(String deviceId);
  Future<void> write(List<int> bytes);
  Future<void> disconnect();
  Future<void> dispose();
}

class BleRobotTransport implements RobotTransport {
  FlutterReactiveBle? _instance;
  FlutterReactiveBle get _ble => _instance ??= FlutterReactiveBle();
  static final _service = Uuid.parse(RobotProtocol.serviceUuid);
  static final _command = Uuid.parse(RobotProtocol.commandUuid);
  static final _telemetry = Uuid.parse(RobotProtocol.telemetryUuid);
  final _packets = StreamController<List<int>>.broadcast();
  final _connections = StreamController<bool>.broadcast();
  StreamSubscription<ConnectionStateUpdate>? _connection;
  StreamSubscription<List<int>>? _notification;
  String? _deviceId;
  int _connectionEpoch = 0;
  @override
  Stream<List<int>> get packets => _packets.stream;
  @override
  Stream<bool> get connectionChanges => _connections.stream;
  Future<void> _ready() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      throw StateError(
        'Use the Android or iOS app for Bluetooth. Browser preview supports demo only.',
      );
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      final sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
      final permissions = sdk >= 31
          ? [Permission.bluetoothScan, Permission.bluetoothConnect]
          : [Permission.locationWhenInUse];
      final result = await permissions.request();
      if (result.values.any((s) => !s.isGranted)) {
        throw StateError(
          'Bluetooth permission is required. Allow it in device settings.',
        );
      }
    }
    final status = _ble.status == BleStatus.unknown
        ? await _ble.statusStream
              .firstWhere((s) => s != BleStatus.unknown)
              .timeout(const Duration(seconds: 8))
        : _ble.status;
    if (status != BleStatus.ready) {
      throw StateError(
        status == BleStatus.poweredOff
            ? 'Turn on Bluetooth, then scan again.'
            : status == BleStatus.locationServicesDisabled
            ? 'Enable Location services to scan on this Android version.'
            : 'Bluetooth is unavailable or permission was denied. Check device settings.',
      );
    }
  }

  @override
  Stream<RobotDevice> scan() async* {
    await _ready();
    yield* _ble
        .scanForDevices(withServices: [_service], scanMode: ScanMode.lowLatency)
        .map(
          (d) => RobotDevice(
            id: d.id,
            name: d.name.isEmpty ? 'FireGuard Robot' : d.name,
            rssi: d.rssi,
          ),
        );
  }

  @override
  Future<void> connect(String deviceId) async {
    await disconnect();
    final epoch = _connectionEpoch;
    await _ready();
    if (epoch != _connectionEpoch) throw StateError('Connection cancelled');
    _deviceId = deviceId;
    final ready = Completer<void>();
    _connection = _ble
        .connectToDevice(
          id: deviceId,
          servicesWithCharacteristicsToDiscover: {
            _service: [_command, _telemetry],
          },
          connectionTimeout: const Duration(seconds: 10),
        )
        .listen(
          (update) {
            if (epoch != _connectionEpoch) return;
            if (update.connectionState == DeviceConnectionState.connected) {
              _notification = _ble
                  .subscribeToCharacteristic(
                    QualifiedCharacteristic(
                      serviceId: _service,
                      characteristicId: _telemetry,
                      deviceId: deviceId,
                    ),
                  )
                  .listen(
                    _packets.add,
                    onError: (Object e) {
                      _packets.addError(e);
                    },
                  );
              _connections.add(true);
              if (!ready.isCompleted) ready.complete();
            } else if (update.connectionState ==
                DeviceConnectionState.disconnected) {
              _connections.add(false);
              if (!ready.isCompleted)
                ready.completeError(
                  StateError('Robot disconnected before it was ready.'),
                );
            }
          },
          onError: (Object e) {
            if (epoch != _connectionEpoch) return;
            _connections.add(false);
            if (!ready.isCompleted) ready.completeError(e);
          },
        );
    await ready.future.timeout(const Duration(seconds: 12));
  }

  @override
  Future<void> write(List<int> bytes) async {
    final id = _deviceId;
    if (id == null) throw StateError('Robot is disconnected');
    await _ble.writeCharacteristicWithResponse(
      QualifiedCharacteristic(
        serviceId: _service,
        characteristicId: _command,
        deviceId: id,
      ),
      value: bytes,
    );
  }

  @override
  Future<void> disconnect() async {
    _connectionEpoch++;
    _deviceId = null;
    await _notification?.cancel();
    _notification = null;
    await _connection?.cancel();
    _connection = null;
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    await _packets.close();
    await _connections.close();
  }
}
