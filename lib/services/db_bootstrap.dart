// `sqflite` has no Windows/Linux implementation; those platforms need the
// FFI-backed factory. `dart:ffi` doesn't exist on web, so the FFI setup
// lives behind a conditional import and web gets a no-op.
export 'db_bootstrap_stub.dart' if (dart.library.ffi) 'db_bootstrap_native.dart';
