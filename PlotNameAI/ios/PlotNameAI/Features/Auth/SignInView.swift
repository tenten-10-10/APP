import SwiftUI

// MARK: - SignInView

/// サインアウト中に表示する軽量なサインイン画面。
/// Mock では自動サインインされるため通常は表示されないが、
/// 本番（Apple/Supabase）でサインアウト状態のときの入口になる。
struct SignInView: View {

    @Environment(AuthService.self) private var auth

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                Text("PlotName AI")
                    .font(.largeTitle.bold())
                Text("ひとつのアイデアから、13フェーズのネームへ。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            VStack(spacing: 12) {
                // Sign in with Apple 風のボタン（本番は SignInWithAppleButton に差し替え可）。
                Button {
                    Task { await auth.signInWithApple() }
                } label: {
                    HStack {
                        Image(systemName: "applelogo")
                        Text("Appleでサインイン")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(.primary)
                .disabled(auth.isAuthenticating)

                if auth.isAuthenticating {
                    ProgressView()
                }

                if let error = auth.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Text("サインインすることで利用規約とプライバシーポリシーに同意したものとみなされます。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .padding()
    }
}

#Preview {
    SignInView()
        .environmentForPreview()
}
