import Foundation

@main
struct SearchTestRunner {
    private static var failures = 0
    private static var checks = 0

    static func main() {
        testCaseAndDiacriticInsensitive()
        testAllGeneralTermsMatch()
        testStructuredFilters()
        testQuotedSubject()
        testRanking()
        testLabelFilter()
        testAttachmentFilename()
        testIndexedSearchMutationLifecycle()
        testRecipientAutocomplete()
        testRecipientReplacement()
        testGmailRecipientDirectory()
        testGmailRecipientMetadataDecode()
        testGmailQuotaDetection()
        testThreadOpeningPolicy()
        testArchiveAdvancePolicy()
        testUndoWindow()
        testSenderBlockNormalization()
        testCommandBackspaceCurrentLine()
        testCommandBackspacePreviousLine()
        testBulletToggle()
        testEmptyListCaretPlacement()
        testDashToggle()
        testListContinuation()
        testDashContinuation()
        testListExit()
        testIndentRoundTrip()
        testMarkdownBulletTriggers()
        testMarkdownNumberTrigger()
        testIndentedMarkdownTrigger()
        testMixedNestedListMarkers()
        testNestedNumberMarkerSwitch()
        testSlashMenuEligibility()
        testOutgoingSerialization()
        testInlineImageFallback()
        testGoogleDesktopCredentialParsing()
        testUnsubscribeHeaderParsing()
        testGmailThreadParsing()
        testGmailSoftWrappedPlainTextParsing()
        testLongPlainTextNormalization()
        testGmailHTMLAndInlineImageParsing()
        testGmailMIMEMessage()

        if failures > 0 {
            print("\(failures) search test(s) failed")
            exit(1)
        }

        print("\(checks) search, editor, and Gmail tests passed")
    }

    private static func testCaseAndDiacriticInsensitive() {
        var thread = MailThread.samples[0]
        thread.sender = "José Alvarez"
        expect(
            MailSearchEngine.search("JOSE", in: [thread]).map(\.thread.id) == [thread.id],
            "case and diacritic folding"
        )
    }

    private static func testAllGeneralTermsMatch() {
        let results = MailSearchEngine.search("project Thursday", in: MailThread.samples)
        expect(results.map(\.thread.id) == ["project-handoff"], "all general terms match")
    }

    private static func testStructuredFilters() {
        let results = MailSearchEngine.search("from:ava is:unread has:attachment", in: MailThread.samples)
        expect(results.map(\.thread.id) == ["project-handoff"], "combined structured filters")
    }

    private static func testQuotedSubject() {
        let results = MailSearchEngine.search("subject:\"Project handoff\"", in: MailThread.samples)
        expect(results.first?.thread.id == "project-handoff", "quoted subject filter")
    }

    private static func testRanking() {
        let subjectMatch = makeThread(
            id: "subject-match",
            subject: "Quarterly forecast",
            preview: "The numbers are ready.",
            body: "The numbers are ready."
        )
        let bodyMatch = makeThread(
            id: "body-match",
            subject: "Planning notes",
            preview: "The quarterly forecast is in the attachment.",
            body: "The quarterly forecast is in the attachment."
        )
        let results = MailSearchEngine.search("forecast", in: [bodyMatch, subjectMatch])
        expect(results.map(\.thread.id) == ["subject-match", "body-match"], "subject ranks above body")
    }

    private static func testLabelFilter() {
        let results = MailSearchEngine.search("label:receipts", in: MailThread.samples)
        expect(results.map(\.thread.id) == ["september-receipt"], "label filter")
    }

    private static func testAttachmentFilename() {
        var thread = makeThread(
            id: "attachment-match",
            subject: "Notes",
            preview: "The file is attached.",
            body: "The file is attached."
        )
        thread.hasAttachment = true
        thread.messages = [
            MailMessage(
                id: "attachment-message",
                sender: "Example Sender",
                recipientLine: "to me",
                body: "The file is attached.",
                timestamp: "Now",
                attachmentNames: ["Q3-forecast.pdf"]
            )
        ]

        let results = MailSearchEngine.search("forecast", in: [thread])
        expect(results.map(\.thread.id) == [thread.id], "attachment filename search")
    }

