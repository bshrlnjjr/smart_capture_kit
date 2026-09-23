import Foundation
import Vision

print("=== Legacy VNRecognizeTextRequest ===")
for rev in [VNRecognizeTextRequestRevision1, VNRecognizeTextRequestRevision2, VNRecognizeTextRequestRevision3] {
    for level in [VNRequestTextRecognitionLevel.accurate, .fast] {
        do {
            let langs = try VNRecognizeTextRequest.supportedRecognitionLanguages(for: level, revision: rev)
            let arabic = langs.filter { $0.lowercased().hasPrefix("ar") }
            print("rev \(rev) level \(level == .accurate ? "accurate" : "fast"): count=\(langs.count) arabic=\(arabic) all=\(langs)")
        } catch {
            print("rev \(rev): error \(error)")
        }
    }
}

print("\n=== New Vision RecognizeTextRequest (Swift, macOS 15+) ===")
if #available(macOS 15.0, *) {
    let req = RecognizeTextRequest()
    let langs = req.supportedRecognitionLanguages
    let codes = langs.map { $0.maximalIdentifier }
    print("count=\(codes.count)")
    print("arabic=\(codes.filter { $0.lowercased().hasPrefix("ar") })")
    print("all=\(codes)")
} else {
    print("unavailable")
}
