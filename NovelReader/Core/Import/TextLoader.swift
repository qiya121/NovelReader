//
//  TextLoader.swift
//  NovelReader
//
//  文件读取 + 编码识别（PRD §5.1-2 / §5.1-3）
//
//  编码识别顺序（必须按此顺序，成功即停）：
//    UTF-8 → UTF-16（按 BOM 判 LE/BE）→ GB18030 → 失败
//  判定必须用严格解码，不允许把替换字符（U+FFFD）当成"解码成功"。
//

import Foundation
import CoreFoundation

enum TextEncodingKind: String {
    case utf8
    case utf16
    case gb18030

    var displayName: String {
        switch self {
        case .utf8: return "UTF-8"
        case .utf16: return "UTF-16"
        case .gb18030: return "GB18030"
        }
    }
}

struct DecodedText {
    let text: String
    let encoding: TextEncodingKind
}

enum TextLoadError: LocalizedError, Equatable {
    case unreadable(String)
    case tooLarge
    case unrecognizedEncoding
    case empty

    var errorDescription: String? {
        switch self {
        case .unreadable(let reason):
            return "无法读取文件：\(reason)"
        case .tooLarge:
            return "文件过大，请拆分后导入"
        case .unrecognizedEncoding:
            return "文件编码无法识别，请另存为 UTF-8 后重试"
        case .empty:
            return "文件内容为空"
        }
    }
}

enum TextLoader {

    /// 硬上限（PRD §8：> 50 MB 直接拒绝）
    static let hardLimitBytes = 50 * 1024 * 1024

    /// GB18030 对应的 String.Encoding
    static let gb18030Encoding: String.Encoding = {
        let cfEncoding = CFStringEncodings.GB_18030_2000
        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(cfEncoding.rawValue))
        return String.Encoding(rawValue: nsEncoding)
    }()

    // MARK: - 入口

    /// 读取本地文件并解码。调用方负责处理 security-scoped 访问。
    static func load(from url: URL, progress: ((Double) -> Void)? = nil) throws -> DecodedText {
        let size: Int
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        } catch {
            throw TextLoadError.unreadable(error.localizedDescription)
        }
        guard size <= hardLimitBytes else { throw TextLoadError.tooLarge }

        let data: Data
        do {
            data = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw TextLoadError.unreadable(error.localizedDescription)
        }
        progress?(0.05)
        return try decode(data)
    }

    /// 编码识别（纯字节 → 文本），单测直接调这个
    static func decode(_ data: Data) throws -> DecodedText {
        guard !data.isEmpty else { throw TextLoadError.empty }

        // 1) UTF-8 —— String(data:encoding:.utf8) 对非法序列返回 nil，等价严格解码
        if let text = String(data: data, encoding: .utf8), isClean(text) {
            return DecodedText(text: text, encoding: .utf8)
        }

        // 2) UTF-16 —— 只按 BOM 判定（PRD §5.1-3）
        if data.count >= 2 {
            let bytes = [UInt8](data.prefix(2))
            if bytes[0] == 0xFF && bytes[1] == 0xFE,
               let text = String(data: data, encoding: .utf16LittleEndian), isClean(text) {
                return DecodedText(text: text, encoding: .utf16)
            }
            if bytes[0] == 0xFE && bytes[1] == 0xFF,
               let text = String(data: data, encoding: .utf16BigEndian), isClean(text) {
                return DecodedText(text: text, encoding: .utf16)
            }
        }

        // 3) GB18030
        if let text = String(data: data, encoding: gb18030Encoding), isClean(text) {
            return DecodedText(text: text, encoding: .gb18030)
        }

        // 4) 全部失败：禁止用乱码内容入库
        throw TextLoadError.unrecognizedEncoding
    }

    /// 严格解码的兜底校验：出现替换字符即视为解码失败
    private static func isClean(_ text: String) -> Bool {
        if text.isEmpty { return false }
        return !text.unicodeScalars.contains { $0.value == 0xFFFD }
    }
}
