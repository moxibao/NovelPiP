import UIKit
import AVFoundation
import AVKit
import CoreText

final class PiPRenderer: NSObject, AVPictureInPictureSampleBufferPlaybackDelegate {
    private let displayLayer = AVSampleBufferDisplayLayer()
    private let containerView = UIView()
    private var pipController: AVPictureInPictureController?
    private var pipPossibleObservation: NSKeyValueObservation?
    private var frameNumber: Int64 = 0
    private var timer: Timer?
    private var currentText = "NovelPiP"
    private var onSkip: ((Bool) -> Void)?
    private var playing = true

    override init() {
        super.init()

        // 关键：音频会话必须在 AVPictureInPictureController 初始化之前激活
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback)
        try? session.setActive(true)

        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = UIColor.white.cgColor

        containerView.frame = CGRect(x: 0, y: 0, width: 2, height: 2)
        containerView.alpha = 0.01
        containerView.isUserInteractionEnabled = false
        displayLayer.frame = containerView.bounds
        containerView.layer.addSublayer(displayLayer)

        if AVPictureInPictureController.isPictureInPictureSupported() {
            let source = AVPictureInPictureController.ContentSource(
                sampleBufferDisplayLayer: displayLayer,
                playbackDelegate: self
            )
            pipController = AVPictureInPictureController(contentSource: source)
            pipController?.canStartPictureInPictureAutomaticallyFromInline = true
            PiPDebug.shared.attach(to: pipController)
        }
    }

    var isSupported: Bool { AVPictureInPictureController.isPictureInPictureSupported() }
    var isActive: Bool { pipController?.isPictureInPictureActive ?? false }
    var isPossible: Bool { pipController?.isPictureInPicturePossible ?? false }

    /// 把承载 layer 的隐藏视图挂到当前窗口，确保系统认为内联内容可见。
    func attachToWindow() {
        guard let window = Self.activeWindow() else { return }
        if containerView.superview !== window {
            containerView.removeFromSuperview()
            window.addSubview(containerView)
        }
    }

    private static func activeWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }

    func prepare(text: String, onSkip: @escaping (Bool) -> Void) {
        currentText = text
        self.onSkip = onSkip
        attachToWindow()
        renderFrame()
        startRefreshing()
        print("[PiP] prepare 完成, isPossible=\(isPossible)")
    }

    func requestStart() {
        guard let controller = pipController else {
            print("[PiP] pipController 为 nil")
            return
        }
        attachToWindow()

        print("[PiP] 请求启动, isPossible=\(controller.isPictureInPicturePossible)")

        if controller.isPictureInPicturePossible {
            controller.startPictureInPicture()
            return
        }

        pipPossibleObservation = controller.observe(
            \.isPictureInPicturePossible,
            options: [.new]
        ) { c, _ in
            print("[PiP] isPossible 变为 \(c.isPictureInPicturePossible)")
            guard c.isPictureInPicturePossible else { return }
            c.startPictureInPicture()
        }
    }

    func update(text: String) {
        currentText = text
        renderFrame()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        pipPossibleObservation = nil
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
        paragraph.lineSpacing = 15
        paragraph.alignment = .left
        let font = UIFont.systemFont(ofSize: 34, weight: .regular)
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

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    skipByInterval skipInterval: CMTime,
                                    completion: @escaping () -> Void) {
        onSkip?(CMTimeGetSeconds(skipInterval) >= 0)
        completion()
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
