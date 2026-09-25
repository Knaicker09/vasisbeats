import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'error_log_service.dart';
import 'local_database.dart';
import 'track_encryption_service.dart';

const int _maxRetries = 3;

/// Downloads and manages on-device audio for `vms_beats_tracks`: resumable
/// and retryable transfers, post-download integrity checks, update detection,
/// and encryption at rest (see TrackEncryptionService). Only the encrypted
/// form lives in the app's documents directory; plaintext exists only in a
/// temp file while downloading (until the checksum is verified and the file
/// encrypted) and while a track is loaded for playback (preparePlayableFile).
///
/// Native platforms only — web is online-only and streams instead.
///
/// Catalog metadata is cached separately by OfflineCacheService; this class
/// owns the bytes and the download-state columns on `local_tracks`.
class DownloadManager {
  DownloadManager._();
  static final DownloadManager _instance = DownloadManager._();
  factory DownloadManager() => _instance;

  final LocalDatabase _localDb = LocalDatabase();
  final TrackEncryptionService _encryption = TrackEncryptionService();
  final Dio _dio = Dio();

  /// Live per-track progress (0.0–1.0) for tracks currently downloading.
  final ValueNotifier<Map<String, double>> progress = ValueNotifier({});

  /// Where a track's audio can be fetched (or streamed, on web): the
  /// website's proxy route, which streams the R2 object and forwards Range
  /// headers, so resume works with no separate signing step here.
  ///
  /// KNOWN GAP: that route has no auth check of its own (a website-side
  /// change). Paid tracks are additionally hidden at the database — a user
  /// who isn't entitled never receives their object keys.
  static String urlForObjectKey(String r2ObjectKey) => Uri.https(
        'www.vasisstudio.com',
        '/api/files/read',
        {'key': r2ObjectKey},
      ).toString();

  /// A downloaded track whose catalog entry has changed since it was
  /// downloaded (a re-uploaded/edited track).
  static bool isStale(Map<String, dynamic> row) {
    if (row['download_status'] != 'complete') return false;
    final downloaded = row['downloaded_version'];
    final current = row['server_updated_at'];
    return downloaded != null && current != null && downloaded != current;
  }

