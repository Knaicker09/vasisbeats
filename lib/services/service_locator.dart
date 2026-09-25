import 'package:get_it/get_it.dart';
import 'beats_profile_service.dart';
import 'offline_cache_service.dart';
import 'download_manager.dart';
import 'practice_audio_handler.dart';
import 'practice_controller.dart';

GetIt getIt = GetIt.instance;

Future<void> setupServiceLocator() async {
  print('[ServiceLocator] Setting up service locator...');

  final practiceAudioHandler = await initPracticeAudioService();
  getIt.registerSingleton<PracticeAudioHandler>(practiceAudioHandler);
  getIt.registerLazySingleton<PracticeController>(
      () => PracticeController(getIt<PracticeAudioHandler>()));

  getIt.registerLazySingleton<BeatsProfileService>(() => BeatsProfileService());
  getIt.registerLazySingleton<OfflineCacheService>(() => OfflineCacheService());
  getIt.registerLazySingleton<DownloadManager>(() => DownloadManager());
}
