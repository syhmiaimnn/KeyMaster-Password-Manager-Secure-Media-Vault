import 'package:device_preview/device_preview.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_lock.dart';
import 'app_settings.dart';
import 'onboarding_screen.dart';
import 'pin_setup_screen.dart';
import 'security_service.dart';
import 'ui/theme.dart';
import 'unlock_screen.dart';

// DevicePreview is a design tool. Use it only in debug builds on desktop,
// never on a real phone, never in a release build, never on the web.
bool get _useDevicePreview {
  if (kReleaseMode || kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Saved choices first, so the very first frame already has the right
  // theme and the screenshot guard is set before anything is shown.
  await AppSettings.instance.load();

  // The lock code lives in AppLock now (it used to be in this file).
  AppLock.instance.attach();

  final bool hasPin = await SecurityService().hasPin();

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

class _KeyMasterAppState extends State<KeyMasterApp> {
  // Decided once. Later changes of the settings must not swap the first screen.
  late final Widget _home = _firstScreen();

  Widget _firstScreen() {
    if (widget.hasPin) return const UnlockScreen();
    if (AppSettings.instance.onboardingDone) return const PinSetupScreen();
    return const OnboardingScreen();
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilds the app when the theme choice changes.
    return ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, child) {
        return MaterialApp(
          navigatorKey: AppLock.instance.navigatorKey,
          locale: DevicePreview.locale(context),
          builder: DevicePreview.appBuilder,
          debugShowCheckedModeBanner: false,
          title: 'KeyMaster',
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: AppSettings.instance.themeMode,
          home: _home,
        );
      },
    );
  }
}
