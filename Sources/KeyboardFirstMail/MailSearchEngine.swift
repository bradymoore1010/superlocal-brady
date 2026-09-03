import Foundation

struct SearchResult: Equatable, Sendable {
    let thread: MailThread
    let score: Int
}

enum MailSearchEngine {
    struct IndexedResult: Equatable, Sendable {
        let threadID: String
        let score: Int
        let date: Date
    }

    /// A compact, reusable representation of the searchable mailbox. Expensive
    /// Unicode folding and body assembly happen only when a thread changes, not
    /// on every keystroke or SwiftUI body evaluation.
    struct Index: Sendable {
        fileprivate struct Document: Sendable {
            let id: String
            let date: Date
            let sender: String
            let subject: String
            let preview: String
            let senderWords: [String]
            let subjectWords: [String]
            let bodyTerms: Set<String>
            let bodyTrigrams: Set<UInt32>
            let labels: [String]
            let isUnread: Bool
            let isStarred: Bool
            let hasAttachment: Bool
        }

        private var documents: [Document] = []
        private var offsetsByID: [String: Int] = [:]
        private var senderWordPostings: [String: [Int]] = [:]
        private var subjectWordPostings: [String: [Int]] = [:]
        private var trigramPostings: [UInt32: [Int]] = [:]
        private var hasAccurateWordPostings = true
        private var hasAccurateTrigramPostings = true

        init(threads: [MailThread] = []) {
            replaceAll(with: threads)
        }

        mutating func replaceAll(with threads: [MailThread]) {
            documents = threads.map(Self.document).sorted { $0.date > $1.date }
            rebuildOffsets()
            rebuildWordPostings()
            rebuildTrigramPostings()
        }

        mutating func update(_ thread: MailThread) {
            let replacement = Self.document(for: thread)
            if let offset = offsetsByID[thread.id], documents.indices.contains(offset) {
                let dateChanged = documents[offset].date != replacement.date
                documents[offset] = replacement
                if dateChanged {
                    documents.sort { $0.date > $1.date }
                    rebuildOffsets()
                }
            } else {
                let insertion = documents.firstIndex { $0.date < replacement.date } ?? documents.endIndex
                documents.insert(replacement, at: insertion)
                rebuildOffsets()
            }
            hasAccurateWordPostings = false
            hasAccurateTrigramPostings = false
        }

        mutating func updateMetadata(for thread: MailThread) {
            guard let offset = offsetsByID[thread.id], documents.indices.contains(offset) else {
                update(thread)
                return
            }
            let previous = documents[offset]
            documents[offset] = Document(
                id: thread.id,
                date: thread.date,
                sender: previous.sender,
                subject: previous.subject,
                preview: previous.preview,
                senderWords: previous.senderWords,
                subjectWords: previous.subjectWords,
                bodyTerms: previous.bodyTerms,
                bodyTrigrams: previous.bodyTrigrams,
                labels: thread.labels.map { MailSearchEngine.normalize($0.rawValue) },
                isUnread: thread.isUnread,
                isStarred: thread.isStarred,
                hasAttachment: thread.hasAttachment
            )
        }

        mutating func remove(threadID: String) {
            guard let offset = offsetsByID[threadID], documents.indices.contains(offset) else { return }
            documents.remove(at: offset)
            rebuildOffsets()
            hasAccurateWordPostings = false
            hasAccurateTrigramPostings = false
        }

