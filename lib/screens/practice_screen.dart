import 'package:flutter/material.dart';

import '../app_nav.dart';
import '../platform_support.dart';
import '../services/beats_profile_service.dart';
import '../services/download_manager.dart';
import '../services/offline_cache_service.dart';
import '../services/practice_controller.dart';
import '../services/service_locator.dart';
import '../ui/brand.dart';
import '../ui/dialogs.dart';
import '../ui/widgets.dart';
import '../widgets/beat_pulse_indicator.dart';
import '../widgets/practice_timer_picker.dart';

const Map<String, String> _tempoLabelText = {
  'beginner': 'Beginner / Slow',
  'practice': 'Practice',
  'performance': 'Kirtan / Performance',
};

const Map<String, String> _instrumentLabels = {
  'mrdanga': 'Mrdanga',
  'kartals': 'Kartals',
  'tanpura': 'Tanpura',
  'full_mix': 'Full mix',
};

class _BrowseData {
  final List<Map<String, dynamic>> talas;
  final List<Map<String, dynamic>> sets;
  final Set<String> favorites;
  final bool isPaid;
  final Map<String, ({int total, int complete, int failed, int stale})> summaries;
  _BrowseData(this.talas, this.sets, this.favorites, this.isPaid, this.summaries);
}

/// Practice tab: browse practice sets by tala (locked ones marked for the
/// free tier), then the player console — beat lights, LOOP / PLAY / TIMER
/// pads, a BPM stepper and slider with beginner-friendly tempo labels, and
/// the instrument mix. Tempo, loop, timer
/// and mix are remembered per practice set. Tracks arrive through the
/// background download (DownloadManager.syncAll); there are no per-track
/// download controls.
class PracticeView extends StatefulWidget {
  const PracticeView({super.key});

  @override
  State<PracticeView> createState() => _PracticeViewState();
}

class _PracticeViewState extends State<PracticeView> {
  final _controller = getIt<PracticeController>();
  final _cache = OfflineCacheService();
  final _downloads = DownloadManager();

  late Future<_BrowseData> _browse;
  Map<String, dynamic>? _current;
  Map<String, dynamic>? _currentTala;
  Set<String> _favorites = {};
  bool _loading = false;
  int _lastRequestId = 0;
  int _downloadedCount = 0;

  @override
  void initState() {
    super.initState();
    _browse = _loadBrowse();
    AppNav.practiceRequest.addListener(_onRequest);
    AppNav.tab.addListener(_onTab);
    _downloads.status.addListener(_onDownloadStatus);
    _onRequest();
  }

  @override
  void dispose() {
    AppNav.practiceRequest.removeListener(_onRequest);
    AppNav.tab.removeListener(_onTab);
    _downloads.status.removeListener(_onDownloadStatus);
    super.dispose();
  }

  /// As background downloads land: refresh the list's download badges, or
  /// — if the open set had nothing playable yet — load it now that it may.
  /// A set that's already playing is left alone.
  void _onDownloadStatus() {
    final complete = _downloads.status.value.complete;
    if (complete == _downloadedCount || !mounted) return;
    _downloadedCount = complete;
    final current = _current;
    if (current == null) {
      setState(() => _browse = _loadBrowse());
    } else if (_controller.stemVolumesNotifier.value.isEmpty && !_loading) {
      _controller.loadPracticeSet(current).catchError((_) {});
    }
  }

  void _onTab() {
    if (AppNav.tab.value == AppNav.practice && _current == null && mounted) {
      setState(() => _browse = _loadBrowse());
    }
  }

  void _onRequest() {
    final req = AppNav.practiceRequest.value;
    if (req == null || req.id == _lastRequestId) return;
    _lastRequestId = req.id;
    _open(req.practiceSet);
  }

  Future<_BrowseData> _loadBrowse() async {
    final profile = await BeatsProfileService().fetchCurrentProfile();
    final talas = await _cache.getCachedTalas();
    final sets = await _cache.getCachedPracticeSets();
    final favorites = await _cache.getCachedFavoriteIds();
    final summaries = offlineSupported ? await _downloads.getSetSummaries() : {};
    _favorites = favorites;
    return _BrowseData(talas, sets, favorites, profile?.isPaid ?? false,
        Map.of(summaries.cast<String, ({int total, int complete, int failed, int stale})>()));
  }

