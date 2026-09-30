import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_nav.dart';
import '../platform_support.dart';
import '../services/beats_profile_service.dart';
import '../services/connectivity_service.dart';
import '../services/offline_cache_service.dart';
import '../ui/brand.dart';
import '../ui/widgets.dart';
import 'home_screen.dart';
import 'learn_screen.dart';
import 'practice_screen.dart';
import 'profile_screen.dart';

class _Tab {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  const _Tab(this.label, this.icon, this.selectedIcon);
}

const _tabs = [
  _Tab('Home', Icons.dashboard_outlined, Icons.dashboard),
  _Tab('Practice', Icons.music_note_outlined, Icons.music_note),
  _Tab('Learn', Icons.play_lesson_outlined, Icons.play_lesson),
  _Tab('Profile', Icons.person_outline, Icons.person),
];

/// The signed-in app frame: a hover-expanding glass sidebar on wide
/// screens; on phones a glass top bar with the brand mark and page title
/// and a bottom bar whose active tab glows cyan. Pages sit on the neon
/// background.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {

  @override
  void initState() {
    super.initState();
    ConnectivityService.instance.start();
    _refreshInBackground();
  }

  /// Every sign-in / app start: mirror the catalog and the user's data and
  /// start downloading their tracks in the background (native only; a
  /// no-op on web).
  Future<void> _refreshInBackground() async {
    final profile = await BeatsProfileService().fetchCurrentProfile();
    if (profile != null) await OfflineCacheService().refreshAll(profile.studentId);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AppNav.tab,
      builder: (context, index, _) {
        final body = _PageStack(index: index);
        return LayoutBuilder(builder: (context, constraints) {
          final wide = constraints.maxWidth >= kWideBreakpoint;
          if (wide) {
            return Scaffold(
              backgroundColor: Brand.bg,
              body: Row(
                children: [
                  _Sidebar(index: index),
                  Expanded(
                    child: NeonBackground(
                      child: Column(
                        children: [
                          const _OfflineBanner(),
                          Expanded(child: body),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }
          return Scaffold(
            backgroundColor: Brand.bg,
            body: Column(
              children: [
                _TopBar(title: _tabs[index].label),
                Expanded(
                  child: NeonBackground(
                    child: Column(
                      children: [
                        const _OfflineBanner(),
                        Expanded(child: body),
                      ],
                    ),
                  ),
                ),
                _BottomBar(index: index),
              ],
            ),
          );
        });
      },
    );
  }
}

/// Keeps every tab alive (Practice in particular must not lose its loaded
/// set or timer when you glance at another tab).
class _PageStack extends StatelessWidget {
  final int index;
  const _PageStack({required this.index});

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: index,
      children: const [HomeView(), PracticeView(), LearnView(), ProfileView()],
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    if (!offlineSupported) return const SizedBox.shrink();
    return ValueListenableBuilder<bool>(
      valueListenable: ConnectivityService.instance.online,
      builder: (context, online, _) {
        if (online) return const SizedBox.shrink();
        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Brand.warning.withValues(alpha: 0.12),
            border: Border(bottom: BorderSide(color: Brand.warning.withValues(alpha: 0.4))),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off, size: 16, color: Brand.warning),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  "You're offline — showing your saved content.",
                  style: nunito(13, 700, color: Brand.warningText),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  final String title;
  const _TopBar({required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: Brand.chromeGradient,
        border: Border(bottom: BorderSide(color: Brand.border)),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 60,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const BrandMark(size: 30),
                const Spacer(),
                Text(title.toUpperCase(), style: sora(13, 700, color: Brand.textSecondary, spacing: 1.6)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final int index;
  const _BottomBar({required this.index});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: Brand.chromeGradient,
        border: Border(top: BorderSide(color: Brand.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              for (var i = 0; i < _tabs.length; i++)
                Expanded(
                  child: _NavItem(
                    tab: _tabs[i],
                    selected: i == index,
                    onTap: () => AppNav.goTo(i),
                    vertical: true,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final _Tab tab;
  final bool selected;
  final VoidCallback onTap;
  final bool vertical;
  final bool showLabel;

  const _NavItem({
    required this.tab,
    required this.selected,
    required this.onTap,
    this.vertical = false,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? Brand.cyanBright : Brand.textMuted;
    final icon = Icon(selected ? tab.selectedIcon : tab.icon, color: color, size: 24);
    final label = Text(
      vertical ? tab.label.toUpperCase() : tab.label,
      style: vertical ? sora(10, 700, color: color, spacing: 1) : sora(14, 600, color: color),
    );

    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Brand.radius),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          padding: EdgeInsets.symmetric(vertical: vertical ? 7 : 12, horizontal: vertical ? 4 : 16),
          margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
          decoration: BoxDecoration(
            color: selected ? Brand.cyan.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(Brand.radius),
            border: Border.all(color: selected ? Brand.cyan.withValues(alpha: 0.7) : Colors.transparent),
            boxShadow: selected ? Brand.glow(Brand.cyan, 0.45) : null,
          ),
          child: vertical
              ? Column(mainAxisSize: MainAxisSize.min, children: [icon, const SizedBox(height: 3), label])
              : Row(
                  children: [
                    icon,
                    if (showLabel) ...[const SizedBox(width: 12), Flexible(child: label)],
                  ],
                ),
        ),
      ),
    );
  }
}

/// Wide-screen sidebar: 80px rail that expands to 256px on hover.
class _Sidebar extends StatefulWidget {
  final int index;
  const _Sidebar({required this.index});

  @override
  State<_Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<_Sidebar> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final email = Supabase.instance.client.auth.currentUser?.email ?? '';
    return MouseRegion(
      onEnter: (_) => setState(() => _expanded = true),
      onExit: (_) => setState(() => _expanded = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: _expanded ? 256 : 80,
        decoration: const BoxDecoration(
          gradient: Brand.chromeGradient,
          border: Border(right: BorderSide(color: Brand.border)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                Center(
                  child: FittedBox(child: BrandMark(size: 40, showWordmark: _expanded)),
                ),
                const SizedBox(height: 28),
                for (var i = 0; i < _tabs.length; i++)
                  _NavItem(
                    tab: _tabs[i],
                    selected: i == widget.index,
                    showLabel: _expanded,
                    onTap: () => AppNav.goTo(i),
                  ),
                const Spacer(),
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: Brand.primaryGradient,
                        boxShadow: Brand.glow(Brand.blue, 0.5),
                      ),
                      child: Text(
                        email.isEmpty ? '?' : email[0].toUpperCase(),
                        style: sora(15, 700, color: Colors.white),
                      ),
                    ),
                    if (_expanded) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(email,
                                overflow: TextOverflow.ellipsis,
                                style: nunito(13, 600, color: Brand.text)),
                            Text('Online', style: nunito(12, 600, color: Brand.green)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