        func search(
            _ query: String,
            allowedThreadIDs: Set<String>? = nil,
            limit: Int? = nil
        ) -> [IndexedResult] {
            let parsed = MailSearchEngine.parse(query)
            let maximum = limit.map { max(0, $0) }
            if maximum == 0 { return [] }

            if parsed.isEmpty {
                let matches = documents.lazy.compactMap { document -> IndexedResult? in
                    guard allowedThreadIDs?.contains(document.id) ?? true else { return nil }
                    return IndexedResult(threadID: document.id, score: 0, date: document.date)
                }
                if let maximum { return Array(matches.prefix(maximum)) }
                return Array(matches)
            }

            if let maximum,
               let fastResults = highRankPrefixResults(
                   for: parsed,
                   maximum: maximum,
                   allowedThreadIDs: allowedThreadIDs
               ) {
                return fastResults
            }

            var matches: [IndexedResult] = []
            if let maximum { matches.reserveCapacity(maximum) }

            let candidateOffsets = trigramCandidateOffsets(for: parsed)
            let offsets = candidateOffsets ?? Array(documents.indices)
            for offset in offsets {
                guard documents.indices.contains(offset) else { continue }
                let document = documents[offset]
                guard allowedThreadIDs?.contains(document.id) ?? true,
                      let score = MailSearchEngine.score(document, for: parsed) else { continue }

                let result = IndexedResult(threadID: document.id, score: score, date: document.date)
                if let maximum {
                    let insertion = matches.firstIndex { MailSearchEngine.outranks(result, $0) }
                        ?? matches.endIndex
                    if insertion < maximum {
                        matches.insert(result, at: insertion)
                        if matches.count > maximum { matches.removeLast() }
                    } else if matches.count < maximum {
                        matches.append(result)
                    }
                } else {
                    matches.append(result)
                }
            }

            if maximum == nil {
                matches.sort(by: MailSearchEngine.outranks)
            }
            return matches
        }

        private mutating func rebuildOffsets() {
            offsetsByID = Dictionary(
                uniqueKeysWithValues: documents.enumerated().map { ($0.element.id, $0.offset) }
            )
        }

        /// Command-K commonly searches a sender or a subject word. A word
        /// prefix scores above every body/preview-only match, so once this path
        /// finds a full top-k it can return the exact ranked result without a
        /// 10,000-document scan. Substring-only queries retain the full scan.
        private func highRankPrefixResults(
            for query: ParsedQuery,
            maximum: Int,
            allowedThreadIDs: Set<String>?
        ) -> [IndexedResult]? {
            guard hasAccurateWordPostings,
                  maximum > 0,
                  query.general.count == 1,
                  let term = query.general.first else { return nil }

            var candidateOffsets = Set<Int>()
            for (word, offsets) in senderWordPostings where word.hasPrefix(term) {
                candidateOffsets.formUnion(offsets)
            }
            for (word, offsets) in subjectWordPostings where word.hasPrefix(term) {
                candidateOffsets.formUnion(offsets)
            }
            guard candidateOffsets.count >= maximum else { return nil }

            var matches: [IndexedResult] = []
            matches.reserveCapacity(candidateOffsets.count)
            for offset in candidateOffsets {
                guard documents.indices.contains(offset) else { continue }
                let document = documents[offset]
                guard allowedThreadIDs?.contains(document.id) ?? true,
                      let score = MailSearchEngine.score(document, for: query) else { continue }
                matches.append(IndexedResult(
                    threadID: document.id,
                    score: score,
                    date: document.date
                ))
            }
            guard matches.count >= maximum else { return nil }
            matches.sort(by: MailSearchEngine.outranks)
            return Array(matches.prefix(maximum))
        }

        private mutating func rebuildWordPostings() {
            senderWordPostings.removeAll(keepingCapacity: true)
            subjectWordPostings.removeAll(keepingCapacity: true)
            for (offset, document) in documents.enumerated() {
                for word in Set(document.senderWords) {
                    senderWordPostings[word, default: []].append(offset)
                }
                for word in Set(document.subjectWords) {
                    subjectWordPostings[word, default: []].append(offset)
                }
            }
            hasAccurateWordPostings = true
        }

        /// Every substring match must contain every ASCII trigram in the query.
        /// Intersecting those postings eliminates unrelated documents before
        /// the more expressive ranking logic runs, while retaining substring
        /// semantics for sender, subject, preview, and body terms.
        private func trigramCandidateOffsets(for query: ParsedQuery) -> [Int]? {
            guard hasAccurateTrigramPostings else { return nil }
            let queryTrigrams = query.general.flatMap(MailSearchEngine.asciiTrigrams(in:))
            guard !queryTrigrams.isEmpty else { return nil }

            let orderedPostings = Set(queryTrigrams)
                .map { trigramPostings[$0] ?? [] }
                .sorted { $0.count < $1.count }
            guard let first = orderedPostings.first else { return nil }
            var candidates = Set(first)
            for postings in orderedPostings.dropFirst() where !candidates.isEmpty {
                candidates.formIntersection(postings)
            }
            return Array(candidates)
        }

