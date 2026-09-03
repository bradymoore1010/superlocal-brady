import Foundation

enum MailEditorCommand: String, CaseIterable, Sendable {
    case bulletList
    case dashList
    case numberedList
    case outdent
    case indent

    var title: String {
        switch self {
        case .bulletList: "Bulleted list"
        case .dashList: "Dash list"
        case .numberedList: "Numbered list"
        case .outdent: "Decrease indent"
        case .indent: "Increase indent"
        }
    }

    var systemImage: String {
        switch self {
        case .bulletList: "list.bullet"
        case .dashList: "minus"
        case .numberedList: "list.number"
        case .outdent: "decrease.indent"
        case .indent: "increase.indent"
        }
    }

    var shortcut: String {
        switch self {
        case .bulletList: "⇧⌘8"
        case .dashList: ""
        case .numberedList: "⇧⌘7"
        case .outdent: "⌘["
        case .indent: "⌘]"
        }
    }
}

struct MailEditorRequest: Equatable, Sendable {
    let id = UUID()
    let command: MailEditorCommand
}

struct MailTextEdit: Equatable, Sendable {
    let range: NSRange
    let replacement: String
    let selection: NSRange
}

enum MailLineFormatter {
    static func commandBackspace(in text: String, selection: NSRange) -> MailTextEdit? {
        let source = text as NSString
        let location = min(max(selection.location, 0), source.length)

        if selection.length > 0 {
            let length = min(selection.length, source.length - location)
            return MailTextEdit(
                range: NSRange(location: location, length: length),
                replacement: "",
                selection: NSRange(location: location, length: 0)
            )
        }

        guard location > 0 else { return nil }

        let currentLine = source.lineRange(for: NSRange(location: location, length: 0))
        let deleteStart: Int
        if location > currentLine.location {
            deleteStart = currentLine.location
        } else {
            let previousLine = source.lineRange(for: NSRange(location: location - 1, length: 0))
            deleteStart = previousLine.location
        }

        guard deleteStart < location else { return nil }
        return MailTextEdit(
            range: NSRange(location: deleteStart, length: location - deleteStart),
            replacement: "",
            selection: NSRange(location: deleteStart, length: 0)
        )
    }

    static func apply(
        _ command: MailEditorCommand,
        to text: String,
        selection: NSRange
    ) -> MailTextEdit? {
        let source = text as NSString
        let safeSelection = clamped(selection, to: source.length)
        let selectedLines = source.lineRange(for: safeSelection)
        let segment = source.substring(with: selectedLines)
        let lines = segment.components(separatedBy: "\n")
        let hasTrailingSentinel = segment.hasSuffix("\n")
        let transformCount = max(lines.count - (hasTrailingSentinel ? 1 : 0), 1)

        var transformations: [LineTransformation] = []

        switch command {
        case .bulletList, .dashList, .numberedList:
            let targetKind: ListKind
            switch command {
            case .bulletList: targetKind = .bullet
            case .dashList: targetKind = .dash
            case .numberedList: targetKind = .numbered
            case .indent, .outdent: return nil
            }
            let activeLines = Array(lines.prefix(transformCount))
            let shouldRemove = !activeLines.isEmpty && activeLines.allSatisfy {
                listPrefix(in: $0 as NSString)?.kind == targetKind
            }

            for (index, line) in lines.enumerated() {
                guard index < transformCount else {
                    transformations.append(.identity(line))
                    continue
                }

                let lineSource = line as NSString
                let existing = listPrefix(in: lineSource)
                let editLocation = existing?.range.location ?? indentationLength(in: lineSource)
                let removedLength = existing?.range.length ?? 0
                let inserted: String

                if shouldRemove {
                    inserted = ""
                } else {
                    inserted = prefixText(for: targetKind, number: index + 1)
                }

                transformations.append(
                    replacing(
                        line,
                        range: NSRange(location: editLocation, length: removedLength),
                        with: inserted
                    )
                )
            }

        case .indent:
            transformations = lines.enumerated().map { index, line in
                guard index < transformCount else { return .identity(line) }
                return replacing(line, range: NSRange(location: 0, length: 0), with: "\t")
            }

        case .outdent:
            transformations = lines.enumerated().map { index, line in
                guard index < transformCount else { return .identity(line) }
                let lineSource = line as NSString
                let removeLength: Int
                if lineSource.length > 0, lineSource.character(at: 0) == 9 {
                    removeLength = 1
                } else {
                    removeLength = min(leadingSpaceCount(in: lineSource), 4)
                }
                return replacing(
                    line,
                    range: NSRange(location: 0, length: removeLength),
                    with: ""
                )
            }
        }

        let replacement = transformations.map(\.text).joined(separator: "\n")
        let localStart = safeSelection.location - selectedLines.location
        let localEnd = localStart + safeSelection.length
        let mappedStart = map(localStart, through: transformations)
        let mappedEnd = map(localEnd, through: transformations)

        return MailTextEdit(
            range: selectedLines,
            replacement: replacement,
            selection: NSRange(
                location: selectedLines.location + mappedStart,
                length: max(mappedEnd - mappedStart, 0)
            )
        )
    }

