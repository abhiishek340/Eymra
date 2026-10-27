#!/usr/bin/env swift
// Generates Fixtures/*.jpg (900×1200 or 1200×900, with EXIF date + GPS) and Fixtures/features.json
// (photo records + synthetic feature records). Deterministic: same output every run.
// Usage: swift scripts/make-fixtures.swift [outputDir]
import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: Deterministic RNG
struct RNG {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state >> 11
    }
    mutating func float() -> Float { Float(next() % 1_000_000) / 1_000_000 }
    mutating func gauss() -> Float {
        let u = max(1e-6, float()), v = float()
        return (-2 * log(u)).squareRoot() * cos(2 * .pi * v)
    }
}
var rng = RNG(state: 42)

func unit(_ v: [Float]) -> [Float] {
    let n = v.reduce(0) { $0 + $1 * $1 }.squareRoot()
    return v.map { $0 / max(n, 1e-6) }
}
func randomUnit(_ dim: Int) -> [Float] { unit((0..<dim).map { _ in rng.gauss() }) }
let dim = 32

// MARK: Fixture plan
enum Kind: String { case me, meWithView, group, view, food, detail, receipt, screenshot }
struct Shot {
    var scene: Int
    var moment: String
    var kind: Kind
    var minute: Double         // minutes after the scene start
    var faces = 0
    var blurry = false
    var eyesClosed = false
    var dark = false
    var bright = false
    var favorite = false
    var landscape = false
    var boost: Float = 0       // nudges aesthetics/capture quality up or down inside a cluster
    var notMe = false          // a friend on their own: the user is not in this shot
}
struct Place { var name: String; var lat: Double; var lon: Double; var startHour: Int; var startMinute: Int
    var sky: (CGFloat, CGFloat, CGFloat); var ground: (CGFloat, CGFloat, CGFloat) }

let places = [
    Place(name: "Cafe", lat: 46.0207, lon: 7.7491, startHour: 8, startMinute: 30, sky: (0.55, 0.38, 0.25), ground: (0.85, 0.75, 0.6)),
    Place(name: "Ridge", lat: 46.0010, lon: 7.7860, startHour: 10, startMinute: 12, sky: (0.35, 0.6, 0.95), ground: (0.45, 0.5, 0.35)),
    Place(name: "Lake", lat: 46.0350, lon: 7.7200, startHour: 12, startMinute: 30, sky: (0.6, 0.8, 0.95), ground: (0.1, 0.45, 0.6)),
    Place(name: "Town", lat: 46.0240, lon: 7.7470, startHour: 15, startMinute: 0, sky: (0.75, 0.75, 0.8), ground: (0.6, 0.45, 0.4)),
    Place(name: "Sunset", lat: 46.0120, lon: 7.7600, startHour: 18, startMinute: 40, sky: (0.95, 0.5, 0.3), ground: (0.25, 0.15, 0.3)),
]

var shots: [Shot] = []
// Scene 0 – café: two food near-dups, two selfie near-dups.
shots += [Shot(scene: 0, moment: "latte", kind: .food, minute: 0, boost: 0.1),
          Shot(scene: 0, moment: "latte", kind: .food, minute: 0.3, blurry: true),
          Shot(scene: 0, moment: "cafeSelfie", kind: .me, minute: 4, faces: 1),
          Shot(scene: 0, moment: "cafeSelfie", kind: .me, minute: 4.2, faces: 1, boost: 0.15)]
// Scene 1 – ridge: an 8-frame posing series, me-with-view pair, views, a detail.
for i in 0..<8 {
    shots.append(Shot(scene: 1, moment: "ridgePose", kind: .me, minute: Double(i) * 0.4, faces: 1,
                      blurry: i == 2, eyesClosed: i == 5, boost: i == 6 ? 0.25 : Float(i) * 0.01))
}
shots += [Shot(scene: 1, moment: "ridgeSmall", kind: .meWithView, minute: 8, faces: 1, landscape: true),
          Shot(scene: 1, moment: "ridgeSmall", kind: .meWithView, minute: 8.3, faces: 1, landscape: true, boost: 0.1),
          Shot(scene: 1, moment: "ridgeView", kind: .view, minute: 14, landscape: true, boost: 0.2),
          Shot(scene: 1, moment: "ridgeView", kind: .view, minute: 14.2, landscape: true),
          Shot(scene: 1, moment: "valley", kind: .view, minute: 20, landscape: true),
          Shot(scene: 1, moment: "flower", kind: .detail, minute: 28)]
