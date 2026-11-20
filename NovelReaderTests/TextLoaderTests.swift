//
//  TextLoaderTests.swift
//  NovelReaderTests
//
//  PRD §9：编码识别（UTF-8 / UTF-16 / GB18030 各 1 例 + 1 例乱码拒绝）
//

import XCTest
@testable import NovelReader

final class TextLoaderTests: XCTestCase {

    func testDecodesUTF8() throws {
        let text = "第一章 起始\n这是正文。"
        let data = try XCTUnwrap(text.data(using: .utf8))

        let decoded = try TextLoader.decode(data)
        XCTAssertEqual(decoded.encoding, .utf8)
        XCTAssertEqual(decoded.text, text)
    }

    func testDecodesUTF16LittleEndianWithBOM() throws {
        let text = "第一章 起始"
        let body = try XCTUnwrap(text.data(using: .utf16LittleEndian))
        var data = Data([0xFF, 0xFE])
        data.append(body)

        let decoded = try TextLoader.decode(data)
        XCTAssertEqual(decoded.encoding, .utf16)
        // BOM 保留在字符串开头，由 TextCleaner 去掉
        XCTAssertEqual(decoded.text.replacingOccurrences(of: "\u{FEFF}", with: ""), text)
    }

    func testDecodesUTF16BigEndianWithBOM() throws {
        let text = "第二章 另一段"
        let body = try XCTUnwrap(text.data(using: .utf16BigEndian))
        var data = Data([0xFE, 0xFF])
        data.append(body)

        let decoded = try TextLoader.decode(data)
        XCTAssertEqual(decoded.encoding, .utf16)
        XCTAssertEqual(decoded.text.replacingOccurrences(of: "\u{FEFF}", with: ""), text)
    }

    func testDecodesGB18030() throws {
        let text = "第一章 测试内容，含中文标点。"
        guard let data = text.data(using: TextLoader.gb18030Encoding) else {
            throw XCTSkip("当前系统不支持 GB18030 编码")
        }
        // 中文 GB18030 字节不是合法 UTF-8，确保走的是第三条分支
        XCTAssertNil(String(data: data, encoding: .utf8))

        let decoded = try TextLoader.decode(data)
        XCTAssertEqual(decoded.encoding, .gb18030)
        XCTAssertEqual(decoded.text, text)
    }

    func testRejectsUnrecognizedEncoding() {
        // 0xC3 期待一个后续字节，0x28 不是合法继续字节；GB18030 同样解不出来
        let data = Data([0xC3, 0x28, 0xC3, 0x28])
        XCTAssertThrowsError(try TextLoader.decode(data)) { error in
            XCTAssertEqual(error as? TextLoadError, .unrecognizedEncoding)
        }
    }

    func testRejectsEmptyFile() {
        XCTAssertThrowsError(try TextLoader.decode(Data())) { error in
            XCTAssertEqual(error as? TextLoadError, .empty)
        }
    }
}
