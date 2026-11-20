//
//  BrightnessOverlay.swift
//  NovelReader
//
//  亮度控制（PRD §5.6 ②）
//
//  【禁止】调用 UIScreen.main.brightness 改系统亮度。
//  实现：在窗口最上层盖一层黑色遮罩，alpha = 1 - appBrightness，
//  不拦截任何触摸（isUserInteractionEnabled = false），退出 App 即失效。
//

import UIKit

final class BrightnessOverlay {

    static let shared = BrightnessOverlay()

    private var overlay: UIView?
    private var level: Double = 1.0

    private init() {}

    func setLevel(_ level: Double) {
        self.level = min(max(level, 0.1), 1.0)
        if let overlay = overlay {
            overlay.alpha = 1.0 - self.level
        } else {
            install()
        }
    }

    func refresh() {
        install()
    }

    private func install() {
        guard let window = keyWindow() else { return }
        if overlay?.superview !== window {
            overlay?.removeFromSuperview()
            let view = UIView(frame: window.bounds)
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.backgroundColor = .black
            view.isUserInteractionEnabled = false
            view.tag = 9_001
            window.addSubview(view)
            overlay = view
        }
        overlay?.alpha = 1.0 - level
    }

    private func keyWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap { $0.windows }
        return windows.first { $0.isKeyWindow } ?? windows.first
    }
}
