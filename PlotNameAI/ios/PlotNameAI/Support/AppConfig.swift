import Foundation

// MARK: - ProviderKind

/// 使用する AI プロバイダーの種類。
enum ProviderKind: String, Codable, CaseIterable, Identifiable {
    case mock
    case openAI

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mock: return "Mock（オフライン）"
        case .openAI: return "OpenAI"
        }
    }
}

// MARK: - AppConfig

/// アプリ全体の設定。プロバイダー選択と APIキーの差し込みを担う。
/// 既定は Mock（完全オフラインで動作）。
@Observable
final class AppConfig {

    /// 既定プロバイダーは Mock。
    var providerKind: ProviderKind

    /// OpenAI APIキー（任意）。Info.plist や環境変数からの注入も可能。
    var openAIKey: String?

    init(providerKind: ProviderKind = .mock, openAIKey: String? = nil) {
        self.providerKind = providerKind
        // 環境変数 / Info.plist からキーを読む試み（無ければ nil のまま）。
        self.openAIKey = openAIKey ?? Self.readBundledKey()
    }

    /// 現在の設定に対応する AIProvider を生成する。
    func makeProvider() -> AIProvider {
        switch providerKind {
        case .mock:
            return MockAIProvider()
        case .openAI:
            return OpenAIProvider(apiKey: openAIKey)
        }
    }

    /// Info.plist の "OPENAI_API_KEY" キーを読む（任意）。
    private static func readBundledKey() -> String? {
        if let key = Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String,
           !key.isEmpty {
            return key
        }
        return nil
    }
}
