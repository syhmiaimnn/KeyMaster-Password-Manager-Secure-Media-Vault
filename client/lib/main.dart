import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:device_preview/device_preview.dart';
import 'security_service.dart';
import 'pin_setup_screen.dart';
import 'unlock_screen.dart';
import 'clipboard_service.dart';

// DevicePreview is a design tool. Use it only in debug builds on desktop,
// never on a real phone, never in a release build, never on the web.
bool get _useDevicePreview {
  if (kReleaseMode || kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final securityService = SecurityService();
  final bool hasPin = await securityService.hasPin();

  runApp(
    DevicePreview(
      enabled: _useDevicePreview,
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

  // When the app was covered by the gallery or camera (null = not covered)
  DateTime? _leftAt;

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
    final security = SecurityService();

    if (state == AppLifecycleState.paused) {
      if (security.isAutoLockPaused) {
        // The gallery or camera is open on top of the app. Stay unlocked for
        // now, but remember when we left.
        _leftAt = DateTime.now();
      } else {
        // Home button, app switcher or screen off
        _lockVault();
      }
    }

    if (state == AppLifecycleState.resumed) {
      // Back in the app: wipe the clipboard if the 30 seconds have passed
      ClipboardService.clearIfExpired();

      // Away for too long while the picker was open: lock now
      final left = _leftAt;
      _leftAt = null;
      if (left != null &&
          DateTime.now().difference(left) > SecurityService.autoLockGrace) {
        _lockVault();
      }
    }
  }

  void _lockVault() {
    final security = SecurityService();
    if (!security.isUnlocked) return; // nothing to lock yet

    security.lock(); // forget the vault key

    // Forget decrypted thumbnails and photos that Flutter kept for drawing
    imageCache.clear();
    imageCache.clearLiveImages();

    _navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const UnlockScreen()),
      (route) => false,
    );
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
}