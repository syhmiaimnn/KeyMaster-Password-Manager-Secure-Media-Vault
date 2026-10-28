import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'pin_setup_screen.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';

class _OnboardPage {
  final IconData icon;
  final Color Function(Palette) color;
  final String title;
  final String body;
  final List<IconData> orbit;

  const _OnboardPage({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
    required this.orbit,
  });
}

/// Three welcome pages, shown once before the Master PIN is created.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _index = 0;

  static final List<_OnboardPage> _pages = [
    _OnboardPage(
      icon: Icons.shield_rounded,
      color: (p) => p.primary,
      title: 'Your passwords, locked down',
      body: 'Every login and secret note lives in an encrypted vault that '
          'only your Master PIN can open.',
      orbit: const [
        Icons.lock_rounded,
        Icons.password_rounded,
        Icons.fingerprint_rounded,
      ],
    ),
    _OnboardPage(
      icon: Icons.photo_library_rounded,
      color: (p) => p.accent,
      title: 'Photos that keep your secrets',
      body: 'Each photo gets its own key. Location and camera details are '
          'stripped before it is saved.',
      orbit: const [
        Icons.location_off_rounded,
        Icons.photo_camera_rounded,
        Icons.enhanced_encryption_rounded,
      ],
    ),
    _OnboardPage(
      icon: Icons.cloud_off_rounded,
      color: (p) => p.violet,
      title: 'Private by design',
      body: 'No account, no cloud, no tracking. Everything stays on this '
          'phone and locks itself when you leave.',
      orbit: const [
        Icons.wifi_off_rounded,
        Icons.timer_rounded,
        Icons.visibility_off_rounded,
      ],
    ),
  ];

  bool get _isLast => _index == _pages.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_isLast) {
      _finish();
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _finish() async {
    await AppSettings.instance.setOnboardingDone();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      fadeRoute<void>(const PinSetupScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Scaffold(
      body: AuroraBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 12, 0),
                child: Row(
                  children: [
                    const BrandMark(size: 36),
                    const SizedBox(width: 10),
                    const Text('KeyMaster', style: AppText.subtitle),
                    const Spacer(),
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: _isLast ? 0 : 1,
                      child: TextButton(
                        onPressed: _isLast ? null : _finish,
                        child: Text('Skip', style: TextStyle(color: p.muted)),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _pages.length,
                  onPageChanged: (value) => setState(() => _index = value),
                  itemBuilder: (context, i) => _OnboardPageView(page: _pages[i]),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _pages.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: i == _index ? 26 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _index ? p.primary : p.border,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
                child: GradientButton(
                  label: _isLast ? 'Get started' : 'Continue',
                  icon: _isLast
                      ? Icons.rocket_launch_rounded
                      : Icons.arrow_forward_rounded,
                  onPressed: _next,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardPageView extends StatelessWidget {
  final _OnboardPage page;
  const _OnboardPageView({required this.page});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final color = page.color(p);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: [
          const SizedBox(height: 8),
          _Art(icon: page.icon, color: color, orbit: page.orbit),
          const SizedBox(height: 28),
          Text(
            page.title,
            textAlign: TextAlign.center,
            style: AppText.display.copyWith(fontSize: 27),
          ),
          const SizedBox(height: 14),
          Text(
            page.body,
            textAlign: TextAlign.center,
            style: AppText.body.copyWith(color: p.muted, fontSize: 15.5),
          ),
        ],
      ),
    );
  }
}

/// A big icon tile with three small icons around it.
class _Art extends StatelessWidget {
  final IconData icon;
  final Color color;
  final List<IconData> orbit;

  const _Art({required this.icon, required this.color, required this.orbit});

  Widget _chip(Palette p, IconData data, Alignment alignment) {
    return Align(
      alignment: alignment,
      child: Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: p.border),
          boxShadow: [
            BoxShadow(color: color.withAlpha(40), blurRadius: 16),
          ],
        ),
        child: Icon(data, color: color, size: 26),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.85, end: 1),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) {
        return Transform.scale(scale: scale, child: child);
      },
      child: SizedBox(
        width: 280,
        height: 280,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [color.withAlpha(64), color.withAlpha(0)],
                ),
              ),
            ),
            Container(
              width: 204,
              height: 204,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: color.withAlpha(60)),
              ),
            ),
            Container(
              width: 116,
              height: 116,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(36),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [color, color.withAlpha(170)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withAlpha(110),
                    blurRadius: 36,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 56),
            ),
            _chip(p, orbit[0], const Alignment(-0.92, -0.45)),
            _chip(p, orbit[1], const Alignment(0.95, -0.1)),
            _chip(p, orbit[2], const Alignment(-0.3, 0.95)),
          ],
        ),
      ),
    );
  }
}
