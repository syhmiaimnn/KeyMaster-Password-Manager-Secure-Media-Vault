import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'media_vault_screen.dart';
import 'security_center_screen.dart';
import 'security_service.dart';
import 'settings_screen.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';
import 'vault_dashboard_screen.dart';
import 'vault_store.dart';

/// The main screen after unlocking: four tabs and a bottom navigation bar.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final VaultStore _store = VaultStore.instance;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _store.load(force: true);
    SecurityService().isBiometricEnabled().then(AppSettings.instance.setBiometricOn);
  }

  void _go(int index) => setState(() => _index = index);

  Widget _securityIcon(int badge, {required bool selected}) {
    return Badge(
      isLabelVisible: badge > 0,
      label: Text('$badge'),
      child: Icon(
        selected ? Icons.verified_user_rounded : Icons.verified_user_outlined,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);

    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, result) {
        // Back from another tab goes to the first tab before leaving the app.
        if (!didPop) _go(0);
      },
      child: Scaffold(
        body: IndexedStack(
          index: _index,
          children: [
            VaultDashboardScreen(onOpenSecurity: () => _go(2)),
            const MediaVaultScreen(),
            SecurityCenterScreen(onOpenSettings: () => _go(3)),
            const SettingsScreen(),
          ],
        ),
        bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: p.border)),
          ),
          child: ListenableBuilder(
            listenable: Listenable.merge([_store, AppSettings.instance]),
            builder: (context, child) {
              final report = _store.report();
              final badge = report.issueCount + report.deviceIssues;
              return NavigationBar(
                selectedIndex: _index,
                onDestinationSelected: (value) {
                  tapFeedback();
                  _go(value);
                },
                destinations: [
                  const NavigationDestination(
                    icon: Icon(Icons.lock_outline_rounded),
                    selectedIcon: Icon(Icons.lock_rounded),
                    label: 'Vault',
                  ),
                  const NavigationDestination(
                    icon: Icon(Icons.photo_library_outlined),
                    selectedIcon: Icon(Icons.photo_library_rounded),
                    label: 'Photos',
                  ),
                  NavigationDestination(
                    icon: _securityIcon(badge, selected: false),
                    selectedIcon: _securityIcon(badge, selected: true),
                    label: 'Security',
                  ),
                  const NavigationDestination(
                    icon: Icon(Icons.settings_outlined),
                    selectedIcon: Icon(Icons.settings_rounded),
                    label: 'Settings',
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
