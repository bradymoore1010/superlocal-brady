import Foundation
import UniformTypeIdentifiers

enum Mailbox: String, CaseIterable, Identifiable, Codable, Sendable {
    case inbox = "Inbox"
    case starred = "Starred"
    case sent = "Sent"
    case drafts = "Drafts"
    case archive = "Archive"
    case updates = "Updates"
    case receipts = "Receipts"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .inbox: "circle.fill"
        case .starred: "star"
        case .sent: "arrow.up.right"
        case .drafts: "square"
        case .archive: "arrow.down"
        case .updates: "diamond"
        case .receipts: "circle"
        }
    }

    var isLabel: Bool {
        self == .updates || self == .receipts
    }
}

struct MailMessage: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let sender: String
    let senderEmail: String
    let recipientLine: String
    let body: String
    let htmlBody: String?
    let timestamp: String
    let attachmentNames: [String]
    let inlineImages: [InlineDraftImage]
    let rfcMessageID: String?
    let references: String?
    let listUnsubscribe: String?
    let listUnsubscribePost: String?
    let gmailLabelIDs: Set<String>

    init(
        id: String,
        sender: String,
        senderEmail: String = "",
        recipientLine: String,
        body: String,
        htmlBody: String? = nil,
        timestamp: String,
        attachmentNames: [String] = [],
        inlineImages: [InlineDraftImage] = [],
        rfcMessageID: String? = nil,
        references: String? = nil,
        listUnsubscribe: String? = nil,
        listUnsubscribePost: String? = nil,
        gmailLabelIDs: Set<String> = []
    ) {
        self.id = id
        self.sender = sender
        self.senderEmail = senderEmail
        self.recipientLine = recipientLine
        self.body = body
        self.htmlBody = htmlBody
        self.timestamp = timestamp
        self.attachmentNames = attachmentNames
        self.inlineImages = inlineImages
        self.rfcMessageID = rfcMessageID
        self.references = references
        self.listUnsubscribe = listUnsubscribe
        self.listUnsubscribePost = listUnsubscribePost
        self.gmailLabelIDs = gmailLabelIDs
    }

    var unsubscribeMethod: MailUnsubscribeMethod? {
        MailUnsubscribeParser.method(
            listUnsubscribe: listUnsubscribe,
            listUnsubscribePost: listUnsubscribePost
        )
    }

    var isAuthoredByUser: Bool {
        if gmailLabelIDs.contains("SENT") { return true }
        guard sender.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("You") == .orderedSame else { return false }
        return !gmailLabelIDs.contains("DRAFT")
            && recipientLine.caseInsensitiveCompare("draft") != .orderedSame
    }

    var compactPreview: String {
        // A one-line row can never display an entire message. Bound the work
        // before applying draft-marker cleanup so long threads do not repeatedly
        // normalize hundreds of kilobytes while SwiftUI measures their rows.
        let previewSource = String(body.prefix(512))
        let normalizedBody = MailDraftSerializer.outgoingText(
            from: MailPlainTextNormalizer.currentMessageText(previewSource),
            inlineImages: inlineImages
        )
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !normalizedBody.isEmpty { return normalizedBody }
        return attachmentNames.isEmpty ? "" : "Attachment: \(attachmentNames.joined(separator: ", "))"
    }
}

enum InlineImageDisplaySize: String, CaseIterable, Identifiable, Hashable, Codable, Sendable {
    case small
    case medium
    case large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }

    var maximumSize: CGSize {
        switch self {
        case .small: CGSize(width: 280, height: 180)
        case .medium: CGSize(width: 440, height: 280)
        case .large: CGSize(width: 640, height: 420)
        }
    }
}

struct InlineDraftImage: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let url: URL
    let name: String
    let data: Data
    var displaySize: InlineImageDisplaySize

    init(
        id: UUID = UUID(),
        url: URL,
        name: String,
        data: Data,
        displaySize: InlineImageDisplaySize = .large
    ) {
        self.id = id
        self.url = url
        self.name = name
        self.data = data
        self.displaySize = displaySize
    }

    init?(url: URL) {
        guard Self.isSupportedImage(url) else { return nil }

        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing { url.stopAccessingSecurityScopedResource() }
        }

        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        id = UUID()
        self.url = url
        name = url.lastPathComponent
        self.data = data
        displaySize = .large
    }

    static func isSupportedImage(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }
}