  Future<void> _refresh() async {
    final profile = await BeatsProfileService().fetchCurrentProfile();
    if (profile != null) await _cache.refreshAll(profile.studentId);
    if (mounted) setState(() => _browse = _loadBrowse());
    await _browse;
  }

  Future<void> _open(Map<String, dynamic> set) async {
    setState(() => _loading = true);
    try {
      await _controller.loadPracticeSet(set);
      final talas = await _cache.getCachedTalas();
      final tala = talas.cast<Map<String, dynamic>?>().firstWhere(
            (t) => t?['id'] == set['tala_id'],
            orElse: () => null,
          );
      if (mounted) {
        setState(() {
          _current = set;
          _currentTala = tala;
        });
      }
    } on LockedContentException catch (e) {
      if (mounted) showLockedDialog(context, practiceSetTitle: e.practiceSetTitle);
    } catch (_) {
      if (mounted) showBrandSnack(context, 'Could not load this practice set. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _close() async {
    await _controller.stop();
    if (mounted) {
      setState(() {
        _current = null;
        _browse = _loadBrowse();
      });
    }
  }

  Future<void> _toggleFavorite(String practiceSetId) async {
    final profile = await BeatsProfileService().fetchCurrentProfile();
    if (profile == null) return;
    final makeFavorite = !_favorites.contains(practiceSetId);
    try {
      await _cache.setFavorite(profile.studentId, practiceSetId, makeFavorite);
      setState(() {
        _favorites = makeFavorite
            ? {..._favorites, practiceSetId}
            : _favorites.difference({practiceSetId});
      });
    } catch (_) {
      if (mounted) showBrandSnack(context, 'Could not update the favorite — check your connection.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    return PortalScroll(
      title: 'Practice',
      subtitle: current == null ? 'Choose a practice set' : null,
      onRefresh: current == null ? _refresh : null,
      maxWidth: current == null ? 1100 : 640,
      children: [
        if (_loading) const LinearProgressIndicator(),
        if (current == null)
          _BrowseList(future: _browse, onOpen: _open, onLocked: (s) {
            showLockedDialog(context, practiceSetTitle: s['title'] as String?);
          })
        else
          ..._playerChildren(current),
      ],
    );
  }

  List<Widget> _playerChildren(Map<String, dynamic> set) {
    final isFavorite = _favorites.contains(set['id']);
    return [
      Row(
        children: [
          TextButton.icon(
            onPressed: _close,
            icon: const Icon(Icons.arrow_back, size: 18),
            label: Text('ALL SETS', style: sora(12, 700, spacing: 1.2)),
          ),
          const Spacer(),
          IconButton(
            tooltip: isFavorite ? 'Remove from favorites' : 'Add to favorites',
            icon: Icon(isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                color: isFavorite ? Brand.amber : Brand.textMuted, size: 28),
            onPressed: () => _toggleFavorite(set['id'] as String),
          ),
        ],
      ),
      ValueListenableBuilder<Map<String, double>>(
        valueListenable: _controller.stemVolumesNotifier,
        builder: (context, stems, _) {
          if (stems.isEmpty) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SetHeader(controller: _controller, set: set, tala: _currentTala),
                const SizedBox(height: 16),
                GlassTile(
                  title: offlineSupported ? 'Downloading' : 'No tracks yet',
                  icon: offlineSupported ? Icons.downloading : Icons.music_off_outlined,
                  iconColor: Brand.blue,
                  child: Text(
                    offlineSupported
                        ? 'This practice set is still downloading. It will be ready '
                            'to play here as soon as it finishes.'
                        : 'No tracks are available for this practice set yet.',
                  ),
                ),
              ],
            );
          }
          return _Console(controller: _controller, set: set, tala: _currentTala, stems: stems);
        },
      ),
    ];
  }
}

/// Neon accent per tempo tier, used on set cards and the player header.
Color _tempoColor(Object? tempoLabel) => switch (tempoLabel) {
      'beginner' => Brand.cyan,
      'performance' => Brand.pink,
      _ => Brand.violet,
    };

class _BrowseList extends StatelessWidget {
  final Future<_BrowseData> future;
  final void Function(Map<String, dynamic>) onOpen;
  final void Function(Map<String, dynamic>) onLocked;

