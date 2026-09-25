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
/// free tier), then the player — tempo with beginner-friendly labels, a beat
/// indicator, loop, instrument mix, practice timer, and per-track
/// downloads. Tempo, loop, timer and mix are remembered per practice set.
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
  int _trackRefresh = 0;

  @override
  void initState() {
    super.initState();
    _browse = _loadBrowse();
    AppNav.practiceRequest.addListener(_onRequest);
    AppNav.tab.addListener(_onTab);
    _onRequest();
  }

  @override
  void dispose() {
    AppNav.practiceRequest.removeListener(_onRequest);
    AppNav.tab.removeListener(_onTab);
    super.dispose();
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
      children: [
        if (_loading) const LinearProgressIndicator(color: Brand.orange),
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
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _close,
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          label: Text('All practice sets', style: nunito(14, 600, color: Colors.white)),
        ),
      ),
      ValueListenableBuilder<Map<String, double>>(
        valueListenable: _controller.stemVolumesNotifier,
        builder: (context, stems, _) {
          final hasAudio = stems.isNotEmpty;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GlassTile(
                title: set['title'] as String? ?? '',
                icon: Icons.music_note,
                iconColor: Brand.purple,
                child: hasAudio
                    ? _PlayerControls(
                        controller: _controller,
                        set: set,
                        tala: _currentTala,
                        isFavorite: isFavorite,
                        onToggleFavorite: () => _toggleFavorite(set['id'] as String),
                      )
                    : Text(
                        offlineSupported
                            ? 'Download this practice set below to play it, on or offline.'
                            : 'No tracks are available for this practice set yet.',
                      ),
              ),
              if (hasAudio) ...[
                const SizedBox(height: 16),
                PortalCard(
                  header: 'Instrument mix',
                  child: Column(
                    children: [
                      for (final entry in stems.entries)
                        Row(
                          children: [
                            SizedBox(
                              width: 88,
                              child: Text(_instrumentLabels[entry.key] ?? entry.key,
                                  style: nunito(14, 600, color: Brand.gray700)),
                            ),
                            Expanded(
                              child: Slider(
                                value: entry.value,
                                semanticFormatterCallback: (v) => '${(v * 100).round()} percent',
                                onChanged: (v) => _controller.setStemVolume(entry.key, v),
                              ),
                            ),
                            SizedBox(
                              width: 40,
                              child: Text('${(entry.value * 100).round()}%',
                                  textAlign: TextAlign.right,
                                  style: nunito(13, 500, color: Brand.gray600)),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                PortalCard(header: 'Practice timer', child: _TimerSection(controller: _controller)),
              ],
              if (offlineSupported) ...[
                const SizedBox(height: 16),
                _DownloadsPanel(
                  key: ValueKey('${set['id']}-$_trackRefresh'),
                  practiceSetId: set['id'] as String,
                  onChanged: () async {
                    await _controller.loadPracticeSet(set);
                    if (mounted) setState(() => _trackRefresh++);
                  },
                ),
              ],
            ],
          );
        },
      ),
    ];
  }
}

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
            child: Center(child: CircularProgressIndicator(color: Brand.orange)),
          );
        }
        if (snapshot.hasError) {
          return const GlassTile(
            title: 'Could not load practice sets',
            icon: Icons.error_outline,
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
                  padding: const EdgeInsets.only(bottom: 8, top: 4),
                  child: Row(
                    children: [
                      if (tala['image_asset'] != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: Image.asset(
                            'images/${tala['image_asset']}',
                            width: 36,
                            height: 36,
                            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                          ),
                        ),
                      Text(tala['name'] as String? ?? '',
                          style: nunito(20, 700, color: Colors.white)),
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
                const SizedBox(height: 8),
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
    final badges = <Widget>[
      if (locked) const StatusBadge('Supporters', kind: BadgeKind.amber, icon: Icons.lock_outline),
      if (offlineSupported && s != null && s.total > 0) ...[
        if (s.failed > 0)
          const StatusBadge('Download failed', kind: BadgeKind.red, icon: Icons.error_outline)
        else if (s.stale > 0)
          const StatusBadge('Update available', kind: BadgeKind.amber, icon: Icons.update)
        else if (s.complete == s.total)
          const StatusBadge('Downloaded', kind: BadgeKind.green, icon: Icons.check_circle_outline)
        else
          StatusBadge('${s.complete}/${s.total} downloaded', kind: BadgeKind.gray),
      ],
    ];

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(Brand.radius),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Brand.radius),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(color: Brand.purple, shape: BoxShape.circle),
                child: Icon(locked ? Icons.lock_outline : Icons.music_note,
                    size: 20, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(set['title'] as String? ?? '',
                        style: nunito(16, 600, color: Brand.gray900)),
                    Text(
                      '${_tempoLabelText[set['tempo_label']] ?? ''} · '
                      '${set['bpm_min']}–${set['bpm_max']} BPM',
                      style: nunito(13, 400, color: Brand.gray600),
                    ),
                    if (badges.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Wrap(spacing: 6, runSpacing: 4, children: badges),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Brand.gray400),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayerControls extends StatelessWidget {
  final PracticeController controller;
  final Map<String, dynamic> set;
  final Map<String, dynamic>? tala;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;

  const _PlayerControls({
    required this.controller,
    required this.set,
    required this.tala,
    required this.isFavorite,
    required this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context) {
    final minBpm = (set['bpm_min'] as num?)?.toDouble() ?? 60;
    final maxBpm = (set['bpm_max'] as num?)?.toDouble() ?? 120;
    final beats = (tala?['beats_count'] as int?) ?? 4;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              tooltip: isFavorite ? 'Remove from favorites' : 'Add to favorites',
              icon: Icon(isFavorite ? Icons.star : Icons.star_border,
                  color: isFavorite ? Colors.amber : Colors.white),
              onPressed: onToggleFavorite,
            ),
          ],
        ),
        ValueListenableBuilder<bool>(
          valueListenable: controller.isPlayingNotifier,
          builder: (context, playing, _) => ValueListenableBuilder<int>(
            valueListenable: controller.currentBpmNotifier,
            builder: (context, bpm, _) => Column(
              children: [
                BeatPulseIndicator(bpm: bpm, beatsCount: beats, isPlaying: playing),
                const SizedBox(height: 8),
                Text('$bpm BPM', style: nunito(36, 700, color: Colors.white)),
                const SizedBox(height: 4),
                StatusBadge(_tempoLabelText[set['tempo_label']] ?? 'Practice', kind: BadgeKind.purple),
                if (maxBpm > minBpm)
                  Slider(
                    value: bpm.toDouble().clamp(minBpm, maxBpm),
                    min: minBpm,
                    max: maxBpm,
                    divisions: (maxBpm - minBpm) <= 200 ? (maxBpm - minBpm).round() : null,
                    label: '$bpm BPM',
                    onChanged: (v) => controller.setBpm(v.round()),
                  ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ValueListenableBuilder<bool>(
                      valueListenable: controller.loopEnabledNotifier,
                      builder: (context, loop, _) => Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            iconSize: 30,
                            tooltip: loop ? 'Loop is on' : 'Loop is off',
                            icon: Icon(loop ? Icons.repeat_one : Icons.repeat,
                                color: loop ? Brand.orangeBright : Colors.white70),
                            onPressed: controller.toggleLoop,
                          ),
                          Text(loop ? 'Loop on' : 'Loop off',
                              style: nunito(12, 600, color: Colors.white)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 28),
                    Semantics(
                      button: true,
                      label: playing ? 'Pause' : 'Play',
                      child: GestureDetector(
                        onTap: playing ? controller.pause : controller.play,
                        child: Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: Brand.primaryGradient,
                            boxShadow: Brand.cardShadow,
                          ),
                          child: Icon(playing ? Icons.pause : Icons.play_arrow,
                              size: 42, color: Colors.white),
                        ),
                      ),
                    ),
                    const SizedBox(width: 28),
                    const SizedBox(width: 48),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
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
            const SizedBox(height: 10),
            Text(
              minutes == null
                  ? 'No timer set.'
                  : remaining == null
                      ? 'Timer set for $minutes min — it counts down while audio plays.'
                      : '${_fmt(remaining)} remaining',
              style: nunito(13, 500, color: Brand.gray600),
            ),
          ],
        ),
      ),
    );
  }
}

/// Per-track download management for a practice set: status, progress,
/// retry, update (when a track changed on the server) and download-all.
class _DownloadsPanel extends StatefulWidget {
  final String practiceSetId;
  final Future<void> Function() onChanged;

  const _DownloadsPanel({super.key, required this.practiceSetId, required this.onChanged});

  @override
  State<_DownloadsPanel> createState() => _DownloadsPanelState();
}

class _DownloadsPanelState extends State<_DownloadsPanel> {
  final _downloads = DownloadManager();
  final _cache = OfflineCacheService();
  late Future<List<Map<String, dynamic>>> _tracks;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _tracks = _cache.getCachedTracks(widget.practiceSetId);
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _tracks = _cache.getCachedTracks(widget.practiceSetId);
        });
      }
    }
    await widget.onChanged();
  }

  Future<void> _downloadAll() => _run(() async {
        final failed = await _downloads.downloadPracticeSet(widget.practiceSetId);
        if (failed > 0 && mounted) {
          showBrandSnack(context, '$failed track${failed == 1 ? '' : 's'} could not be downloaded.');
        }
      });

  Future<void> _retry(String id) => _run(() => _downloads.downloadTrack(id, userInitiated: true));

  Future<void> _update(String id) => _run(() async {
        await _downloads.deleteDownload(id);
        await _downloads.downloadTrack(id, userInitiated: true);
      });

  Future<void> _delete(String id) => _run(() => _downloads.deleteDownload(id));

  @override
  Widget build(BuildContext context) {
    return PortalCard(
      header: 'Downloads',
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _tracks,
        builder: (context, snapshot) {
          final tracks = snapshot.data;
          if (tracks == null) return const Center(child: CircularProgressIndicator());
          if (tracks.isEmpty) return const Text('This practice set has no tracks yet.');

          final allDone = tracks.every(
              (t) => t['download_status'] == 'complete' && !DownloadManager.isStale(t));
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ValueListenableBuilder<Map<String, double>>(
                valueListenable: _downloads.progress,
                builder: (context, progress, _) => Column(
                  children: [
                    for (final t in tracks) _trackRow(t, progress[t['id']]),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              if (!allDone)
                GradientButton(
                  label: 'Download all',
                  icon: Icons.download,
                  loading: _busy,
                  onPressed: _busy ? null : _downloadAll,
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _trackRow(Map<String, dynamic> t, double? progress) {
    final id = t['id'] as String;
    final status = t['download_status'] as String? ?? 'not_downloaded';
    final stale = DownloadManager.isStale(t);

    Widget trailing;
    if (progress != null || status == 'downloading') {
      trailing = SizedBox(
        width: 120,
        child: Row(
          children: [
            Expanded(child: LinearProgressIndicator(value: progress)),
            const SizedBox(width: 8),
            Text('${((progress ?? 0) * 100).round()}%', style: nunito(12, 600)),
          ],
        ),
      );
    } else if (status == 'failed') {
      trailing = Row(mainAxisSize: MainAxisSize.min, children: [
        const StatusBadge('Failed', kind: BadgeKind.red, icon: Icons.error_outline),
        TextButton(onPressed: _busy ? null : () => _retry(id), child: const Text('Retry')),
      ]);
    } else if (stale) {
      trailing = Row(mainAxisSize: MainAxisSize.min, children: [
        const StatusBadge('Update available', kind: BadgeKind.amber, icon: Icons.update),
        TextButton(onPressed: _busy ? null : () => _update(id), child: const Text('Update')),
      ]);
    } else if (status == 'complete') {
      trailing = Row(mainAxisSize: MainAxisSize.min, children: [
        const StatusBadge('Downloaded', kind: BadgeKind.green, icon: Icons.check_circle_outline),
        IconButton(
          tooltip: 'Remove download',
          icon: const Icon(Icons.delete_outline, color: Brand.error),
          onPressed: _busy ? null : () => _delete(id),
        ),
      ]);
    } else {
      trailing = TextButton(
          onPressed: _busy ? null : () => _retry(id), child: const Text('Download'));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t['title'] as String? ?? '', style: nunito(14, 600, color: Brand.gray900)),
                Text(_instrumentLabels[t['instrument']] ?? '${t['instrument']}',
                    style: nunito(12, 400, color: Brand.gray500)),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}
