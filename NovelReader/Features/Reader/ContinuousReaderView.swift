//
//  ContinuousReaderView.swift
//  NovelReader
//
//  「连续」模式（PRD §5.6 ①）：全书跨章节无缝竖向滚动。
//
//  实现要点：
//  - 章节 = UITableView 的行，章节标题作为普通文本行内嵌在正文里；
//  - 行高按需测量并缓存，未测量的行用 estimatedRowHeight 估计 —— 绝不一次性布局整本书；
//  - UITableView 天然回收不可见行，满足「只保留可视区 ±3 屏」的内存要求；
//  - 阅读位置以 (chapters, offset) 为锚，而不是 contentOffset，
//    这样行高估计被修正时位置不会丢。
//

import UIKit

final class ContinuousReaderView: UIView {

    /// (章节序号, 全书绝对偏移)
    var onAnchorChanged: ((Int, Int) -> Void)?

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let chapters: [Chapter]
    private let context: PaginationService.Context
    private let params: TypesettingParams
    private let theme: ReaderTheme
    private let pagination: PaginationService

    private var heightCache: [Int: CGFloat] = [:]
    private var isRestoring = false
    private var didRestore = false
    private var pendingOffset: Int

    private let topInset = TypesettingParams.pageInsets.top
    private let sideInset = TypesettingParams.pageInsets.left

    init(chapters: [Chapter],
         context: PaginationService.Context,
         params: TypesettingParams,
         theme: ReaderTheme,
         initialOffset: Int,
         pagination: PaginationService) {

        self.chapters = chapters
        self.context = context
        self.params = params
        self.theme = theme
        self.pendingOffset = initialOffset
        self.pagination = pagination
        super.init(frame: .zero)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        backgroundColor = theme.background

        tableView.backgroundColor = theme.background
        tableView.separatorStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.estimatedRowHeight = 800
        tableView.rowHeight = UITableView.automaticDimension
        tableView.showsVerticalScrollIndicator = false
        tableView.contentInset = UIEdgeInsets(top: topInset, left: 0, bottom: TypesettingParams.pageInsets.bottom, right: 0)
        tableView.register(ContinuousTextCell.self, forCellReuseIdentifier: ContinuousTextCell.reuseIdentifier)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: topAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    func restore(animated: Bool = false) {
        guard !didRestore else { return }
        didRestore = true
        guard let index = chapterIndex(for: pendingOffset) else { return }

        isRestoring = true
        let indexPath = IndexPath(row: index, section: 0)
        tableView.reloadData()
        tableView.layoutIfNeeded()

        tableView.scrollToRow(at: indexPath, at: .top, animated: false)
        tableView.layoutIfNeeded()

        if let cell = tableView.cellForRow(at: indexPath) as? ContinuousTextCell {
            let inChapter = max(0, pendingOffset - chapters[index].startOffset)
            let y = cell.textOffsetY(forCharacter: inChapter)
            let rowTop = tableView.rectForRow(at: indexPath).minY
            let target = rowTop + y - tableView.contentInset.top
            tableView.setContentOffset(CGPoint(x: 0, y: max(-tableView.contentInset.top, target)), animated: animated)
        }
        isRestoring = false
        notifyAnchor()
    }

    private func chapterIndex(for offset: Int) -> Int? {
        guard !chapters.isEmpty else { return nil }
        for chapter in chapters where offset < chapter.endOffset {
            return chapter.index
        }
        return chapters.count - 1
    }

    /// 跳到指定绝对偏移（目录、书签用）
    func jump(toOffset offset: Int) {
        pendingOffset = offset
        didRestore = false
        restore()
    }

    private func notifyAnchor() {
        guard let indexPath = tableView.indexPathsForVisibleRows?.min() else { return }
        guard let cell = tableView.cellForRow(at: indexPath) as? ContinuousTextCell else { return }

        let rowTop = tableView.rectForRow(at: indexPath).minY
        let localY = tableView.contentOffset.y + tableView.contentInset.top - rowTop
        let chapter = chapters[indexPath.row]
        let charIndex = cell.characterIndex(atY: localY)
        let absolute = chapter.startOffset + min(max(0, charIndex), chapter.charCount)
        onAnchorChanged?(indexPath.row, absolute)
    }

    // MARK: - 行高

    private func measuredHeight(for index: Int) -> CGFloat {
        if let cached = heightCache[index] { return cached }

        let chapter = chapters[index]
        let text = context.chapterText(at: index)
        let titleLength = pagination.inlineTitleLength(for: chapter,
                                                       mode: context.book.chapterMode,
                                                       chapterText: text)
        let attributed = TextStyler.attributedString(text,
                                                     params: params,
                                                     color: theme.textColor,
                                                     inlineTitleLength: titleLength)

        let storage = NSTextStorage(attributedString: attributed)
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: CGSize(width: params.textAreaSize.width, height: 100_000))
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        layoutManager.ensureLayout(for: container)

        let used = layoutManager.usedRect(for: container)
        let height = ceil(used.height) + 8
        heightCache[index] = height
        return height
    }
}

// MARK: - 数据源

extension ContinuousReaderView: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        chapters.count
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        measuredHeight(for: indexPath.row)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ContinuousTextCell.reuseIdentifier,
                                                 for: indexPath) as! ContinuousTextCell
        let chapter = chapters[indexPath.row]
        let text = context.chapterText(at: indexPath.row)
        let titleLength = pagination.inlineTitleLength(for: chapter,
                                                       mode: context.book.chapterMode,
                                                       chapterText: text)
        let attributed = TextStyler.attributedString(text,
                                                      params: params,
                                                      color: theme.textColor,
                                                      inlineTitleLength: titleLength)
        cell.configure(attributed: attributed, sideInset: sideInset)
        return cell
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        cell.backgroundColor = theme.background
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !isRestoring else { return }
        notifyAnchor()
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        notifyAnchor()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { notifyAnchor() }
    }
}

// MARK: - 文本行

final class ContinuousTextCell: UITableViewCell {

    static let reuseIdentifier = "ContinuousTextCell"

    private let textView = UITextView(usingTextLayoutManager: false)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none

        textView.isEditable = false
        textView.isSelectable = false
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.isUserInteractionEnabled = false
        textView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(textView)

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 2),
            textView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            textView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            textView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(attributed: NSAttributedString, sideInset: CGFloat) {
        textView.attributedText = attributed
    }

    /// 给定行内 y 坐标 → 字符下标
    func characterIndex(atY y: CGFloat) -> Int {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return 0 }
        layoutManager.ensureLayout(for: textContainer)
        let point = CGPoint(x: 0, y: max(0, y))
        let glyphIndex = layoutManager.glyphIndex(for: point, in: textContainer)
        return layoutManager.characterIndexForGlyph(at: glyphIndex)
    }

    /// 给定字符下标 → 行内 y 坐标
    func textOffsetY(forCharacter index: Int) -> CGFloat {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return 0 }
        layoutManager.ensureLayout(for: textContainer)
        let length = (textView.text as NSString).length
        let location = min(max(0, index), max(0, length - 1))
        guard length > 0 else { return 0 }
        let glyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: location, length: 1),
                                                  actualCharacterRange: nil)
        let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        return rect.minY
    }
}
