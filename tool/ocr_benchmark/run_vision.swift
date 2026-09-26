// Runs Apple Vision text recognition over every PNG in a directory and
// writes the recognized lines plus timing as JSON, for the phase 6 OCR
// benchmark.
//
// Configuration mirrors what VisionOcrEngine will use: revision 3,
// `.accurate` (the only level with Arabic — see ADR 0001), languages
// ar-SA + en-US.
//
// Usage: swift tool/ocr_benchmark/run_vision.swift <samples_dir> <out.json> [lc]
//   lc: "1" enables usesLanguageCorrection (default off).
//
// Runs on macOS Vision. The same revision-3 model ships on iOS 16+, but
// macOS numbers are a proxy until re-run on an iPhone.

import AppKit
import Foundation
import Vision

let args = CommandLine.arguments
guard args.count >= 3 else {
  print("usage: run_vision.swift <samples_dir> <out.json> [lc]")
  exit(1)
}
let dir = URL(fileURLWithPath: args[1])
let outURL = URL(fileURLWithPath: args[2])
let languageCorrection = args.count >= 4 && args[3] == "1"

struct Result: Codable {
  let lines: [String]
  let confidences: [Float]
  let milliseconds: Double
}

let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
  .filter { $0.hasSuffix(".png") }
  .sorted()

var results: [String: Result] = [:]
for file in files {
  let url = dir.appendingPathComponent(file)
  guard let image = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
  else { continue }

  let request = VNRecognizeTextRequest()
  request.revision = VNRecognizeTextRequestRevision3
  request.recognitionLevel = .accurate
  request.recognitionLanguages = ["ar-SA", "en-US"]
  request.usesLanguageCorrection = languageCorrection

  let start = Date()
  try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
  let ms = Date().timeIntervalSince(start) * 1000

  // Top-to-bottom reading order; Vision's y origin is bottom-left.
  let observations = (request.results ?? []).sorted {
    $0.boundingBox.midY > $1.boundingBox.midY
  }
  let candidates = observations.compactMap { $0.topCandidates(1).first }
  results[file] = Result(
    lines: candidates.map(\.string),
    confidences: candidates.map(\.confidence),
    milliseconds: ms)
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
try encoder.encode(results).write(to: outURL)
print("vision (lc=\(languageCorrection)): \(results.count) images -> \(outURL.path)")
