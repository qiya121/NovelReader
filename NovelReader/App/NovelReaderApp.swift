//
//  NovelReaderApp.swift
//  NovelReader
//
//  纯本地、无账号、无网络。不声明任何网络权限，不集成任何埋点/广告/崩溃 SDK。
//

import SwiftUI

@main
struct NovelReaderApp: App {

    private let services = AppServices.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(services.preferences)
                .preferredColorScheme(.light)   // V1 不跟随系统深色（PRD §10）
        }
    }
}
