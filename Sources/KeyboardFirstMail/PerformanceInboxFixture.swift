import Foundation

enum PerformanceInboxFixture {
    static let defaultThreadCount = 10_000

    struct Summary: Codable, Sendable {
        let threadCount: Int
        let messageCount: Int
        let longThreadCount: Int
        let htmlMessageCount: Int
        let attachmentThreadCount: Int
        let inlineImageThreadCount: Int
    }

    static func make(threadCount: Int = defaultThreadCount) -> [MailThread] {
        let count = max(1, threadCount)
        let baseDate = Date(timeIntervalSince1970: 1_788_364_800)
        let normalBodies = (0..<24).map { bodyVariant in
            """
            Project update \(bodyVariant): The customer review is complete and the next decision is ready.

            The working group confirmed the timeline, owner, and follow-up details. Search marker delta\(bodyVariant) remains available for deterministic queries.

            Thanks,
            Fixture Sender
            """
        }
        let longBody = Array(repeating: normalBodies[7], count: 28).joined(separator: "\n\n")
        let htmlRows = (0..<80).map { row in
            "<tr><td>Line \(row)</td><td>Quarterly planning detail \(row)</td><td>$\(row * 137)</td></tr>"
        }.joined()
        let heavyHTML = """
        <html><body><div style="font-family:Arial"><h1>Quarterly account review</h1>
        <p>HTML-heavy fixture with a conventional newsletter layout.</p>
        <table><thead><tr><th>Line</th><th>Detail</th><th>Amount</th></tr></thead><tbody>\(htmlRows)</tbody></table>
        <blockquote class="gmail_quote">Previous quoted message should remain out of the current view.</blockquote>
        </div></body></html>
        """
        let inlineImageData = Data(repeating: 0x4d, count: 2_048)
        let topics = [
            "Project handoff", "Customer follow-up", "Quarterly forecast", "Security review",
            "Contract notes", "Product feedback", "Receipt and invoice", "Interview timing",
            "Launch checklist", "Account planning", "Travel confirmation", "Team update"
        ]

        return (0..<count).map { index in
            let isLongThread = index.isMultiple(of: 97)
            let isHTMLHeavy = index.isMultiple(of: 53)
            let hasAttachments = index.isMultiple(of: 7)
            let hasInlineImage = index.isMultiple(of: 89)
            let messageCount = isLongThread ? 40 : (index.isMultiple(of: 11) ? 8 : 2)
            let senderNumber = index % 240
            let body = isLongThread ? longBody : normalBodies[index % normalBodies.count]
            let attachments = hasAttachments
                ? ["account-plan-\(index).pdf", "forecast-\(index).xlsx", "notes-\(index).txt"]
                : []
            let inlineImages = hasInlineImage
                ? [InlineDraftImage(
                    id: deterministicUUID(index),
                    url: URL(fileURLWithPath: "/fixture/inline-\(index).png"),
                    name: "inline-\(index).png",
                    data: inlineImageData,
                    displaySize: .medium
                )]
                : []
            let messages = (0..<messageCount).map { messageIndex in
                let fromUser = !messageIndex.isMultiple(of: 2)
                return MailMessage(
                    id: "fixture-\(index)-message-\(messageIndex)",
                    sender: fromUser ? "You" : "Sender \(senderNumber)",
                    senderEmail: fromUser ? "me@example.com" : "sender\(senderNumber)@example.com",
                    recipientLine: fromUser ? "to Sender \(senderNumber)" : "to me",
                    body: body,
                    htmlBody: isHTMLHeavy && messageIndex == messageCount - 1 ? heavyHTML : nil,
                    timestamp: "Sep \(1 + index % 28)",
                    attachmentNames: messageIndex == messageCount - 1 ? attachments : [],
                    inlineImages: messageIndex == messageCount - 1 ? inlineImages : []
                )
            }
            let folder: Mailbox = switch index % 20 {
            case 0, 1, 2: .archive
            case 3: .sent
            case 4: .drafts
            default: .inbox
            }
            var labels: Set<Mailbox> = [folder]
            if index.isMultiple(of: 4) { labels.insert(.updates) }
            if index.isMultiple(of: 13) { labels.insert(.receipts) }
            let subject = "\(topics[index % topics.count]) · batch \(index % 101) · delta\(index % 24)"

            return MailThread(
                id: String(format: "fixture-thread-%05d", index),
                sender: "Sender \(senderNumber)",
                email: "sender\(senderNumber)@example.com",
                subject: subject,
                preview: messages.last?.body ?? "",
                displayDate: "Sep \(1 + index % 28)",
                date: baseDate.addingTimeInterval(TimeInterval(-index * 61)),
                isUnread: index.isMultiple(of: 3),
                isStarred: index.isMultiple(of: 17),
                hasAttachment: hasAttachments || hasInlineImage,
                folder: folder,
                labels: labels,
                messages: messages,
                // Production Gmail summaries retain the union of message
                // labels, so correspondence is known before body hydration.
                gmailLabelIDs: folder == .drafts ? ["DRAFT"] : ["SENT"]
            )
        }
    }

    static func summary(of threads: [MailThread]) -> Summary {
        Summary(
            threadCount: threads.count,
            messageCount: threads.reduce(0) { $0 + $1.messages.count },
            longThreadCount: threads.filter { $0.messages.count >= 40 }.count,
            htmlMessageCount: threads.reduce(0) { count, thread in
                count + thread.messages.filter { $0.htmlBody != nil }.count
            },
            attachmentThreadCount: threads.filter(\.hasAttachment).count,
            inlineImageThreadCount: threads.filter { thread in
                thread.messages.contains { !$0.inlineImages.isEmpty }
            }.count
        )
    }

    private static func deterministicUUID(_ value: Int) -> UUID {
        let suffix = String(format: "%012x", value)
        return UUID(uuidString: "00000000-0000-4000-8000-\(suffix)")!
    }
}
