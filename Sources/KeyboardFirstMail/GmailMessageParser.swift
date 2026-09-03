import Foundation

enum GmailMessageParser {
    static func mailThread(from payload: GmailThreadPayload, accountEmail: String, now: Date = Date()) -> MailThread? {
        let parsedMessages = (payload.messages ?? [])
            .compactMap { parsedMessage(from: $0, accountEmail: accountEmail, now: now) }
            .sorted { $0.date < $1.date }
        guard !parsedMessages.isEmpty, let latest = parsedMessages.last else { return nil }

        let messages = parsedMessages.map(\.message)
        let gmailLabels = Set(messages.flatMap(\.gmailLabelIDs))
        let externalAddress = parsedMessages.reversed().first(where: { !$0.isMine })?.from
            ?? parsedMessages.reversed().flatMap { $0.to }.first(where: { !$0.address.equalsEmail(accountEmail) })
            ?? MailboxAddress(displayName: accountEmail, address: accountEmail)
        let subject = latest.subject.isEmpty ? "(No subject)" : latest.subject
        let preview = latest.message.compactPreview.isEmpty
            ? cleanSnippet(latest.snippet)
            : latest.message.compactPreview

        var mailboxes = Set<Mailbox>()
        if gmailLabels.contains("INBOX") { mailboxes.insert(.inbox) }
        if gmailLabels.contains("SENT") { mailboxes.insert(.sent) }
        if gmailLabels.contains("DRAFT") { mailboxes.insert(.drafts) }
        if !gmailLabels.contains("INBOX") && !gmailLabels.contains("SENT") && !gmailLabels.contains("DRAFT") {
            mailboxes.insert(.archive)
        }
        if gmailLabels.contains("CATEGORY_UPDATES") { mailboxes.insert(.updates) }
        if looksLikeReceipt(subject: subject, messages: messages) { mailboxes.insert(.receipts) }

        let folder: Mailbox
        if mailboxes.contains(.inbox) { folder = .inbox }
        else if mailboxes.contains(.drafts) { folder = .drafts }
        else if mailboxes.contains(.sent) { folder = .sent }
        else { folder = .archive }

        return MailThread(
            id: payload.id,
            sender: externalAddress.displayName,
            email: externalAddress.address,
            subject: subject,
            preview: preview,
            displayDate: displayDate(for: latest.date, now: now),
            date: latest.date,
            isUnread: gmailLabels.contains("UNREAD"),
            isStarred: gmailLabels.contains("STARRED"),
            hasAttachment: messages.contains { !$0.attachmentNames.isEmpty || !$0.inlineImages.isEmpty },
            folder: folder,
            labels: mailboxes,
            messages: messages,
            gmailLabelIDs: gmailLabels
        )
    }

    private struct ParsedMessage {
        let message: MailMessage
        let date: Date
        let from: MailboxAddress
        let to: [MailboxAddress]
        let subject: String
        let snippet: String
        let isMine: Bool
    }

    private static func parsedMessage(
        from payload: GmailMessagePayload,
        accountEmail: String,
        now: Date
    ) -> ParsedMessage? {
        let headers = HeaderCollection(payload.payload?.headers ?? [])
        let from = MailboxAddress.parse(headers["From"] ?? "")
        let to = MailboxAddress.parseList(headers["To"] ?? "")
        let cc = MailboxAddress.parseList(headers["Cc"] ?? "")
        let isMine = from.address.equalsEmail(accountEmail)
        let date = payload.internalDate
            .flatMap(Double.init)
            .map { Date(timeIntervalSince1970: $0 / 1_000) }
            ?? parseHeaderDate(headers["Date"])
            ?? now
        let sender = isMine ? "You" : from.displayName
        let recipients = (to + cc).map(\.displayName).filter { !$0.isEmpty }
        let recipientLine = recipients.isEmpty
            ? (isMine ? "to recipients" : "to me")
            : "to \(recipients.joined(separator: ", "))"
        let body = extractReadableBody(from: payload.payload)
        let htmlBody = extractHTMLBody(from: payload.payload)
        let attachments = attachmentNames(in: payload.payload)
        let subject = decodeRFC2047(headers["Subject"] ?? "")
        let labels = Set(payload.labelIds ?? [])

        return ParsedMessage(
            message: MailMessage(
                id: payload.id,
                sender: sender,
                senderEmail: from.address,
                recipientLine: recipientLine,
                body: body,
                htmlBody: htmlBody,
                timestamp: messageTimestamp(for: date, now: now),
                attachmentNames: attachments,
                inlineImages: [],
                rfcMessageID: headers["Message-ID"] ?? headers["Message-Id"],
                references: headers["References"],
                listUnsubscribe: headers["List-Unsubscribe"],
                listUnsubscribePost: headers["List-Unsubscribe-Post"],
                gmailLabelIDs: labels
            ),
            date: date,
            from: from,
            to: to,
            subject: subject,
            snippet: payload.snippet ?? "",
            isMine: isMine
        )
    }

