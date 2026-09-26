// Generates SYNTHETIC identity-card-like images with known ground truth for
// the phase 6 OCR benchmark.
//
// Every value is invented (names drawn from common-name lists, national
// numbers from an obviously fake 999xxxxxxx range), every card is stamped
// "SYNTHETIC TEST CARD", and the layout imitates no real document design.
// No real document is used or reproduced.
//
// Usage: swift tool/ocr_benchmark/generate_samples.swift <out_dir> [count]
//
// Writes <out_dir>/<card>_<variant>.png plus <out_dir>/ground_truth.json.
// Rendering goes through CoreText so Arabic is shaped (joined letter forms,
// right-to-left runs) exactly as a printed card would be.

import AppKit
import CoreImage
import CoreText
import Foundation

let args = CommandLine.arguments
guard args.count >= 2 else {
  print("usage: generate_samples.swift <out_dir> [count]")
  exit(1)
}
let outDir = URL(fileURLWithPath: args[1])
let cardCount = args.count >= 3 ? Int(args[2])! : 20
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

// MARK: - Deterministic RNG

struct SplitMix64: RandomNumberGenerator {
  var state: UInt64
  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}
var rng = SplitMix64(state: 20_260_926)

// MARK: - Invented data

let firstNames: [(ar: String, en: String)] = [
  ("محمد", "Mohammad"), ("أحمد", "Ahmad"), ("عمر", "Omar"), ("خالد", "Khaled"),
  ("يوسف", "Yousef"), ("سارة", "Sara"), ("ليلى", "Layla"), ("نور", "Noor"),
  ("رنا", "Rana"), ("هبة", "Hiba"), ("زيد", "Zaid"), ("طارق", "Tariq"),
]
let familyNames: [(ar: String, en: String)] = [
  ("الخطيب", "Alkhatib"), ("النجار", "Alnajjar"), ("الحداد", "Alhaddad"),
  ("العلي", "Alali"), ("الزعبي", "Alzoubi"), ("المصري", "Almasri"),
  ("الشامي", "Alshami"), ("القاسم", "Alqasem"),
]
let places: [(ar: String, en: String)] = [
  ("عمان", "Amman"), ("إربد", "Irbid"), ("الزرقاء", "Zarqa"), ("العقبة", "Aqaba"),
  ("السلط", "Salt"), ("مادبا", "Madaba"),
]

let arabicIndicDigits: [Character] = ["٠", "١", "٢", "٣", "٤", "٥", "٦", "٧", "٨", "٩"]
func toArabicIndic(_ s: String) -> String {
  String(s.map { c in c.wholeNumberValue.map { arabicIndicDigits[$0] } ?? c })
}

// MARK: - Fonts

let arabicFontNames = ["GeezaPro", "AlNile", "ArialMT", "SFArabic-Regular"]
let latinFontNames = ["Helvetica", "ArialMT", "Menlo-Regular"]

func font(_ name: String, _ size: CGFloat) -> CTFont {
  CTFontCreateWithName(name as CFString, size, nil)
}

// MARK: - Rendering

struct Line: Codable {
  let text: String
  let script: String  // "arabic", "latin" or "mixed"
  let field: String?  // key value the line carries, for field-level scoring
  let value: String?
}

struct Card: Codable {
  let id: String
  let arabicFont: String
  let latinFont: String
  let lines: [Line]
}

let width = 1400
let height = Int((Double(width) / (85.60 / 53.98)).rounded())

