import Foundation
import Security

final class GmailCredentialStore: @unchecked Sendable {
    static let shared = GmailCredentialStore()

    private let keychainService: String
    private let keychainAccount = "oauth-token-set"
    private let fileManager: FileManager
    let applicationSupportDirectory: URL
    let configurationURL: URL
    let databaseURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let performancePath = ProcessInfo.processInfo.environment["MAIL_PERF_DATA_DIR"],
           !performancePath.isEmpty {
            applicationSupportDirectory = URL(fileURLWithPath: performancePath, isDirectory: true)
            keychainService = "com.brady.keyboardfirstmail.gmail.performance"
        } else {
            let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
            applicationSupportDirectory = base.appendingPathComponent("KeyboardFirstMail", isDirectory: true)
            keychainService = "com.brady.keyboardfirstmail.gmail"
        }
        configurationURL = applicationSupportDirectory.appendingPathComponent("GmailOAuth.json")
        databaseURL = applicationSupportDirectory.appendingPathComponent("mail.sqlite3")
    }

    func loadConfiguration() throws -> GmailOAuthConfiguration? {
        guard fileManager.fileExists(atPath: configurationURL.path) else { return nil }
        return try JSONDecoder().decode(GmailOAuthConfiguration.self, from: Data(contentsOf: configurationURL))
    }

    func importConfiguration(from url: URL) throws -> GmailOAuthConfiguration {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing { url.stopAccessingSecurityScopedResource() }
        }

        let configuration = try GmailOAuthConfiguration(googleCredentialData: Data(contentsOf: url))
        try ensureApplicationSupportDirectory()
        let data = try JSONEncoder().encode(configuration)
        try data.write(to: configurationURL, options: [.atomic, .completeFileProtectionUnlessOpen])
        return configuration
    }

    func loadTokens() throws -> GmailTokenSet? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw GmailIntegrationError.keychain(status)
        }
        return try JSONDecoder().decode(GmailTokenSet.self, from: data)
    }

    func saveTokens(_ tokens: GmailTokenSet) throws {
        let data = try JSONEncoder().encode(tokens)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            attributes.forEach { insert[$0.key] = $0.value }
            let insertStatus = SecItemAdd(insert as CFDictionary, nil)
            guard insertStatus == errSecSuccess else {
                throw GmailIntegrationError.keychain(insertStatus)
            }
        } else if status != errSecSuccess {
            throw GmailIntegrationError.keychain(status)
        }
    }

    func deleteTokens() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GmailIntegrationError.keychain(status)
        }
    }

    func ensureApplicationSupportDirectory() throws {
        try fileManager.createDirectory(
            at: applicationSupportDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }
}
