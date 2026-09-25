import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:url_launcher/url_launcher.dart';

import '../platform_support.dart';
import '../services/auth_service.dart';
import '../services/beats_profile_service.dart';
import '../services/download_manager.dart';
import '../services/offline_cache_service.dart';
import '../ui/brand.dart';
import '../ui/dialogs.dart';
import '../ui/widgets.dart';
import 'admin_screen.dart';
import 'auth/change_password_screen.dart';

const String _donationEmail = 'vasiskirtan@gmail.com';

/// Profile tab: account, support/donation, downloaded content, practice
/// history, and account actions.
class ProfileView extends StatefulWidget {
  const ProfileView({super.key});

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  final _nameController = TextEditingController();
  late Future<BeatsProfile?> _profile;
  bool _editing = false;
  bool _saving = false;
  int _donationAmount = 5;
  int _downloadsRefresh = 0;

  @override
  void initState() {
    super.initState();
    _profile = _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<BeatsProfile?> _loadProfile() async {
    final profile = await BeatsProfileService().fetchCurrentProfile();
    if (profile != null) {
      // Opportunistic background refresh of everything cacheable.
      OfflineCacheService().refreshAll(profile.studentId);
    }
    return profile;
  }

  Future<void> _saveName(BeatsProfile profile) async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    try {
      await BeatsProfileService().updateDisplayName(name);
      if (mounted) {
        setState(() => _profile = BeatsProfileService().fetchCurrentProfile());
        showBrandSnack(context, 'Username updated successfully');
      }
    } catch (e) {
      if (mounted) showBrandSnack(context, 'Failed to update username. Check your connection.');
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _editing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<BeatsProfile?>(
      future: _profile,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Brand.orange));
        }
        final profile = snapshot.data;
        if (profile == null) {
          return PortalScroll(
            title: 'Profile',
            children: [
              GlassTile(
                title: 'Account',
                icon: Icons.error_outline,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Error Authenticating, please try again...\n'
                      'We could not load your account details.',
                    ),
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      GradientButton(
                        label: 'Try again',
                        expanded: false,
                        onPressed: () => setState(() => _profile = _loadProfile()),
                      ),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white)),
                        onPressed: () => AuthService().signOut(),
                        child: const Text('Sign out'),
                      ),
                    ]),
                  ],
                ),
              ),
            ],
          );
        }

        return PortalScroll(
          title: 'Profile',
          children: [
            _accountTile(profile),
            _supportCard(profile),
            if (offlineSupported) _downloadsCard(),
            _historyCard(),
            _actions(profile),
          ],
        );
      },
    );
  }

  Widget _accountTile(BeatsProfile profile) {
    final tier = profile.isAdmin ? 'Paid (Admin)' : (profile.isPaid ? 'Paid' : 'Free');
    return GlassTile(
      title: 'Profile',
      icon: Icons.person,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: CircleAvatar(
              radius: 44,
              backgroundColor: Brand.gray200,
              backgroundImage: const AssetImage('images/default_profile.png'),
            ),
          ),
          const SizedBox(height: 16),
          _label('Username'),
          if (_editing)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    autofocus: true,
                    style: nunito(15, 500, color: Brand.gray900),
                    decoration: const InputDecoration(isDense: true),
                  ),
                ),
                const SizedBox(width: 8),
                if (_saving)
                  const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                else ...[
                  IconButton(
                    tooltip: 'Save',
                    icon: const Icon(Icons.check, color: Colors.greenAccent),
                    onPressed: () => _saveName(profile),
                  ),
                  IconButton(
                    tooltip: 'Cancel',
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => setState(() => _editing = false),
                  ),
                ],
              ],
            )
          else
            Row(
              children: [
                Expanded(child: Text(profile.displayName, style: nunito(18, 600, color: Colors.white))),
                IconButton(
                  tooltip: 'Edit username',
                  icon: const Icon(Icons.edit, color: Colors.white),
                  onPressed: () {
                    _nameController.text = profile.displayName;
                    setState(() => _editing = true);
                  },
                ),
              ],
            ),
          const SizedBox(height: 12),
          _label('Email'),
          Text(profile.email, style: nunito(16, 500, color: Colors.white)),
          const SizedBox(height: 12),
          _label('Account type'),
          Row(
            children: [
              StatusBadge(
                tier,
                kind: profile.isPaid ? BadgeKind.green : BadgeKind.gray,
                icon: profile.isPaid ? Icons.workspace_premium : Icons.person_outline,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _label('Donation'),
          Text(
            '${profile.donationCurrency} ${profile.donationAmount.toStringAsFixed(1)}',
            style: nunito(16, 700, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text.toUpperCase(),
            style: nunito(12, 600, color: const Color(0xFFE5E7EB), spacing: 0.6)),
      );

  Widget _supportCard(BeatsProfile profile) {
    return PortalCard(
      header: 'Support VasisBeats',
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Donate USD 5\$ or more to Vasis Studios and send details to ',
                  style: nunito(14, 400, color: Brand.gray700)),
              GestureDetector(
                onTap: () => _emailDonationReceipt(profile),
                child: Text(_donationEmail,
                    style: nunito(14, 700, color: Brand.purpleLight)
                        .copyWith(decoration: TextDecoration.underline)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 24,
            runSpacing: 16,
            alignment: WrapAlignment.spaceAround,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Column(children: [
                Image.asset('images/upi_qr.png', height: 120, width: 120, fit: BoxFit.contain),
                const SizedBox(height: 6),
                Text('Donate with UPI', style: nunito(13, 600, color: Brand.gray700)),
              ]),
              Column(children: [
                DropdownButton<int>(
                  value: _donationAmount,
                  items: [5, 10, 15, 20]
                      .map((a) => DropdownMenuItem(value: a, child: Text('\$$a')))
                      .toList(),
                  onChanged: (v) => setState(() => _donationAmount = v ?? 5),
                ),
                const SizedBox(height: 8),
                GradientButton(
                  label: 'Donate via PayPal',
                  icon: Icons.payment,
                  expanded: false,
                  onPressed: () => launchUrl(
                    Uri.parse('https://www.paypal.com/paypalme/Girigovardhana/${_donationAmount}USD'),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
              ]),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _emailDonationReceipt(BeatsProfile profile) async {
    final uri = Uri(
      scheme: 'mailto',
      path: _donationEmail,
      query: 'subject=${Uri.encodeComponent('VASIS Donation Receipt - $_donationAmount')}'
          '&body=${Uri.encodeComponent('Hello VASIS Team,\n\nI have donated $_donationAmount to support VASIS.\n\n'
              'Transaction Details:\n- Amount: $_donationAmount\n- Date: ${DateTime.now().toString().split(' ')[0]}\n'
              '- Payment Method: [Please specify]\n- Username: ${profile.displayName}\n\n'
              'I have attached the transaction screenshot for your reference.\n\nThanks,\n${profile.displayName}')}',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      await Clipboard.setData(const ClipboardData(text: _donationEmail));
      if (mounted) showBrandSnack(context, 'Email address copied to clipboard');
    }
  }

  Widget _downloadsCard() {
    final downloads = DownloadManager();
    return PortalCard(
      header: 'Downloaded content',
      child: FutureBuilder<List<Map<String, dynamic>>>(
        key: ValueKey(_downloadsRefresh),
        future: downloads.getDownloadedTracks(),
        builder: (context, snapshot) {
          final tracks = snapshot.data;
          if (tracks == null) return const Center(child: CircularProgressIndicator());
          if (tracks.isEmpty) return const Text('Nothing downloaded yet.');
          final anyStale = tracks.any(DownloadManager.isStale);
          final totalBytes =
              tracks.fold<int>(0, (sum, t) => sum + ((t['bytes_downloaded'] as int?) ?? 0));
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${tracks.length} track${tracks.length == 1 ? '' : 's'} · '
                  '${(totalBytes / 1024 / 1024).toStringAsFixed(1)} MB used',
                  style: nunito(13, 600, color: Brand.gray600)),
              const SizedBox(height: 8),
              for (final t in tracks)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(t['title'] as String? ?? '',
                      style: nunito(14, 600, color: Brand.gray900)),
                  subtitle: Text(
                      '${((t['bytes_downloaded'] as int? ?? 0) / 1024 / 1024).toStringAsFixed(1)} MB',
                      style: nunito(12, 400, color: Brand.gray500)),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (DownloadManager.isStale(t))
                      const StatusBadge('Update available', kind: BadgeKind.amber, icon: Icons.update),
                    IconButton(
                      tooltip: 'Remove download',
                      icon: const Icon(Icons.delete_outline, color: Brand.error),
                      onPressed: () async {
                        await downloads.deleteDownload(t['id'] as String);
                        if (mounted) setState(() => _downloadsRefresh++);
                      },
                    ),
                  ]),
                ),
              if (anyStale)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: GradientButton(
                    label: 'Update all',
                    icon: Icons.update,
                    onPressed: () async {
                      await downloads.updateStaleTracks();
                      if (mounted) setState(() => _downloadsRefresh++);
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _historyCard() {
    return PortalCard(
      header: 'Practice history',
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: OfflineCacheService().getCachedPracticeHistory(limit: 10),
        builder: (context, snapshot) {
          final sessions = snapshot.data;
          if (sessions == null) return const Center(child: CircularProgressIndicator());
          if (sessions.isEmpty) return const Text('No practice sessions yet.');
          return Column(
            children: [
              for (final s in sessions)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.music_note),
                  title: Text(
                    '${((s['duration_seconds'] as int? ?? 0) / 60).round()} min at '
                    '${s['tempo_bpm'] ?? '—'} BPM',
                    style: nunito(14, 600, color: Brand.gray900),
                  ),
                  subtitle: Text(_when(s['started_at'] as String?),
                      style: nunito(12, 400, color: Brand.gray500)),
                ),
            ],
          );
        },
      ),
    );
  }

  String _when(String? iso) {
    final dt = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  Widget _actions(BeatsProfile profile) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white, side: const BorderSide(color: Colors.white70)),
          onPressed: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const ChangePasswordScreen())),
          icon: const Icon(Icons.lock_outline),
          label: const Text('Change password'),
        ),
        if (storeRatingSupported)
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white, side: const BorderSide(color: Colors.white70)),
            onPressed: _showRatingDialog,
            icon: const Icon(Icons.star_outline),
            label: const Text('Rate the app'),
          ),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white, side: const BorderSide(color: Colors.white70)),
          onPressed: () => launchSupportEmail(context, subject: 'Vasis Beats support'),
          icon: const Icon(Icons.support_agent),
          label: const Text('Contact support'),
        ),
        if (profile.isAdmin)
          GradientButton(
            label: 'Admin Panel',
            icon: Icons.admin_panel_settings_outlined,
            expanded: false,
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const AdminPanelScreen())),
          ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: Brand.error),
          // No navigation needed: MyApp's auth listener returns to sign in.
          onPressed: () => AuthService().signOut(),
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
        ),
      ],
    );
  }

  void _showRatingDialog() {
    double rating = 3.0;
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Rate Our App'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  5,
                  (i) => IconButton(
                    tooltip: '${i + 1} star${i == 0 ? '' : 's'}',
                    icon: Icon(i < rating ? Icons.star : Icons.star_border,
                        color: Colors.amber, size: 32),
                    onPressed: () => setDialogState(() => rating = i + 1.0),
                  ),
                ),
              ),
              TextField(
                controller: controller,
                decoration: const InputDecoration(hintText: 'Optional feedback'),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              child: const Text('Submit'),
              onPressed: () async {
                final platform = Theme.of(context).platform;
                final storeUri = switch (platform) {
                  TargetPlatform.android => Uri.parse(
                      'https://play.google.com/store/apps/details?id=dev.suragch.flutter_audio_service_demo'),
                  TargetPlatform.iOS => Uri.parse('https://apps.apple.com/app/id1624246378'),
                  TargetPlatform.macOS => Uri.parse('https://apps.apple.com/app/id1625800928'),
                  _ => null,
                };
                Future<void> openStore() async {
                  if (storeUri != null && await canLaunchUrl(storeUri)) await launchUrl(storeUri);
                }

                try {
                  final review = InAppReview.instance;
                  if (await review.isAvailable()) {
                    await review.requestReview();
                  } else {
                    await openStore();
                  }
                } catch (_) {
                  await openStore();
                }
                if (context.mounted) Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}