  const _BrowseList({required this.future, required this.onOpen, required this.onLocked});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_BrowseData>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return const GlassTile(
            title: 'Could not load practice sets',
            icon: Icons.error_outline,
            iconColor: Brand.red,
            child: Text('Pull down to try again.'),
          );
        }
        final data = snapshot.data!;
        if (data.sets.isEmpty) {
          return const GlassTile(
            title: 'Practice sets',
            icon: Icons.library_music_outlined,
            child: Text('No practice content has been published yet.'),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final tala in data.talas)
              if (data.sets.any((s) => s['tala_id'] == tala['id'])) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 12, top: 4),
                  child: Row(
                    children: [
                      if (tala['image_asset'] != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: Image.asset(
                            'images/${tala['image_asset']}',
                            width: 32,
                            height: 32,
                            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                          ),
                        ),
                      GradientText(tala['name'] as String? ?? '', style: sora(20, 800, spacing: -0.3)),
                      if (tala['beats_count'] != null) ...[
                        const SizedBox(width: 10),
                        Text('${tala['beats_count']} BEATS',
                            style: sora(11, 700, color: Brand.textMuted, spacing: 1.2)),
                      ],
                    ],
                  ),
                ),
                for (final set in data.sets.where((s) => s['tala_id'] == tala['id']))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _SetCard(
                      set: set,
                      locked: isPaidSet(set) && !data.isPaid,
                      summary: data.summaries[set['id']],
                      onTap: () => (isPaidSet(set) && !data.isPaid) ? onLocked(set) : onOpen(set),
                    ),
                  ),
                const SizedBox(height: 12),
              ],
          ],
        );
      },
    );
  }
}

class _SetCard extends StatelessWidget {
  final Map<String, dynamic> set;
  final bool locked;
  final ({int total, int complete, int failed, int stale})? summary;
  final VoidCallback onTap;

