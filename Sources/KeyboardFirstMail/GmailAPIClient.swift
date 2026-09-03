import Foundation

actor GmailAPIClient {
    private let configuration: GmailOAuthConfiguration
    private let credentialStore: GmailCredentialStore
    private let session: URLSession
    private var tokens: GmailTokenSet
    private let requestClock = ContinuousClock()
    private var nextThreadMetadataRequestAt: ContinuousClock.Instant?

    init(
        configuration: GmailOAuthConfiguration,
        tokens: GmailTokenSet,
        credentialStore: GmailCredentialStore,
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.tokens = tokens
        self.credentialStore = credentialStore
        self.session = session
    }

    func profile() async throws -> GmailProfile {
        try await request(path: "/gmail/v1/users/me/profile")
    }

    func listThreads(
        pageToken: String? = nil,
        maxResults: Int = 100,
        query searchQuery: String? = nil
    ) async throws -> GmailThreadListResponse {
        var query = [
            URLQueryItem(name: "maxResults", value: String(max(1, min(500, maxResults)))),
            URLQueryItem(name: "includeSpamTrash", value: "false")
        ]
        if let pageToken { query.append(URLQueryItem(name: "pageToken", value: pageToken)) }
        if let searchQuery, !searchQuery.isEmpty { query.append(URLQueryItem(name: "q", value: searchQuery)) }
        return try await request(path: "/gmail/v1/users/me/threads", query: query)
    }

    func thread(id: String) async throws -> GmailThreadPayload {
        try await request(
            path: "/gmail/v1/users/me/threads/\(id)",
            query: [URLQueryItem(name: "format", value: "full")]
        )
    }

    func threadMetadata(id: String) async throws -> GmailThreadPayload {
        try await waitForThreadMetadataRequestSlot()
        let headers = ["From", "To", "Cc", "Bcc", "Reply-To"]
        let query = [
            URLQueryItem(name: "format", value: "metadata"),
            URLQueryItem(
                name: "fields",
                value: "id,messages(id,threadId,labelIds,internalDate,payload(headers))"
            )
        ] + headers.map { URLQueryItem(name: "metadataHeaders", value: $0) }
        return try await request(
            path: "/gmail/v1/users/me/threads/\(id)",
            query: query
        )
    }

    func attachment(messageID: String, attachmentID: String) async throws -> GmailAttachmentPayload {
        try await request(
            path: "/gmail/v1/users/me/messages/\(messageID)/attachments/\(attachmentID)"
        )
    }

    func history(startingAt historyID: String, pageToken: String? = nil) async throws -> GmailHistoryListResponse {
        var query = [URLQueryItem(name: "startHistoryId", value: historyID)]
        if let pageToken { query.append(URLQueryItem(name: "pageToken", value: pageToken)) }
        return try await request(path: "/gmail/v1/users/me/history", query: query)
    }

    func modifyThread(id: String, add labelsToAdd: [String], remove labelsToRemove: [String]) async throws {
        let body = try JSONEncoder().encode(GmailModifyRequest(addLabelIds: labelsToAdd, removeLabelIds: labelsToRemove))
        let _: GmailThreadMutationResponse = try await request(
            method: "POST",
            path: "/gmail/v1/users/me/threads/\(id)/modify",
            body: body
        )
    }

    @discardableResult
    func send(raw: String, threadID: String? = nil) async throws -> GmailSendResponse {
        let body = try JSONEncoder().encode(GmailSendRequest(raw: raw, threadId: threadID))
        return try await request(method: "POST", path: "/gmail/v1/users/me/messages/send", body: body)
    }

    func currentTokens() -> GmailTokenSet { tokens }

    private func request<Response: Decodable & Sendable>(
        method: String = "GET",
        path: String,
        query: [URLQueryItem] = [],
        body: Data? = nil
    ) async throws -> Response {
        var didRefreshAfterUnauthorized = false
        var retryCount = 0
        var quotaRetryCount = 0

        while true {
            let accessToken = try await validAccessToken(forceRefresh: didRefreshAfterUnauthorized)
            var components = URLComponents()
            components.scheme = "https"
            components.host = "gmail.googleapis.com"
            components.path = path
            if !query.isEmpty { components.queryItems = query }
            guard let url = components.url else { throw GmailIntegrationError.invalidServerResponse }

            var request = URLRequest(url: url)
            request.httpMethod = method
            request.timeoutInterval = 45
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if let body {
                request.httpBody = body
                request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            }

            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw GmailIntegrationError.invalidServerResponse
            }

            if httpResponse.statusCode == 401, !didRefreshAfterUnauthorized {
                didRefreshAfterUnauthorized = true
                continue
            }

            if (httpResponse.statusCode == 429 || (500...599).contains(httpResponse.statusCode)), retryCount < 3 {
                let delays: [Duration] = [.milliseconds(250), .milliseconds(750), .milliseconds(1_500)]
                try await Task.sleep(for: delays[retryCount])
                retryCount += 1
                continue
            }

            if httpResponse.statusCode == 403,
               GmailAPIErrorEnvelope.isQuotaExceeded(in: data),
               quotaRetryCount < 4 {
                // Gmail's per-user query-cost budget is minute-based. Short
                // retries only create another burst, so progressively span a
                // full quota window while preserving the in-flight scan.
                let delays: [Duration] = [.seconds(10), .seconds(20), .seconds(40), .seconds(60)]
                try await Task.sleep(for: delays[quotaRetryCount])
                quotaRetryCount += 1
                continue
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                throw GmailIntegrationError.api(
                    status: httpResponse.statusCode,
                    message: GmailAPIErrorEnvelope.message(from: data)
                )
            }

            do {
                return try JSONDecoder().decode(Response.self, from: data)
            } catch {
                throw GmailIntegrationError.api(
                    status: httpResponse.statusCode,
                    message: "Could not decode Gmail's response: \(error.localizedDescription)"
                )
            }
        }
    }

    private func waitForThreadMetadataRequestSlot() async throws {
        // A thread metadata read consumes Gmail query-cost units. Reserve
        // starts on the actor so concurrent directory workers cannot burst
        // through the per-minute user quota or contend with foreground mail.
        let now = requestClock.now
        let scheduledAt = max(now, nextThreadMetadataRequestAt ?? now)
        nextThreadMetadataRequestAt = scheduledAt.advanced(by: .milliseconds(500))
        if scheduledAt > now {
            try await requestClock.sleep(until: scheduledAt)
        }
    }

    private func validAccessToken(forceRefresh: Bool) async throws -> String {
        if !forceRefresh, tokens.hasUsableAccessToken { return tokens.accessToken }

        var form: [String: String] = [
            "client_id": configuration.clientID,
            "refresh_token": tokens.refreshToken,
            "grant_type": "refresh_token"
        ]
        if let clientSecret = configuration.clientSecret { form["client_secret"] = clientSecret }

        var request = URLRequest(url: configuration.tokenEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form.gmailFormURLEncodedData

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GmailIntegrationError.invalidServerResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw GmailIntegrationError.api(
                status: httpResponse.statusCode,
                message: GmailAPIErrorEnvelope.message(from: data)
            )
        }

        let refreshed = try JSONDecoder().decode(GmailRefreshTokenResponse.self, from: data)
        tokens.accessToken = refreshed.accessToken
        tokens.expiresAt = Date().addingTimeInterval(TimeInterval(refreshed.expiresIn))
        tokens.tokenType = refreshed.tokenType
        if let scope = refreshed.scope { tokens.scope = scope }
        try credentialStore.saveTokens(tokens)
        return tokens.accessToken
    }
}

