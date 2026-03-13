import SwiftUI

struct RootView: View {

    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        TabView {
            ConversationView(viewModel: env.conversationViewModel)
                .tabItem {
                    Label("Conversation", systemImage: "bubble.left.and.bubble.right.fill")
                }

            SettingsView(viewModel: env.settingsViewModel)
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
    }
}
