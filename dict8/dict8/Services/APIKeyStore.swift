import Foundation
import Security

protocol APIKeyStoring: Sendable {
    func status() async throws -> APIKeyStatus
    func apiKey() async throws -> String
    func save(_ key: String) async throws
    func remove() async throws
}

enum APIKeyStoreError: Error, Equatable, Sendable {
    case invalidKey
    case missingKey
    case keychainStatus(OSStatus)
}

actor SystemAPIKeyStore: APIKeyStoring {
    nonisolated static let service = "com.xehl.dict8.openrouter"
    nonisolated static let account = "default"

    private let developmentOverride: String?

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        developmentOverride = environment["OPENROUTER_API_KEY"]
    }

    func status() throws -> APIKeyStatus {
        if let developmentOverride,
           !developmentOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .developmentOverride
        }

        var result: CFTypeRef?
        let query: [CFString: Any] = baseQuery.merging([
            kSecMatchLimit: kSecMatchLimitOne,
            kSecReturnAttributes: true,
        ]) { _, new in new }
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            return .storedInKeychain
        case errSecItemNotFound:
            return .missing
        default:
            throw APIKeyStoreError.keychainStatus(status)
        }
    }

    func apiKey() throws -> String {
        if let developmentOverride = validKey(developmentOverride) {
            return developmentOverride
        }

        var result: CFTypeRef?
        let query: [CFString: Any] = baseQuery.merging([
            kSecMatchLimit: kSecMatchLimitOne,
            kSecReturnData: true,
        ]) { _, new in new }
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let key = String(data: data, encoding: .utf8),
                  let validKey = validKey(key) else {
                throw APIKeyStoreError.invalidKey
            }
            return validKey
        case errSecItemNotFound:
            throw APIKeyStoreError.missingKey
        default:
            throw APIKeyStoreError.keychainStatus(status)
        }
    }

    func save(_ key: String) throws {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let data = key.data(using: .utf8) else {
            throw APIKeyStoreError.invalidKey
        }

        let attributes: [CFString: Any] = [kSecValueData: data]
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            attributes as CFDictionary
        )

        if updateStatus == errSecItemNotFound {
            let addQuery = baseQuery.merging([
                kSecValueData: data,
                kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock,
            ]) { _, new in new }
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw APIKeyStoreError.keychainStatus(addStatus)
            }
            return
        }

        guard updateStatus == errSecSuccess else {
            throw APIKeyStoreError.keychainStatus(updateStatus)
        }
    }

    func remove() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw APIKeyStoreError.keychainStatus(status)
        }
    }

    private var baseQuery: [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.service,
            kSecAttrAccount: Self.account,
        ]
    }

    private func validKey(_ key: String?) -> String? {
        guard let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
