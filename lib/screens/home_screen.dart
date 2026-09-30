import 'package:flutter/material.dart';

import '../app_nav.dart';
import '../platform_support.dart';
import '../services/beats_profile_service.dart';
import '../services/connectivity_service.dart';
import '../services/download_manager.dart';
import '../services/offline_cache_service.dart';
import '../services/practice_controller.dart' show isPaidSet;
import '../services/practice_settings_service.dart';
import '../ui/brand.dart';
import '../ui/dialogs.dart';
import '../ui/widgets.dart';

/// Home tab: Start Practice, Continue Practice (restores the last set with
/// its saved tempo/loop/timer/mix), recent and favourite sets, progress of
/// the background track download (with a retry if tracks failed), and
/// offline status. Reads through OfflineCacheService, so on native it renders
/// instantly from the saved catalog and works offline.
class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  late Future<_HomeData> _future;
  final _downloads = DownloadManager();
  bool _syncRunning = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
    // Reload whenever the user comes back to this tab, and when a
    // background download pass starts or ends (on first launch the catalog
    // arrives just before the first pass starts).
    AppNav.tab.addListener(_onTabChanged);
    _downloads.status.addListener(_onDownloadStatus);
  }

  @override
  void dispose() {
    AppNav.tab.removeListener(_onTabChanged);
    _downloads.status.removeListener(_onDownloadStatus);
    super.dispose();
  }

  void _onTabChanged() {
    if (AppNav.tab.value == AppNav.home && mounted) setState(() => _future = _load());
  }

  void _onDownloadStatus() {
    final running = _downloads.status.value.running;
    if (running == _syncRunning) return;
    _syncRunning = running;
    if (mounted) setState(() => _future = _load());
  }

  Future<_HomeData> _load() async {
    final cache = OfflineCacheService();
    final profile = await BeatsProfileService().fetchCurrentProfile();
    final sets = await cache.getCachedPracticeSets();
    final favoriteIds = await cache.getCachedFavoriteIds();
    final history = await cache.getCachedPracticeHistory(limit: 20);
    final lastId = await PracticeSettingsService.instance.lastPracticeSetId();

    Map<String, dynamic>? byId(String? id) =>
        id == null ? null : sets.cast<Map<String, dynamic>?>().firstWhere((s) => s?['id'] == id, orElse: () => null);

    final continueSet = byId(lastId);
    final continueSettings = lastId == null ? null : await PracticeSettingsService.instance.load(lastId);

    final recentIds = <String>[];
    for (final s in history) {
      final id = s['practice_set_id'] as String;
      if (!recentIds.contains(id) && id != lastId) recentIds.add(id);
      if (recentIds.length == 3) break;
    }

    return _HomeData(
      name: profile?.displayName ?? 'there',
      isPaid: profile?.isPaid ?? false,
      continueSet: continueSet,
      continueSettings: continueSettings,
      recent: recentIds.map(byId).whereType<Map<String, dynamic>>().toList(),
      favorites: sets.where((s) => favoriteIds.contains(s['id'])).toList(),
      catalogEmpty: sets.isEmpty,
    );
  }

  Future<void> _refresh() async {
    final profile = await BeatsProfileService().fetchCurrentProfile();
    if (profile != null) await OfflineCacheService().refreshAll(profile.studentId);
    if (mounted) setState(() => _future = _load());
    await _future;
  }

  void _open(Map<String, dynamic> set, bool isPaid) {
    if (isPaidSet(set) && !isPaid) {
      showLockedDialog(context, practiceSetTitle: set['title'] as String?);
      return;
    }
    AppNav.openPractice(set);
  }

  String _summary(PracticeSettings? s) {
    if (s == null) return 'Pick up where you left off';
    final parts = <String>[
      if (s.bpm != null) '${s.bpm} BPM',
      if (s.loop) 'loop on',
      if (s.timerMinutes != null) '${s.timerMinutes} min timer',
    ];
    return parts.isEmpty ? 'Pick up where you left off' : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_HomeData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: Brand.cyan));
        }
        if (snapshot.hasError) {
          return PortalScroll(
            title: 'Overview',
            onRefresh: _refresh,
            children: [
              GlassTile(
                title: 'Something went wrong',
                icon: Icons.error_outline,
                iconColor: Brand.red,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('We could not load your home page.'),
                    const SizedBox(height: 12),
                    GradientButton(
                      label: 'Try again',
                      expanded: false,
                      onPressed: () => setState(() => _future = _load()),
                    ),
                  ],
                ),
              ),
            ],
          );
        }

        final d = snapshot.data!;
        return PortalScroll(
          title: 'Overview',
          subtitle: 'Welcome back, ${d.name}!',
          onRefresh: _refresh,
          children: [
            LayoutBuilder(builder: (context, c) {
              if (c.maxWidth >= kWideBreakpoint) return const SizedBox.shrink();
              return GradientText('Welcome back, ${d.name}!', style: sora(22, 800, spacing: -0.3));
            }),
            GlassTile(
              title: 'Start practice',
              icon: Icons.play_arrow,
              iconColor: Brand.cyan,
              child: GradientButton(
                label: 'Start Practice',
                icon: Icons.music_note,
                onPressed: () => AppNav.goTo(AppNav.practice),
              ),
            ),
            if (offlineSupported)
              ValueListenableBuilder<DownloadSyncStatus>(
                valueListenable: _downloads.status,
                builder: (context, status, _) => _DownloadStatusTile(status: status),
              ),
            if (d.continueSet != null)
              GlassTile(
                title: 'Continue practice',
                icon: Icons.history,
                iconColor: Brand.blue,
                child: _SetRow(
                  set: d.continueSet!,
                  subtitle: _summary(d.continueSettings),
                  locked: isPaidSet(d.continueSet!) && !d.isPaid,
                  onTap: () => _open(d.continueSet!, d.isPaid),
                ),
              ),
            GlassTile(
              title: 'Favorites',
              icon: Icons.star_outline,
              iconColor: Brand.amber,
              child: d.favorites.isEmpty
                  ? const Text('No favorites yet — tap the star on a practice set to add one.')
                  : Column(
                      children: [
                        for (final s in d.favorites)
                          _SetRow(
                            set: s,
                            locked: isPaidSet(s) && !d.isPaid,
                            onTap: () => _open(s, d.isPaid),
                          ),
                      ],
                    ),
            ),
            if (d.recent.isNotEmpty)
              GlassTile(
                title: 'Recent practice',
                icon: Icons.schedule,
                iconColor: Brand.green,
                child: Column(
                  children: [
                    for (final s in d.recent)
                      _SetRow(
                        set: s,
                        locked: isPaidSet(s) && !d.isPaid,
                        onTap: () => _open(s, d.isPaid),
                      ),
                  ],
                ),
              ),
            if (offlineSupported)
              ValueListenableBuilder<bool>(
                valueListenable: ConnectivityService.instance.online,
                builder: (context, online, _) => ValueListenableBuilder<DownloadSyncStatus>(
                  valueListenable: _downloads.status,
                  builder: (context, status, _) {
                    final n = status.complete;
                    return GlassTile(
                      title: 'Offline status',
                      icon: online ? Icons.cloud_done_outlined : Icons.cloud_off,
                      iconColor: online ? Brand.green : Brand.warning,
                      child: Text(
                        online
                            ? 'Online · $n track${n == 1 ? '' : 's'} saved on this device'
                            : 'Offline · $n track${n == 1 ? '' : 's'} available to play',
                      ),
                    );
                  },
                ),
              ),
            if (d.catalogEmpty)
              const GlassTile(
                title: 'Practice content',
                icon: Icons.library_music_outlined,
                child: Text('No practice content has been published yet.'),
              ),
          ],
        );
      },
    );
  }
}

