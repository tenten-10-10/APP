import Foundation
import Security

/// A stable, app-generated device identifier used as `actorDeviceID` on
/// inventory events and as a conflict tiebreaker. Per spec §16 this is an
/// app-private UUID — never the advertising identifier — and may be stored in
/// the Keychain so it survives reinstalls (best-effort; falls back to
/// UserDefaults). It contains no personal data.
final class DeviceIdentity {

    static let shared = DeviceIdentity()

    private let service = "ProjectStock.deviceID"
    private let account = "primary"
    private let defaultsKey = "ProjectStock.deviceID"

    let deviceID: String

    private(set) var displayName: String

    private init() {
        if let stored = Self.readKeychain(service: service, account: account) {
            deviceID = stored
        } else if let fromDefaults = UserDefaults.standard.string(forKey: defaultsKey) {
            deviceID = fromDefaults
            Self.writeKeychain(fromDefaults, service: service, account: account)
        } else {
            let new = UUID().uuidString
            deviceID = new
            UserDefaults.standard.set(new, forKey: defaultsKey)
            Self.writeKeychain(new, service: service, account: account)
        }
        displayName = UserDefaults.standard.string(forKey: "ProjectStock.deviceName")
            ?? DeviceIdentity.defaultDeviceName()
    }

    func updateDisplayName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        displayName = trimmed.isEmpty ? DeviceIdentity.defaultDeviceName() : trimmed
        UserDefaults.standard.set(displayName, forKey: "ProjectStock.deviceName")
    }

    private static func defaultDeviceName() -> String {
        #if canImport(UIKit)
        return UIDeviceName.current
        #else
        return "iPhone"
        #endif
    }

    // MARK: - Keychain helpers

    private static func readKeychain(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }
        return value
    }

    @discardableResult
    private static func writeKeychain(_ value: String, service: String, account: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(attributes as CFDictionary, nil)
        return status == errSecSuccess
    }
}

#if canImport(UIKit)
import UIKit
private enum UIDeviceName {
    static var current: String { UIDevice.current.name }
}
#endif
