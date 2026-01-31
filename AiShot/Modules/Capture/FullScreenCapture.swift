import Cocoa
import ScreenCaptureKit
import CoreGraphics

final class FullScreenCapture {
    private let queue = DispatchQueue(label: "AiShot.FullScreenCapture", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var isCapturing = false
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter
    }()

    func start(interval: TimeInterval = 60.0) {
        stop()
        _ = captureDirectory
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.captureTick()
        }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func captureTick() {
        guard !isCapturing else { return }
        guard CGPreflightScreenCaptureAccess() else { return }
        isCapturing = true
        Task.detached(priority: .utility) { [weak self] in
            await self?.captureOnce()
            self?.queue.async { [weak self] in
                self?.isCapturing = false
            }
        }
    }

    private func captureOnce() async {
        do {
            let content = try await SCShareableContent.current
            let displays = content.displays
            guard !displays.isEmpty else { return }
            for display in displays {
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let configuration = SCStreamConfiguration()
                configuration.width = display.width
                configuration.height = display.height
                configuration.pixelFormat = kCVPixelFormatType_32BGRA
                configuration.showsCursor = SettingsStore.captureCursorValue
                let image = try await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: configuration
                )
                try save(image, displayID: display.displayID)
            }
        } catch {
            print("Auto-capture error: \(error)")
        }
    }

    private func save(_ image: CGImage, displayID: UInt32) throws {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        let fileName = "ai_\(Self.timestampFormatter.string(from: Date()))_\(displayID).png"
        let url = captureDirectory.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
    }

    private var captureDirectory: URL {
        let cacheRoot = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        let directory = cacheRoot.appendingPathComponent("AiShot", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            print("Failed to create cache directory: \(error)")
        }
        return directory
    }
}
