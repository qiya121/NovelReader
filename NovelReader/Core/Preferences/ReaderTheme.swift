//
//  ReaderTheme.swift
//  NovelReader
//
//  6 组背景色（PRD §5.6 ③）。色值从截图像素取样，必须逐字使用：
//  背景色、配套正文色都要照抄，不得"调一下更好看"。
//

import UIKit

struct ReaderTheme: Equatable, Identifiable {

    let key: String
    let name: String
    let backgroundHex: String
    let textHex: String

    var id: String { key }

    var background: UIColor { UIColor(hexString: backgroundHex) ?? .white }
    var textColor: UIColor { UIColor(hexString: textHex) ?? .black }

    /// 深色主题（用于状态栏样式、滚动条等）
    var isDark: Bool { key == "night_gray" }

    /// 状态栏样式
    var statusBarStyle: UIStatusBarStyle { isDark ? .lightContent : .darkContent }

    // MARK: - 固定顺序（面板里从左到右 1..6）

    static let all: [ReaderTheme] = [
        ReaderTheme(key: "paper_white",  name: "护眼白", backgroundHex: "#ECECE2", textHex: "#3A3A35"),
        ReaderTheme(key: "leaf_green",   name: "豆绿",   backgroundHex: "#D6EBC0", textHex: "#2F3A2A"),
        ReaderTheme(key: "night_gray",   name: "夜阅",   backgroundHex: "#363B37", textHex: "#D7DAD3"),
        ReaderTheme(key: "mist_blue",    name: "雾蓝",   backgroundHex: "#DCE2F0", textHex: "#2E3440"),
        ReaderTheme(key: "clay_pink",    name: "藕粉",   backgroundHex: "#C4ACA2", textHex: "#3B2F2A"),
        ReaderTheme(key: "kraft_yellow", name: "牛皮纸", backgroundHex: "#E7E1D3", textHex: "#3D3729")
    ]

    static let `default` = ReaderTheme.all[0]

    static func theme(forKey key: String) -> ReaderTheme {
        ReaderTheme.all.first { $0.key == key } ?? .default
    }

    // MARK: - 书架封面底色（补丁 R-06：8 色固定映射，非随机）

    static let coverPalette: [UIColor] = [
        UIColor(hex: 0xE8E3D9),
        UIColor(hex: 0xDCE6D5),
        UIColor(hex: 0xE4DFDA),
        UIColor(hex: 0xDAE3EA),
        UIColor(hex: 0xE7DED8),
        UIColor(hex: 0xE3E0D2),
        UIColor(hex: 0xDFE0E6),
        UIColor(hex: 0xE9E2DF)
    ]

    static let coverTextColor = UIColor(hex: 0x4A4A45)

    static func coverColor(seed: Int) -> UIColor {
        guard !coverPalette.isEmpty else { return .systemGray5 }
        let index = ((seed % coverPalette.count) + coverPalette.count) % coverPalette.count
        return coverPalette[index]
    }
}

// MARK: - 设置面板与视觉规范里的固定色（PRD §7）

enum ReaderUI {

    static let panelBackground = UIColor.white
    static let groupTitle = UIColor(hex: 0x1C1C1E)
    static let optionBackground = UIColor(hex: 0xF2F2F4)
    static let optionBorder = UIColor(hex: 0x1C1C1E)
    static let optionText = UIColor(hex: 0x3A3A3C)
    static let sliderTint = UIColor(hex: 0x0A84FF)

    static let panelCornerRadius: CGFloat = 24
    static let panelHorizontalPadding: CGFloat = 20
    static let groupSpacing: CGFloat = 28
}
