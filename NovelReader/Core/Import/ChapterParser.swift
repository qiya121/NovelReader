//
//  ChapterParser.swift
//  NovelReader
//
//  章节解析（PRD §5.2 + 补丁 R-03）
//
//  三种模式：
//   - strict：只认「第X章」，X 为阿拉伯数字
//   - loose ：额外接受中文数字、其他量词、Chapter/Ch.、楔子/番外等、裸数字标题行
//   - none  ：不分章，整本一章
//
//  【防误判】这是全项目最容易出错的地方，规则必须逐条实现：
//   1. 候选行长度 > 40 → 丢弃
//   2. 相邻两章之间字符数 < 100 → 丢弃后一个（保留前一个）
//   3. 章数上限（补丁 R-03 拆分）：
//        3-A 平均每章 < 100 字 → 判定误判，降级为 none
//        3-B 章数 > 2000 但平均长度正常 → 保留，仅软提示
//   4. 章节行必须整行独占（本实现按行扫描，天然满足）
//   5. 第一章之前正文 > 500 字 → 补一个「正文开始前」章节
//

import Foundation

// MARK: - 结果结构

struct ParsedChapter: Hashable {
    var index: Int
    var title: String
    var startOffset: Int
    var endOffset: Int

    var charCount: Int { max(0, endOffset - startOffset) }
}

struct ChapterParseResult {
    var chapters: [ParsedChapter]
    /// 实际生效的模式（可能因规则降级）
    var effectiveMode: ChapterMode
    /// 是否发生了自动降级
    var didDegrade: Bool
    /// 降级/软提示的文案，交给导入流程做 Toast
    var notice: String?
}

// MARK: - 解析器

enum ChapterParser {

    static let preambleTitle = "正文开始前"
    static let preambleMinLength = 500

    static let maxChapterCount = 2000
    /// 补丁 R-03：平均每章短于此值才判定为"把正文切碎了"
    static let minAverageChapterLength = 100

    static let strictMaxLineLength = 30
    static let looseMaxLineLength = 40
    static let minGapBetweenChapters = 100

    // MARK: 正则（逐字对应 PRD §5.2）

    /// 严格：行首可选空格 + 第 + 1~6 位阿拉伯数字 + 章，其后可带标题
    private static let strictRegex = try! NSRegularExpression(
        pattern: #"^\s*第[0-9]{1,6}\s*章[^\n]{0,25}$"#
    )

    /// 宽松 1：中文数字 / 阿拉伯数字 + 章节回卷篇部
    private static let looseNumberedRegex = try! NSRegularExpression(
        pattern: #"^\s*第\s*[0-9零一二三四五六七八九十百千两]{1,8}\s*[章节回卷篇部]\s*.{0,25}$"#
    )

    /// 宽松 2：Chapter 1 / CHAPTER 01 / Ch.1
    private static let looseEnglishRegex = try! NSRegularExpression(
        pattern: #"^\s*(?:Chapter|Ch\.)\s*[0-9]{1,4}\b.{0,25}$"#,
        options: [.caseInsensitive]
    )

    /// 宽松 3：独立成行的标志词
    private static let looseKeywordRegex = try! NSRegularExpression(
        pattern: #"^\s*(楔子|序章|引子|前言|后记|尾声|番外|终章|大结局)\s*.{0,15}$"#
    )

    /// 宽松 4：裸标题行 `1.` `01 ` `一、`
    private static let looseNumericBareRegex = try! NSRegularExpression(
        pattern: #"^\s*[0-9]{1,4}\s*[\.、\)]\s*\S{1,20}$"#
    )
    private static let looseChineseNumeralBareRegex = try! NSRegularExpression(
        pattern: #"^\s*[零一二三四五六七八九十百千两]{1,8}\s*[、\.]\s*\S{1,20}$"#
    )

    private static let looseKeywords = ["楔子", "序章", "引子", "前言", "后记", "尾声", "番外", "终章", "大结局"]

    private static let chineseNumerals = Set("零一二三四五六七八九十百千两")

    // MARK: - 入口

