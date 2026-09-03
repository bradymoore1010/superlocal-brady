import AppKit
import CryptoKit
import Foundation
import Network
import Security

struct GmailOAuthCoordinator: Sendable {
    static let gmailScope = "https://www.googleapis.com/auth/gmail.modify"

    func authorize(using configuration: GmailOAuthConfiguration) async throws -> GmailTokenSet {
        let server = try OAuthLoopbackServer()
        let port = try await server.start()
        let redirectURI = "http://127.0.0.1:\(port)"
        let verifier = try Self.randomURLSafeString(byteCount: 48)
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let state = try Self.randomURLSafeString(byteCount: 32)

        var components = URLComponents(url: configuration.authorizationEndpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Self.gmailScope),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "include_granted_scopes", value: "true"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state)
        ]
        guard let authorizationURL = components?.url else {
            throw GmailIntegrationError.invalidOAuthConfiguration
        }

        let opened = await MainActor.run { NSWorkspace.shared.open(authorizationURL) }
        guard opened else {
            throw GmailIntegrationError.authorizationFailed("The Google authorization page could not be opened.")
        }

        let callbackURL = try await server.waitForCallback()
        let callback = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
        let values = Dictionary(uniqueKeysWithValues: (callback?.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        if let error = values["error"] {
            if error == "access_denied" { throw GmailIntegrationError.authorizationCancelled }
            throw GmailIntegrationError.authorizationFailed(values["error_description"] ?? error)
        }
        guard values["state"] == state else { throw GmailIntegrationError.stateMismatch }
        guard let code = values["code"], !code.isEmpty else {
            throw GmailIntegrationError.missingAuthorizationCode
        }

        var form: [String: String] = [
            "client_id": configuration.clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI
        ]
        if let clientSecret = configuration.clientSecret {
            form["client_secret"] = clientSecret
        }

        var request = URLRequest(url: configuration.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form.formURLEncodedData
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GmailIntegrationError.invalidServerResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw GmailIntegrationError.api(
                status: httpResponse.statusCode,
                message: OAuthErrorResponse.message(from: data)
            )
        }

        let token = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
        guard let refreshToken = token.refreshToken, !refreshToken.isEmpty else {
            throw GmailIntegrationError.missingRefreshToken
        }
        return GmailTokenSet(
            accessToken: token.accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(token.expiresIn)),
            tokenType: token.tokenType,
            scope: token.scope,
            accountEmail: nil
        )
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func randomURLSafeString(byteCount: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        guard status == errSecSuccess else { throw GmailIntegrationError.keychain(status) }
        return base64URL(Data(bytes))
    }
}

private final class OAuthLoopbackServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.brady.keyboardfirstmail.oauth-loopback", qos: .userInitiated)
    private let lock = NSLock()
    private var startContinuation: CheckedContinuation<UInt16, Error>?
    private var callbackContinuation: CheckedContinuation<URL, Error>?
    private var callbackResult: Result<URL, Error>?
    private var didStart = false

    init() throws {
        listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { [weak self] connection in
            self?.receiveRequest(on: connection, accumulated: Data())
        }
        listener.stateUpdateHandler = { [weak self] state in
            self?.handle(state)
        }
    }

    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                startContinuation = continuation
                if !didStart {
                    didStart = true
                    listener.start(queue: queue)
                }
            }
        }
    }

    func waitForCallback() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let immediate: Result<URL, Error>? = lock.withLock {
                if let callbackResult { return callbackResult }
                callbackContinuation = continuation
                return nil
            }
            if let immediate { continuation.resume(with: immediate) }
        }
    }

    private func handle(_ state: NWListener.State) {
        switch state {
        case .ready:
            guard let port = listener.port?.rawValue else {
                finish(.failure(GmailIntegrationError.authorizationFailed("The local OAuth callback could not start.")))
                return
            }
            let continuation: CheckedContinuation<UInt16, Error>? = lock.withLock {
                defer { startContinuation = nil }
                return startContinuation
            }
            continuation?.resume(returning: port)
        case let .failed(error):
            let integrationError = GmailIntegrationError.authorizationFailed(error.localizedDescription)
            let start: CheckedContinuation<UInt16, Error>? = lock.withLock {
                defer { startContinuation = nil }
                return startContinuation
            }
            start?.resume(throwing: integrationError)
            finish(.failure(integrationError))
        case .cancelled:
            break
        default:
            break
        }
    }

    private func receiveRequest(on connection: NWConnection, accumulated: Data) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 32_768) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var requestData = accumulated
            if let data { requestData.append(data) }

            if requestData.range(of: Data("\r\n\r\n".utf8)) != nil || isComplete {
                self.handleRequest(requestData, on: connection)
            } else if let error {
                connection.cancel()
                self.finish(.failure(GmailIntegrationError.authorizationFailed(error.localizedDescription)))
            } else {
                self.receiveRequest(on: connection, accumulated: requestData)
            }
        }
    }

    private func handleRequest(_ data: Data, on connection: NWConnection) {
        let requestText = String(decoding: data, as: UTF8.self)
        let firstLine = requestText.components(separatedBy: "\r\n").first ?? ""
        let fields = firstLine.split(separator: " ")
        let target = fields.count >= 2 ? String(fields[1]) : ""
        let callbackURL = URL(string: "http://127.0.0.1\(target)")

        let success = callbackURL != nil
        let title = success ? "Mail is connected" : "Mail could not connect"
        let detail = success ? "You can close this window and return to Mail." : "Return to Mail and try again."
        let html = """
            <!doctype html><meta charset="utf-8"><title>\(title)</title>
            <style>body{font:15px -apple-system,BlinkMacSystemFont,sans-serif;margin:72px;color:#171717}main{max-width:480px}h1{font-size:24px;font-weight:600}p{color:#666;line-height:1.5}</style>
            <main><h1>\(title)</h1><p>\(detail)</p></main>
            """
        let response = """
            HTTP/1.1 \(success ? "200 OK" : "400 Bad Request")\r
            Content-Type: text/html; charset=utf-8\r
            Content-Length: \(html.utf8.count)\r
            Connection: close\r
            Cache-Control: no-store\r
            \r
            \(html)
            """
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })

        if let callbackURL { finish(.success(callbackURL)) }
        else { finish(.failure(GmailIntegrationError.invalidServerResponse)) }
    }

    private func finish(_ result: Result<URL, Error>) {
        let continuation: CheckedContinuation<URL, Error>? = lock.withLock {
            guard callbackResult == nil else { return nil }
            callbackResult = result
            defer { callbackContinuation = nil }
            return callbackContinuation
        }
        continuation?.resume(with: result)
        listener.cancel()
    }
}

private struct OAuthTokenResponse: Decodable {
    let accessToken: String
    let expiresIn: Int
    let refreshToken: String?
    let scope: String?
    let tokenType: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
        case tokenType = "token_type"
    }
}

private struct OAuthErrorResponse: Decodable {
    let error: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }

    static func message(from data: Data) -> String {
        guard let response = try? JSONDecoder().decode(Self.self, from: data) else {
            return String(data: data, encoding: .utf8) ?? "Unknown OAuth error"
        }
        return response.errorDescription ?? response.error ?? "Unknown OAuth error"
    }
}

private extension Dictionary where Key == String, Value == String {
    var formURLEncodedData: Data {
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

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
