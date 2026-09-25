import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The playback settings remembered for one practice set.
class PracticeSettings {
  final int? bpm;
  final bool loop;
  final int? timerMinutes;
  final Map<String, double> stemVolumes;

  const PracticeSettings({
    this.bpm,
    this.loop = false,
    this.timerMinutes,
    this.stemVolumes = const {},
  });

  Map<String, dynamic> toJson() => {
        'bpm': bpm,
        'loop': loop,
        'timerMinutes': timerMinutes,
        'stemVolumes': stemVolumes,
      };

  factory PracticeSettings.fromJson(Map<String, dynamic> json) => PracticeSettings(
        bpm: json['bpm'] as int?,
        loop: json['loop'] as bool? ?? false,
        timerMinutes: json['timerMinutes'] as int?,
        stemVolumes: {
          for (final e in (json['stemVolumes'] as Map? ?? const {}).entries)
            e.key as String: (e.value as num).toDouble(),
        },
      );
}

/// Remembers tempo, loop, timer length and instrument mix per practice set —
/// saved on every change and applied the next time that set is played — plus
/// which set was played last (for "Continue Practice"). Stored on-device with
/// shared_preferences (works on every platform, including web) and keyed by
/// signed-in user so accounts sharing a device keep separate settings.
class PracticeSettingsService {
  PracticeSettingsService._();
  static final PracticeSettingsService instance = PracticeSettingsService._();

  String get _user => Supabase.instance.client.auth.currentUser?.id ?? 'anonymous';
  String _setKey(String practiceSetId) => 'practice_settings.$_user.$practiceSetId';
  String get _lastKey => 'practice_last_set.$_user';

  Future<PracticeSettings?> load(String practiceSetId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_setKey(practiceSetId));
    if (raw == null) return null;
    try {
      return PracticeSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null; // corrupt entry — fall back to defaults
    }
  }

  Future<void> save(String practiceSetId, PracticeSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_setKey(practiceSetId), jsonEncode(settings.toJson()));
  }

  Future<String?> lastPracticeSetId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastKey);
  }

  Future<void> setLastPracticeSet(String practiceSetId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastKey, practiceSetId);
  }
}
