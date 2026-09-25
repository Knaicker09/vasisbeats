import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../platform_support.dart';
import 'beats_profile_service.dart';
import 'download_manager.dart';
import 'error_log_service.dart';
import 'offline_cache_service.dart';
import 'practice_audio_handler.dart';
import 'practice_settings_service.dart';

/// Thrown when a paid practice set is opened by someone on the free tier.
class LockedContentException implements Exception {
  final String practiceSetTitle;
  LockedContentException(this.practiceSetTitle);
  @override
  String toString() => 'LockedContentException($practiceSetTitle)';
}

bool isPaidSet(Map<String, dynamic> practiceSet) {
  final v = practiceSet['is_paid'];
  return v == true || v == 1;
}

/// Tala/practice-set-oriented playback + session state. Owns the
/// ValueNotifiers the Practice screen binds to and coordinates the audio
/// engine (PracticeAudioHandler), the catalog (OfflineCacheService),
/// downloads (DownloadManager, native only), saved settings and practice
/// session recording.
///
/// Saved settings — tempo, loop, timer length and per-instrument volumes —
/// are stored per practice set on every change and applied when that set is
/// next loaded, so playback starts exactly as it was left.
class PracticeController {
  final PracticeAudioHandler _audioHandler;
  final OfflineCacheService _cache = OfflineCacheService();
  final PracticeSettingsService _settings = PracticeSettingsService.instance;

  PracticeController(this._audioHandler) {
    _audioHandler.playbackState.listen((state) {
      isPlayingNotifier.value = state.playing;
    });
    isPlayingNotifier.addListener(_onPlayingChanged);
  }

  DownloadManager get _downloads => DownloadManager();

  final currentPracticeSetNotifier = ValueNotifier<Map<String, dynamic>?>(null);
  final isPlayingNotifier = ValueNotifier<bool>(false);
  final currentBpmNotifier = ValueNotifier<int>(0);
  final loopEnabledNotifier = ValueNotifier<bool>(false);
  final stemVolumesNotifier = ValueNotifier<Map<String, double>>({});

  /// The chosen timer length (persisted); null = no timer.
  final timerMinutesNotifier = ValueNotifier<int?>(null);

  /// Time left on a running timer; null until playback starts.
  final timerRemainingNotifier = ValueNotifier<Duration?>(null);

  int _baseBpm = 0;
  String? _sessionId;
  String? _practiceSetId;
  String? _trackId;
  DateTime? _startedAt;
  final Stopwatch _played = Stopwatch();
  Timer? _ticker;
  Timer? _saveDebounce;

  /// Each instrument in the loaded set may have several tracks — real
  /// recordings at different BPMs, not a live-stretchable single file — so
  /// picking one per instrument for a given target tempo is a running
  /// concern, not a one-off at load time. [_tracksByInstrument] holds every
  /// downloaded/available track for the current set, sorted by BPM;
  /// [_selectedTrackByInstrument] is whichever one is actually loaded right
  /// now, per instrument. [_primaryInstrument] mirrors what was passed to
  /// PracticeAudioHandler.loadStems.
  Map<String, List<Map<String, dynamic>>> _tracksByInstrument = {};
  Map<String, Map<String, dynamic>> _selectedTrackByInstrument = {};
  String? _primaryInstrument;
  Timer? _trackSwapDebounce;

  /// Loads a practice set and applies its saved settings. Throws
  /// [LockedContentException] for a paid set on the free tier. Native
  /// platforms play downloaded (decrypted) files and skip any tracks not
  /// downloaded; web streams every track.
  Future<void> loadPracticeSet(Map<String, dynamic> practiceSet) async {
    try {
      await _load(practiceSet);
    } on LockedContentException {
      rethrow;
    } catch (_) {
      ErrorLogService.instance.log(
        LogCategory.playback,
        LogCode.playbackLoadFailed,
        context: {'practice_set_id': practiceSet['id'], 'track_id': _trackId},
      );
      rethrow;
    }
  }

