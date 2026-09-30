import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../platform_support.dart';
import 'beats_profile_service.dart';
import 'download_manager.dart';
import 'local_database.dart';

/// The app's data access for catalog text, favorites, practice history and
/// the profile.
///
/// * Native platforms: everything is read from the on-device SQLite cache
///   (see LocalDatabase) so screens render instantly and work offline;
///   `refresh*` calls mirror Supabase into it whenever a connection allows.
/// * Web is online-only (no local storage of this kind): the same `get*`
///   methods read live from Supabase and `refresh*` are no-ops, so no
///   screen needs to know which mode it's in.
///
/// User-specific rows (profile, favorites, history) are tied to the signed-in
/// account, so switching accounts on a device never shows the previous
/// user's data.
/// Tala names are Hindi numbers in the catalog ("Teen Taal", "Do Taal");
/// the app shows them in English. Applied to tala names and practice-set
/// titles as they leave this service, so every screen (and the lock-screen
/// title) gets the English name while the database keeps the original.
const Map<String, String> _talaNamesInEnglish = {
  'Teen Taal': 'Three Beats',
  'Do Taal': 'Two Beats',
};

String? _inEnglish(String? text) {
  if (text == null) return null;
  var out = text;
  _talaNamesInEnglish.forEach((hindi, english) => out = out.replaceAll(hindi, english));
  return out;
}

List<Map<String, dynamic>> _withEnglish(Iterable<Map<String, dynamic>> rows, String field) => [
      for (final r in rows) {...r, field: _inEnglish(r[field] as String?)},
    ];

class OfflineCacheService {
  OfflineCacheService._();
  static final OfflineCacheService _instance = OfflineCacheService._();
  factory OfflineCacheService() => _instance;

  final LocalDatabase _localDb = LocalDatabase();
  SupabaseClient get _client => Supabase.instance.client;

  String get _now => DateTime.now().toUtc().toIso8601String();
  String? get _authUserId => _client.auth.currentUser?.id;

  // ---------------------------------------------------------------------
  // Profile
  // ---------------------------------------------------------------------