    private static func testIndexedSearchMutationLifecycle() {
        var first = makeThread(
            id: "indexed-first",
            subject: "Launch plan",
            preview: "Alpha",
            body: "The quarterly forecast is ready."
        )
        let second = makeThread(
            id: "indexed-second",
            subject: "Customer notes",
            preview: "Beta",
            body: "Security review complete."
        )
        var index = MailSearchEngine.Index(threads: [first, second])
        let initial = index.search("orecas").map(\.threadID)

        first.isUnread = true
        first.isStarred = true
        first.labels.insert(.receipts)
        index.updateMetadata(for: first)
        let filtered = index.search("label:receipts is:unread is:starred").map(\.threadID)

        index.remove(threadID: first.id)
        let removed = index.search("forecast").isEmpty

        var inserted = second
        inserted = MailThread(
            id: "indexed-third",
            sender: inserted.sender,
            email: inserted.email,
            subject: "Forecast follow-up",
            preview: inserted.preview,
            displayDate: inserted.displayDate,
            date: inserted.date.addingTimeInterval(60),
            isUnread: false,
            isStarred: false,
            hasAttachment: false,
            folder: .inbox,
            labels: [.inbox],
            messages: inserted.messages
        )
        index.update(inserted)
        let added = index.search("forecast", limit: 1).map(\.threadID)

        expect(
            initial == [first.id] && filtered == [first.id] && removed && added == [inserted.id],
            "indexed search preserves substring, filters, update, remove, and insert"
        )
    }

    private static func testRecipientAutocomplete() {
        var ava = makeThread(
            id: "ava-contact",
            subject: "Planning",
            preview: "Ready",
            body: "Ready"
        )
        ava.sender = "Ava Patel"
        ava.email = "ava@example.com"

        var theo = makeThread(
            id: "theo-contact",
            subject: "Coffee",
            preview: "Tuesday works",
            body: "Tuesday works"
        )
        theo.sender = "Theo Martin"
        theo.email = "theo@example.com"
        theo.folder = .sent
        theo.labels = [.sent]

        let index = RecipientAutocompleteIndex(threads: [ava, theo])
        let nameMatch = index.suggestions(matching: "pat")
        let sentMatch = index.suggestions(matching: "the")
        expect(
            nameMatch.first?.email == "ava@example.com"
                && sentMatch.first?.email == "theo@example.com"
                && sentMatch.first?.wasPreviouslyEmailed == true,
            "recipient autocomplete finds names, addresses, and previous recipients"
        )
    }

    private static func testRecipientReplacement() {
        let suggestion = RecipientSuggestion(
            name: "Ava Patel",
            email: "ava@example.com",
            interactionCount: 3,
            wasPreviouslyEmailed: true,
            lastInteraction: Date()
        )
        let single = RecipientAutocompleteIndex.replacingActiveRecipient(
            in: "av",
            with: suggestion
        )
        let multiple = RecipientAutocompleteIndex.replacingActiveRecipient(
            in: "first@example.com, av",
            with: suggestion
        )
        expect(
            single == "Ava Patel <ava@example.com>"
                && multiple == "first@example.com, Ava Patel <ava@example.com>",
            "Tab completion replaces only the active recipient"
        )
    }

    private static func testGmailRecipientDirectory() {
        let ownEmail = "me@example.com"
        let inbound = GmailMessagePayload(
            id: "inbound",
            threadId: "directory-thread",
            labelIds: ["INBOX"],
            snippet: nil,
            historyId: nil,
            internalDate: "1000",
            payload: GmailMessagePart(
                partId: nil,
                mimeType: "multipart/alternative",
                filename: nil,
                headers: [
                    GmailMessageHeader(name: "From", value: "Avery Quinn <avery@example.com>"),
                    GmailMessageHeader(name: "To", value: "Me <me@example.com>"),
                    GmailMessageHeader(name: "Cc", value: "Team <team@example.org>"),
                    GmailMessageHeader(name: "Reply-To", value: "Avery Replies <reply@example.com>")
                ],
                body: nil,
                parts: nil
            ),
            sizeEstimate: nil
        )
        let sent = GmailMessagePayload(
            id: "sent",
            threadId: "directory-thread",
            labelIds: ["SENT"],
            snippet: nil,
            historyId: nil,
            internalDate: "2000",
            payload: GmailMessagePart(
                partId: nil,
                mimeType: "text/plain",
                filename: nil,
                headers: [
                    GmailMessageHeader(name: "From", value: "Me <me@example.com>"),
                    GmailMessageHeader(name: "To", value: "Avery Quinn <avery@example.com>")
                ],
                body: nil,
                parts: nil
            ),
            sizeEstimate: nil
        )
        var builder = GmailRecipientDirectoryBuilder(accountEmail: ownEmail)
        builder.record(
            GmailThreadPayload(
                id: "directory-thread",
                historyId: nil,
                messages: [inbound, sent]
            )
        )
        let entries = Dictionary(uniqueKeysWithValues: builder.entries.map { ($0.email.lowercased(), $0) })
        let index = RecipientAutocompleteIndex(threads: [], directory: builder.entries)
        let suggestion = index.suggestions(matching: "ave").first

        expect(
            entries[ownEmail] == nil
                && entries["avery@example.com"]?.interactionCount == 2
                && entries["avery@example.com"]?.wasPreviouslyEmailed == true
                && entries["team@example.org"]?.wasPreviouslyEmailed == false
                && entries["reply@example.com"]?.name == "Avery Replies"
                && suggestion?.email == "avery@example.com",
            "Gmail-wide directory aggregates headers and feeds autocomplete"
        )
    }

