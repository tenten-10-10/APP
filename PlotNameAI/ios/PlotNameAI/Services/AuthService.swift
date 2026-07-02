import Foundation

// MARK: - AppUser

/// アプリ内のユーザー表現。バックエンドのユーザー行に対応（camelCase ⇄ snake_case）。
struct AppUser: Codable, Identifiable, Hashable {
    var id: String
    var displayName: String
    var email: String?

    init(id: String, displayName: String, email: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.email = email
    }
}

// MARK: - AuthError

/// 認証エラー。未設定プロバイダーやキャンセルを表す。
enum AuthError: LocalizedError {
    case notConfigured
    case cancelled
    case failed(reason: String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "この認証プロバイダーは設定されていません。"
        case .cancelled:
            return "サインインがキャンセルされました。"
        case .failed(let reason):
            return "サインインに失敗しました: \(reason)"
        }
    }
}

// MARK: - AuthProviding

/// 認証プロバイダー抽象。Sign in with Apple / Supabase などが準拠する想定。
protocol AuthProviding: Sendable {
    /// Apple でサインインし、ユーザーを返す。
    func signInWithApple() async throws -> AppUser
    /// サインアウト。
    func signOut() async throws
    /// アカウントを削除する（App Review 5.1.1(v) 対応）。
    /// サーバー側のユーザーデータ削除まで行う想定。
    func deleteAccount() async throws
}

// MARK: - MockAuthProvider

/// オフラインで即座にローカルサインインするモック。
/// アプリがネットワーク無しでも動作するよう、これを既定にする。
struct MockAuthProvider: AuthProviding {
    func signInWithApple() async throws -> AppUser {
        // 疑似的な処理遅延。
        try? await Task.sleep(nanoseconds: 200_000_000)
        return AppUser(
            id: "mock-local-user",
            displayName: "ゲスト作家",
            email: nil
        )
    }

    func signOut() async throws {
        // ローカルなので即時。
    }

    func deleteAccount() async throws {
        // ローカルモック: サーバー側データは無いので疑似遅延のみ。
        // ローカルデータの削除は呼び出し側（ProjectStore.deleteAllData）が行う。
        try? await Task.sleep(nanoseconds: 200_000_000)
    }
}

// MARK: - AppleAuthProvider (STUB)

/// Sign in with Apple（AuthenticationServices）を使う本番プロバイダーのスタブ。
///
/// 実装メモ（将来）:
/// - `ASAuthorizationAppleIDProvider` で `ASAuthorizationAppleIDRequest` を作り、
///   `ASAuthorizationController` をデリゲートで駆動する（continuation でラップ）。
/// - credential.user を AppUser.id に、fullName/email を初回のみ受け取って保存する。
/// - Capability「Sign in with Apple」と entitlement が必要（Xcodeで要確認）。
struct AppleAuthProvider: AuthProviding {
    func signInWithApple() async throws -> AppUser {
        // TODO: ASAuthorizationController を用いた実装に差し替える。
        throw AuthError.notConfigured
    }

    func signOut() async throws {
        throw AuthError.notConfigured
    }

    func deleteAccount() async throws {
        // TODO: Sign in with Apple のトークン失効（Apple の revoke API）を
        //       バックエンド経由で行い、ユーザーデータを削除する。
        throw AuthError.notConfigured
    }
}

// MARK: - SupabaseAuthProvider (STUB)

/// Supabase Auth を使う本番プロバイダーのスタブ。
///
/// 実装メモ（将来）:
/// - Supabase の `signInWithIdToken(provider: .apple, idToken:)` に Apple の idToken を渡す。
/// - セッションは Keychain に保存し、起動時に復元する。
struct SupabaseAuthProvider: AuthProviding {
    func signInWithApple() async throws -> AppUser {
        // TODO: Supabase クライアントを用いた実装に差し替える。
        throw AuthError.notConfigured
    }

    func signOut() async throws {
        throw AuthError.notConfigured
    }

    func deleteAccount() async throws {
        // TODO: Supabase の RPC / Edge Function でユーザー行と関連データを削除する。
        throw AuthError.notConfigured
    }
}

// MARK: - AuthService

/// 認証状態を保持する @Observable サービス。
/// 既定は Mock プロバイダーで、起動時に自動サインインしてオフライン動作を保証する。
@Observable
@MainActor
final class AuthService {

    /// 現在のユーザー（nil ならサインアウト中）。
    private(set) var currentUser: AppUser?

    /// 処理中フラグ（ボタンの無効化等に使用）。
    private(set) var isAuthenticating = false

    /// 直近のエラーメッセージ（UI 表示用）。
    var errorMessage: String?

    /// サインイン済みか。
    var isSignedIn: Bool { currentUser != nil }

    private let provider: AuthProviding

    /// - Parameters:
    ///   - provider: 認証プロバイダー。既定は Mock（オフライン即時サインイン）。
    ///   - autoSignIn: 起動時に自動サインインするか（Mock 用途で true 既定）。
    init(provider: AuthProviding = MockAuthProvider(), autoSignIn: Bool = true) {
        self.provider = provider
        if autoSignIn, provider is MockAuthProvider {
            // Mock のときのみ自動サインインしてアプリを止めない。
            Task { await self.signInWithApple() }
        }
    }

    // MARK: Actions

    /// Apple でサインインする。
    func signInWithApple() async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        errorMessage = nil
        defer { isAuthenticating = false }
        do {
            currentUser = try await provider.signInWithApple()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// サインアウトする。
    func signOut() {
        Task {
            try? await provider.signOut()
            currentUser = nil
        }
    }

    /// アカウントを削除し、サインアウト状態にする（App Review 5.1.1(v) 対応）。
    /// ローカルデータの削除は呼び出し側（ProjectStore.deleteAllData）が行う。
    func deleteAccount() async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        errorMessage = nil
        defer { isAuthenticating = false }
        do {
            try await provider.deleteAccount()
            currentUser = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
