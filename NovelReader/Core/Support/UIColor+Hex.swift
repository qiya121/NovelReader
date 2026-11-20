//
//  UIColor+Hex.swift
//  NovelReader
//

import UIKit

extension UIColor {

    /// `UIColor(hex: 0xECECE2)` 或 `UIColor(hexString: "#ECECE2")`
    convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        let r = CGFloat((hex & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((hex & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(hex & 0x0000FF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: alpha)
    }

    convenience init?(hexString: String) {
        var value = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let intValue = UInt32(value, radix: 16) else { return nil }
        self.init(hex: intValue)
    }
}