    private static func testGmailRecipientMetadataDecode() {
        let json = Data(#"""
        {
          "id": "directory-thread",
          "messages": [{
            "id": "directory-message",
            "labelIds": ["INBOX"],
            "internalDate": "1725148800000",
            "payload": {
              "headers": [
                {"name": "From", "value": "New Contact <new@example.com>"},
                {"name": "To", "value": "Me <me@example.com>"}
              ]
            }
          }]
        }
        """#.utf8)

        let payload = try? JSONDecoder().decode(GmailThreadPayload.self, from: json)
        var builder = GmailRecipientDirectoryBuilder(accountEmail: "me@example.com")
        if let payload { builder.record(payload) }
        expect(
            payload?.messages?.first?.threadId == nil
                && builder.entries.map(\.email) == ["new@example.com"],
            "Gmail directory accepts partial metadata responses"
        )
    }

    private static func testGmailQuotaDetection() {
        let quotaError = Data(#"""
        {
          "error": {
            "code": 403,
            "message": "Quota exceeded for quota metric 'Total Query Cost'",
            "status": "RESOURCE_EXHAUSTED",
            "errors": [{"reason": "rateLimitExceeded"}]
          }
        }
        """#.utf8)
        let permissionError = Data(#"""
        {"error":{"code":403,"message":"Insufficient Permission","status":"PERMISSION_DENIED"}}
        """#.utf8)

        expect(
            GmailAPIErrorEnvelope.isQuotaExceeded(in: quotaError)
                && !GmailAPIErrorEnvelope.isQuotaExceeded(in: permissionError),
            "Gmail quota errors are retried without masking permission failures"
        )
    }

    private static func testThreadOpeningPolicy() {
        let untouched = MailThread.samples.first { $0.id == "coffee-next-week" }
        let correspondence = MailThread.samples.first { $0.id == "project-handoff" }
        var latestFromUser = correspondence
        latestFromUser?.messages.append(
            MailMessage(
                id: "handoff-5",
                sender: "You",
                recipientLine: "to Ava Patel",
                body: "One last note.",
                timestamp: "Now"
            )
        )
        let draft = MailThread.samples.first { $0.id == "draft-demo" }

        expect(
            untouched?.shouldOpenReplyComposerByDefault == false
                && untouched?.defaultExpandedMessageID == "coffee-1"
                && correspondence?.shouldOpenReplyComposerByDefault == true
                && correspondence?.defaultExpandedMessageID == "handoff-4"
                && latestFromUser?.defaultExpandedMessageID == "handoff-4"
                && draft?.shouldOpenReplyComposerByDefault == false,
            "thread opening separates untouched mail from active correspondence"
        )
    }

    private static func testArchiveAdvancePolicy() {
        let threads = Array(MailThread.samples.prefix(3))
        expect(
            MailTriagePolicy.nextThreadID(afterRemoving: threads[0].id, from: threads) == threads[1].id
                && MailTriagePolicy.nextThreadID(afterRemoving: threads[1].id, from: threads) == threads[2].id
                && MailTriagePolicy.nextThreadID(afterRemoving: threads[2].id, from: threads) == threads[1].id
                && MailTriagePolicy.nextThreadID(afterRemoving: threads[0].id, from: [threads[0]]) == nil,
            "archive advances through the current message list"
        )
    }

    private static func testUndoWindow() {
        let start = Date(timeIntervalSince1970: 1_000)
        let window = MailUndoWindow(startedAt: start)
        expect(
            window.isActive(at: start.addingTimeInterval(4.999))
                && window.isActive(at: start.addingTimeInterval(5))
                && !window.isActive(at: start.addingTimeInterval(5.001)),
            "archive and send remain undoable for five seconds"
        )
    }

    private static func testSenderBlockNormalization() {
        expect(
            SenderBlockPolicy.normalizedAddress("  Person@Example.COM \n") == "person@example.com",
            "blocked sender matching is case and whitespace insensitive"
        )
    }

    private static func testCommandBackspaceCurrentLine() {
        let original = "Alpha\nBeta"
        let edit = MailLineFormatter.commandBackspace(
            in: original,
            selection: NSRange(location: (original as NSString).length, length: 0)
        )
        let result = applying(edit, to: original)
        expect(result?.text == "Alpha\n" && result?.selection.location == 6, "Command-Backspace clears current line")
    }

    private static func testCommandBackspacePreviousLine() {
        let original = "Alpha\n"
        let edit = MailLineFormatter.commandBackspace(
            in: original,
            selection: NSRange(location: (original as NSString).length, length: 0)
        )
        let result = applying(edit, to: original)
        expect(result?.text == "" && result?.selection.location == 0, "repeated Command-Backspace clears line above")
    }

    private static func testBulletToggle() {
        let original = "One\nTwo"
        let addEdit = MailLineFormatter.apply(
            .bulletList,
            to: original,
            selection: NSRange(location: 0, length: (original as NSString).length)
        )
        guard let added = applying(addEdit, to: original) else {
            expect(false, "bulleted list toggle")
            return
        }
        let removeEdit = MailLineFormatter.apply(
            .bulletList,
            to: added.text,
            selection: NSRange(location: 0, length: (added.text as NSString).length)
        )
        let removed = applying(removeEdit, to: added.text)
        expect(added.text == "• One\n• Two" && removed?.text == original, "bulleted list toggle")
    }

    private static func testEmptyListCaretPlacement() {
        let cases: [(MailEditorCommand, String)] = [
            (.bulletList, "• "),
            (.dashList, "- "),
            (.numberedList, "1. ")
        ]
        let results = cases.compactMap { command, expected -> Bool? in
            let edit = MailLineFormatter.apply(
                command,
                to: "",
                selection: NSRange(location: 0, length: 0)
            )
            guard let result = applying(edit, to: "") else { return nil }
            return result.text == expected
                && result.selection.location == (expected as NSString).length
        }
        expect(results.count == cases.count && results.allSatisfy { $0 }, "empty list puts caret after its marker")
    }

    private static func testDashToggle() {
        let original = "One\nTwo"
        let addEdit = MailLineFormatter.apply(
            .dashList,
            to: original,
            selection: NSRange(location: 0, length: (original as NSString).length)
        )
        guard let added = applying(addEdit, to: original) else {
            expect(false, "dash list toggle")
            return
        }
        let removeEdit = MailLineFormatter.apply(
            .dashList,
            to: added.text,
            selection: NSRange(location: 0, length: (added.text as NSString).length)
        )
        let removed = applying(removeEdit, to: added.text)
        expect(added.text == "- One\n- Two" && removed?.text == original, "dash list toggle")
    }

    private static func testListContinuation() {
        let original = "1. First"
        let edit = MailLineFormatter.continueList(
            in: original,
            selection: NSRange(location: (original as NSString).length, length: 0)
        )
        let result = applying(edit, to: original)
        expect(result?.text == "1. First\n2. ", "Return continues numbered list")
    }

    private static func testDashContinuation() {
        let original = "- First"
        let edit = MailLineFormatter.continueList(
            in: original,
            selection: NSRange(location: (original as NSString).length, length: 0)
        )
        let result = applying(edit, to: original)
        expect(result?.text == "- First\n- ", "Return continues dash list")
    }

    private static func testListExit() {
        let original = "• "
        let edit = MailLineFormatter.continueList(
            in: original,
            selection: NSRange(location: (original as NSString).length, length: 0)
        )
        let result = applying(edit, to: original)
        expect(result?.text == "" && result?.selection.location == 0, "Return exits empty list item")
    }

    private static func testIndentRoundTrip() {
        let original = "• One"
        let indentEdit = MailLineFormatter.apply(
            .indent,
            to: original,
            selection: NSRange(location: (original as NSString).length, length: 0)
        )
        guard let indented = applying(indentEdit, to: original) else {
            expect(false, "indent and outdent")
            return
        }
        let outdentEdit = MailLineFormatter.apply(
            .outdent,
            to: indented.text,
            selection: indented.selection
        )
        let outdented = applying(outdentEdit, to: indented.text)
        expect(indented.text == "\t• One" && outdented?.text == original, "indent and outdent")
    }

    private static func testMarkdownBulletTriggers() {
        let markers = ["*", "-", "+"]
        let results = markers.compactMap { marker -> String? in
            let edit = MailLineFormatter.completeListTrigger(
                in: marker,
                selection: NSRange(location: (marker as NSString).length, length: 0)
            )
            return applying(edit, to: marker)?.text
        }
        expect(results == ["• ", "- ", "• "], "Markdown markers preserve bullet and dash lists")
    }

    private static func testMarkdownNumberTrigger() {
        let markers = ["1.", "3)"]
        let results = markers.compactMap { marker -> String? in
            let edit = MailLineFormatter.completeListTrigger(
                in: marker,
                selection: NSRange(location: (marker as NSString).length, length: 0)
            )
            return applying(edit, to: marker)?.text
        }
        expect(results == ["1. ", "3. "], "number markers start a numbered list")
    }

    private static func testIndentedMarkdownTrigger() {
        let original = "\t-"
        let edit = MailLineFormatter.completeListTrigger(
            in: original,
            selection: NSRange(location: (original as NSString).length, length: 0)
        )
        let result = applying(edit, to: original)
        expect(result?.text == "\t- " && result?.selection.location == 3, "indented dash marker preserves indentation")
    }

    private static func testMixedNestedListMarkers() {
        let original = "• Parent\n\t• -"
        let edit = MailLineFormatter.completeListTrigger(
            in: original,
            selection: NSRange(location: (original as NSString).length, length: 0)
        )
        let result = applying(edit, to: original)
        expect(result?.text == "• Parent\n\t- ", "nested bullet can switch to dash")
    }

    private static func testNestedNumberMarkerSwitch() {
        let original = "• Parent\n\t- Child\n\t- 1."
        let edit = MailLineFormatter.completeListTrigger(
            in: original,
            selection: NSRange(location: (original as NSString).length, length: 0)
        )
        let result = applying(edit, to: original)
        expect(result?.text == "• Parent\n\t- Child\n\t1. ", "nested dash can switch to numbered")
    }

    private static func testSlashMenuEligibility() {
        let eligible = ["", "\t", "• ", "\t- "].allSatisfy { text in
            MailLineFormatter.canPresentSlashMenu(
                in: text,
                selection: NSRange(location: (text as NSString).length, length: 0)
            )
        }
        let ineligible = MailLineFormatter.canPresentSlashMenu(
            in: "Ordinary text",
            selection: NSRange(location: 13, length: 0)
        )
        expect(eligible && !ineligible, "slash menu appears only on an empty list row")
    }

    private static func testOutgoingSerialization() {
        let draft = "\n\t• Parent  \n\t\t- Child\tvalue  \n\t\t1. First\n"
        let outgoing = MailDraftSerializer.outgoingText(from: draft)
        expect(
            outgoing == "    • Parent\n        - Child    value\n        1. First",
            "outgoing list text uses stable spaces and readable markers"
        )
    }

    private static func testInlineImageFallback() {
        let image = InlineDraftImage(
            url: URL(fileURLWithPath: "/tmp/photo.png"),
            name: "photo.png",
            data: Data([0])
        )
        let draft = "Before\n\(MailDraftSerializer.inlineImageMarker)\nAfter"
        let outgoing = MailDraftSerializer.outgoingText(from: draft, inlineImages: [image])
        expect(
            outgoing == "Before\n[Image: photo.png]\nAfter",
            "embedded images have a readable plain-text fallback"
        )
    }

    private static func testGoogleDesktopCredentialParsing() {
        let json = """
        {
          "installed": {
            "client_id": "desktop-client.apps.googleusercontent.com",
            "project_id": "mail-test",
            "auth_uri": "https://accounts.google.com/o/oauth2/auth",
            "token_uri": "https://oauth2.googleapis.com/token",
            "client_secret": "desktop-secret",
            "redirect_uris": ["http://localhost"]
          }
        }
        """
        let configuration = try? GmailOAuthConfiguration(googleCredentialData: Data(json.utf8))
        expect(
            configuration?.clientID == "desktop-client.apps.googleusercontent.com"
                && configuration?.clientSecret == "desktop-secret"
                && configuration?.tokenEndpoint.absoluteString == "https://oauth2.googleapis.com/token",
            "Google Desktop OAuth JSON parses"
        )
    }

    private static func testUnsubscribeHeaderParsing() {
        let oneClickURL = URL(string: "https://news.example.com/unsubscribe?token=abc")!
        expect(
            MailUnsubscribeParser.method(
                listUnsubscribe: "<mailto:leave@example.com>, <\(oneClickURL.absoluteString)>",
                listUnsubscribePost: "List-Unsubscribe=One-Click"
            ) == .oneClick(oneClickURL),
            "one-click unsubscribe prefers the HTTPS action"
        )
        expect(
            MailUnsubscribeParser.method(
                listUnsubscribe: "<https://news.example.com/preferences>",
                listUnsubscribePost: nil
            ) == .web(URL(string: "https://news.example.com/preferences")!),
            "standard unsubscribe falls back to the sender web page"
        )
        expect(
            MailUnsubscribeParser.method(
                listUnsubscribe: "<mailto:leave@example.com?subject=unsubscribe>",
                listUnsubscribePost: nil
            ) == .email(URL(string: "mailto:leave@example.com?subject=unsubscribe")!),
            "mailto unsubscribe creates a draft fallback"
        )
        expect(
            MailUnsubscribeParser.method(
                listUnsubscribe: "<https://127.0.0.1/unsubscribe>",
                listUnsubscribePost: "List-Unsubscribe=One-Click"
            ) == .web(URL(string: "https://127.0.0.1/unsubscribe")!),
            "private-network unsubscribe URLs never receive an automatic POST"
        )
    }

    private static func testGmailThreadParsing() {
        let body = GmailOAuthCoordinator.base64URL(Data("Hello Brady\n\nOn Tuesday, someone wrote:\n> old text".utf8))
        let message = GmailMessagePayload(
            id: "message-1",
            threadId: "thread-1",
            labelIds: ["INBOX", "UNREAD", "STARRED"],
            snippet: "Hello Brady",
            historyId: "42",
            internalDate: "1788361200000",
            payload: GmailMessagePart(
                partId: "",
                mimeType: "text/plain",
                filename: "",
                headers: [
                    GmailMessageHeader(name: "From", value: "Ava Patel <ava@example.com>"),
                    GmailMessageHeader(name: "To", value: "Brady <brady@example.com>"),
                    GmailMessageHeader(name: "Subject", value: "Project handoff"),
                    GmailMessageHeader(name: "Message-ID", value: "<message-1@example.com>")
                ],
                body: GmailMessagePartBody(attachmentId: nil, size: 56, data: body),
                parts: nil
            ),
            sizeEstimate: 500
        )
        let parsed = GmailMessageParser.mailThread(
            from: GmailThreadPayload(id: "thread-1", historyId: "42", messages: [message]),
            accountEmail: "brady@example.com",
            now: Date(timeIntervalSince1970: 1_788_362_000)
        )
        expect(
            parsed?.sender == "Ava Patel"
                && parsed?.email == "ava@example.com"
                && parsed?.subject == "Project handoff"
                && parsed?.folder == .inbox
                && parsed?.isUnread == true
                && parsed?.isStarred == true
                && parsed?.messages.first?.body == "Hello Brady"
                && parsed?.messages.first?.rfcMessageID == "<message-1@example.com>",
            "Gmail thread maps to the native mail model"
        )
    }

    private static func testGmailHTMLAndInlineImageParsing() {
        let html = """
        <div>Open <a href="https://example.com/report">the report</a>.<img src="cid:chart-1"><div><br></div><div><br></div></div><br>
        <div class="gmail_quote gmail_quote_container"><div class="gmail_attr">On Tuesday, Ava wrote:</div><blockquote class="gmail_quote">Old message</blockquote></div>
        """
        let htmlData = GmailOAuthCoordinator.base64URL(Data(html.utf8))
        let imageBytes = Data([0x89, 0x50, 0x4e, 0x47])
        let imageData = GmailOAuthCoordinator.base64URL(imageBytes)
        let message = GmailMessagePayload(
            id: "message-html",
            threadId: "thread-html",
            labelIds: ["INBOX"],
            snippet: "Open the report",
            historyId: "43",
            internalDate: "1788361200000",
            payload: GmailMessagePart(
                partId: "",
                mimeType: "multipart/related",
                filename: "",
                headers: [
                    GmailMessageHeader(name: "From", value: "Ava Patel <ava@example.com>"),
                    GmailMessageHeader(name: "To", value: "Brady <brady@example.com>"),
                    GmailMessageHeader(name: "Subject", value: "HTML report"),
                    GmailMessageHeader(name: "List-Unsubscribe", value: "<https://news.example.com/unsubscribe?token=abc>"),
                    GmailMessageHeader(name: "List-Unsubscribe-Post", value: "List-Unsubscribe=One-Click")
                ],
                body: nil,
                parts: [
                    GmailMessagePart(
                        partId: "0",
                        mimeType: "text/html",
                        filename: "",
                        headers: [],
                        body: GmailMessagePartBody(attachmentId: nil, size: html.utf8.count, data: htmlData),
                        parts: nil
                    ),
                    GmailMessagePart(
                        partId: "1",
                        mimeType: "image/png",
                        filename: "chart.png",
                        headers: [GmailMessageHeader(name: "Content-ID", value: "<chart-1>")],
                        body: GmailMessagePartBody(attachmentId: nil, size: imageBytes.count, data: imageData),
                        parts: nil
                    )
                ]
            ),
            sizeEstimate: 900
        )

        let parsed = GmailMessageParser.mailThread(
            from: GmailThreadPayload(id: "thread-html", historyId: "43", messages: [message]),
            accountEmail: "brady@example.com",
            now: Date(timeIntervalSince1970: 1_788_362_000)
        )
        let parsedHTML = parsed?.messages.first?.htmlBody ?? ""
        expect(
            parsedHTML.contains("href=\"https://example.com/report\"")
                && parsedHTML.contains("src=\"data:image/png;base64,\(imageBytes.base64EncodedString())\"")
                && !parsedHTML.contains("gmail_quote")
                && !parsedHTML.contains("Old message")
                && !parsedHTML.hasSuffix("<br>")
                && parsed?.unsubscribeMethod == .oneClick(URL(string: "https://news.example.com/unsubscribe?token=abc")!),
            "Gmail HTML preserves rich content and removes quoted history"
        )

        let mobileReply = """
        <div dir="auto">Thanks for keeping me posted! Will do. And best of luck with the headcount planning.&nbsp;</div><div dir="auto"><br></div><div dir="auto"><br><div class="gmail_quote gmail_quote_container">Old message</div></div>
        """
        expect(
            MailHTMLNormalizer.currentMessageHTML(mobileReply)
                == "<div dir=\"auto\">Thanks for keeping me posted! Will do. And best of luck with the headcount planning.&nbsp;</div>",
            "Gmail mobile reply removes trailing spacer rows before quoted history"
        )
    }

    private static func testGmailSoftWrappedPlainTextParsing() {
        let text = """
        Still no updates! Feel free to keep pinging me to check back. We are

        getting near the end stages of a larger headcount rollout and approval.



        On Monday, Brady wrote:
        > Old message
        """
        let body = GmailOAuthCoordinator.base64URL(Data(text.utf8))
        let message = GmailMessagePayload(
            id: "message-soft-wrap",
            threadId: "thread-soft-wrap",
            labelIds: ["INBOX"],
            snippet: "Still no updates",
            historyId: "44",
            internalDate: "1788361200000",
            payload: GmailMessagePart(
                partId: "",
                mimeType: "text/plain",
                filename: "",
                headers: [
                    GmailMessageHeader(name: "From", value: "Ava Patel <ava@example.com>"),
                    GmailMessageHeader(name: "To", value: "Brady <brady@example.com>"),
                    GmailMessageHeader(name: "Subject", value: "Compact reply")
                ],
                body: GmailMessagePartBody(attachmentId: nil, size: text.utf8.count, data: body),
                parts: nil
            ),
            sizeEstimate: 500
        )

        let parsed = GmailMessageParser.mailThread(
            from: GmailThreadPayload(id: "thread-soft-wrap", historyId: "44", messages: [message]),
            accountEmail: "brady@example.com",
            now: Date(timeIntervalSince1970: 1_788_362_000)
        )
        expect(
            parsed?.messages.first?.body
                == "Still no updates! Feel free to keep pinging me to check back. We are getting near the end stages of a larger headcount rollout and approval.",
            "Gmail plain text removes soft-wrap gaps and quoted history"
        )
        let cachedMessage = MailMessage(
            id: "cached-soft-wrap",
            sender: "Ava Patel",
            recipientLine: "to me",
            body: text,
            timestamp: "Now"
        )
        expect(
            cachedMessage.compactPreview
                == "Still no updates! Feel free to keep pinging me to check back. We are getting near the end stages of a larger headcount rollout and approval.",
            "cached Gmail previews remove soft-wrap gaps and quoted history"
        )
        var cachedThread = makeThread(
            id: "cached-thread",
            subject: "Compact reply",
            preview: text,
            body: text
        )
        cachedThread.messages = [cachedMessage]
        expect(
            cachedThread.displayPreview == cachedMessage.compactPreview,
            "cached thread rows use the normalized latest-message preview"
        )
    }

    private static func testLongPlainTextNormalization() {
        let longLine = String(repeating: "A", count: 250_000) + "."
        expect(
            MailPlainTextNormalizer.currentMessageText(longLine) == longLine,
            "long email bodies normalize without regex backtracking"
        )
    }

    private static func testGmailMIMEMessage() {
        let image = InlineDraftImage(
            url: URL(fileURLWithPath: "/tmp/chart.png"),
            name: "chart.png",
            data: Data([0x89, 0x50, 0x4e, 0x47]),
            displaySize: .medium
        )
        let draft = GmailOutgoingDraft(
            to: "ava@example.com\r\nBcc: injected@example.com",
            subject: "Project update\r\nX-Test: injected",
            draftBody: "• Result\nRead https://example.com/report\n\t- Detail\n\(MailDraftSerializer.inlineImageMarker)",
            attachments: [],
            inlineImages: [image],
            inReplyTo: "<previous@example.com>",
            references: "<root@example.com>"
        )
        let raw = try? GmailMIMEBuilder.rawMessage(from: draft)
        let decoded = raw.flatMap(decodeBase64URL).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let html = decodedHTMLPart(in: decoded)
        expect(
            decoded.contains("To: ava@example.com Bcc: injected@example.com")
                && !decoded.contains("\r\nBcc: injected@example.com")
                && decoded.contains("multipart/related")
                && decoded.contains("Content-ID: <mail-image-")
                && decoded.contains("References: <root@example.com> <previous@example.com>")
                && html.contains("href=\"https://example.com/report\""),
            "Gmail MIME preserves formatting and blocks header injection"
        )
    }

    private static func decodedHTMLPart(in message: String) -> String {
        guard let headerRange = message.range(of: "Content-Type: text/html; charset=utf-8"),
              let bodyStart = message.range(of: "\r\n\r\n", range: headerRange.upperBound..<message.endIndex) else {
            return ""
        }
        let remainder = message[bodyStart.upperBound...]
        guard let boundaryStart = remainder.range(of: "\r\n--") else { return "" }
        let base64 = remainder[..<boundaryStart.lowerBound]
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
        return Data(base64Encoded: base64)
            .flatMap { String(data: $0, encoding: .utf8) }
            ?? ""
    }

    private static func decodeBase64URL(_ value: String) -> Data? {
        var base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64.append(String(repeating: "=", count: (4 - base64.count % 4) % 4))
        return Data(base64Encoded: base64)
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        checks += 1
        if condition() {
            print("✓ \(name)")
        } else {
            failures += 1
            print("✗ \(name)")
        }
    }

    private static func applying(_ edit: MailTextEdit?, to text: String) -> (text: String, selection: NSRange)? {
        guard let edit else { return nil }
        let mutable = NSMutableString(string: text)
        mutable.replaceCharacters(in: edit.range, with: edit.replacement)
        return (mutable as String, edit.selection)
    }

    private static func makeThread(id: String, subject: String, preview: String, body: String) -> MailThread {
        MailThread(
            id: id,
            sender: "Example Sender",
            email: "sender@example.com",
            subject: subject,
            preview: preview,
            displayDate: "Now",
            date: Date(),
            isUnread: false,
            isStarred: false,
            hasAttachment: false,
            folder: .inbox,
            labels: [],
            messages: [MailMessage(id: "\(id)-message", sender: "Example Sender", recipientLine: "to me", body: body, timestamp: "Now")]
        )
    }
}