  const _SetCard({required this.set, required this.locked, required this.summary, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final accent = locked ? Brand.amber : _tempoColor(set['tempo_label']);
    final badges = <Widget>[
      if (locked) const StatusBadge('Supporters', kind: BadgeKind.amber, icon: Icons.lock_outline),
      if (offlineSupported && s != null && s.total > 0) ...[
        if (s.failed > 0)
          const StatusBadge('Download failed', kind: BadgeKind.red, icon: Icons.error_outline)
        else if (s.complete == s.total)
          const StatusBadge('Downloaded', kind: BadgeKind.green, icon: Icons.check_circle_outline)
        else
          StatusBadge('${s.complete}/${s.total} downloaded', kind: BadgeKind.gray),
      ],
    ];
    final radius = BorderRadius.circular(Brand.cardRadius);

    return Material(
      color: Brand.surface,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: accent.withValues(alpha: 0.35)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        splashColor: accent.withValues(alpha: 0.15),
        highlightColor: accent.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(Brand.radius),
                  border: Border.all(color: accent.withValues(alpha: 0.8), width: 1.5),
                  boxShadow: Brand.glow(accent, 0.5),
                ),
                child: Icon(locked ? Icons.lock_outline : Icons.graphic_eq_rounded, size: 22, color: accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(set['title'] as String? ?? '', style: sora(15, 700, color: Brand.text)),
                    const SizedBox(height: 2),
                    Text(
                      '${_tempoLabelText[set['tempo_label']] ?? ''} · '
                      '${set['bpm_min']}–${set['bpm_max']} BPM',
                      style: nunito(13, 500, color: Brand.textMuted),
                    ),
                    if (badges.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Wrap(spacing: 6, runSpacing: 4, children: badges),
                      ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: accent.withValues(alpha: 0.8)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The player's title card: set name, live BPM, tala and tempo tier, in a
/// neon frame tinted by the tempo tier.
class _SetHeader extends StatelessWidget {
  final PracticeController controller;
  final Map<String, dynamic> set;
  final Map<String, dynamic>? tala;

  const _SetHeader({required this.controller, required this.set, required this.tala});

  @override
  Widget build(BuildContext context) {
    final accent = _tempoColor(set['tempo_label']);
    final details = [
      if (tala?['name'] != null) tala!['name'] as String,
      _tempoLabelText[set['tempo_label']] ?? 'Practice',
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.alphaBlend(accent.withValues(alpha: 0.14), Brand.surface), Brand.surface],
        ),
        borderRadius: BorderRadius.circular(Brand.cardRadius),
        border: Border.all(color: accent.withValues(alpha: 0.85), width: 1.5),
        boxShadow: Brand.glow(accent, 0.6),
      ),
      child: Column(
        children: [
          Icon(Icons.music_note_rounded, color: accent, size: 30),
          const SizedBox(height: 6),
          Text(set['title'] as String? ?? '',
              textAlign: TextAlign.center, style: sora(20, 800, color: Brand.text, spacing: -0.3)),
          const SizedBox(height: 4),
          ValueListenableBuilder<int>(
            valueListenable: controller.currentBpmNotifier,
            builder: (context, bpm, _) => bpm == 0
                ? const SizedBox.shrink()
                : Text('$bpm BPM', style: sora(15, 700, color: accent, spacing: 0.5)),
          ),
          const SizedBox(height: 2),
          Text(details, textAlign: TextAlign.center, style: nunito(13, 600, color: Brand.textMuted)),
        ],
      ),
    );
  }
}

/// The practice console: title card, beat lights, LOOP / PLAY / TIMER pads,
/// the tempo strip and the instrument mixer.
class _Console extends StatelessWidget {
  final PracticeController controller;
  final Map<String, dynamic> set;
  final Map<String, dynamic>? tala;
  final Map<String, double> stems;

  const _Console({required this.controller, required this.set, required this.tala, required this.stems});

  String _fmt(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  void _openTimer(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('PRACTICE TIMER', style: sora(13, 800, color: Brand.pink, spacing: 1.6)),
              const SizedBox(height: 14),
              _TimerSection(controller: controller),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final beats = (tala?['beats_count'] as int?) ?? 4;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SetHeader(controller: controller, set: set, tala: tala),
        const SizedBox(height: 22),
        ValueListenableBuilder<bool>(
          valueListenable: controller.isPlayingNotifier,
          builder: (context, playing, _) => ValueListenableBuilder<int>(
            valueListenable: controller.currentBpmNotifier,
            builder: (context, bpm, _) => BeatPulseIndicator(bpm: bpm, beatsCount: beats, isPlaying: playing),
          ),
        ),
        const SizedBox(height: 22),
        SizedBox(
          height: 132,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ValueListenableBuilder<bool>(
                  valueListenable: controller.loopEnabledNotifier,
                  builder: (context, loop, _) => NeonPad(
                    label: 'Loop',
                    semanticLabel: loop ? 'Loop is on' : 'Loop is off',
                    icon: loop ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                    color: Brand.violet,
                    active: loop,
                    onTap: controller.toggleLoop,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ValueListenableBuilder<bool>(
                  valueListenable: controller.isPlayingNotifier,
                  builder: (context, playing, _) => NeonPad(
                    label: playing ? 'Pause' : 'Play',
                    icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    iconSize: 46,
                    color: Brand.cyan,
                    active: playing,
                    breathing: playing,
                    onTap: playing ? controller.pause : controller.play,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ValueListenableBuilder<int?>(
                  valueListenable: controller.timerMinutesNotifier,
                  builder: (context, minutes, _) => ValueListenableBuilder<Duration?>(
                    valueListenable: controller.timerRemainingNotifier,
                    builder: (context, remaining, _) => NeonPad(
                      label: 'Timer',
                      semanticLabel: 'Practice timer',
                      icon: minutes == null ? Icons.timer_outlined : null,
                      value: minutes == null ? null : (remaining == null ? '${minutes}m' : _fmt(remaining)),
                      color: Brand.pink,
                      active: minutes != null,
                      onTap: () => _openTimer(context),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _TempoStrip(controller: controller, set: set),
        const SizedBox(height: 16),
        _MixerStrip(controller: controller, stems: stems),
      ],
    );
  }
}

/// A console strip: dark glass panel with a small uppercase label.
class _Strip extends StatelessWidget {
  final String label;
  final Widget? trailing;
  final Widget child;
  const _Strip({required this.label, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: Brand.surface.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(Brand.cardRadius),
        border: Border.all(color: Brand.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(label, style: sora(11, 800, color: Brand.textMuted, spacing: 1.6)),
              const Spacer(),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

/// BPM − / value / + stepper (tap ±1, long-press ±5) over the tempo slider.
class _TempoStrip extends StatelessWidget {
  final PracticeController controller;
  final Map<String, dynamic> set;
  const _TempoStrip({required this.controller, required this.set});

  @override
  Widget build(BuildContext context) {
    final minBpm = (set['bpm_min'] as num?)?.toDouble() ?? 60;
    final maxBpm = (set['bpm_max'] as num?)?.toDouble() ?? 120;
    final adjustable = maxBpm > minBpm;

    return ValueListenableBuilder<int>(
      valueListenable: controller.currentBpmNotifier,
      builder: (context, bpm, _) {
        void step(int delta) =>
            controller.setBpm((bpm + delta).clamp(minBpm.round(), maxBpm.round()));
        return _Strip(
          label: 'TEMPO',
          trailing: StatusBadge(_tempoLabelText[set['tempo_label']] ?? 'Practice', kind: BadgeKind.purple),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _StepButton(
                    icon: Icons.remove_rounded,
                    tooltip: 'Slower',
                    onTap: adjustable && bpm > minBpm ? () => step(-1) : null,
                    onLongPress: adjustable && bpm > minBpm ? () => step(-5) : null,
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text('$bpm', style: sora(40, 800, color: Brand.text, height: 1.1)),
                        Text('BPM', style: sora(11, 800, color: Brand.cyan, spacing: 2)),
                      ],
                    ),
                  ),
                  _StepButton(
                    icon: Icons.add_rounded,
                    tooltip: 'Faster',
                    onTap: adjustable && bpm < maxBpm ? () => step(1) : null,
                    onLongPress: adjustable && bpm < maxBpm ? () => step(5) : null,
                  ),
                ],
              ),
              if (adjustable) ...[
                const SizedBox(height: 4),
                Slider(
                  value: bpm.toDouble().clamp(minBpm, maxBpm),
                  min: minBpm,
                  max: maxBpm,
                  divisions: (maxBpm - minBpm) <= 200 ? (maxBpm - minBpm).round() : null,
                  label: '$bpm BPM',
                  onChanged: (v) => controller.setBpm(v.round()),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Text('${minBpm.round()}', style: sora(11, 600, color: Brand.textFaint)),
                      const Spacer(),
                      Text('${maxBpm.round()}', style: sora(11, 600, color: Brand.textFaint)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  const _StepButton({required this.icon, required this.tooltip, this.onTap, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Brand.surfaceRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Brand.radius),
          side: BorderSide(color: enabled ? Brand.borderStrong : Brand.border),
        ),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(Brand.radius),
          child: SizedBox(
            width: 56,
            height: 56,
            child: Icon(icon, size: 28, color: enabled ? Brand.text : Brand.textFaint),
          ),
        ),
      ),
    );
  }
}

class _MixerStrip extends StatelessWidget {
  final PracticeController controller;
  final Map<String, double> stems;
  const _MixerStrip({required this.controller, required this.stems});

  @override
  Widget build(BuildContext context) {
    return _Strip(
      label: 'MIX',
      child: Column(
        children: [
          for (final entry in stems.entries)
            Row(
              children: [
                SizedBox(
                  width: 84,
                  child: Text((_instrumentLabels[entry.key] ?? entry.key).toUpperCase(),
                      overflow: TextOverflow.ellipsis,
                      style: sora(11, 700, color: Brand.textSecondary, spacing: 1)),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(activeTrackColor: Brand.violet),
                    child: Slider(
                      value: entry.value,
                      semanticFormatterCallback: (v) => '${(v * 100).round()} percent',
                      onChanged: (v) => controller.setStemVolume(entry.key, v),
                    ),
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: Text('${(entry.value * 100).round()}%',
                      textAlign: TextAlign.right, style: sora(12, 700, color: Brand.text)),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _TimerSection extends StatelessWidget {
  final PracticeController controller;
  const _TimerSection({required this.controller});

  String _fmt(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int?>(
      valueListenable: controller.timerMinutesNotifier,
      builder: (context, minutes, _) => ValueListenableBuilder<Duration?>(
        valueListenable: controller.timerRemainingNotifier,
        builder: (context, remaining, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PracticeTimerPicker(
              selectedMinutes: minutes,
              onSelected: controller.selectTimer,
              onCancel: controller.cancelTimer,
            ),
            const SizedBox(height: 12),
            Text(
              minutes == null
                  ? 'No timer set.'
                  : remaining == null
                      ? 'Timer set for $minutes min — it counts down while audio plays.'
                      : '${_fmt(remaining)} remaining',
              style: nunito(13, 600, color: Brand.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