func makeContext(_ w: Int, _ h: Int) -> CGContext {
  CGContext(
    data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

/// Draws [text] with its baseline at y (CoreGraphics coords, origin bottom-left).
func draw(
  _ ctx: CGContext, _ text: String, font f: CTFont, x: CGFloat, y: CGFloat,
  alignRight: Bool, maxX: CGFloat, color: CGColor = CGColor(gray: 0.08, alpha: 1)
) {
  let attrs: [NSAttributedString.Key: Any] = [
    NSAttributedString.Key(kCTFontAttributeName as String): f,
    NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
  ]
  let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
  let w = CTLineGetTypographicBounds(line, nil, nil, nil)
  ctx.textPosition = CGPoint(x: alignRight ? maxX - CGFloat(w) : x, y: y)
  CTLineDraw(line, ctx)
}

func renderCard(_ index: Int) -> (Card, CGImage) {
  let first = firstNames.randomElement(using: &rng)!
  let father = firstNames.randomElement(using: &rng)!
  let family = familyNames.randomElement(using: &rng)!
  let place = places.randomElement(using: &rng)!
  let year = Int.random(in: 1955...2005, using: &rng)
  let month = Int.random(in: 1...12, using: &rng)
  let day = Int.random(in: 1...28, using: &rng)
  let dob = String(format: "%02d/%02d/%04d", day, month, year)
  let expiry = String(
    format: "%04d-%02d-%02d", Int.random(in: 2027...2035, using: &rng),
    Int.random(in: 1...12, using: &rng), Int.random(in: 1...28, using: &rng))
  let nationalNo = "999" + String(format: "%07d", Int.random(in: 0...9_999_999, using: &rng))
  let female = ["سارة", "ليلى", "نور", "رنا", "هبة"].contains(first.ar)
  // Half the cards print Arabic-Indic digits in the Arabic block, as many
  // Arabic-script documents do; the rest print Western digits.
  let indicDigits = index % 2 == 0

  let arFontName = arabicFontNames[index % arabicFontNames.count]
  let enFontName = latinFontNames[index % latinFontNames.count]

  let nameAr = "\(first.ar) \(father.ar) \(family.ar)"
  let nameEn = "\(first.en) \(father.en) \(family.en)"
  let dobAr = indicDigits ? toArabicIndic(dob) : dob

  let lines: [Line] = [
    Line(text: "الاسم: \(nameAr)", script: "arabic", field: "name_ar", value: nameAr),
    Line(text: "تاريخ الولادة: \(dobAr)", script: "arabic", field: "dob_ar", value: dobAr),
    Line(text: "مكان الولادة: \(place.ar)", script: "arabic", field: "place_ar", value: place.ar),
    Line(text: "الجنس: \(female ? "أنثى" : "ذكر")", script: "arabic", field: "sex_ar", value: female ? "أنثى" : "ذكر"),
    Line(text: "Name: \(nameEn)", script: "latin", field: "name_en", value: nameEn),
    Line(text: "Date of Birth: \(dob)", script: "latin", field: "dob_en", value: dob),
    Line(text: "Sex: \(female ? "F" : "M")", script: "latin", field: nil, value: nil),
    Line(text: "Expiry: \(expiry)", script: "latin", field: "expiry", value: expiry),
    Line(text: "الرقم الوطني National No. \(nationalNo)", script: "mixed", field: "national_no", value: nationalNo),
  ]

  let ctx = makeContext(width, height)
  // Off-white base with a faint security-style wave pattern, so the engines
  // face some background texture rather than a flat page.
  ctx.setFillColor(CGColor(red: 0.95, green: 0.96, blue: 0.93, alpha: 1))
  ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
  ctx.setStrokeColor(CGColor(red: 0.62, green: 0.75, blue: 0.70, alpha: 0.35))
  ctx.setLineWidth(1.2)
  for k in stride(from: 0, to: height, by: 14) {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 0, y: CGFloat(k)))
    for x in stride(from: 0, through: width, by: 8) {
      path.addLine(to: CGPoint(x: CGFloat(x), y: CGFloat(k) + 5 * sin(CGFloat(x) / 45 + CGFloat(k))))
    }
    ctx.addPath(path)
  }
  ctx.strokePath()

  // Header band + synthetic stamp.
  ctx.setFillColor(CGColor(red: 0.16, green: 0.36, blue: 0.33, alpha: 1))
  ctx.fill(CGRect(x: 0, y: height - 90, width: width, height: 90))
  draw(
    ctx, "SYNTHETIC TEST CARD — NOT A REAL DOCUMENT", font: font("Helvetica-Bold", 34),
    x: 40, y: CGFloat(height - 58), alignRight: false, maxX: 0,
    color: CGColor(gray: 1, alpha: 1))

  // Photo placeholder box on the left.
  ctx.setFillColor(CGColor(gray: 0.78, alpha: 1))
  ctx.fill(CGRect(x: 40, y: 150, width: 250, height: 320))

  let arFont = font(arFontName, 38)
  let enFont = font(enFontName, 32)
  var y = CGFloat(height - 150)
  for line in lines {
    switch line.script {
    case "arabic":
      draw(ctx, line.text, font: arFont, x: 0, y: y, alignRight: true, maxX: CGFloat(width - 40))
      y -= 58
    case "latin":
      draw(ctx, line.text, font: enFont, x: 330, y: y, alignRight: false, maxX: 0)
      y -= 50
    default:
      draw(ctx, line.text, font: font(arFontName, 34), x: 330, y: 60, alignRight: false, maxX: 0)
    }
  }

  let card = Card(
    id: String(format: "card%02d", index), arabicFont: arFontName, latinFont: enFontName,
    lines: lines)
  return (card, ctx.makeImage()!)
}