/// Background track download: progress while it runs, and a retry when
/// tracks failed even after the automatic retries. Hidden once everything
/// is on the device.
class _DownloadStatusTile extends StatelessWidget {
  final DownloadSyncStatus status;
  const _DownloadStatusTile({required this.status});

  @override
  Widget build(BuildContext context) {
    final s = status;
    if (s.running && s.complete < s.total) {
      return GlassTile(
        title: 'Downloading tracks',
        icon: Icons.downloading,
        iconColor: Brand.blue,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${s.complete} of ${s.total} tracks saved for offline practice. '
                'You can keep using the app meanwhile.'),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: s.total == 0 ? null : s.complete / s.total,
              color: Brand.cyan,
              backgroundColor: Brand.border,
            ),
          ],
        ),
      );
    }
    if (!s.running && s.failed > 0) {
      return GlassTile(
        title: 'Some tracks did not download',
        icon: Icons.error_outline,
        iconColor: Brand.warning,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${s.failed} track${s.failed == 1 ? '' : 's'} could not be downloaded. '
                'Check your connection and try again.'),
            const SizedBox(height: 12),
            GradientButton(
              label: 'Try again',
              icon: Icons.refresh,
              expanded: false,
              onPressed: () => DownloadManager().syncAll(userInitiated: true),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

class _SetRow extends StatelessWidget {
  final Map<String, dynamic> set;
  final String? subtitle;
  final bool locked;
  final VoidCallback onTap;

  const _SetRow({required this.set, required this.locked, required this.onTap, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Brand.radius),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Brand.cyan.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Brand.cyan.withValues(alpha: 0.7)),
              ),
              child: const Icon(Icons.graphic_eq_rounded, size: 20, color: Brand.cyan),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(set['title'] as String? ?? '',
                      style: sora(14, 700, color: Brand.text)),
                  if (subtitle != null)
                    Text(subtitle!, style: nunito(13, 400, color: Brand.textSecondary)),
                ],
              ),
            ),
            if (locked)
              const StatusBadge('Supporters', kind: BadgeKind.amber, icon: Icons.lock_outline)
            else
              const Icon(Icons.chevron_right, color: Brand.textMuted),
          ],
        ),
      ),
    );
  }
}

class _HomeData {
  final String name;
  final bool isPaid;
  final Map<String, dynamic>? continueSet;
  final PracticeSettings? continueSettings;
  final List<Map<String, dynamic>> recent;
  final List<Map<String, dynamic>> favorites;
  final bool catalogEmpty;

  _HomeData({
    required this.name,
    required this.isPaid,
    required this.continueSet,
    required this.continueSettings,
    required this.recent,
    required this.favorites,
    required this.catalogEmpty,
  });
}
