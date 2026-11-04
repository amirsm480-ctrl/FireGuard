import 'dart:async';
import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'firebase_bootstrap.dart';
import 'fireguard_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeFirebase();
  final controller = AppController();
  runApp(FireguardApp(controller: controller));
  unawaited(controller.init());
}
