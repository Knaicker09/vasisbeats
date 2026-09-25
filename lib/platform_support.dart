import 'package:flutter/foundation.dart';

/// What each platform can do. The web build is online-only: no local
/// database, no downloads, no encrypted files — everything is read live
/// and audio is streamed. Every offline feature checks [offlineSupported].
bool get offlineSupported => !kIsWeb;

/// Short platform name used in error-log rows and error reports.
String get platformName => kIsWeb ? 'web' : defaultTargetPlatform.name;

/// `audio_service` (OS media notification / lock-screen controls) exists on
/// Android, iOS, macOS and web. On Windows/Linux the practice player runs
/// without it — playback works identically, minus OS media-key integration.
bool get audioServiceSupported =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.macOS;

/// `in_app_review` / store links exist for Android, iOS and macOS only.
bool get storeRatingSupported =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS);
