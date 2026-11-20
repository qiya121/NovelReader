//
//  ReadingOptions.swift
//  NovelReader
//
//  阅读设置的枚举口径（PRD §5.6 + 补丁 R-01）
//

import Foundation
import CoreGraphics
import UIKit

// MARK: - ① 翻页方式

enum PageTransitionMode: String, CaseIterable, Identifiable {
    case slide       // 左右
    case scroll      // 上下
    case continuous  // 连续

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .slide:      return "左右"
        case .scroll:     return "上下"
        case .continuous: return "连续"
        }
    }
}

// MARK: - ④ 字体大小（补丁 R-01：存真实 pt 值，默认 17）

enum FontTier: String, CaseIterable, Identifiable {
    case small
    case medium
    case large

    var id: String { rawValue }

    var pointSize: CGFloat {
        switch self {
        case .small:  return 17
        case .medium: return 20
        case .large:  return 24
        }
    }

    /// 面板上的展示（三档都是字母 A，只是字号不同）
    var displayName: String { "A" }

    /// 把库里存的 pt 映射到最近档位（19 → 20，兼容历史数据）
    static func nearest(toPointSize size: CGFloat) -> FontTier {
        var best = FontTier.small
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for tier in FontTier.allCases {
            let distance = abs(tier.pointSize - size)
            if distance < bestDistance {
                bestDistance = distance
                best = tier
            }
        }
        return best
    }

    static func from(pointSize size: CGFloat) -> FontTier {
        if let exact = FontTier.allCases.first(where: { abs($0.pointSize - size) < 0.5 }) {
            return exact
        }
        return nearest(toPointSize: size)
    }
}

// MARK: - ⑥ 行间距（5 档，默认 1.6）

enum LineSpacingTier: String, CaseIterable, Identifiable {
    case tight
    case slightlyTight
    case standard
    case slightlyLoose
    case loose

    var id: String { rawValue }

    var multiplier: CGFloat {
        switch self {
        case .tight:         return 1.35
        case .slightlyTight: return 1.5
        case .standard:      return 1.6
        case .slightlyLoose: return 1.8
        case .loose:         return 2.0
        }
    }

    var displayName: String {
        switch self {
        case .tight:         return "紧凑"
        case .slightlyTight: return "较紧"
        case .standard:      return "标准"
        case .slightlyLoose: return "较松"
        case .loose:         return "宽松"
        }
    }

    static func nearest(toMultiplier value: CGFloat) -> LineSpacingTier {
        var best = LineSpacingTier.standard
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for tier in LineSpacingTier.allCases {
            let distance = abs(tier.multiplier - value)
            if distance < bestDistance {
                bestDistance = distance
                best = tier
            }
        }
        return best
    }
}

// MARK: - 字体样式（V1 只有系统默认，预留自定义）

enum FontFamily {

    static let systemKey = "system"

    /// PostScript 名 → 展示名。V1 只有系统默认。
    static var available: [(key: String, displayName: String)] {
        [(systemKey, "系统默认")]
    }

    static func displayName(for key: String) -> String {
        if key == systemKey { return "系统默认" }
        if UIFont(name: key, size: 17) != nil { return key }
        return "加载失败"
    }
}
