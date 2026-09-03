import Foundation
import Security

struct GmailOAuthConfiguration: Codable, Equatable, Sendable {
    let clientID: String
    let clientSecret: String?
    let authorizationEndpoint: URL
    let tokenEndpoint: URL

    init(
        clientID: String,
        clientSecret: String? = nil,
        authorizationEndpoint: URL = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
        tokenEndpoint: URL = URL(string: "https://oauth2.googleapis.com/token")!
    ) {
        self.clientID = clientID
        self.clientSecret = clientSecret?.nilIfEmpty
        self.authorizationEndpoint = authorizationEndpoint
        self.tokenEndpoint = tokenEndpoint
    }

    init(googleCredentialData data: Data) throws {
        let document = try JSONDecoder().decode(GoogleOAuthCredentialDocument.self, from: data)
        guard let credential = document.installed ?? document.web,
              !credential.clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GmailIntegrationError.invalidOAuthConfiguration
        }

        self.init(
            clientID: credential.clientID,
            clientSecret: credential.clientSecret,
            authorizationEndpoint: credential.authorizationEndpoint.flatMap(URL.init(string:))
                ?? URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
            tokenEndpoint: credential.tokenEndpoint.flatMap(URL.init(string:))
                ?? URL(string: "https://oauth2.googleapis.com/token")!
        )
    }
}

private struct GoogleOAuthCredentialDocument: Decodable {
    let installed: GoogleOAuthCredential?
    let web: GoogleOAuthCredential?
}

private struct GoogleOAuthCredential: Decodable {
    let clientID: String
    let clientSecret: String?
    let authorizationEndpoint: String?
    let tokenEndpoint: String?

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case clientSecret = "client_secret"
        case authorizationEndpoint = "auth_uri"
        case tokenEndpoint = "token_uri"
    }
}

struct GmailTokenSet: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var tokenType: String
    var scope: String?
    var accountEmail: String?

    var hasUsableAccessToken: Bool {
        !accessToken.isEmpty && expiresAt.timeIntervalSinceNow > 75
    }
}

struct GmailCachedMailbox: Sendable {
    // Version 2 repairs caches written by the first summary-only mailbox
    // optimization, which could replace full message payloads with list rows.
    static let currentContentVersion = 2

    let threads: [MailThread]
    let accountEmail: String
    let historyID: String?
    let syncedAt: Date?
    let contentVersion: Int

    init(
        threads: [MailThread],
        accountEmail: String,
        historyID: String?,
        syncedAt: Date?,
        contentVersion: Int = currentContentVersion
    ) {
        self.threads = threads
        self.accountEmail = accountEmail
        self.historyID = historyID
        self.syncedAt = syncedAt
        self.contentVersion = contentVersion
    }
}

struct GmailBootstrapState: Sendable {
    let hasConfiguration: Bool
    let cache: GmailCachedMailbox?
    let recipientDirectory: GmailRecipientDirectorySnapshot?
}

enum GmailConnectionState: Equatable, Sendable {
    case disconnected
    case readyToConnect
    case connecting
    case syncing(completed: Int, total: Int)
    case connected(email: String, syncedAt: Date?)
    case failed(message: String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var sidebarTitle: String {
        switch self {
        case .disconnected: "Connect Gmail"
        case .readyToConnect: "Connect Gmail"
        case .connecting: "Connecting…"
        case let .syncing(completed, total):
            total > 0 ? "Syncing \(completed)/\(total)" : "Syncing Gmail…"
        case let .connected(email, _): email
        case .failed: "Gmail needs attention"
        }
    }
}

enum GmailIntegrationError: LocalizedError, Sendable {
    case missingOAuthConfiguration
    case invalidOAuthConfiguration
    case authorizationCancelled
    case authorizationFailed(String)
    case missingAuthorizationCode
    case stateMismatch
    case missingRefreshToken
    case keychain(OSStatus)
    case invalidServerResponse
    case api(status: Int, message: String)
    case cache(String)
    case attachmentUnreadable(String)
    case unsubscribe(String)

    var errorDescription: String? {
        switch self {
        case .missingOAuthConfiguration:
            "Choose the Desktop OAuth JSON downloaded from Google Cloud first."
        case .invalidOAuthConfiguration:
            "That file is not a valid Google Desktop OAuth credential."
        case .authorizationCancelled:
            "Google authorization was cancelled."
        case let .authorizationFailed(message):
            message
        case .missingAuthorizationCode:
            "Google did not return an authorization code."
        case .stateMismatch:
            "The Google authorization response could not be verified."
        case .missingRefreshToken:
            "Google did not return a refresh token. Remove this app from your Google Account permissions and connect again."
        case let .keychain(status):
            "The Gmail credential could not be saved in Keychain (error \(status))."
        case .invalidServerResponse:
            "Gmail returned an unreadable response."
        case let .api(status, message):
            "Gmail error \(status): \(message)"
        case let .cache(message):
            "The local Gmail cache could not be opened: \(message)"
        case let .attachmentUnreadable(name):
            "The attachment \"\(name)\" could not be read."
        case let .unsubscribe(message):
            "Unsubscribe failed: \(message)"
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
