import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_nav.dart';
import '../platform_support.dart';
import '../services/connectivity_service.dart';
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

/// The signed-in app frame, laid out like the website's student portal:
/// a hover-expanding navy sidebar on wide screens; on phones a navy top bar
/// with the page title in orange and a navy bottom bar with an orange
/// active pill. Pages sit on the piano-keys background.
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
              backgroundColor: Brand.navy,
              body: Row(
                children: [
                  _Sidebar(index: index),
                  Expanded(
                    child: PortalBackground(
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
            backgroundColor: Brand.navy,
            body: Column(
              children: [
                _TopBar(title: _tabs[index].label),
                Expanded(
                  child: PortalBackground(
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
          color: Brand.warningBg,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off, size: 16, color: Brand.warning),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  "You're offline — showing your saved content.",
                  style: nunito(13, 600, color: const Color(0xFF92400E)),
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
        border: Border(bottom: BorderSide(color: Color(0x4DDC2626))),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 64,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Image.asset('images/logo.png', height: 44),
                const Spacer(),
                Text(title, style: nunito(18, 600, color: Brand.orange)),
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
        border: Border(top: BorderSide(color: Color(0x4DDC2626))),
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
    final color = selected ? Colors.white : Brand.gray300;
    final icon = Icon(selected ? tab.selectedIcon : tab.icon, color: color, size: 24);
    final label = Text(tab.label, style: nunito(vertical ? 12 : 14, 600, color: color));

    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Brand.radius),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: vertical ? 6 : 12, horizontal: vertical ? 4 : 16),
          margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          decoration: BoxDecoration(
            color: selected ? Brand.orange : Colors.transparent,
            borderRadius: BorderRadius.circular(Brand.radius),
          ),
          child: vertical
              ? Column(mainAxisSize: MainAxisSize.min, children: [icon, const SizedBox(height: 2), label])
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

/// Wide-screen sidebar: 80px rail that expands to 256px on hover, like the
/// website's.
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
        decoration: const BoxDecoration(gradient: Brand.chromeGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                Center(
                  child: Image.asset(
                    'images/logo.png',
                    width: _expanded ? 128 : 56,
                    height: _expanded ? 72 : 48,
                    fit: BoxFit.contain,
                  ),
                ),
                if (!_expanded)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('MENU',
                        textAlign: TextAlign.center,
                        style: nunito(11, 700, color: Brand.orange, spacing: 1)),
                  ),
                const SizedBox(height: 24),
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
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: Brand.orange,
                      child: Text(
                        email.isEmpty ? '?' : email[0].toUpperCase(),
                        style: nunito(15, 700, color: Colors.white),
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
                                style: nunito(13, 500, color: Colors.white)),
                            Text('Online', style: nunito(12, 400, color: Brand.orange)),
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
