import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_controller.dart';
import 'components.dart';

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key, required this.controller});
  final AppController controller;
  Future<void> _export(BuildContext context) async {
    try {
      final data = await controller.exportCsv();
      await Clipboard.setData(ClipboardData(text: data));
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'CSV copied to clipboard. Paste it into a spreadsheet or file.',
            ),
          ),
        );
    } catch (error) {
      if (context.mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not export: $error')));
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: orange.withValues(alpha: .09),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.cloud_outlined,
                    color: orange,
                    size: 27,
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Your mission log',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 19,
                          letterSpacing: -.3,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        controller.isDemo
                            ? 'Demo session · not saved to Firebase'
                            : controller.databaseLabel,
                        style: const TextStyle(
                          fontSize: 12,
                          color: muted,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Wrap(
              spacing: 24,
              runSpacing: 18,
              children: [
                _Figure(
                  '${controller.storedSampleCount}',
                  'SESSION SAMPLES QUEUED',
                ),
                _Figure('${controller.activities.length}', 'EVENTS IN VIEW'),
                _Figure(controller.isDemo ? 'DEMO' : 'CLOUD', 'DATA SOURCE'),
              ],
            ),
            const SizedBox(height: 23),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: () => unawaited(controller.refreshHistory()),
                  icon: const Icon(Icons.refresh_rounded, size: 17),
                  label: const Text('Refresh history'),
                ),
                FilledButton.icon(
                  onPressed: () => unawaited(_export(context)),
                  icon: const Icon(Icons.content_copy_rounded, size: 16),
                  label: const Text('Copy CSV'),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 22),
      Panel(
        child: Column(
          children: [
            SectionTitle(
              'Sensor timeline',
              subtitle: controller.isDemo
                  ? 'Simulated samples for this demo'
                  : 'Recent samples in view · raw ADC values',
              trailing: const StatusTag('MQ2', color: orange),
            ),
            const SizedBox(height: 22),
            GasChart(samples: controller.samples, height: 200),
            if (controller.samples.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 15),
                child: Text(
                  'No readings yet. Connect a robot to collect samples.',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 22),
      Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle(
              'Activity history',
              subtitle: 'Connections, mode changes and sensor events',
            ),
            const SizedBox(height: 23),
            ActivityList(entries: controller.activities, limit: 100),
          ],
        ),
      ),
      const SizedBox(height: 18),
      const Text(
        'Firebase uses your phone or tablet’s internet connection. BLE control works directly with the robot. Anonymous sign-in keeps each installation’s history separate.',
        style: TextStyle(color: muted, fontSize: 11, height: 1.7),
      ),
    ],
  );
}

class _Figure extends StatelessWidget {
  const _Figure(this.value, this.label);
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: const TextStyle(
          color: ink,
          fontSize: 25,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        label,
        style: const TextStyle(
          color: muted,
          fontSize: 8,
          letterSpacing: .8,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}

class DevicesPage extends StatelessWidget {
  const DevicesPage({super.key, required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle(
              'Connect your robot',
              subtitle: 'A direct Bluetooth Low Energy connection',
            ),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F6F8),
                borderRadius: BorderRadius.circular(17),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(17),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Icon(
                      controller.isConnected
                          ? Icons.bluetooth_connected_rounded
                          : Icons.bluetooth_rounded,
                      size: 37,
                      color: teal,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    controller.connectionLabel,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    controller.isConnected
                        ? 'Your ESP32 is linked to this device.'
                        : controller.isDemo
                        ? 'Demo mode is active. Exit the demo to connect a real robot.'
                        : 'Power on your ESP32 and keep it nearby.\nNo robot Wi-Fi hotspot is needed.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: muted,
                      fontSize: 12,
                      height: 1.7,
                    ),
                  ),
                  const SizedBox(height: 19),
                  if (controller.isConnected)
                    OutlinedButton.icon(
                      onPressed: () => unawaited(controller.disconnect()),
                      icon: const Icon(Icons.link_off_rounded, size: 17),
                      label: const Text('Disconnect robot'),
                    )
                  else if (controller.isDemo)
                    OutlinedButton.icon(
                      onPressed: () => unawaited(controller.stopDemo()),
                      icon: const Icon(Icons.close_rounded, size: 17),
                      label: const Text('Exit demo'),
                    )
                  else
                    FilledButton.icon(
                      onPressed:
                          controller.isScanning || controller.isConnecting
                          ? null
                          : () => unawaited(controller.scan()),
                      icon: controller.isScanning
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(
                              Icons.bluetooth_searching_rounded,
                              size: 18,
                            ),
                      label: Text(
                        controller.isScanning
                            ? 'Scanning nearby…'
                            : controller.isConnecting
                            ? 'Connecting…'
                            : 'Scan for robot',
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'NEARBY DEVICES',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: muted,
                    ),
                  ),
                ),
                Text(
                  '${controller.devices.length} found',
                  style: const TextStyle(color: muted, fontSize: 10),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (controller.devices.isEmpty)
              EmptyState(
                icon: Icons.radar_rounded,
                title: controller.isScanning
                    ? 'Looking for FireGuard…'
                    : 'No robot discovered yet',
                detail:
                    'Only robots advertising the FireGuard BLE service appear here. Flash the included firmware first.',
              )
            else
              ...controller.devices.map(
                (device) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      border: Border.all(color: line),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.developer_board_rounded,
                          color: teal,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                device.name.isEmpty
                                    ? 'FireGuard Robot'
                                    : device.name,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                '${device.rssi} dBm · Bluetooth LE',
                                style: const TextStyle(
                                  color: muted,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed:
                              controller.isConnecting || controller.isConnected
                              ? null
                              : () => unawaited(controller.connect(device)),
                          child: const Text('Connect'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 22),
      Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle(
              'Take a look around',
              subtitle: 'Try the interface before connecting your hardware',
            ),
            const SizedBox(height: 15),
            const Text(
              'Demo mode uses simulated sensor readings. You can try the controls, nozzle and pump without moving a real robot. Nothing is uploaded to Firebase.',
              style: TextStyle(color: muted, fontSize: 12, height: 1.7),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: controller.isConnecting
                  ? null
                  : () => unawaited(
                      controller.isDemo
                          ? controller.stopDemo()
                          : controller.startDemo(),
                    ),
              icon: Icon(
                controller.isDemo
                    ? Icons.close_rounded
                    : Icons.play_circle_outline_rounded,
                size: 18,
              ),
              label: Text(
                controller.isDemo ? 'Exit demo mode' : 'Explore demo',
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 22),
      Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle(
              'Cloud connection',
              subtitle: 'Firebase Cloud Firestore',
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.cloud_outlined, color: orange, size: 21),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    controller.databaseLabel,
                    style: const TextStyle(
                      color: ink,
                      fontSize: 12,
                      height: 1.6,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              'Create your Firebase project, enable Anonymous Authentication, then connect the app configuration. The setup guide included with this project walks you through each step.',
              style: TextStyle(color: muted, fontSize: 12, height: 1.7),
            ),
          ],
        ),
      ),
    ],
  );
}
