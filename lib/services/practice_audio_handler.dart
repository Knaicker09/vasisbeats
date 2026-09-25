import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import '../platform_support.dart';
import 'error_log_service.dart';

/// Starts the practice audio engine. Call once, at app boot. Where
/// `audio_service` doesn't exist (Windows/Linux) the handler is used
/// directly, without OS media-session registration — playback is the same.
Future<PracticeAudioHandler> initPracticeAudioService() async {
  if (!audioServiceSupported) return PracticeAudioHandler();
  return await AudioService.init(
    builder: () => PracticeAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.vasisstudio.beats.practice',
      androidNotificationChannelName: 'Vasis Beats Practice',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );
}

/// Multi-stem practice player: one "primary" AudioPlayer registered with
/// audio_service — it drives the OS media notification / lock-screen
/// controls — plus zero or more secondary stems (other instruments in the
/// same practice set) that play in sync alongside it via plain just_audio,
/// invisible to the system media session.
///
/// Sync approach: every transport call (play/pause/seek/speed/loop) fans
/// out to all players via Future.wait so they start together; a periodic
/// re-seek of the secondaries to the primary's position (every 10s while
/// playing) corrects any drift that accumulates from independently
/// looping same-duration sources. This has not been verified against real
/// audio on a device — see the Phase 5 plan note on why that verification
/// has to wait for real content.
class PracticeAudioHandler extends BaseAudioHandler {
  final AudioPlayer _primaryPlayer = AudioPlayer();
  final Map<String, AudioPlayer> _secondaryPlayers = {};
  String? _primaryInstrument;
  Timer? _resyncTimer;

  PracticeAudioHandler() {
    _primaryPlayer.playbackEventStream.listen(
      _broadcastState,
      onError: (Object _, StackTrace __) => ErrorLogService.instance
          .log(LogCategory.playback, LogCode.playbackSourceError),
    );
  }

  void _broadcastState(PlaybackEvent event) {
    final playing = _primaryPlayer.playing;
    playbackState.add(playbackState.value.copyWith(
      controls: [
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
      ],
      systemActions: const {MediaAction.seek},
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_primaryPlayer.processingState]!,
      playing: playing,
      updatePosition: _primaryPlayer.position,
      bufferedPosition: _primaryPlayer.bufferedPosition,
      speed: _primaryPlayer.speed,
    ));
  }

  Future<void> _setSource(AudioPlayer player, String source) =>
      source.startsWith('http') ? player.setUrl(source) : player.setFilePath(source);

  /// Loads a fresh set of stems for one practice set/track selection.
  /// [sources] keys are instrument names ('mrdanga', 'kartals', 'tanpura',
  /// 'full_mix' — matching vms_beats_tracks.instrument); values are either
  /// a decrypted local file path (native, from
  /// DownloadManager.preparePlayableFile) or an https URL (web, streamed).
  /// [primaryInstrument] should be 'full_mix' when present, otherwise any
  /// one stem — that's the player the OS notification/lock-screen controls
  /// track. Saved settings ([loop], [speed], [volumes]) are applied here so
  /// they're in effect from the first beat.
  Future<void> loadStems(
    Map<String, String> sources, {
    required String primaryInstrument,
    required MediaItem displayItem,
    bool loop = false,
    double speed = 1.0,
    Map<String, double> volumes = const {},
  }) async {
    await stop();
    _primaryInstrument = primaryInstrument;
    mediaItem.add(displayItem);

    final primarySource = sources[primaryInstrument];
    if (primarySource == null) {
      throw ArgumentError('primaryInstrument "$primaryInstrument" not present in sources');
    }
    await _setSource(_primaryPlayer, primarySource);

    for (final entry in sources.entries) {
      if (entry.key == primaryInstrument) continue;
      final player = AudioPlayer();
      await _setSource(player, entry.value);
      _secondaryPlayers[entry.key] = player;
    }

    await setLoop(loop);
    if (speed != 1.0) await setSpeed(speed);
    for (final entry in volumes.entries) {
      setStemVolume(entry.key, entry.value);
    }
  }

  @override
  Future<void> play() async {
    await Future.wait([
      _primaryPlayer.play(),
      ..._secondaryPlayers.values.map((p) => p.play()),
    ]);
    _startResync();
  }

  @override
  Future<void> pause() async {
    _resyncTimer?.cancel();
    await Future.wait([
      _primaryPlayer.pause(),
      ..._secondaryPlayers.values.map((p) => p.pause()),
    ]);
  }

  @override
  Future<void> seek(Duration position) async {
    await Future.wait([
      _primaryPlayer.seek(position),
      ..._secondaryPlayers.values.map((p) => p.seek(position)),
    ]);
  }

  /// Tempo control — applies a playback speed multiplier to every stem.
  @override
  Future<void> setSpeed(double speed) async {
    await Future.wait([
      _primaryPlayer.setSpeed(speed),
      ..._secondaryPlayers.values.map((p) => p.setSpeed(speed)),
    ]);
  }

  Future<void> setLoop(bool enabled) async {
    final mode = enabled ? LoopMode.one : LoopMode.off;
    await Future.wait([
      _primaryPlayer.setLoopMode(mode),
      ..._secondaryPlayers.values.map((p) => p.setLoopMode(mode)),
    ]);
  }

  /// Per-stem volume for the instrument-mix panel. 0.0–1.0.
  void setStemVolume(String instrument, double volume) {
    if (instrument == _primaryInstrument) {
      _primaryPlayer.setVolume(volume);
    } else {
      _secondaryPlayers[instrument]?.setVolume(volume);
    }
  }

  /// Replaces one stem's underlying file/URL in place — used when the
  /// tempo slider moves far enough that a different BPM-specific recording
  /// is the closer match, so the app plays a real recording near the
  /// requested tempo rather than time-stretching a single fixed file
  /// across its whole range. Leaves every other stem and the transport
  /// state (playing/paused, loop mode, speed) exactly as it was; this one
  /// stem restarts from 0.
  Future<void> swapStemSource(String instrument, String source) async {
    final wasPlaying = _primaryPlayer.playing;
    final speed = _primaryPlayer.speed;
    final loopMode = _primaryPlayer.loopMode;

    if (instrument == _primaryInstrument) {
      await _setSource(_primaryPlayer, source);
      await _primaryPlayer.setSpeed(speed);
      await _primaryPlayer.setLoopMode(loopMode);
      if (wasPlaying) await _primaryPlayer.play();
    } else {
      final old = _secondaryPlayers[instrument];
      final volume = old?.volume ?? 1.0;
      await old?.dispose();
      final player = AudioPlayer();
      await _setSource(player, source);
      await player.setSpeed(speed);
      await player.setLoopMode(loopMode);
      await player.setVolume(volume);
      _secondaryPlayers[instrument] = player;
      if (wasPlaying) await player.play();
    }
  }

  void _startResync() {
    _resyncTimer?.cancel();
    if (_secondaryPlayers.isEmpty) return;
    _resyncTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!_primaryPlayer.playing) return;
      final position = _primaryPlayer.position;
      for (final p in _secondaryPlayers.values) {
        p.seek(position);
      }
    });
  }

  @override
  Future<void> stop() async {
    _resyncTimer?.cancel();
    await _primaryPlayer.stop();
    for (final p in _secondaryPlayers.values) {
      await p.dispose();
    }
    _secondaryPlayers.clear();
    _primaryInstrument = null;
    return super.stop();
  }
}
