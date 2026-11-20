//
//  BookCardView.swift
//  NovelReader
//
//  书架卡片（网格）/ 行（列表）。封面占位 = 书名首字 + 固定底色（补丁 R-06）。
//

import SwiftUI

struct BookCoverView: View {

    let book: Book
    var width: CGFloat
    var height: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: width * 0.12, style: .continuous)
                .fill(Color(ReaderTheme.coverColor(seed: book.coverSeed)))
            Text(book.initialCharacter)
                .font(.system(size: width * 0.42, weight: .medium))
                .foregroundColor(Color(ReaderTheme.coverTextColor))
        }
        .frame(width: width, height: height)
        .overlay(
            RoundedRectangle(cornerRadius: width * 0.12, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 0.5)
        )
    }
}

// MARK: - 网格卡片

struct BookCardView: View {

    let book: Book
    let chapterCount: Int
    let onToggleFavorite: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                GeometryReader { proxy in
                    BookCoverView(book: book,
                                  width: proxy.size.width,
                                  height: proxy.size.height)
                }
                .aspectRatio(3.0 / 4.0, contentMode: .fit)

                Button(action: onToggleFavorite) {
                    Image(systemName: book.isFavorite ? "star.fill" : "star")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(book.isFavorite ? Color.orange : Color.white)
                        .padding(6)
                        .background(
                            Circle().fill(Color.black.opacity(0.18))
                        )
                }
                .buttonStyle(.plain)
                .padding(6)
                .accessibilityLabel(book.isFavorite ? "取消收藏" : "收藏")
            }

            Text(book.title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color(hex: 0x1C1C1E))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(height: 38, alignment: .top)

            HStack(spacing: 6) {
                Text("\(book.progressPercent)%")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: 0x8E8E93))
                if chapterCount > 0 {
                    Text("共 \(chapterCount) 章")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: 0x8E8E93))
                }
            }
        }
    }
}

// MARK: - 列表行

struct BookRowView: View {

    let book: Book
    let chapterCount: Int
    let onToggleFavorite: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            BookCoverView(book: book, width: 44, height: 59)

            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color(hex: 0x1C1C1E))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text("\(book.progressPercent)%")
                    if chapterCount > 0 {
                        Text("共 \(chapterCount) 章")
                    }
                }
                .font(.system(size: 12))
                .foregroundColor(Color(hex: 0x8E8E93))
            }

            Spacer(minLength: 0)

            Button(action: onToggleFavorite) {
                Image(systemName: book.isFavorite ? "star.fill" : "star")
                    .font(.system(size: 15))
                    .foregroundColor(book.isFavorite ? .orange : Color(hex: 0xC7C7CC))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(book.isFavorite ? "取消收藏" : "收藏")
        }
        .padding(.vertical, 6)
    }
}

// MARK: - 空状态（PRD §5.3-6）

struct ShelfEmptyView: View {

    let onImport: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(hex: 0xF2F2F4))
                Image(systemName: "books.vertical")
                    .font(.system(size: 44, weight: .light))
                    .foregroundColor(Color(hex: 0xB0B0B5))
            }
            .frame(width: 120, height: 120)

            Text("书架还空着，点右上角导入一本 TXT 小说")
                .font(.system(size: 14))
                .foregroundColor(Color(hex: 0x8E8E93))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button(action: onImport) {
                Text("导入")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color(hex: 0x1C1C1E))
                    .padding(.horizontal, 28)
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(hex: 0xF2F2F4))
                    )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex & 0xFF0000) >> 16) / 255,
                  green: Double((hex & 0x00FF00) >> 8) / 255,
                  blue: Double(hex & 0x0000FF) / 255,
                  opacity: alpha)
    }

    init(hexString: String) {
        var value = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        let intValue = UInt32(value, radix: 16) ?? 0xFFFFFF
        self.init(hex: intValue)
    }
}
