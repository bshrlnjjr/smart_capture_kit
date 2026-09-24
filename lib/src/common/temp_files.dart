import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Owns the plugin's temporary capture directory.
///
/// Every image `SmartCapture` writes lives under a single subdirectory of the
/// platform temporary directory, `<tmp>/smart_capture_kit/`. This exists so
/// cleanup — and the "the plugin makes no promise about how long this
/// survives" language in [CaptureImage] — has one place to point at, and so a
/// host that wants to nuke everything the plugin has ever written can do so
/// without guessing at file names.
class SmartCaptureTempFiles {
  SmartCaptureTempFiles._();

  static Directory? _cachedDir;
  static int _counter = 0;

  /// The plugin's temporary directory, created if it does not already exist.
  static Future<Directory> directory() async {
    final cached = _cachedDir;
    if (cached != null && await cached.exists()) return cached;
    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}/smart_capture_kit');
    await dir.create(recursive: true);
    _cachedDir = dir;
    return dir;
  }

  /// A fresh file path inside the plugin's temporary directory.
  ///
  /// [prefix] identifies the kind of file for easier debugging (e.g.
  /// `portrait_original`); it is never derived from, and must never contain,
  /// any personal data.
  static Future<String> newFilePath(String prefix, {String extension = 'jpg'}) async {
    final dir = await directory();
    final id = '${DateTime.now().microsecondsSinceEpoch}_${_counter++}';
    return '${dir.path}/${prefix}_$id.$extension';
  }

  /// Deletes every file the plugin has written, including ones already
  /// handed to the host as a [CaptureImage].
  ///
  /// Intended for a host that wants a hard guarantee nothing lingers, e.g. on
  /// sign-out. Individual results should normally be cleaned up with their
  /// own `dispose()` instead.
  static Future<void> clearAll() async {
    final dir = await directory();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    _cachedDir = null;
  }
}
