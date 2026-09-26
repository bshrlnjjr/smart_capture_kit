import Flutter
import ImageIO
import UIKit
import Vision

/// Native side of smart_capture_kit on iOS.
///
/// `recognizeText` runs Apple Vision text recognition over an image file and returns
/// one entry per recognized line, in the same shape as the Android implementation:
/// `{engineVersion, milliseconds, lines: [{text, confidence, box: [l, t, r, b],
/// corners: [x0, y0, ... x3, y3], block}]}`, normalized to the upright image with a
/// top-left origin.
///
/// Arabic exists only in request revision 3 at the `.accurate` level (iOS 16+) —
/// see doc/decisions/0001-ocr-engine-selection.md. `.fast` silently drops Arabic, so
/// it is never used here.
public class SmartCaptureKitPlugin: NSObject, FlutterPlugin {
  private let queue = DispatchQueue(label: "smart_capture_kit.ocr", qos: .userInitiated)

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "smart_capture_kit", binaryMessenger: registrar.messenger())
    let instance = SmartCaptureKitPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("iOS " + UIDevice.current.systemVersion)
    case "supportedScripts":
      result(Self.supportedScripts())
    case "recognizeText":
      recognizeText(call.arguments as? [String: Any] ?? [:], result: result)
    case "disposeTextRecognizer":
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Scripts Vision can read on this device, queried rather than assumed.
  static func supportedScripts() -> [String] {
    var scripts = ["latin"]
    if #available(iOS 16.0, *) {
      let request = VNRecognizeTextRequest()
      request.revision = VNRecognizeTextRequestRevision3
      request.recognitionLevel = .accurate
      let languages = (try? request.supportedRecognitionLanguages()) ?? []
      if languages.contains(where: { $0.hasPrefix("ar") }) {
        scripts.append("arabic")
      }
    }
    return scripts
  }

  private func recognizeText(_ args: [String: Any], result: @escaping FlutterResult) {
    guard let path = args["path"] as? String else {
      result(FlutterError(code: "invalid_arguments", message: "recognizeText requires 'path'", details: nil))
      return
    }
    let scripts = args["scripts"] as? [String] ?? ["latin"]
    let languageCorrection = args["usesLanguageCorrection"] as? Bool ?? false

    queue.async {
      let url = URL(fileURLWithPath: path)
      guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
      else {
        DispatchQueue.main.async {
          result(FlutterError(code: "image_unreadable", message: "Could not decode \(path)", details: nil))
        }
        return
      }
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
      let exif = (properties?[kCGImagePropertyOrientation] as? UInt32) ?? 1
      let orientation = CGImagePropertyOrientation(rawValue: exif) ?? .up

      let request = VNRecognizeTextRequest()
      request.recognitionLevel = .accurate
      request.usesLanguageCorrection = languageCorrection
      var languages: [String] = []
      if scripts.contains("arabic") {
        guard #available(iOS 16.0, *) else {
          DispatchQueue.main.async {
            result(FlutterError(
              code: "script_unsupported",
              message: "Arabic text recognition requires iOS 16 or later",
              details: nil))
          }
          return
        }
        request.revision = VNRecognizeTextRequestRevision3
        languages.append("ar-SA")
      }
      if scripts.contains("latin") {
        languages.append("en-US")
      }
      request.recognitionLanguages = languages

      let start = Date()
      do {
        try VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])
          .perform([request])
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "ocr_failed", message: error.localizedDescription, details: nil))
        }
        return
      }
      let ms = Int(Date().timeIntervalSince(start) * 1000)

      // Vision's normalized coordinates have a bottom-left origin; flip to top-left.
      var lines: [[String: Any]] = []
      for (index, observation) in (request.results ?? []).enumerated() {
        guard let candidate = observation.topCandidates(1).first else { continue }
        let box = observation.boundingBox
        let corners = [observation.topLeft, observation.topRight, observation.bottomRight, observation.bottomLeft]
        lines.append([
          "text": candidate.string,
          "confidence": Double(candidate.confidence),
          "box": [box.minX, 1 - box.maxY, box.maxX, 1 - box.minY].map { Double($0) },
          "corners": corners.flatMap { [Double($0.x), Double(1 - $0.y)] },
          "block": index,
        ])
      }
      DispatchQueue.main.async {
        result([
          "engineVersion": "VNRecognizeTextRequest rev \(request.revision)",
          "milliseconds": ms,
          "lines": lines,
        ])
      }
    }
  }
}
