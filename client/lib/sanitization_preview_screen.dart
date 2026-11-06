import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'media_vault_service.dart';
import 'metadata_analysis.dart';
import 'ui/score_ring.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';
import 'vault_store.dart';

/// What happened on the preview screen.
enum PreviewAction { saved, skipped, failed, stopAll }

class PreviewResult {
  final PreviewAction action;

  /// Set when [action] is [PreviewAction.saved].
  final ImportedPhoto? photo;

  /// Set when [action] is [PreviewAction.failed].
  final String? error;

  /// True when the user chose "clean all the remaining photos" without
  /// looking at each one.
  final bool cleanRest;

  const PreviewResult(
    this.action, {
    this.photo,
    this.error,
    this.cleanRest = false,
  });
}

/// Cleans one photo, saves its encrypted files and adds the record to the
/// vault. If the record cannot be saved, the files are removed again.
/// Throws [MediaVaultException] with a sentence the user can read.
Future<ImportedPhoto> importIntoVault(
  MediaVaultService media,
  Uint8List original, {
  MetadataAnalysis? before,
}) async {
  final photo = await media.importPhoto(original, before: before);
  try {
    await VaultStore.instance.add(photo.item);
  } catch (_) {
    await media.deletePhotoFiles(photo.item);
    throw const MediaVaultException(
      'The vault could not be saved. Please try again.',
    );
  }
  return photo;
}

enum _Phase { review, working, done, failed }

/// Shows what a photo gives away BEFORE it is saved: where it was taken, when,
/// with which phone, and who it belongs to. Then it cleans the photo and shows
/// the same check on the saved copy.
class SanitizationPreviewScreen extends StatefulWidget {
  /// The original photo, exactly as the gallery or camera gave it.
  final Uint8List bytes;

  /// The hidden data found in [bytes].
  final MetadataAnalysis before;

  final MediaVaultService media;

  /// This photo's place in the batch, counting from 1.
  final int position;
  final int total;

  const SanitizationPreviewScreen({
    super.key,
    required this.bytes,
    required this.before,
    required this.media,
    required this.position,
    required this.total,
  });

  @override
  State<SanitizationPreviewScreen> createState() =>
      _SanitizationPreviewScreenState();
}

class _SanitizationPreviewScreenState extends State<SanitizationPreviewScreen> {
  _Phase _phase = _Phase.review;
  bool _showAll = false;
  bool _cleanRest = false;
  ImportedPhoto? _saved;
  String? _error;

  int get _remaining => widget.total - widget.position;

  @override
  void dispose() {
    // Let go of the decoded original. Best effort, like in the viewer.
    imageCache.clear();
    imageCache.clearLiveImages();
    super.dispose();
  }

  // ---------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------

  Future<void> _clean({required bool rest}) async {
    if (_phase == _Phase.working) return;
    setState(() {
      _phase = _Phase.working;
      _error = null;
    });
    try {
      final photo = await importIntoVault(
        widget.media,
        widget.bytes,
        before: widget.before,
      );
      if (!mounted) return;
      setState(() {
        _saved = photo;
        _cleanRest = rest;
        _phase = _Phase.done;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is MediaVaultException
            ? error.message
            : 'This photo could not be cleaned, so it was not saved.';
        _phase = _Phase.failed;
      });
    }
  }

  void _finish() {
    Navigator.of(context).pop<PreviewResult>(
      PreviewResult(PreviewAction.saved, photo: _saved, cleanRest: _cleanRest),
    );
  }

  void _skip() {
    Navigator.of(context).pop<PreviewResult>(
      const PreviewResult(PreviewAction.skipped),
    );
  }

  void _fail() {
    Navigator.of(context).pop<PreviewResult>(
      PreviewResult(PreviewAction.failed, error: _error),
    );
  }

  void _stop() {
    Navigator.of(context).pop<PreviewResult>(
      const PreviewResult(PreviewAction.stopAll),
    );
  }

