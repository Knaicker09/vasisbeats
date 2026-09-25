import 'dart:async';
import 'dart:convert';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../platform_support.dart';
import 'local_database.dart';

class LogCategory {
  static const auth = 'auth';
  static const playback = 'playback';
  static const download = 'download';
}

/// Closed vocabulary — the only things that ever reach vms_beats_error_log
/// describing *what* failed. No exception messages or stack traces.
class LogCode {
  static const otpSendFailed = 'otp_send_failed';
  static const otpVerifyFailed = 'otp_verify_failed';
  static const otpExpired = 'otp_expired';
  static const passwordSignInFailed = 'password_sign_in_failed';
  static const passwordResetFailed = 'password_reset_failed';
  static const sessionRefreshFailed = 'session_refresh_failed';

  static const playbackSourceError = 'playback_source_error';
  static const playbackLoadFailed = 'playback_load_failed';

  static const downloadNetworkFailure = 'download_network_failure';
  static const downloadHttpError = 'download_http_error';
  static const downloadChecksumMismatch = 'download_checksum_mismatch';
  static const downloadDiskFull = 'download_disk_full';
  static const downloadFailed = 'download_failed';
}

/// Structured, privacy-respecting operational logging of auth, playback and
/// download failures, for spotting recurring problems across users.
///
/// Rows are written to a local queue first and flushed to
/// `vms_beats_error_log` whenever a connection allows, because these
/// failures overwhelmingly happen when the network is the problem. Only
/// whitelisted context keys are kept; the student id is attached only when
/// signed in; nothing here ever throws into the caller.
class ErrorLogService {
  ErrorLogService._();
  static final ErrorLogService instance = ErrorLogService._();

  static const _allowedContextKeys = {
    'track_id',
    'practice_set_id',
    'http_status',
    'attempt_number',
  };
  static const _maxQueuedRows = 200;

  final LocalDatabase _localDb = LocalDatabase();
  bool _flushing = false;
  String? _appVersion;

  Future<void> log(
    String category,
    String code, {
    Map<String, Object?> context = const {},
  }) async {
    try {
      final safeContext = {
        for (final e in context.entries)
          if (_allowedContextKeys.contains(e.key) && e.value != null) e.key: e.value,
      };

      if (!offlineSupported) {
        // Web is online-only: no local queue, send straight away.
        await Supabase.instance.client.from('vms_beats_error_log').insert({
          'category': category,
          'code': code,
          'context': safeContext.isEmpty ? null : safeContext,
          'app_version': await _getAppVersion(),
          'platform': platformName,
        });
        return;
      }

      final db = await _localDb.database;
      int? studentId;
      if (_isSignedIn()) {
        final rows = await db.query('local_profile', columns: ['student_id'], limit: 1);
        if (rows.isNotEmpty) studentId = rows.first['student_id'] as int;
      }

      await db.insert('local_error_log', {
        'student_id': studentId,
        'category': category,
        'code': code,
        'context': safeContext.isEmpty ? null : jsonEncode(safeContext),
        'app_version': await _getAppVersion(),
        'platform': platformName,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      await db.execute(
        'DELETE FROM local_error_log WHERE id NOT IN '
        '(SELECT id FROM local_error_log ORDER BY id DESC LIMIT $_maxQueuedRows)',
      );

      unawaited(flush());
    } catch (_) {
      // Logging must never be the thing that fails.
    }
  }

  /// Pushes queued rows to Supabase. A network failure leaves the rest
  /// queued for next time; a row the server rejects outright is dropped,
  /// since retrying it can never succeed.
  Future<void> flush() async {
    if (_flushing || !offlineSupported) return;
    _flushing = true;
    try {
      final db = await _localDb.database;
      final pending = await db.query('local_error_log', orderBy: 'id', limit: 100);
      final signedIn = _isSignedIn();

      for (final row in pending) {
        try {
          await Supabase.instance.client.from('vms_beats_error_log').insert({
            'student_id': signedIn ? row['student_id'] : null,
            'category': row['category'],
            'code': row['code'],
            'context': row['context'] == null ? null : jsonDecode(row['context'] as String),
            'app_version': row['app_version'],
            'platform': row['platform'],
            'created_at': row['created_at'],
          });
        } on PostgrestException {
          // Rejected by the server — drop it below.
        } catch (_) {
          break;
        }
        await db.delete('local_error_log', where: 'id = ?', whereArgs: [row['id']]);
      }
    } catch (_) {
      // Best effort.
    } finally {
      _flushing = false;
    }
  }

  bool _isSignedIn() {
    try {
      return Supabase.instance.client.auth.currentUser != null;
    } catch (_) {
      return false;
    }
  }

  Future<String> _getAppVersion() async {
    final cached = _appVersion;
    if (cached != null) return cached;
    final info = await PackageInfo.fromPlatform();
    return _appVersion = '${info.version}+${info.buildNumber}';
  }
}
