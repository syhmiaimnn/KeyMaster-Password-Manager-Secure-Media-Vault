import 'package:flutter/material.dart';

import 'ui/theme.dart';
import 'ui/widgets.dart';

/// What KeyMaster is and how it protects the user, in plain words. Also a good
/// page to open during the project presentation.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  Widget _row(Palette p, IconData icon, Color color, String title, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(icon: icon, color: color, size: 40),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.subtitle.copyWith(fontSize: 15.5)),
                const SizedBox(height: 3),
                Text(text, style: AppText.caption.copyWith(color: p.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final divider = Divider(height: 1, thickness: 1, indent: 70, color: p.border);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Row(
              children: [
                RoundIconButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Center(child: BrandMark(size: 84)),
            const SizedBox(height: 18),
            const Center(child: Text('KeyMaster', style: AppText.display)),
            const SizedBox(height: 6),
            Center(
              child: Text(
                'Password manager and secure media vault',
                style: AppText.body.copyWith(color: p.muted),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: p.primary.withAlpha(30),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'FINAL YEAR PROJECT · 17059D',
                  style: AppText.overline.copyWith(color: p.primary),
                ),
              ),
            ),
            const SectionLabel('How your data is protected'),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _row(
                    p,
                    Icons.pin_rounded,
                    p.primary,
                    'Master PIN to key',
                    'Your PIN is stretched with Argon2id (19 MiB of memory, '
                        '2 passes), so every guess is slow and expensive.',
                  ),
                  divider,
                  _row(
                    p,
                    Icons.vpn_key_rounded,
                    p.violet,
                    'A random vault key',
                    'A random 256-bit key encrypts your data. The PIN only '
                        'unlocks that key, so changing the PIN is instant.',
                  ),
                  divider,
                  _row(
                    p,
                    Icons.enhanced_encryption_rounded,
                    p.accent,
                    'AES-256-GCM',
                    'Passwords and notes are sealed with AES-256-GCM, which '
                        'also notices if anyone changes the data.',
                  ),
                  divider,
                  _row(
                    p,
                    Icons.photo_library_rounded,
                    p.success,
                    'Photos with their own keys',
                    'Each photo has its own key. GPS location and camera '
                        'details are removed before it is saved.',
                  ),
                  divider,
                  _row(
                    p,
                    Icons.timer_rounded,
                    p.warning,
                    'Lockout and auto-lock',
                    'Five wrong PINs trigger waits that get longer each time. '
                        'The vault locks when you leave the app.',
                  ),
                  divider,
                  _row(
                    p,
                    Icons.content_paste_off_rounded,
                    p.danger,
                    'Clipboard clean-up',
                    'Copied passwords are wiped from the clipboard after a '
                        'short time.',
                  ),
                  divider,
                  _row(
                    p,
                    Icons.cloud_off_rounded,
                    p.primary,
                    'Nothing leaves your phone',
                    'No account, no cloud and no analytics. The app never '
                        'sends your data anywhere.',
                  ),
                ],
              ),
            ),
            const SectionLabel('Honest limits'),
            const InfoBanner(
              icon: Icons.info_outline_rounded,
              text: 'Biometric unlock keeps a copy of the vault key in the '
                  "phone's secure storage (Android Keystore). A design bound "
                  'to the fingerprint hardware is planned for a later phase. '
                  'Also, Dart cannot guarantee that memory is wiped, so keys '
                  'are cleared on a best-effort basis.',
            ),
            const SizedBox(height: 18),
            Center(
              child: SoftButton(
                label: 'Open-source licences',
                icon: Icons.description_outlined,
                onPressed: () => showLicensePage(
                  context: context,
                  applicationName: 'KeyMaster',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
