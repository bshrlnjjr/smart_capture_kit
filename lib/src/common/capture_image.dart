import 'dart:io';
import 'dart:typed_data';

import 'package:meta/meta.dart';

/// What an image in a capture result represents.
enum CaptureImageKind {
  /// The full-resolution frame exactly as the camera produced it, with no
  /// cropping or geometric correction applied.
  original,

  /// The original cropped to the requested aspect ratio. Geometry is
  /// otherwise unchanged.
  cropped,

  /// A document image whose perspective has been corrected so the card fills
  /// the frame as a rectangle. Produced only for document captures.
  rectified,
}

/// A single image produced by a capture flow.
///
/// ## File ownership
///
/// Images are written to a temporary directory owned by the plugin. The host
/// application becomes responsible for the file the moment a result is handed
/// to it:
///
/// - To keep an image, copy or move it somewhere the host controls. The plugin
///   makes no promise about how long its temporary directory survives; the OS
///   may clear it at any time.
/// - To discard it, call [delete], or call `dispose()` on the enclosing result
///   to delete every image it owns at once.
///
/// The plugin never uploads an image and never writes one outside its
/// temporary directory.
@immutable
class CaptureImage {
  const CaptureImage({
    required this.path,
    required this.kind,
    required this.width,
    required this.height,
    this.mimeType = 'image/jpeg',
  });

  /// Absolute path to the file on disk.
  final String path;

  final CaptureImageKind kind;

  /// Pixel dimensions of the encoded image.
  final int width;
  final int height;

  final String mimeType;

  double get aspectRatio => height == 0 ? 0 : width / height;

  File get file => File(path);

  /// Reads the encoded bytes.
  ///
  /// Kept as a method rather than a field so that a result can be passed around
  /// without pulling several megabytes of image data into memory.
  Future<Uint8List> readBytes() => file.readAsBytes();

  /// Deletes the backing file if it still exists.
  ///
  /// Safe to call more than once, and safe to call on a file the OS already
  /// reclaimed.
  Future<void> delete() async {
    try {
      final f = file;
      if (await f.exists()) {
        await f.delete();
      }
    } on FileSystemException {
      // The file is already gone, or the directory was cleared by the OS.
      // Either way the post-condition the caller wanted already holds.
    }
  }

  @override
  String toString() =>
      'CaptureImage(${kind.name}, ${width}x$height, $mimeType)';
}
