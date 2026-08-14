import CoreGraphics
import Foundation
import BabelCore

/// Rewrites a captured crop into the dark-text-on-light-background form every
/// recognizer reads most reliably, whatever colours the source used.
///
/// Screen text is not a scanned page. It arrives as light-on-dark, as saturated
/// glyphs on a saturated banner, or as a secondary label only a few luminance
/// steps away from its panel. A fixed grayscale threshold answers only one of
/// those, so preparation derives its parameters from the crop itself:
///
/// 1. Project every pixel onto the direction of greatest colour variance. In a
///    text crop that direction *is* the foreground-to-background axis, so red
///    on green separates as cleanly as black on white, and a luminance-only
///    conversion — which collapses equiluminant colours into flat gray — is
///    avoided.
/// 2. Split the projection with Otsu's method and stretch the two class means
///    to full range. Anchoring on class means rather than fixed percentiles
///    matters because glyphs routinely cover under 2% of a crop, and a 2%
///    percentile would clip them into the background.
/// 3. Orient the minority class dark, so the result is dark-on-light no matter
///    which polarity the source used.
///
/// Everything runs on the CPU with deterministic integer output. That keeps the
/// passes available while the display or GPU is asleep, which a GPU-backed Core
/// Image context does not guarantee.
enum OCRImagePreparation {
    /// A grayscale buffer plus the geometry needed to map results back.
    struct Grayscale {
        var pixels: [UInt8]
        let width: Int
        let height: Int
    }

    /// Largest crop preparation will process. Beyond this the per-pixel passes
    /// cost more than the recognition they are meant to rescue.
    static let maximumPixelCount = 8_000_000

    // MARK: - Preparation

    /// Returns the crop as dark text on a light background, or `nil` when the
    /// crop holds no separable content.
    static func separated(from image: CGImage) -> Grayscale? {
        guard let rgba = rgbaPixels(from: image) else {
            return nil
        }
        return separated(
            rgba: rgba,
            width: image.width,
            height: image.height
        )
    }

    /// Separates an already-rasterized crop, so a caller preparing the same
    /// capture more than once pays for the bitmap conversion only once.
    static func separated(
        rgba: [UInt8],
        width: Int,
        height: Int
    ) -> Grayscale? {
        let count = width * height
        guard count > 0, count <= maximumPixelCount else {
            return nil
        }

        let axis = principalColourAxis(
            rgba: rgba,
            count: count
        )
        // The projection runs once per pixel over a full capture, so it stays
        // in fixed-point integers: the axis is scaled by `axisScale` and the
        // result carries that scale until normalisation divides it out.
        let axisX = Int((axis.x * Double(axisScale)).rounded())
        let axisY = Int((axis.y * Double(axisScale)).rounded())
        let axisZ = Int((axis.z * Double(axisScale)).rounded())
        var projection = [Int32](repeating: 0, count: count)
        var histogram = [Int](repeating: 0, count: bucketCount)
        projection.withUnsafeMutableBufferPointer { output in
            rgba.withUnsafeBufferPointer { source in
                for pixel in 0..<count {
                    let index = pixel * 4
                    let alpha = Int(source[index + 3])
                    let red: Int
                    let green: Int
                    let blue: Int
                    if alpha == 255 {
                        red = Int(source[index])
                        green = Int(source[index + 1])
                        blue = Int(source[index + 2])
                    } else {
                        red = compositeOnWhite(
                            Int(source[index]),
                            alpha: alpha
                        )
                        green = compositeOnWhite(
                            Int(source[index + 1]),
                            alpha: alpha
                        )
                        blue = compositeOnWhite(
                            Int(source[index + 2]),
                            alpha: alpha
                        )
                    }
                    let value = red * axisX + green * axisY + blue * axisZ
                    output[pixel] = Int32(value)
                    histogram[bucket(forScaled: value)] += 1
                }
            }
        }

        guard let classes = classes(in: histogram) else {
            return nil
        }

        // The threshold is derived from the whole crop rather than from local
        // windows. Per-tile thresholds were measured and rejected: they gain
        // nothing on cursor-sized captures, and where a tile edge crosses a
        // background boundary they flip polarity mid-glyph, which turns a word
        // into two unreadable halves. Crops that really do straddle two
        // backgrounds are handled earlier, by Vision reading the original.
        var pixels = [UInt8](repeating: 255, count: count)
        var darkCount = 0
        let low = Int((classes.low * Double(axisScale)).rounded())
        let span = max(Int((classes.span * Double(axisScale)).rounded()), 1)
        pixels.withUnsafeMutableBufferPointer { output in
            projection.withUnsafeBufferPointer { source in
                for pixel in 0..<count {
                    let scaled = (Int(source[pixel]) - low) * 255 / span
                    let clamped = min(max(scaled, 0), 255)
                    output[pixel] = UInt8(clamped)
                    if clamped < 128 {
                        darkCount += 1
                    }
                }
            }
        }

        // Glyphs are the minority of a text crop. Whichever class is smaller is
        // therefore the text, and it has to end up dark.
        if darkCount * 2 > count {
            for pixel in 0..<count {
                pixels[pixel] = 255 - pixels[pixel]
            }
        }

        return Grayscale(pixels: pixels, width: width, height: height)
    }

