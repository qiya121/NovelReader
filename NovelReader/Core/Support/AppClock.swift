//
//  AppClock.swift
//  NovelReader
//
//  时间戳统一 ISO8601，数据库里 created_at / updated_at / bookmarks.created_at 都用它。
//

import Foundation

enum AppClock {

    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    static var now: String {
        formatter.string(from: Date())
    }

    static func date(from string: String) -> Date? {
        formatter.date(from: string)
    }

    /// 书签列表用的短时间文案
    static func shortDisplay(_ iso: String) -> String {
        guard let date = date(from: iso) else { return iso }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
        } else if Calendar.current.isDateInYear(date) {
            formatter.dateFormat = "M月d日"
        } else {
            formatter.dateFormat = "yyyy年M月d日"
        }
        return formatter.string(from: date)
    }
}

private extension Calendar {
    func isDateInYear(_ date: Date) -> Bool {
        isDate(date, equalTo: Date(), toGranularity: .year)
    }
}
