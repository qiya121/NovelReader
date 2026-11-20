//
//  ReadingPreferences.swift
//  NovelReader
//
//  阅读偏好（PRD §4.4 + 补丁 R-01）
//
//  存储位置：UserDefaults，suite 名 `reading.preferences`（全局默认）。
//  单书覆盖写 `books.settings_override`，V1 不写入（PRD §12.6）。
//
//  字段名固定，禁止改名。
//

import Foundation
import Combine

final class ReadingPreferences: ObservableObject {

    static let suiteName = "reading.preferences"

    enum Key {
        static let fontSize = "font_size_pt"
        static let lineSpacing = "line_spacing_multiplier"
        static let background = "background_color_key"
        static let transition = "page_transition"
        static let brightness = "app_brightness"
        static let fontFamily = "font_family"
        /// 书架布局（PRD §5.3-1，状态持久化）
        static let shelfLayout = "shelf_layout"
    }

    private let defaults: UserDefaults

    // MARK: - 设置值

    /// 真实 pt 值，取值集合 {17, 20, 24}
    @Published var fontSize: CGFloat {
        didSet {
            let clamped = min(max(fontSize, 12), 40)
            if clamped != fontSize {
                fontSize = clamped
                return
            }
            defaults.set(Double(fontSize), forKey: Key.fontSize)
        }
    }

    /// 行距倍率，取值集合 {1.35, 1.5, 1.6, 1.8, 2.0}
    @Published var lineSpacingMultiplier: CGFloat {
        didSet { defaults.set(Double(lineSpacingMultiplier), forKey: Key.lineSpacing) }
    }

    @Published var backgroundColorKey: String {
        didSet { defaults.set(backgroundColorKey, forKey: Key.background) }
    }

    @Published var pageTransition: PageTransitionMode {
        didSet { defaults.set(pageTransition.rawValue, forKey: Key.transition) }
    }

    /// 0.1 ~ 1.0，只影响本 App（PRD §5.6 ②）
    @Published var appBrightness: Double {
        didSet {
            let clamped = min(max(appBrightness, 0.1), 1.0)
            if clamped != appBrightness {
                appBrightness = clamped
                return
            }
            defaults.set(appBrightness, forKey: Key.brightness)
            onBrightnessChanged?(appBrightness)
        }
    }

    @Published var fontFamilyKey: String {
        didSet { defaults.set(fontFamilyKey, forKey: Key.fontFamily) }
    }

    /// 书架是否列表布局（false = 网格 2 列）
    @Published var shelfUsesListLayout: Bool {
        didSet { defaults.set(shelfUsesListLayout ? "list" : "grid", forKey: Key.shelfLayout) }
    }

    /// 亮度变化回调，由 App 层接到遮罩上
    var onBrightnessChanged: ((Double) -> Void)?

    // MARK: - 派生值

    var fontTier: FontTier {
        get { FontTier.from(pointSize: fontSize) }
        set { fontSize = newValue.pointSize }
    }

    var lineSpacingTier: LineSpacingTier {
        get { LineSpacingTier.nearest(toMultiplier: lineSpacingMultiplier) }
        set { lineSpacingMultiplier = newValue.multiplier }
    }

    var theme: ReaderTheme {
        ReaderTheme.theme(forKey: backgroundColorKey)
    }

    // MARK: - 初始化

    init(defaults: UserDefaults? = nil) {
        let store = defaults ?? UserDefaults(suiteName: Self.suiteName) ?? .standard
        self.defaults = store

        store.register(defaults: [
            Key.fontSize: 17.0,                 // 补丁 R-01：默认 17，不是 19
            Key.lineSpacing: 1.6,
            Key.background: "paper_white",
            Key.transition: PageTransitionMode.slide.rawValue,
            Key.brightness: 1.0,
            Key.fontFamily: FontFamily.systemKey,
            Key.shelfLayout: "grid"
        ])

        self.fontSize = CGFloat(store.double(forKey: Key.fontSize))
        self.lineSpacingMultiplier = CGFloat(store.double(forKey: Key.lineSpacing))
        self.backgroundColorKey = store.string(forKey: Key.background) ?? "paper_white"
        self.pageTransition = PageTransitionMode(rawValue: store.string(forKey: Key.transition) ?? "") ?? .slide
        self.appBrightness = store.double(forKey: Key.brightness)
        self.fontFamilyKey = store.string(forKey: Key.fontFamily) ?? FontFamily.systemKey
        self.shelfUsesListLayout = (store.string(forKey: Key.shelfLayout) ?? "grid") == "list"
    }
}