// MARK: - Degradations (simulating a hand-held phone capture after rectification)

let ciContext = CIContext()

func ciToCG(_ image: CIImage, _ extent: CGRect) -> CGImage {
  ciContext.createCGImage(image, from: extent)!
}

func scaled(_ img: CGImage, by s: CGFloat) -> CGImage {
  let w = Int(CGFloat(img.width) * s), h = Int(CGFloat(img.height) * s)
  let ctx = makeContext(w, h)
  ctx.interpolationQuality = .high
  ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
  return ctx.makeImage()!
}

func blurred(_ img: CGImage, sigma: Double) -> CGImage {
  let ci = CIImage(cgImage: img).clampedToExtent().applyingGaussianBlur(sigma: sigma)
  return ciToCG(ci, CGRect(x: 0, y: 0, width: img.width, height: img.height))
}

/// A soft specular highlight over part of the card, like lamination under a lamp.
func withGlare(_ img: CGImage, center: CGPoint, radius: CGFloat) -> CGImage {
  let ctx = makeContext(img.width, img.height)
  ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
  let colors = [CGColor(gray: 1, alpha: 0.97), CGColor(gray: 1, alpha: 0.6), CGColor(gray: 1, alpha: 0)] as CFArray
  let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(), colors: colors, locations: [0, 0.45, 1])!
  ctx.drawRadialGradient(
    gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius,
    options: [])
  return ctx.makeImage()!
}

func rotated(_ img: CGImage, degrees: CGFloat) -> CGImage {
  let ctx = makeContext(img.width, img.height)
  ctx.setFillColor(CGColor(gray: 0.3, alpha: 1))
  ctx.fill(CGRect(x: 0, y: 0, width: img.width, height: img.height))
  ctx.translateBy(x: CGFloat(img.width) / 2, y: CGFloat(img.height) / 2)
  ctx.rotate(by: degrees * .pi / 180)
  ctx.draw(img, in: CGRect(x: -img.width / 2, y: -img.height / 2, width: img.width, height: img.height))
  return ctx.makeImage()!
}

/// Additive sensor-like noise, then a low-quality JPEG round trip.
func noisyJpeg(_ img: CGImage, quality: Double) -> CGImage {
  let noise = CIFilter(name: "CIRandomGenerator")!.outputImage!
    .transformed(by: CGAffineTransform(scaleX: 1.5, y: 1.5))
    .applyingFilter("CIColorMatrix", parameters: [
      "inputRVector": CIVector(x: 0.10, y: 0, z: 0, w: 0),
      "inputGVector": CIVector(x: 0.10, y: 0, z: 0, w: 0),
      "inputBVector": CIVector(x: 0.10, y: 0, z: 0, w: 0),
      "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
      "inputBiasVector": CIVector(x: -0.05, y: -0.05, z: -0.05, w: 0),
    ])
  let ci = noise.applyingFilter("CIAdditionCompositing", parameters: [
    kCIInputBackgroundImageKey: CIImage(cgImage: img)
  ])
  let noisy = ciToCG(ci, CGRect(x: 0, y: 0, width: img.width, height: img.height))
  let rep = NSBitmapImageRep(cgImage: noisy)
  let data = rep.representation(using: .jpeg, properties: [.compressionFactor: quality])!
  return NSBitmapImageRep(data: data)!.cgImage!
}

func writePNG(_ img: CGImage, _ name: String) {
  let rep = NSBitmapImageRep(cgImage: img)
  try! rep.representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent(name))
}

// MARK: - Main

var cards: [Card] = []
for i in 0..<cardCount {
  let (card, clean) = renderCard(i)
  cards.append(card)
  let variants: [(String, CGImage)] = [
    ("clean", clean),
    // Roughly what a card filling ~35% of a 1080p frame yields after
    // rectification: the minimum the capture guidance accepts.
    ("lowres", scaled(clean, by: 0.5)),
    ("blur", blurred(clean, sigma: 1.6)),
    ("glare", withGlare(clean, center: CGPoint(x: CGFloat(width) * 0.80, y: CGFloat(height) * 0.72), radius: 240)),
    ("rotated", rotated(clean, degrees: 3)),
    ("noisy_jpeg", noisyJpeg(clean, quality: 0.35)),
  ]
  for (name, img) in variants {
    writePNG(img, "\(card.id)_\(name).png")
  }
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
try encoder.encode(cards).write(to: outDir.appendingPathComponent("ground_truth.json"))
print("wrote \(cards.count) cards x 6 variants to \(outDir.path)")
