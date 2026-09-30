import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_nav.dart';
import 'services/service_locator.dart';
import 'services/db_bootstrap.dart';
import 'services/download_manager.dart';
import 'services/error_log_service.dart';
import 'services/offline_cache_service.dart';
import 'services/practice_controller.dart';

import 'platform_support.dart';
import 'screens/auth/login_screen.dart';
import 'screens/main_shell.dart';
import 'ui/brand.dart';

/// Global navigator key, used for navigation/snackbars from places
/// (deep-link callbacks) that don't have a BuildContext of their own.
final navigatorKey = GlobalKey<NavigatorState>();

const String _errorReportEmail = 'namelestek@gmail.com';
const String _appName = 'Vasis Beats';

String _truncate(String value, int maxLength) =>
    value.length <= maxLength ? value : value.substring(0, maxLength);

/// Best-effort first non-empty stack frame, for a quick-glance summary on
/// top of the full raw stack trace included further down the report.
/// Mirrors `firstStackFrame` in the website's lib/errorReporting.ts.
String? _firstStackFrame(String stack) {
  final lines = stack.split('\n');
  for (final line in lines.skip(1)) {
    final trimmed = line.trim();
    if (trimmed.isNotEmpty) return trimmed;
  }
  return null;
}

/// Logs an uncaught error to the console and opens a pre-filled email
/// report (via the device's mail client) addressed to [_errorReportEmail].
/// Field set mirrors the website's dev-alert email (lib/errorReporting.ts):
/// app, source, affected user, timestamp, error name/message, first stack
/// frame, and the full stack trace.
Future<void> _reportError(
  Object error,
  StackTrace stack, {
  String source = 'zone-error',
}) async {
  debugPrint('❌ Uncaught error ($source): $error');
  debugPrint(stack.toString());

  try {
    final userEmail =
        Supabase.instance.client.auth.currentUser?.email ?? '(not logged in / unknown)';
    final timestamp = DateTime.now().toUtc().toIso8601String();
    final errorName = error.runtimeType.toString();
    final message = error.toString();
    final stackString = stack.toString();
    final frame = _firstStackFrame(stackString);

    final subject = _truncate('[$_appName] $source error: $message', 200);

    final bodyLines = <String>[
      'App: $_appName',
      'Source: $source',
      'Affected user: $userEmail',
      'Platform: $platformName',
      'Timestamp: $timestamp',
      'Error name: $errorName',
      'Error message: $message',
      if (frame != null) 'Location (first frame): $frame',
      '',
      'Stack trace:',
      stackString,
    ];

    final reportUri = Uri(
      scheme: 'mailto',
      path: _errorReportEmail,
      query:
          'subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(bodyLines.join('\n'))}',
    );
    if (await canLaunchUrl(reportUri)) {
      await launchUrl(reportUri, mode: LaunchMode.externalApplication);
    }
  } catch (e) {
    // Never let error reporting itself crash the app.
    debugPrint('Failed to open error report email: $e');
  }
}

void main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      _reportError(
        details.exception,
        details.stack ?? StackTrace.current,
        source: 'flutter-error',
      );
    };

    // Load environment variables
    try {
      await dotenv.load(fileName: ".env");
    } catch (e) {
      debugPrint('Error loading .env file: $e');
      // In production, you might want to handle this differently
      // For now, we'll just print the error and continue
    }

    await Supabase.initialize(
      url: dotenv.env['SUPABASE_URL']!,
      anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );

    if (offlineSupported) await initDatabaseFactory();
    await setupServiceLocator();

    Supabase.instance.client.auth.onAuthStateChange.listen(
      (state) {
        if (state.event == AuthChangeEvent.signedOut) {
          // Nothing of the previous user's should linger: stop and release
          // playback, drop their cached profile/favorites/history, and start
          // the next person on the Home tab.
          AppNav.goTo(AppNav.home);
          getIt<PracticeController>().stop();
          OfflineCacheService().clearUserData();
        }
      },
      onError: (_) => ErrorLogService.instance
          .log(LogCategory.auth, LogCode.sessionRefreshFailed),
    );
    ErrorLogService.instance.flush();

    // Best-effort, non-blocking: catch any downloaded track that was left
    // corrupted/partial by a previous crash before the app tries to play
    // it, and clear out any leftover decrypted playback temp files (safe
    // now — nothing should be mid-playback at app startup).
    if (offlineSupported) {
      getIt<DownloadManager>().verifyDownloadedTracks();
      getIt<DownloadManager>().cleanupTempPlaybackFiles();
    }

    runApp(MyApp());
  }, _reportError);
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Vasis Beats',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en')],
      // Single source of truth for auth-driven navigation: rebuilds on every
      // sign-in/sign-out, whichever flow produced it (password, emailed
      // code, registration confirmation).
      home: StreamBuilder<AuthState>(
        stream: Supabase.instance.client.auth.onAuthStateChange,
        initialData: AuthState(
          AuthChangeEvent.initialSession,
          Supabase.instance.client.auth.currentSession,
        ),
        builder: (context, snapshot) {
          final session =
              snapshot.data?.session ?? Supabase.instance.client.auth.currentSession;
          return session == null ? const LoginScreen() : const MainShell();
        },
      ),
    );
  }
}
