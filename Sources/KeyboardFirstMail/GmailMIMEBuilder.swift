import Foundation
import UniformTypeIdentifiers

struct GmailOutgoingDraft: Sendable {
    let to: String
    let subject: String
    let draftBody: String
    let attachments: [DraftAttachment]
    let inlineImages: [InlineDraftImage]
    let inReplyTo: String?
    let references: String?
}

enum GmailMIMEBuilder {
    static func rawMessage(from draft: GmailOutgoingDraft) throws -> String {
        let plainText = MailDraftSerializer.outgoingText(from: draft.draftBody, inlineImages: draft.inlineImages)
        let inlineParts = draft.inlineImages.enumerated().map { index, image in
            InlinePart(image: image, contentID: "mail-image-\(index)-\(image.id.uuidString.lowercased())")
        }
        let html = htmlBody(from: draft.draftBody, inlineParts: inlineParts)
        let content = alternativeBody(plainText: plainText, html: html)
        let relatedContent = inlineParts.isEmpty ? content : relatedBody(content: content, inlineParts: inlineParts)
        let completeBody = draft.attachments.isEmpty
            ? relatedContent
            : try mixedBody(content: relatedContent, attachments: draft.attachments)

        var headers = [
            "To: \(sanitizedHeaderValue(draft.to))",
            "Subject: \(encodedHeader(sanitizedHeaderValue(draft.subject)))",
            "Date: \(dateFormatter.string(from: Date()))",
            "Message-ID: <\(UUID().uuidString.lowercased())@keyboardfirstmail.local>",
            "MIME-Version: 1.0"
        ]
        if let inReplyTo = draft.inReplyTo?.trimmingCharacters(in: .whitespacesAndNewlines), !inReplyTo.isEmpty {
            let safeInReplyTo = sanitizedHeaderValue(inReplyTo)
            headers.append("In-Reply-To: \(safeInReplyTo)")
            let existing = sanitizedHeaderValue(draft.references?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
            headers.append("References: \([existing, safeInReplyTo].filter { !$0.isEmpty }.joined(separator: " "))")
        }
        headers.append(completeBody.contentTypeHeader)

        let message = (headers + ["", completeBody.body]).joined(separator: "\r\n")
        return GmailOAuthCoordinator.base64URL(Data(message.utf8))
    }

    private struct MIMEBody {
        let contentTypeHeader: String
        let body: String
    }

    private struct InlinePart {
        let image: InlineDraftImage
        let contentID: String
    }

    private static func alternativeBody(plainText: String, html: String) -> MIMEBody {
        let boundary = "mail-alternative-\(UUID().uuidString)"
        let body = [
            "--\(boundary)",
            "Content-Type: text/plain; charset=utf-8",
            "Content-Transfer-Encoding: base64",
            "",
            wrappedBase64(Data(plainText.utf8)),
            "--\(boundary)",
            "Content-Type: text/html; charset=utf-8",
            "Content-Transfer-Encoding: base64",
            "",
            wrappedBase64(Data(html.utf8)),
            "--\(boundary)--"
        ].joined(separator: "\r\n")
        return MIMEBody(
            contentTypeHeader: "Content-Type: multipart/alternative; boundary=\"\(boundary)\"",
            body: body
        )
    }

    private static func relatedBody(content: MIMEBody, inlineParts: [InlinePart]) -> MIMEBody {
        let boundary = "mail-related-\(UUID().uuidString)"
        var sections = [
            "--\(boundary)",
            content.contentTypeHeader,
            "",
            content.body
        ]

        for part in inlineParts {
            let mimeType = UTType(filenameExtension: part.image.url.pathExtension)?.preferredMIMEType ?? "image/png"
            sections.append(contentsOf: [
                "--\(boundary)",
                "Content-Type: \(mimeType); name=\"\(safeFilename(part.image.name))\"",
                "Content-Transfer-Encoding: base64",
                "Content-ID: <\(part.contentID)>",
                "Content-Disposition: inline; filename=\"\(safeFilename(part.image.name))\"",
                "",
                wrappedBase64(part.image.data)
            ])
        }
        sections.append("--\(boundary)--")
        return MIMEBody(
            contentTypeHeader: "Content-Type: multipart/related; boundary=\"\(boundary)\"",
            body: sections.joined(separator: "\r\n")
        )
    }

    private static func mixedBody(content: MIMEBody, attachments: [DraftAttachment]) throws -> MIMEBody {
        let boundary = "mail-mixed-\(UUID().uuidString)"
        var sections = [
            "--\(boundary)",
            content.contentTypeHeader,
            "",
            content.body
        ]
        for attachment in attachments {
            let didStartAccessing = attachment.url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing { attachment.url.stopAccessingSecurityScopedResource() }
            }
            guard let data = try? Data(contentsOf: attachment.url) else {
                throw GmailIntegrationError.attachmentUnreadable(attachment.name)
            }
            let mimeType = UTType(filenameExtension: attachment.url.pathExtension)?.preferredMIMEType
                ?? "application/octet-stream"
            sections.append(contentsOf: [
                "--\(boundary)",
                "Content-Type: \(mimeType); name=\"\(safeFilename(attachment.name))\"",
                "Content-Transfer-Encoding: base64",
                "Content-Disposition: attachment; filename=\"\(safeFilename(attachment.name))\"",
                "",
                wrappedBase64(data)
            ])
        }
        sections.append("--\(boundary)--")
        return MIMEBody(
            contentTypeHeader: "Content-Type: multipart/mixed; boundary=\"\(boundary)\"",
            body: sections.joined(separator: "\r\n")
        )
    }

