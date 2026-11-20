//
//  ChapterDrawerView.swift
//  NovelReader
//
//  章节目录抽屉（P7）
//  - 当前章节高亮 + 左侧指示条
//  - 支持搜索章节名
//  - 不分章时显示「本书未分章」，切章按钮置灰
//

import SwiftUI

struct ChapterDrawerView: View {

    let chapters: [Chapter]
    let currentIndex: Int
    let isChaptered: Bool
    var onClose: () -> Void = { }
    var onJumpChapterEnd: ((Int) -> Void)? = nil
    let onSelect: (Int) -> Void

    @State private var query = ""

    private var filteredChapters: [Chapter] {
        let keyword = query.trimmingCharacters(in: .whitespaces)
        guard !keyword.isEmpty else { return chapters }
        return chapters.filter { $0.title.localizedCaseInsensitiveContains(keyword) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if !isChaptered {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 30, weight: .light))
                        .foregroundColor(Color(hex: 0xB0B0B5))
                    Text("本书未分章")
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: 0x8E8E93))
                }
                Spacer()
            } else {
                searchField
                chapterList
            }
        }
        .background(Color.white)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("目录")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Color(hex: 0x1C1C1E))
                if isChaptered {
                    Text("共 \(chapters.count) 章")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: 0x8E8E93))
                }
            }
            Spacer()
            if isChaptered {
                Button {
                    onJumpChapterEnd?(currentIndex)
                } label: {
                    Text("跳到章尾")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: 0x3A3A3C))
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(hex: 0xF2F2F4))
                        )
                }
                .buttonStyle(.plain)
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(hex: 0x8E8E93))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundColor(Color(hex: 0x8E8E93))
            TextField("搜索章节名", text: $query)
                .font(.system(size: 14))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: 0xC7C7CC))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(hex: 0xF2F2F4))
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private var chapterList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredChapters) { chapter in
                        chapterRow(chapter)
                            .id(chapter.index)
                    }
                }
                .padding(.bottom, 24)
            }
            .onAppear {
                proxy.scrollTo(currentIndex, anchor: .center)
            }
        }
    }

    private func chapterRow(_ chapter: Chapter) -> some View {
        let isCurrent = chapter.index == currentIndex
        return Button {
            onSelect(chapter.index)
        } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(isCurrent ? Color(hex: 0x1C1C1E) : Color.clear)
                    .frame(width: 3, height: 18)

                Text(chapter.title)
                    .font(.system(size: 15, weight: isCurrent ? .medium : .regular))
                    .foregroundColor(isCurrent ? Color(hex: 0x1C1C1E) : Color(hex: 0x3A3A3C))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .frame(height: 46)
            .background(isCurrent ? Color(hex: 0xF7F7F8) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
