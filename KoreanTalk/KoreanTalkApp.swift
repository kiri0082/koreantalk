import SwiftUI
import UIKit

@main
struct KoreanTalkApp: App {

    @StateObject private var env = AppEnvironment()

    init() {
        // Keep screen awake — this app is designed to be used hands-free while driving/walking
        UIApplication.shared.isIdleTimerDisabled = true
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(env)
        }
    }
}
