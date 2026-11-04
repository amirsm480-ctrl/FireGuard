import 'dart:async';
import 'package:flutter/material.dart';
import 'app_controller.dart';
import 'ui/components.dart';
import 'ui/control.dart';
import 'ui/dashboard.dart';
import 'ui/data_pages.dart';

class FireguardApp extends StatefulWidget {
  const FireguardApp({super.key, required this.controller});
  final AppController controller;
  @override
  State<FireguardApp> createState() => _FireguardAppState();
}

class _FireguardAppState extends State<FireguardApp>
    with WidgetsBindingObserver {
  int _page = 0;
  final _scroll = ScrollController();
  static const _names = ['Overview', 'Control', 'History', 'Devices'];
  static const _descriptions = [
    'Your mission, in focus.',
    'Precision at your fingertips.',
    'Every reading. Every response.',
    'One robot. A direct connection.',
  ];
  static const _icons = [
    Icons.grid_view_rounded,
    Icons.gamepad_outlined,
    Icons.insights_outlined,
    Icons.bluetooth_rounded,
  ];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      widget.controller.onAppBackground();
    } else {
      widget.controller.onAppForeground();
    }
  }

  void _navigate(int page) {
    if (_page == page) return;
    if (_page == 1) unawaited(widget.controller.emergencyStop());
    setState(() => _page = page);
    if (_scroll.hasClients) _scroll.jumpTo(0);
    if (page == 2) unawaited(widget.controller.refreshHistory());
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'FireGuard',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: canvasColor,
      colorScheme: ColorScheme.fromSeed(
        seedColor: orange,
        primary: orange,
        secondary: teal,
        surface: Colors.white,
        onSurface: ink,
      ),
      fontFamily: 'Roboto',
      textTheme: ThemeData.light().textTheme.apply(
        bodyColor: ink,
        displayColor: ink,
        fontFamily: 'Roboto',
      ),
      dividerTheme: const DividerThemeData(color: line, thickness: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11),
          ),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          side: const BorderSide(color: Color(0xFFDDE2E8)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11),
          ),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: orange,
          textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ),
      sliderTheme: const SliderThemeData(
        trackHeight: 4,
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7),
        overlayShape: RoundSliderOverlayShape(overlayRadius: 16),
        inactiveTrackColor: line,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? teal
              : const Color(0xFFD9DFE5),
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: orange.withValues(alpha: .1),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 10,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected) ? orange : muted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 21,
            color: states.contains(WidgetState.selected) ? orange : muted,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: ink,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    home: AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          return Scaffold(
            bottomNavigationBar: wide
                ? null
                : DecoratedBox(
                    decoration: const BoxDecoration(
                      border: Border(top: BorderSide(color: line)),
                    ),
                    child: NavigationBar(
                      selectedIndex: _page,
                      onDestinationSelected: _navigate,
                      height: 67,
                      destinations: [
                        for (var i = 0; i < _names.length; i++)
                          NavigationDestination(
                            icon: Icon(_icons[i]),
                            label: _names[i],
                          ),
                      ],
                    ),
                  ),
            body: SafeArea(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (wide) _sidebar(context),
                  Expanded(
                    child: Column(
                      children: [
                        _topBar(context, wide),
                        Expanded(
                          child: SingleChildScrollView(
                            controller: _scroll,
                            padding: EdgeInsets.fromLTRB(
                              wide ? 32 : 16,
                              wide ? 28 : 23,
                              wide ? 32 : 16,
                              30,
                            ),
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 1160,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _pageHeader(context, wide),
                                    if (widget.controller.isDemo) ...[
                                      const SizedBox(height: 18),
                                      _demoBanner(),
                                    ],
                                    if (widget.controller.error != null) ...[
                                      const SizedBox(height: 16),
                                      _errorBanner(),
                                    ],
                                    if (widget.controller.isStale &&
                                        !widget.controller.isDemo) ...[
                                      const SizedBox(height: 16),
                                      const Panel(
                                        padding: 14,
                                        color: Color(0xFFFFF0EC),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.timer_off_outlined,
                                              color: orange,
                                              size: 20,
                                            ),
                                            SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                'Connection is stale. Controls are paused; reconnect to continue.',
                                                style: TextStyle(
                                                  color: Color(0xFF9E5239),
                                                  fontSize: 12,
                                                  height: 1.5,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 23),
                                    KeyedSubtree(
                                      key: ValueKey(_page),
                                      child: switch (_page) {
                                        0 => DashboardPage(
                                          controller: widget.controller,
                                          onControl: () => _navigate(1),
                                          onDevices: () => _navigate(3),
                                          onHistory: () => _navigate(2),
                                        ),
                                        1 => ControlPage(
                                          controller: widget.controller,
                                          onDevices: () => _navigate(3),
                                        ),
                                        2 => HistoryPage(
                                          controller: widget.controller,
                                        ),
                                        _ => DevicesPage(
                                          controller: widget.controller,
                                        ),
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
  Widget _sidebar(BuildContext context) => Container(
    width: 216,
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(right: BorderSide(color: line)),
    ),
    padding: const EdgeInsets.fromLTRB(20, 27, 20, 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _brand(),
        const SizedBox(height: 47),
        const Padding(
          padding: EdgeInsets.only(left: 12, bottom: 13),
          child: Text(
            'WORKSPACE',
            style: TextStyle(
              color: Color(0xFFA0A7B1),
              fontSize: 9,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        for (var i = 0; i < _names.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Material(
              color: _page == i ? const Color(0xFFFFF0E9) : Colors.transparent,
              borderRadius: BorderRadius.circular(11),
              child: InkWell(
                onTap: () => _navigate(i),
                borderRadius: BorderRadius.circular(11),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 15,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _icons[i],
                        size: 19,
                        color: _page == i ? orange : muted,
                      ),
                      const SizedBox(width: 13),
                      Text(
                        _names[i],
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: _page == i
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: _page == i ? orange : muted,
                        ),
                      ),
                      const Spacer(),
                      if (_page == i)
                        Container(
                          width: 5,
                          height: 5,
                          decoration: const BoxDecoration(
                            color: orange,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: canvasColor,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.bluetooth_connected_rounded,
                color: teal,
                size: 24,
              ),
              const SizedBox(height: 12),
              const Text(
                'Direct by design.',
                style: TextStyle(
                  color: ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 7),
              const Text(
                'Robot control over BLE.\nMission history in Firebase.',
                style: TextStyle(color: muted, fontSize: 10, height: 1.7),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => _showHelp(context),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 24),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('How it works →'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 23),
        Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: ink,
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(
                Icons.local_fire_department_rounded,
                color: Colors.white,
                size: 17,
              ),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'FireGuard Project',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 3),
                Text(
                  'ROBOT CONSOLE · V1.0',
                  style: TextStyle(
                    fontSize: 7,
                    letterSpacing: .8,
                    color: muted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  );
  Widget _brand({bool compact = false}) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: compact ? 31 : 36,
        height: compact ? 31 : 36,
        decoration: BoxDecoration(
          color: orange,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(
          Icons.local_fire_department_rounded,
          color: Colors.white,
          size: compact ? 22 : 25,
        ),
      ),
      const SizedBox(width: 9),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'FIREGUARD',
            style: TextStyle(
              color: ink,
              fontSize: compact ? 13 : 16,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (!compact) ...[
            const SizedBox(height: 3),
            const Text(
              'SMART FIREFIGHTING',
              style: TextStyle(color: muted, fontSize: 7, letterSpacing: 1.2),
            ),
          ],
        ],
      ),
    ],
  );
  Widget _topBar(BuildContext context, bool wide) => Container(
    height: 74,
    padding: EdgeInsets.symmetric(horizontal: wide ? 32 : 16),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: line)),
    ),
    child: Row(
      children: [
        if (wide)
          const Row(
            children: [
              Icon(Icons.home_outlined, size: 16, color: muted),
              SizedBox(width: 10),
              Text('Workspace', style: TextStyle(color: muted, fontSize: 11)),
              SizedBox(width: 10),
              Icon(
                Icons.chevron_right_rounded,
                size: 14,
                color: Color(0xFFB8BEC6),
              ),
              SizedBox(width: 8),
            ],
          )
        else
          _brand(compact: true),
        if (wide)
          Text(
            _names[_page],
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        const Spacer(),
        if (wide)
          StatusTag(
            widget.controller.isDemo
                ? 'Demo session'
                : widget.controller.isConnected
                ? 'Robot connected'
                : 'Robot offline',
            color: widget.controller.isDemo
                ? orange
                : widget.controller.isConnected
                ? teal
                : muted,
            icon: widget.controller.isDemo
                ? Icons.science_outlined
                : Icons.bluetooth_rounded,
          ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Connection & setup help',
          onPressed: () => _showHelp(context),
          icon: const Icon(Icons.help_outline_rounded, color: muted, size: 21),
        ),
      ],
    ),
  );
  Widget _pageHeader(BuildContext context, bool wide) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _names[_page],
              style: TextStyle(
                color: ink,
                fontSize: wide ? 29 : 25,
                letterSpacing: -.8,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _descriptions[_page],
              style: const TextStyle(color: muted, fontSize: 12),
            ),
          ],
        ),
      ),
      const SizedBox(width: 10),
      FilledButton.icon(
        onPressed: widget.controller.canControl
            ? () => unawaited(widget.controller.emergencyStop())
            : null,
        icon: const Icon(Icons.stop_circle_outlined, size: 17),
        label: Text(wide ? 'Emergency stop' : 'Stop'),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFBD4B3B),
          disabledBackgroundColor: const Color(0xFFEAECEF),
          disabledForegroundColor: const Color(0xFFA3A9B3),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
          minimumSize: const Size(0, 42),
        ),
      ),
    ],
  );
  Widget _demoBanner() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF2E4),
      border: Border.all(color: const Color(0xFFF7DFC5)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        const Icon(Icons.science_outlined, color: Color(0xFFB97A2F), size: 18),
        const SizedBox(width: 9),
        const Expanded(
          child: Text(
            'DEMO · Simulated robot. No hardware or Firebase writes.',
            style: TextStyle(
              fontSize: 11,
              height: 1.5,
              color: Color(0xFF9D6A2C),
            ),
          ),
        ),
        const SizedBox(width: 7),
        TextButton(
          onPressed: () => unawaited(widget.controller.stopDemo()),
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF9D6A2C),
            padding: const EdgeInsets.symmetric(horizontal: 7),
            minimumSize: const Size(0, 32),
          ),
          child: const Text('Exit'),
        ),
      ],
    ),
  );
  Widget _errorBanner() => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: const Color(0xFFFFEDEA),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.error_outline_rounded,
          color: Color(0xFFBD4B3B),
          size: 18,
        ),
        const SizedBox(width: 9),
        Expanded(
          child: SelectableText(
            widget.controller.error!,
            style: const TextStyle(
              fontSize: 11,
              height: 1.6,
              color: Color(0xFF9B493D),
            ),
          ),
        ),
        const SizedBox(width: 5),
        InkWell(
          onTap: widget.controller.clearError,
          child: const Padding(
            padding: EdgeInsets.all(3),
            child: Icon(
              Icons.close_rounded,
              color: Color(0xFF9B493D),
              size: 17,
            ),
          ),
        ),
      ],
    ),
  );
  void _showHelp(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(23)),
      title: const Row(
        children: [
          Icon(Icons.local_fire_department_rounded, color: orange),
          SizedBox(width: 9),
          Text(
            'A simpler connection',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          ),
        ],
      ),
      content: const SizedBox(
        width: 430,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '01  CONNECT WITH BLUETOOTH',
                style: TextStyle(
                  color: teal,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .5,
                ),
              ),
              SizedBox(height: 9),
              Text(
                'The ESP32 Dev Module has built-in BLE. Flash the included firmware, enable Bluetooth on your phone or iPad, then open Devices and scan for FireGuard.',
                style: TextStyle(fontSize: 12, height: 1.7),
              ),
              SizedBox(height: 23),
              Text(
                '02  KEEP YOUR MISSION HISTORY',
                style: TextStyle(
                  color: orange,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .5,
                ),
              ),
              SizedBox(height: 9),
              Text(
                'Firebase Cloud Firestore stores sensor readings and activity using your phone’s internet connection. Create a Firebase project, enable Anonymous Authentication and follow the included setup guide. Your robot does not need Wi-Fi.',
                style: TextStyle(fontSize: 12, height: 1.7),
              ),
              SizedBox(height: 23),
              Text(
                '03  CONTROL WITH CONFIDENCE',
                style: TextStyle(
                  color: ink,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .5,
                ),
              ),
              SizedBox(height: 9),
              Text(
                'Hold a direction to move; release to stop. Backgrounding the app disconnects the robot. The firmware stops the motor and pump if commands stop for 1.2 seconds, including in Auto mode.',
                style: TextStyle(fontSize: 12, height: 1.7),
              ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Got it'),
        ),
      ],
    ),
  );
}
