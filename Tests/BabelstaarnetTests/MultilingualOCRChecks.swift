import AppKit
import BabelCore
import Foundation
import LanguagePacks
@testable import BabelOCR

@main enum MultilingualOCRChecks {
    struct Root: Decodable { let ocr: Rules }
    struct Rules: Decodable { let spacing: [Spacing]; let scales: [Scale]; let colours: [Colours] }
    struct Spacing: Decodable { let text, compact: String }
    struct Scale: Decodable { let height, scale: Double; let cjk: Bool; let width, imageHeight, maximum: Int }
    struct Colours: Decodable { let background, foreground: [UInt8] }
    struct Corpus: Decodable {
        struct Sample: Decodable { let language, text, focus: String }
        struct Appearance: Decodable { let id, foreground, background: String; let end: String? }
        let samples: [Sample]; let appearances: [Appearance]; let sizes: [Int]
    }
    @MainActor static func main() async throws {
        let shared = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Shared")
        let rules = try JSONDecoder().decode(Root.self, from: Data(contentsOf: shared.appendingPathComponent("reading-contract.json"))).ocr
        for c in rules.spacing {
            precondition(ReadingText.compactCjkSpacing(c.text) == c.compact)
            let ranges = ReadingText.ocrWordRanges(in: c.text, language: .simplifiedChinese)
            precondition(ranges.allSatisfy { !$0.isEmpty })
            if c.text.contains("学 习") { precondition(ranges.contains { ReadingText.compactCjkSpacing(String(c.text[$0])) == "学习" }) }
        }
        for c in rules.scales { precondition(abs(SharedPolicy.ocrScale(glyphHeight: c.height, cjk: c.cjk, width: c.width, height: c.imageHeight, maximum: c.maximum) - c.scale) < 0.001) }
        for c in rules.colours {
            let rgba: [UInt8] = (0..<100).flatMap { index -> [UInt8] in (index % 10 == 1 ? c.foreground : c.background) + [UInt8(255)] }
            guard let gray = SharedPolicy.separateOCR(rgba, width: 10, height: 10) else { preconditionFailure("Colour separation failed") }
            precondition(Int(gray[0]) - Int(gray[1]) >= 160)
        }
        precondition(SharedPolicy.separateOCR([UInt8](repeating: 255, count: 400), width: 10, height: 10) == nil)
        let english = LanguagePair.configured(source: "en", target: "da").source
        precondition(OCRTextQualityPolicy(language: english).isPlausibleWord("iOS"))
        let cjk = LanguagePair.configured(source: "zh-Hans", target: "en").source
        precondition(OCRTextQualityPolicy(language: cjk).isPlausibleWord("iOS系统"))
        let corpus = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: shared.appendingPathComponent("ocr-corpus.json")))
        var report: [[String: Any]] = []
        for sample in corpus.samples {
            let language = LanguagePair.configured(source: sample.language, target: sample.language == "en" ? "da" : "en").source
            for appearance in corpus.appearances {
                for size in corpus.sizes {
                    for serif in [false, true] {
                        let name = language.code.hasPrefix("zh") ? serif ? "Songti SC" : language.code == "zh-Hant" ? "PingFang TC" : "PingFang SC" : serif ? "Times New Roman Italic" : ".AppleSystemUIFont"
                        let font = NSFont(name: name, size: CGFloat(size)) ?? .systemFont(ofSize: CGFloat(size))
                        let (image, point) = try render(sample, appearance, font)
                        let frame = CGRect(x: 120, y: 60, width: image.width, height: image.height)
                        let capture = CapturedDisplay(displayID: 1, image: image, frame: frame)
                        let started = CFAbsoluteTimeGetCurrent()
                        let result = try await OCRService(language: language).recognizeText(in: capture, focusPoint: CGPoint(x: frame.minX + point.x, y: frame.minY + point.y))
                        let text = result.regions.map(\.sourceText).joined(separator: " ")
                        let error = characterError(sample.text, text)
                        report.append(["language": sample.language, "appearance": appearance.id, "size": size, "font": font.fontName, "characterError": error, "recognized": text, "milliseconds": (CFAbsoluteTimeGetCurrent()-started)*1000])
                        if appearance.id == "paper", size >= 16 { precondition(error <= 0.2, "Ordinary text failed: \(sample.language) \(size) \(font.fontName): \(text)") }
                    }
                }
            }
            // Single-character words are real reading units in Chinese and English.
            let word = sample.language.hasPrefix("zh") ? "我" : "I"
            let (image, point) = try render(.init(language: sample.language, text: word, focus: word), .init(id: "single", foreground: "#181818", background: "#ffffff", end: nil), .systemFont(ofSize: 28))
            if sample.language != "da" {
                let result = try await OCRService(language: language).recognizeText(in: CapturedDisplay(displayID: 1, image: image, frame: CGRect(x: 0, y: 0, width: image.width, height: image.height)), focusPoint: point)
                precondition(result.regions.flatMap(\.words).contains { $0.sourceText == word }, "Single-character OCR must survive routing")
            }
        }
        let root = shared.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("build")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: root.appendingPathComponent("mac-ocr-appearance.json"))
        for language in LanguageCatalog.languages {
            let rows = report.filter { $0["language"] as? String == language.id }
            let error = rows.reduce(0.0) { $0 + ($1["characterError"] as! Double) } / Double(rows.count)
            print("\(language.id): \(rows.count) generated OCR fixtures, mean character error \(String(format: "%.1f%%", error*100))")
        }
        print("Multilingual OCR pixel/geometry checks passed. Fixture timing excludes desktop capture.")
    }
    @MainActor static func render(_ sample: Corpus.Sample, _ style: Corpus.Appearance, _ font: NSFont) throws -> (CGImage, CGPoint) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: colour(style.foreground)]
        let text = sample.text as NSString
        let size = text.size(withAttributes: attributes), width = Int(ceil(size.width)) + 48, height = max(80, Int(ceil(size.height)) + 48)
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { throw NSError(domain: "Fixture", code: 1) }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let bounds = NSRect(x: 0, y: 0, width: width, height: height)
        colour(style.background).setFill(); bounds.fill()
        if let end = style.end { NSGradient(starting: colour(style.background), ending: colour(end))?.draw(in: bounds, angle: 0) }
        text.draw(at: NSPoint(x: 24, y: 24), withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
        let range = text.range(of: sample.focus)
        let prefix = text.substring(to: range.location) as NSString, focus = sample.focus as NSString
        let point = CGPoint(x: 24 + prefix.size(withAttributes: attributes).width + focus.size(withAttributes: attributes).width/2, y: 24 + size.height/2)
        return (bitmap.cgImage!, point)
    }
    static func colour(_ hex: String) -> NSColor {
        let value = UInt32(hex.dropFirst(), radix: 16)!
        return NSColor(srgbRed: CGFloat((value >> 16) & 255)/255, green: CGFloat((value >> 8)&255)/255, blue: CGFloat(value&255)/255, alpha: 1)
    }
    static func characterError(_ expected: String, _ actual: String) -> Double {
        let a = Array(expected.lowercased().filter { $0.isLetter || $0.isNumber }), b = Array(actual.lowercased().filter { $0.isLetter || $0.isNumber })
        var row = Array(0...b.count)
        for i in a.indices { var next = [i+1] + [Int](repeating: 0, count: b.count); for j in b.indices { next[j+1] = min(row[j+1]+1, next[j]+1, row[j] + (a[i] == b[j] ? 0 : 1)) }; row = next }
        return Double(row[b.count])/Double(max(1,a.count))
    }
}