    private static func extractReadableBody(from root: GmailMessagePart?) -> String {
        guard let root else { return "" }
        let plainParts = textParts(in: root, mimeType: "text/plain")
        let raw: String
        if !plainParts.isEmpty {
            raw = plainParts.joined(separator: "\n\n")
        } else {
            raw = textParts(in: root, mimeType: "text/html")
                .map(htmlToText)
                .joined(separator: "\n\n")
        }
        return MailPlainTextNormalizer.currentMessageText(raw)
    }

    private static func extractHTMLBody(from root: GmailMessagePart?) -> String? {
        guard let root else { return nil }
        let parts = textParts(in: root, mimeType: "text/html")
            .map { embedAvailableInlineImages(in: $0, from: root) }
            .map(MailHTMLNormalizer.currentMessageHTML)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "<div style=\"height:16px\"></div>")
    }

    private struct InlineImageResource {
        let contentID: String
        let mimeType: String
        let data: Data
    }

    private static func embedAvailableInlineImages(in html: String, from root: GmailMessagePart) -> String {
        inlineImageResources(in: root).reduce(html) { result, resource in
            let dataURL = "data:\(resource.mimeType);base64,\(resource.data.base64EncodedString())"
            return result.replacingOccurrences(
                of: "cid:\(resource.contentID)",
                with: dataURL,
                options: .caseInsensitive
            )
        }
        .replacingOccurrences(of: "src=\"//", with: "src=\"https://", options: .caseInsensitive)
        .replacingOccurrences(of: "src='//", with: "src='https://", options: .caseInsensitive)
    }

    private static func inlineImageResources(in part: GmailMessagePart) -> [InlineImageResource] {
        var resources: [InlineImageResource] = []
        let mimeType = part.mimeType?.lowercased() ?? ""
        let headers = HeaderCollection(part.headers ?? [])
        let rawContentID = headers["Content-ID"] ?? headers["X-Attachment-Id"]
        let contentID = rawContentID?
            .trimmingCharacters(in: CharacterSet(charactersIn: "<> \t\r\n"))

        if mimeType.hasPrefix("image/"),
           let contentID,
           !contentID.isEmpty,
           let encoded = part.body?.data,
           let data = decodeBase64URL(encoded),
           !data.isEmpty {
            resources.append(
                InlineImageResource(contentID: contentID, mimeType: mimeType, data: data)
            )
        }

        for child in part.parts ?? [] {
            resources.append(contentsOf: inlineImageResources(in: child))
        }
        return resources
    }

    private static func textParts(in part: GmailMessagePart, mimeType: String) -> [String] {
        var values: [String] = []
        if part.mimeType?.lowercased() == mimeType,
           (part.filename ?? "").isEmpty,
           let encoded = part.body?.data,
           let data = decodeBase64URL(encoded),
           let value = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
            values.append(value)
        }
        for child in part.parts ?? [] {
            values.append(contentsOf: textParts(in: child, mimeType: mimeType))
        }
        return values
    }

    private static func attachmentNames(in root: GmailMessagePart?) -> [String] {
        guard let root else { return [] }
        var names: [String] = []
        if let filename = root.filename?.trimmingCharacters(in: .whitespacesAndNewlines), !filename.isEmpty {
            names.append(decodeRFC2047(filename))
        }
        for child in root.parts ?? [] { names.append(contentsOf: attachmentNames(in: child)) }
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }

    private static func htmlToText(_ html: String) -> String {
        var value = html
        let replacements: [(String, String)] = [
            ("(?i)<br\\s*/?>", "\n"),
            ("(?i)</(p|div|h[1-6]|tr|blockquote)\\s*>", "\n"),
            ("(?i)<li(?:\\s[^>]*)?>", "• "),
            ("(?i)</li\\s*>", "\n"),
            ("(?s)<style(?:\\s[^>]*)?>.*?</style>", ""),
            ("(?s)<script(?:\\s[^>]*)?>.*?</script>", ""),
            ("(?s)<[^>]+>", "")
        ]
        for (pattern, replacement) in replacements {
            value = value.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        value = decodeHTMLEntities(value)
        value = value.replacingOccurrences(of: "[ \\t]+\n", with: "\n", options: .regularExpression)
        value = value.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return value
    }

    private static func decodeHTMLEntities(_ value: String) -> String {
        var result = value
        let named = [
            "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&#39;": "'", "&apos;": "'"
        ]
        for (entity, replacement) in named {
            result = result.replacingOccurrences(of: entity, with: replacement, options: .caseInsensitive)
        }

        let pattern = try? NSRegularExpression(pattern: "&#(x?[0-9A-Fa-f]+);")
        let source = result as NSString
        let matches = pattern?.matches(in: result, range: NSRange(location: 0, length: source.length)).reversed() ?? []
        var mutable = result
        for match in matches {
            let token = source.substring(with: match.range(at: 1))
            let number: UInt32?
            if token.lowercased().hasPrefix("x") { number = UInt32(token.dropFirst(), radix: 16) }
            else { number = UInt32(token, radix: 10) }
            if let number, let scalar = UnicodeScalar(number) {
                let range = Range(match.range, in: mutable)!
                mutable.replaceSubrange(range, with: String(scalar))
            }
        }
        return mutable
    }

    private static func cleanSnippet(_ value: String) -> String {
        decodeHTMLEntities(value)
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func looksLikeReceipt(subject: String, messages: [MailMessage]) -> Bool {
        let value = ([subject] + messages.flatMap { [$0.body] + $0.attachmentNames })
            .joined(separator: " ")
            .lowercased()
        return ["receipt", "invoice", "order confirmation", "payment confirmation"].contains { value.contains($0) }
    }

    private static func parseHeaderDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        return headerDateFormatters.lazy.compactMap { $0.date(from: value) }.first
    }

    private static func displayDate(for date: Date, now: Date) -> String {
        let calendar = Calendar.autoupdatingCurrent
        if calendar.isDate(date, inSameDayAs: now) { return shortTimeFormatter.string(from: date) }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return monthDayFormatter.string(from: date)
        }
        return yearDateFormatter.string(from: date)
    }

    private static func messageTimestamp(for date: Date, now: Date) -> String {
        let calendar = Calendar.autoupdatingCurrent
        if calendar.isDate(date, inSameDayAs: now) { return "Today, \(shortTimeFormatter.string(from: date))" }
        if calendar.isDateInYesterday(date) { return "Yesterday, \(shortTimeFormatter.string(from: date))" }
        return yearDateFormatter.string(from: date)
    }

    private static func decodeBase64URL(_ value: String) -> Data? {
        var base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let padding = (4 - base64.count % 4) % 4
        base64.append(String(repeating: "=", count: padding))
        return Data(base64Encoded: base64, options: .ignoreUnknownCharacters)
    }

    static func decodeRFC2047(_ value: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "=\\?([^?]+)\\?([bBqQ])\\?([^?]+)\\?=") else { return value }
        var result = value
        let matches = regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).reversed()
        for match in matches {
            let source = value as NSString
            let charset = source.substring(with: match.range(at: 1))
            let encoding = source.substring(with: match.range(at: 2)).lowercased()
            let payload = source.substring(with: match.range(at: 3))
            let data: Data?
            if encoding == "b" {
                data = Data(base64Encoded: payload)
            } else {
                data = decodeQuotedPrintableWord(payload)
            }
            guard let data else { continue }
            let stringEncoding: String.Encoding = charset.lowercased().contains("iso-8859-1") ? .isoLatin1 : .utf8
            guard let decoded = String(data: data, encoding: stringEncoding), let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: decoded)
        }
        return result.replacingOccurrences(of: "?= =?", with: "?==?")
    }

    private static func decodeQuotedPrintableWord(_ value: String) -> Data? {
        let bytes = Array(value.replacingOccurrences(of: "_", with: " ").utf8)
        var output: [UInt8] = []
        var index = 0
        while index < bytes.count {
            if bytes[index] == 61, index + 2 < bytes.count,
               let high = hexValue(bytes[index + 1]), let low = hexValue(bytes[index + 2]) {
                output.append(high * 16 + low)
                index += 3
            } else {
                output.append(bytes[index])
                index += 1
            }
        }
        return Data(output)
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 48...57: byte - 48
        case 65...70: byte - 55
        case 97...102: byte - 87
        default: nil
        }
    }

    private static let shortTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        return formatter
    }()

    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    private static let yearDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()

    private static let headerDateFormatters: [DateFormatter] = {
        ["EEE, d MMM yyyy HH:mm:ss Z", "d MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm Z"].map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            return formatter
        }
    }()
}

