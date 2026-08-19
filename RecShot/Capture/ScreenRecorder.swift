import AVFoundation
import AppKit
import ScreenCaptureKit

struct RecordingApplication: Identifiable {
    let id: String
    let name: String
}

enum RecordingError: LocalizedError {
    case applicationUnavailable
    case noDisplay
    case noFrames
    case failedToStart
    case failedToSave

    var errorDescription: String? {
        switch self {
        case .applicationUnavailable:
            return "That application is no longer available to record."
        case .noDisplay:
            return "Couldn’t find a display for the recording."
        case .noFrames:
            return "The recording ended before any frames were captured."
        case .failedToStart:
            return "Couldn’t start the screen recording."
        case .failedToSave:
            return "Couldn’t save the screen recording."
        }
    }
}

final class ScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let sampleQueue = DispatchQueue(label: "com.recshot.recording")
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var outputURL: URL?
    private var didReceiveFrame = false
    private var recordingOutput: AnyObject?
    private var recordingDelegate: AnyObject?

    func availableApplications() async throws -> [RecordingApplication] {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        let bundleIDsWithWindows = Set<String>(
            content.windows.compactMap { window in
                guard window.isOnScreen else { return nil }
                return window.owningApplication?.bundleIdentifier
            }
        )

        return content.applications
            .filter { bundleIDsWithWindows.contains($0.bundleIdentifier) }
            .filter { $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .map { RecordingApplication(id: $0.bundleIdentifier, name: $0.applicationName) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func startFullDisplay() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        let screen = NSScreen.screenUnderMouse()
        guard let display = content.displays.first(where: { $0.displayID == screen.displayID })
                ?? content.displays.first else {
            throw RecordingError.noDisplay
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        try await start(filter: filter)
    }

    func startApplication(bundleIdentifier: String) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        guard let application = content.applications.first(where: {
            $0.bundleIdentifier == bundleIdentifier
        }) else {
            throw RecordingError.applicationUnavailable
        }

        let windows = content.windows.filter {
            $0.isOnScreen && $0.owningApplication?.bundleIdentifier == bundleIdentifier
        }
        let display = display(for: windows, content: content)
        let filter = SCContentFilter(
            display: display,
            including: [application],
            exceptingWindows: []
        )
        try await start(filter: filter)
    }

    func stop() async throws -> URL {
        guard let stream else {
            throw RecordingError.failedToSave
        }

        do {
            try await stream.stopCapture()
            if #available(macOS 15.0, *), recordingOutput != nil {
                if let delegate = recordingDelegate as? RecordingOutputDelegate {
                    try await delegate.waitForFinish()
                }
                guard let outputURL, fileIsUsable(at: outputURL) else {
                    discardOutput()
                    throw RecordingError.failedToSave
                }
                cleanup()
                return outputURL
            }
            return try await finishWriter()
        } catch {
            discardOutput()
            throw error
        }
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .screen, sampleBuffer.isValid else { return }

        sampleQueue.async { [weak self] in
            self?.append(sampleBuffer)
        }
    }

    private func start(filter: SCContentFilter) async throws {
        guard stream == nil else { throw RecordingError.failedToStart }

        let url = ScreenshotStore().recordingURL()
        let configuration = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        configuration.width = evenPixel(filter.contentRect.width * scale)
        configuration.height = evenPixel(filter.contentRect.height * scale)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 5
        configuration.showsCursor = true
        configuration.capturesAudio = true
        configuration.scalesToFit = true

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        do {
            if #available(macOS 15.0, *) {
                let recordingConfiguration = SCRecordingOutputConfiguration()
                recordingConfiguration.outputURL = url
                recordingConfiguration.videoCodecType = AVVideoCodecType.h264
                recordingConfiguration.outputFileType = AVFileType.mp4
                let delegate = RecordingOutputDelegate()
                let output = SCRecordingOutput(configuration: recordingConfiguration, delegate: delegate)
                try stream.addRecordingOutput(output)
                recordingOutput = output
                recordingDelegate = delegate
            } else {
                try stream.addStreamOutput(
                    self,
                    type: .screen,
                    sampleHandlerQueue: sampleQueue
                )
            }
            self.stream = stream
            self.outputURL = url
            try await stream.startCapture()
        } catch {
            self.stream = nil
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    private func append(_ sampleBuffer: CMSampleBuffer) {
        if recordingOutput != nil { return }
        guard let outputURL, let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).valid else {
            return
        }

        if writer == nil {
            guard let format = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
            let dimensions = CMVideoFormatDescriptionGetDimensions(format)

            guard let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .mov) else {
                return
            }

            let settings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: dimensions.width,
                AVVideoHeightKey: dimensions.height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: max(4_000_000, Int(dimensions.width * dimensions.height) * 4),
                    AVVideoExpectedSourceFrameRateKey: 30,
                    AVVideoMaxKeyFrameIntervalKey: 60
                ]
            ]
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            input.expectsMediaDataInRealTime = true
            guard writer.canAdd(input) else { return }
            writer.add(input)
            guard writer.startWriting() else { return }
            writer.startSession(atSourceTime: presentationTime)
            self.writer = writer
            self.videoInput = input
        }

        guard let videoInput, videoInput.isReadyForMoreMediaData else { return }
        if videoInput.append(sampleBuffer) {
            didReceiveFrame = true
        }
    }

    private func finishWriter() async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            sampleQueue.async { [weak self] in
                guard let self,
                      let outputURL = self.outputURL,
                      let writer = self.writer,
                      let videoInput = self.videoInput else {
                    self?.discardOutput()
                    continuation.resume(throwing: RecordingError.noFrames)
                    return
                }

                videoInput.markAsFinished()
                writer.finishWriting {
                    guard writer.status == .completed, self.didReceiveFrame else {
                        let error = writer.error ?? RecordingError.failedToSave
                        self.discardOutput()
                        continuation.resume(throwing: error)
                        return
                    }

                    self.cleanup()
                    continuation.resume(returning: outputURL)
                }
            }
        }
    }

    private func cleanup() {
        stream = nil
        writer = nil
        videoInput = nil
        outputURL = nil
        didReceiveFrame = false
        recordingOutput = nil
        recordingDelegate = nil
    }

    private func discardOutput() {
        if let outputURL {
            try? FileManager.default.removeItem(at: outputURL)
        }
        cleanup()
    }

    private func fileIsUsable(at url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return false
        }
        return size.intValue > 0
    }

    private func display(for windows: [SCWindow], content: SCShareableContent) -> SCDisplay {
        let preferredScreen = windows
            .sorted { area(of: $0.frame) > area(of: $1.frame) }
            .compactMap { window in
                NSScreen.screens.first { NSIntersectsRect($0.frame, window.frame) }
            }
            .first
            ?? NSScreen.screenUnderMouse()

        return content.displays.first(where: { $0.displayID == preferredScreen.displayID })
            ?? content.displays[0]
    }

    private func area(of rect: CGRect) -> CGFloat {
        rect.width * rect.height
    }

    private func evenPixel(_ value: CGFloat) -> Int {
        max(2, Int(value.rounded()) & ~1)
    }
}

@available(macOS 15.0, *)
private final class RecordingOutputDelegate: NSObject, SCRecordingOutputDelegate {
    private let lock = NSLock()
    private var result: Result<Void, Error>?
    private var continuation: CheckedContinuation<Void, Error>?

    func waitForFinish() async throws {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let result {
                lock.unlock()
                continuation.resume(with: result)
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        complete(.success(()))
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        complete(.failure(error))
    }

    private func complete(_ result: Result<Void, Error>) {
        lock.lock()
        guard self.result == nil else {
            lock.unlock()
            return
        }
        self.result = result
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()

        continuation?.resume(with: result)
    }
}

private extension CMTime {
    var valid: CMTime? {
        isValid && isNumeric ? self : nil
    }
}