    static func parse(text: String,
                      mode: ChapterMode,
                      bookTitle: String,
                      progress: ((Double) -> Void)? = nil) -> ChapterParseResult {

        let ns = text as NSString
        let totalLength = ns.length

        guard totalLength > 0 else {
            return ChapterParseResult(chapters: [], effectiveMode: .none, didDegrade: false, notice: nil)
        }

        switch mode {
        case .none:
            return ChapterParseResult(chapters: [wholeBookChapter(totalLength: totalLength, title: bookTitle)],
                                      effectiveMode: .none,
                                      didDegrade: false,
                                      notice: nil)

        case .strict:
            let matches = scanLines(in: ns, progress: progress) { line in
                self.strictLineTitle(line)
            }
            guard !matches.isEmpty else {
                return ChapterParseResult(chapters: [wholeBookChapter(totalLength: totalLength, title: bookTitle)],
                                          effectiveMode: .none,
                                          didDegrade: true,
                                          notice: "未识别到章节，已按整本处理")
            }
            let chapters = buildChapters(totalLength: totalLength, matches: matches)
            return ChapterParseResult(chapters: chapters,
                                      effectiveMode: .strict,
                                      didDegrade: false,
                                      notice: nil)

        case .loose:
            var matches = scanLines(in: ns, progress: progress) { line in
                self.looseLineTitle(line)
            }
            guard !matches.isEmpty else {
                return ChapterParseResult(chapters: [wholeBookChapter(totalLength: totalLength, title: bookTitle)],
                                          effectiveMode: .none,
                                          didDegrade: true,
                                          notice: "未识别到章节，已按整本处理")
            }

            // 防误判 2：相邻章节间距 < 100 字 → 丢弃后一个
            matches = filterDenseMatches(matches)

            // 防误判 3（补丁 R-03）
            // 说明：经过上面的间距过滤后，相邻章节起点至少相距 100 字，
            // 因此"平均每章 < 100 字"在正常情况下不会成立。这里保留这条判断作为防御性兜底：
            // 一旦将来放宽间距规则（例如允许 50 字），它仍然能挡住"把正文切碎"的输入。
            if matches.count > 1 {
                let average = totalLength / max(matches.count, 1)
                if average < minAverageChapterLength {
                    return ChapterParseResult(chapters: [wholeBookChapter(totalLength: totalLength, title: bookTitle)],
                                              effectiveMode: .none,
                                              didDegrade: true,
                                              notice: "未识别到有效章节，已按整本处理")
                }
            }

            var notice: String?
            if matches.count > maxChapterCount {
                notice = "已识别 \(matches.count) 章，如目录过多可改用严格模式"
            }

            let chapters = buildChapters(totalLength: totalLength, matches: matches)
            return ChapterParseResult(chapters: chapters,
                                      effectiveMode: .loose,
                                      didDegrade: false,
                                      notice: notice)
        }
    }

    // MARK: - 单行判定

    /// 严格模式：长度 ≤ 30、必须含「第」、整行匹配正则
    static func strictLineTitle(_ line: String) -> String? {
        let length = line.utf16.count
        guard length > 0, length <= strictMaxLineLength else { return nil }
        guard line.contains("第") else { return nil }
        guard matches(strictRegex, line) else { return nil }
        return line.trimmingCharacters(in: .whitespaces)
    }

    /// 宽松模式：长度 ≤ 40 + 快速预筛 + 五个正则任一命中
    static func looseLineTitle(_ line: String) -> String? {
        let length = line.utf16.count
        guard length > 0, length <= looseMaxLineLength else { return nil }
        guard mayBeLooseCandidate(line) else { return nil }

        let hit = matches(looseNumberedRegex, line)
            || matches(looseEnglishRegex, line)
            || matches(looseKeywordRegex, line)
            || matches(looseNumericBareRegex, line)
            || matches(looseChineseNumeralBareRegex, line)
        guard hit else { return nil }
        return line.trimmingCharacters(in: .whitespaces)
    }

