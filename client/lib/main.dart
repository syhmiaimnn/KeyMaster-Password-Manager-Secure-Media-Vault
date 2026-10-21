import 'package:flutter/material.dart';
import 'package:device_preview/device_preview.dart';
import 'security_service.dart';
import 'vault_dashboard_screen.dart';
import 'pin_setup_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final securityService = SecurityService();
  bool hasPin = await securityService.hasPin();

  runApp(
    DevicePreview(
      enabled: true,
      builder: (context) => KeyMasterApp(hasPin: hasPin),
    ),
  );
}

class KeyMasterApp extends StatelessWidget {
  final bool hasPin;
  const KeyMasterApp({super.key, required this.hasPin});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: DevicePreview.locale(context),
      builder: DevicePreview.appBuilder,
      debugShowCheckedModeBanner: false,
      title: 'KeyMaster',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        primarySwatch: Colors.blue,
      ),
      home: hasPin ? const VaultDashboardScreen() : const PinSetupScreen(),
    );
  }
}