  Future<void> _load(Map<String, dynamic> practiceSet) async {
    if (isPaidSet(practiceSet) && !await BeatsProfileService().isCurrentUserPaid()) {
      throw LockedContentException(practiceSet['title'] as String? ?? '');
    }

    await _releaseCurrentSet();
    _practiceSetId = practiceSet['id'] as String;
    currentPracticeSetNotifier.value = practiceSet;

    final tracks = await _cache.getCachedTracks(_practiceSetId!);
    final playable = offlineSupported
        ? tracks.where((t) => t['download_status'] == 'complete').toList()
        : tracks;

    if (playable.isEmpty) {
      stemVolumesNotifier.value = {};
      return;
    }

    // Group by instrument, sorted by BPM — each instrument here is a ladder
    // of real recordings, not one file to be stretched across the whole
    // tempo range (today's catalog has exactly one instrument per set, but
    // this holds for a future true multi-instrument mix too).
    _tracksByInstrument = {};
    for (final track in playable) {
      (_tracksByInstrument[track['instrument'] as String] ??= []).add(track);
    }
    for (final list in _tracksByInstrument.values) {
      list.sort((a, b) => (a['bpm'] as int).compareTo(b['bpm'] as int));
    }

    _primaryInstrument = _tracksByInstrument.containsKey('full_mix')
        ? 'full_mix'
        : _tracksByInstrument.keys.first;

    final saved = await _settings.load(_practiceSetId!);
    final minBpm = (practiceSet['bpm_min'] as num?)?.toInt();
    final maxBpm = (practiceSet['bpm_max'] as num?)?.toInt();
    // Default to the slowest available recording, same as picking the first
    // (lowest-BPM) track used to do before this was ladder-aware.
    var bpm = saved?.bpm ?? _tracksByInstrument[_primaryInstrument]!.first['bpm'] as int;
    if (minBpm != null && maxBpm != null && minBpm <= maxBpm) {
      bpm = bpm.clamp(minBpm, maxBpm);
    }

    _selectedTrackByInstrument = {};
    final sources = <String, String>{};
    for (final entry in _tracksByInstrument.entries) {
      final nearest = _nearestTrack(entry.value, bpm);
      _selectedTrackByInstrument[entry.key] = nearest;
      sources[entry.key] = offlineSupported
          ? await _downloads.preparePlayableFile(nearest['id'] as String)
          : DownloadManager.urlForObjectKey(nearest['r2_object_key'] as String);
    }

    final primaryTrack = _selectedTrackByInstrument[_primaryInstrument]!;
    _trackId = primaryTrack['id'] as String;
    _baseBpm = primaryTrack['bpm'] as int;

    final volumes = {
      for (final i in sources.keys) i: (saved?.stemVolumes[i] ?? 1.0).clamp(0.0, 1.0).toDouble(),
    };

    await _audioHandler.loadStems(
      sources,
      primaryInstrument: _primaryInstrument!,
      displayItem: MediaItem(
        id: _practiceSetId!,
        title: practiceSet['title'] as String,
        album: 'Vasis Beats',
      ),
      loop: saved?.loop ?? false,
      speed: _speedFor(bpm),
      volumes: volumes,
    );

    currentBpmNotifier.value = bpm;
    loopEnabledNotifier.value = saved?.loop ?? false;
    stemVolumesNotifier.value = volumes;
    timerMinutesNotifier.value = saved?.timerMinutes;
    timerRemainingNotifier.value = null;

    _sessionId = null;
    _startedAt = null;
    _played
      ..stop()
      ..reset();
    await _settings.setLastPracticeSet(_practiceSetId!);
  }

  double _speedFor(int bpm) => _baseBpm <= 0 ? 1.0 : (bpm / _baseBpm).clamp(0.5, 2.0).toDouble();

  Map<String, dynamic> _nearestTrack(List<Map<String, dynamic>> sortedByBpm, int targetBpm) {
    return sortedByBpm.reduce((a, b) {
      final da = ((a['bpm'] as int) - targetBpm).abs();
      final db = ((b['bpm'] as int) - targetBpm).abs();
      return da <= db ? a : b;
    });
  }

  Future<void> play() => _audioHandler.play();
  Future<void> pause() => _audioHandler.pause();
  Future<void> seek(Duration position) => _audioHandler.seek(position);

  /// Tempo by target BPM (what the UI shows). Applies a speed multiplier
  /// against whichever recording is currently loaded immediately, for a
  /// smooth live slider drag, then — a moment after the value settles —
  /// swaps each instrument to the real recording nearest the new target so
  /// what's actually playing stays close to a genuine BPM-specific track
  /// rather than a single file stretched across the whole range.
  Future<void> setBpm(int bpm) async {
    if (_baseBpm <= 0) return;
    currentBpmNotifier.value = bpm;
    await _audioHandler.setSpeed(_speedFor(bpm));
    _scheduleSave();
    _scheduleTrackSwap(bpm);
  }

  void _scheduleTrackSwap(int bpm) {
    _trackSwapDebounce?.cancel();
    _trackSwapDebounce = Timer(const Duration(milliseconds: 300), () => _swapToNearestTracks(bpm));
  }

