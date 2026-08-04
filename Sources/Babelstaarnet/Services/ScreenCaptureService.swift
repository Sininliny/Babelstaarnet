import AppKit
import CoreGraphics
import ScreenCaptureKit

enum ScreenCaptureError: LocalizedError {
    case permissionDenied
    case noDisplays

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Screen Recording permission is required."
        case .noDisplays:
            return "No display was available to capture."
        }
    }
}

actor ScreenCaptureService {
    private struct ScreenGeometry: Sendable {
        let displayID: CGDirectDisplayID
        let frame: CGRect
    }

    private var cachedContent: SCShareableContent?
    private var contentCachedAt = Date.distantPast
    private var cachedScreens: [ScreenGeometry] = []
    private var screensCachedAt = Date.distantPast

    nonisolated var hasPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    nonisolated func requestPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    func captureRegion(
        around cursor: CGPoint,
        estimatedTextHeight: CGFloat?,
        velocity: CursorVelocity,
        expansion: CGFloat = 1
    ) async throws -> CapturedDisplay {
        guard CGPreflightScreenCaptureAccess() else {
            throw ScreenCaptureError.permissionDenied
        }

        let screens = await screenGeometries()
        guard let screen = screens.first(where: { $0.frame.contains(cursor) })
            ?? screens.min(by: {
                distance(from: cursor, to: $0.frame)
                    < distance(from: cursor, to: $1.frame)
            }) else {
            throw ScreenCaptureError.noDisplays
        }

        let content = try await shareableContent()
        guard let display = content.displays.first(where: {
            $0.displayID == screen.displayID
        }) else {
            cachedContent = nil
            cachedScreens.removeAll()
            throw ScreenCaptureError.noDisplays
        }

        let captureFrame = AdaptiveCapturePlanner.captureFrame(
            around: cursor,
            on: screen.frame,
            estimatedTextHeight: estimatedTextHeight,
            velocity: velocity,
            expansion: expansion
        )
        let sourceRect = AdaptiveCapturePlanner.sourceRect(
            for: captureFrame,
            on: screen.frame
        )
        let scale = max(CGFloat(display.width) / screen.frame.width, 1)
        let ownApplications = content.applications.filter {
            $0.processID == ProcessInfo.processInfo.processIdentifier
        }
        let filter = SCContentFilter(
            display: display,
            excludingApplications: ownApplications,
            exceptingWindows: []
        )
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = sourceRect
        configuration.width = max(Int(ceil(sourceRect.width * scale)), 1)
        configuration.height = max(Int(ceil(sourceRect.height * scale)), 1)
        configuration.showsCursor = false
        configuration.capturesAudio = false

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
        return CapturedDisplay(
            displayID: display.displayID,
            image: image,
            frame: captureFrame,
            screenFrame: screen.frame
        )
    }

    private func shareableContent() async throws -> SCShareableContent {
        if let cachedContent,
           Date().timeIntervalSince(contentCachedAt) < 60 {
            return cachedContent
        }
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        cachedContent = content
        contentCachedAt = Date()
        return content
    }

    private func screenGeometries() async -> [ScreenGeometry] {
        if !cachedScreens.isEmpty,
           Date().timeIntervalSince(screensCachedAt) < 5 {
            return cachedScreens
        }
        let screens = await MainActor.run {
            NSScreen.screens.compactMap { screen -> ScreenGeometry? in
                guard let number = screen.deviceDescription[
                    NSDeviceDescriptionKey("NSScreenNumber")
                ] as? NSNumber else {
                    return nil
                }
                return ScreenGeometry(
                    displayID: CGDirectDisplayID(number.uint32Value),
                    frame: screen.frame
                )
            }
        }
        cachedScreens = screens
        screensCachedAt = Date()
        return screens
    }

    private func distance(
        from point: CGPoint,
        to rect: CGRect
    ) -> CGFloat {
        let dx = max(
            max(rect.minX - point.x, 0),
            point.x - rect.maxX
        )
        let dy = max(
            max(rect.minY - point.y, 0),
            point.y - rect.maxY
        )
        return hypot(dx, dy)
    }
}
