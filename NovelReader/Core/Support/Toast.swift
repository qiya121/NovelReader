//
//  Toast.swift
//  NovelReader
//
//  Toast 统一用 UIKit 实现，SwiftUI 与 UIKit 两侧都能调，避免两套逻辑。
//

import UIKit

enum Toast {

    private static var current: UIView?

    static func show(_ message: String, duration: TimeInterval = 2.0) {
        guard !message.isEmpty else { return }
        guard let host = keyWindow() else { return }

        current?.removeFromSuperview()

        let container = UIView()
        container.backgroundColor = UIColor.black.withAlphaComponent(0.82)
        container.layer.cornerRadius = 14
        container.alpha = 0
        container.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = message
        label.textColor = .white
        label.font = .systemFont(ofSize: 14)
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(label)
        host.addSubview(container)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            container.centerXAnchor.constraint(equalTo: host.centerXAnchor),
            container.bottomAnchor.constraint(equalTo: host.safeAreaLayoutGuide.bottomAnchor, constant: -88),
            container.widthAnchor.constraint(lessThanOrEqualTo: host.widthAnchor, multiplier: 0.8)
        ])

        current = container
        UIView.animate(withDuration: 0.18) {
            container.alpha = 1
        }
        UIView.animate(withDuration: 0.25, delay: duration, options: []) {
            container.alpha = 0
        } completion: { _ in
            container.removeFromSuperview()
            if current === container { current = nil }
        }
    }

    private static func keyWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap { $0.windows }
        return windows.first { $0.isKeyWindow } ?? windows.first
    }
}
