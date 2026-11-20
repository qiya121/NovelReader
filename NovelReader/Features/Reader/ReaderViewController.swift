//
//  ReaderViewController.swift
//  NovelReader
//
//  阅读页（P3）核心。
//
//  三条不可破坏的约束：
//  1. 默认全屏正文，无导航栏/工具栏/页眉页脚；
//  2. 任何设置改动后必须回到同一字符偏移（不是同一页码）；
//  3. 翻页/滚动停止后 500ms 内落库进度，进后台立即落库。
//

import UIKit
import Combine

final class ReaderViewController: UIViewController {

    var onClose: (() -> Void)?

    // MARK: - 依赖

    private let book: Book
    private let initialOffset: Int
    private let preferences: ReadingPreferences
    private let store: LibraryStore
    private let pagination: PaginationService
    private let textProvider: BookTextProvider

    // MARK: - 数据

    private var chapters: [Chapter] = []
    private var context: PaginationService.Context?
    private var params: TypesettingParams?
    private var currentTheme: ReaderTheme

    // MARK: - 位置

    private var chapterIndex = 0
    private var pageIndex = 0
    /// 全书绝对偏移（UTF-16）
    private var currentOffset = 0

    // MARK: - UI

    private let pageContainer = UIView()
    private let chrome = ReaderChromeView()
    private var pageViewController: UIPageViewController?
    private var continuousView: ContinuousReaderView?

    private var isChromeVisible = false
    private var didLoadContent = false
    private var lastLayoutSize: CGSize = .zero
    private var lastMode: PageTransitionMode
    private var cancellables = Set<AnyCancellable>()
    private var saveWorkItem: DispatchWorkItem?
    private var settingsWorkItem: DispatchWorkItem?
    private var totalPagesWorkItem: DispatchWorkItem?
    private var totalPageCount: Int?

    // MARK: - 初始化

    init(book: Book, initialOffset: Int) {
        self.book = book
        self.initialOffset = initialOffset
        self.preferences = AppServices.shared.preferences
        self.store = AppServices.shared.store
        self.pagination = AppServices.shared.pagination
        self.textProvider = BookTextProvider(store: AppServices.shared.store)
        self.currentTheme = AppServices.shared.preferences.theme
        self.lastMode = AppServices.shared.preferences.pageTransition
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        totalPagesWorkItem?.cancel()
        saveWorkItem?.cancel()
    }

    // MARK: - 状态栏

    override var preferredStatusBarStyle: UIStatusBarStyle { currentTheme.statusBarStyle }

    override var prefersStatusBarHidden: Bool { false }

