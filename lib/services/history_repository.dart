import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../domain.dart';

abstract class HistoryRepository {
  bool get persistent;
  bool get available;
  String get label;
  void Function()? onChanged;
  Future<void> open();
  Future<void> selectDevice(String deviceId);
  Future<void> saveSample(Telemetry sample, String deviceId);
  Future<void> saveActivity(ActivityEntry event);
  Future<List<Telemetry>> recentSamples({int limit = 60});
  Future<List<ActivityEntry>> recentActivities();
  Future<int> sampleCount();
  Future<String> exportCsv();
  Future<void> close();
}

class FirestoreHistoryRepository extends HistoryRepository {
  FirebaseFirestore? _firestore;
  String? _uid;
  String? _robotId;
  String? _failure;
  int _queued = 0;
  int _sessionSamples = 0;
  @override
  bool get persistent => true;
  @override
  bool get available => _uid != null;
  @override
  String get label =>
      _failure ??
      (!available
          ? 'Firebase not configured'
          : _queued > 0
          ? 'Firebase · $_queued pending sync'
          : 'Firebase · synced');
  @override
  Future<void> open() async {
    if (Firebase.apps.isEmpty) return;
    try {
      final auth = FirebaseAuth.instance;
      final user =
          auth.currentUser ??
          (await auth.signInAnonymously().timeout(
            const Duration(seconds: 10),
          )).user;
      if (user == null) throw StateError('Sign-in returned no user');
      _uid = user.uid;
      _firestore = FirebaseFirestore.instance;
      final profile = await _firestore!
          .doc('users/$_uid')
          .get()
          .timeout(const Duration(seconds: 5));
      _robotId = profile.data()?['lastRobotId'] as String?;
    } catch (e) {
      _failure = 'Firebase unavailable · check configuration and connection';
      // A previously authenticated user can still queue Firestore writes offline.
      onChanged?.call();
    }
  }

  CollectionReference<Map<String, dynamic>>? get _samples =>
      !available || _robotId == null
      ? null
      : _firestore!.collection('users/$_uid/robots/$_robotId/samples');
  CollectionReference<Map<String, dynamic>>? get _events =>
      !available || _robotId == null
      ? null
      : _firestore!.collection('users/$_uid/robots/$_robotId/events');
  @override
  Future<void> selectDevice(String deviceId) async {
    if (!available) return;
    // URL-safe encoding keeps both iOS UUIDs and Android addresses valid document IDs.
    final robotId = base64Url.encode(utf8.encode(deviceId)).replaceAll('=', '');
    if (_robotId != robotId) _sessionSamples = 0;
    _robotId = robotId;
    _enqueue(
      _firestore!.doc('users/$_uid').set({
        'lastRobotId': _robotId,
      }, SetOptions(merge: true)),
    );
  }

  void _enqueue(Future<void> write) {
    _queued++;
    onChanged?.call();
    unawaited(
      write.then(
        (_) {
          _queued--;
          _failure = null;
          onChanged?.call();
        },
        onError: (Object error, StackTrace stack) {
          _queued--;
          _failure = 'Firebase write failed · check rules and connection';
          onChanged?.call();
        },
      ),
    );
  }

  @override
  Future<void> saveSample(Telemetry sample, String deviceId) async {
    if (_samples == null) return;
    _sessionSamples++;
    _enqueue(
      _samples!.doc().set({
        ...sample.toMap(),
        'deviceId': deviceId,
        'source': 'robot',
        'serverAt': FieldValue.serverTimestamp(),
      }),
    );
  }

  @override
  Future<void> saveActivity(ActivityEntry event) async {
    if (_events == null || event.demo) return;
    _enqueue(
      _events!.doc().set({
        ...event.toMap(),
        'source': 'robot',
        'serverAt': FieldValue.serverTimestamp(),
      }),
    );
  }

  @override
  Future<List<Telemetry>> recentSamples({int limit = 60}) async {
    if (_samples == null) return [];
    final result = await _samples!
        .orderBy('at', descending: true)
        .limit(limit)
        .get()
        .timeout(const Duration(seconds: 6));
    return result.docs
        .map((d) => Telemetry.fromMap(d.data()))
        .toList()
        .reversed
        .toList();
  }

  @override
  Future<List<ActivityEntry>> recentActivities() async {
    if (_events == null) return [];
    final result = await _events!
        .orderBy('at', descending: true)
        .limit(100)
        .get()
        .timeout(const Duration(seconds: 6));
    return result.docs.map((d) => ActivityEntry.fromMap(d.data())).toList();
  }

  @override
  Future<int> sampleCount() async => _sessionSamples;
  @override
  Future<String> exportCsv() async {
    final samples = await recentSamples(limit: 1000);
    return telemetryCsv(samples, source: 'robot');
  }

  @override
  Future<void> close() async {
    onChanged = null;
  }
}

String telemetryCsv(List<Telemetry> samples, {required String source}) =>
    'source,time,mode,motion,speed,servo,distance_cm,mq2_raw,flame_left,flame_center,flame_right,pump\n${samples.map((s) => [source, s.receivedAt.toUtc().toIso8601String(), s.mode.name, s.motion.name, s.speed, s.servo, s.distanceCm ?? '', s.mq2, s.flameLeft, s.flameCenter, s.flameRight, s.pump].join(',')).join('\n')}';

/// Explicitly volatile storage for tests. Demo data never enters a cloud repository.
class MemoryHistoryRepository extends HistoryRepository {
  final List<Telemetry> _samples = [];
  final List<ActivityEntry> _events = [];
  @override
  bool get persistent => false;
  @override
  bool get available => true;
  @override
  String get label => 'In-memory test storage';
  @override
  Future<void> open() async {}
  @override
  Future<void> selectDevice(String deviceId) async {}
  @override
  Future<void> saveSample(Telemetry sample, String deviceId) async {
    _samples.add(sample);
  }

  @override
  Future<void> saveActivity(ActivityEntry event) async {
    if (!event.demo) _events.insert(0, event);
  }

  @override
  Future<List<Telemetry>> recentSamples({int limit = 60}) async => _samples
      .skip((_samples.length - limit).clamp(0, _samples.length))
      .toList();
  @override
  Future<List<ActivityEntry>> recentActivities() async => List.of(_events);
  @override
  Future<int> sampleCount() async => _samples.length;
  @override
  Future<String> exportCsv() async => telemetryCsv(_samples, source: 'robot');
  @override
  Future<void> close() async {}
}
