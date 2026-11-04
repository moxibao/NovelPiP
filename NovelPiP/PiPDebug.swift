import Foundation
import AVKit

/// 临时诊断用：把 PiP 状态和错误打到控制台。
/// 确认问题后再删除此文件。
final class PiPDebug: NSObject, AVPictureInPictureControllerDelegate {
    static let shared = PiPDebug()

    func attach(to controller: AVPictureInPictureController?) {
        controller?.delegate = self
    }

    func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        print("[PiP] 已启动")
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        print("[PiP] 启动失败: \(error)")
    }

    func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        print("[PiP] 已停止")
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        print("[PiP] 恢复界面")
        completionHandler(true)
    }
}