    // MARK: - 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = currentTheme.background
        setupContainers()
        setupGestures()
        bindPreferences()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(appDidEnterBackground),
                                               name: UIApplication.didEnterBackgroundNotification,
                                               object: nil)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let size = view.bounds.size
        guard size.width > 0, size.height > 0 else { return }

        if !didLoadContent {
            didLoadContent = true
            lastLayoutSize = size
            params = makeParams(viewport: size)
            loadContent()
            rebuildReader()
            updateChrome()
            startTotalPageCount()
        } else if size != lastLayoutSize {
            lastLayoutSize = size
            let anchor = currentOffset
            params = makeParams(viewport: size)
            restorePosition(forOffset: anchor)
            rebuildReader()
            updateChrome()
        }
    }

    // MARK: - 搭建

    private func setupContainers() {
        pageContainer.frame = view.bounds
        pageContainer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        pageContainer.backgroundColor = currentTheme.background
        view.addSubview(pageContainer)

        chrome.frame = view.bounds
        chrome.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        chrome.onBack = { [weak self] in self?.closeReader() }
        chrome.onBookmarkList = { [weak self] in self?.presentBookmarkList() }
        chrome.onToggleBookmark = { [weak self] in self?.toggleBookmark() }
        chrome.onOpenTOC = { [weak self] in self?.presentTableOfContents() }
        chrome.onOpenSettings = { [weak self] in self?.presentSettings() }
        chrome.onShowProgress = { [weak self] in self?.showProgressToast() }
        chrome.applyTheme(currentTheme)
        view.addSubview(chrome)
    }

    private func setupGestures() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.cancelsTouchesInView = false
        pageContainer.addGestureRecognizer(tap)

        let edge = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handleEdgePan(_:)))
        edge.edges = .left
        view.addGestureRecognizer(edge)
    }

    private func bindPreferences() {
        preferences.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.scheduleSettingsApply() }
            }
            .store(in: &cancellables)
    }

    // MARK: - 内容加载

    private func loadContent() {
        guard let bookID = book.id else { return }
        do {
            chapters = try store.chapters(bookID: bookID)
            if chapters.isEmpty {
                chapters = [Chapter(bookID: bookID,
                                    index: 0,
                                    title: book.title,
                                    startOffset: 0,
                                    endOffset: book.charCount,
                                    charCount: book.charCount)]
            }
            let text = try textProvider.cleanedText(for: book)
            context = PaginationService.Context(book: book, fullText: text, chapters: chapters)

            let preferred = initialOffset > 0 ? initialOffset : book.lastCharOffset
            restorePosition(forOffset: preferred)
        } catch {
            Toast.show(error.localizedDescription)
        }
    }

    private func makeParams(viewport: CGSize) -> TypesettingParams {
        TypesettingParams(fontSize: preferences.fontSize,
                          lineSpacingMultiplier: preferences.lineSpacingMultiplier,
                          fontPostScriptName: preferences.fontFamilyKey == FontFamily.systemKey
                            ? nil
                            : preferences.fontFamilyKey,
                          textAreaSize: TypesettingParams.textAreaSize(forViewport: viewport),
                          backgroundKey: preferences.backgroundColorKey)
    }

    private var resolvedParams: TypesettingParams {
        params ?? makeParams(viewport: view.bounds.size == .zero ? UIScreen.main.bounds.size : view.bounds.size)
    }

    private func paginatedChapter(_ index: Int) -> PaginatedChapter {
        guard let context else {
            return Paginator.paginate(chapterIndex: index,
                                      chapterText: "",
                                      inlineTitleLength: 0,
                                      params: resolvedParams,
                                      textColor: currentTheme.textColor)
        }
        return pagination.paginatedChapter(index: index,
                                           context: context,
                                           params: resolvedParams,
                                           textColor: currentTheme.textColor)
    }

    // MARK: - 位置换算

    private func clampOffset(_ offset: Int) -> Int {
        guard let context else { return 0 }
        return min(max(0, offset), max(0, context.fullTextLength - 1))
    }

    private func chapterIndexContaining(_ offset: Int) -> Int {
        guard !chapters.isEmpty else { return 0 }
        for chapter in chapters where offset < chapter.endOffset {
            return chapter.index
        }
        return chapters.count - 1
    }

    private func restorePosition(forOffset offset: Int) {
        guard !chapters.isEmpty else { return }
        currentOffset = clampOffset(offset)
        chapterIndex = chapterIndexContaining(currentOffset)
        let inChapter = max(0, currentOffset - chapters[chapterIndex].startOffset)
        pageIndex = paginatedChapter(chapterIndex).pageIndex(forOffset: inChapter)
    }

    private var currentChapterTitle: String? {
        guard book.chapterMode != .none, chapters.indices.contains(chapterIndex) else { return nil }
        return chapters[chapterIndex].title
    }

    private var currentPercent: Double {
        guard book.charCount > 0 else { return 0 }
        return min(1, max(0, Double(currentOffset) / Double(book.charCount)))
    }

    // MARK: - 渲染

    private func rebuildReader() {
        teardownReader()

        switch preferences.pageTransition {
        case .slide:
            buildPageController(orientation: .horizontal)
        case .scroll:
            buildPageController(orientation: .vertical)
        case .continuous:
            buildContinuousReader()
        }
    }

    private func teardownReader() {
        if let pageViewController {
            pageViewController.willMove(toParent: nil)
            pageViewController.view.removeFromSuperview()
            pageViewController.removeFromParent()
        }
        pageViewController = nil
        continuousView?.removeFromSuperview()
        continuousView = nil
        pageContainer.backgroundColor = currentTheme.background
    }

    private func buildPageController(orientation: UIPageViewController.NavigationOrientation) {
        let controller = UIPageViewController(transitionStyle: .scroll,
                                              navigationOrientation: orientation,
                                              options: nil)
        controller.dataSource = self
        controller.delegate = self
        controller.view.frame = pageContainer.bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        controller.view.backgroundColor = currentTheme.background

        addChild(controller)
        pageContainer.addSubview(controller.view)
        controller.didMove(toParent: self)
        pageViewController = controller

        if let start = makePageController(chapter: chapterIndex, page: pageIndex) {
            controller.setViewControllers([start], direction: .forward, animated: false)
        }
    }

    private func buildContinuousReader() {
        guard let context else { return }
        let view = ContinuousReaderView(chapters: chapters,
                                        context: context,
                                        params: resolvedParams,
                                        theme: currentTheme,
                                        initialOffset: currentOffset,
                                        pagination: pagination)
        view.frame = pageContainer.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.onAnchorChanged = { [weak self] chapterIdx, offset in
            guard let self else { return }
            self.chapterIndex = chapterIdx
            self.currentOffset = offset
            self.updateChrome()
            self.scheduleSave()
        }
        pageContainer.addSubview(view)
        continuousView = view
        view.restore()
    }

    private func makePageController(chapter: Int, page: Int) -> ReaderPageViewController? {
        guard chapters.indices.contains(chapter) else { return nil }
        let paginated = paginatedChapter(chapter)
        guard paginated.pages.indices.contains(page) else { return nil }

        let globalOffset = chapters[chapter].startOffset + paginated.pages[page].charRange.location
        let controller = ReaderPageViewController(chapterIndex: chapter,
                                                  pageIndex: page,
                                                  globalOffset: globalOffset)
        controller.configure(paginated: paginated,
                             page: paginated.pages[page],
                             theme: currentTheme)
        return controller
    }

    // MARK: - 交互

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: pageContainer)
        let width = max(1, pageContainer.bounds.width)
        let ratio = point.x / width

        // 中部 60% 唤起/收起工具栏；两侧 20% 翻页
        if ratio >= 0.2 && ratio <= 0.8 {
            toggleChrome()
            return
        }
        // 上下 / 连续模式翻页热区失效（PRD §5.5）
        guard preferences.pageTransition == .slide else { return }
        advance(forward: ratio > 0.8)
    }

    private func toggleChrome() {
        isChromeVisible.toggle()
        chrome.setVisible(isChromeVisible)
        if isChromeVisible { updateChrome() }
    }

    private func advance(forward: Bool) {
        guard let controller = pageViewController,
              let current = controller.viewControllers?.first as? ReaderPageViewController else { return }

        let target = forward
            ? self.pageViewController(controller, viewControllerAfter: current)
            : self.pageViewController(controller, viewControllerBefore: current)

        guard let target else {
            if forward { Toast.show("已读完本书") }
            return
        }
        controller.setViewControllers([target], direction: forward ? .forward : .reverse, animated: true) { [weak self] _ in
            guard let self, let page = target as? ReaderPageViewController else { return }
            self.apply(page: page, previousChapter: self.chapterIndex)
        }
    }

    private func apply(page: ReaderPageViewController, previousChapter: Int) {
        chapterIndex = page.chapterIndex
        pageIndex = page.pageIndex
        currentOffset = page.globalOffset
        updateChrome()
        scheduleSave()

        if page.chapterIndex != previousChapter, let title = currentChapterTitle {
            Toast.show(title)
        }
    }

    @objc private func handleEdgePan(_ gesture: UIScreenEdgePanGestureRecognizer) {
        guard gesture.state == .ended else { return }
        let translation = gesture.translation(in: view)
        let velocity = gesture.velocity(in: view)
        if translation.x > 80 || velocity.x > 600 {
            closeReader()
        }
    }

    private func closeReader() {
        saveProgress(immediate: true)
        onClose?()
    }

    @objc private func appDidEnterBackground() {
        saveProgress(immediate: true)
    }

    // MARK: - 进度

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.saveProgress(immediate: false)
        }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    private func saveProgress(immediate: Bool) {
        guard let bookID = book.id else { return }
        do {
            try store.saveProgress(bookID: bookID,
                                   chapterIndex: chapterIndex,
                                   charOffset: currentOffset,
                                   percent: currentPercent)
        } catch {
            if immediate { Toast.show("保存失败，请重试") }
        }
    }

    private func startTotalPageCount() {
        guard preferences.pageTransition != .continuous, let context else { return }
        totalPagesWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let total = self.pagination.totalPageCount(context: context,
                                                       params: self.resolvedParams,
                                                       textColor: self.currentTheme.textColor,
                                                       isCancelled: { false })
            guard let total else { return }
            DispatchQueue.main.async {
                self.totalPageCount = total
                self.updateChrome()
            }
        }
        totalPagesWorkItem = item
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.8, execute: item)
    }

    private func showProgressToast() {
        var text = "已读 \(Int((currentPercent * 100).rounded()))%"
        if preferences.pageTransition != .continuous {
            let paginated = paginatedChapter(chapterIndex)
            text += " · 本章 \(pageIndex + 1)/\(paginated.pageCount) 页"
        }
        if let total = totalPageCount {
            text += " · 全书 \(total) 页"
        }
        Toast.show(text)
    }

    // MARK: - Chrome

    private func updateChrome() {
        let percentText = "\(Int((currentPercent * 100).rounded()))%"
        var pageText = ""
        if preferences.pageTransition != .continuous {
            let paginated = paginatedChapter(chapterIndex)
            pageText = "\(pageIndex + 1)/\(paginated.pageCount)"
        }
        let bookmarked = isBookmarked(at: currentOffset)
        chrome.update(bookTitle: book.title,
                      chapterTitle: currentChapterTitle,
                      isBookmarked: bookmarked,
                      percentText: percentText,
                      pageText: pageText)
    }

    // MARK: - 设置变更

    private func scheduleSettingsApply() {
        settingsWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.applySettingsIfNeeded() }
        settingsWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: item)
    }

    private func applySettingsIfNeeded() {
        let newTheme = preferences.theme
        let newParams = makeParams(viewport: lastLayoutSize == .zero ? view.bounds.size : lastLayoutSize)
        let themeChanged = newTheme != currentTheme
        let paramsChanged = newParams.fingerprint != params?.fingerprint
        let modeChanged = preferences.pageTransition != lastMode

        guard themeChanged || paramsChanged || modeChanged else { return }

        let anchor = currentOffset
        currentTheme = newTheme
        params = newParams
        lastMode = preferences.pageTransition

        view.backgroundColor = newTheme.background
        pageContainer.backgroundColor = newTheme.background
        setNeedsStatusBarAppearanceUpdate()

        restorePosition(forOffset: anchor)
        rebuildReader()
        updateChrome()
    }

    // MARK: - 书签

    private func isBookmarked(at offset: Int) -> Bool {
        guard let bookID = book.id else { return false }
        return (try? store.bookmark(bookID: bookID, charOffset: offset)) != nil
    }

    private func toggleBookmark() {
        guard let bookID = book.id else { return }
        let offset = currentOffset

        if isBookmarked(at: offset) {
            try? store.removeBookmark(bookID: bookID, charOffset: offset)
            Toast.show("已移除书签")
            updateChrome()
            return
        }

        guard let context else { return }
        let ns = context.fullText as NSString
        let length = min(30, max(0, ns.length - offset))
        let excerpt = length > 0
            ? ns.substring(with: NSRange(location: offset, length: length))
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespaces)
            : book.title

        do {
            _ = try store.addBookmark(bookID: bookID,
                                      chapterIndex: chapterIndex,
                                      charOffset: offset,
                                      chapterTitle: currentChapterTitle ?? book.title,
                                      excerpt: excerpt)
            Toast.show("已添加书签")
        } catch {
            Toast.show(error.localizedDescription)
        }
        updateChrome()
    }

    // MARK: - 面板

    private func presentSettings() {
        let panel = ReadingSettingsView(preferences: preferences)
        presentBottomSheet(height: .fixed(620), content: panel)
    }

    private func presentTableOfContents() {
        let view = ChapterDrawerView(chapters: chapters,
                                     currentIndex: chapterIndex,
                                     isChaptered: book.chapterMode != .none,
                                     onClose: { [weak self] in self?.dismissBottomSheet() },
                                     onJumpChapterEnd: { [weak self] index in
                                         self?.jumpToChapterEnd(index)
                                     },
                                     onSelect: { [weak self] index in
                                         self?.jump(toChapter: index)
                                     })
        presentBottomSheet(height: .fraction(0.72), content: view)
    }

    private func presentBookmarkList() {
        let bookID = book.id ?? 0
        let view = ReaderBookmarkSheet(bookID: bookID,
                                       onClose: { [weak self] in self?.dismissBottomSheet() },
                                       onSelect: { [weak self] bookmark in
                                           self?.jump(toOffset: bookmark.charOffset)
                                       })
        presentBottomSheet(height: .fraction(0.7), content: view)
    }

    private func jumpToChapterEnd(_ index: Int) {
        guard chapters.indices.contains(index) else { return }
        let chapter = chapters[index]
        jump(toOffset: max(chapter.startOffset, chapter.endOffset - 1))
    }

    private func jump(toChapter index: Int) {
        guard chapters.indices.contains(index) else { return }
        jump(toOffset: chapters[index].startOffset)
    }

    private func jump(toOffset offset: Int) {
        restorePosition(forOffset: offset)
        if let controller = pageViewController, let page = makePageController(chapter: chapterIndex, page: pageIndex) {
            controller.setViewControllers([page], direction: .forward, animated: false)
        }
        if let continuousView {
            continuousView.jump(toOffset: currentOffset)
        }
        updateChrome()
        scheduleSave()
        dismissBottomSheet()
    }
}