    private static func htmlBody(from draft: String, inlineParts: [InlinePart]) -> String {
        var imageIndex = 0
        let lines = MailDraftSerializer.normalizedBody(from: draft).components(separatedBy: "\n")
        let rendered = lines.map { line -> String in
            var content = ""
            let segments = line.components(separatedBy: MailDraftSerializer.inlineImageMarker)
            for index in segments.indices {
                content += linkifiedHTML(segments[index])
                if index < segments.count - 1, inlineParts.indices.contains(imageIndex) {
                    let part = inlineParts[imageIndex]
                    content += "<img src=\"cid:\(part.contentID)\" alt=\"\(escapeHTML(part.image.name))\" style=\"display:block;max-width:\(Int(part.image.displaySize.maximumSize.width))px;height:auto;margin:10px 0;border-radius:8px\">"
                    imageIndex += 1
                }
            }
            return content.isEmpty ? "<div><br></div>" : "<div>\(content)</div>"
        }.joined()
        return "<!doctype html><html><body style=\"margin:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;font-size:14px;line-height:1.5;color:#171717;white-space:pre-wrap\">\(rendered)</body></html>"
    }

    private static func encodedHeader(_ value: String) -> String {
        guard !value.canBeConverted(to: .ascii) else { return value }
        return "=?UTF-8?B?\(Data(value.utf8).base64EncodedString())?="
    }

    private static func safeFilename(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "_").replacingOccurrences(of: "\"", with: "_")
    }

    private static func sanitizedHeaderValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private static func wrappedBase64(_ data: Data) -> String {
        let base64 = data.base64EncodedString()
        return stride(from: 0, to: base64.count, by: 76).map { offset in
            let start = base64.index(base64.startIndex, offsetBy: offset)
            let end = base64.index(start, offsetBy: min(76, base64.distance(from: start, to: base64.endIndex)))
            return String(base64[start..<end])
        }.joined(separator: "\r\n")
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func linkifiedHTML(_ value: String) -> String {
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue
        ) else { return escapeHTML(value) }

        let source = value as NSString
        let matches = detector.matches(
            in: value,
            range: NSRange(location: 0, length: source.length)
        )
        guard !matches.isEmpty else { return escapeHTML(value) }

        var result = ""
        var cursor = 0
        for match in matches {
            guard let url = match.url, match.range.location >= cursor else { continue }
            result += escapeHTML(source.substring(with: NSRange(
                location: cursor,
                length: match.range.location - cursor
            )))
            let label = escapeHTML(source.substring(with: match.range))
            let target = escapeHTML(url.absoluteString)
            result += "<a href=\"\(target)\" style=\"color:#292929;text-decoration:underline\">\(label)</a>"
            cursor = NSMaxRange(match.range)
        }
        if cursor < source.length {
            result += escapeHTML(source.substring(from: cursor))
        }
        return result
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "EEE, d MMM yyyy HH:mm:ss Z"
        return formatter
    }()
}