struct MailInlineImageRequest: Equatable, Sendable {
    let id = UUID()
    let images: [InlineDraftImage]
}

struct DraftAttachment: Identifiable, Hashable, Sendable {
    let id: UUID
    let url: URL
    let name: String
    var byteCount: Int64?

    init(id: UUID = UUID(), url: URL, byteCount: Int64? = nil) {
        self.id = id
        self.url = url
        name = url.lastPathComponent
        self.byteCount = byteCount
    }

    static func loadByteCount(for url: URL) -> Int64? {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing { url.stopAccessingSecurityScopedResource() }
        }

        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize.map(Int64.init)
    }

    var sizeLabel: String? {
        guard let byteCount else { return nil }
        return ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }
}

struct MailThread: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var sender: String
    var email: String
    var subject: String
    var preview: String
    var displayDate: String
    var date: Date
    var isUnread: Bool
    var isStarred: Bool
    var hasAttachment: Bool
    var folder: Mailbox
    var labels: Set<Mailbox>
    var messages: [MailMessage]
    var gmailLabelIDs: Set<String>

    var searchableBody: String {
        messages
            .map { message in
                ([message.body] + message.attachmentNames + message.inlineImages.map(\.name))
                    .joined(separator: " ")
            }
            .joined(separator: " ")
    }

    init(
        id: String,
        sender: String,
        email: String,
        subject: String,
        preview: String,
        displayDate: String,
        date: Date,
        isUnread: Bool,
        isStarred: Bool,
        hasAttachment: Bool,
        folder: Mailbox,
        labels: Set<Mailbox>,
        messages: [MailMessage],
        gmailLabelIDs: Set<String> = []
    ) {
        self.id = id
        self.sender = sender
        self.email = email
        self.subject = subject
        self.preview = preview
        self.displayDate = displayDate
        self.date = date
        self.isUnread = isUnread
        self.isStarred = isStarred
        self.hasAttachment = hasAttachment
        self.folder = folder
        self.labels = labels
        self.messages = messages
        self.gmailLabelIDs = gmailLabelIDs
    }

    var displayPreview: String {
        if let latestPreview = messages.last?.compactPreview, !latestPreview.isEmpty {
            return latestPreview
        }
        // Summary rows are normalized once when they are persisted. Avoid
        // re-running the body parser for every SwiftUI display pass.
        if messages.isEmpty { return preview }
        return MailPlainTextNormalizer.currentMessageText(preview)
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var unsubscribeMethod: MailUnsubscribeMethod? {
        messages.reversed().compactMap(\.unsubscribeMethod).first
    }

    var shouldOpenReplyComposerByDefault: Bool {
        // Gmail already exposes SENT at the thread level, so the hot open and
        // keyboard-navigation path does not need to rescan a long conversation.
        if !gmailLabelIDs.isEmpty { return gmailLabelIDs.contains("SENT") }
        return messages.contains(where: \.isAuthoredByUser)
    }

    var defaultExpandedMessageID: String? {
        messages.reversed().first(where: { !$0.isAuthoredByUser })?.id
            ?? messages.last?.id
    }

    var listSummary: MailThread {
        var summary = self
        summary.preview = displayPreview
        summary.messages = []
        return summary
    }
}

enum CommandAction: String, Sendable {
    case compose
    case search
    case scheduleSend
    case signatures
    case inbox
    case starred
    case sent
    case drafts
    case archiveMailbox
    case archiveCurrent
    case remind
    case unsubscribe
    case blockSender
    case reply
    case toggleStar
    case toggleUnread
}

enum MailTriagePolicy {
    static func nextThreadID(afterRemoving threadID: String, from threads: [MailThread]) -> String? {
        guard let index = threads.firstIndex(where: { $0.id == threadID }) else {
            return threads.first?.id
        }
        if threads.indices.contains(index + 1) { return threads[index + 1].id }
        if index > threads.startIndex { return threads[index - 1].id }
        return nil
    }
}