    static func completeListTrigger(in text: String, selection: NSRange) -> MailTextEdit? {
        guard selection.length == 0 else { return nil }
        let source = text as NSString
        let location = min(max(selection.location, 0), source.length)
        let lineRange = source.lineRange(for: NSRange(location: location, length: 0))
        let rawLine = source.substring(with: lineRange) as NSString
        let lineLength = rawLine.length - (rawLine.hasSuffix("\n") ? 1 : 0)
        guard location == lineRange.location + lineLength else { return nil }

        let indent = indentationLength(in: rawLine)
        guard indent < lineLength else { return nil }
        let markerRange = NSRange(location: indent, length: lineLength - indent)
        let marker = rawLine.substring(with: markerRange)
        var replacementRange = markerRange
        var typedMarker = marker

        if let existing = listPrefix(in: rawLine) {
            let contentStart = NSMaxRange(existing.range)
            guard contentStart < lineLength else { return nil }
            let contentRange = NSRange(location: contentStart, length: lineLength - contentStart)
            typedMarker = rawLine.substring(with: contentRange)
            replacementRange = NSRange(
                location: existing.range.location,
                length: lineLength - existing.range.location
            )
        }

        guard let target = listTrigger(for: typedMarker) else { return nil }
        let replacement = prefixText(for: target.kind, number: target.number)

        let globalRange = NSRange(
            location: lineRange.location + replacementRange.location,
            length: replacementRange.length
        )
        return MailTextEdit(
            range: globalRange,
            replacement: replacement,
            selection: NSRange(location: globalRange.location + (replacement as NSString).length, length: 0)
        )
    }

    static func continueList(in text: String, selection: NSRange) -> MailTextEdit? {
        guard selection.length == 0 else { return nil }
        let source = text as NSString
        let location = min(max(selection.location, 0), source.length)
        let lineRange = source.lineRange(for: NSRange(location: location, length: 0))
        let rawLine = source.substring(with: lineRange)
        let line = rawLine.trimmingCharacters(in: .newlines) as NSString
        guard let prefix = listPrefix(in: line) else { return nil }

        let contentRange = NSRange(
            location: NSMaxRange(prefix.range),
            length: max(line.length - NSMaxRange(prefix.range), 0)
        )
        let content = line.substring(with: contentRange)
        let indent = line.substring(with: NSRange(location: 0, length: prefix.range.location))

        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let globalPrefixRange = NSRange(
                location: lineRange.location + prefix.range.location,
                length: prefix.range.length
            )
            return MailTextEdit(
                range: globalPrefixRange,
                replacement: "",
                selection: NSRange(location: globalPrefixRange.location, length: 0)
            )
        }

        let nextPrefix: String
        switch prefix.kind {
        case .bullet:
            nextPrefix = "• "
        case .dash:
            nextPrefix = "- "
        case .numbered:
            nextPrefix = "\((prefix.number ?? 0) + 1). "
        }

