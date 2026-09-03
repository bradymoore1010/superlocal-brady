import AppKit
import Foundation

@main
struct MailStoreTestRunner {
    private static var failures = 0
    private static var checks = 0

    @MainActor
    static func main() {
        let first = makeThread(id: "first", sender: "First Sender", email: "first@example.com", date: 3)
        let second = makeThread(id: "second", sender: "Second Sender", email: "second@example.com", date: 2)
        let newsletter = makeThread(
            id: "newsletter",
            sender: "Daily Brief",
            email: "brief@example.com",
            date: 1,
            listUnsubscribe: "<mailto:unsubscribe@example.com?subject=Remove%20me>"
        )
        let store = MailStore(
            initialThreads: [first, second, newsletter],
            bootstrapGmail: false,
            startSearchIndexing: false,
            enableCachedSearch: false
        )

        store.open(first)
        store.archiveCurrent()
        expect(
            store.openedThread?.id == second.id
                && store.threads.first(where: { $0.id == first.id })?.folder == .archive,
            "E archives and advances to the next conversation"
        )
        expect(
            store.undoLastAction()
                && store.threads.first(where: { $0.id == first.id })?.folder == .inbox,
            "archive can be undone during the undo window"
        )

        let replyMessageCount = store.openedThread?.messages.count
        store.replyDraft = "Reply body"
        store.sendReply()
        let replyWasOptimistic = store.openedThread?.messages.count == (replyMessageCount ?? 0) + 1
        let replyUndone = store.undoLastAction()
        expect(
            replyWasOptimistic
                && replyUndone
                && store.openedThread?.messages.count == replyMessageCount
                && store.replyDraft == "Reply body",
            "reply send is optimistic and restores its draft on undo"
        )

        store.presentCompose()
        store.composeTo = "person@example.com"
        store.composeSubject = "Hello"
        store.composeBody = "Composed body"
        store.sendCompose()
        let controlZ = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.control],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "z",
            charactersIgnoringModifiers: "z",
            isARepeat: false,
            keyCode: 6
        )!
        expect(
            store.handleKeyEvent(controlZ)
                && store.isComposePresented
                && store.composeTo == "person@example.com"
                && store.composeSubject == "Hello"
                && store.composeBody == "Composed body",
            "Ctrl-Z undoes a composed send and reopens the draft"
        )

        store.closeCompose()
        store.open(newsletter)
        store.requestUnsubscribe()
        let returnKey = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36
        )!
        expect(
            store.handleKeyEvent(returnKey)
                && store.pendingUnsubscribe == nil
                && store.isComposePresented
                && store.composeTo == "unsubscribe@example.com",
            "Return confirms the unsubscribe action"
        )

        store.closeCompose()
        expect(
            store.commands.contains(where: { $0.action == .blockSender }),
            "Command-K exposes Block sender for the selected conversation"
        )

        if failures > 0 {
            print("\(failures) mail store test(s) failed")
            exit(1)
        }
        print("\(checks) mail store behavior tests passed")
    }

    @MainActor
    private static func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        checks += 1
        if condition() {
            print("✓ \(name)")
        } else {
            failures += 1
            print("✗ \(name)")
        }
    }

    private static func makeThread(
        id: String,
        sender: String,
        email: String,
        date: TimeInterval,
        listUnsubscribe: String? = nil
    ) -> MailThread {
        MailThread(
            id: id,
            sender: sender,
            email: email,
            subject: "Subject \(id)",
            preview: "Message \(id)",
            displayDate: "Now",
            date: Date(timeIntervalSince1970: date),
            isUnread: true,
            isStarred: false,
            hasAttachment: false,
            folder: .inbox,
            labels: [.inbox],
            messages: [
                MailMessage(
                    id: "message-\(id)",
                    sender: sender,
                    senderEmail: email,
                    recipientLine: "to me",
                    body: "Message \(id)",
                    timestamp: "Now",
                    listUnsubscribe: listUnsubscribe
                )
            ]
        )
    }
}