// MARK: - UIPageViewController 数据源 / 代理

extension ReaderViewController: UIPageViewControllerDataSource, UIPageViewControllerDelegate {

    func pageViewController(_ pageViewController: UIPageViewController,
                            viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let page = viewController as? ReaderPageViewController else { return nil }

        if page.pageIndex > 0 {
            return makePageController(chapter: page.chapterIndex, page: page.pageIndex - 1)
        }
        let previousChapter = page.chapterIndex - 1
        guard previousChapter >= 0 else { return nil }
        let lastPage = paginatedChapter(previousChapter).lastPageIndex
        return makePageController(chapter: previousChapter, page: lastPage)
    }

    func pageViewController(_ pageViewController: UIPageViewController,
                            viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let page = viewController as? ReaderPageViewController else { return nil }

        let pageCount = paginatedChapter(page.chapterIndex).pageCount
        if page.pageIndex + 1 < pageCount {
            return makePageController(chapter: page.chapterIndex, page: page.pageIndex + 1)
        }
        let nextChapter = page.chapterIndex + 1
        guard nextChapter < chapters.count else { return nil }
        return makePageController(chapter: nextChapter, page: 0)
    }

    func pageViewController(_ pageViewController: UIPageViewController,
                            didFinishAnimating finished: Bool,
                            previousViewControllers: [UIViewController],
                            transitionCompleted completed: Bool) {
        guard completed,
              let current = pageViewController.viewControllers?.first as? ReaderPageViewController else { return }
        apply(page: current, previousChapter: chapterIndex)
    }
}
