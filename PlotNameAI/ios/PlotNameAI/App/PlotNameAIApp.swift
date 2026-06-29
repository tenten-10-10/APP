import SwiftUI

// MARK: - PlotNameAIApp

@main
struct PlotNameAIApp: App {

    /// アプリ全体のサービスコンテナ。
    @State private var env = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(env)
                .environment(env.store)
                .environment(env.billing)
                .environment(env.usage)
                .environment(env.generation)
                .environment(env.safety)
                .environment(env.config)
                .tint(.accentColor)
        }
    }
}
