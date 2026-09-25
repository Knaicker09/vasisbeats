import 'package:flutter/material.dart';

import '../app_nav.dart';
import '../platform_support.dart';
import '../services/beats_profile_service.dart';
import '../services/download_manager.dart';
import '../services/offline_cache_service.dart';
import '../services/practice_controller.dart' show isPaidSet;
import '../ui/brand.dart';
import '../ui/dialogs.dart';
import '../ui/widgets.dart';

class _Tutorial {
  final String title;
  final String body;
  const _Tutorial(this.title, this.body);
}

const List<_Tutorial> _tutorials = [
  _Tutorial(
    'What BPM means',
    'BPM (beats per minute) is how fast the rhythm cycle repeats. A higher number means a faster tempo. Every practice set shows a BPM range so you know what to expect before you start.',
  ),
  _Tutorial(
    'Practicing slowly',
    'Start well below a track\'s normal tempo — the "Beginner / Slow" sets are built for this. Getting the pattern right at a slow, steady tempo matters more than rushing to full speed.',
  ),
  _Tutorial(
    'Increasing speed',
    'Once a rhythm feels comfortable, raise the tempo a little at a time using the BPM slider on the Practice screen, rather than jumping straight to performance speed.',
  ),
  _Tutorial(
    'Practicing with kartals and mrdanga',
    'Use the instrument mix on the Practice screen to bring in one instrument at a time — start with just the mrdanga to internalize the beat, then bring the kartals in once it feels steady.',
  ),
];

/// Learn tab: short tutorials plus practice sets linked to LMS courses,
/// which can be downloaded together for offline use.
class LearnView extends StatefulWidget {
  const LearnView({super.key});

  @override
  State<LearnView> createState() => _LearnViewState();
}

class _LearnViewState extends State<LearnView> {
  late Future<({List<Map<String, dynamic>> sets, bool isPaid})> _future;
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
    AppNav.tab.addListener(_onTab);
  }

  @override
  void dispose() {
    AppNav.tab.removeListener(_onTab);
    super.dispose();
  }

  void _onTab() {
    if (AppNav.tab.value == AppNav.learn && mounted) setState(() => _future = _load());
  }

  Future<({List<Map<String, dynamic>> sets, bool isPaid})> _load() async {
    final profile = await BeatsProfileService().fetchCurrentProfile();
    final sets = await OfflineCacheService().getCachedPracticeSets();
    return (
      sets: sets.where((s) => s['course_id'] != null || s['class_id'] != null).toList(),
      isPaid: profile?.isPaid ?? false,
    );
  }

  Future<void> _downloadCourseContent() async {
    setState(() => _downloading = true);
    try {
      final failed = await DownloadManager().downloadCourseContent();
      if (mounted) {
        showBrandSnack(
          context,
          failed == 0
              ? 'Course content is saved on this device.'
              : '$failed track${failed == 1 ? '' : 's'} could not be downloaded. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PortalScroll(
      title: 'Learn',
      subtitle: 'Short tutorials and course practice',
      children: [
        for (final t in _tutorials)
          PortalCard(
            padding: EdgeInsets.zero,
            child: ExpansionTile(
              leading: const Icon(Icons.play_circle_outline),
              title: Text(t.title, style: nunito(16, 600, color: Brand.gray900)),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [Text(t.body, style: nunito(14, 400, color: Brand.gray700, height: 1.5))],
            ),
          ),
        FutureBuilder<({List<Map<String, dynamic>> sets, bool isPaid})>(
          future: _future,
          builder: (context, snapshot) {
            final data = snapshot.data;
            if (data == null) {
              return const Center(child: CircularProgressIndicator(color: Brand.orange));
            }
            return PortalCard(
              header: 'Course-linked practice',
              child: data.sets.isEmpty
                  ? const Text('No course-linked practice sets yet.')
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final s in data.sets)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.music_note),
                            title: Text(s['title'] as String? ?? '',
                                style: nunito(15, 600, color: Brand.gray900)),
                            trailing: (isPaidSet(s) && !data.isPaid)
                                ? const StatusBadge('Supporters',
                                    kind: BadgeKind.amber, icon: Icons.lock_outline)
                                : const Icon(Icons.chevron_right),
                            onTap: () => (isPaidSet(s) && !data.isPaid)
                                ? showLockedDialog(context,
                                    practiceSetTitle: s['title'] as String?)
                                : AppNav.openPractice(s),
                          ),
                        if (offlineSupported) ...[
                          const SizedBox(height: 12),
                          GradientButton(
                            label: 'Download all course content',
                            icon: Icons.download,
                            loading: _downloading,
                            onPressed: _downloading ? null : _downloadCourseContent,
                          ),
                        ],
                      ],
                    ),
            );
          },
        ),
      ],
    );
  }
}
