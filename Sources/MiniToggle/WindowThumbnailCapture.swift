import AppKit
import ScreenCaptureKit
import CoreImage

// Once started, mutable stream state and completion are confined to queue.
final class WindowThumbnailCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private static let context = CIContext()
    private let queue = DispatchQueue(label: "local.royce.MiniToggle.thumbnail")
    private var stream: SCStream?
    private var completion: ((CGImage?) -> Void)?

    static func image(for window: SCWindow) async -> CGImage? {
        let configuration = SCStreamConfiguration()
        let scale = min(480 / max(window.frame.width, 1), 300 / max(window.frame.height, 1))
        configuration.width = max(1, Int(window.frame.width * scale))
        configuration.height = max(1, Int(window.frame.height * scale))
        configuration.showsCursor = false
        configuration.scalesToFit = true
        let filter = SCContentFilter(desktopIndependentWindow: window)
        if #available(macOS 14.0, *) {
            configuration.ignoreGlobalClipSingleWindow = true
            configuration.ignoreShadowsSingleWindow = true
            if let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) {
                return image
            }
        }
        // A short-lived stream also handles windows the screenshot service
        // temporarily cannot capture during full-screen/Space transitions.
        return await withCheckedContinuation { continuation in
            let capture = WindowThumbnailCapture()
            capture.completion = { continuation.resume(returning: $0) }
            capture.stream = SCStream(filter: filter, configuration: configuration, delegate: capture)
            do {
                try capture.stream?.addStreamOutput(capture, type: .screen, sampleHandlerQueue: capture.queue)
                capture.stream?.startCapture { error in
                    if error != nil { capture.queue.async { capture.finish(nil) } }
                }
                capture.queue.asyncAfter(deadline: .now() + 2) { capture.finish(nil) }
            } catch {
                capture.queue.async { capture.finish(nil) }
            }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int, status == SCFrameStatus.complete.rawValue,
              let buffer = sampleBuffer.imageBuffer else { return }
        let image = CIImage(cvPixelBuffer: buffer)
        finish(Self.context.createCGImage(image, from: image.extent))
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        queue.async { self.finish(nil) }
    }

    private func finish(_ image: CGImage?) {
        guard let completion else { return }
        self.completion = nil
        stream?.stopCapture(completionHandler: nil)
        stream = nil
        completion(image)
    }
}
