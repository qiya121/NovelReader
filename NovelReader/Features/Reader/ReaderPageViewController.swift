//
//  ReaderPageViewController.swift
//  NovelReader
//
//  单页渲染。
//
//  关键点：不把"这一页的字符串"重新排版 —— 那样页首的半段文字会被当成新段落，
//  重新套用首行缩进，页码与正文立刻错位。这里直接用分页时生成的
//  NSLayoutManager，按容器绘制对应的 glyph 区间。
//

import UIKit

final class ReaderPageView: UIView {

    private var paginated: PaginatedChapter?
    private var page: PageSlice?
    private var textInset: UIEdgeInsets = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(paginated: PaginatedChapter,
                   page: PageSlice,
                   textInset: UIEdgeInsets) {
        self.paginated = paginated
        self.page = page
        self.textInset = textInset
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let paginated, let page, page.glyphRange.length > 0 else { return }
        let layoutManager = paginated.layoutManager
        // 每个容器从自己的原点开始排版，因此这里只需要加上页边距
        let origin = CGPoint(x: textInset.left, y: textInset.top)
        layoutManager.drawBackground(forGlyphRange: page.glyphRange, at: origin)
        layoutManager.drawGlyphs(forGlyphRange: page.glyphRange, at: origin)
    }
}

// MARK: - 单页控制器

final class ReaderPageViewController: UIViewController {

    let chapterIndex: Int
    let pageIndex: Int
    /// 全书绝对偏移（该页首字符）
    let globalOffset: Int

    private let pageView = ReaderPageView()

    init(chapterIndex: Int, pageIndex: Int, globalOffset: Int) {
        self.chapterIndex = chapterIndex
        self.pageIndex = pageIndex
        self.globalOffset = globalOffset
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(pageView)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        pageView.frame = view.bounds
    }

    func configure(paginated: PaginatedChapter, page: PageSlice, theme: ReaderTheme) {
        loadViewIfNeeded()
        view.backgroundColor = theme.background
        pageView.configure(paginated: paginated,
                           page: page,
                           textInset: UIEdgeInsets(top: TypesettingParams.pageInsets.top,
                                                   left: TypesettingParams.pageInsets.left,
                                                   bottom: TypesettingParams.pageInsets.bottom,
                                                   right: TypesettingParams.pageInsets.right))
    }
}