    /// The two colour classes a histogram splits into.
    private struct Classes {
        let darkMean: Double
        let lightMean: Double

        var gap: Double {
            lightMean - darkMean
        }

        /// A quarter-gap margin on each side leaves stroke interiors and
        /// background just short of saturation, which preserves the
        /// antialiased edges small glyphs are mostly made of.
        var low: Double {
            darkMean - gap * 0.25
        }

        var span: Double {
            gap * 1.5
        }
    }

    private static func classes(in histogram: [Int]) -> Classes? {
        let threshold = otsuThreshold(histogram: histogram)
        var darkWeight = 0.0
        var darkSum = 0.0
        var lightWeight = 0.0
        var lightSum = 0.0
        for index in histogram.indices {
            let weight = Double(histogram[index])
            guard weight > 0 else {
                continue
            }
            if index <= threshold {
                darkWeight += weight
                darkSum += weight * value(forBucket: index)
            } else {
                lightWeight += weight
                lightSum += weight * value(forBucket: index)
            }
        }
        guard darkWeight > 0, lightWeight > 0 else {
            return nil
        }
        let classes = Classes(
            darkMean: darkSum / darkWeight,
            lightMean: lightSum / lightWeight
        )
        return classes.gap > minimumClassGap ? classes : nil
    }

    // MARK: - Rule removal

    /// Erases table and underline rules so sparse-layout recognition reads the
    /// cell text instead of the grid.
    ///
    /// A run is only erased when it is also *thin*. Without that guard the same
    /// scan removes the body of filled banners and bold headings, which is how
    /// a dark-background crop loses its text entirely.
    static func removeRules(
        from grayscale: inout Grayscale,
        maximumThickness: Int = 4
    ) {
        removeHorizontalRules(
            from: &grayscale,
            maximumThickness: maximumThickness
        )
        removeVerticalRules(
            from: &grayscale,
            maximumThickness: maximumThickness
        )
    }

    private static func removeHorizontalRules(
        from grayscale: inout Grayscale,
        maximumThickness: Int
    ) {
        let width = grayscale.width
        let height = grayscale.height
        let minimumLength = max(48, width / 14)
        for row in 0..<height {
            let rowStart = row * width
            var runStart: Int?
            for column in 0...width {
                let isDark = column < width
                    && grayscale.pixels[rowStart + column] < darkLevel
                if isDark {
                    runStart = runStart ?? column
                    continue
                }
                guard let start = runStart else {
                    continue
                }
                runStart = nil
                guard column - start >= minimumLength,
                      isThinHorizontally(
                          grayscale,
                          row: row,
                          from: start,
                          to: column,
                          maximumThickness: maximumThickness
                      ) else {
                    continue
                }
                for index in start..<column {
                    grayscale.pixels[rowStart + index] = 255
                }
            }
        }
    }

    private static func removeVerticalRules(
        from grayscale: inout Grayscale,
        maximumThickness: Int
    ) {
        let width = grayscale.width
        let height = grayscale.height
        let minimumLength = max(24, height / 14)
        for column in 0..<width {
            var runStart: Int?
            for row in 0...height {
                let isDark = row < height
                    && grayscale.pixels[row * width + column] < darkLevel
                if isDark {
                    runStart = runStart ?? row
                    continue
                }
                guard let start = runStart else {
                    continue
                }
                runStart = nil
                guard row - start >= minimumLength,
                      isThinVertically(
                          grayscale,
                          column: column,
                          from: start,
                          to: row,
                          maximumThickness: maximumThickness
                      ) else {
                    continue
                }
                for index in start..<row {
                    grayscale.pixels[index * width + column] = 255
                }
            }
        }
    }