struct MailUndoWindow: Equatable, Sendable {
    static let duration: TimeInterval = 5

    let startedAt: Date

    init(startedAt: Date = Date()) {
        self.startedAt = startedAt
    }

    var deadline: Date { startedAt.addingTimeInterval(Self.duration) }

    func isActive(at date: Date = Date()) -> Bool {
        date <= deadline
    }
}

enum SenderBlockPolicy {
    static func normalizedAddress(_ address: String) -> String {
        address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

enum CommandPaletteMode: Equatable, Sendable {
    case commands
    case signatures
    case scheduleSend
    case reminder
}

enum MailUnsubscribeMethod: Hashable, Sendable {
    case oneClick(URL)
    case web(URL)
    case email(URL)

    var url: URL {
        switch self {
        case let .oneClick(url), let .web(url), let .email(url): url
        }
    }
}

enum MailUnsubscribeParser {
    static func method(
        listUnsubscribe: String?,
        listUnsubscribePost: String?
    ) -> MailUnsubscribeMethod? {
        guard let listUnsubscribe else { return nil }
        let urls = extractURLs(from: listUnsubscribe)
        let webURL = urls.first { url in
            ["https", "http"].contains(url.scheme?.lowercased() ?? "")
        }
        let emailURL = urls.first { $0.scheme?.lowercased() == "mailto" }
        let supportsOneClick = listUnsubscribePost?
            .localizedCaseInsensitiveContains("List-Unsubscribe=One-Click") == true

        if supportsOneClick,
           let webURL,
           webURL.scheme?.lowercased() == "https",
           isSafeOneClickURL(webURL) {
            return .oneClick(webURL)
        }
        if let webURL { return .web(webURL) }
        if let emailURL { return .email(emailURL) }
        return nil
    }

    private static func extractURLs(from value: String) -> [URL] {
        let source = value as NSString
        let matches = (try? NSRegularExpression(pattern: #"<([^>]+)>"#))?
            .matches(in: value, range: NSRange(location: 0, length: source.length)) ?? []
        var candidates = matches.compactMap { match -> String? in
            guard match.numberOfRanges > 1 else { return nil }
            return source.substring(with: match.range(at: 1))
        }
        if candidates.isEmpty {
            candidates = value.split(separator: ",").map(String.init)
        }
        return candidates.compactMap { candidate in
            URL(string: candidate.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    static func isSafeOneClickURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https" else { return false }
        return isSafeOneClickHost(url.host)
    }

    private static func isSafeOneClickHost(_ rawHost: String?) -> Bool {
        guard let host = rawHost?.lowercased(), !host.isEmpty else { return false }
        if host == "localhost" || host.hasSuffix(".local") || host == "::1" { return false }
        if host.hasPrefix("127.") || host.hasPrefix("10.") || host.hasPrefix("192.168.") { return false }
        if host.hasPrefix("169.254.") || host == "0.0.0.0" { return false }
        let segments = host.split(separator: ".")
        if segments.count == 4,
           segments[0] == "172",
           let second = Int(segments[1]),
           (16...31).contains(second) { return false }
        return true
    }
}

struct PendingUnsubscribe: Equatable, Sendable {
    let threadID: String
    let sender: String
    let method: MailUnsubscribeMethod

    var confirmationTitle: String { "Unsubscribe from \(sender)?" }

    var confirmationMessage: String {
        switch method {
        case .oneClick:
            "This will ask the sender to stop future mailing-list messages."
        case .web:
            "The sender’s unsubscribe page will open so you can finish there."
        case .email:
            "A ready-to-send unsubscribe draft will open. Nothing sends automatically."
        }
    }

    var confirmationButtonTitle: String {
        switch method {
        case .oneClick: "Unsubscribe"
        case .web: "Open unsubscribe page"
        case .email: "Create draft"
        }
    }

    var isDestructive: Bool {
        if case .oneClick = method { return true }
        return false
    }
}

struct PendingSenderBlock: Equatable, Sendable {
    let sender: String
    let email: String

    var confirmationTitle: String { "Block (sender)?" }
    var confirmationMessage: String {
        "Messages from (email) will skip your inbox in Mail. Existing conversations from this sender will be archived."
    }
}

struct MailCommand: Identifiable, Hashable, Sendable {
    let action: CommandAction
    let title: String
    let subtitle: String?
    let icon: String
    let shortcut: String
    let keywords: [String]

    var id: String { action.rawValue }
}

extension MailThread {
    static let samples: [MailThread] = {
        func date(_ month: Int, _ day: Int, _ hour: Int) -> Date {
            var components = DateComponents()
            components.calendar = Calendar(identifier: .gregorian)
            components.timeZone = TimeZone(secondsFromGMT: 0)
            components.year = 2026
            components.month = month
            components.day = day
            components.hour = hour
            return components.date ?? .distantPast
        }

        return [
            MailThread(
                id: "project-handoff",
                sender: "Ava Patel",
                email: "ava@northwind.example",
                subject: "Project handoff",
                preview: "Everything is ready for Thursday. I added the final notes…",
                displayDate: "10:42",
                date: date(9, 2, 10),
                isUnread: true,
                isStarred: false,
                hasAttachment: true,
                folder: .inbox,
                labels: [.updates],
                messages: [
                    MailMessage(
                        id: "handoff-1",
                        sender: "You",
                        recipientLine: "to Ava Patel",
                        body: "Here is the first draft and the open question on timing.",
                        timestamp: "Aug 27"
                    ),
                    MailMessage(
                        id: "handoff-2",
                        sender: "Ava Patel",
                        recipientLine: "to me",
                        body: "Looks good. I left two comments in the document.",
                        timestamp: "Aug 28"
                    ),
                    MailMessage(
                        id: "handoff-3",
                        sender: "You",
                        recipientLine: "to Ava Patel",
                        body: "Both comments are resolved. Thursday still works on my side.",
                        timestamp: "Aug 31"
                    ),
                    MailMessage(
                        id: "handoff-4",
                        sender: "Ava Patel",
                        recipientLine: "to me",
                        body: "Everything is ready for Thursday. I added the final notes and moved the open questions to the top so we can make the decisions quickly.\n\nNo need to prepare anything else. See you then.",
                        timestamp: "Today, 10:42"
                    )
                ]
            ),
            MailThread(
                id: "northwind-shipping",
                sender: "Northwind",
                email: "orders@northwind.example",
                subject: "Your order shipped",
                preview: "Track package 10482 and view the latest delivery estimate.",
                displayDate: "9:18",
                date: date(9, 2, 9),
                isUnread: true,
                isStarred: false,
                hasAttachment: false,
                folder: .inbox,
                labels: [.updates],
                messages: [MailMessage(id: "shipping-1", sender: "Northwind", recipientLine: "to me", body: "Track package 10482 and view the latest delivery estimate.", timestamp: "Today, 9:18")]
            ),
            MailThread(
                id: "coffee-next-week",
                sender: "Theo Martin",
                email: "theo@example.com",
                subject: "Coffee next week",
                preview: "Tuesday at 9 works for me. Want to meet downtown?",
                displayDate: "8:54",
                date: date(9, 2, 8),
                isUnread: true,
                isStarred: true,
                hasAttachment: false,
                folder: .inbox,
                labels: [],
                messages: [MailMessage(id: "coffee-1", sender: "Theo Martin", recipientLine: "to me", body: "Tuesday at 9 works for me. Want to meet downtown?", timestamp: "Today, 8:54")]
            ),
            MailThread(
                id: "september-receipt",
                sender: "Studio Supply",
                email: "receipts@studiosupply.example",
                subject: "September receipt",
                preview: "Your receipt for order 2187 is attached.",
                displayDate: "Yesterday",
                date: date(9, 1, 17),
                isUnread: false,
                isStarred: false,
                hasAttachment: true,
                folder: .inbox,
                labels: [.receipts],
                messages: [MailMessage(id: "receipt-1", sender: "Studio Supply", recipientLine: "to me", body: "Your receipt for order 2187 is attached.", timestamp: "Yesterday")]
            ),
            MailThread(
                id: "product-notes",
                sender: "Jules Park",
                email: "jules@example.com",
                subject: "Re: Product notes",
                preview: "The keyboard flow feels right. One thought on the reply field…",
                displayDate: "Yesterday",
                date: date(9, 1, 13),
                isUnread: false,
                isStarred: true,
                hasAttachment: false,
                folder: .inbox,
                labels: [],
                messages: [MailMessage(id: "notes-1", sender: "Jules Park", recipientLine: "to me", body: "The keyboard flow feels right. One thought on the reply field: keep it directly in the thread.", timestamp: "Yesterday")]
            ),
            MailThread(
                id: "security-sign-in",
                sender: "Nimbus",
                email: "security@nimbus.example",
                subject: "Security sign-in",
                preview: "A new sign-in was approved from your Mac.",
                displayDate: "Mon",
                date: date(8, 31, 18),
                isUnread: false,
                isStarred: false,
                hasAttachment: false,
                folder: .inbox,
                labels: [.updates],
                messages: [MailMessage(id: "security-1", sender: "Nimbus", recipientLine: "to me", body: "A new sign-in was approved from your Mac in Dallas, Texas.", timestamp: "Mon")]
            ),
            MailThread(
                id: "paper-welcome",
                sender: "Paper",
                email: "hello@paper.design",
                subject: "Welcome to your workspace",
                preview: "Your first collaborative canvas is ready.",
                displayDate: "Mon",
                date: date(8, 31, 12),
                isUnread: false,
                isStarred: false,
                hasAttachment: false,
                folder: .inbox,
                labels: [.updates],
                messages: [MailMessage(id: "paper-1", sender: "Paper", recipientLine: "to me", body: "Your first collaborative canvas is ready.", timestamp: "Mon")]
            ),
            MailThread(
                id: "updated-policy",
                sender: "Atlas Health",
                email: "benefits@atlas.example",
                subject: "Updated policy",
                preview: "The latest coverage summary is ready to review.",
                displayDate: "Fri",
                date: date(8, 28, 15),
                isUnread: false,
                isStarred: false,
                hasAttachment: true,
                folder: .inbox,
                labels: [.updates],
                messages: [MailMessage(id: "policy-1", sender: "Atlas Health", recipientLine: "to me", body: "The latest coverage summary is ready to review.", timestamp: "Fri")]
            ),
            MailThread(
                id: "introduction",
                sender: "Rina",
                email: "rina@example.com",
                subject: "Introduction",
                preview: "I thought the two of you should meet.",
                displayDate: "Fri",
                date: date(8, 28, 10),
                isUnread: false,
                isStarred: false,
                hasAttachment: false,
                folder: .inbox,
                labels: [],
                messages: [MailMessage(id: "intro-1", sender: "Rina", recipientLine: "to me", body: "I thought the two of you should meet.", timestamp: "Fri")]
            ),
            MailThread(
                id: "draft-demo",
                sender: "You",
                email: "me@example.com",
                subject: "Partnership follow-up",
                preview: "Draft: A quick follow-up from our conversation…",
                displayDate: "11:12",
                date: date(9, 2, 11),
                isUnread: false,
                isStarred: false,
                hasAttachment: false,
                folder: .drafts,
                labels: [],
                messages: [MailMessage(id: "draft-1", sender: "You", recipientLine: "draft", body: "A quick follow-up from our conversation…", timestamp: "Draft")]
            ),
            MailThread(
                id: "sent-demo",
                sender: "You",
                email: "me@example.com",
                subject: "Re: Interview timing",
                preview: "Thursday afternoon works well for me.",
                displayDate: "Aug 29",
                date: date(8, 29, 14),
                isUnread: false,
                isStarred: false,
                hasAttachment: false,
                folder: .sent,
                labels: [],
                messages: [MailMessage(id: "sent-1", sender: "You", recipientLine: "to Michael", body: "Thursday afternoon works well for me.", timestamp: "Aug 29")]
            )
        ]
    }()
}