    /// 快速预筛：把 99% 的正文行挡在正则之前（5MB 文件的性能关键）
    private static func mayBeLooseCandidate(_ line: String) -> Bool {
        if line.contains("第") { return true }

        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.unicodeScalars.first else { return false }

        if first.properties.numericType != nil { return true }
        if chineseNumerals.contains(Character(first)) { return true }

        let lowered = trimmed.lowercased()
        if lowered.hasPrefix("chapter") || lowered.hasPrefix("ch.") { return true }

        for keyword in looseKeywords where trimmed.hasPrefix(keyword) {
            return true
        }
        return false
    }

    private static func matches(_ regex: NSRegularExpression, _ string: String) -> Bool {
        let range = NSRange(location: 0, length: (string as NSString).length)
        return regex.firstMatch(in: string, options: [], range: range) != nil
    }

    // MARK: - 行扫描

    /// 逐行扫描，返回 (行首偏移, 标题)
    private static func scanLines(in ns: NSString,
                                  progress: ((Double) -> Void)?,
                                  matcher: (String) -> String?) -> [(start: Int, title: String)] {

        var results: [(start: Int, title: String)] = []
        guard ns.length > 0 else { return results }

        let total = Double(ns.length)
        var cursor = 0
        var lineCounter = 0

        while cursor < ns.length {
            var lineStart = 0
            var lineEnd = 0
            var contentsEnd = 0
            ns.getLineStart(&lineStart,
                            end: &lineEnd,
                            contentsEnd: &contentsEnd,
                            for: NSRange(location: cursor, length: 0))

            let contentLength = max(0, contentsEnd - lineStart)
            if contentLength > 0 {
                let line = ns.substring(with: NSRange(location: lineStart, length: contentLength))
                if let title = matcher(line) {
                    results.append((start: lineStart, title: title))
                }
            }

            lineCounter += 1
            if lineCounter % 2000 == 0 {
                progress?(min(1.0, Double(cursor) / total))
            }

            if lineEnd <= cursor { break }
            cursor = lineEnd
        }

        progress?(1.0)
        return results
    }

    // MARK: - 组合章节

    private static func wholeBookChapter(totalLength: Int, title: String) -> ParsedChapter {
        ParsedChapter(index: 0, title: title, startOffset: 0, endOffset: totalLength)
    }

    /// 防误判 2：相邻两个章节行的间距 < 100 字 → 丢弃后一个（保留前一个）
    ///
    /// 比较对象是**相邻的两个候选行**，不是「上一个被保留的章节」。
    /// 若改成与保留结果比较，密集候选会被稀疏化成"每 100 字一章"——
    /// 而这一段密集候选的本来面目是正文误命中，应该整段只留第一个。
    private static func filterDenseMatches(_ matches: [(start: Int, title: String)]) -> [(start: Int, title: String)] {
        guard matches.count > 1 else { return matches }
        var kept: [(start: Int, title: String)] = [matches[0]]
        var previousStart = matches[0].start

        for index in 1..<matches.count {
            let candidate = matches[index]
            let gap = candidate.start - previousStart
            previousStart = candidate.start
            if gap < minGapBetweenChapters {
                continue // 丢弃后一个，保留前一个
            }
            kept.append(candidate)
        }
        return kept
    }

    private static func buildChapters(totalLength: Int,
                                      matches: [(start: Int, title: String)]) -> [ParsedChapter] {
        var chapters: [ParsedChapter] = []

        // 防误判 5：正文开头 > 500 字且不是章标题 → 补一个「正文开始前」
        if let first = matches.first, first.start > preambleMinLength {
            chapters.append(ParsedChapter(index: 0,
                                          title: preambleTitle,
                                          startOffset: 0,
                                          endOffset: first.start))
        }

        for (offset, match) in matches.enumerated() {
            // 没有前言章节时，第一章从 0 开始，避免开头正文丢失
            let start = (offset == 0 && chapters.isEmpty) ? 0 : match.start
            let end = (offset + 1 < matches.count) ? matches[offset + 1].start : totalLength
            guard end > start else { continue }
            chapters.append(ParsedChapter(index: chapters.count,
                                          title: match.title,
                                          startOffset: start,
                                          endOffset: end))
        }

        if chapters.isEmpty {
            chapters.append(ParsedChapter(index: 0,
                                          title: preambleTitle,
                                          startOffset: 0,
                                          endOffset: totalLength))
        }
        return chapters
    }
}