// Scene 2 – lake: a group series, a view pair, two poses on the same backdrop.
for i in 0..<4 { shots.append(Shot(scene: 2, moment: "lakeGroup", kind: .group, minute: Double(i) * 0.5, faces: i == 3 ? 4 : 3, boost: i == 1 ? 0.2 : 0)) }
shots += [Shot(scene: 2, moment: "lakeView", kind: .view, minute: 6, favorite: true, landscape: true),
          Shot(scene: 2, moment: "lakeView", kind: .view, minute: 6.2, landscape: true),
          Shot(scene: 2, moment: "lakeMeA", kind: .me, minute: 10, faces: 1, boost: 0.1),
          Shot(scene: 2, moment: "lakeMeB", kind: .me, minute: 13, faces: 1)]
// Scene 3 – town: architecture, dessert, me-with-view, a receipt.
shots += [Shot(scene: 3, moment: "church", kind: .view, minute: 0, boost: 0.1),
          Shot(scene: 3, moment: "church", kind: .view, minute: 0.4),
          Shot(scene: 3, moment: "square", kind: .view, minute: 6, landscape: true),
          Shot(scene: 3, moment: "gelato", kind: .food, minute: 10, boost: 0.1),
          Shot(scene: 3, moment: "gelato", kind: .food, minute: 10.2),
          Shot(scene: 3, moment: "townFriend", kind: .meWithView, minute: 15, faces: 1, notMe: true),
          Shot(scene: 3, moment: "receipt", kind: .receipt, minute: 18)]
// Scene 4 – sunset: a view series with a blown-out frame, a selfie pair, one too dark, a screenshot.
shots += [Shot(scene: 4, moment: "sunsetView", kind: .view, minute: 0, landscape: true, boost: 0.2),
          Shot(scene: 4, moment: "sunsetView", kind: .view, minute: 0.3, bright: true, landscape: true),
          Shot(scene: 4, moment: "sunsetView", kind: .view, minute: 0.6, landscape: true),
          Shot(scene: 4, moment: "sunsetMe", kind: .me, minute: 5, faces: 1, boost: 0.1),
          Shot(scene: 4, moment: "sunsetMe", kind: .me, minute: 5.3, faces: 1),
          Shot(scene: 4, moment: "sunsetMe", kind: .me, minute: 5.5, faces: 1, dark: true),
          Shot(scene: 4, moment: "screen", kind: .screenshot, minute: 40)]
precondition(shots.count == 40, "expected 40 fixtures, got \(shots.count)")

// MARK: Synthetic vectors
var placeVectors = places.map { _ in randomUnit(dim) }
var momentVectors: [String: [Float]] = [:]
// Two poses on the same lake backdrop share a background: small moment spread.
let spread: [String: Float] = ["lakeMeA": 0.5, "lakeMeB": 0.5]

// MARK: Output
let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Fixtures")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone.current
let baseDay = DateComponents(year: 2026, month: 10, day: 24)
let exifFormatter = DateFormatter()
exifFormatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
exifFormatter.timeZone = calendar.timeZone

struct Face: Codable { var box: Box; var captureQuality: Float?; var eyesClosed: Bool; var smiling: Bool; var print: [Float] }
struct Box: Codable { var x: Float; var y: Float; var width: Float; var height: Float }
struct Label: Codable { var identifier: String; var confidence: Float }
struct Geo: Codable { var latitude: Double; var longitude: Double; var horizontalAccuracy: Double }
struct Record: Codable {
    var id: String; var file: String; var creationDate: Date; var modificationDate: Date?; var location: Geo?
    var isFavorite: Bool; var pixelWidth: Int; var pixelHeight: Int; var isScreenshot: Bool; var isAnimated: Bool
    var burstIdentifier: String?; var moment: String; var kind: String
}
struct Feature: Codable {
    var photoID: String; var schemaVersion: Int; var featurePrint: [Float]; var featurePrintRevision: Int
    var aestheticScore: Float?; var isUtility: Bool; var faces: [Face]; var humanBoxes: [Box]; var saliencyBox: Box?
    var labels: [Label]; var horizonDegrees: Float?; var sharpness: Float; var darkFraction: Float
    var brightFraction: Float; var meanLuma: Float; var thumb32: [UInt8]
}
struct Reference: Codable { var prints: [[Float]] }
struct Fixture: Codable { var photos: [Record]; var features: [Feature]; var meReference: Reference }

