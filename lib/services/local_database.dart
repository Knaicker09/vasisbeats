import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// On-device cache: catalog text (talas/practice sets/tracks), the signed-in
/// user's profile, favorites and practice history, plus each track's
/// download state — everything the app needs to render fully offline, not
/// just the downloaded audio bytes. Refreshed opportunistically whenever a
/// network call succeeds (see OfflineCacheService); always read-first-from
/// here, never blocked on a network round trip.
class LocalDatabase {
  static Database? _db;

  Future<Database> get database async {
    final existing = _db;
    if (existing != null) return existing;
    final opened = await _open();
    _db = opened;
    return opened;
  }

  Future<Database> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = join(dir.path, 'vasis_beats_cache.db');
    return openDatabase(
      path,
      version: 3,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await _createErrorLogTable(db);
        if (oldVersion < 3) {
          await db.execute('ALTER TABLE local_tracks ADD COLUMN downloaded_version TEXT');
          await db.execute('ALTER TABLE local_profile ADD COLUMN auth_user_id TEXT');
          await db.execute('ALTER TABLE local_practice_sessions ADD COLUMN student_id INTEGER');
        }
      },
      onCreate: (db, version) async {
        await _createErrorLogTable(db);
        await db.execute('''
          CREATE TABLE local_profile (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            student_id INTEGER NOT NULL,
            email TEXT NOT NULL,
            display_name TEXT NOT NULL,
            role TEXT NOT NULL,
            account_type TEXT NOT NULL,
            donation_amount REAL NOT NULL,
            donation_currency TEXT NOT NULL,
            cached_at TEXT NOT NULL,
            auth_user_id TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE local_talas (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            name_es TEXT,
            name_pt TEXT,
            beats_count INTEGER,
            description TEXT,
            image_asset TEXT,
            display_order INTEGER NOT NULL DEFAULT 0,
            is_active INTEGER NOT NULL DEFAULT 1,
            cached_at TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE local_practice_sets (
            id TEXT PRIMARY KEY,
            tala_id TEXT NOT NULL,
            title TEXT NOT NULL,
            title_es TEXT,
            title_pt TEXT,
            tempo_label TEXT NOT NULL,
            bpm_min INTEGER NOT NULL,
            bpm_max INTEGER NOT NULL,
            course_id INTEGER,
            class_id INTEGER,
            is_paid INTEGER NOT NULL DEFAULT 1,
            display_order INTEGER NOT NULL DEFAULT 0,
            is_active INTEGER NOT NULL DEFAULT 1,
            cached_at TEXT NOT NULL
          )
        ''');

        // Download state lives on the same row as the catalog metadata —
        // it's always exactly one-to-one with a track, so a separate
        // "download_manifest" table would only add a join for no benefit.
        await db.execute('''
          CREATE TABLE local_tracks (
            id TEXT PRIMARY KEY,
            practice_set_id TEXT NOT NULL,
            title TEXT NOT NULL,
            instrument TEXT NOT NULL,
            bpm INTEGER NOT NULL,
            r2_object_key TEXT NOT NULL,
            file_size_bytes INTEGER,
            duration_seconds REAL,
            checksum_sha256 TEXT,
            display_order INTEGER NOT NULL DEFAULT 0,
            is_active INTEGER NOT NULL DEFAULT 1,
            server_updated_at TEXT,
            cached_at TEXT NOT NULL,
            local_path TEXT,
            download_status TEXT NOT NULL DEFAULT 'not_downloaded',
            bytes_downloaded INTEGER NOT NULL DEFAULT 0,
            retry_count INTEGER NOT NULL DEFAULT 0,
            downloaded_at TEXT,
            -- server_updated_at at the moment the file was downloaded; if the
            -- catalog later reports a different server_updated_at, the
            -- downloaded copy is stale and an update is offered.
            downloaded_version TEXT,
            -- Checksum of the ENCRYPTED file on disk, computed locally right
            -- after encryption. checksum_sha256 above is the server's
            -- plaintext checksum, used once at download time before
            -- encrypting; this one is what startup integrity checks
            -- re-verify against, since the file on disk is never plaintext.
            encrypted_checksum_sha256 TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE local_favorites (
            practice_set_id TEXT PRIMARY KEY,
            cached_at TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE local_practice_sessions (
            id TEXT PRIMARY KEY,
            practice_set_id TEXT NOT NULL,
            track_id TEXT,
            tempo_bpm INTEGER,
            instrument_mix TEXT,
            timer_minutes INTEGER,
            loop_enabled INTEGER NOT NULL DEFAULT 0,
            duration_seconds INTEGER,
            started_at TEXT NOT NULL,
            ended_at TEXT,
            synced INTEGER NOT NULL DEFAULT 0,
            cached_at TEXT NOT NULL,
            student_id INTEGER
          )
        ''');
        await db.execute(
            'CREATE INDEX idx_local_practice_sessions_started ON local_practice_sessions (started_at DESC)');
      },
    );
  }

  /// Pending operational error-log rows, flushed to vms_beats_error_log
  /// by ErrorLogService once there's a connection.
  Future<void> _createErrorLogTable(Database db) async {
    await db.execute('''
      CREATE TABLE local_error_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        student_id INTEGER,
        category TEXT NOT NULL,
        code TEXT NOT NULL,
        context TEXT,
        app_version TEXT,
        platform TEXT,
        created_at TEXT NOT NULL
      )
    ''');
  }
}
