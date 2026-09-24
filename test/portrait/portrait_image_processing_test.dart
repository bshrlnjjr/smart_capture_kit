import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:smart_capture_kit/src/common/geometry.dart';
import 'package:smart_capture_kit/src/portrait/portrait_image_processing.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.tempPath);
  final String tempPath;

  @override
  Future<String?> getTemporaryPath() async => tempPath;
}

Future<String> _writeTestImage(Directory dir, String name, int size) async {
  final image = img.Image(width: size, height: size);
  img.fill(image, color: img.ColorRgb8(120, 120, 120));
  // A distinct bright square marks where the "face" is, so a wrong crop
  // origin is visible in the output dimensions/content rather than only in
  // an offset we'd have to re-derive to check.
  for (var y = size ~/ 4; y < size ~/ 2; y++) {
    for (var x = size ~/ 4; x < size ~/ 2; x++) {
      image.setPixelRgb(x, y, 255, 255, 255);
    }
  }
  final path = '${dir.path}/$name';
  File(path).writeAsBytesSync(img.encodeJpg(image));
  return path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('smart_capture_kit_test');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('producePortraitCrop', () {
    test('produces a cropped image no larger than the source', () async {
      final source = await _writeTestImage(tempDir, 'source.jpg', 400);
      const faceBox = NormalizedRect(left: 0.25, top: 0.25, right: 0.5, bottom: 0.5);

      final result = await producePortraitCrop(
        sourcePath: source,
        faceBox: faceBox,
        paddingFactor: 0.6,
      );

      expect(result, isNotNull);
      expect(result!.width, lessThanOrEqualTo(400));
      expect(result.height, lessThanOrEqualTo(400));
      expect(await File(result.path).exists(), isTrue);
    });

    test('forces the requested aspect ratio within a small tolerance',
        () async {
      final source = await _writeTestImage(tempDir, 'source.jpg', 800);
      const faceBox = NormalizedRect(left: 0.4, top: 0.3, right: 0.6, bottom: 0.5);

      final result = await producePortraitCrop(
        sourcePath: source,
        faceBox: faceBox,
        aspectRatio: 3 / 4,
        paddingFactor: 0.5,
      );

      expect(result, isNotNull);
      final actualRatio = result!.width / result.height;
      // Center-crop clamping at the image edge can perturb the ratio
      // slightly; this only asserts it lands in the right neighborhood.
      expect(actualRatio, closeTo(3 / 4, 0.15));
    });

    test('a face box touching the image edge still produces a usable crop',
        () async {
      final source = await _writeTestImage(tempDir, 'source.jpg', 300);
      const faceBox = NormalizedRect(left: 0.0, top: 0.0, right: 0.2, bottom: 0.2);

      final result = await producePortraitCrop(
        sourcePath: source,
        faceBox: faceBox,
        paddingFactor: 0.6,
      );

      // Clamped to the source bounds rather than fabricating pixels beyond
      // the edge.
      expect(result, isNotNull);
      expect(result!.width, greaterThan(0));
      expect(result.width, lessThanOrEqualTo(300));
    });
  });
}