struct GmailProfile: Decodable, Sendable {
    let emailAddress: String
    let messagesTotal: Int?
    let threadsTotal: Int?
    let historyId: String
}

struct GmailThreadListResponse: Decodable, Sendable {
    let threads: [GmailThreadReference]?
    let nextPageToken: String?
    let resultSizeEstimate: Int?
}

struct GmailThreadReference: Decodable, Sendable {
    let id: String
    let snippet: String?
    let historyId: String?
}

struct GmailThreadPayload: Decodable, Sendable {
    let id: String
    let historyId: String?
    let messages: [GmailMessagePayload]?
}

struct GmailMessagePayload: Decodable, Sendable {
    let id: String
    // Gmail partial responses omit fields that were not returned. Directory
    // indexing does not need this value, so keep metadata decoding resilient.
    let threadId: String?
    let labelIds: [String]?
    let snippet: String?
    let historyId: String?
    let internalDate: String?
    let payload: GmailMessagePart?
    let sizeEstimate: Int?
}

struct GmailMessagePart: Decodable, Sendable {
    let partId: String?
    let mimeType: String?
    let filename: String?
    let headers: [GmailMessageHeader]?
    let body: GmailMessagePartBody?
    let parts: [GmailMessagePart]?
}

struct GmailMessageHeader: Decodable, Sendable {
    let name: String
    let value: String
}

