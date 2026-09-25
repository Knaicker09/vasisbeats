import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../platform_support.dart';
import 'beats_profile_service.dart';
import 'download_manager.dart';
import 'error_log_service.dart';
import 'offline_cache_service.dart';

/// Tracks whether the device has a network connection and, when one comes
/// back, catches up on everything that was waiting for it: failed
/// downloads, un-uploaded practice sessions, queued error-log rows and a
/// fresh catalog/favorites/history pull.
///
/// Native platforms only; the web build is always-online by nature.
class ConnectivityService {
  ConnectivityService._();
  static final ConnectivityService instance = ConnectivityService._();

  final ValueNotifier<bool> online = ValueNotifier(true);
  StreamSubscription<List<ConnectivityResult>>? _sub;

  Future<void> start() async {
    if (!offlineSupported || _sub != null) return;
    online.value = _isOnline(await Connectivity().checkConnectivity());
    _sub = Connectivity().onConnectivityChanged.listen((results) {
      final nowOnline = _isOnline(results);
      final wasOnline = online.value;
      online.value = nowOnline;
      if (nowOnline && !wasOnline) _catchUp();
    });
  }

  bool _isOnline(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  Future<void> _catchUp() async {
    try {
      final profile = await BeatsProfileService().fetchCurrentProfile();
      if (profile != null) {
        await OfflineCacheService().refreshAll(profile.studentId);
      }
      await ErrorLogService.instance.flush();
      await DownloadManager().retryFailedDownloads();
    } catch (e) {
      debugPrint('⚠️ Catch-up after reconnect failed: $e');
    }
  }
}
