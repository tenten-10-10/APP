import SwiftUI

/// First-run welcome carousel. Introduces the core concepts, then lets the user
/// start from scratch or seed a sample project. Dismissal is recorded in
/// `AppSettings.hasCompletedOnboarding` so it only appears once.
struct OnboardingView: View {
    @EnvironmentObject private var container: ServiceContainer
    @EnvironmentObject private var settings: AppSettings
    @Binding var isPresented: Bool

    @State private var page = 0
    @State private var creatingSample = false
    @State private var error: PresentableError?

    private struct Page: Identifiable {
        let id = UUID()
        let symbol: String
        let title: String
        let body: String
    }

    private let pages: [Page] = [
        Page(symbol: "shippingbox.fill",
             title: NSLocalizedString("ProjectStock へようこそ", comment: ""),
             body: NSLocalizedString("プロジェクトごとに在庫を整理し、QRコードで現物をすばやく管理するアプリです。", comment: "")),
        Page(symbol: "folder.fill",
             title: NSLocalizedString("プロジェクトで整理", comment: ""),
             body: NSLocalizedString("フォルダ・保管場所・製品を自由な階層で管理。数量での管理と、個体ごとの管理のどちらにも対応します。", comment: "")),
        Page(symbol: "qrcode.viewfinder",
             title: NSLocalizedString("QRで入出庫", comment: ""),
             body: NSLocalizedString("スキャンして入庫・出庫・移動・貸出を記録。すべて追記型の台帳に残り、いつでも訂正できます。", comment: "")),
        Page(symbol: "square.and.arrow.up.on.square.fill",
             title: NSLocalizedString("ラベル印刷と共有", comment: ""),
             body: NSLocalizedString("QRラベルを PNG / PDF / EPS で書き出して印刷。プロジェクトは iCloud でチームと共有できます。", comment: "")),
    ]

    private var isLastPage: Bool { page == pages.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            header
            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { idx, item in
                    pageView(item).tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: page)

            PageDots(count: pages.count, index: page)
                .padding(.bottom, 16)

            controls
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .errorAlert($error)
        .interactiveDismissDisabled(true)
    }

    private var header: some View {
        HStack {
            Spacer()
            Button(NSLocalizedString("スキップ", comment: "")) { finish(seedSample: false) }
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding()
                .accessibilityIdentifier("onboardingSkip")
        }
    }

    private func pageView(_ item: Page) -> some View {
        VStack(spacing: 28) {
            Spacer(minLength: 0)
            ZStack {
                Circle()
                    .fill(Brand.gradient)
                    .frame(width: 148, height: 148)
                    .shadow(color: Brand.primary.opacity(0.35), radius: 18, y: 8)
                Image(systemName: item.symbol)
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundColor(.white)
            }
            .accessibilityHidden(true)
            VStack(spacing: 12) {
                Text(item.title)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                Text(item.body)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 28)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var controls: some View {
        if isLastPage {
            VStack(spacing: 12) {
                Button {
                    finish(seedSample: false)
                } label: {
                    Text(NSLocalizedString("始める", comment: ""))
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("onboardingStart")

                Button {
                    finish(seedSample: true)
                } label: {
                    if creatingSample {
                        ProgressView()
                    } else {
                        Text(NSLocalizedString("サンプルデータで試す", comment: ""))
                    }
                }
                .font(.subheadline.weight(.medium))
                .disabled(creatingSample)
            }
        } else {
            Button {
                withAnimation { page += 1 }
            } label: {
                Text(NSLocalizedString("次へ", comment: ""))
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    private func finish(seedSample: Bool) {
        if seedSample {
            creatingSample = true
            let result = container.performWrite { ctx in
                _ = try container.sampleData.makeSampleProject(in: ctx, owner: settings.effectiveOperatorName)
            }
            creatingSample = false
            if case .failure(let err) = result {
                error = PresentableError(err)
                return
            }
        }
        settings.hasCompletedOnboarding = true
        Haptics.success()
        withAnimation { isPresented = false }
    }
}
