import 'package:flutter/material.dart';

import 'security_service.dart';
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
    // The decoy vault must not explain that it is one, so a decoy session
    // does not show the two Phase 7 features.
    final decoy = SecurityService().isDecoySession;

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
                    Icons.key_rounded,
                    p.warning,
                    'Recovery phrase',
                    'Twelve random words make a second key that opens the same '
                        'vault key. Write them on paper. If you forget the PIN, '
                        'the words get you back in.',
                  ),
                  divider,
                  _row(
                    p,
                    Icons.fingerprint_rounded,
                    p.accent,
                    'Fingerprint tied to the hardware',
                    'The key behind fingerprint unlock lives in the Android '
                        'Keystore and cannot be copied out. Adding a new '
                        'fingerprint to the phone switches it off.',
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
                    'Each photo has its own key. Before it is saved you see '
                        'what it gives away. Location, camera and phone '
                        'details, dates, owner fields and thumbnails are then '
                        'removed, and the saved copy is read back to check.',
                  ),
                  divider,
                  _row(
                    p,
                    Icons.account_tree_rounded,
                    p.violet,
                    'Folders with their own keys',
                    'Photos live in folders. Every folder has its own key, '
                        'and the keys of its photos are locked with it. '
                        'Deleting a folder deletes its key, so its photos can '
                        'never be opened again.',
                  ),
                  divider,
                  _row(
                    p,
                    Icons.share_rounded,
                    p.accent,
                    'Clean copies for sharing',
                    'Share a photo from the vault as a fresh copy with no '
                        'hidden data. It is checked again just before it '
                        'leaves, and the temporary file is deleted afterwards.',
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
                  if (!decoy) ...[
                    divider,
                    _row(
                      p,
                      Icons.theater_comedy_rounded,
                      p.violet,
                      'Decoy vault',
                      'A second PIN opens a different vault with harmless '
                          'entries. Both PINs take the same time, and the '
                          'stored data looks the same with or without a '
                          'decoy.',
                    ),
                    divider,
                    _row(
                      p,
                      Icons.camera_front_rounded,
                      p.danger,
                      'Intruder photo',
                      'After five wrong PINs the front camera takes a photo. '
                          'It is locked with a public key, so it can be taken '
                          'while the app is locked. Only the open real vault '
                          'can unlock it.',
                    ),
                  ],
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
              text: 'Anyone who finds your recovery phrase can open the vault, '
                  'so keep the paper safe. Some phones rate their fingerprint '
                  'sensor too weak to guard a key, and there only the PIN '
                  'works. Dart cannot guarantee that memory is wiped, so keys '
                  'are cleared on a best-effort basis.',
            ),
            const SizedBox(height: 12),
            const InfoBanner(
              icon: Icons.warning_amber_rounded,
              text: 'Your original photo stays in the gallery until you delete '
                  'it there. A clean copy you share belongs to the app that '
                  'receives it. While you share, the copy sits in the '
                  'private cache of the app for a few minutes. Cleaning '
                  'removes hidden data in the file, not what the picture '
                  'shows: faces, street signs and screens are not detected. '
                  'Rebuilding a photo can also change its colours slightly.',
            ),
            if (!decoy) ...[
              const SizedBox(height: 12),
              const InfoBanner(
                icon: Icons.theater_comedy_rounded,
                text: 'The decoy vault hides which PIN you typed. It does not '
                    'hide that KeyMaster has the feature, so someone who '
                    'knows the app can look for missing settings. The '
                    'intruder camera shows the green camera dot on Android 12 '
                    'and newer, and it needs the camera permission.',
              ),
            ],
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
