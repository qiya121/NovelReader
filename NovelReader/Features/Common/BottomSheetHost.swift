//
//  BottomSheetHost.swift
//  NovelReader
//
//  V1 所有底部浮层的统一容器（补丁 R-07）。
//
//  为什么不用 UISheetPresentationController：
//  `preferredCornerRadius` 需要 iOS 16.4，而最低版本是 16.0；
//  在 16.0 上系统 sheet 圆角固定 10pt，达不到 PRD §7 要求的 24pt。
//
//  行为：全宽贴底、顶部 24pt 圆角、点外部关闭、下滑关闭、超高时内部滚动。
//

import SwiftUI
import UIKit

enum SheetHeight {
    /// 固定高度（pt）
    case fixed(CGFloat)
    /// 屏幕高度比例
    case fraction(CGFloat)
}

/// 让调用方（不关心泛型参数）可以关闭当前浮层
protocol BottomSheetDismissing: AnyObject {
    func dismissSheet()
}

final class BottomSheetHost<Content: View>: UIViewController {

    private let sheetHeight: SheetHeight
    private let hosting: UIHostingController<Content>

    private let dimmingView = UIView()
    private let cardView = UIView()

    private var cardBottomConstraint: NSLayoutConstraint?
    private var cardHeightConstraint: NSLayoutConstraint?
    private var hasAnimatedIn = false

    init(height: SheetHeight, content: Content) {
        self.sheetHeight = height
        self.hosting = UIHostingController(rootView: content)
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        setupDimming()
        setupCard()
        setupContent()
        registerKeyboardObservers()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !hasAnimatedIn else { return }
        hasAnimatedIn = true
        animateIn()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        cardHeightConstraint?.constant = resolvedHeight()
    }

    // MARK: - 搭建

    private func setupDimming() {
        dimmingView.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        dimmingView.alpha = 0
        dimmingView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dimmingView)
        NSLayoutConstraint.activate([
            dimmingView.topAnchor.constraint(equalTo: view.topAnchor),
            dimmingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            dimmingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimmingView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        dimmingView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleDimmingTap)))
    }

    private func setupCard() {
        cardView.backgroundColor = ReaderUI.panelBackground
        cardView.layer.cornerRadius = ReaderUI.panelCornerRadius
        cardView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        cardView.layer.masksToBounds = true
        cardView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cardView)

        let bottom = cardView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        let height = cardView.heightAnchor.constraint(equalToConstant: resolvedHeight())
        cardBottomConstraint = bottom
        cardHeightConstraint = height

        NSLayoutConstraint.activate([
            cardView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottom,
            height
        ])

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        cardView.addGestureRecognizer(pan)
    }

    private func setupContent() {
        addChild(hosting)
        hosting.view.backgroundColor = .clear
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: cardView.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: cardView.trailingAnchor)
        ])
        hosting.didMove(toParent: self)
    }

    private func resolvedHeight() -> CGFloat {
        let screenHeight = view.bounds.height > 0 ? view.bounds.height : UIScreen.main.bounds.height
        let maxHeight = screenHeight * 0.85
        switch sheetHeight {
        case .fixed(let value):
            return min(value, maxHeight)
        case .fraction(let ratio):
            return min(screenHeight * ratio, maxHeight)
        }
    }

    // MARK: - 动画

    private func animateIn() {
        view.layoutIfNeeded()
        cardView.transform = CGAffineTransform(translationX: 0, y: cardView.bounds.height)
        UIView.animate(withDuration: 0.28, delay: 0, options: [.curveEaseOut]) {
            self.dimmingView.alpha = 1
            self.cardView.transform = .identity
        }
    }

    private func animateOut(completion: (() -> Void)? = nil) {
        UIView.animate(withDuration: 0.24, delay: 0, options: [.curveEaseIn]) {
            self.dimmingView.alpha = 0
            self.cardView.transform = CGAffineTransform(translationX: 0, y: self.cardView.bounds.height)
        } completion: { _ in
            completion?()
            self.dismiss(animated: false)
        }
    }

    // MARK: - 交互

    @objc private func handleDimmingTap() {
        dismissSheet()
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view)
        let velocity = gesture.velocity(in: view)

        switch gesture.state {
        case .changed:
            let offset = max(0, translation.y)
            cardView.transform = CGAffineTransform(translationX: 0, y: offset)
            dimmingView.alpha = max(0, 1 - offset / max(cardView.bounds.height, 1))
        case .ended, .cancelled:
            if translation.y > 80 || velocity.y > 800 {
                animateOut()
            } else {
                UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut]) {
                    self.cardView.transform = .identity
                    self.dimmingView.alpha = 1
                }
            }
        default:
            break
        }
    }

    func dismissSheet() {
        animateOut()
    }

    // MARK: - 键盘
    private func registerKeyboardObservers() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(keyboardWillChange(_:)),
                                               name: UIResponder.keyboardWillChangeFrameNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(keyboardWillHide(_:)),
                                               name: UIResponder.keyboardWillHideNotification,
                                               object: nil)
    }

    @objc private func keyboardWillChange(_ note: Notification) {
        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let converted = view.convert(frame, from: nil)
        let overlap = max(0, view.bounds.maxY - converted.minY)
        cardBottomConstraint?.constant = -overlap
        UIView.animate(withDuration: 0.25) { self.view.layoutIfNeeded() }
    }

    @objc private func keyboardWillHide(_ note: Notification) {
        cardBottomConstraint?.constant = 0
        UIView.animate(withDuration: 0.25) { self.view.layoutIfNeeded() }
    }
}

// MARK: - 便捷present

extension UIViewController {

    func presentBottomSheet<Content: View>(height: SheetHeight,
                                           content: Content,
                                           on parent: UIViewController? = nil) {
        let host = BottomSheetHost(height: height, content: content)
        (parent ?? self).present(host, animated: false)
    }

    /// 关闭当前底部浮层（如果有）
    func dismissBottomSheet() {
        (presentedViewController as? BottomSheetDismissing)?.dismissSheet()
    }
}

extension BottomSheetHost: BottomSheetDismissing {}