// Face identities: the user, and a few friends. A face print is its identity plus small noise.
let meFace = randomUnit(dim)
let friendFaces = (0..<4).map { _ in randomUnit(dim) }
func facePrint(_ identity: [Float]) -> [Float] { unit((0..<dim).map { identity[$0] + 0.04 * rng.gauss() }) }

func draw(_ s: Shot, place: Place, momentSeed: Float, width: Int, height: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let w = CGFloat(width), h = CGFloat(height)
    func rgb(_ c: (CGFloat, CGFloat, CGFloat), _ k: CGFloat = 1) -> CGColor { CGColor(red: c.0 * k, green: c.1 * k, blue: c.2 * k, alpha: 1) }
    let horizon = h * (0.35 + 0.2 * CGFloat(momentSeed))
    ctx.setFillColor(rgb(place.ground)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: horizon))
    ctx.setFillColor(rgb(place.sky)); ctx.fill(CGRect(x: 0, y: horizon, width: w, height: h - horizon))
    // Moment-specific scenery: a sun and some hills.
    ctx.setFillColor(CGColor(red: 1, green: 0.9, blue: 0.5, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: w * CGFloat(momentSeed) * 0.8, y: h * 0.75, width: w * 0.12, height: w * 0.12))
    ctx.setFillColor(rgb(place.ground, 0.7))
    for i in 0..<4 {
        let x = w * CGFloat((Float(i) * 0.3 + momentSeed).truncatingRemainder(dividingBy: 1.2)) - w * 0.1
        ctx.fillEllipse(in: CGRect(x: x, y: horizon - h * 0.08, width: w * 0.5, height: h * 0.16))
    }
    switch s.kind {
    case .food:
        ctx.setFillColor(CGColor(gray: 0.97, alpha: 1)); ctx.fillEllipse(in: CGRect(x: w * 0.2, y: h * 0.25, width: w * 0.6, height: w * 0.6))
        ctx.setFillColor(CGColor(red: 0.6, green: 0.35, blue: 0.15, alpha: 1)); ctx.fillEllipse(in: CGRect(x: w * 0.32, y: h * 0.25 + w * 0.12, width: w * 0.36, height: w * 0.36))
    case .detail:
        ctx.setFillColor(CGColor(red: 0.9, green: 0.2, blue: 0.5, alpha: 1))
        for k in 0..<6 { let a = CGFloat(k) * .pi / 3
            ctx.fillEllipse(in: CGRect(x: w * 0.45 + cos(a) * w * 0.06, y: h * 0.45 + sin(a) * w * 0.06, width: w * 0.08, height: w * 0.08)) }
    case .receipt, .screenshot:
        ctx.setFillColor(CGColor(gray: 0.98, alpha: 1)); ctx.fill(CGRect(x: w * 0.1, y: h * 0.05, width: w * 0.8, height: h * 0.9))
        ctx.setFillColor(CGColor(gray: 0.2, alpha: 1))
        for k in 0..<18 { ctx.fill(CGRect(x: w * 0.18, y: h * 0.1 + CGFloat(k) * h * 0.045, width: w * (0.3 + 0.03 * CGFloat(k % 5)), height: h * 0.012)) }
    default: break
    }
    // People.
    let big = s.kind == .me
    for f in 0..<s.faces {
        let r = big ? w * 0.16 : (s.kind == .group ? w * 0.08 : w * 0.035)
        let cx = s.faces == 1 ? w * (0.45 + 0.05 * CGFloat(momentSeed)) : w * (0.2 + 0.6 * CGFloat(f) / CGFloat(max(1, s.faces - 1)))
        let cy = big ? h * 0.55 : h * 0.4
        ctx.setFillColor(CGColor(red: 0.2, green: 0.3, blue: 0.7, alpha: 1))
        ctx.fill(CGRect(x: cx - r * 0.9, y: cy - r * 3.2, width: r * 1.8, height: r * 2.4))
        ctx.setFillColor(CGColor(red: 0.95, green: 0.78, blue: 0.65, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
        ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
        let eyeH = s.eyesClosed ? r * 0.05 : r * 0.22
        ctx.fillEllipse(in: CGRect(x: cx - r * 0.45, y: cy + r * 0.15, width: r * 0.22, height: eyeH))
        ctx.fillEllipse(in: CGRect(x: cx + r * 0.23, y: cy + r * 0.15, width: r * 0.22, height: eyeH))
        ctx.fill(CGRect(x: cx - r * 0.35, y: cy - r * 0.45, width: r * 0.7, height: r * 0.08))
    }
    var image = ctx.makeImage()!
    if s.blurry || s.dark || s.bright {
        var ci = CIImage(cgImage: image)
        if s.blurry { ci = ci.clampedToExtent().applyingGaussianBlur(sigma: 14).cropped(to: CGRect(x: 0, y: 0, width: w, height: h)) }
        if s.dark { ci = ci.applyingFilter("CIColorControls", parameters: ["inputBrightness": -0.75, "inputContrast": 0.6]) }
        if s.bright { ci = ci.applyingFilter("CIExposureAdjust", parameters: ["inputEV": 3.0]) }
        image = CIContext().createCGImage(ci, from: CGRect(x: 0, y: 0, width: w, height: h))!
    }
    return image
}

func grey32(_ image: CGImage) -> [UInt8] {
    var buf = [UInt8](repeating: 0, count: 1024)
    buf.withUnsafeMutableBytes { raw in
        let ctx = CGContext(data: raw.baseAddress, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 32,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: 32, height: 32))
    }
    return buf
}

