import UIKit
import AVFoundation
import CoreText

final class PiPRenderer: NSObject, AVPictureInPictureSampleBufferPlaybackDelegate {
    private let displayLayer = AVSampleBufferDisplayLayer()
    private var pipController: AVPictureInPictureController?
    private var frameNumber: Int64 = 0
    private var timer: Timer?
    private var currentText = "NovelPiP"
    private var onSkip: ((Bool) -> Void)?
    private var playing = true

    override init() {
        super.init()
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = UIColor.white.cgColor
        if AVPictureInPictureController.isPictureInPictureSupported() {
            let source = AVPictureInPictureController.ContentSource(
                sampleBufferDisplayLayer: displayLayer,
                playbackDelegate: self
            )
            pipController = AVPictureInPictureController(contentSource: source)
            pipController?.canStartPictureInPictureAutomaticallyFromInline = true
        }
    }

    var isSupported: Bool { AVPictureInPictureController.isPictureInPictureSupported() }
    var isActive: Bool { pipController?.isPictureInPictureActive ?? false }

    func start(text: String, onSkip: @escaping (Bool) -> Void) {
        currentText = text
        self.onSkip = onSkip
        renderFrame()
        if pipController?.isPictureInPicturePossible == true {
            pipController?.startPictureInPicture()
        }
        startRefreshing()
    }

    func update(text: String) {
        currentText = text
        renderFrame()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if isActive { pipController?.stopPictureInPicture() }
    }

    private func startRefreshing() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            guard let self, self.playing else { return }
            self.renderFrame()
        }
    }

    private func renderFrame() {
        let width = 1280
        let height = 720
        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
        ]
        CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                            kCVPixelFormatType_32ARGB, attrs as CFDictionary, &pixelBuffer)
        guard let buffer = pixelBuffer else { return }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer),
              let context = CGContext(data: base, width: width, height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else { return }

        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 13
        paragraph.alignment = .left
        let font = UIFont.systemFont(ofSize: 38, weight: .regular)
        let attributed = NSAttributedString(string: currentText,
            attributes: [.font: font, .foregroundColor: UIColor.black, .paragraphStyle: paragraph])
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(rect: CGRect(x: 88, y: 80, width: width - 176, height: height - 160), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        CTFrameDraw(frame, context)
        context.restoreGState()

        var description: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                       imageBuffer: buffer,
                                                       formatDescriptionOut: &description)
        guard let format = description else { return }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 1),
                                        presentationTimeStamp: CMTime(value: frameNumber, timescale: 1),
                                        decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault,
                                                  imageBuffer: buffer,
                                                  formatDescription: format,
                                                  sampleTiming: &timing,
                                                  sampleBufferOut: &sample)
        if let sample {
            if displayLayer.status == .failed { displayLayer.flush() }
            displayLayer.enqueue(sample)
            frameNumber += 1
        }
    }

    // PiP system skip-forward and skip-back events become page-turn events.
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    skipByInterval skipInterval: CMTime,
                                    completionHandler: @escaping () -> Void) {
        onSkip?(CMTimeGetSeconds(skipInterval) >= 0)
        completionHandler()
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    setPlaying playing: Bool) {
        self.playing = playing
    }

    func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        return !playing
    }

    func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        return CMTimeRange(start: .zero, duration: CMTime(value: 3600, timescale: 1))
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    didTransitionToRenderSize newRenderSize: CMVideoDimensions) { }
}