  Future<void> cacheProfile(BeatsProfile profile) async {
    final db = await _localDb.database;
    await db.insert(
      'local_profile',
      {
        'id': 1,
        'student_id': profile.studentId,
        'email': profile.email,
        'display_name': profile.displayName,
        'role': profile.role,
        'account_type': profile.accountType,
        'donation_amount': profile.donationAmount,
        'donation_currency': profile.donationCurrency,
        'auth_user_id': _authUserId,
        'cached_at': _now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// The cached profile — only if it belongs to whoever is signed in now.
  Future<BeatsProfile?> getCachedProfile() async {
    final authId = _authUserId;
    if (authId == null) return null;
    final db = await _localDb.database;
    final rows = await db.query('local_profile',
        where: 'id = 1 AND auth_user_id = ?', whereArgs: [authId], limit: 1);
    if (rows.isEmpty) return null;
    final row = rows.first;
    return BeatsProfile(
      studentId: row['student_id'] as int,
      email: row['email'] as String,
      displayName: row['display_name'] as String,
      role: row['role'] as String,
      accountType: row['account_type'] as String,
      donationAmount: (row['donation_amount'] as num).toDouble(),
      donationCurrency: row['donation_currency'] as String,
    );
  }

  /// Called on sign-out: drops the previous user's profile, favorites and
  /// already-synced history. Sessions not yet uploaded stay (tagged with
  /// their owner) so they still sync when that user next signs in.
  Future<void> clearUserData() async {
    if (!offlineSupported) return;
    final db = await _localDb.database;
    await db.delete('local_profile');
    await db.delete('local_favorites');
    await db.delete('local_practice_sessions', where: 'synced = 1');
  }

  Future<int?> _currentStudentId() async {
    if (offlineSupported) {
      return (await getCachedProfile())?.studentId;
    }
    final data = await _client.rpc('beats_get_my_profile');
    return data == null ? null : (data as Map)['id'] as int?;
  }

  // ---------------------------------------------------------------------
  // Catalog: talas / practice sets / tracks
  // ---------------------------------------------------------------------

  /// Pulls the catalog this user is allowed to see and mirrors it locally.
  /// Preserves each track's local download state; anything the server no
  /// longer returns (removed, or a paid set this user can't access) is
  /// hidden rather than deleted, so downloaded files aren't orphaned.
  Future<void> refreshCatalog() async {
    if (!offlineSupported) return;
    final db = await _localDb.database;

    final talas = await _client.from('vms_beats_talas').select().eq('is_active', true);
    final talaBatch = db.batch();
    for (final t in talas) {
      talaBatch.insert(
        'local_talas',
        {
          'id': t['id'],
          'name': t['name'],
          'name_es': t['name_es'],
          'name_pt': t['name_pt'],
          'beats_count': t['beats_count'],
          'description': t['description'],
          'image_asset': t['image_asset'],
          'display_order': t['display_order'] ?? 0,
          'is_active': 1,
          'cached_at': _now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await talaBatch.commit(noResult: true);
    await _deactivateMissing(db, 'local_talas', talas.map((t) => t['id'] as String));

    final sets = await _client.from('vms_beats_practice_sets').select().eq('is_active', true);
    final setsBatch = db.batch();
    for (final s in sets) {
      setsBatch.insert(
        'local_practice_sets',
        {
          'id': s['id'],
          'tala_id': s['tala_id'],
          'title': s['title'],
          'title_es': s['title_es'],
          'title_pt': s['title_pt'],
          'tempo_label': s['tempo_label'],
          'bpm_min': s['bpm_min'],
          'bpm_max': s['bpm_max'],
          'course_id': s['course_id'],
          'class_id': s['class_id'],
          'is_paid': (s['is_paid'] as bool) ? 1 : 0,
          'display_order': s['display_order'] ?? 0,
          'is_active': 1,
          'cached_at': _now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await setsBatch.commit(noResult: true);
    await _deactivateMissing(db, 'local_practice_sets', sets.map((s) => s['id'] as String));

    final tracks = await _client.from('vms_beats_tracks').select().eq('is_active', true);
    final existingTracks = await db.query(
      'local_tracks',
      columns: [
        'id',
        'local_path',
        'download_status',
        'bytes_downloaded',
        'retry_count',
        'downloaded_at',
        'downloaded_version',
        'encrypted_checksum_sha256',
      ],
    );
    final existingById = {for (final row in existingTracks) row['id'] as String: row};

    final tracksBatch = db.batch();
    for (final tr in tracks) {
      final id = tr['id'] as String;
      final existing = existingById[id];
      tracksBatch.insert(
        'local_tracks',
        {
          'id': id,
          'practice_set_id': tr['practice_set_id'],
          'title': tr['title'],
          'instrument': tr['instrument'],
          'bpm': tr['bpm'],
          'r2_object_key': tr['r2_object_key'],
          'file_size_bytes': tr['file_size_bytes'],
          'duration_seconds': tr['duration_seconds'],
          'checksum_sha256': tr['checksum_sha256'],
          'display_order': tr['display_order'] ?? 0,
          'is_active': 1,
          'server_updated_at': tr['updated_at'],
          'cached_at': _now,
          // Preserved from whatever was already on disk for this track.
          'local_path': existing?['local_path'],
          'download_status': existing?['download_status'] ?? 'not_downloaded',
          'bytes_downloaded': existing?['bytes_downloaded'] ?? 0,
          'retry_count': existing?['retry_count'] ?? 0,
          'downloaded_at': existing?['downloaded_at'],
          'downloaded_version': existing?['downloaded_version'],
          'encrypted_checksum_sha256': existing?['encrypted_checksum_sha256'],
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await tracksBatch.commit(noResult: true);
    await _deactivateMissing(db, 'local_tracks', tracks.map((t) => t['id'] as String));
  }

  Future<void> _deactivateMissing(Database db, String table, Iterable<String> keepIds) async {
    final ids = keepIds.toList();
    if (ids.isEmpty) {
      await db.rawUpdate('UPDATE $table SET is_active = 0');
      return;
    }
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.rawUpdate('UPDATE $table SET is_active = 0 WHERE id NOT IN ($placeholders)', ids);
  }

  Future<List<Map<String, dynamic>>> getCachedTalas() async {
    if (!offlineSupported) {
      final rows = await _client
          .from('vms_beats_talas')
          .select()
          .eq('is_active', true)
          .order('display_order');
      return _withEnglish(List<Map<String, dynamic>>.from(rows), 'name');
    }
    final db = await _localDb.database;
    return _withEnglish(
        await db.query('local_talas', where: 'is_active = 1', orderBy: 'display_order'), 'name');
  }

  Future<List<Map<String, dynamic>>> getCachedPracticeSets({String? talaId}) async {
    if (!offlineSupported) {
      var query = _client.from('vms_beats_practice_sets').select().eq('is_active', true);
      if (talaId != null) query = query.eq('tala_id', talaId);
      final rows = await query.order('display_order');
      return _withEnglish(List<Map<String, dynamic>>.from(rows), 'title');
    }
    final db = await _localDb.database;
    return _withEnglish(
      await db.query(
        'local_practice_sets',
        where: talaId == null ? 'is_active = 1' : 'is_active = 1 AND tala_id = ?',
        whereArgs: talaId == null ? null : [talaId],
        orderBy: 'display_order',
      ),
      'title',
    );
  }

  Future<List<Map<String, dynamic>>> getCachedTracks(String practiceSetId) async {
    if (!offlineSupported) {
      final rows = await _client
          .from('vms_beats_tracks')
          .select()
          .eq('is_active', true)
          .eq('practice_set_id', practiceSetId)
          .order('display_order');
      return List<Map<String, dynamic>>.from(rows);
    }
    final db = await _localDb.database;
    return db.query(
      'local_tracks',
      where: 'is_active = 1 AND practice_set_id = ?',
      whereArgs: [practiceSetId],
      orderBy: 'display_order',
    );
  }

  // ---------------------------------------------------------------------
  // Favorites
  // ---------------------------------------------------------------------

  Future<void> refreshFavorites(int studentId) async {
    if (!offlineSupported) return;
    final rows = await _client
        .from('vms_beats_favorites')
        .select('practice_set_id')
        .eq('student_id', studentId);

    final db = await _localDb.database;
    await db.delete('local_favorites');
    final batch = db.batch();
    for (final r in rows) {
      batch.insert(
        'local_favorites',
        {'practice_set_id': r['practice_set_id'], 'cached_at': _now},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<Set<String>> getCachedFavoriteIds() async {
    if (!offlineSupported) {
      final studentId = await _currentStudentId();
      if (studentId == null) return {};
      final rows = await _client
          .from('vms_beats_favorites')
          .select('practice_set_id')
          .eq('student_id', studentId);
      return rows.map<String>((r) => r['practice_set_id'] as String).toSet();
    }
    final db = await _localDb.database;
    final rows = await db.query('local_favorites', columns: ['practice_set_id']);
    return rows.map((r) => r['practice_set_id'] as String).toSet();
  }

  /// Writes through to Supabase first, then mirrors locally. Favorites are a
  /// light, infrequent write, so there's no offline queue for them; toggling
  /// while offline throws and the UI shows its normal network-error state.
  Future<void> setFavorite(int studentId, String practiceSetId, bool isFavorite) async {
    if (isFavorite) {
      await _client.from('vms_beats_favorites').upsert({
        'student_id': studentId,
        'practice_set_id': practiceSetId,
      }, onConflict: 'student_id,practice_set_id');
    } else {
      await _client
          .from('vms_beats_favorites')
          .delete()
          .eq('student_id', studentId)
          .eq('practice_set_id', practiceSetId);
    }
    if (!offlineSupported) return;

    final db = await _localDb.database;
    if (isFavorite) {
      await db.insert(
        'local_favorites',
        {'practice_set_id': practiceSetId, 'cached_at': _now},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } else {
      await db.delete('local_favorites', where: 'practice_set_id = ?', whereArgs: [practiceSetId]);
    }
  }

  // ---------------------------------------------------------------------
  // Practice history
  // ---------------------------------------------------------------------

  /// Native: writes the session locally first (so it shows in history
  /// immediately, even offline) and uploads best-effort; a session recorded
  /// offline stays `synced = 0` until a later `syncPendingPracticeSessions()`.
  /// Web: uploads directly. Safe to call repeatedly with the same [id] —
  /// it updates that session (used to checkpoint duration on each pause).
  Future<void> recordPracticeSession({
    required String id,
    required String practiceSetId,
    String? trackId,
    int? tempoBpm,
    Map<String, double>? instrumentMix,
    int? timerMinutes,
    bool loopEnabled = false,
    int? durationSeconds,
    required DateTime startedAt,
    DateTime? endedAt,
  }) async {
    final studentId = await _currentStudentId();
    if (studentId == null) return;

    final row = {
      'id': id,
      'student_id': studentId,
      'practice_set_id': practiceSetId,
      'track_id': trackId,
      'tempo_bpm': tempoBpm,
      'instrument_mix': instrumentMix,
      'timer_minutes': timerMinutes,
      'loop_enabled': loopEnabled,
      'duration_seconds': durationSeconds,
      'started_at': startedAt.toUtc().toIso8601String(),
      'ended_at': endedAt?.toUtc().toIso8601String(),
    };

    if (!offlineSupported) {
      await _client.from('vms_beats_practice_sessions').upsert(row);
      return;
    }

    final db = await _localDb.database;
    await db.insert(
      'local_practice_sessions',
      {
        'id': id,
        'practice_set_id': practiceSetId,
        'track_id': trackId,
        'tempo_bpm': tempoBpm,
        'instrument_mix': instrumentMix == null ? null : jsonEncode(instrumentMix),
        'timer_minutes': timerMinutes,
        'loop_enabled': loopEnabled ? 1 : 0,
        'duration_seconds': durationSeconds,
        'started_at': startedAt.toUtc().toIso8601String(),
        'ended_at': endedAt?.toUtc().toIso8601String(),
        'synced': 0,
        'student_id': studentId,
        'cached_at': _now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await syncPendingPracticeSessions();
  }

  /// Uploads this user's sessions that haven't reached Supabase yet (e.g.
  /// recorded offline). Safe to call whenever a connection may be back.
  Future<void> syncPendingPracticeSessions() async {
    if (!offlineSupported) return;
    final studentId = await _currentStudentId();
    if (studentId == null) return;

    final db = await _localDb.database;
    final pending = await db.query('local_practice_sessions',
        where: 'synced = 0 AND student_id = ?', whereArgs: [studentId]);

    for (final row in pending) {
      try {
        await _client.from('vms_beats_practice_sessions').upsert({
          'id': row['id'],
          'student_id': studentId,
          'practice_set_id': row['practice_set_id'],
          'track_id': row['track_id'],
          'tempo_bpm': row['tempo_bpm'],
          'instrument_mix':
              row['instrument_mix'] == null ? null : jsonDecode(row['instrument_mix'] as String),
          'timer_minutes': row['timer_minutes'],
          'loop_enabled': (row['loop_enabled'] as int) == 1,
          'duration_seconds': row['duration_seconds'],
          'started_at': row['started_at'],
          'ended_at': row['ended_at'],
        });
        await db.update('local_practice_sessions', {'synced': 1},
            where: 'id = ?', whereArgs: [row['id']]);
      } on PostgrestException catch (e) {
        // The server refused this row outright (e.g. its practice set was
        // deleted); retrying can never succeed, so drop it.
        debugPrint('Dropping unsyncable practice session ${row['id']}: ${e.code}');
        await db.delete('local_practice_sessions', where: 'id = ?', whereArgs: [row['id']]);
      } catch (_) {
        // Offline or transient — leave it pending for the next attempt.
        break;
      }
    }
  }

  /// Pulls recent history from Supabase into the cache, so sessions
  /// recorded on another device also show up here offline.
  Future<void> refreshPracticeHistory(int studentId, {int limit = 50}) async {
    if (!offlineSupported) return;
    final rows = await _client
        .from('vms_beats_practice_sessions')
        .select()
        .eq('student_id', studentId)
        .order('started_at', ascending: false)
        .limit(limit);

    final db = await _localDb.database;
    final batch = db.batch();
    for (final r in rows) {
      batch.insert(
        'local_practice_sessions',
        {
          'id': r['id'],
          'practice_set_id': r['practice_set_id'],
          'track_id': r['track_id'],
          'tempo_bpm': r['tempo_bpm'],
          'instrument_mix': r['instrument_mix'] == null ? null : jsonEncode(r['instrument_mix']),
          'timer_minutes': r['timer_minutes'],
          'loop_enabled': (r['loop_enabled'] as bool) ? 1 : 0,
          'duration_seconds': r['duration_seconds'],
          'started_at': r['started_at'],
          'ended_at': r['ended_at'],
          'synced': 1,
          'student_id': studentId,
          'cached_at': _now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getCachedPracticeHistory({int limit = 50}) async {
    final studentId = await _currentStudentId();
    if (studentId == null) return [];

    if (!offlineSupported) {
      final rows = await _client
          .from('vms_beats_practice_sessions')
          .select()
          .eq('student_id', studentId)
          .order('started_at', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(rows);
    }
    final db = await _localDb.database;
    return db.query('local_practice_sessions',
        where: 'student_id = ?',
        whereArgs: [studentId],
        orderBy: 'started_at DESC',
        limit: limit);
  }

  // ---------------------------------------------------------------------

  /// Best-effort background refresh of everything cacheable for this
  /// student. Fire-and-forget after a successful profile load; a failure
  /// just leaves the cache as fresh as it was last time.
  ///
  /// A successful catalog pull (so: online) also starts the background
  /// download of every track the user can access — new ones, changed ones,
  /// and ones that failed earlier and are still under the retry cap.
  Future<void> refreshAll(int studentId) async {
    if (!offlineSupported) return;
    try {
      await refreshCatalog();
      DownloadManager().syncAll();
      await refreshFavorites(studentId);
      await refreshPracticeHistory(studentId);
      await syncPendingPracticeSessions();
    } catch (e) {
      debugPrint('⚠️ Background cache refresh failed (will retry next time): $e');
    }
  }
}