var records: [Record] = []
var features: [Feature] = []
var momentSeeds: [String: Float] = [:]

for (index, s) in shots.enumerated() {
    let place = places[s.scene]
    var comps = baseDay
    comps.hour = place.startHour
    comps.minute = place.startMinute
    let date = calendar.date(from: comps)!.addingTimeInterval(s.minute * 60 + Double(index % 3))
    let file = String(format: "fixture-%02d.jpg", index + 1)
    let id = String(format: "fixture-%02d", index + 1)
    let (width, height) = s.landscape ? (1200, 900) : (900, 1200)
    let seed = momentSeeds[s.moment] ?? rng.float()
    momentSeeds[s.moment] = seed
    let image = draw(s, place: place, momentSeed: seed, width: width, height: height)

    // JPEG with EXIF date and GPS (screenshots and receipts carry no GPS).
    var props: [CFString: Any] = [
        kCGImageDestinationLossyCompressionQuality: 0.6,
        kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: exifFormatter.string(from: date),
                                         kCGImagePropertyExifDateTimeDigitized: exifFormatter.string(from: date)],
        kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFDateTime: exifFormatter.string(from: date)],
    ]
    let hasGPS = s.kind != .screenshot && s.kind != .receipt
    let jitter = Double(index) * 0.00002
    if hasGPS {
        props[kCGImagePropertyGPSDictionary] = [
            kCGImagePropertyGPSLatitude: place.lat + jitter, kCGImagePropertyGPSLatitudeRef: "N",
            kCGImagePropertyGPSLongitude: place.lon + jitter, kCGImagePropertyGPSLongitudeRef: "E",
            kCGImagePropertyGPSHPositioningError: 10.0,
        ]
    }
    let url = outDir.appendingPathComponent(file)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, props as CFDictionary)
    precondition(CGImageDestinationFinalize(dest))

    // Synthetic features: place vector + moment offset + per-frame noise, normalised (distances 0–2).
    let momentVector = momentVectors[s.moment] ?? randomUnit(dim)
    momentVectors[s.moment] = momentVector
    let k = spread[s.moment] ?? 0.9
    let raw = (0..<dim).map { placeVectors[s.scene][$0] + k * momentVector[$0] + 0.04 * rng.gauss() }
    let print = unit(raw)

    var faces: [Face] = []
    for f in 0..<s.faces {
        let size: Float = s.kind == .me ? 0.32 : (s.kind == .group ? 0.16 : 0.06)
        let x: Float = s.faces == 1 ? 0.4 : 0.1 + 0.6 * Float(f) / Float(max(1, s.faces - 1))
        // In group shots the user is the first face; a "notMe" shot shows a friend only.
        var identity = (f == 0 && !s.notMe) ? meFace : friendFaces[(f + (s.notMe ? 0 : 3)) % friendFaces.count]
        // One pose at the lake is turned away: it only partly looks like you, so the app should ask.
        if s.moment == "lakeMeB" { identity = unit((0..<dim).map { 0.47 * meFace[$0] + 0.88 * friendFaces[2][$0] }) }
        faces.append(Face(box: Box(x: x, y: 0.3, width: size, height: size * 0.75),
                          captureQuality: min(1, 0.55 + s.boost + 0.1 * rng.float()),
                          eyesClosed: s.eyesClosed, smiling: s.boost > 0.12, print: facePrint(identity)))
    }
    var labels: [Label] = []
    var saliency: Box?
    switch s.kind {
    case .food: labels = [Label(identifier: "food", confidence: 0.92), Label(identifier: "drink", confidence: 0.4)]
        saliency = Box(x: 0.2, y: 0.3, width: 0.6, height: 0.45)
    case .view: labels = [Label(identifier: "outdoor", confidence: 0.9), Label(identifier: "mountain", confidence: 0.6), Label(identifier: "sky", confidence: 0.7)]
        saliency = Box(x: 0.25 + 0.2 * seed, y: 0.3, width: 0.35, height: 0.3)
    case .meWithView: labels = [Label(identifier: "outdoor", confidence: 0.85), Label(identifier: "landscape", confidence: 0.6)]
        saliency = Box(x: 0.42, y: 0.4, width: 0.12, height: 0.25)
    case .me: labels = [Label(identifier: "people", confidence: 0.8), Label(identifier: "outdoor", confidence: 0.4)]
        saliency = Box(x: 0.3, y: 0.2, width: 0.4, height: 0.6)
    case .group: labels = [Label(identifier: "people", confidence: 0.9), Label(identifier: "lake", confidence: 0.5)]
        saliency = Box(x: 0.1, y: 0.25, width: 0.8, height: 0.5)
    case .detail: labels = [Label(identifier: "flower", confidence: 0.7)]
        saliency = Box(x: 0.42, y: 0.42, width: 0.16, height: 0.12)
    case .receipt, .screenshot: labels = [Label(identifier: "document", confidence: 0.9)]
    }
    let sharp: Float = s.blurry ? 8 : 250 + 400 * rng.float() + 600 * s.boost
    let aesthetic: Float = s.kind == .receipt ? -0.6 : -0.1 + 0.5 * rng.float() + 1.2 * s.boost
    let thumb = grey32(image)
    let mean = Float(thumb.reduce(0) { $0 + Int($1) }) / 1024

    records.append(Record(id: id, file: file, creationDate: date, modificationDate: nil,
                          location: hasGPS ? Geo(latitude: place.lat + jitter, longitude: place.lon + jitter, horizontalAccuracy: 10) : nil,
                          isFavorite: s.favorite, pixelWidth: width, pixelHeight: height,
                          isScreenshot: s.kind == .screenshot, isAnimated: false, burstIdentifier: nil,
                          moment: s.moment, kind: s.kind.rawValue))
    features.append(Feature(photoID: id, schemaVersion: 4, featurePrint: print, featurePrintRevision: 2,
                            aestheticScore: aesthetic, isUtility: s.kind == .receipt, faces: faces,
                            humanBoxes: faces.map { Box(x: $0.box.x - 0.05, y: 0.25, width: $0.box.width + 0.1, height: 0.7) },
                            saliencyBox: saliency, labels: labels,
                            horizonDegrees: s.kind == .view ? (index % 2 == 0 ? 1.5 : 6) : nil,
                            sharpness: sharp, darkFraction: s.dark ? 0.78 : 0.01, brightFraction: s.bright ? 0.45 : 0.005,
                            meanLuma: mean, thumb32: thumb))
}

let encoder = JSONEncoder()
encoder.dateEncodingStrategy = .iso8601
encoder.outputFormatting = [.sortedKeys]
try encoder.encode(Fixture(photos: records, features: features,
                           meReference: Reference(prints: (0..<5).map { _ in facePrint(meFace) }))).write(to: outDir.appendingPathComponent("features.json"))
print("Wrote \(records.count) fixtures to \(outDir.path)")
