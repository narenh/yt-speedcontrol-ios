import Foundation
import Security

extension Notification.Name {
    /// Posted (on the main queue) whenever the Canopy Account token is deleted, so the app
    /// can go back to sign-in from wherever the 401 happened.
    static let canopyTokenRemoved = Notification.Name("canopyTokenRemoved")
}

/// The Canopy Account token, kept as a Keychain generic password.
/// "ThisDeviceOnly" keeps it out of iCloud Keychain and backups; "AfterFirstUnlock" lets the
/// Live Activity intents (which run in the app's process) read it while the phone is locked.
/// Never log the token.
enum TokenStore {
    private static let service = "com.canopysf.CanopyControl.canopyToken"
    private static let account = "token"
    private static let installedKey = "installedBefore"

    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static var token: String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ token: String) {
        SecItemDelete(query as CFDictionary)
        var q = query
        q[kSecValueData as String] = Data(token.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }

    static func delete() {
        let hadToken = token != nil
        SecItemDelete(query as CFDictionary)
        if hadToken {
            DispatchQueue.main.async { NotificationCenter.default.post(name: .canopyTokenRemoved, object: nil) }
        }
    }

    /// Keychain items outlive deleting the app: on the first launch after an install, forget any
    /// token left from before.
    static func clearIfFreshInstall() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: installedKey) else { return }
        SecItemDelete(query as CFDictionary)
        defaults.set(true, forKey: installedKey)
    }
}
