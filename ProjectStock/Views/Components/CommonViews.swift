import SwiftUI
import UIKit
import MessageUI

/// Generic empty-state placeholder.
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    var message: String? = nil
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            Text(title).font(.headline).multilineTextAlignment(.center)
            if let message {
                Text(message).font(.subheadline).foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .accessibilityElement(children: .combine)
    }
}

/// A labelled metric used across detail headers; wraps so it never clips on a
/// 320pt-wide screen (spec §15).
struct MetricView: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundColor(.secondary)
            Text(value).font(.headline).minimumScaleFactor(0.7).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(title) + Text(": ") + Text(value))
    }
}

/// iOS 15-safe key/value row (avoids iOS 16's `LabeledContent`).
struct LabeledRow: View {
    let title: String
    let value: String
    var body: some View {
        HStack {
            Text(title).foregroundColor(.primary)
            Spacer()
            Text(value).foregroundColor(.secondary).multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(title) + Text(": ") + Text(value))
    }
}

/// iOS 15-safe multiline text input (avoids iOS 16's `TextField(axis:)`).
struct MultilineTextField: View {
    @Binding var text: String
    var placeholder: String
    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
                    .padding(.leading, 4)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .frame(minHeight: 60)
        }
    }
}

/// `UIActivityViewController` wrapper for sharing exported files (spec §16:
/// files come from a temp directory).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Identifiable wrapper so a `URL` can drive a `.sheet(item:)`.
struct ShareableFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// `MFMailComposeViewController` wrapper for emailing an exported file straight
/// out of the app — the simplest way to get a QR label onto a Windows PC.
/// Check `MailComposeView.canSend` before presenting; fall back to `ShareSheet`
/// when no Mail account is configured.
struct MailComposeView: UIViewControllerRepresentable {
    let subject: String
    let body: String
    var attachmentURL: URL? = nil
    var onFinish: () -> Void = {}

    static var canSend: Bool { MFMailComposeViewController.canSendMail() }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        if let url = attachmentURL, let data = try? Data(contentsOf: url) {
            vc.addAttachmentData(data, mimeType: Self.mimeType(for: url), fileName: url.lastPathComponent)
        }
        return vc
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    private static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "png": return "image/png"
        case "pdf": return "application/pdf"
        case "svg": return "image/svg+xml"
        case "eps": return "application/postscript"
        default:    return "application/octet-stream"
        }
    }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult, error: Error?) {
            controller.dismiss(animated: true, completion: onFinish)
        }
    }
}

/// Identifiable error wrapper for `.alert(item:)`.
struct PresentableError: Identifiable {
    let id = UUID()
    let message: String
    let detail: String?
    init(_ error: Error) {
        self.message = error.localizedDescription
        self.detail = (error as NSError).domain.isEmpty ? nil : CloudKitErrorMapper.rawDescription(for: error)
    }
    init(message: String, detail: String? = nil) {
        self.message = message
        self.detail = detail
    }
}

extension View {
    /// Standard error alert with an optional details line.
    func errorAlert(_ error: Binding<PresentableError?>) -> some View {
        alert(item: error) { presentable in
            Alert(title: Text(NSLocalizedString("エラー", comment: "")),
                  message: Text(presentable.message),
                  dismissButton: .default(Text(NSLocalizedString("OK", comment: ""))))
        }
    }
}
