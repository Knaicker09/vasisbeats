import 'package:flutter/foundation.dart';

class PracticeRequest {
  final Map<String, dynamic> practiceSet;
  final int id;
  PracticeRequest(this.practiceSet, this.id);
}

/// App-level navigation between the four tabs, so Home / Learn / dialogs can
/// jump to Practice (with a set to open) or Profile without holding a
/// reference to the shell.
class AppNav {
  AppNav._();

  static const home = 0;
  static const practice = 1;
  static const learn = 2;
  static const profile = 3;

  static final tab = ValueNotifier<int>(home);
  static final practiceRequest = ValueNotifier<PracticeRequest?>(null);
  static int _requestId = 0;

  static void goTo(int index) => tab.value = index;

  static void openPractice(Map<String, dynamic> practiceSet) {
    practiceRequest.value = PracticeRequest(practiceSet, ++_requestId);
    tab.value = practice;
  }
}
