//
//  TextCleaner.swift
//  NovelReader
//
//  文本清洗（PRD §5.1-4）。顺序固定：
//    ① 统一换行 \r\n、\r → \n
//    ② 去掉 BOM 与零宽字符（U+FEFF、U+200B~U+200F）
//    ③ 行尾空格清理
//    ④ 连续 3 个以上空行压缩为 1 个空行
//    ⑤ 制表符 → 4 空格
//
//  【重要】清洗后文本的偏移量就是全书唯一的 offset 基准（PRD 补丁 G-01：UTF-16 单位）。
//  实现上直接按 UTF-16 code unit 处理，天然与 NSRange / NSLayoutManager 对齐，
//  也避免 Swift String 逐 Character 扫描在大文件上的性能问题。
//

import Foundation

enum TextCleaner {

    private static let cr: UInt16 = 0x000D      // \r
    private static let lf: UInt16 = 0x000A      // \n
    private static let tab: UInt16 = 0x0009     // \t
    private static let space: UInt16 = 0x0020   // 半角空格
    private static let ideographicSpace: UInt16 = 0x3000 // 全角空格
    private static let bom: UInt16 = 0xFEFF
    private static let zeroWidthRange: ClosedRange<UInt16> = 0x200B...0x200F

    /// 执行清洗。输入输出都按 UTF-16 处理，不做任何"删除正文"的动作。
    static func clean(_ raw: String) -> String {
        let units = Array(raw.utf16)
        var out: [UInt16] = []
        out.reserveCapacity(units.count)

        var consecutiveNewlines = 0
        var previousWasCR = false

        func trimTrailingSpaces() {
            while let last = out.last, last == space || last == ideographicSpace {
                out.removeLast()
            }
        }

        for unit in units {
            if unit == cr {
                trimTrailingSpaces()
                if consecutiveNewlines < 2 {
                    out.append(lf)
                    consecutiveNewlines += 1
                }
                previousWasCR = true
                continue
            }
            if unit == lf {
                if previousWasCR {
                    // 已经由 \r 输出过换行，跳过 LF，避免 \r\n 变成两个换行
                    previousWasCR = false
                    continue
                }
                trimTrailingSpaces()
                if consecutiveNewlines < 2 {
                    out.append(lf)
                    consecutiveNewlines += 1
                }
                continue
            }
            previousWasCR = false

            if unit == bom || zeroWidthRange.contains(unit) { continue }
            if unit == tab {
                out.append(space); out.append(space); out.append(space); out.append(space)
                continue
            }

            out.append(unit)
            if unit != space && unit != ideographicSpace {
                consecutiveNewlines = 0
            }
        }
        trimTrailingSpaces()

        return String(decoding: out, as: UTF16.self)
    }

    /// 全文 UTF-16 长度 —— 即 `books.char_count`
    static func utf16Length(of text: String) -> Int {
        text.utf16.count
    }
}
