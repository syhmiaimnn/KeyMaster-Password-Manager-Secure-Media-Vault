import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'generator_screen.dart';
import 'item_detail_screen.dart';
import 'password_tools.dart';
import 'ui/format.dart';
import 'ui/score_ring.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';
import 'vault_item.dart';
import 'vault_store.dart';

enum _Issue { weak, reused, old }

/// The Security tab: a score for the whole vault, the passwords that need
/// attention, and a checklist of device protections.
class SecurityCenterScreen extends StatefulWidget {
  /// Called when a failing checklist row is tapped (the shell opens Settings).
  final VoidCallback? onOpenSettings;

  const SecurityCenterScreen({super.key, this.onOpenSettings});

  @override
  State<SecurityCenterScreen> createState() => _SecurityCenterScreenState();
}

class _SecurityCenterScreenState extends State<SecurityCenterScreen> {
  final VaultStore _store = VaultStore.instance;
  _Issue? _chosen;

  List<VaultItem> _itemsFor(SecurityReport report, _Issue issue) {
    switch (issue) {
      case _Issue.weak:
        return report.weak;
      case _Issue.reused:
        return report.reused;
      case _Issue.old:
        return report.old;
    }
  }

  /// The issue to show: the one the user tapped, or the first one that has
  /// items.
  _Issue? _active(SecurityReport report) {
    final chosen = _chosen;
    if (chosen != null) return chosen;
    for (final issue in _Issue.values) {
      if (_itemsFor(report, issue).isNotEmpty) return issue;
    }
    return null;
  }

  String _reason(VaultItem item, _Issue issue) {
    switch (issue) {
      case _Issue.weak:
        final result = PasswordTools.evaluate(item.password);
        return '${result.label} · about ${result.bits.round()} bits';
      case _Issue.reused:
        final others = _store.logins
            .where((other) => other.id != item.id && other.password == item.password)
            .length;
        return others == 1
            ? 'Same password as 1 other item'
            : 'Same password as $others other items';
      case _Issue.old:
        return 'Changed ${timeAgo(item.updatedAt)}';
    }
  }

  Widget _scoreCard(Palette p, SecurityReport report) {
    final passed = report.checklist.where((entry) => entry.ok).length;
    final String headline;
    if (report.passwordCount == 0) {
      headline = 'Add some passwords and KeyMaster will check them for you.';
    } else if (report.issueCount == 0 && report.deviceIssues == 0) {
      headline = 'Everything looks great. Keep it up.';
    } else {
      final parts = <String>[];
      if (report.issueCount > 0) {
        parts.add(report.issueCount == 1
            ? '1 password to fix'
            : '${report.issueCount} passwords to fix');
      }
      if (report.deviceIssues > 0) {
        parts.add(report.deviceIssues == 1
            ? '1 setting to review'
            : '${report.deviceIssues} settings to review');
      }
      headline = parts.join(' and ');
    }

    return AppCard(
      padding: const EdgeInsets.all(20),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [p.surface, p.surfaceAlt],
      ),
      child: Row(
        children: [
          ScoreRing(score: report.score, size: 112, strokeWidth: 10),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SECURITY SCORE',
                  style: AppText.overline.copyWith(color: p.muted),
                ),
                const SizedBox(height: 4),
                Text(
                  report.verdict,
                  style: AppText.display.copyWith(
                    fontSize: 24,
                    color: ScoreRing.colorFor(p, report.score),
                  ),
                ),
                const SizedBox(height: 8),
                Text(headline, style: AppText.caption.copyWith(color: p.muted)),
                const SizedBox(height: 10),
                Text(
                  '$passed of ${report.checklist.length} protections on',
                  style: AppText.caption.copyWith(
                    color: p.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _issueCard(
    Palette p, {
    required _Issue issue,
    required IconData icon,
    required Color color,
    required String label,
    required int count,
    required bool selected,
  }) {
    return Expanded(
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        color: selected ? color.withAlpha(28) : p.surface,
        borderColor: selected ? color : p.border,
        onTap: () {
          tapFeedback();
          setState(() => _chosen = issue);
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: count == 0 ? p.success : color, size: 20),
                const Spacer(),
                if (count == 0)
                  Icon(Icons.check_circle_rounded, color: p.success, size: 16),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '$count',
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            ),
            Text(label, style: AppText.caption.copyWith(color: p.muted)),
          ],
        ),
      ),
    );
  }