  Future<Directory> _tracksDir() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docsDir.path, 'vasis_beats_tracks'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Ephemeral directory for the decrypted copy a loaded track plays from —
  /// never the permanent home for a track (that's the encrypted file).
  Future<Directory> _playbackTempDir() async {
    final tempDir = await getTemporaryDirectory();
    final dir = Directory(p.join(tempDir.path, 'vasis_beats_playback'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Downloads (or resumes) one track. Safe to call repeatedly — a track
  /// already `complete` and verified returns immediately. Automatic callers
  /// stop after [_maxRetries] consecutive failures; pass
  /// [userInitiated] for an explicit retry/update, which starts fresh.
  Future<void> downloadTrack(String trackId, {bool userInitiated = false}) async {
    final db = await _localDb.database;
    final rows = await db.query('local_tracks', where: 'id = ?', whereArgs: [trackId], limit: 1);
    if (rows.isEmpty) {
      throw StateError('Unknown track $trackId — refresh the catalog first.');
    }
    final track = rows.first;

    if (track['download_status'] == 'complete' &&
        await _verifyEncryptedOnDisk(
            track['local_path'] as String?, track['encrypted_checksum_sha256'] as String?)) {
      return;
    }

    final retryCount = userInitiated ? 0 : (track['retry_count'] as int?) ?? 0;
    if (retryCount >= _maxRetries) {
      await _updateTrack(trackId, {'download_status': 'failed'});
      return;
    }

    final dir = await _tracksDir();
    final plainTempPath = p.join(dir.path, '$trackId.download.tmp');
    final encryptedPath = p.join(dir.path, '$trackId.enc');
    final plainTempFile = File(plainTempPath);

    await _updateTrack(trackId, {'download_status': 'downloading', 'retry_count': retryCount});
    _setProgress(trackId, 0);

    try {
      final url = urlForObjectKey(track['r2_object_key'] as String);
      final expectedSize = track['file_size_bytes'] as int?;
      final expectedPlainChecksum = track['checksum_sha256'] as String?;

      // First try resuming a partial file; if the server ignored the Range
      // header (so the resumed file is wrong), start over once from zero.
      var verified = false;
      for (var attempt = 0; attempt < 2 && !verified; attempt++) {
        final resumeFrom =
            attempt == 0 && await plainTempFile.exists() ? await plainTempFile.length() : 0;
        if (resumeFrom == 0 && await plainTempFile.exists()) await plainTempFile.delete();

        await _dio.download(
          url,
          plainTempPath,
          deleteOnError: false,
          fileAccessMode: resumeFrom > 0 ? FileAccessMode.append : FileAccessMode.write,
          options: Options(headers: resumeFrom > 0 ? {'Range': 'bytes=$resumeFrom-'} : null),
          onReceiveProgress: (received, total) {
            final soFar = resumeFrom + received;
            final full = expectedSize ?? (total > 0 ? resumeFrom + total : 0);
            if (full > 0) _setProgress(trackId, (soFar / full).clamp(0.0, 1.0));
          },
        );

        verified = await _verifyPlainOnDisk(plainTempPath, expectedPlainChecksum, expectedSize);
        if (!verified && await plainTempFile.exists()) await plainTempFile.delete();
      }

      if (!verified) {
        debugPrint('⚠️ Integrity check failed for track $trackId.');
        ErrorLogService.instance.log(
          LogCategory.download,
          LogCode.downloadChecksumMismatch,
          context: {'track_id': trackId, 'attempt_number': retryCount + 1},
        );
        await _updateTrack(trackId, {
          'download_status': 'failed',
          'bytes_downloaded': 0,
          'retry_count': retryCount + 1,
        });
        return;
      }

      // Verified against the server's checksum — encrypt, then discard the
      // plaintext temp file so it never persists past this point.
      final encryptedFile = File(encryptedPath);
      await _encryption.encryptFile(plainTempFile, encryptedFile);
      await plainTempFile.delete();

      final encryptedBytes = await encryptedFile.readAsBytes();
      await _updateTrack(trackId, {
        'download_status': 'complete',
        'local_path': encryptedPath,
        'bytes_downloaded': encryptedBytes.length,
        'downloaded_at': DateTime.now().toUtc().toIso8601String(),
        'downloaded_version': track['server_updated_at'],
        'retry_count': 0,
        'encrypted_checksum_sha256': sha256.convert(encryptedBytes).toString(),
      });
    } catch (e) {
      debugPrint('⚠️ Download failed for track $trackId: $e');
      final failure = _classifyFailure(e);
      ErrorLogService.instance.log(
        LogCategory.download,
        failure.code,
        context: {
          'track_id': trackId,
          'attempt_number': retryCount + 1,
          'http_status': failure.httpStatus,
        },
      );
      await _updateTrack(trackId, {'download_status': 'failed', 'retry_count': retryCount + 1});
    } finally {
      _setProgress(trackId, null);
    }
  }

  /// Downloads every track of a practice set that isn't already downloaded
  /// and current. Returns how many tracks failed.
  Future<int> downloadPracticeSet(String practiceSetId, {bool userInitiated = true}) async {
    final db = await _localDb.database;
    final tracks = await db.query('local_tracks',
        where: 'practice_set_id = ? AND is_active = 1', whereArgs: [practiceSetId]);
    return _downloadAll(tracks, userInitiated: userInitiated);
  }

  /// Downloads all practice sets linked to LMS courses (`course_id` set),
  /// or just one course's if [courseId] is given.
  Future<int> downloadCourseContent({int? courseId, bool userInitiated = true}) async {
    final db = await _localDb.database;
    final tracks = await db.rawQuery('''
      SELECT t.* FROM local_tracks t
      JOIN local_practice_sets s ON s.id = t.practice_set_id
      WHERE t.is_active = 1 AND s.is_active = 1
        AND ${courseId == null ? 's.course_id IS NOT NULL' : 's.course_id = ?'}
    ''', courseId == null ? [] : [courseId]);
    return _downloadAll(tracks, userInitiated: userInitiated);
  }

  Future<int> _downloadAll(List<Map<String, Object?>> tracks, {required bool userInitiated}) async {
    var failed = 0;
    for (final t in tracks) {
      final row = Map<String, dynamic>.from(t);
      final needsWork = row['download_status'] != 'complete' || isStale(row);
      if (!needsWork) continue;
      if (isStale(row)) await deleteDownload(row['id'] as String);
      await downloadTrack(row['id'] as String, userInitiated: userInitiated);
      final after = await _statusOf(row['id'] as String);
      if (after != 'complete') failed++;
    }
    return failed;
  }

  /// Re-downloads every downloaded track whose catalog entry has changed.
  Future<int> updateStaleTracks() async {
    final stale = await getStaleTracks();
    return _downloadAll(stale, userInitiated: true);
  }

  Future<List<Map<String, dynamic>>> getStaleTracks() async {
    final db = await _localDb.database;
    final rows = await db.query('local_tracks',
        where: "download_status = 'complete' AND is_active = 1");
    return rows.map((r) => Map<String, dynamic>.from(r)).where(isStale).toList();
  }

  /// Automatic retry of failed tracks (up to the retry cap). Called when
  /// connectivity returns and at startup; explicit retries use
  /// downloadTrack(userInitiated: true).
  Future<void> retryFailedDownloads() async {
    final db = await _localDb.database;
    final failed = await db.query('local_tracks',
        where: "download_status = 'failed' AND retry_count < ?", whereArgs: [_maxRetries]);
    for (final row in failed) {
      await downloadTrack(row['id'] as String);
    }
  }

  /// Startup integrity sweep. Anything marked `complete` has its encrypted
  /// file re-verified against the checksum recorded when it was written
  /// (catching partial writes / disk corruption); bad entries reset to
  /// `failed` so the app can tell the user and offer a retry. Downloads that
  /// were interrupted by the app being killed go back to `not_downloaded`
  /// (their partial file is kept and resumed on the next attempt).
  Future<void> verifyDownloadedTracks() async {
    final db = await _localDb.database;
    await db.update('local_tracks', {'download_status': 'not_downloaded'},
        where: "download_status = 'downloading'");

    final complete = await db.query('local_tracks', where: "download_status = 'complete'");
    for (final row in complete) {
      final ok = await _verifyEncryptedOnDisk(
          row['local_path'] as String?, row['encrypted_checksum_sha256'] as String?);
      if (!ok) {
        await _updateTrack(row['id'] as String, {
          'download_status': 'failed',
          'local_path': null,
          'bytes_downloaded': 0,
          'retry_count': 0,
          'encrypted_checksum_sha256': null,
          'downloaded_version': null,
        });
      }
    }
  }

  /// Per practice set: how many tracks exist, are downloaded, failed, or
  /// out of date — for the badges in the Practice list.
  Future<Map<String, ({int total, int complete, int failed, int stale})>> getSetSummaries() async {
    final db = await _localDb.database;
    final rows = await db.query('local_tracks', where: 'is_active = 1');
    final out = <String, ({int total, int complete, int failed, int stale})>{};
    for (final r in rows) {
      final row = Map<String, dynamic>.from(r);
      final id = row['practice_set_id'] as String;
      final cur = out[id] ?? (total: 0, complete: 0, failed: 0, stale: 0);
      out[id] = (
        total: cur.total + 1,
        complete: cur.complete + (row['download_status'] == 'complete' ? 1 : 0),
        failed: cur.failed + (row['download_status'] == 'failed' ? 1 : 0),
        stale: cur.stale + (isStale(row) ? 1 : 0),
      );
    }
    return out;
  }

  /// All tracks currently downloaded (Profile's downloaded-content list).
  Future<List<Map<String, dynamic>>> getDownloadedTracks() async {
    final db = await _localDb.database;
    final rows = await db.query('local_tracks',
        where: "download_status = 'complete'", orderBy: 'title');
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  /// Deletes a track's encrypted file and resets it to `not_downloaded`.
  Future<void> deleteDownload(String trackId) async {
    final db = await _localDb.database;
    final rows = await db.query('local_tracks', where: 'id = ?', whereArgs: [trackId], limit: 1);
    if (rows.isEmpty) return;

    final localPath = rows.first['local_path'] as String?;
    if (localPath != null) {
      final file = File(localPath);
      if (await file.exists()) await file.delete();
    }
    await _updateTrack(trackId, {
      'download_status': 'not_downloaded',
      'local_path': null,
      'bytes_downloaded': 0,
      'retry_count': 0,
      'downloaded_at': null,
      'downloaded_version': null,
      'encrypted_checksum_sha256': null,
    });
  }

  /// Decrypts a downloaded track to a temp file a player can open and
  /// returns its path. Call [cleanupTempPlaybackFiles] once playback of it
  /// has stopped.
  Future<String> preparePlayableFile(String trackId) async {
    final db = await _localDb.database;
    final rows = await db.query('local_tracks', where: 'id = ?', whereArgs: [trackId], limit: 1);
    if (rows.isEmpty) {
      throw StateError('Unknown track $trackId.');
    }
    final track = rows.first;
    if (track['download_status'] != 'complete') {
      throw StateError('Track $trackId is not downloaded (status: ${track['download_status']}).');
    }

    final encryptedFile = File(track['local_path'] as String);
    final tempDir = await _playbackTempDir();
    final outputFile = File(p.join(tempDir.path, '$trackId.mp3'));
    await _encryption.decryptFile(encryptedFile, outputFile);
    return outputFile.path;
  }

  /// Wipes every decrypted playback temp file. Call after stopping playback
  /// and on app start.
  Future<void> cleanupTempPlaybackFiles() async {
    final dir = await _playbackTempDir();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  void _setProgress(String trackId, double? value) {
    final current = progress.value;
    // Throttle: only publish when it moves by at least 1%.
    if (value != null && current[trackId] != null && (value - current[trackId]!).abs() < 0.01) {
      return;
    }
    final next = Map<String, double>.from(current);
    if (value == null) {
      next.remove(trackId);
    } else {
      next[trackId] = value;
    }
    progress.value = next;
  }

  Future<String?> _statusOf(String trackId) async {
    final db = await _localDb.database;
    final rows = await db.query('local_tracks',
        columns: ['download_status'], where: 'id = ?', whereArgs: [trackId], limit: 1);
    return rows.isEmpty ? null : rows.first['download_status'] as String?;
  }

  ({String code, int? httpStatus}) _classifyFailure(Object e) {
    final inner = e is DioException ? (e.error ?? e) : e;
    if (inner is FileSystemException) {
      // 28 = ENOSPC (POSIX), 112 = ERROR_DISK_FULL (Windows)
      final osCode = inner.osError?.errorCode;
      if (osCode == 28 || osCode == 112) {
        return (code: LogCode.downloadDiskFull, httpStatus: null);
      }
    }
    if (e is DioException) {
      final status = e.response?.statusCode;
      if (status != null) {
        return (code: LogCode.downloadHttpError, httpStatus: status);
      }
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        return (code: LogCode.downloadNetworkFailure, httpStatus: null);
      }
    }
    return (code: LogCode.downloadFailed, httpStatus: null);
  }

  Future<bool> _verifyPlainOnDisk(String path, String? expectedChecksum, int? expectedSize) async {
    final file = File(path);
    if (!await file.exists()) return false;
    if (expectedSize != null && await file.length() != expectedSize) return false;
    if (expectedChecksum == null || expectedChecksum.isEmpty) {
      // No checksum recorded server-side yet — existence (and size, when
      // known) is all that can be checked.
      return true;
    }
    final bytes = await file.readAsBytes();
    return sha256.convert(bytes).toString() == expectedChecksum;
  }

  Future<bool> _verifyEncryptedOnDisk(String? localPath, String? expectedEncryptedChecksum) async {
    if (localPath == null || expectedEncryptedChecksum == null) return false;
    final file = File(localPath);
    if (!await file.exists()) return false;
    final bytes = await file.readAsBytes();
    return sha256.convert(bytes).toString() == expectedEncryptedChecksum;
  }

  Future<void> _updateTrack(String trackId, Map<String, Object?> values) async {
    final db = await _localDb.database;
    await db.update('local_tracks', values,
        where: 'id = ?', whereArgs: [trackId], conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