  /// The back button and the close button.
  void _leave() {
    if (_phase == _Phase.working) return;
    if (_phase == _Phase.done) {
      _finish();
    } else if (_phase == _Phase.failed) {
      _fail();
    } else if (widget.total > 1) {
      _stop();
    } else {
      _skip();
    }
  }

  // ---------------------------------------------------------------
  // Pieces
  // ---------------------------------------------------------------

  static IconData _iconFor(MetaCategory category) {
    return switch (category) {
      MetaCategory.location => Icons.location_on_rounded,
      MetaCategory.owner => Icons.badge_rounded,
      MetaCategory.time => Icons.schedule_rounded,
      MetaCategory.device => Icons.smartphone_rounded,
      MetaCategory.thumbnail => Icons.photo_size_select_small_rounded,
      MetaCategory.other => Icons.more_horiz_rounded,
      MetaCategory.settings => Icons.tune_rounded,
      MetaCategory.image => Icons.image_rounded,
    };
  }

  static Color _riskColor(Palette p, ExposureLevel level) {
    return switch (level) {
      ExposureLevel.high => p.danger,
      ExposureLevel.medium => p.warning,
      ExposureLevel.low => p.accent,
      ExposureLevel.none => p.success,
    };
  }

  static String _riskWord(ExposureLevel level) {
    return switch (level) {
      ExposureLevel.high => 'High risk',
      ExposureLevel.medium => 'Medium',
      ExposureLevel.low => 'Low',
      ExposureLevel.none => 'Harmless',
    };
  }

