//
//  RootView.swift
//  NovelReader
//

import SwiftUI

struct RootView: View {

    @EnvironmentObject private var preferences: ReadingPreferences
    @StateObject private var shelfModel = ShelfViewModel()

    var body: some View {
        NavigationStack {
            ShelfView(model: shelfModel)
        }
        .tint(Color(hex: 0x1C1C1E))
        .onAppear {
            BrightnessOverlay.shared.setLevel(preferences.appBrightness)
        }
        .onChange(of: preferences.appBrightness) { value in
            BrightnessOverlay.shared.setLevel(value)
        }
    }
}