  Future<void> _swapToNearestTracks(int targetBpm) async {
    if (_practiceSetId == null) return;
    for (final entry in _tracksByInstrument.entries) {
      final nearest = _nearestTrack(entry.value, targetBpm);
      final current = _selectedTrackByInstrument[entry.key];
      if (current != null && nearest['id'] == current['id']) continue;

      _selectedTrackByInstrument[entry.key] = nearest;
      final source = offlineSupported
          ? await _downloads.preparePlayableFile(nearest['id'] as String)
          : DownloadManager.urlForObjectKey(nearest['r2_object_key'] as String);
      await _audioHandler.swapStemSource(entry.key, source);

      if (entry.key == _primaryInstrument) {
        _baseBpm = nearest['bpm'] as int;
        _trackId = nearest['id'] as String;
      }
    }
    // Re-apply speed against the (possibly now-updated) base so the audible
    // tempo still matches the slider exactly after swapping recordings.
    await _audioHandler.setSpeed(_speedFor(currentBpmNotifier.value));
  }

  Future<void> toggleLoop() async {
    final next = !loopEnabledNotifier.value;
    loopEnabledNotifier.value = next;
    await _audioHandler.setLoop(next);
    _scheduleSave();
  }

  void setStemVolume(String instrument, double volume) {
    final updated = Map<String, double>.from(stemVolumesNotifier.value);
    updated[instrument] = volume;
    stemVolumesNotifier.value = updated;
    _audioHandler.setStemVolume(instrument, volume);
    _scheduleSave();
  }

  /// Chooses the practice-timer length. It counts down only while audio is
  /// actually playing, and starts with the next playback.
  void selectTimer(int minutes) {
    timerMinutesNotifier.value = minutes;
    timerRemainingNotifier.value = null;
    _scheduleSave();
  }

  void cancelTimer() {
    timerMinutesNotifier.value = null;
    timerRemainingNotifier.value = null;
    _scheduleSave();
  }

  void _onPlayingChanged() {
    if (isPlayingNotifier.value) {
      _startedAt ??= DateTime.now();
      _sessionId ??= const Uuid().v4();
      _played.start();
      _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    } else {
      _played.stop();
      _ticker?.cancel();
      _ticker = null;
      _checkpointSession();
    }
  }

  void _tick() {
    final minutes = timerMinutesNotifier.value;
    if (minutes == null) return;
    final remaining = timerRemainingNotifier.value ?? Duration(minutes: minutes);
    if (remaining.inSeconds <= 1) {
      timerRemainingNotifier.value = null;
      pause();
      return;
    }
    timerRemainingNotifier.value = remaining - const Duration(seconds: 1);
  }

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 400), _saveNow);
  }

  Future<void> _saveNow() async {
    final id = _practiceSetId;
    if (id == null) return;
    await _settings.save(
      id,
      PracticeSettings(
        bpm: currentBpmNotifier.value,
        loop: loopEnabledNotifier.value,
        timerMinutes: timerMinutesNotifier.value,
        stemVolumes: stemVolumesNotifier.value,
      ),
    );
  }

  /// Writes (or updates) this session's record; called on every pause and
  /// when playback of a set ends, so an interrupted session still counts.
  Future<void> _checkpointSession() async {
    final id = _sessionId;
    final setId = _practiceSetId;
    final startedAt = _startedAt;
    if (id == null || setId == null || startedAt == null || _played.elapsed.inSeconds < 1) return;
    try {
      await _cache.recordPracticeSession(
        id: id,
        practiceSetId: setId,
        trackId: _trackId,
        tempoBpm: currentBpmNotifier.value,
        instrumentMix: stemVolumesNotifier.value,
        timerMinutes: timerMinutesNotifier.value,
        loopEnabled: loopEnabledNotifier.value,
        durationSeconds: _played.elapsed.inSeconds,
        startedAt: startedAt,
        endedAt: DateTime.now(),
      );
    } catch (e) {
      debugPrint('⚠️ Could not record practice session: $e');
    }
  }

  /// Stops audio, records the session, and removes any decrypted playback
  /// files from disk.
  Future<void> stop() => _releaseCurrentSet();

  Future<void> _releaseCurrentSet() async {
    _saveDebounce?.cancel();
    _trackSwapDebounce?.cancel();
    await _saveNow();
    _played.stop();
    _ticker?.cancel();
    _ticker = null;
    await _checkpointSession();
    await _audioHandler.stop();
    if (offlineSupported) await _downloads.cleanupTempPlaybackFiles();

    _sessionId = null;
    _startedAt = null;
    _played.reset();
    timerRemainingNotifier.value = null;
    currentPracticeSetNotifier.value = null;
    stemVolumesNotifier.value = {};
    _practiceSetId = null;
    _tracksByInstrument = {};
    _selectedTrackByInstrument = {};
    _primaryInstrument = null;
    _baseBpm = 0;
  }
}
