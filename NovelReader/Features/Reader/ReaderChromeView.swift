//
//  ReaderChromeView.swift
//  NovelReader
//
//  顶部栏 + 底部工具栏（PRD §5.5 / §7）
//  默认完全不显示，单击屏幕中部 60% 区域淡入/淡出（0.2s）。
//  底部 4 个等分按钮：目录 / 书签 / 设置 / 进度。
//

import UIKit

final class ReaderChromeView: UIView {

    // MARK: - 回调

    var onBack: (() -> Void)?
    var onBookmarkList: (() -> Void)?
    var onToggleBookmark: (() -> Void)?
    var onOpenTOC: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onShowProgress: (() -> Void)?

    // MARK: - 子视图

    private let topBar = UIView()
    private let bottomBar = UIView()
    private let topSeparator = UIView()
    private let bottomSeparator = UIView()

    private let backButton = UIButton(type: .system)
    private let bookmarkStarButton = UIButton(type: .system)
    private let bookTitleLabel = UILabel()
    private let chapterLabel = UILabel()

    private let tocItem = ChromeItemView(icon: "list.bullet", title: "目录")
    private let bookmarkItem = ChromeItemView(icon: "bookmark", title: "书签")
    private let settingsItem = ChromeItemView(icon: "circle.grid.3x3", title: "设置")
    private let progressItem = ChromeItemView(icon: nil, title: "0%", subtitle: "0/0")

    private var theme: ReaderTheme = .default

    // MARK: - 初始化

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        backgroundColor = .clear
        alpha = 0
        isHidden = true

