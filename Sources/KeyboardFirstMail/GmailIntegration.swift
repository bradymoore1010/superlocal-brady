import Foundation

actor GmailIntegration {
    typealias ProgressHandler = @Sendable (_ completed: Int, _ total: Int) async -> Void

    private let credentialStore: GmailCredentialStore
    private let databaseURL: URL
    private var repository: SQLiteMailRepository?
    private var repositoryError: Error?
    private let oauthCoordinator = GmailOAuthCoordinator()
    private var client: GmailAPIClient?
    private var accountEmail: String?
    private var historyID: String?

    init(credentialStore: GmailCredentialStore = .shared) {
        self.credentialStore = credentialStore
        databaseURL = credentialStore.databaseURL
    }

    private func prepareRepository() {
        guard repository == nil, repositoryError == nil else { return }
        do {
            repository = try SQLiteMailRepository(databaseURL: databaseURL)
        } catch {
            repositoryError = error
        }
    }

    func bootstrap() async -> GmailBootstrapState {
        // SQLite opens and schema checks can touch the filesystem. Perform
        // them on this actor instead of synchronously during MailStore init so
        // the first window can be constructed immediately.
        prepareRepository()
        let configuration: GmailOAuthConfiguration?
        let cache: GmailCachedMailbox?
        let recipientDirectory: GmailRecipientDirectorySnapshot?
        do { configuration = try credentialStore.loadConfiguration() }
        catch { configuration = nil }
        do { cache = try await repository?.loadMailbox() }
        catch { cache = nil }
        accountEmail = cache?.accountEmail
        historyID = cache?.historyID
        do { recipientDirectory = try await repository?.loadRecipientDirectory(accountEmail: accountEmail) }
        catch { recipientDirectory = nil }

        return GmailBootstrapState(
            hasConfiguration: configuration != nil,
            cache: cache,
            recipientDirectory: recipientDirectory
        )
    }

    func restoreStoredCredentials() -> Bool {
        let configuration: GmailOAuthConfiguration?
        let tokens: GmailTokenSet?
        do { configuration = try credentialStore.loadConfiguration() }
        catch { configuration = nil }
        do { tokens = try credentialStore.loadTokens() }
        catch { tokens = nil }
        guard let configuration, let tokens else {
            client = nil
            return false
        }
        client = GmailAPIClient(
            configuration: configuration,
            tokens: tokens,
            credentialStore: credentialStore
        )
        if accountEmail == nil { accountEmail = tokens.accountEmail }
        return true
    }

    @discardableResult
    func importConfiguration(from url: URL) throws -> GmailOAuthConfiguration {
        try credentialStore.importConfiguration(from: url)
    }

    func connect(progress: @escaping ProgressHandler) async throws -> GmailCachedMailbox {
        prepareRepository()
        guard let configuration = try credentialStore.loadConfiguration() else {
            throw GmailIntegrationError.missingOAuthConfiguration
        }

        var tokens = try await oauthCoordinator.authorize(using: configuration)
        let authorizationClient = GmailAPIClient(
            configuration: configuration,
            tokens: tokens,
            credentialStore: credentialStore
        )
        let profile = try await authorizationClient.profile()
        tokens.accountEmail = profile.emailAddress
        try credentialStore.saveTokens(tokens)
        client = GmailAPIClient(
            configuration: configuration,
            tokens: tokens,
            credentialStore: credentialStore
        )
        accountEmail = profile.emailAddress
        historyID = profile.historyId
        return try await fullSync(profile: profile, progress: progress)
    }

    func sync(progress: @escaping ProgressHandler) async throws -> GmailCachedMailbox {
        prepareRepository()
        let client = try configuredClient()
        let profile = try await client.profile()
        accountEmail = profile.emailAddress

        if let historyID, let repository,
           let cached = try await repository.loadMailbox(), !cached.threads.isEmpty {
            if cached.contentVersion < GmailCachedMailbox.currentContentVersion {
                return try await fullSync(profile: profile, progress: progress)
            }
            do {
                return try await incrementalSync(
                    client: client,
                    cached: cached,
                    startingHistoryID: historyID,
                    fallbackProfile: profile,
                    progress: progress
                )
            } catch let GmailIntegrationError.api(status, _) where status == 404 {
                return try await fullSync(profile: profile, progress: progress)
            }
        }
        return try await fullSync(profile: profile, progress: progress)
    }

    func searchGmail(_ query: String, limit: Int = 20) async throws -> [MailThread] {
        prepareRepository()
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty else { return [] }
        let client = try configuredClient()
        let profile = try await client.profile()
        let response = try await client.listThreads(maxResults: limit, query: cleanQuery)
        let ids = response.threads?.map(\.id) ?? []
        let payloads = try await fetchThreads(ids: ids, client: client, progress: { _, _ in })
        let threads = payloads.compactMap {
            GmailMessageParser.mailThread(from: $0, accountEmail: profile.emailAddress)
        }
        if let repository {
            try await repository.mergeMailbox(
                threads: threads,
                accountEmail: profile.emailAddress,
                historyID: historyID,
                syncedAt: Date()
            )
        }
        return threads
    }

    func syncRecipientDirectory(
        progress: @escaping ProgressHandler
    ) async throws -> GmailRecipientDirectorySnapshot {
        prepareRepository()
        let client = try configuredClient()
        let profile = try await client.profile()
        var threadIDs: [String] = []
        var nextPageToken: String?

        repeat {
            try Task.checkCancellation()
            let response = try await client.listThreads(
                pageToken: nextPageToken,
                maxResults: 500,
                query: "in:sent"
            )
            threadIDs.append(contentsOf: response.threads?.map(\.id) ?? [])
            nextPageToken = response.nextPageToken
        } while nextPageToken != nil

        var builder = GmailRecipientDirectoryBuilder(accountEmail: profile.emailAddress)
        await progress(0, threadIDs.count)
        try await withThrowingTaskGroup(of: GmailThreadPayload?.self) { group in
            var iterator = threadIDs.makeIterator()
            let concurrency = min(4, threadIDs.count)
            for _ in 0..<concurrency {
                guard let id = iterator.next() else { break }
                addRecipientDirectoryTask(id: id, client: client, to: &group)
            }

            var completed = 0
            while let payload = try await group.next() {
                try Task.checkCancellation()
                if let payload { builder.record(payload) }
                completed += 1
                await progress(completed, threadIDs.count)
                if let id = iterator.next() {
                    addRecipientDirectoryTask(id: id, client: client, to: &group)
                }
            }
        }

        let syncedAt = Date()
        let entries = builder.entries.sorted {
            $0.email.localizedCaseInsensitiveCompare($1.email) == .orderedAscending
        }
        try await repository?.replaceRecipientDirectory(
            entries,
            accountEmail: profile.emailAddress,
            syncedAt: syncedAt
        )
        accountEmail = profile.emailAddress
        return GmailRecipientDirectorySnapshot(entries: entries, syncedAt: syncedAt)
    }

    func searchCachedMail(_ query: String, limit: Int = 100) async throws -> [MailThread] {
        prepareRepository()
        guard let repository else {
            if let repositoryError { throw repositoryError }
            return []
        }
        return try await repository.cachedThreads(matching: query, limit: limit)
    }

    func searchCachedMailIDs(_ query: String, limit: Int = 100) async throws -> [String] {
        prepareRepository()
        guard let repository else {
            if let repositoryError { throw repositoryError }
            return []
        }
        return try await repository.cachedThreadIDs(matching: query, limit: limit)
    }

    func cachedThread(id: String) async throws -> MailThread? {
        prepareRepository()
        guard let repository else {
            if let repositoryError { throw repositoryError }
            return nil
        }
        return try await repository.cachedThread(id: id)
    }

    func fetchThread(id: String, includeInlineContent: Bool = false) async throws -> MailThread {
        let client = try configuredClient()
        let profile = try await client.profile()
        let fetchedPayload = try await client.thread(id: id)
        let payload = includeInlineContent
            ? await hydrateInlineAttachments(in: fetchedPayload, client: client)
            : fetchedPayload
        guard let thread = GmailMessageParser.mailThread(from: payload, accountEmail: profile.emailAddress) else {
            throw GmailIntegrationError.invalidServerResponse
        }
        accountEmail = profile.emailAddress
        if let repository {
            try await repository.mergeMailbox(
                threads: [thread],
                accountEmail: profile.emailAddress,
                historyID: historyID,
                syncedAt: Date()
            )
        }
        return thread
    }

    private struct InlineAttachmentReference: Hashable, Sendable {
        let messageID: String
        let attachmentID: String
    }

    private func hydrateInlineAttachments(
        in thread: GmailThreadPayload,
        client: GmailAPIClient
    ) async -> GmailThreadPayload {
        let references = Set((thread.messages ?? []).flatMap { message in
            inlineAttachmentReferences(in: message.payload, messageID: message.id)
        })
        guard !references.isEmpty else { return thread }

        let encodedDataByReference = await withTaskGroup(
            of: (InlineAttachmentReference, String?).self,
            returning: [InlineAttachmentReference: String].self
        ) { group in
            var iterator = Array(references).makeIterator()
            let concurrency = min(6, references.count)
            for _ in 0..<concurrency {
                guard let reference = iterator.next() else { break }
                addInlineAttachmentTask(reference, client: client, to: &group)
            }

            var values: [InlineAttachmentReference: String] = [:]
            while let (reference, data) = await group.next() {
                if let data { values[reference] = data }
                if let next = iterator.next() {
                    addInlineAttachmentTask(next, client: client, to: &group)
                }
            }
            return values
        }
        guard !encodedDataByReference.isEmpty else { return thread }

        let messages = thread.messages?.map { message in
            GmailMessagePayload(
                id: message.id,
                threadId: message.threadId,
                labelIds: message.labelIds,
                snippet: message.snippet,
                historyId: message.historyId,
                internalDate: message.internalDate,
                payload: hydrate(
                    part: message.payload,
                    messageID: message.id,
                    encodedDataByReference: encodedDataByReference
                ),
                sizeEstimate: message.sizeEstimate
            )
        }
        return GmailThreadPayload(id: thread.id, historyId: thread.historyId, messages: messages)
    }

    private func addInlineAttachmentTask(
        _ reference: InlineAttachmentReference,
        client: GmailAPIClient,
        to group: inout TaskGroup<(InlineAttachmentReference, String?)>
    ) {
        group.addTask {
            let payload = try? await client.attachment(
                messageID: reference.messageID,
                attachmentID: reference.attachmentID
            )
            return (reference, payload?.data)
        }
    }

    private func inlineAttachmentReferences(
        in part: GmailMessagePart?,
        messageID: String
    ) -> [InlineAttachmentReference] {
        guard let part else { return [] }
        var references: [InlineAttachmentReference] = []
        let isInlineImage = part.mimeType?.lowercased().hasPrefix("image/") == true
            && part.headers?.contains(where: { header in
                let name = header.name.lowercased()
                return name == "content-id" || name == "x-attachment-id"
            }) == true
        if isInlineImage,
           part.body?.data == nil,
           let attachmentID = part.body?.attachmentId,
           !attachmentID.isEmpty {
            references.append(
                InlineAttachmentReference(messageID: messageID, attachmentID: attachmentID)
            )
        }
        for child in part.parts ?? [] {
            references.append(contentsOf: inlineAttachmentReferences(in: child, messageID: messageID))
        }
        return references
    }

    private func hydrate(
        part: GmailMessagePart?,
        messageID: String,
        encodedDataByReference: [InlineAttachmentReference: String]
    ) -> GmailMessagePart? {
        guard let part else { return nil }
        let hydratedBody: GmailMessagePartBody?
        if let attachmentID = part.body?.attachmentId,
           let encodedData = encodedDataByReference[
               InlineAttachmentReference(messageID: messageID, attachmentID: attachmentID)
           ] {
            hydratedBody = GmailMessagePartBody(
                attachmentId: attachmentID,
                size: part.body?.size,
                data: encodedData
            )
        } else {
            hydratedBody = part.body
        }

        return GmailMessagePart(
            partId: part.partId,
            mimeType: part.mimeType,
            filename: part.filename,
            headers: part.headers,
            body: hydratedBody,
            parts: part.parts?.compactMap {
                hydrate(part: $0, messageID: messageID, encodedDataByReference: encodedDataByReference)
            }
        )
    }

    func archive(threadID: String) async throws {
        try await configuredClient().modifyThread(id: threadID, add: [], remove: ["INBOX"])
    }

    func setStarred(_ starred: Bool, threadID: String) async throws {
        try await configuredClient().modifyThread(
            id: threadID,
            add: starred ? ["STARRED"] : [],
            remove: starred ? [] : ["STARRED"]
        )
    }

    func setUnread(_ unread: Bool, threadID: String) async throws {
        try await configuredClient().modifyThread(
            id: threadID,
            add: unread ? ["UNREAD"] : [],
            remove: unread ? [] : ["UNREAD"]
        )
    }

    func unsubscribeOneClick(at url: URL) async throws {
        guard MailUnsubscribeParser.isSafeOneClickURL(url) else {
            throw GmailIntegrationError.unsubscribe("The sender provided an unsafe unsubscribe address.")
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let redirectBlocker = UnsubscribeRedirectBlocker()
        let session = URLSession(configuration: configuration, delegate: redirectBlocker, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.httpShouldHandleCookies = false
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("List-Unsubscribe=One-Click".utf8)

        let (_, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw GmailIntegrationError.invalidServerResponse
        }
        guard (200..<400).contains(response.statusCode) else {
            throw GmailIntegrationError.unsubscribe("The sender returned status \(response.statusCode).")
        }
    }

    @discardableResult
    func send(draft: GmailOutgoingDraft, threadID: String? = nil) async throws -> GmailSendResponse {
        let raw = try GmailMIMEBuilder.rawMessage(from: draft)
        return try await configuredClient().send(raw: raw, threadID: threadID)
    }

    func persistLocalThreadState(_ thread: MailThread) async throws {
        prepareRepository()
        try await repository?.updateThreadState(thread)
    }

    private func configuredClient() throws -> GmailAPIClient {
        if let client { return client }
        guard let configuration = try credentialStore.loadConfiguration() else {
            throw GmailIntegrationError.missingOAuthConfiguration
        }
        guard let tokens = try credentialStore.loadTokens() else {
            throw GmailIntegrationError.authorizationCancelled
        }
        let newClient = GmailAPIClient(
            configuration: configuration,
            tokens: tokens,
            credentialStore: credentialStore
        )
        client = newClient
        accountEmail = tokens.accountEmail
        return newClient
    }

    private func fullSync(
        profile: GmailProfile,
        progress: @escaping ProgressHandler
    ) async throws -> GmailCachedMailbox {
        guard let repository else {
            throw repositoryError ?? GmailIntegrationError.cache("Repository unavailable")
        }
        let client = try configuredClient()
        var references: [GmailThreadReference] = []
        var nextPageToken: String?
        let maximumThreads = 300

        repeat {
            let remaining = maximumThreads - references.count
            guard remaining > 0 else { break }
            let response = try await client.listThreads(
                pageToken: nextPageToken,
                maxResults: min(100, remaining)
            )
            references.append(contentsOf: response.threads ?? [])
            nextPageToken = response.nextPageToken
        } while nextPageToken != nil && references.count < maximumThreads

        await progress(0, references.count)
        let payloads = try await fetchThreads(
            ids: references.map(\.id),
            client: client,
            progress: progress
        )
        let threads = payloads
            .compactMap { GmailMessageParser.mailThread(from: $0, accountEmail: profile.emailAddress) }
            .sorted { $0.date > $1.date }
        let syncedAt = Date()
        historyID = profile.historyId
        accountEmail = profile.emailAddress
        try await repository.replaceMailbox(
            threads: threads,
            accountEmail: profile.emailAddress,
            historyID: profile.historyId,
            syncedAt: syncedAt
        )
        return GmailCachedMailbox(
            threads: threads,
            accountEmail: profile.emailAddress,
            historyID: profile.historyId,
            syncedAt: syncedAt
        )
    }

    private func incrementalSync(
        client: GmailAPIClient,
        cached: GmailCachedMailbox,
        startingHistoryID: String,
        fallbackProfile: GmailProfile,
        progress: @escaping ProgressHandler
    ) async throws -> GmailCachedMailbox {
        var changedThreadIDs = Set<String>()
        var nextPageToken: String?
        var newestHistoryID = startingHistoryID

        repeat {
            let response = try await client.history(startingAt: startingHistoryID, pageToken: nextPageToken)
            for record in response.history ?? [] { changedThreadIDs.formUnion(record.threadIDs) }
            if let responseHistoryID = response.historyId { newestHistoryID = responseHistoryID }
            nextPageToken = response.nextPageToken
        } while nextPageToken != nil

        guard !changedThreadIDs.isEmpty else {
            let syncedAt = Date()
            historyID = newestHistoryID
            // loadMailbox intentionally returns lightweight summaries. Only
            // advance metadata here; replacing the mailbox would erase every
            // cached message body when Gmail has no new history records.
            try await repository?.updateSyncMetadata(
                accountEmail: fallbackProfile.emailAddress,
                historyID: newestHistoryID,
                syncedAt: syncedAt
            )
            return GmailCachedMailbox(
                threads: cached.threads,
                accountEmail: fallbackProfile.emailAddress,
                historyID: newestHistoryID,
                syncedAt: syncedAt
            )
        }

        let ids = Array(changedThreadIDs)
        await progress(0, ids.count)
        let results = await fetchChangedThreads(ids: ids, client: client, progress: progress)
        var byID = Dictionary(uniqueKeysWithValues: cached.threads.map { ($0.id, $0) })
        var removedIDs = Set<String>()
        for result in results {
            switch result {
            case let .success(payload):
                if let thread = GmailMessageParser.mailThread(from: payload, accountEmail: fallbackProfile.emailAddress) {
                    byID[thread.id] = thread
                }
            case let .removed(id):
                byID[id] = nil
                removedIDs.insert(id)
            case .failed:
                break
            }
        }

        let threads = byID.values.sorted { $0.date > $1.date }
        let syncedAt = Date()
        historyID = newestHistoryID
        try await repository?.mergeMailbox(
            threads: results.compactMap { result in
                guard case let .success(payload) = result else { return nil }
                return GmailMessageParser.mailThread(from: payload, accountEmail: fallbackProfile.emailAddress)
            },
            removedThreadIDs: removedIDs,
            accountEmail: fallbackProfile.emailAddress,
            historyID: newestHistoryID,
            syncedAt: syncedAt
        )
        return GmailCachedMailbox(
            threads: threads,
            accountEmail: fallbackProfile.emailAddress,
            historyID: newestHistoryID,
            syncedAt: syncedAt
        )
    }

    private func fetchThreads(
        ids: [String],
        client: GmailAPIClient,
        progress: @escaping ProgressHandler
    ) async throws -> [GmailThreadPayload] {
        try await withThrowingTaskGroup(of: GmailThreadPayload.self) { group in
            var iterator = ids.makeIterator()
            let concurrency = min(8, ids.count)
            for _ in 0..<concurrency {
                if let id = iterator.next() { group.addTask { try await client.thread(id: id) } }
            }

            var payloads: [GmailThreadPayload] = []
            payloads.reserveCapacity(ids.count)
            while let payload = try await group.next() {
                payloads.append(payload)
                await progress(payloads.count, ids.count)
                if let id = iterator.next() { group.addTask { try await client.thread(id: id) } }
            }
            return payloads
        }
    }

    private enum ChangedThreadResult: Sendable {
        case success(GmailThreadPayload)
        case removed(String)
        case failed(String)
    }

    private func fetchChangedThreads(
        ids: [String],
        client: GmailAPIClient,
        progress: @escaping ProgressHandler
    ) async -> [ChangedThreadResult] {
        await withTaskGroup(of: ChangedThreadResult.self) { group in
            var iterator = ids.makeIterator()
            let concurrency = min(8, ids.count)
            for _ in 0..<concurrency {
                if let id = iterator.next() { addChangedThreadTask(id: id, client: client, to: &group) }
            }

            var results: [ChangedThreadResult] = []
            while let result = await group.next() {
                results.append(result)
                await progress(results.count, ids.count)
                if let id = iterator.next() { addChangedThreadTask(id: id, client: client, to: &group) }
            }
            return results
        }
    }

    private func addChangedThreadTask(
        id: String,
        client: GmailAPIClient,
        to group: inout TaskGroup<ChangedThreadResult>
    ) {
        group.addTask {
            do {
                return .success(try await client.thread(id: id))
            } catch let GmailIntegrationError.api(status, _) where status == 404 {
                return .removed(id)
            } catch {
                return .failed(id)
            }
        }
    }

    private func addRecipientDirectoryTask(
        id: String,
        client: GmailAPIClient,
        to group: inout ThrowingTaskGroup<GmailThreadPayload?, Error>
    ) {
        group.addTask {
            do {
                return try await client.threadMetadata(id: id)
            } catch let GmailIntegrationError.api(status, _) where status == 404 {
                return nil
            }
        }
    }
}

private final class UnsubscribeRedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
