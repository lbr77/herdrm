import Foundation
import Security

/// Keychain-backed store for tailcat connection tokens, keyed by device id.
///
/// A tailcat token grants full control of the remote herdr (it is the only
/// credential the tunnel checks), so it is kept in the Keychain rather than
/// in `devices.json`. This-device-only accessibility keeps tokens out of
/// iCloud Keychain and device-to-device migration, matching the mobile
/// secret store's posture. Shared by the macOS app today and the iOS
/// transport when that lands — the Security framework is available on both.
public enum TailcatTokenStore {
    private static let service = "dev.bybee.herdrm.tailcat-token"

    public static func token(for deviceID: UUID) throws -> String? {
        var query = baseQuery(deviceID: deviceID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw TailcatTokenStoreError(status: status) }
        guard let data = item as? Data, let token = String(data: data, encoding: .utf8) else {
            throw TailcatTokenStoreError(status: errSecDecode)
        }
        return token
    }

    /// Convenience non-throwing read for connection paths that turn a missing
    /// token into a device error rather than a Keychain failure.
    public static func existingToken(for deviceID: UUID) -> String? {
        try? token(for: deviceID)
    }

    public static func setToken(_ token: String, for deviceID: UUID) throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try removeToken(for: deviceID)
            return
        }
        let data = Data(trimmed.utf8)
        let query = baseQuery(deviceID: deviceID)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw TailcatTokenStoreError(status: updateStatus)
        }
        var newItem = query
        newItem[kSecValueData as String] = data
        newItem[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(newItem as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw TailcatTokenStoreError(status: addStatus) }
    }

    public static func removeToken(for deviceID: UUID) throws {
        let status = SecItemDelete(baseQuery(deviceID: deviceID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TailcatTokenStoreError(status: status)
        }
    }

    private static func baseQuery(deviceID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: deviceID.uuidString,
        ]
    }
}

public struct TailcatTokenStoreError: LocalizedError, Sendable {
    public let status: OSStatus

    public var errorDescription: String? {
        let detail = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
        return "could not access tailcat token in Keychain: \(detail)"
    }
}