struct GmailMessagePartBody: Decodable, Sendable {
    let attachmentId: String?
    let size: Int?
    let data: String?
}

struct GmailAttachmentPayload: Decodable, Sendable {
    let attachmentId: String?
    let size: Int?
    let data: String?
}

struct GmailHistoryListResponse: Decodable, Sendable {
    let history: [GmailHistoryRecord]?
    let nextPageToken: String?
    let historyId: String?
}

struct GmailHistoryRecord: Decodable, Sendable {
    let id: String
    let messages: [GmailHistoryMessageReference]?
    let messagesAdded: [GmailHistoryMessageChange]?
    let messagesDeleted: [GmailHistoryMessageChange]?
    let labelsAdded: [GmailHistoryLabelChange]?
    let labelsRemoved: [GmailHistoryLabelChange]?

    var threadIDs: Set<String> {
        var ids = Set(messages?.map(\.threadId) ?? [])
        ids.formUnion(messagesAdded?.map(\.message.threadId) ?? [])
        ids.formUnion(messagesDeleted?.map(\.message.threadId) ?? [])
        ids.formUnion(labelsAdded?.map(\.message.threadId) ?? [])
        ids.formUnion(labelsRemoved?.map(\.message.threadId) ?? [])
        return ids
    }
}

struct GmailHistoryMessageReference: Decodable, Sendable {
    let id: String
    let threadId: String
}

struct GmailHistoryMessageChange: Decodable, Sendable {
    let message: GmailHistoryMessageReference
}

struct GmailHistoryLabelChange: Decodable, Sendable {
    let message: GmailHistoryMessageReference
    let labelIds: [String]?
}

struct GmailSendResponse: Decodable, Sendable {
    let id: String
    let threadId: String
    let labelIds: [String]?
}

private struct GmailModifyRequest: Encodable {
    let addLabelIds: [String]
    let removeLabelIds: [String]
}

private struct GmailThreadMutationResponse: Decodable, Sendable {
    let id: String
}

private struct GmailSendRequest: Encodable {
    let raw: String
    let threadId: String?
}

private struct GmailRefreshTokenResponse: Decodable {
    let accessToken: String
    let expiresIn: Int
    let scope: String?
    let tokenType: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case scope
        case tokenType = "token_type"
    }
}

struct GmailAPIErrorEnvelope: Decodable {
    struct ErrorDetail: Decodable {
        let reason: String?
    }

    struct APIError: Decodable {
        let code: Int?
        let message: String?
        let status: String?
        let errors: [ErrorDetail]?
    }

    let error: APIError?

    static func message(from data: Data) -> String {
        if let envelope = try? JSONDecoder().decode(Self.self, from: data),
           let error = envelope.error {
            return error.message ?? error.status ?? "Unknown Gmail error"
        }
        return String(data: data, encoding: .utf8) ?? "Unknown Gmail error"
    }

    static func isQuotaExceeded(in data: Data) -> Bool {
        guard let error = try? JSONDecoder().decode(Self.self, from: data).error else {
            return false
        }
        if error.status?.caseInsensitiveCompare("RESOURCE_EXHAUSTED") == .orderedSame {
            return true
        }
        if error.errors?.contains(where: {
            $0.reason?.localizedCaseInsensitiveContains("rateLimit") == true
                || $0.reason?.localizedCaseInsensitiveContains("quota") == true
        }) == true {
            return true
        }
        return error.message?.localizedCaseInsensitiveContains("quota exceeded") == true
    }
}

private extension Dictionary where Key == String, Value == String {
    var gmailFormURLEncodedData: Data {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let body = sorted { $0.key < $1.key }
            .map { key, value in
                let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(encodedKey)=\(encodedValue)"
            }
            .joined(separator: "&")
        return Data(body.utf8)
    }
}
