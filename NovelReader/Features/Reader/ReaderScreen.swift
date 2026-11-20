//
//  ReaderScreen.swift
//  NovelReader
//
//  SwiftUI 入口包装：全屏阅读页。
//

import SwiftUI
import UIKit

struct ReaderRequest: Identifiable {
    let id = UUID()
    let book: Book
    let initialOffset: Int
}

struct ReaderScreen: UIViewControllerRepresentable {

    let book: Book
    let initialOffset: Int

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> ReaderViewController {
        let controller = ReaderViewController(book: book, initialOffset: initialOffset)
        controller.onClose = { [dismiss] in
            dismiss()
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: ReaderViewController, context: Context) {}
}
