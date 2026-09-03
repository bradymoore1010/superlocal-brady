import Foundation

@main
struct RepositoryTestRunner {
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("keyboard-first-mail-repository-tests-(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let repository = try SQLiteMailRepository(
            databaseURL: directory.appendingPathComponent("mail.sqlite3")
        )
        let message = MailMessage(
            id: "message-1",
            sender: "Ava Patel",
            senderEmail: "ava@example.com",
            recipientLine: "to me",
            body: "The message body must survive summary state updates.",
            timestamp: "Now",
            gmailLabelIDs: ["INBOX", "UNREAD"]
        )
        let fullThread = MailThread(
            id: "thread-1",
            sender: "Ava Patel",
            email: "ava@example.com",
            subject: "Cache regression",
            preview: message.body,
            displayDate: "Now",
            date: Date(),
            isUnread: true,
            isStarred: false,
            hasAttachment: false,
            folder: .inbox,
            labels: [.inbox],
            messages: [message],
            gmailLabelIDs: ["INBOX", "UNREAD"]
        )

        try await repository.replaceMailbox(
            threads: [fullThread],
            accountEmail: "me@example.com",
            historyID: "100",
            syncedAt: Date()
        )

        var updatedSummary = fullThread.listSummary
        updatedSummary.isUnread = false
        updatedSummary.gmailLabelIDs.remove("UNREAD")
        try await repository.updateThreadState(updatedSummary)
        try await repository.updateSyncMetadata(
            accountEmail: "me@example.com",
            historyID: "101",
            syncedAt: Date()
        )

        let cached = try await repository.cachedThread(id: fullThread.id)
        guard cached?.messages == [message], cached?.isUnread == false else {
            fputs("repository regression test failed: summary update erased cached content\n", stderr)
            exit(1)
        }

        let mailbox = try await repository.loadMailbox()
        guard mailbox?.threads.first?.messages.isEmpty == true,
              mailbox?.contentVersion == GmailCachedMailbox.currentContentVersion else {
            fputs("repository regression test failed: lightweight mailbox snapshot is invalid\n", stderr)
            exit(1)
        }

        let directoryEntry = RecipientSuggestion(
            name: "Legacy Contact",
            email: "legacy@example.com",
            interactionCount: 7,
            wasPreviouslyEmailed: true,
            lastInteraction: Date(timeIntervalSince1970: 1_000)
        )
        try await repository.replaceRecipientDirectory(
            [directoryEntry],
            accountEmail: "me@example.com",
            syncedAt: Date(timeIntervalSince1970: 2_000)
        )
        let cachedDirectory = try await repository.loadRecipientDirectory(accountEmail: "me@example.com")
        guard cachedDirectory?.entries == [directoryEntry],
              cachedDirectory?.syncedAt == Date(timeIntervalSince1970: 2_000),
              try await repository.loadRecipientDirectory(accountEmail: "someone@example.com") == nil else {
            fputs("repository regression test failed: Gmail directory cache is invalid\n", stderr)
            exit(1)
        }

        print("4 repository cache tests passed")
    }
}