    /// Measures how tall the dark area is at the midpoint of a horizontal run.
    private static func isThinHorizontally(
        _ grayscale: Grayscale,
        row: Int,
        from start: Int,
        to end: Int,
        maximumThickness: Int
    ) -> Bool {
        let column = (start + end) / 2
        var thickness = 1
        var probe = row - 1
        while probe >= 0,
              grayscale.pixels[probe * grayscale.width + column] < darkLevel {
            thickness += 1
            if thickness > maximumThickness {
                return false
            }
            probe -= 1
        }
        probe = row + 1
        while probe < grayscale.height,
              grayscale.pixels[probe * grayscale.width + column] < darkLevel {
            thickness += 1
            if thickness > maximumThickness {
                return false
            }
            probe += 1
        }
        return true
    }

    /// Measures how wide the dark area is at the midpoint of a vertical run.
    private static func isThinVertically(
        _ grayscale: Grayscale,
        column: Int,
        from start: Int,
        to end: Int,
        maximumThickness: Int
    ) -> Bool {
        let row = (start + end) / 2
        let rowStart = row * grayscale.width
        var thickness = 1
        var probe = column - 1
        while probe >= 0, grayscale.pixels[rowStart + probe] < darkLevel {
            thickness += 1
            if thickness > maximumThickness {
                return false
            }
            probe -= 1
        }
        probe = column + 1
        while probe < grayscale.width,
              grayscale.pixels[rowStart + probe] < darkLevel {
            thickness += 1
            if thickness > maximumThickness {
                return false
            }
            probe += 1
        }
        return true
    }

    /// Deepens glyph strokes that antialiasing left lighter than the page.
    /// Applied after separation, where the background is already near white.
    static func strengthenStrokes(
        _ grayscale: inout Grayscale,
        gain: Double = 1.65
    ) {
        for index in grayscale.pixels.indices {
            let darkness = 255 - Int(grayscale.pixels[index])
            let deepened = 255 - Int(
                min(Double(darkness) * gain, 255).rounded()
            )
            grayscale.pixels[index] = UInt8(min(max(deepened, 0), 255))
        }
    }

    // MARK: - Image construction