  Widget _issueList(Palette p, SecurityReport report, _Issue? active) {
    if (report.passwordCount == 0) {
      return const InfoBanner(
        icon: Icons.key_rounded,
        text: 'No passwords yet. Add one from the Vault tab to see its strength here.',
      );
    }
    if (active == null || _itemsFor(report, active).isEmpty) {
      return InfoBanner(
        icon: Icons.verified_rounded,
        color: p.success,
        text: 'Nothing to fix here. Your passwords are strong, different from '
            'each other and recently changed.',
      );
    }

    final items = _itemsFor(report, active);
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, indent: 72, color: p.border),
            InkWell(
              onTap: () => openItemDetail(context, items[i].id),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    ItemAvatar(title: items[i].title, size: 42),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            items[i].title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.subtitle.copyWith(fontSize: 15),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _reason(items[i], active),
                            style: AppText.caption.copyWith(color: p.muted),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: p.muted),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _body(Palette p) {
    final report = _store.report();
    final active = _active(report);
    final previous = AppSettings.instance.previousUnlock;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        const PageTitle(eyebrow: 'Protection overview', title: 'Security'),
        const SizedBox(height: 18),
        Reveal(child: _scoreCard(p, report)),
        const SectionLabel('Password health'),
        Row(
          children: [
            _issueCard(
              p,
              issue: _Issue.weak,
              icon: Icons.warning_amber_rounded,
              color: p.danger,
              label: 'Weak',
              count: report.weak.length,
              selected: active == _Issue.weak,
            ),
            const SizedBox(width: 10),
            _issueCard(
              p,
              issue: _Issue.reused,
              icon: Icons.copy_all_rounded,
              color: p.warning,
              label: 'Reused',
              count: report.reused.length,
              selected: active == _Issue.reused,
            ),
            const SizedBox(width: 10),
            _issueCard(
              p,
              issue: _Issue.old,
              icon: Icons.history_rounded,
              color: p.violet,
              label: 'Old',
              count: report.old.length,
              selected: active == _Issue.old,
            ),
          ],
        ),
        const SizedBox(height: 14),
        _issueList(p, report, active),
        const SectionLabel('Device protection'),
        SettingGroup(
          children: [
            for (final entry in report.checklist)
              SettingTile(
                icon: entry.ok
                    ? Icons.check_circle_rounded
                    : Icons.error_outline_rounded,
                color: entry.ok ? p.success : p.warning,
                title: entry.title,
                subtitle: entry.detail,
                onTap: entry.ok ? null : widget.onOpenSettings,
              ),
          ],
        ),
        const SectionLabel('Tools'),
        SettingGroup(
          children: [
            SettingTile(
              icon: Icons.auto_awesome_rounded,
              color: p.accent,
              title: 'Password generator',
              subtitle: 'Strong random passwords, made on this phone',
              onTap: () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (context) => const GeneratorScreen(),
                  ),
                );
              },
            ),
          ],
        ),
        const SectionLabel('Activity'),
        AppCard(
          child: Row(
            children: [
              IconBadge(icon: Icons.schedule_rounded, color: p.primary, size: 40),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Previous unlock', style: AppText.subtitle),
                    const SizedBox(height: 2),
                    Text(
                      previous == null
                          ? 'This is your first session.'
                          : '${formatDateTime(previous)} (${timeAgo(previous)})',
                      style: AppText.caption.copyWith(color: p.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: Listenable.merge([_store, AppSettings.instance]),
          builder: (context, child) => _body(p),
        ),
      ),
    );
  }
}
