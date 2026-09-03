import Foundation

struct RecipientSuggestion: Identifiable, Equatable, Sendable {
    let name: String
    let email: String
    let interactionCount: Int
    let wasPreviouslyEmailed: Bool
    let lastInteraction: Date

    var id: String { email.foldingForRecipientSearch }

    var formattedAddress: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              !trimmedName.matchesRecipientEmail(email),
              trimmedName.caseInsensitiveCompare("You") != .orderedSame else {
            return email
        }
        return "\(trimmedName) <\(email)>"
    }
}

struct RecipientAutocompleteIndex: Sendable {
    private struct Entry: Sendable {
        var name: String
        let email: String
        var interactionCount: Int
        var wasPreviouslyEmailed: Bool
        var lastInteraction: Date
    }

    private var entriesByEmail: [String: Entry] = [:]

    init(threads: [MailThread] = [], directory: [RecipientSuggestion] = []) {
        rebuild(threads: threads, directory: directory)
    }

    mutating func rebuild(
        threads: [MailThread],
        directory: [RecipientSuggestion] = []
    ) {
        entriesByEmail.removeAll(keepingCapacity: true)
        entriesByEmail.reserveCapacity(min(threads.count + directory.count, 32_768))
        for suggestion in directory { record(suggestion) }
        for thread in threads {
            record(thread)
        }
    }

    mutating func record(_ suggestion: RecipientSuggestion) {
        let email = suggestion.email.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedEmail = email.foldingForRecipientSearch
        guard Self.looksLikeEmail(email), normalizedEmail != "me" else { return }

        if var existing = entriesByEmail[normalizedEmail] {
            existing.interactionCount += max(1, suggestion.interactionCount)
            existing.wasPreviouslyEmailed = existing.wasPreviouslyEmailed || suggestion.wasPreviouslyEmailed
            if suggestion.lastInteraction >= existing.lastInteraction {
                existing.lastInteraction = suggestion.lastInteraction
                if !suggestion.name.isEmpty { existing.name = suggestion.name }
            }
            entriesByEmail[normalizedEmail] = existing
        } else {
            entriesByEmail[normalizedEmail] = Entry(
                name: suggestion.name,
                email: email,
                interactionCount: max(1, suggestion.interactionCount),
                wasPreviouslyEmailed: suggestion.wasPreviouslyEmailed,
                lastInteraction: suggestion.lastInteraction
            )
        }
    }

    mutating func record(_ thread: MailThread) {
        let email = thread.email.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedEmail = email.foldingForRecipientSearch
        guard Self.looksLikeEmail(email), normalizedEmail != "me" else { return }

        let candidateName = Self.usefulName(thread.sender, email: email)
        let previouslyEmailed = thread.folder == .sent
            || thread.labels.contains(.sent)
            || thread.gmailLabelIDs.contains("SENT")

        if var existing = entriesByEmail[normalizedEmail] {
            existing.interactionCount += 1
            existing.wasPreviouslyEmailed = existing.wasPreviouslyEmailed || previouslyEmailed
            if thread.date >= existing.lastInteraction {
                existing.lastInteraction = thread.date
                if !candidateName.isEmpty { existing.name = candidateName }
            } else if existing.name.isEmpty, !candidateName.isEmpty {
                existing.name = candidateName
            }
            entriesByEmail[normalizedEmail] = existing
        } else {
            entriesByEmail[normalizedEmail] = Entry(
                name: candidateName,
                email: email,
                interactionCount: 1,
                wasPreviouslyEmailed: previouslyEmailed,
                lastInteraction: thread.date
            )
        }
    }

    func suggestions(matching rawValue: String, limit: Int = 6) -> [RecipientSuggestion] {
        let query = Self.activeRecipientToken(in: rawValue).foldingForRecipientSearch
        guard !query.isEmpty else { return [] }

        return entriesByEmail.values.compactMap { entry -> (RecipientSuggestion, Int)? in
            let name = entry.name.foldingForRecipientSearch
            let email = entry.email.foldingForRecipientSearch
            let localPart = email.split(separator: "@", maxSplits: 1).first.map(String.init) ?? email

            let matchScore: Int
            if email == query || name == query { matchScore = 1_000 }
            else if name.hasPrefix(query) { matchScore = 700 }
            else if name.split(separator: " ").contains(where: { $0.hasPrefix(query) }) { matchScore = 620 }
            else if localPart.hasPrefix(query) { matchScore = 580 }
            else if email.hasPrefix(query) { matchScore = 540 }
            else if name.contains(query) { matchScore = 400 }
            else if email.contains(query) { matchScore = 360 }
            else { return nil }

            let relationshipScore = entry.wasPreviouslyEmailed ? 80 : 0
            let frequencyScore = min(entry.interactionCount, 20) * 3
            return (
                RecipientSuggestion(
                    name: entry.name,
                    email: entry.email,
                    interactionCount: entry.interactionCount,
                    wasPreviouslyEmailed: entry.wasPreviouslyEmailed,
                    lastInteraction: entry.lastInteraction
                ),
                matchScore + relationshipScore + frequencyScore
            )
        }
        .sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            if lhs.0.lastInteraction != rhs.0.lastInteraction {
                return lhs.0.lastInteraction > rhs.0.lastInteraction
            }
            return lhs.0.email.localizedCaseInsensitiveCompare(rhs.0.email) == .orderedAscending
        }
        .prefix(max(1, limit))
        .map(\.0)
    }

    static func replacingActiveRecipient(
        in rawValue: String,
        with suggestion: RecipientSuggestion
    ) -> String {
        guard let delimiter = rawValue.lastIndex(where: { $0 == "," || $0 == ";" }) else {
            return suggestion.formattedAddress
        }

        let prefixEnd = rawValue.index(after: delimiter)
        let prefix = rawValue[..<prefixEnd].trimmingCharacters(in: .whitespaces)
        return "\(prefix) \(suggestion.formattedAddress)"
    }

    static func activeRecipientToken(in rawValue: String) -> String {
        let suffix: Substring
        if let delimiter = rawValue.lastIndex(where: { $0 == "," || $0 == ";" }) {
            suffix = rawValue[rawValue.index(after: delimiter)...]
        } else {
            suffix = rawValue[...]
        }
        return suffix.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func usefulName(_ rawName: String, email: String) -> String {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              name.caseInsensitiveCompare("You") != .orderedSame,
              !name.matchesRecipientEmail(email) else { return "" }
        return name
    }

    static func looksLikeEmail(_ value: String) -> Bool {
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".")
    }
}

private extension String {
    var foldingForRecipientSearch: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func matchesRecipientEmail(_ other: String) -> Bool {
        foldingForRecipientSearch == other.foldingForRecipientSearch
    }
}
