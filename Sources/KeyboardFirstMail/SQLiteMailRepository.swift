import Foundation
import SQLite3

actor SQLiteMailRepository {
    // SQLite is opened in FULLMUTEX mode and every query is actor-isolated. The
    // unsafe annotation only lets deinit close the opaque C handle.
    nonisolated(unsafe) private var database: OpaquePointer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private static let summarySeparator: Character = "\u{1F}"

    init(databaseURL: URL) throws {
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &handle, flags, nil) == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite error"
            if let handle { sqlite3_close(handle) }
            throw GmailIntegrationError.cache(message)
        }
        database = handle

        do {
            try Self.execute("PRAGMA journal_mode=WAL", on: handle)
            try Self.execute("PRAGMA synchronous=NORMAL", on: handle)
            try Self.execute("PRAGMA foreign_keys=ON", on: handle)
            try Self.execute(
                """
                CREATE TABLE IF NOT EXISTS mail_threads (
                    id TEXT PRIMARY KEY NOT NULL,
                    date REAL NOT NULL,
                    json BLOB NOT NULL,
                    summary_json BLOB
                )
                """,
                on: handle
            )
            // Existing installations gain the lightweight summary column in
            // place. Duplicate-column errors mean the migration already ran.
            try? Self.execute("ALTER TABLE mail_threads ADD COLUMN summary_json BLOB", on: handle)
            try Self.execute(
                """
                CREATE VIRTUAL TABLE IF NOT EXISTS mail_search USING fts5(
                    thread_id UNINDEXED,
                    sender,
                    email,
                    subject,
                    preview,
                    body,
                    attachments,
                    tokenize='unicode61 remove_diacritics 2'
                )
                """,
                on: handle
            )
            try Self.execute(
                """
                CREATE TABLE IF NOT EXISTS mail_thread_summaries (
                    thread_id TEXT PRIMARY KEY NOT NULL,
                    date REAL NOT NULL,
                    sender TEXT NOT NULL,
                    email TEXT NOT NULL,
                    subject TEXT NOT NULL,
                    preview TEXT NOT NULL,
                    display_date TEXT NOT NULL,
                    is_unread INTEGER NOT NULL,
                    is_starred INTEGER NOT NULL,
                    has_attachment INTEGER NOT NULL,
                    folder TEXT NOT NULL,
                    labels TEXT NOT NULL,
                    gmail_label_ids TEXT NOT NULL,
                    FOREIGN KEY(thread_id) REFERENCES mail_threads(id) ON DELETE CASCADE
                )
                """,
                on: handle
            )
            try Self.execute(
                """
                CREATE TABLE IF NOT EXISTS mail_metadata (
                    key TEXT PRIMARY KEY NOT NULL,
                    value TEXT NOT NULL
                )
                """,
                on: handle
            )
        } catch {
            sqlite3_close(handle)
            database = nil
            throw error
        }
    }

    deinit {
        if let database { sqlite3_close(database) }
    }

    func loadMailbox() async throws -> GmailCachedMailbox? {
        let threads = try await loadThreads()
        guard let accountEmail = try metadata(for: "account_email"), !accountEmail.isEmpty else {
            return nil
        }
        let historyID = try metadata(for: "history_id")
        let syncedAt = try metadata(for: "synced_at").flatMap(Double.init).map(Date.init(timeIntervalSince1970:))
        let contentVersion = try metadata(for: "content_version").flatMap(Int.init) ?? 0
        return GmailCachedMailbox(
            threads: threads,
            accountEmail: accountEmail,
            historyID: historyID,
            syncedAt: syncedAt,
            contentVersion: contentVersion
        )
    }

    func replaceMailbox(
        threads: [MailThread],
        accountEmail: String,
        historyID: String?,
        syncedAt: Date
    ) throws {
        try transaction {
            try execute("DELETE FROM mail_thread_summaries")
            try execute("DELETE FROM mail_threads")
            try execute("DELETE FROM mail_search")
            for thread in threads {
                try insert(thread)
            }
            try setMetadata(accountEmail, for: "account_email")
            if let historyID { try setMetadata(historyID, for: "history_id") }
            else { try deleteMetadata(for: "history_id") }
            try setMetadata(String(syncedAt.timeIntervalSince1970), for: "synced_at")
            try setMetadata(String(GmailCachedMailbox.currentContentVersion), for: "content_version")
        }
    }

    func mergeMailbox(
        threads: [MailThread],
        removedThreadIDs: Set<String> = [],
        accountEmail: String,
        historyID: String?,
        syncedAt: Date
    ) throws {
        try transaction {
            for threadID in removedThreadIDs {
                try deleteThread(id: threadID)
            }
            for thread in threads {
                try deleteThread(id: thread.id)
                try insert(thread)
            }
            try setMetadata(accountEmail, for: "account_email")
            if let historyID { try setMetadata(historyID, for: "history_id") }
            try setMetadata(String(syncedAt.timeIntervalSince1970), for: "synced_at")
            try setMetadata(String(GmailCachedMailbox.currentContentVersion), for: "content_version")
        }
    }

    func updateThreadState(_ thread: MailThread) throws {
        var persistedThread = thread
        if persistedThread.messages.isEmpty,
           let cachedThread = try cachedThread(id: thread.id),
           !cachedThread.messages.isEmpty {
            // MailStore intentionally keeps lightweight list summaries in
            // memory. Local read/star/archive changes must not replace the
            // cached Gmail payload that owns the actual message bodies.
            persistedThread.messages = cachedThread.messages
        }

        try transaction {
            try deleteThread(id: persistedThread.id)
            try insert(persistedThread)
        }
    }

    func updateSyncMetadata(
        accountEmail: String,
        historyID: String?,
        syncedAt: Date
    ) throws {
        try transaction {
            try setMetadata(accountEmail, for: "account_email")
            if let historyID { try setMetadata(historyID, for: "history_id") }
            else { try deleteMetadata(for: "history_id") }
            try setMetadata(String(syncedAt.timeIntervalSince1970), for: "synced_at")
            try setMetadata(String(GmailCachedMailbox.currentContentVersion), for: "content_version")
        }
    }

    func loadRecipientDirectory(accountEmail: String?) throws -> GmailRecipientDirectorySnapshot? {
        guard let accountEmail,
              let storedAccount = try metadata(for: "recipient_directory_account"),
              storedAccount.caseInsensitiveCompare(accountEmail) == .orderedSame else { return nil }
        guard try tableExists("mail_recipient_directory") else { return nil }

        let statement = try prepare(
            """
            SELECT email, name, interaction_count, was_previously_emailed, last_interaction
            FROM mail_recipient_directory
            """
        )
        defer { sqlite3_finalize(statement) }
        var entries: [RecipientSuggestion] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let email = string(at: 0, in: statement),
                  let name = string(at: 1, in: statement) else { continue }
            entries.append(
                RecipientSuggestion(
                    name: name,
                    email: email,
                    interactionCount: Int(sqlite3_column_int64(statement, 2)),
                    wasPreviouslyEmailed: sqlite3_column_int(statement, 3) != 0,
                    lastInteraction: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))
                )
            )
        }
        let syncedAt = try metadata(for: "recipient_directory_synced_at")
            .flatMap(Double.init)
            .map(Date.init(timeIntervalSince1970:))
        return GmailRecipientDirectorySnapshot(entries: entries, syncedAt: syncedAt)
    }

    func replaceRecipientDirectory(
        _ entries: [RecipientSuggestion],
        accountEmail: String,
        syncedAt: Date
    ) throws {
        // The directory is supplemental autocomplete data. Create its table on
        // first directory sync so Gmail cache startup keeps its previous cost.
        try execute(
            """
            CREATE TABLE IF NOT EXISTS mail_recipient_directory (
                email_key TEXT PRIMARY KEY NOT NULL,
                email TEXT NOT NULL,
                name TEXT NOT NULL,
                interaction_count INTEGER NOT NULL,
                was_previously_emailed INTEGER NOT NULL,
                last_interaction REAL NOT NULL
            )
            """
        )
        try transaction {
            try execute("DELETE FROM mail_recipient_directory")
            let statement = try prepare(
                """
                INSERT INTO mail_recipient_directory(
                    email_key, email, name, interaction_count,
                    was_previously_emailed, last_interaction
                ) VALUES (?, ?, ?, ?, ?, ?)
                """
            )
            defer { sqlite3_finalize(statement) }

            for entry in entries {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                try bind(entry.id, at: 1, in: statement)
                try bind(entry.email, at: 2, in: statement)
                try bind(entry.name, at: 3, in: statement)
                sqlite3_bind_int64(statement, 4, Int64(max(1, entry.interactionCount)))
                sqlite3_bind_int(statement, 5, entry.wasPreviouslyEmailed ? 1 : 0)
                sqlite3_bind_double(statement, 6, entry.lastInteraction.timeIntervalSince1970)
                try stepDone(statement)
            }

            try setMetadata(accountEmail, for: "recipient_directory_account")
            try setMetadata(
                String(syncedAt.timeIntervalSince1970),
                for: "recipient_directory_synced_at"
            )
        }
    }

    func cachedThreads(matching rawQuery: String, limit: Int = 100) async throws -> [MailThread] {
        let ids = try cachedThreadIDs(matching: rawQuery, limit: limit)
        var threads: [MailThread] = []
        threads.reserveCapacity(ids.count)
        for id in ids {
            if let summary = try loadSummary(id: id) {
                threads.append(summary)
            } else if let fullThread = try cachedThread(id: id) {
                threads.append(fullThread.listSummary)
            }
        }
        return threads
    }

    func cachedThreadIDs(matching rawQuery: String, limit: Int = 100) throws -> [String] {
        let terms = rawQuery
            .split(whereSeparator: { $0.isWhitespace })
            .map { String($0).replacingOccurrences(of: "\"", with: "\"\"") }
            .filter { !$0.isEmpty }
        guard !terms.isEmpty else { return [] }

        let match = terms.map { "\"\($0)\"*" }.joined(separator: " AND ")
        let sql = """
            SELECT s.thread_id
            FROM mail_search s
            LEFT JOIN mail_thread_summaries m ON m.thread_id = s.thread_id
            WHERE mail_search MATCH ?
            ORDER BY bm25(mail_search), m.date DESC
            LIMIT ?
            """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(match, at: 1, in: statement)
        sqlite3_bind_int(statement, 2, Int32(max(1, limit)))

        var ids: [String] = []
        ids.reserveCapacity(max(1, limit))
        while sqlite3_step(statement) == SQLITE_ROW {
            if let id = string(at: 0, in: statement) { ids.append(id) }
        }
        return ids
    }

    private func loadThreads() async throws -> [MailThread] {
        if let summaries = try loadAllSummaries() {
            return summaries
        }
        let statement = try prepare("SELECT COALESCE(summary_json, json) FROM mail_threads ORDER BY date DESC")
        defer { sqlite3_finalize(statement) }

        var threads: [MailThread] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let bytes = sqlite3_column_blob(statement, 0) else { continue }
            let length = Int(sqlite3_column_bytes(statement, 0))
            let data = Data(bytes: bytes, count: length)
            if let thread = try? decoder.decode(MailThread.self, from: data) {
                threads.append(thread)
            }
        }
        for thread in threads {
            try? insertSummary(thread.listSummary)
        }
        return threads
    }

    private func loadAllSummaries() throws -> [MailThread]? {
        let expected = try rowCount(in: "mail_threads")
        guard expected > 0 else { return [] }
        let statement = try prepare(
            """
            SELECT thread_id, date, sender, email, subject, preview, display_date,
                   is_unread, is_starred, has_attachment, folder, labels, gmail_label_ids
            FROM mail_thread_summaries
            ORDER BY date DESC
            """
        )
        defer { sqlite3_finalize(statement) }
        var summaries: [MailThread] = []
        summaries.reserveCapacity(expected)
        while sqlite3_step(statement) == SQLITE_ROW {
            if let summary = summary(from: statement) { summaries.append(summary) }
        }
        return summaries.count == expected ? summaries : nil
    }

    private func loadSummary(id: String) throws -> MailThread? {
        let statement = try prepare(
            """
            SELECT thread_id, date, sender, email, subject, preview, display_date,
                   is_unread, is_starred, has_attachment, folder, labels, gmail_label_ids
            FROM mail_thread_summaries
            WHERE thread_id = ? LIMIT 1
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(id, at: 1, in: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return summary(from: statement)
    }

    private func summary(from statement: OpaquePointer) -> MailThread? {
        guard let id = string(at: 0, in: statement),
              let sender = string(at: 2, in: statement),
              let email = string(at: 3, in: statement),
              let subject = string(at: 4, in: statement),
              let preview = string(at: 5, in: statement),
              let displayDate = string(at: 6, in: statement),
              let folderValue = string(at: 10, in: statement),
              let folder = Mailbox(rawValue: folderValue),
              let labelsValue = string(at: 11, in: statement),
              let gmailLabelsValue = string(at: 12, in: statement) else { return nil }
        let labels = Set(labelsValue.split(separator: Self.summarySeparator).compactMap {
            Mailbox(rawValue: String($0))
        })
        let gmailLabelIDs = Set(gmailLabelsValue.split(separator: Self.summarySeparator).map(String.init))
        return MailThread(
            id: id,
            sender: sender,
            email: email,
            subject: subject,
            preview: preview,
            displayDate: displayDate,
            date: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
            isUnread: sqlite3_column_int(statement, 7) != 0,
            isStarred: sqlite3_column_int(statement, 8) != 0,
            hasAttachment: sqlite3_column_int(statement, 9) != 0,
            folder: folder,
            labels: labels,
            messages: [],
            gmailLabelIDs: gmailLabelIDs
        )
    }

    private func rowCount(in table: String) throws -> Int {
        let statement = try prepare("SELECT COUNT(*) FROM \(table)")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func tableExists(_ table: String) throws -> Bool {
        let statement = try prepare(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1"
        )
        defer { sqlite3_finalize(statement) }
        try bind(table, at: 1, in: statement)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    func cachedThread(id: String) throws -> MailThread? {
        let statement = try prepare("SELECT json FROM mail_threads WHERE id = ? LIMIT 1")
        defer { sqlite3_finalize(statement) }
        try bind(id, at: 1, in: statement)
        guard sqlite3_step(statement) == SQLITE_ROW,
              let bytes = sqlite3_column_blob(statement, 0) else { return nil }
        let length = Int(sqlite3_column_bytes(statement, 0))
        return try decoder.decode(MailThread.self, from: Data(bytes: bytes, count: length))
    }

    private func insert(_ thread: MailThread) throws {
        let data = try encoder.encode(thread)
        let summaryData = try encoder.encode(thread.listSummary)
        let threadStatement = try prepare(
            "INSERT OR REPLACE INTO mail_threads(id, date, json, summary_json) VALUES (?, ?, ?, ?)"
        )
        defer { sqlite3_finalize(threadStatement) }
        try bind(thread.id, at: 1, in: threadStatement)
        sqlite3_bind_double(threadStatement, 2, thread.date.timeIntervalSince1970)
        _ = data.withUnsafeBytes { bytes in
            sqlite3_bind_blob(threadStatement, 3, bytes.baseAddress, Int32(bytes.count), sqliteTransient)
        }
        _ = summaryData.withUnsafeBytes { bytes in
            sqlite3_bind_blob(threadStatement, 4, bytes.baseAddress, Int32(bytes.count), sqliteTransient)
        }
        try stepDone(threadStatement)
        try insertSummary(thread.listSummary)

        let searchStatement = try prepare(
            """
            INSERT INTO mail_search(thread_id, sender, email, subject, preview, body, attachments)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """
        )
        defer { sqlite3_finalize(searchStatement) }
        let attachmentText = thread.messages
            .flatMap { $0.attachmentNames + $0.inlineImages.map(\.name) }
            .joined(separator: " ")
        for (index, value) in [
            thread.id,
            thread.sender,
            thread.email,
            thread.subject,
            thread.preview,
            thread.searchableBody,
            attachmentText
        ].enumerated() {
            try bind(value, at: Int32(index + 1), in: searchStatement)
        }
        try stepDone(searchStatement)
    }

    private func deleteThread(id: String) throws {
        for sql in [
            "DELETE FROM mail_thread_summaries WHERE thread_id = ?",
            "DELETE FROM mail_threads WHERE id = ?",
            "DELETE FROM mail_search WHERE thread_id = ?"
        ] {
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }
            try bind(id, at: 1, in: statement)
            try stepDone(statement)
        }
    }

    private func insertSummary(_ thread: MailThread) throws {
        let statement = try prepare(
            """
            INSERT OR REPLACE INTO mail_thread_summaries(
                thread_id, date, sender, email, subject, preview, display_date,
                is_unread, is_starred, has_attachment, folder, labels, gmail_label_ids
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        )
        defer { sqlite3_finalize(statement) }
        let labels = thread.labels.map(\.rawValue).sorted().joined(separator: String(Self.summarySeparator))
        let gmailLabelIDs = thread.gmailLabelIDs.sorted().joined(separator: String(Self.summarySeparator))
        let textValues = [
            (1, thread.id),
            (3, thread.sender),
            (4, thread.email),
            (5, thread.subject),
            (6, thread.preview),
            (7, thread.displayDate),
            (11, thread.folder.rawValue),
            (12, labels),
            (13, gmailLabelIDs)
        ]
        for (index, value) in textValues { try bind(value, at: Int32(index), in: statement) }
        sqlite3_bind_double(statement, 2, thread.date.timeIntervalSince1970)
        sqlite3_bind_int(statement, 8, thread.isUnread ? 1 : 0)
        sqlite3_bind_int(statement, 9, thread.isStarred ? 1 : 0)
        sqlite3_bind_int(statement, 10, thread.hasAttachment ? 1 : 0)
        try stepDone(statement)
    }

    private func string(at index: Int32, in statement: OpaquePointer) -> String? {
        guard let value = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: value)
    }

    private func metadata(for key: String) throws -> String? {
        let statement = try prepare("SELECT value FROM mail_metadata WHERE key = ? LIMIT 1")
        defer { sqlite3_finalize(statement) }
        try bind(key, at: 1, in: statement)
        guard sqlite3_step(statement) == SQLITE_ROW,
              let value = sqlite3_column_text(statement, 0) else { return nil }
        return String(cString: value)
    }

    private func setMetadata(_ value: String, for key: String) throws {
        let statement = try prepare("INSERT OR REPLACE INTO mail_metadata(key, value) VALUES (?, ?)")
        defer { sqlite3_finalize(statement) }
        try bind(key, at: 1, in: statement)
        try bind(value, at: 2, in: statement)
        try stepDone(statement)
    }

    private func deleteMetadata(for key: String) throws {
        let statement = try prepare("DELETE FROM mail_metadata WHERE key = ?")
        defer { sqlite3_finalize(statement) }
        try bind(key, at: 1, in: statement)
        try stepDone(statement)
    }

    private func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func execute(_ sql: String) throws {
        guard let database else { throw GmailIntegrationError.cache("Database is closed") }
        try Self.execute(sql, on: database)
    }

    private static func execute(_ sql: String, on database: OpaquePointer) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &errorPointer) == SQLITE_OK else {
            let message = errorPointer.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(database))
            sqlite3_free(errorPointer)
            throw GmailIntegrationError.cache(message)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        guard let database else { throw GmailIntegrationError.cache("Database is closed") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw GmailIntegrationError.cache(String(cString: sqlite3_errmsg(database)))
        }
        return statement
    }

    private func bind(_ value: String, at index: Int32, in statement: OpaquePointer) throws {
        guard sqlite3_bind_text(statement, index, value, -1, sqliteTransient) == SQLITE_OK else {
            throw databaseError()
        }
    }

    private func stepDone(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else { throw databaseError() }
    }

    private func databaseError() -> GmailIntegrationError {
        guard let database else { return .cache("Database is closed") }
        return .cache(String(cString: sqlite3_errmsg(database)))
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
