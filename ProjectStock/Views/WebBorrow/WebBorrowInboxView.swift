import SwiftUI

/// The owner's inbox for borrow requests submitted through the public web form
/// (`t.l0l0.app/<code>`). In "承認してから反映" mode each request is approved or
/// rejected here; in "自動で反映" mode requests are turned into loans on arrival,
/// and only ones that could not be applied automatically remain here.
struct WebBorrowInboxView: View {
    @EnvironmentObject private var webBorrow: WebBorrowInbox
    @EnvironmentObject private var settings: AppSettings

    @State private var busyID: String?
    /// 却下は復元できない（申請がリストから消える）ので、誤タップで
    /// 消してしまわないよう確認を挟む。
    @State private var confirmingReject: WebBorrowRequest?

    var body: some View {
        List {
            Section {
                Picker(NSLocalizedString("受け取り方", comment: ""), selection: $settings.webBorrowModeRaw) {
                    ForEach(WebBorrowMode.allCases) { Text($0.localizedTitle).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(settings.webBorrowMode == .automatic
                     ? NSLocalizedString("QRから届いた借用リクエストを、確認なしで自動的に貸出として記録します。", comment: "")
                     : NSLocalizedString("QRから届いた借用リクエストを一覧で確認し、承認したものだけを貸出として記録します。", comment: ""))
            }

            if webBorrow.pending.isEmpty {
                Section {
                    EmptyStateView(
                        systemImage: "tray",
                        title: NSLocalizedString("新しい借用リクエストはありません", comment: ""),
                        message: NSLocalizedString("QRを読み取った人がWebフォームから借用を申請すると、ここに届きます。", comment: "")
                    )
                    .listRowBackground(Color.clear)
                }
            } else {
                Section(NSLocalizedString("承認待ち", comment: "")) {
                    ForEach(webBorrow.pending) { request in
                        requestRow(request)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("Web借用リクエスト", comment: ""))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if webBorrow.isRefreshing {
                    ProgressView()
                } else {
                    Button {
                        Task { await webBorrow.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel(Text(NSLocalizedString("更新", comment: "")))
                }
            }
        }
        .refreshable { await webBorrow.refresh() }
        .task { await webBorrow.refresh() }
        .alert(webBorrow.errorMessage ?? "",
               isPresented: Binding(get: { webBorrow.errorMessage != nil },
                                    set: { if !$0 { webBorrow.errorMessage = nil } })) {
            Button(NSLocalizedString("OK", comment: "")) { webBorrow.errorMessage = nil }
        }
        .confirmationDialog(NSLocalizedString("この申請を却下しますか？", comment: ""),
                            isPresented: Binding(get: { confirmingReject != nil },
                                                 set: { if !$0 { confirmingReject = nil } }),
                            titleVisibility: .visible,
                            presenting: confirmingReject) { request in
            Button(NSLocalizedString("却下する", comment: ""), role: .destructive) {
                act(request) { await webBorrow.reject(request) }
                confirmingReject = nil
            }
            Button(NSLocalizedString("キャンセル", comment: ""), role: .cancel) { confirmingReject = nil }
        } message: { request in
            Text(String(format: NSLocalizedString("%@ さんの申請を却下します。却下した申請は一覧から消え、元に戻せません。", comment: ""),
                        request.trimmedBorrower.isEmpty ? NSLocalizedString("（借り手未記入）", comment: "") : request.trimmedBorrower))
        }
    }

    @ViewBuilder private func requestRow(_ request: WebBorrowRequest) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle").foregroundColor(Brand.primary)
                Text(request.trimmedBorrower.isEmpty
                     ? NSLocalizedString("借り手未記入", comment: "")
                     : request.trimmedBorrower)
                    .font(.headline)
                Spacer()
            }

            if let dest = request.trimmedDestination {
                Label(dest, systemImage: "shippingbox")
                    .font(.subheadline).foregroundColor(.secondary)
            }

            Text(periodText(request))
                .font(.caption).foregroundColor(.secondary)

            if let note = request.trimmedNote {
                Text(note).font(.caption).foregroundColor(.secondary)
            }

            Label(request.code, systemImage: "qrcode")
                .font(.caption2).foregroundColor(.secondary)

            HStack(spacing: 12) {
                Button {
                    act(request) { await webBorrow.approve(request) }
                } label: {
                    Label(NSLocalizedString("承認して貸出", comment: ""), systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Brand.primary)
                .disabled(busyID != nil)

                Button(role: .destructive) {
                    confirmingReject = request
                } label: {
                    Label(NSLocalizedString("却下", comment: ""), systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(busyID != nil)
            }
            .padding(.top, 2)
            .overlay {
                if busyID == request.id { ProgressView() }
            }
        }
        .padding(.vertical, 4)
    }

    private func periodText(_ request: WebBorrowRequest) -> String {
        let from = request.borrowFrom.flatMap { formattedDay($0) }
        let until = request.borrowUntil.flatMap { formattedDay($0) }
        switch (from, until) {
        case let (f?, u?): return String(format: NSLocalizedString("期間: %@ 〜 %@", comment: ""), f, u)
        case let (f?, nil): return String(format: NSLocalizedString("貸出日: %@", comment: ""), f)
        case let (nil, u?): return String(format: NSLocalizedString("返却予定: %@", comment: ""), u)
        case (nil, nil): return NSLocalizedString("期間の指定なし", comment: "")
        }
    }

    private func formattedDay(_ ymd: String) -> String? {
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: ymd) else { return ymd }
        return DateFormatters.day.string(from: date)
    }

    private func act(_ request: WebBorrowRequest, _ work: @escaping () async -> Void) {
        busyID = request.id
        Task {
            await work()
            busyID = nil
        }
    }
}
