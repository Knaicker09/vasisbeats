import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../platform_support.dart';
import 'offline_cache_service.dart';

/// The signed-in user's profile: `vms_students` (shared with the Vasis
/// Studio website/LMS) merged with `vms_beats_access` (this app's tier).
class BeatsProfile {
  final int studentId;
  final String email;
  final String displayName;
  final String role;
  final String accountType;
  final double donationAmount;
  final String donationCurrency;

  const BeatsProfile({
    required this.studentId,
    required this.email,
    required this.displayName,
    required this.role,
    required this.accountType,
    required this.donationAmount,
    required this.donationCurrency,
  });

  bool get isAdmin => role == 'admin';

  /// Same rule the previous app used to unlock paid levels, and the same
  /// one the database enforces (private.vms_beats_caller_is_paid): an
  /// admin, a `paid` account, or any recorded donation.
  bool get isPaid => isAdmin || accountType == 'paid' || donationAmount > 0;
}

/// Reads/updates the signed-in user's profile through two database
/// functions (`beats_get_my_profile`, `beats_update_my_name`) rather than
/// the tables directly: `vms_students` only lets `student`/`admin` rows be
/// read by their owner, so direct queries return nothing for teachers.
/// `vms_students` rows themselves are created by the `handle_new_auth_user`
/// trigger on `auth.users` — this app never inserts one.
class BeatsProfileService {
  SupabaseClient get _client => Supabase.instance.client;
  OfflineCacheService get _cache => OfflineCacheService();

  /// Returns null only if nobody is signed in (a genuinely signed-out
  /// state — the Supabase session is restored from local storage before
  /// this runs). On native platforms a network failure falls back to the
  /// profile cached the last time this succeeded, so the app still opens
  /// offline. Web is online-only and has no cache.
  Future<BeatsProfile?> fetchCurrentProfile() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;

    try {
      final data = await _client.rpc('beats_get_my_profile');
      if (data == null) return null;
      final row = Map<String, dynamic>.from(data as Map);

      final email = (row['email'] as String?) ?? user.email ?? '';
      final legalName = (row['legal_name'] as String?)?.trim();
      final profile = BeatsProfile(
        studentId: row['id'] as int,
        email: email,
        displayName: (legalName == null || legalName.isEmpty)
            ? (email.contains('@') ? email.split('@').first : email)
            : legalName,
        role: (row['role'] as String?) ?? 'student',
        accountType: (row['account_type'] as String?) ?? 'free',
        donationAmount: (row['donation_amount'] as num?)?.toDouble() ?? 0.0,
        donationCurrency: (row['donation_currency'] as String?) ?? 'USD',
      );

      if (offlineSupported) await _cache.cacheProfile(profile);
      return profile;
    } catch (e) {
      debugPrint('⚠️ Could not fetch profile from Supabase: $e');
      if (!offlineSupported) rethrow;
      return _cache.getCachedProfile();
    }
  }

  Future<void> updateDisplayName(String newName) async {
    await _client.rpc('beats_update_my_name', params: {'new_name': newName});
  }

  /// Convenience for places that only need a yes/no (gating a paid set).
  Future<bool> isCurrentUserPaid() async {
    final profile = await fetchCurrentProfile();
    return profile?.isPaid ?? false;
  }
}
