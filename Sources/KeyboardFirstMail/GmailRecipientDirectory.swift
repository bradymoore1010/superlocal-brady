import Foundation

struct GmailRecipientDirectorySnapshot: Equatable, Sendable {
    let entries: [RecipientSuggestion]
    let syncedAt: Date?
}

struct MailboxAddress: Equatable, Sendable {
    let displayName: String
    let address: String
    let hasExplicitDisplayName: Bool

    init(displayName: String, address: String, hasExplicitDisplayName: Bool = false) {
        self.displayName = displayName
        self.address = address
        self.hasExplicitDisplayName = hasExplicitDisplayName
    }

    static func parse(_ rawValue: String) -> MailboxAddress {
        let value = GmailMessageParser.decodeRFC2047(rawValue)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let open = value.lastIndex(of: "<"), let close = value[open...].firstIndex(of: ">") {
            let email = cleanEmail(String(value[value.index(after: open)..<close]))
            let rawName = String(value[..<open])
                .trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
            return MailboxAddress(
                displayName: rawName.isEmpty ? fallbackName(for: email) : rawName,
                address: email,
                hasExplicitDisplayName: !rawName.isEmpty
            )
        }

        let tokens = value.split(whereSeparator: { $0.isWhitespace })
        if let rawEmail = tokens.last.map(String.init), rawEmail.contains("@") {
            let email = cleanEmail(rawEmail)
            let rawName = tokens.dropLast().joined(separator: " ")
                .trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
            return MailboxAddress(
                displayName: rawName.isEmpty ? fallbackName(for: email) : rawName,
                address: email,
                hasExplicitDisplayName: !rawName.isEmpty
            )
        }

        let email = cleanEmail(value)
        return MailboxAddress(
            displayName: fallbackName(for: email),
            address: email,
            hasExplicitDisplayName: false
        )
    }

    static func parseList(_ rawValue: String) -> [MailboxAddress] {
        var values: [String] = []
        var current = ""
        var angleDepth = 0
        var quoted = false

        for character in rawValue {
            if character == "\"" { quoted.toggle() }
            if !quoted {
                if character == "<" { angleDepth += 1 }
                if character == ">" { angleDepth = max(0, angleDepth - 1) }
            }
            if (character == "," || character == ";"), !quoted, angleDepth == 0 {
                values.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { values.append(current) }
        return values.map(parse).filter {
            RecipientAutocompleteIndex.looksLikeEmail($0.address)
        }
    }

    private static func cleanEmail(_ rawValue: String) -> String {
        var value = rawValue.trimmingCharacters(
            in: CharacterSet(charactersIn: " \t\r\n\"'<>[](),:;")
        )
        if value.lowercased().hasPrefix("mailto:") { value.removeFirst("mailto:".count) }
        return value
    }

    private static func fallbackName(for email: String) -> String {
        let localPart = email.split(separator: "@").first.map(String.init) ?? email
        return localPart
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

struct GmailRecipientDirectoryBuilder: Sendable {
    private struct Entry: Sendable {
        var name: String
        var email: String
        var hasExplicitName: Bool
        var interactionCount: Int
        var wasPreviouslyEmailed: Bool
        var lastInteraction: Date
    }

    private var entriesByEmail: [String: Entry] = [:]
    private var selfEmailKeys: Set<String>

    init(accountEmail: String) {
        selfEmailKeys = [Self.emailKey(accountEmail)]
    }

    mutating func record(_ thread: GmailThreadPayload) {
        for message in thread.messages ?? [] { record(message) }
    }

    mutating func record(_ message: GmailMessagePayload) {
        let headers = Dictionary(
            (message.payload?.headers ?? []).map { ($0.name.lowercased(), $0.value) },
            uniquingKeysWith: { first, _ in first }
        )
        let from = MailboxAddress.parseList(headers["from"] ?? "")
        let wasSent = Set(message.labelIds ?? []).contains("SENT")
        if wasSent {
            for address in from {
                let key = Self.emailKey(address.address)
                selfEmailKeys.insert(key)
                entriesByEmail[key] = nil
            }
        }

        let candidates = from
            + MailboxAddress.parseList(headers["to"] ?? "")
            + MailboxAddress.parseList(headers["cc"] ?? "")
            + MailboxAddress.parseList(headers["bcc"] ?? "")
            + MailboxAddress.parseList(headers["reply-to"] ?? "")
        let date = message.internalDate
            .flatMap(Double.init)
            .map { Date(timeIntervalSince1970: $0 / 1_000) }
            ?? .distantPast

        var uniqueCandidates: [String: MailboxAddress] = [:]
        for candidate in candidates {
            let key = Self.emailKey(candidate.address)
            guard !key.isEmpty, !selfEmailKeys.contains(key) else { continue }
            if uniqueCandidates[key]?.hasExplicitDisplayName != true
                || candidate.hasExplicitDisplayName {
                uniqueCandidates[key] = candidate
            }
        }

        for (key, candidate) in uniqueCandidates {
            if var existing = entriesByEmail[key] {
                existing.interactionCount += 1
                existing.wasPreviouslyEmailed = existing.wasPreviouslyEmailed || wasSent
                if date > existing.lastInteraction { existing.lastInteraction = date }
                if candidate.hasExplicitDisplayName,
                   (!existing.hasExplicitName || date >= existing.lastInteraction) {
                    existing.name = candidate.displayName
                    existing.email = candidate.address
                    existing.hasExplicitName = true
                }
                entriesByEmail[key] = existing
            } else {
                entriesByEmail[key] = Entry(
                    name: candidate.displayName,
                    email: candidate.address,
                    hasExplicitName: candidate.hasExplicitDisplayName,
                    interactionCount: 1,
                    wasPreviouslyEmailed: wasSent,
                    lastInteraction: date
                )
            }
        }
    }

    var entries: [RecipientSuggestion] {
        entriesByEmail.values.map { entry in
            RecipientSuggestion(
                name: entry.name,
                email: entry.email,
                interactionCount: entry.interactionCount,
                wasPreviouslyEmailed: entry.wasPreviouslyEmailed,
                lastInteraction: entry.lastInteraction
            )
        }
    }

    private static func emailKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
