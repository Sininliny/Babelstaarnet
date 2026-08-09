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

private final class TesseractProcessController: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    func register(_ process: Process) {
        lock.lock()
        self.process = process
        let shouldTerminate = cancelled
        lock.unlock()
        if shouldTerminate, process.isRunning {
            process.terminate()
        }
    }

    func clear(_ process: Process) {
        lock.lock()
        if self.process === process {
            self.process = nil
        }
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let process = self.process
        lock.unlock()
        if process?.isRunning == true {
            process?.terminate()
        }
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

struct TesseractOCRService {
    /// One recognized line together with how sure Tesseract was about it,
    /// which is what decides between competing readings of the same place.
    private struct ScoredRegion {
        let region: TextRegion
        /// Mean per-word confidence, 0...100 as Tesseract reports it.
        let confidence: Double
    }

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

    func recognize(
        in capture: CapturedDisplay,
        prefersSmallText: Bool = false
    ) async throws -> [TextRegion] {
        guard let executableURL else {
            throw TesseractError.unavailable
        }

        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let bitmap = NSBitmapImageRep(cgImage: capture.image)
            guard let png = bitmap.representation(using: .png, properties: [:]) else {
                throw TesseractError.imageEncodingFailed
            }

            let imageSize = CGSize(
                width: capture.image.width,
                height: capture.image.height
            )
            let primaryPageSegmentation = capture.frame == capture.screenFrame
                ? 3
                : 6

            async let normalTSV = Self.runTesseract(
                executableURL: executableURL,
                png: png,
                automaticInversion: true,
                pageSegmentationMode: primaryPageSegmentation
            )

            // One colour-aware rewrite replaces the previous fixed-contrast
            // and minimum-channel passes. Because it derives its threshold
            // from the crop, it covers dark mode, saturated banners, and
            // low-contrast panels with the same two runs: block layout for
            // ordinary text, and automatic layout so text inside banner and
            // button outlines is not mistaken for table structure.
            //
            // Only the automatic-layout run re-enables Tesseract's own
            // inversion. Preparation applies one threshold to the whole crop,
            // so a crop holding two backgrounds leaves one of them
            // light-on-dark; automatic layout finds that region as its own
            // block and can invert it alone, which uniform-block mode, being
            // all-or-nothing, cannot.
            //
            // The capture is rasterized once here and the pixels are shared
            // with the small-text pass below, which otherwise converted the
            // same CGImage a second time before any Tesseract process started.
            let rasterized = OCRImagePreparation.rgbaPixels(
                from: capture.image
            )
            let separatedPNG = rasterized.flatMap {
                Self.separatedPNG(
                    rgba: $0,
                    width: capture.image.width,
                    height: capture.image.height
                )
            }
            async let blockTSV: String? = {
                guard let separatedPNG else {
                    return nil
                }
                return try? await Self.runTesseract(
                    executableURL: executableURL,
                    png: separatedPNG,
                    automaticInversion: false,
                    pageSegmentationMode: primaryPageSegmentation
                )
            }()
            async let layoutTSV: String? = {
                guard let separatedPNG,
                      primaryPageSegmentation != 3 else {
                    return nil
                }
                return try? await Self.runTesseract(
                    executableURL: executableURL,
                    png: separatedPNG,
                    automaticInversion: true,
                    pageSegmentationMode: 3
                )
            }()

            let eagerSmallImage = prefersSmallText
                ? rasterized.flatMap {
                    Self.smallTextPNG(
                        rgba: $0,
                        width: capture.image.width,
                        height: capture.image.height,
                        regions: []
                    )
                }
                : nil
            async let eagerSmallTSV: String? = {
                guard let eagerSmallImage else {
                    return nil
                }
                return try? await Self.runTesseract(
                    executableURL: executableURL,
                    png: eagerSmallImage.png,
                    automaticInversion: false,
                    pageSegmentationMode: 11,
                    dpi: 288
                )
            }()

            let passResults = try await (
                normalTSV,
                blockTSV,
                layoutTSV,
                eagerSmallTSV
            )
            try Task.checkCancellation()
            func parsePass(
                _ tsv: String?,
                size: CGSize,
                minimumConfidence: Double = 35
            ) -> [ScoredRegion] {
                guard let tsv else {
                    return []
                }
                return Self.parse(
                    tsv: tsv,
                    imageSize: size,
                    captureFrame: capture.frame,
                    screenFrame: capture.screenFrame,
                    displayID: capture.displayID,
                    minimumConfidence: minimumConfidence
                )
            }

            let mergedRegions = Self.merge(
                Self.merge(
                    parsePass(passResults.0, size: imageSize),
                    with: parsePass(passResults.1, size: imageSize)
                ),
                with: parsePass(passResults.2, size: imageSize)
            )
            if let eagerSmallImage,
               let eagerSmallTSV = passResults.3 {
                let eagerSmallRegions = parsePass(
                    eagerSmallTSV,
                    size: eagerSmallImage.size,
                    minimumConfidence: 22
                )
                try Task.checkCancellation()
                return Self.merge(
                    mergedRegions,
                    with: eagerSmallRegions
                ).map(\.region)
            }
            guard Self.needsSmallTextPass(mergedRegions),
                  let rasterized,
                  let smallImage = Self.smallTextPNG(
                      rgba: rasterized,
                      width: capture.image.width,
                      height: capture.image.height,
                      regions: mergedRegions.map(\.region)
                  ),
                  let smallTSV = try? await Self.runTesseract(
                      executableURL: executableURL,
                      png: smallImage.png,
                      automaticInversion: false,
                      pageSegmentationMode: 11,
                      dpi: 288
                  ) else {
                return mergedRegions.map(\.region)
            }
            let smallRegions = parsePass(
                smallTSV,
                size: smallImage.size,
                minimumConfidence: 22
            )
            try Task.checkCancellation()
            return Self.merge(
                mergedRegions,
                with: smallRegions
            ).map(\.region)
        }
        return try await withTaskCancellationHandler {
            do {
                let value = try await worker.value
                try Task.checkCancellation()
                return value
            } catch {
                if Task.isCancelled {
                    throw CancellationError()
                }
                throw error
            }
        } onCancel: {
            worker.cancel()
        }
    }

    private static func runTesseract(
        executableURL: URL,
        png: Data,
        automaticInversion: Bool,
        pageSegmentationMode: Int,
        dpi: Int = 144
    ) async throws -> String {
        let controller = TesseractProcessController()
        let worker = Task.detached(priority: .userInitiated) {
            try runTesseractSynchronously(
                executableURL: executableURL,
                png: png,
                automaticInversion: automaticInversion,
                pageSegmentationMode: pageSegmentationMode,
                dpi: dpi,
                controller: controller
            )
        }
        return try await withTaskCancellationHandler {
            do {
                let value = try await worker.value
                try Task.checkCancellation()
                return value
            } catch {
                if Task.isCancelled || controller.isCancelled {
                    throw CancellationError()
                }
                throw error
            }
        } onCancel: {
            controller.cancel()
            worker.cancel()
        }
    }

    private static func runTesseractSynchronously(
        executableURL: URL,
        png: Data,
        automaticInversion: Bool,
        pageSegmentationMode: Int,
        dpi: Int,
        controller: TesseractProcessController
    ) throws -> String {
        try Task.checkCancellation()
        let process = Process()
        process.executableURL = executableURL
        process.arguments = [
            "stdin",
            "stdout",
            "-l", "dan",
            "--oem", "1",
            "--psm", "\(pageSegmentationMode)",
            "--dpi", "\(dpi)",
            "-c", "tessedit_do_invert=\(automaticInversion ? 1 : 0)",
            "-c", "preserve_interword_spaces=1",
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
        controller.register(process)
        defer { controller.clear(process) }

        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        if controller.isCancelled || Task.isCancelled {
            throw CancellationError()
        }

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

    /// The colour-adaptive rewrite of the crop, as dark text on a light page.
    private static func separatedPNG(
        rgba: [UInt8],
        width: Int,
        height: Int
    ) -> Data? {
        guard let grayscale = OCRImagePreparation.separated(
            rgba: rgba,
            width: width,
            height: height
        ), let output = OCRImagePreparation.image(from: grayscale) else {
            return nil
        }
        return pngData(from: output)
    }

    private static func pngData(from image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image)
            .representation(using: .png, properties: [:])
    }

    private struct PreparedOCRImage {
        let png: Data
        let size: CGSize
    }

    private static func needsSmallTextPass(
        _ regions: [ScoredRegion]
    ) -> Bool {
        let heights = regions
            .flatMap(\.region.words)
            .map(\.frame.height)
            .filter { $0 > 0 }
            .sorted()
        guard !heights.isEmpty else {
            return true
        }
        let lowerQuartile = heights[
            min(heights.count - 1, heights.count / 4)
        ]
        return lowerQuartile <= 13
    }

    /// Dense PDFs and forms need a different treatment from ordinary screen
    /// text: long table rules are removed, the remaining glyphs are enlarged,
    /// and sparse-text segmentation reads each cell independently.
    ///
    /// The crop is separated first so this works in either polarity. Measuring
    /// darkness straight from luminance, as this did before, marked the whole
    /// background of a dark table as ink — after which rule removal erased
    /// entire rows instead of the rules inside them.
    private static func smallTextPNG(
        rgba: [UInt8],
        width: Int,
        height: Int,
        regions: [TextRegion]
    ) -> PreparedOCRImage? {
        guard width > 0,
              height > 0,
              width * height <= 2_000_000,
              var grayscale = OCRImagePreparation.separated(
                  rgba: rgba,
                  width: width,
                  height: height
              ) else {
            return nil
        }

        // Tiny antialiased glyph edges land lighter than the stroke core.
        // Deepening them keeps the stroke connected through the enlargement.
        OCRImagePreparation.strengthenStrokes(&grayscale)
        OCRImagePreparation.removeRules(from: &grayscale)

        let recognizedHeights = regions
            .flatMap(\.words)
            .map(\.frame.height)
            .filter { $0 > 0 }
            .sorted()
        let lowerHeight = recognizedHeights.isEmpty
            ? 8
            : recognizedHeights[
                min(
                    recognizedHeights.count - 1,
                    recognizedHeights.count / 4
                )
            ]
        let requestedScale: CGFloat
        if lowerHeight < 7 {
            requestedScale = 3
        } else if lowerHeight < 10 {
            requestedScale = 2.7
        } else {
            requestedScale = 2.4
        }
        let dimensionLimit = 4_000 / CGFloat(max(width, height))
        let scale = max(1, min(requestedScale, dimensionLimit))
        let targetWidth = Int(
            (CGFloat(width) * scale).rounded()
        )
        let targetHeight = Int(
            (CGFloat(height) * scale).rounded()
        )
        guard let enlarged = OCRImagePreparation.image(
            from: grayscale,
            targetWidth: targetWidth,
            targetHeight: targetHeight
        ), let png = pngData(from: enlarged) else {
            return nil
        }
        return PreparedOCRImage(
            png: png,
            size: CGSize(width: targetWidth, height: targetHeight)
        )
    }

    private static func merge(
        _ primary: [ScoredRegion],
        with secondary: [ScoredRegion]
    ) -> [ScoredRegion] {
        var merged = primary
        for candidate in secondary {
            if let index = merged.firstIndex(where: {
                overlapRatio($0.region.frame, candidate.region.frame) >= 0.58
            }) {
                if recognitionScore(candidate) > recognitionScore(merged[index]) {
                    merged[index] = candidate
                }
            } else {
                merged.append(candidate)
            }
        }
        return merged.sorted {
            if abs($0.region.frame.midY - $1.region.frame.midY) > 4 {
                return $0.region.frame.midY > $1.region.frame.midY
            }
            return $0.region.frame.minX < $1.region.frame.minX
        }
    }

    /// Ranks two readings of the same place on the screen.
    ///
    /// Length alone used to decide this, which let a noisy pass win with a
    /// longer string of wrong letters. Tesseract already reports how sure it
    /// was per word, so confidence carries the comparison and length only
    /// separates readings the engine was equally sure about.
    private static func recognitionScore(_ scored: ScoredRegion) -> Int {
        let letters = scored.region.sourceText.unicodeScalars.filter {
            CharacterSet.letters.contains($0)
        }.count
        return Int(scored.confidence * 12)
            + scored.region.words.count * 20
            + letters
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
        displayID: CGDirectDisplayID,
        minimumConfidence: Double = 35
    ) -> [ScoredRegion] {
        struct LineKey: Hashable {
            let page: Int
            let block: Int
            let paragraph: Int
            let line: Int
        }

        struct ParsedWord {
            let order: Int
            let confidence: Double
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
                  confidence >= minimumConfidence else {
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
                    confidence: confidence,
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
            let parsed = (wordsByLine[key] ?? [])
                .sorted { $0.order < $1.order }
            let words = parsed.map(\.region)
            guard !words.isEmpty else {
                return nil
            }

            let frame = words
                .dropFirst()
                .reduce(words[0].frame) { $0.union($1.frame) }
            return ScoredRegion(
                region: TextRegion(
                    sourceText: words
                        .map(\.sourceText)
                        .joined(separator: " "),
                    frame: frame,
                    screenFrame: screenFrame,
                    displayID: displayID,
                    words: words
                ),
                confidence: parsed.map(\.confidence).reduce(0, +)
                    / Double(parsed.count)
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