        private mutating func rebuildTrigramPostings() {
            trigramPostings.removeAll(keepingCapacity: true)
            for (offset, document) in documents.enumerated() {
                var trigrams = document.bodyTrigrams
                trigrams.formUnion(MailSearchEngine.asciiTrigrams(in: document.sender))
                trigrams.formUnion(MailSearchEngine.asciiTrigrams(in: document.subject))
                trigrams.formUnion(MailSearchEngine.asciiTrigrams(in: document.preview))
                for trigram in trigrams {
                    trigramPostings[trigram, default: []].append(offset)
                }
            }
            hasAccurateTrigramPostings = true
        }

        private static func document(for thread: MailThread) -> Document {
            let sender = MailSearchEngine.normalize("\(thread.sender) \(thread.email)")
            let subject = MailSearchEngine.normalize(thread.subject)
            let bodyTerms = MailSearchEngine.bodyTerms(in: thread)
            return Document(
                id: thread.id,
                date: thread.date,
                sender: sender,
                subject: subject,
                preview: MailSearchEngine.normalize(thread.displayPreview),
                senderWords: MailSearchEngine.words(in: sender),
                subjectWords: MailSearchEngine.words(in: subject),
                bodyTerms: bodyTerms,
                bodyTrigrams: MailSearchEngine.asciiTrigrams(in: bodyTerms),
                labels: thread.labels.map { MailSearchEngine.normalize($0.rawValue) },
                isUnread: thread.isUnread,
                isStarred: thread.isStarred,
                hasAttachment: thread.hasAttachment
            )
        }
    }

    private struct ParsedQuery {
        var general: [String] = []
        var senders: [String] = []
        var subjects: [String] = []
        var labels: [String] = []
        var unread: Bool?
        var starred: Bool?
        var hasAttachment: Bool?

        var isEmpty: Bool {
            general.isEmpty && senders.isEmpty && subjects.isEmpty && labels.isEmpty
                && unread == nil && starred == nil && hasAttachment == nil
        }
    }

    static func search(_ query: String, in threads: [MailThread]) -> [SearchResult] {
        let threadsByID = Dictionary(uniqueKeysWithValues: threads.map { ($0.id, $0) })
        return Index(threads: threads).search(query).compactMap { match in
            threadsByID[match.threadID].map { SearchResult(thread: $0, score: match.score) }
        }
    }

    static func normalize(_ value: String) -> String {
        if value.utf8.allSatisfy({ $0 < 0x80 }) {
            return value.lowercased()
        }
        return value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
    }

    private static func parse(_ query: String) -> ParsedQuery {
        var parsed = ParsedQuery()

        for rawToken in lex(query) {
            let token = normalize(rawToken)
            if token.hasPrefix("from:") {
                appendValue(from: token, prefix: "from:", to: &parsed.senders)
            } else if token.hasPrefix("subject:") {
                appendValue(from: token, prefix: "subject:", to: &parsed.subjects)
            } else if token.hasPrefix("label:") {
                appendValue(from: token, prefix: "label:", to: &parsed.labels)
            } else if token == "is:unread" {
                parsed.unread = true
            } else if token == "is:read" {
                parsed.unread = false
            } else if token == "is:starred" {
                parsed.starred = true
            } else if token == "is:unstarred" {
                parsed.starred = false
            } else if token == "has:attachment" {
                parsed.hasAttachment = true
            } else if token == "has:noattachment" {
                parsed.hasAttachment = false
            } else if !token.isEmpty {
                parsed.general.append(token)
            }
        }

        return parsed
    }

    private static func appendValue(from token: String, prefix: String, to values: inout [String]) {
        let value = String(token.dropFirst(prefix.count))
        if !value.isEmpty { values.append(value) }
    }