        setupTopBar()
        setupBottomBar()
        applyTheme(theme)
    }

    private func setupTopBar() {
        topBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topBar)

        backButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        backButton.tintColor = UIColor(hex: 0x1C1C1E)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.addTarget(self, action: #selector(handleBack), for: .touchUpInside)

        bookmarkStarButton.setImage(UIImage(systemName: "star"), for: .normal)
        bookmarkStarButton.translatesAutoresizingMaskIntoConstraints = false
        bookmarkStarButton.addTarget(self, action: #selector(handleBookmarkList), for: .touchUpInside)

        bookTitleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        bookTitleLabel.textAlignment = .center
        bookTitleLabel.lineBreakMode = .byTruncatingTail

        chapterLabel.font = .systemFont(ofSize: 11)
        chapterLabel.textAlignment = .center
        chapterLabel.lineBreakMode = .byTruncatingTail
        chapterLabel.textColor = UIColor(hex: 0x8E8E93)

        let centerStack = UIStackView(arrangedSubviews: [bookTitleLabel, chapterLabel])
        centerStack.axis = .vertical
        centerStack.spacing = 1
        centerStack.translatesAutoresizingMaskIntoConstraints = false

        topSeparator.translatesAutoresizingMaskIntoConstraints = false

        topBar.addSubview(backButton)
        topBar.addSubview(bookmarkStarButton)
        topBar.addSubview(centerStack)
        topBar.addSubview(topSeparator)

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 44),

            backButton.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 4),
            backButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 44),
            backButton.heightAnchor.constraint(equalToConstant: 44),

            bookmarkStarButton.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -4),
            bookmarkStarButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            bookmarkStarButton.widthAnchor.constraint(equalToConstant: 44),
            bookmarkStarButton.heightAnchor.constraint(equalToConstant: 44),

            centerStack.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            centerStack.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 8),
            centerStack.trailingAnchor.constraint(equalTo: bookmarkStarButton.leadingAnchor, constant: -8),

            topSeparator.leadingAnchor.constraint(equalTo: topBar.leadingAnchor),
            topSeparator.trailingAnchor.constraint(equalTo: topBar.trailingAnchor),
            topSeparator.bottomAnchor.constraint(equalTo: topBar.bottomAnchor),
            topSeparator.heightAnchor.constraint(equalToConstant: 0.5)
        ])
    }

    private func setupBottomBar() {
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bottomBar)

        let items: [ChromeItemView] = [tocItem, bookmarkItem, settingsItem, progressItem]
        items.forEach { $0.translatesAutoresizingMaskIntoConstraints = false }

        let stack = UIStackView(arrangedSubviews: items)
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false

        bottomBar.addSubview(stack)
        bottomBar.addSubview(bottomSeparator)
        bottomSeparator.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            bottomBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: bottomAnchor),

            stack.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor),
            stack.topAnchor.constraint(equalTo: bottomBar.topAnchor),
            stack.heightAnchor.constraint(equalToConstant: 64),
            stack.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),

            bottomSeparator.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor),
            bottomSeparator.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor),
            bottomSeparator.topAnchor.constraint(equalTo: bottomBar.topAnchor),
            bottomSeparator.heightAnchor.constraint(equalToConstant: 0.5)
        ])

        tocItem.addTarget(self, action: #selector(handleTOC), for: .touchUpInside)
        bookmarkItem.addTarget(self, action: #selector(handleToggleBookmark), for: .touchUpInside)
        settingsItem.addTarget(self, action: #selector(handleSettings), for: .touchUpInside)
        progressItem.addTarget(self, action: #selector(handleProgress), for: .touchUpInside)
    }

    // MARK: - 更新

    func applyTheme(_ theme: ReaderTheme) {
        self.theme = theme
        topBar.backgroundColor = theme.background
        bottomBar.backgroundColor = theme.background
        let lineColor = theme.isDark ? UIColor.white.withAlphaComponent(0.12) : UIColor.black.withAlphaComponent(0.08)
        topSeparator.backgroundColor = lineColor
        bottomSeparator.backgroundColor = lineColor

        bookTitleLabel.textColor = theme.textColor
        chapterLabel.textColor = theme.textColor.withAlphaComponent(0.55)
        backButton.tintColor = theme.textColor
        bookmarkStarButton.tintColor = theme.textColor

        [tocItem, bookmarkItem, settingsItem, progressItem].forEach {
            $0.applyTint(theme.textColor)
        }
    }

    func update(bookTitle: String,
                chapterTitle: String?,
                isBookmarked: Bool,
                percentText: String,
                pageText: String) {
        bookTitleLabel.text = bookTitle
        chapterLabel.text = chapterTitle ?? ""
        chapterLabel.isHidden = (chapterTitle == nil)
        bookmarkItem.setIcon(isBookmarked ? "bookmark.fill" : "bookmark")
        progressItem.setTitle(percentText, subtitle: pageText)
    }

    // MARK: - 显示/隐藏

    func setVisible(_ visible: Bool, animated: Bool = true) {
        guard isHidden == visible else { return }
        if visible {
            isHidden = false
            if animated {
                UIView.animate(withDuration: 0.2) { self.alpha = 1 }
            } else {
                alpha = 1
            }
        } else {
            if animated {
                UIView.animate(withDuration: 0.2) {
                    self.alpha = 0
                } completion: { _ in
                    self.isHidden = true
                }
            } else {
                alpha = 0
                isHidden = true
            }
        }
    }

    /// 只让顶部/底部区域拦截触摸，中间正文区域仍然可以翻页
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard !isHidden, alpha > 0.1 else { return false }
        if topBar.frame.contains(point) { return true }
        if bottomBar.frame.contains(point) { return true }
        return false
    }

    // MARK: - 事件

    @objc private func handleBack() { onBack?() }
    @objc private func handleBookmarkList() { onBookmarkList?() }
    @objc private func handleToggleBookmark() { onToggleBookmark?() }
    @objc private func handleTOC() { onOpenTOC?() }
    @objc private func handleSettings() { onOpenSettings?() }
    @objc private func handleProgress() { onShowProgress?() }
}

// MARK: - 底部单个按钮

final class ChromeItemView: UIControl {

    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let stack = UIStackView()
    private var tint: UIColor = .label

    init(icon: String?, title: String?, subtitle: String? = nil) {
        super.init(frame: .zero)

        iconView.contentMode = .scaleAspectFit
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        iconView.isHidden = (icon == nil)
        if let icon { iconView.image = UIImage(systemName: icon) }

        titleLabel.font = .systemFont(ofSize: 10)
        titleLabel.text = title
        titleLabel.textAlignment = .center

        subtitleLabel.font = .systemFont(ofSize: 10)
        subtitleLabel.text = subtitle
        subtitleLabel.textAlignment = .center
        subtitleLabel.isHidden = (subtitle == nil)

        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 3
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false

        if !iconView.isHidden { stack.addArrangedSubview(iconView) }
        stack.addArrangedSubview(titleLabel)
        if !subtitleLabel.isHidden { stack.addArrangedSubview(subtitleLabel) }

        addSubview(stack)
        var constraints: [NSLayoutConstraint] = [
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ]
        if !iconView.isHidden {
            constraints.append(iconView.widthAnchor.constraint(equalToConstant: 24))
            constraints.append(iconView.heightAnchor.constraint(equalToConstant: 24))
        }
        NSLayoutConstraint.activate(constraints)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.45 : 1 }
    }

    func applyTint(_ color: UIColor) {
        tint = color
        iconView.tintColor = color
        titleLabel.textColor = color
        subtitleLabel.textColor = color.withAlphaComponent(0.55)
    }

    func setIcon(_ name: String) {
        iconView.image = UIImage(systemName: name)
        iconView.isHidden = false
        iconView.tintColor = tint
    }

    func setTitle(_ title: String, subtitle: String?) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = (subtitle == nil)
    }
}
