import SwiftUI
#if canImport(SwiftData)
import SwiftData
#endif

// MARK: - PlotNameAIApp

@main
struct PlotNameAIApp: App {

    /// アプリ全体のサービスコンテナ。
    @State private var env: AppEnvironment

    /// SwiftData コンテナ（端末ではこれを ProjectStore の永続化に使う）。
    private let modelContainer: ModelContainer?

    init() {
        // SwiftData コンテナを構築。失敗時はファイル永続化にフォールバックする。
        var container: ModelContainer?
        var store: ProjectStore?

        if #available(iOS 17, *) {
            do {
                let c = try ModelContainer(for: ProjectRecord.self)
                container = c
                // ModelContext は @MainActor 上で扱う。
                let persistence = SwiftDataProjectPersistence(context: c.mainContext)
                store = ProjectStore(persistence: persistence)
            } catch {
                #if DEBUG
                print("ModelContainer init failed, falling back to file persistence: \(error)")
                #endif
            }
        }

        self.modelContainer = container
        // store が nil ならファイル永続化の既定ストアになる。
        _env = State(initialValue: AppEnvironment(store: store))
    }

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
                .environment(env.auth)
                .environment(env.reward)
                .tint(.accentColor)
                .applyModelContainer(modelContainer)
        }
    }
}

// MARK: - ModelContainer helper

private extension View {
    /// コンテナがあれば SwiftData モデルコンテナを注入する。
    /// （直接 View に @Query を持たせる予定はないが、環境に載せておく。）
    @ViewBuilder
    func applyModelContainer(_ container: ModelContainer?) -> some View {
        if let container {
            self.modelContainer(container)
        } else {
            self
        }
    }
}