  Widget _photo(Palette p) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: 210,
        width: double.infinity,
        child: Image.memory(
          widget.bytes,
          fit: BoxFit.cover,
          cacheWidth: 900,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) => ColoredBox(
            color: p.surfaceAlt,
            child: Center(
              child: Icon(Icons.image_not_supported_rounded, color: p.muted),
            ),
          ),
        ),
      ),
    );
  }

  Widget _beforeCard(Palette p) {
    final before = widget.before;
    final level = before.level;
    final color = _riskColor(p, level);

    final title = switch (level) {
      ExposureLevel.none => 'No hidden data found',
      ExposureLevel.low => 'Low exposure',
      ExposureLevel.medium => 'Medium exposure',
      ExposureLevel.high => 'High exposure',
    };
    final text = before.hiddenFieldCount == 0
        ? 'This file carries no location, owner or date. It is still '
            'rebuilt, encrypted and checked.'
        : '${before.hiddenFieldCount} hidden '
            '${before.hiddenFieldCount == 1 ? 'field' : 'fields'} found. '
            'Cleaning removes all of them before the photo is encrypted.';

    return AppCard(
      child: Row(
        children: [
          ScoreRing(score: before.privacyScore, size: 96, strokeWidth: 9),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppText.subtitle.copyWith(color: color),
                ),
                const SizedBox(height: 4),
                Text(
                  'Privacy score ${before.privacyScore} of 100 as it is now',
                  style: AppText.caption.copyWith(
                    color: p.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(text, style: AppText.caption.copyWith(color: p.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _findings(Palette p) {
    final before = widget.before;
    final present = before.categoriesPresent;
    final shown = [
      for (final category in present)
        if (_showAll || MetadataAnalysis.isSensitive(category)) category,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('What this photo gives away'),
        if (present.isEmpty)
          Text(
            'No hidden fields were found.',
            style: AppText.body.copyWith(color: p.muted),
          )
        else if (shown.isEmpty)
          Text(
            'Only harmless technical fields were found.',
            style: AppText.body.copyWith(color: p.muted),
          ),
        for (final category in shown)
          _CategoryCard(
            analysis: before,
            category: category,
            expanded: _showAll,
            riskColor: _riskColor(p, MetadataAnalysis.riskOf(category)),
            riskWord: _riskWord(MetadataAnalysis.riskOf(category)),
            icon: _iconFor(category),
          ),
        if (present.isNotEmpty)
          Center(
            child: SoftButton(
              label: _showAll
                  ? 'Show less'
                  : 'Show every field (${before.hiddenFieldCount})',
              icon: _showAll
                  ? Icons.expand_less_rounded
                  : Icons.expand_more_rounded,
              onPressed: () => setState(() => _showAll = !_showAll),
            ),
          ),
        if (!before.structureChecked) ...[
          const SizedBox(height: 14),
          Text(
            'Some parts of this file type cannot be listed here. That does '
            'not matter for safety: the saved photo is rebuilt from its '
            'pixels, and the result is checked again.',
            style: AppText.caption.copyWith(color: p.muted),
          ),
        ],
      ],
    );
  }

  Widget _afterCard(Palette p) {
    final saved = _saved!;
    final before = saved.before;
    final after = saved.after;

    Widget ring(String label, int score) {
      return Column(
        children: [
          ScoreRing(score: score, size: 88, strokeWidth: 8),
          const SizedBox(height: 8),
          Text(label, style: AppText.caption.copyWith(color: p.muted)),
        ],
      );
    }

    final removed = [
      for (final category in before.categoriesPresent)
        if (before.countIn(category) > after.countIn(category))
          '${MetadataAnalysis.titleOf(category)} · '
              '${before.countIn(category) - after.countIn(category)}',
    ];

    final left = after.hiddenFieldCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ring('Before', before.privacyScore),
              Icon(Icons.arrow_forward_rounded, color: p.muted),
              ring('After', after.privacyScore),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _statusRow(
          p,
          Icons.verified_rounded,
          p.success,
          left == 0
              ? 'The saved copy was read back: no hidden data found.'
              : 'The saved copy was read back: nothing that identifies you or '
                  'the place is left. $left harmless technical '
                  '${left == 1 ? 'field remains' : 'fields remain'}.',
        ),
        _statusRow(
          p,
          Icons.cleaning_services_rounded,
          p.accent,
          before.hiddenFieldCount == 0
              ? 'This photo had no hidden data to remove.'
              : '${before.hiddenFieldCount} hidden '
                  '${before.hiddenFieldCount == 1 ? 'field' : 'fields'} removed.',
        ),
        if (removed.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 46, bottom: 14),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final text in removed) _SmallTag(text: text)],
            ),
          ),
        _statusRow(
          p,
          Icons.lock_rounded,
          p.primary,
          'Encrypted with its own key and added to your vault.',
        ),
        const SizedBox(height: 4),
        const InfoBanner(
          icon: Icons.info_outline_rounded,
          text: 'Your original is still in the gallery. Delete it there if '
              'you do not want it to stay. KeyMaster cannot do that for you.',
        ),
      ],
    );
  }

  Widget _statusRow(Palette p, IconData icon, Color color, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(icon: icon, color: color, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(text, style: AppText.body),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomBar() {
    final Widget content;
    if (_phase == _Phase.working) {
      content = const GradientButton(
        label: 'Cleaning and encrypting...',
        onPressed: null,
        loading: true,
      );
    } else if (_phase == _Phase.done) {
      content = GradientButton(
        label: _remaining <= 0
            ? 'Done'
            : (_cleanRest ? 'Continue' : 'Next photo'),
        icon: _remaining <= 0 ? Icons.check_rounded : Icons.arrow_forward_rounded,
        onPressed: _finish,
      );
    } else if (_phase == _Phase.failed) {
      content = GradientButton(
        label: _remaining > 0 ? 'Next photo' : 'Close',
        onPressed: _fail,
      );
    } else {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GradientButton(
            label: 'Clean and save to vault',
            icon: Icons.cleaning_services_rounded,
            onPressed: () => _clean(rest: false),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: SoftButton(
                  label: 'Skip this photo',
                  icon: Icons.skip_next_rounded,
                  color: Palette.of(context).muted,
                  onPressed: _skip,
                ),
              ),
              if (_remaining > 0) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: SoftButton(
                    label: 'Clean all $_remaining more',
                    icon: Icons.done_all_rounded,
                    onPressed: () => _clean(rest: true),
                  ),
                ),
              ],
            ],
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
      child: content,
    );
  }

  // ---------------------------------------------------------------
  // Screen
  // ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);

    final String title;
    final String subtitle;
    if (_phase == _Phase.done) {
      title = 'Photo secured';
      subtitle = widget.total > 1
          ? 'Photo ${widget.position} of ${widget.total}'
          : 'Saved to your vault';
    } else if (_phase == _Phase.failed) {
      title = 'Not saved';
      subtitle = widget.total > 1
          ? 'Photo ${widget.position} of ${widget.total}'
          : 'Nothing was added to the vault';
    } else {
      title = 'Privacy preview';
      subtitle = widget.total > 1
          ? 'Photo ${widget.position} of ${widget.total}'
          : 'Before this photo is saved';
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Row(
                  children: [
                    RoundIconButton(
                      icon: Icons.close_rounded,
                      tooltip: widget.total > 1 ? 'Stop importing' : 'Cancel',
                      onPressed: _phase == _Phase.working ? null : _leave,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: AppText.title),
                          Text(
                            subtitle,
                            style: AppText.caption.copyWith(color: p.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  children: [
                    if (_phase == _Phase.done)
                      _afterCard(p)
                    else ...[
                      if (_phase == _Phase.failed && _error != null) ...[
                        InfoBanner(
                          icon: Icons.error_outline_rounded,
                          color: p.danger,
                          text: _error!,
                        ),
                        const SizedBox(height: 14),
                      ],
                      _photo(p),
                      const SizedBox(height: 14),
                      _beforeCard(p),
                      _findings(p),
                    ],
                  ],
                ),
              ),
              _bottomBar(),
            ],
          ),
        ),
      ),
    );
  }
}

