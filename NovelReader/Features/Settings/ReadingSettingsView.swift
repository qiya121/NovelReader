//
//  ReadingSettingsView.swift
//  NovelReader
//
//  阅读设置面板（P5）。6 组，顺序固定：
//  翻页方式 → 亮度 → 背景颜色 → 字体大小 → 字体样式 → 行间距
//
//  视觉规格见 PRD §7，全部写死在这里的常量里，不引入主题系统。
//

import SwiftUI

struct ReadingSettingsView: View {

    @ObservedObject var preferences: ReadingPreferences
    var onClose: () -> Void = { }

    @State private var showFontPicker = false

    var body: some View {
        ZStack {
            Color.white
            if showFontPicker {
                fontPicker
            } else {
                content
            }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: ReaderUI.groupSpacing) {
                    transitionSection
                    brightnessSection
                    backgroundSection
                    fontSizeSection
                    fontFamilySection
                    lineSpacingSection
                }
                .padding(.horizontal, ReaderUI.panelHorizontalPadding)
                .padding(.top, 4)
                .padding(.bottom, 32)
            }
        }
    }

    // MARK: - 头部

    private var header: some View {
        HStack {
            Text("阅读设置")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Color(hex: 0x1C1C1E))
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(hex: 0x8E8E93))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, ReaderUI.panelHorizontalPadding)
        .padding(.top, 18)
        .padding(.bottom, 18)
    }

    // MARK: - ① 翻页方式

    private var transitionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("翻页方式")
            HStack(spacing: 10) {
                ForEach(PageTransitionMode.allCases) { mode in
                    OptionChip(title: mode.displayName,
                               isSelected: preferences.pageTransition == mode) {
                        preferences.pageTransition = mode
                    }
                }
            }
        }
    }

    // MARK: - ② 亮度

    private var brightnessSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("亮度")
            HStack(spacing: 12) {
                Image(systemName: "sun.min")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: 0x8E8E93))
                Slider(value: $preferences.appBrightness, in: 0.1...1.0)
                    .tint(Color(hex: 0x0A84FF))
                Image(systemName: "sun.max")
                    .font(.system(size: 15))
                    .foregroundColor(Color(hex: 0x8E8E93))
            }
        }
    }

    // MARK: - ③ 背景颜色

    private var backgroundSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("背景颜色")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(ReaderTheme.all) { theme in
                        backgroundSwatch(theme)
                    }
                }
                .padding(.vertical, 5)
                .padding(.horizontal, 3)
            }
        }
    }

    private func backgroundSwatch(_ theme: ReaderTheme) -> some View {
        let isSelected = preferences.backgroundColorKey == theme.key
        return Button {
            preferences.backgroundColorKey = theme.key
        } label: {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(hexString: theme.backgroundHex))
                .frame(width: 56, height: 56)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color(hex: 0x1C1C1E), lineWidth: 2)
                        .padding(-3)
                        .opacity(isSelected ? 1 : 0)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white, lineWidth: 1)
                        .opacity(isSelected ? 1 : 0)
                )
                .scaleEffect(isSelected ? 1.06 : 1.0)
                .animation(.easeOut(duration: 0.15), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.name)
    }

    // MARK: - ④ 字体大小

    private var fontSizeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("字体大小")
            HStack(spacing: 10) {
                ForEach(FontTier.allCases) { tier in
                    let isSelected = preferences.fontTier == tier
                    Button {
                        preferences.fontSize = tier.pointSize
                    } label: {
                        Text("A")
                            .font(.system(size: tier.pointSize, weight: .regular))
                            .foregroundColor(Color(hex: 0x3A3A3C))
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(isSelected ? Color.white : Color(hex: 0xF2F2F4))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color(hex: 0x1C1C1E), lineWidth: 1.5)
                                    .opacity(isSelected ? 1 : 0)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - ⑤ 字体样式

    private var fontFamilySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("字体样式")
            Button {
                showFontPicker = true
            } label: {
                HStack {
                    Text(FontFamily.displayName(for: preferences.fontFamilyKey))
                        .font(.system(size: 16))
                        .foregroundColor(Color(hex: 0x3A3A3C))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(hex: 0xC7C7CC))
                }
                .padding(.horizontal, 14)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(hex: 0xF2F2F4))
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - ⑥ 行间距

    private var lineSpacingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("行间距")
            HStack(spacing: 6) {
                ForEach(LineSpacingTier.allCases) { tier in
                    let isSelected = preferences.lineSpacingTier == tier
                    Button {
                        preferences.lineSpacingMultiplier = tier.multiplier
                    } label: {
                        Text(tier.displayName)
                            .font(.system(size: 13))
                            .foregroundColor(Color(hex: 0x3A3A3C))
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(isSelected ? Color.white : Color(hex: 0xF2F2F4))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color(hex: 0x1C1C1E), lineWidth: 1.5)
                                    .opacity(isSelected ? 1 : 0)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(Color(hex: 0x1C1C1E))
    }

    // MARK: - 字体选择（二级页）

    private var fontPicker: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    showFontPicker = false
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(hex: 0x1C1C1E))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)

                Text("字体选择")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Color(hex: 0x1C1C1E))
                Spacer()
            }
            .padding(.horizontal, ReaderUI.panelHorizontalPadding)
            .padding(.top, 18)
            .padding(.bottom, 12)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(FontFamily.available, id: \.key) { item in
                        Button {
                            preferences.fontFamilyKey = item.key
                        } label: {
                            HStack {
                                Text(item.displayName)
                                    .font(.system(size: 16))
                                    .foregroundColor(Color(hex: 0x3A3A3C))
                                Spacer()
                                if preferences.fontFamilyKey == item.key {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(Color(hex: 0x1C1C1E))
                                }
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 52)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(hex: 0xF2F2F4))
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Text("V1 只内置系统字体。自定义字体放到 Resources/Fonts 并注册到 Info.plist 的 UIAppFonts 后会自动出现在这里。")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: 0x8E8E93))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)
                }
                .padding(.horizontal, ReaderUI.panelHorizontalPadding)
                .padding(.bottom, 32)
            }
        }
    }
}

// MARK: - 选项按钮

private struct OptionChip: View {

    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16))
                .foregroundColor(Color(hex: 0x3A3A3C))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? Color.white : Color(hex: 0xF2F2F4))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color(hex: 0x1C1C1E), lineWidth: 1.5)
                        .opacity(isSelected ? 1 : 0)
                )
        }
        .buttonStyle(.plain)
    }
}