    static func image(
        from grayscale: Grayscale,
        targetWidth: Int? = nil,
        targetHeight: Int? = nil
    ) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let provider = CGDataProvider(
            data: Data(grayscale.pixels) as CFData
        ), let source = CGImage(
            width: grayscale.width,
            height: grayscale.height,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: grayscale.width,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(
                rawValue: CGImageAlphaInfo.none.rawValue
            ),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else {
            return nil
        }

        let width = targetWidth ?? grayscale.width
        let height = targetHeight ?? grayscale.height
        guard width != grayscale.width || height != grayscale.height else {
            return source
        }
        guard width > 0,
              height > 0,
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.none.rawValue
              ) else {
            return nil
        }
        context.interpolationQuality = .high
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(
            source,
            in: CGRect(x: 0, y: 0, width: width, height: height)
        )
        return context.makeImage()
    }

    /// Redraws the crop larger without touching its colours.
    ///
    /// Small glyphs lose their diacritics before they lose their shape: a
    /// dense table reads as "Mnedlig" at capture scale and "Månedlig" once
    /// enlarged. Returns `nil` when the result would exceed the pixel budget.
    static func enlarged(_ image: CGImage, scale: CGFloat) -> CGImage? {
        let width = Int((CGFloat(image.width) * scale).rounded())
        let height = Int((CGFloat(image.height) * scale).rounded())
        guard scale > 1,
              width > 0,
              height > 0,
              width * height <= maximumPixelCount,
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }
        context.interpolationQuality = .high
        context.draw(
            image,
            in: CGRect(x: 0, y: 0, width: width, height: height)
        )
        return context.makeImage()
    }

    // MARK: - Pixel access

    static func rgbaPixels(from image: CGImage) -> [UInt8]? {
        let width = image.width
        let height = image.height
        guard width > 0,
              height > 0,
              width * height <= maximumPixelCount else {
            return nil
        }
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = rgba.withUnsafeMutableBytes { bytes -> Bool in
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
        return rendered ? rgba : nil
    }

    static func compositeOnWhite(_ component: Int, alpha: Int) -> Int {
        (component * alpha + 255 * (255 - alpha)) / 255
    }

    // MARK: - Colour axis

    struct ColourAxis: Equatable {
        var x: Double
        var y: Double
        var z: Double
    }

    /// The unit direction of greatest colour variance, found by power iteration
    /// on the RGB covariance of a strided sample.
    static func principalColourAxis(
        rgba: [UInt8],
        count: Int
    ) -> ColourAxis {
        let neutral = ColourAxis(
            x: 1 / 3.0.squareRoot(),
            y: 1 / 3.0.squareRoot(),
            z: 1 / 3.0.squareRoot()
        )
        guard count > 0 else {
            return neutral
        }

        // A strided sample is enough for a covariance direction and keeps the
        // cost flat as captures grow.
        let stride = max(1, count / 40_000)
        var meanR = 0.0
        var meanG = 0.0
        var meanB = 0.0
        var samples = 0.0
        var pixel = 0
        while pixel < count {
            let index = pixel * 4
            let alpha = Int(rgba[index + 3])
            meanR += Double(compositeOnWhite(Int(rgba[index]), alpha: alpha))
            meanG += Double(
                compositeOnWhite(Int(rgba[index + 1]), alpha: alpha)
            )
            meanB += Double(
                compositeOnWhite(Int(rgba[index + 2]), alpha: alpha)
            )
            samples += 1
            pixel += stride
        }
        guard samples > 0 else {
            return neutral
        }
        meanR /= samples
        meanG /= samples
        meanB /= samples

        var rr = 0.0, rg = 0.0, rb = 0.0, gg = 0.0, gb = 0.0, bb = 0.0
        pixel = 0
        while pixel < count {
            let index = pixel * 4
            let alpha = Int(rgba[index + 3])
            let dr = Double(compositeOnWhite(Int(rgba[index]), alpha: alpha))
                - meanR
            let dg = Double(
                compositeOnWhite(Int(rgba[index + 1]), alpha: alpha)
            ) - meanG
            let db = Double(
                compositeOnWhite(Int(rgba[index + 2]), alpha: alpha)
            ) - meanB
            rr += dr * dr
            rg += dr * dg
            rb += dr * db
            gg += dg * dg
            gb += dg * db
            bb += db * db
            pixel += stride
        }

        var axis = neutral
        for _ in 0..<powerIterations {
            let nx = rr * axis.x + rg * axis.y + rb * axis.z
            let ny = rg * axis.x + gg * axis.y + gb * axis.z
            let nz = rb * axis.x + gb * axis.y + bb * axis.z
            let norm = (nx * nx + ny * ny + nz * nz).squareRoot()
            guard norm > 1e-9 else {
                return neutral
            }
            axis = ColourAxis(x: nx / norm, y: ny / norm, z: nz / norm)
        }
        // Pin the sign so lighter pixels always project higher; otherwise the
        // polarity of the output would depend on the starting vector.
        if axis.x + axis.y + axis.z < 0 {
            axis = ColourAxis(x: -axis.x, y: -axis.y, z: -axis.z)
        }
        return axis
    }

    // MARK: - Histogram

    private static let bucketCount = 1_024
    /// An 8-bit RGB triple projected onto a unit vector lies within ±441.7.
    private static let projectionRange = 442.0
    /// Fixed-point scale for the colour axis and the projections taken along
    /// it. A power of two so the compiler can shift rather than divide.
    private static let axisScale = 4_096
    private static let scaledProjectionRange = Int(projectionRange)
        * axisScale
    private static let minimumClassGap = 0.5
    private static let darkLevel: UInt8 = 92
    private static let powerIterations = 24

    /// Buckets a projection value that still carries `axisScale`.
    private static func bucket(forScaled value: Int) -> Int {
        let offset = value + scaledProjectionRange
        let normalized = offset * (bucketCount - 1)
            / (scaledProjectionRange * 2)
        return min(max(normalized, 0), bucketCount - 1)
    }

    private static func value(forBucket bucket: Int) -> Double {
        Double(bucket) / Double(bucketCount - 1)
            * (projectionRange * 2)
            - projectionRange
    }

    /// The split that maximises between-class variance.
    static func otsuThreshold(histogram: [Int]) -> Int {
        var total = 0.0
        var weightedTotal = 0.0
        for index in histogram.indices {
            total += Double(histogram[index])
            weightedTotal += Double(index) * Double(histogram[index])
        }
        guard total > 0 else {
            return histogram.count / 2
        }

        var backgroundWeight = 0.0
        var backgroundSum = 0.0
        var bestVariance = -1.0
        var bestThreshold = histogram.count / 2
        for index in histogram.indices {
            backgroundWeight += Double(histogram[index])
            backgroundSum += Double(index) * Double(histogram[index])
            guard backgroundWeight > 0 else {
                continue
            }
            let foregroundWeight = total - backgroundWeight
            guard foregroundWeight > 0 else {
                break
            }
            let difference = backgroundSum / backgroundWeight
                - (weightedTotal - backgroundSum) / foregroundWeight
            let variance = backgroundWeight * foregroundWeight
                * difference * difference
            if variance > bestVariance {
                bestVariance = variance
                bestThreshold = index
            }
        }
        return bestThreshold
    }
}