/// One kind of hidden data: icon, name, risk, a one-line summary and, when
/// expanded, every field with its value.
class _CategoryCard extends StatelessWidget {
  final MetadataAnalysis analysis;
  final MetaCategory category;
  final bool expanded;
  final Color riskColor;
  final String riskWord;
  final IconData icon;

  const _CategoryCard({
    required this.analysis,
    required this.category,
    required this.expanded,
    required this.riskColor,
    required this.riskWord,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final count = analysis.countIn(category);
    final summary = analysis.summaryFor(category);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconBadge(icon: icon, color: riskColor, size: 38),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    MetadataAnalysis.titleOf(category),
                    style: AppText.subtitle.copyWith(fontSize: 15.5),
                  ),
                ),
                _SmallTag(text: riskWord, color: riskColor),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              summary,
              style: AppText.body.copyWith(
                fontSize: 14,
                fontWeight: category == MetaCategory.location
                    ? FontWeight.w700
                    : FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              count == 1 ? '1 field' : '$count fields',
              style: AppText.caption.copyWith(color: p.muted),
            ),
            if (expanded) ...[
              const SizedBox(height: 10),
              Divider(height: 1, thickness: 1, color: p.border),
              const SizedBox(height: 10),
              for (final finding in analysis.findingsIn(category))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 4,
                        child: Text(
                          finding.label,
                          style: AppText.caption.copyWith(color: p.muted),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 5,
                        child: Text(
                          finding.value.isEmpty ? '-' : finding.value,
                          style: AppText.caption.copyWith(color: p.text),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A small rounded label.
class _SmallTag extends StatelessWidget {
  final String text;
  final Color? color;

  const _SmallTag({required this.text, this.color});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final tint = color ?? p.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: tint.withAlpha(30),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tint.withAlpha(80)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: tint,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
