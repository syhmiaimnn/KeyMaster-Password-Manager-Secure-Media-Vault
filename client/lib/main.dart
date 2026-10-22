import 'package:flutter/material.dart';
import 'package:device_preview/device_preview.dart';
import 'package:flutter/foundation.dart';
import 'security_service.dart';
import 'pin_setup_screen.dart';
import 'unlock_screen.dart';
import 'clipboard_service.dart';

void main() async {
  
  WidgetsFlutterBinding.ensureInitialized();

  final securityService = SecurityService();
  final bool hasPin = await securityService.hasPin();

  runApp(
    DevicePreview(
      enabled: true, // Fix 8 changes this line
      builder: (context) => KeyMasterApp(hasPin: hasPin),
    ),
  );
}

class KeyMasterApp extends StatefulWidget {
  final bool hasPin;
  const KeyMasterApp({super.key, required this.hasPin});

  @override
  State<KeyMasterApp> createState() => _KeyMasterAppState();
}

class _KeyMasterAppState extends State<KeyMasterApp>
    with WidgetsBindingObserver {
  // Lets us change screens from outside a widget (when the app locks)
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // paused = the app is no longer visible (Home button, app switcher, screen off)
    if (state == AppLifecycleState.paused) {
      _lockVault();
    }
    // Back in the app: wipe the clipboard if the 30 seconds have passed
    if (state == AppLifecycleState.resumed) {
      ClipboardService.clearIfExpired();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      locale: DevicePreview.locale(context),
      builder: DevicePreview.appBuilder,
      debugShowCheckedModeBanner: false,
      title: 'KeyMaster',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        primarySwatch: Colors.blue,
      ),
      home: widget.hasPin ? const UnlockScreen() : const PinSetupScreen(),
    );
  }
  
  void _lockVault() {}
}