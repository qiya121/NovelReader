//
//  TypesettingParams.swift
//  NovelReader
//
//  排版参数 + 富文本构造（PRD §6 输入口径 / §7 正文规格）
//
//  页边距固定：左右 20pt、上 56pt（预留状态栏与唤起后的顶部栏）、下 40pt。
//

import UIKit

struct TypesettingParams: Hashable {

    /// 正文字号（真实 pt）
    var fontSize: CGFloat
    /// 行距倍率
    var lineSpacingMultiplier: CGFloat
    /// 自定义字体 PostScript 名；nil = 系统字体
    var fontPostScriptName: String?
    /// 正文可用区域（已扣掉页边距）
    var textAreaSize: CGSize
    /// 背景 key，参与缓存指纹（PRD §6）
    var backgroundKey: String

    /// 排版参数指纹：字号 + 行距 + 字体 + 尺寸 + 背景
    var fingerprint: String {
        let family = fontPostScriptName ?? "system"
        let w = Int(textAreaSize.width.rounded())
        let h = Int(textAreaSize.height.rounded())
        let size = Int((fontSize * 10).rounded())
        let spacing = Int((lineSpacingMultiplier * 100).rounded())
        return "\(size)|\(spacing)|\(family)|\(w)x\(h)|\(backgroundKey)"
    }

    static let pageInsets = UIEdgeInsets(top: 56, left: 20, bottom: 40, right: 20)

    static func textAreaSize(forViewport viewport: CGSize) -> CGSize {
        CGSize(width: max(1, viewport.width - pageInsets.left - pageInsets.right),
               height: max(1, viewport.height - pageInsets.top - pageInsets.bottom))
    }
}

// MARK: - 富文本构造

enum TextStyler {

    static func font(size: CGFloat, postScriptName: String?) -> UIFont {
        if let name = postScriptName, let custom = UIFont(name: name, size: size) {
            return custom
        }
        return UIFont.systemFont(ofSize: size)
    }

    /// 正文段落样式：首行缩进 2 字符、段间距 0.8 行、行距倍率
    static func bodyParagraphStyle(fontSize: CGFloat, multiplier: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .left
        style.lineBreakMode = .byWordWrapping
        style.lineHeightMultiple = multiplier
        style.paragraphSpacing = fontSize * 0.8 * multiplier
        style.firstLineHeadIndent = fontSize * 2
        style.headIndent = 0
        style.tailIndent = 0
        return style
    }

    /// 章节标题段落：居中、字号 ×1.35、行距固定 ×1.2、与正文空 1.5 行
    static func titleParagraphStyle(fontSize: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byWordWrapping
        style.lineHeightMultiple = 1.2
        style.paragraphSpacing = fontSize * 1.5
        style.firstLineHeadIndent = 0
        style.headIndent = 0
        return style
    }

    static func bodyAttributes(params: TypesettingParams,
                               color: UIColor) -> [NSAttributedString.Key: Any] {
        [
            .font: font(size: params.fontSize, postScriptName: params.fontPostScriptName),
            .paragraphStyle: bodyParagraphStyle(fontSize: params.fontSize,
                                                multiplier: params.lineSpacingMultiplier),
            .foregroundColor: color
        ]
    }

    /// 构造章节富文本。
    ///
    /// - Parameter inlineTitleLength: 章节首行（标题行，含换行符）的 UTF-16 长度。
    ///   章节标题就长在正文里（章节 startOffset 指向标题行行首），所以**不额外插入标题**，
    ///   只给首行套标题样式 —— 这样分页得到的 charRange 与全文偏移始终一一对应。
    static func attributedString(_ text: String,
                                 params: TypesettingParams,
                                 color: UIColor,
                                 inlineTitleLength: Int) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text,
                                               attributes: bodyAttributes(params: params, color: color))
        let total = (text as NSString).length
        let titleLength = min(max(0, inlineTitleLength), total)
        if titleLength > 0 {
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: font(size: params.fontSize * 1.35, postScriptName: params.fontPostScriptName),
                .paragraphStyle: titleParagraphStyle(fontSize: params.fontSize),
                .foregroundColor: color
            ]
            result.setAttributes(titleAttributes, range: NSRange(location: 0, length: titleLength))
        }
        return result
    }
}
