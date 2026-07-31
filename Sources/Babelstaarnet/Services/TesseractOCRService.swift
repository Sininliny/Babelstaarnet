import AppKit
import Foundation

enum TesseractError: LocalizedError {
    case unavailable
    case imageEncodingFailed
    case executionFailed(String)
    case unreadableOutput

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Tesseract with Danish language data is not installed."
        case .imageEncodingFailed:
            return "The captured display could not be encoded for Tesseract."
        case let .executionFailed(message):
            return "Tesseract failed: \(message)"
        case .unreadableOutput:
            return "Tesseract returned unreadable OCR data."
        }
    }
}

struct TesseractOCRService {
    var isAvailable: Bool {
        executableURL != nil
    }

    func isDanishReady() async -> Bool {
        guard let executableURL else {
            return false
        }

        return await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = executableURL
            process.arguments = ["--list-langs"]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = output

            do {
                try process.run()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0,
                      let text = String(data: data, encoding: .utf8) else {
                    return false
                }
                return text
                    .split(whereSeparator: \.isWhitespace)
                    .contains("dan")
            } catch {
                return false
            }
        }.value
    }

    func recognize(in capture: CapturedDisplay) async throws -> [TextRegion] {
        guard let executableURL else {
            throw TesseractError.unavailable
        }

        return try await Task.detached(priority: .userInitiated) {
            let bitmap = NSBitmapImageRep(cgImage: capture.image)
            guard let png = bitmap.representation(using: .png, properties: [:]) else {
                throw TesseractError.imageEncodingFailed
            }

            let normalTSV = try Self.runTesseract(
                executableURL: executableURL,
                png: png,
                automaticInversion: true,
                pageSegmentationMode: capture.frame == capture.screenFrame
                    ? 3
                    : 6
            )
            let normalRegions = Self.parse(
                tsv: normalTSV,
                imageSize: CGSize(
                    width: capture.image.width,
                    height: capture.image.height
                ),
                captureFrame: capture.frame,
                screenFrame: capture.screenFrame,
                displayID: capture.displayID
            )

            guard let invertedPNG = Self.invertedHighContrastPNG(
                from: capture.image
            ), let invertedTSV = try? Self.runTesseract(
                executableURL: executableURL,
                png: invertedPNG,
                automaticInversion: false,
                pageSegmentationMode: capture.frame == capture.screenFrame
                    ? 3
                    : 6
            ) else {
                return normalRegions
            }
            let invertedRegions = Self.parse(
                tsv: invertedTSV,
                imageSize: CGSize(
                    width: capture.image.width,
                    height: capture.image.height
                ),
                captureFrame: capture.frame,
                screenFrame: capture.screenFrame,
                displayID: capture.displayID
            )

            let contrastRegions: [TextRegion]
            if let chromaPNG = Self.lightTextOnColorPNG(from: capture.image),
               let chromaTSV = try? Self.runTesseract(
                   executableURL: executableURL,
                   png: chromaPNG,
                   automaticInversion: false,
                   pageSegmentationMode: 3
               ) {
                contrastRegions = Self.parse(
                    tsv: chromaTSV,
                    imageSize: CGSize(
                        width: capture.image.width,
                        height: capture.image.height
                    ),
                    captureFrame: capture.frame,
                    screenFrame: capture.screenFrame,
                    displayID: capture.displayID
                )
            } else {
                contrastRegions = []
            }

            return Self.merge(
                Self.merge(normalRegions, with: invertedRegions),
                with: contrastRegions
            )
        }.value
    }

    private static func runTesseract(
        executableURL: URL,
        png: Data,
        automaticInversion: Bool,
        pageSegmentationMode: Int
    ) throws -> String {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = [
            "stdin",
            "stdout",
            "-l", "dan",
            "--oem", "1",
            "--psm", "\(pageSegmentationMode)",
            "--dpi", "144",
            "-c", "tessedit_do_invert=\(automaticInversion ? 1 : 0)",
            "tsv"
        ]

        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        try process.run()
        input.fileHandleForWriting.write(png)
        try input.fileHandleForWriting.close()

        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8) ?? "unknown error"
            throw TesseractError.executionFailed(
                message.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        guard let tsv = String(data: outputData, encoding: .utf8) else {
            throw TesseractError.unreadableOutput
        }
        return tsv
    }

    private static func invertedHighContrastPNG(
        from image: CGImage
    ) -> Data? {
        contrastPNG(
            from: image,
            source: .luminance,
            contrast: 1.65,
            inverted: true
        )
    }

    /// Separates light glyphs from saturated backgrounds by retaining the
    /// darkest RGB component. A red pixel therefore becomes dark while a
    /// white glyph remains light; inversion produces the dark-on-light input
    /// Tesseract handles most consistently. Automatic page segmentation keeps
    /// text inside banner and button outlines, which uniform-block mode can
    /// otherwise mistake for table structure.
    private static func lightTextOnColorPNG(
        from image: CGImage
    ) -> Data? {
        contrastPNG(
            from: image,
            source: .minimumRGB,
            contrast: 1.85,
            inverted: true
        )
    }

    private enum ContrastSource {
        case luminance
        case minimumRGB
    }

    /// Uses a deterministic CPU bitmap conversion instead of relying on a
    /// GPU-backed Core Image context. This also keeps the OCR passes available
    /// when screen capture is running while the display or GPU is asleep.
    private static func contrastPNG(
        from image: CGImage,
        source: ContrastSource,
        contrast: Double,
        inverted: Bool
    ) -> Data? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else {
            return nil
        }

        var rgba = [UInt8](
            repeating: 0,
            count: width * height * 4
        )
        let rendered = rgba.withUnsafeMutableBytes { bytes in
            guard let address = bytes.baseAddress,
                  let context = CGContext(
                      data: address,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: width * 4,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                          | CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else {
                return false
            }
            context.interpolationQuality = .none
            context.draw(
                image,
                in: CGRect(x: 0, y: 0, width: width, height: height)
            )
            return true
        }
        guard rendered else {
            return nil
        }

        var grayscale = [UInt8](
            repeating: 255,
            count: width * height
        )
        for pixelIndex in 0..<(width * height) {
            let rgbaIndex = pixelIndex * 4
            let alpha = Int(rgba[rgbaIndex + 3])
            let red = compositeOnWhite(
                Int(rgba[rgbaIndex]),
                alpha: alpha
            )
            let green = compositeOnWhite(
                Int(rgba[rgbaIndex + 1]),
                alpha: alpha
            )
            let blue = compositeOnWhite(
                Int(rgba[rgbaIndex + 2]),
                alpha: alpha
            )
            let component: Int
            switch source {
            case .luminance:
                component = (77 * red + 150 * green + 29 * blue) >> 8
            case .minimumRGB:
                component = min(red, green, blue)
            }
            let enhanced = Int(
                (Double(component - 128) * contrast + 128)
                    .rounded()
            )
            let clamped = min(max(enhanced, 0), 255)
            grayscale[pixelIndex] = UInt8(
                inverted ? 255 - clamped : clamped
            )
        }

        return grayscale.withUnsafeMutableBytes { bytes in
            guard let address = bytes.baseAddress,
                  let context = CGContext(
                      data: address,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: width,
                      space: CGColorSpaceCreateDeviceGray(),
                      bitmapInfo: CGImageAlphaInfo.none.rawValue
                  ),
                  let output = context.makeImage() else {
                return nil
            }
            return NSBitmapImageRep(cgImage: output)
                .representation(using: .png, properties: [:])
        }
    }

    private static func compositeOnWhite(
        _ component: Int,
        alpha: Int
    ) -> Int {
        (component * alpha + 255 * (255 - alpha)) / 255
    }

    private static func merge(
        _ primary: [TextRegion],
        with secondary: [TextRegion]
    ) -> [TextRegion] {
        var merged = primary
        for candidate in secondary {
            if let index = merged.firstIndex(where: {
                overlapRatio($0.frame, candidate.frame) >= 0.58
            }) {
                if recognitionScore(candidate) > recognitionScore(merged[index]) {
                    merged[index] = candidate
                }
            } else {
                merged.append(candidate)
            }
        }
        return merged.sorted {
            if abs($0.frame.midY - $1.frame.midY) > 4 {
                return $0.frame.midY > $1.frame.midY
            }
            return $0.frame.minX < $1.frame.minX
        }
    }

    private static func recognitionScore(_ region: TextRegion) -> Int {
        region.words.count * 20
            + region.sourceText.unicodeScalars.filter {
                CharacterSet.letters.contains($0)
            }.count
    }

    private static func overlapRatio(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else {
            return 0
        }
        let intersectionArea = intersection.width * intersection.height
        let smallerArea = min(
            lhs.width * lhs.height,
            rhs.width * rhs.height
        )
        return smallerArea > 0 ? intersectionArea / smallerArea : 0
    }

    private var executableURL: URL? {
        let fixedCandidates = [
            Bundle.main.resourceURL?
                .appendingPathComponent("LocalEngines/tesseract").path,
            "/opt/homebrew/bin/tesseract",
            "/usr/local/bin/tesseract",
            "/usr/bin/tesseract"
        ].compactMap { $0 }

        let pathCandidates = ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: ":")
            .map { String($0) + "/tesseract" } ?? []

        return (fixedCandidates + pathCandidates)
            .first(where: FileManager.default.isExecutableFile(atPath:))
            .map(URL.init(fileURLWithPath:))
    }

    private static func parse(
        tsv: String,
        imageSize: CGSize,
        captureFrame: CGRect,
        screenFrame: CGRect,
        displayID: CGDirectDisplayID
    ) -> [TextRegion] {
        struct LineKey: Hashable {
            let page: Int
            let block: Int
            let paragraph: Int
            let line: Int
        }

        struct ParsedWord {
            let order: Int
            let region: WordRegion
        }

        var wordsByLine: [LineKey: [ParsedWord]] = [:]
        var lineOrder: [LineKey] = []

        for row in tsv.split(whereSeparator: \.isNewline).dropFirst() {
            let columns = row.split(
                separator: "\t",
                omittingEmptySubsequences: false
            )
            guard columns.count >= 12,
                  columns[0] == "5",
                  let page = Int(columns[1]),
                  let block = Int(columns[2]),
                  let paragraph = Int(columns[3]),
                  let line = Int(columns[4]),
                  let wordNumber = Int(columns[5]),
                  let left = Double(columns[6]),
                  let top = Double(columns[7]),
                  let width = Double(columns[8]),
                  let height = Double(columns[9]),
                  let confidence = Double(columns[10]),
                  confidence >= 35 else {
                continue
            }

            let word = columns[11...]
                .joined(separator: "\t")
                .trimmingCharacters(
                    in: CharacterSet.whitespacesAndNewlines
                        .union(.punctuationCharacters)
                )
            guard !word.isEmpty else {
                continue
            }

            let pixelRect = CGRect(
                x: left,
                y: top,
                width: width,
                height: height
            )
            let globalFrame = globalRect(
                pixelRect,
                imageSize: imageSize,
                displayFrame: captureFrame
            )
            let key = LineKey(
                page: page,
                block: block,
                paragraph: paragraph,
                line: line
            )
            if wordsByLine[key] == nil {
                lineOrder.append(key)
            }
            wordsByLine[key, default: []].append(
                ParsedWord(
                    order: wordNumber,
                    region: WordRegion(
                        sourceText: word,
                        frame: globalFrame,
                        screenFrame: screenFrame,
                        displayID: displayID
                    )
                )
            )
        }

        return lineOrder.compactMap { key in
            let words = (wordsByLine[key] ?? [])
                .sorted { $0.order < $1.order }
                .map(\.region)
            guard !words.isEmpty else {
                return nil
            }

            let frame = words
                .dropFirst()
                .reduce(words[0].frame) { $0.union($1.frame) }
            return TextRegion(
                sourceText: words.map(\.sourceText).joined(separator: " "),
                frame: frame,
                screenFrame: screenFrame,
                displayID: displayID,
                words: words
            )
        }
    }

    private static func globalRect(
        _ pixelRect: CGRect,
        imageSize: CGSize,
        displayFrame: CGRect
    ) -> CGRect {
        let scaleX = displayFrame.width / imageSize.width
        let scaleY = displayFrame.height / imageSize.height
        return CGRect(
            x: displayFrame.minX + (pixelRect.minX * scaleX),
            y: displayFrame.minY
                + ((imageSize.height - pixelRect.maxY) * scaleY),
            width: pixelRect.width * scaleX,
            height: pixelRect.height * scaleY
        )
    }
}