        let insertion = "\n\(indent)\(nextPrefix)"
        return MailTextEdit(
            range: NSRange(location: location, length: 0),
            replacement: insertion,
            selection: NSRange(location: location + (insertion as NSString).length, length: 0)
        )
    }

    static func removeEmptyListPrefix(in text: String, selection: NSRange) -> MailTextEdit? {
        guard selection.length == 0 else { return nil }
        let source = text as NSString
        let location = min(max(selection.location, 0), source.length)
        let lineRange = source.lineRange(for: NSRange(location: location, length: 0))
        let rawLine = source.substring(with: lineRange)
        let line = rawLine.trimmingCharacters(in: .newlines) as NSString
        guard let prefix = listPrefix(in: line) else { return nil }
        guard location == lineRange.location + NSMaxRange(prefix.range) else { return nil }

        let contentRange = NSRange(
            location: NSMaxRange(prefix.range),
            length: max(line.length - NSMaxRange(prefix.range), 0)
        )
        guard line.substring(with: contentRange).isEmpty else { return nil }

        let globalPrefixRange = NSRange(
            location: lineRange.location + prefix.range.location,
            length: prefix.range.length
        )
        return MailTextEdit(
            range: globalPrefixRange,
            replacement: "",
            selection: NSRange(location: globalPrefixRange.location, length: 0)
        )
    }

    static func isInList(_ text: String, selection: NSRange) -> Bool {
        let source = text as NSString
        let location = min(max(selection.location, 0), source.length)
        let lineRange = source.lineRange(for: NSRange(location: location, length: 0))
        let rawLine = source.substring(with: lineRange)
        let line = rawLine.trimmingCharacters(in: .newlines) as NSString
        return listPrefix(in: line) != nil
    }

    static func canPresentSlashMenu(in text: String, selection: NSRange) -> Bool {
        guard selection.length == 0 else { return false }
        let source = text as NSString
        let location = min(max(selection.location, 0), source.length)
        let lineRange = source.lineRange(for: NSRange(location: location, length: 0))
        let rawLine = source.substring(with: lineRange)
            .trimmingCharacters(in: .newlines) as NSString
        guard location == lineRange.location + rawLine.length else { return false }

        let indent = indentationLength(in: rawLine)
        if indent == rawLine.length { return true }
        guard let prefix = listPrefix(in: rawLine) else { return false }
        return NSMaxRange(prefix.range) == rawLine.length
    }

    private enum ListKind: Equatable {
        case bullet
        case dash
        case numbered
    }

    private struct ListTrigger {
        let kind: ListKind
        let number: Int?
    }

    private struct Prefix {
        let kind: ListKind
        let range: NSRange
        let number: Int?
    }

    private struct LineTransformation {
        let text: String
        let oldLength: Int
        let newLength: Int
        let editLocation: Int
        let removedLength: Int
        let insertedLength: Int

        static func identity(_ line: String) -> LineTransformation {
            let length = (line as NSString).length
            return LineTransformation(
                text: line,
                oldLength: length,
                newLength: length,
                editLocation: length,
                removedLength: 0,
                insertedLength: 0
            )
        }

        func map(_ offset: Int) -> Int {
            let safeOffset = min(max(offset, 0), oldLength)
            if safeOffset < editLocation { return safeOffset }
            if safeOffset >= editLocation + removedLength {
                return safeOffset + insertedLength - removedLength
            }
            return editLocation + insertedLength
        }
    }

    private static func replacing(
        _ line: String,
        range: NSRange,
        with replacement: String
    ) -> LineTransformation {
        let mutable = NSMutableString(string: line)
        mutable.replaceCharacters(in: range, with: replacement)
        return LineTransformation(
            text: mutable as String,
            oldLength: (line as NSString).length,
            newLength: mutable.length,
            editLocation: range.location,
            removedLength: range.length,
            insertedLength: (replacement as NSString).length
        )
    }

    private static func map(_ offset: Int, through lines: [LineTransformation]) -> Int {
        var oldCursor = 0
        var newCursor = 0

        for (index, line) in lines.enumerated() {
            let oldLineEnd = oldCursor + line.oldLength
            if offset <= oldLineEnd {
                return newCursor + line.map(offset - oldCursor)
            }

            oldCursor = oldLineEnd
            newCursor += line.newLength

            if index < lines.count - 1 {
                oldCursor += 1
                newCursor += 1
                if offset < oldCursor { return newCursor }
            }
        }

        return newCursor
    }

    private static func listPrefix(in line: NSString) -> Prefix? {
        let indent = indentationLength(in: line)
        guard indent < line.length else { return nil }

        if line.character(at: indent) == 0x2022 {
            let end = indent + 1
            guard end < line.length, isWhitespace(line.character(at: end)) else { return nil }
            return Prefix(
                kind: .bullet,
                range: NSRange(location: indent, length: 2),
                number: nil
            )
        }

        if line.character(at: indent) == 45 {
            let end = indent + 1
            guard end < line.length, isWhitespace(line.character(at: end)) else { return nil }
            return Prefix(
                kind: .dash,
                range: NSRange(location: indent, length: 2),
                number: nil
            )
        }

        var cursor = indent
        while cursor < line.length, isDigit(line.character(at: cursor)) {
            cursor += 1
        }
        guard cursor > indent,
              cursor + 1 < line.length,
              line.character(at: cursor) == 46,
              isWhitespace(line.character(at: cursor + 1)) else { return nil }

        let numberText = line.substring(with: NSRange(location: indent, length: cursor - indent))
        return Prefix(
            kind: .numbered,
            range: NSRange(location: indent, length: cursor - indent + 2),
            number: Int(numberText)
        )
    }

    private static func listTrigger(for marker: String) -> ListTrigger? {
        if marker == "*" || marker == "+" {
            return ListTrigger(kind: .bullet, number: nil)
        }
        if marker == "-" {
            return ListTrigger(kind: .dash, number: nil)
        }

        let source = marker as NSString
        guard source.length >= 2 else { return nil }
        let suffix = source.character(at: source.length - 1)
        guard suffix == 46 || suffix == 41 else { return nil }
        for index in 0..<(source.length - 1) {
            guard isDigit(source.character(at: index)) else { return nil }
        }
        let number = Int(source.substring(to: source.length - 1)) ?? 1
        return ListTrigger(kind: .numbered, number: number)
    }

    private static func prefixText(for kind: ListKind, number: Int?) -> String {
        switch kind {
        case .bullet: "• "
        case .dash: "- "
        case .numbered: "\(number ?? 1). "
        }
    }

    private static func indentationLength(in line: NSString) -> Int {
        var cursor = 0
        while cursor < line.length, isWhitespace(line.character(at: cursor)) {
            cursor += 1
        }
        return cursor
    }

    private static func leadingSpaceCount(in line: NSString) -> Int {
        var cursor = 0
        while cursor < line.length, line.character(at: cursor) == 32 {
            cursor += 1
        }
        return cursor
    }

    private static func isWhitespace(_ character: unichar) -> Bool {
        character == 9 || character == 32
    }

    private static func isDigit(_ character: unichar) -> Bool {
        character >= 48 && character <= 57
    }

    private static func clamped(_ range: NSRange, to length: Int) -> NSRange {
        let location = min(max(range.location, 0), length)
        return NSRange(location: location, length: min(max(range.length, 0), length - location))
    }
}

enum MailDraftSerializer {
    static let inlineImageMarker = "\u{FFFC}"

    static func normalizedBody(from draft: String) -> String {
        var lines = draft
            .components(separatedBy: "\n")
            .map(normalizedLine)
        while lines.first?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            lines.removeFirst()
        }
        while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    static func outgoingText(from draft: String, inlineImages: [InlineDraftImage] = []) -> String {
        var outgoing = normalizedBody(from: draft)
        for image in inlineImages {
            guard let range = outgoing.range(of: inlineImageMarker) else { break }
            outgoing.replaceSubrange(range, with: "[Image: \(image.name)]")
        }
        return outgoing.replacingOccurrences(of: inlineImageMarker, with: "[Image]")
    }

    private static func normalizedLine(_ line: String) -> String {
        var normalized = line.replacingOccurrences(of: "\t", with: "    ")
        while normalized.last == " " {
            normalized.removeLast()
        }
        return normalized
    }
}