    private static func lex(_ query: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var isQuoted = false

        for character in query {
            if character == "\"" {
                isQuoted.toggle()
            } else if character.isWhitespace && !isQuoted {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            } else {
                current.append(character)
            }
        }

        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    private static func score(_ document: Index.Document, for query: ParsedQuery) -> Int? {
        if let unread = query.unread, document.isUnread != unread { return nil }
        if let starred = query.starred, document.isStarred != starred { return nil }
        if let hasAttachment = query.hasAttachment, document.hasAttachment != hasAttachment { return nil }

        guard query.senders.allSatisfy(document.sender.contains) else { return nil }
        guard query.subjects.allSatisfy(document.subject.contains) else { return nil }
        guard query.labels.allSatisfy({ term in document.labels.contains(where: { $0.contains(term) }) }) else { return nil }

        var total = query.senders.count * 80 + query.subjects.count * 80 + query.labels.count * 30

        for term in query.general {
            let termScore = score(term: term, in: document)
            guard termScore > 0 else { return nil }
            total += termScore
        }

        if document.isUnread { total += 2 }
        if document.isStarred { total += 1 }
        return total
    }

    private static func score(term: String, in document: Index.Document) -> Int {
        var best = 0

        if document.sender == term || document.subject == term { best = max(best, 120) }
        if document.sender.hasPrefix(term) || document.subject.hasPrefix(term) { best = max(best, 90) }
        if document.senderWords.contains(where: { $0.hasPrefix(term) }) { best = max(best, 72) }
        if document.subjectWords.contains(where: { $0.hasPrefix(term) }) { best = max(best, 68) }
        if document.sender.contains(term) { best = max(best, 58) }
        if document.subject.contains(term) { best = max(best, 54) }
        if document.preview.contains(term) { best = max(best, 30) }
        if best == 0, bodyContains(term, in: document) { best = 18 }

        return best
    }

    private static func words(in value: String) -> [String] {
        value.split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    private static func bodyTerms(in thread: MailThread) -> Set<String> {
        var rawValues = Set<String>()
        for message in thread.messages {
            rawValues.insert(message.body)
            rawValues.formUnion(message.attachmentNames)
            rawValues.formUnion(message.inlineImages.map(\.name))
        }

        var terms = Set<String>()
        for value in rawValues {
            terms.formUnion(words(in: normalize(value)))
        }
        return terms
    }

    private static func bodyContains(_ term: String, in document: Index.Document) -> Bool {
        if document.bodyTerms.contains(term) { return true }
        if let trigram = firstASCIITrigram(in: term), !document.bodyTrigrams.contains(trigram) {
            return false
        }
        return document.bodyTerms.contains { $0.contains(term) }
    }

    private static func asciiTrigrams(in terms: Set<String>) -> Set<UInt32> {
        var result = Set<UInt32>()
        for term in terms {
            let bytes = Array(term.utf8)
            guard bytes.count >= 3, bytes.allSatisfy({ $0 < 0x80 }) else { continue }
            for index in 0...(bytes.count - 3) {
                result.insert(pack(bytes[index], bytes[index + 1], bytes[index + 2]))
            }
        }
        return result
    }

    private static func asciiTrigrams(in value: String) -> Set<UInt32> {
        let bytes = Array(value.utf8)
        guard bytes.count >= 3, bytes.allSatisfy({ $0 < 0x80 }) else { return [] }
        var result = Set<UInt32>()
        result.reserveCapacity(bytes.count - 2)
        for index in 0...(bytes.count - 3) {
            result.insert(pack(bytes[index], bytes[index + 1], bytes[index + 2]))
        }
        return result
    }

    private static func firstASCIITrigram(in term: String) -> UInt32? {
        let bytes = Array(term.utf8)
        guard bytes.count >= 3, bytes.prefix(3).allSatisfy({ $0 < 0x80 }) else { return nil }
        return pack(bytes[0], bytes[1], bytes[2])
    }

    private static func pack(_ first: UInt8, _ second: UInt8, _ third: UInt8) -> UInt32 {
        UInt32(first) << 16 | UInt32(second) << 8 | UInt32(third)
    }

    private static func outranks(_ left: IndexedResult, _ right: IndexedResult) -> Bool {
        if left.score == right.score { return left.date > right.date }
        return left.score > right.score
    }
}