enum MailPlainTextNormalizer {
    static func currentMessageText(_ value: String) -> String {
        let normalizedNewlines = value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return normalizeSoftWrappedParagraphs(trimQuotedReply(normalizedNewlines))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func trimQuotedReply(_ value: String) -> String {
        let lines = value.components(separatedBy: .newlines)
        let quotedIndex = lines.firstIndex { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(">") { return true }
            if trimmed.localizedCaseInsensitiveContains("wrote:") && trimmed.lowercased().hasPrefix("on ") { return true }
            if trimmed == "-----Original Message-----" { return true }
            return false
        }
        let kept = quotedIndex.map { Array(lines[..<$0]) } ?? lines
        return kept.joined(separator: "\n")
    }

    private static func normalizeSoftWrappedParagraphs(_ value: String) -> String {
        let lines = value.components(separatedBy: "\n")
        guard lines.count >= 3 else { return value }

        var normalized: [String] = []
        normalized.reserveCapacity(lines.count)
        var index = 0

        while index < lines.count {
            var currentLine = lines[index]

            while index + 2 < lines.count,
                  lines[index + 1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  shouldJoinSoftWrap(currentLine, with: lines[index + 2]) {
                currentLine += " " + lines[index + 2].trimmingCharacters(in: .whitespaces)
                index += 2
            }

            normalized.append(currentLine)
            index += 1
        }

        return normalized.joined(separator: "\n")
    }

    private static func shouldJoinSoftWrap(_ line: String, with followingLine: String) -> Bool {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        guard trimmedLine.count >= 56,
              let finalCharacter = trimmedLine.last,
              !".!?;:".contains(finalCharacter) else { return false }

        let next = followingLine.trimmingCharacters(in: .whitespaces)
        guard let firstCharacter = next.first else { return false }
        return firstCharacter.isLowercase || firstCharacter.isNumber
    }
}

enum MailHTMLNormalizer {
    private static let quoteExpressions = [
        #"(?is)<(?:div|blockquote)\b[^>]*(?:gmail_quote|gmail_extra|yahoo_quoted|protonmail_quote|moz-cite-prefix)[^>]*>"#,
        #"(?is)<blockquote\b[^>]*\btype\s*=\s*[\"']cite[\"'][^>]*>"#,
        #"(?is)<div\b[^>]*\bid\s*=\s*[\"'](?:divRplyFwdMsg|appendonsend)[\"'][^>]*>"#,
        #"(?is)<hr\b[^>]*\bid\s*=\s*[\"'](?:stopSpelling|replySplit)[\"'][^>]*>"#
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    private static let trailingExpressions = [
        #"(?is)(?:\s|&nbsp;|<br\b[^>]*>)+$"#,
        #"(?is)<(?:div|p|span)\b[^>]*>\s*(?:&nbsp;|<br\b[^>]*>)*\s*$"#,
        #"(?is)<(?:div|p|span)\b[^>]*>\s*(?:&nbsp;|<br\b[^>]*>)*\s*</(?:div|p|span)>(?=\s*(?:</(?:div|p|span)>)*\s*$)"#
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    static func currentMessageHTML(_ html: String) -> String {
        let source = html as NSString
        let firstQuoteLocation = quoteExpressions.compactMap { expression -> Int? in
            let range = expression.rangeOfFirstMatch(
                in: html,
                range: NSRange(location: 0, length: source.length)
            )
            return range.location == NSNotFound ? nil : range.location
        }.min()

        guard let firstQuoteLocation else { return html }
        var result = source.substring(to: firstQuoteLocation)

        while true {
            let before = result
            for expression in trailingExpressions {
                let range = NSRange(location: 0, length: (result as NSString).length)
                result = expression.stringByReplacingMatches(
                    in: result,
                    range: range,
                    withTemplate: ""
                )
            }
            guard result != before else { break }
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct HeaderCollection {
    private let values: [String: String]

    init(_ headers: [GmailMessageHeader]) {
        values = Dictionary(headers.map { ($0.name.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
    }

    subscript(_ name: String) -> String? { values[name.lowercased()] }
}

private extension String {
    func equalsEmail(_ other: String) -> Bool {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(other.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }
}
