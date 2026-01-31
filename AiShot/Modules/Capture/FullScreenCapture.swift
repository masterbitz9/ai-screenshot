import Cocoa
import ScreenCaptureKit
import CoreGraphics

final class FullScreenCapture {
    private let queue = DispatchQueue(label: "AiShot.FullScreenCapture", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var isCapturing = false
    private var isScreenSaverActive = false
    private var screensaverObservers: [NSObjectProtocol] = []
    private let observerQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "AiShot.FullScreenCapture.ObserverQueue"
        queue.qualityOfService = .utility
        return queue
    }()
    private var captureInterval: TimeInterval = 60.0
    private var shouldResumeAfterScreensaver = false
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter
    }()

    init() {
        let center = DistributedNotificationCenter.default()
        isScreenSaverActive = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.apple.ScreenSaver.Engine"
        }
        screensaverObservers = [
            center.addObserver(
                forName: Notification.Name("com.apple.screensaver.didstart"),
                object: nil,
                queue: observerQueue
            ) { [weak self] _ in
                guard let self else { return }
                self.queue.async { [weak self] in
                    guard let self else { return }
                    self.isScreenSaverActive = true
                    if self.timer != nil {
                        self.shouldResumeAfterScreensaver = true
                        self.stopTimer()
                    }
                }
            },
            center.addObserver(
                forName: Notification.Name("com.apple.screensaver.didstop"),
                object: nil,
                queue: observerQueue
            ) { [weak self] _ in
                guard let self else { return }
                self.queue.async { [weak self] in
                    guard let self else { return }
                    self.isScreenSaverActive = false
                    if self.shouldResumeAfterScreensaver, self.timer == nil {
                        self.startTimer(interval: self.captureInterval)
                    }
                }
            }
        ]
    }

    deinit {
        let center = DistributedNotificationCenter.default()
        screensaverObservers.forEach { center.removeObserver($0) }
    }

    func start(interval: TimeInterval = 60.0) {
        stopTimer()
        captureInterval = interval
        shouldResumeAfterScreensaver = true
        _ = captureDirectory
        guard !isScreenSaverActive else { return }
        startTimer(interval: interval)
    }

    func stop() {
        shouldResumeAfterScreensaver = false
        stopTimer()
    }

    private func startTimer(interval: TimeInterval) {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.captureTick()
        }
        self.timer = timer
        timer.resume()
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    private func captureTick() {
        guard !isCapturing else { return }
        guard !isScreenSaverActive else { return }
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
