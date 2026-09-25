import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../ui/brand.dart';
import '../ui/dialogs.dart';
import '../ui/widgets.dart';

/// Admin: view every user and set their Vasis Beats tier and donation.
/// Anyone with `vms_students.role = 'admin'` has database access to this;
/// the screen is only offered to admins in Profile.
class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  late Future<List<Map<String, dynamic>>> _students;
  final _search = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _students = _fetch();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _fetch() async {
    final rows = await Supabase.instance.client
        .from('vms_students')
        .select(
            'id, email, legal_name, role, vms_beats_access(account_type, donation_amount, donation_currency)')
        .order('email');
    return List<Map<String, dynamic>>.from(rows);
  }

  @override
  Widget build(BuildContext context) {
    return PortalPage(
      title: 'Admin Panel',
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: TextField(
                  controller: _search,
                  onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                  decoration: InputDecoration(
                    hintText: 'Search by name or email',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      tooltip: 'Refresh',
                      icon: const Icon(Icons.refresh),
                      onPressed: () => setState(() => _students = _fetch()),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _students,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator(color: Brand.orange));
                    }
                    if (snapshot.hasError) {
                      return const Center(
                        child: NoticeBanner('Could not load users. Check your connection.'),
                      );
                    }
                    final all = snapshot.data ?? const [];
                    final rows = _query.isEmpty
                        ? all
                        : all.where((s) {
                            final hay = '${s['email']} ${s['legal_name']}'.toLowerCase();
                            return hay.contains(_query);
                          }).toList();
                    if (rows.isEmpty) return const Center(child: NoticeBanner('No users found.'));
                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: rows.length,
                      itemBuilder: (_, i) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _UserCard(key: ValueKey(rows[i]['id']), student: rows[i]),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserCard extends StatefulWidget {
  final Map<String, dynamic> student;
  const _UserCard({super.key, required this.student});

  @override
  State<_UserCard> createState() => _UserCardState();
}

class _UserCardState extends State<_UserCard> {
  static const _donationThreshold = 10.0;

  late final TextEditingController _amount;
  late String _accountType;
  late String _currency;
  bool _saving = false;

  Map<String, dynamic>? get _access => widget.student['vms_beats_access'] as Map<String, dynamic>?;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(text: _access?['donation_amount']?.toString() ?? '0');
    _currency = _access?['donation_currency'] as String? ?? 'USD';
    _accountType = _access?['account_type'] as String? ?? 'free';
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text) ?? 0.0;
    final type = (amount >= _donationThreshold && _currency == 'USD') ? 'paid' : _accountType;
    setState(() => _saving = true);
    try {
      // vms_beats_access.student_id is the primary key, so upsert resolves
      // to insert-or-update for one row per student.
      await Supabase.instance.client.from('vms_beats_access').upsert({
        'student_id': widget.student['id'],
        'account_type': type,
        'donation_amount': amount,
        'donation_currency': _currency,
      });
      if (mounted) {
        setState(() => _accountType = type);
        showBrandSnack(context, 'Updated ${widget.student['email']}');
      }
    } catch (_) {
      if (mounted) showBrandSnack(context, 'Failed to update. Check your connection.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = (widget.student['legal_name'] as String?)?.trim();
    final email = widget.student['email'] as String? ?? '';
    final role = widget.student['role'] as String? ?? 'student';

    return PortalCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text((name == null || name.isEmpty) ? email : name,
                    overflow: TextOverflow.ellipsis,
                    style: nunito(17, 700, color: Brand.gray900)),
              ),
              if (role != 'student') StatusBadge(role, kind: BadgeKind.indigo),
            ],
          ),
          Text(email, style: nunito(13, 400, color: Brand.gray500)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 130,
                child: DropdownButtonFormField<String>(
                  initialValue: _accountType,
                  decoration: const InputDecoration(labelText: 'Account type', isDense: true),
                  items: const [
                    DropdownMenuItem(value: 'free', child: Text('Free')),
                    DropdownMenuItem(value: 'paid', child: Text('Paid')),
                  ],
                  onChanged: (v) => setState(() => _accountType = v ?? 'free'),
                ),
              ),
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Donation', isDense: true),
                ),
              ),
              SizedBox(
                width: 100,
                child: DropdownButtonFormField<String>(
                  initialValue: _currency,
                  decoration: const InputDecoration(labelText: 'Currency', isDense: true),
                  items: const [
                    DropdownMenuItem(value: 'USD', child: Text('USD')),
                    DropdownMenuItem(value: 'INR', child: Text('INR')),
                  ],
                  onChanged: (v) => setState(() => _currency = v ?? 'USD'),
                ),
              ),
              GradientButton(
                label: 'Update',
                icon: Icons.save_outlined,
                expanded: false,
                loading: _saving,
                onPressed: _saving ? null : _save,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
